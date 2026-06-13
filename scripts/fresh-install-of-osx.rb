#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: <anywhere; advisable in the PATH>
#
# Idempotent macOS fresh-install and re-configuration script.
# Works on a vanilla macOS and on a pre-configured machine without errors.
#
# Usage: fresh-install-of-osx.rb
#
# TODO: Need to figure out scriptable commands for:
# 1. Auto-adjust Brightness
# 2. Brightness on battery
# 3. Keyboard brightness

$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'cron'
require 'env_vars'
require 'fileutils'
require 'git_processor'
require 'keybase'
require 'logging'
require 'macos'
require 'open3'
require 'path_utils'
require 'rbconfig'
require 'repos'
require 'shellwords'
require 'tempfile'

include Logging

# ---------------------------------------------------------------------------
# Constants

SCRIPTS_DIR = Pathname.new(__FILE__).dirname.freeze
UTILITIES_DIR = SCRIPTS_DIR.join('utilities').freeze
RUBY_BIN = RbConfig.ruby.freeze

# ---------------------------------------------------------------------------
# Bootstrap helpers

# Sets DNS to 1.1.1.1 if on Jio ISP (GitHub may otherwise not resolve).
# Mirrors _setup_jio_dns in the shell version.
def setup_jio_dns
  org, = Open3.capture3('curl', '-fsS', 'https://ipinfo.io/org')
  org = org.strip
  return unless org.downcase.include?('jio')

  info 'Setting DNS for Wi-Fi from Jio ISP'
  unless system('networksetup', '-setdnsservers', 'Wi-Fi', '1.1.1.1')
    warn 'Failed to set DNS for Wi-Fi'
  end
end

# Downloads ~/.shellrc from GitHub on a first install so it is available for
# the user's future interactive shell sessions. No sourcing needed in Ruby --
# shell utility functions are provided by the utility modules in this repo.
# Mirrors _download_and_source_shellrc in the shell version.
def download_shellrc(curl_opts)
  shellrc = EnvVars::HOME.join('.shellrc')
  unless EnvVars.first_install?
    info "Skipping downloading '#{shellrc.to_s.cyan}' -- not a first install"
    return
  end

  url = "https://raw.githubusercontent.com/#{EnvVars::GH_USERNAME}/dotfiles/refs/heads/#{EnvVars::DOTFILES_BRANCH}/files/--HOME--/.shellrc"
  info "Downloading '#{shellrc.to_s.cyan}' for future shell sessions"
  cmd = ['curl'] + curl_opts + ['-fsSL', url, '-o', shellrc.to_s]
  unless system(*cmd)
    warn "Failed to download '#{shellrc.to_s.cyan}' -- shell sessions may be incomplete until dotfiles are installed"
    return
  end
  success "Downloaded '#{shellrc.to_s.cyan}'"
end

# Enables Touch ID for sudo in terminal shells by uncommenting auth in the
# PAM sudo_local template. Mirrors _approve_fingerprint_sudo in the shell version.
def approve_fingerprint_sudo
  step_start
  section_header 'Setting up Touch ID for sudo access in terminal shells'

  # AppleBiometricSensor = T1/T2 chip (Intel); AppleBiometricServices = Apple Silicon.
  sensor_out, = Open3.capture3('ioreg', '-c', 'AppleBiometricSensor')
  sensor = sensor_out.include?('AppleBiometricSensor')
  services_out, = Open3.capture3('ioreg', '-c', 'AppleBiometricServices')
  services = services_out.include?('AppleBiometricServices')
  unless sensor || services
    info 'Touch ID hardware not detected -- skipping configuration.'
    step_end
    return
  end

  template_file_pn = Pathname.new('/etc/pam.d/sudo_local.template')
  unless template_file_pn.file?
    warn "Template file '#{template_file_pn}' not found -- skipping."
    step_end
    return
  end

  target_file_pn = Pathname.new('/etc/pam.d/sudo_local')
  if target_file_pn.file?
    info "'#{target_file_pn.to_s.cyan}' already present -- skipping."
  else
    content = template_file_pn.read.gsub(/^#auth/, 'auth')
    tmp = Tempfile.new('sudo_local')
    tmp.write(content)
    tmp.close
    result = system('sudo', 'cp', tmp.path, target_file_pn.to_s)
    tmp.unlink
    if result
      success "Created '#{target_file_pn.to_s.cyan}'"
    else
      record_error "Failed to create '#{target_file_pn.to_s.cyan}'"
    end
  end
  step_end
end

# Verifies FileVault disk encryption is active. Aborts if not.
# Mirrors _ensure_filevault_is_on in the shell version.
def ensure_filevault_is_on
  step_start
  section_header 'Verifying FileVault status'
  fv_out, = Open3.capture3('fdesetup', 'isactive')
  unless fv_out.strip == 'true'
    error 'FileVault is not turned on. Please encrypt your hard disk!'
    # error raises RuntimeError; at_exit cleanup hooks still run.
  end
  step_end
end

# Installs Xcode Command Line Tools via non-interactive softwareupdate.
# Mirrors _install_xcode_command_line_tools in the shell version.
def install_xcode_command_line_tools
  current_section = 'Install Xcode Command Line Tools'
  step_start
  section_header 'Installing Xcode command-line tools'

  software_update_marker_file = Pathname.new('/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress')
  if system('xcode-select', '-p', out: File::NULL, err: File::NULL)
    info 'Xcode command-line tools already present -- skipping.'
    # Idempotency cleanup: remove the in-progress sentinel unconditionally.
    software_update_marker_file.delete if software_update_marker_file.exist?
    step_end
    return
  end

  software_update_marker_file.write('')
  unless system('sudo', 'softwareupdate', '-ia', '--agree-to-license', '--force')
    record_warning 'softwareupdate encountered errors during Xcode CLT install'
  end
  software_update_marker_file.delete if software_update_marker_file.exist?

  unless system('xcode-select', '-p', out: File::NULL, err: File::NULL)
    error "Couldn't install Xcode command-line tools; aborting"
  end
  success 'Successfully installed Xcode command-line tools'
  step_end
end

# Resets permissions on SSH key files so git does not complain.
# Mirrors set_ssh_folder_permissions in .shellrc.
def set_ssh_folder_permissions
  ssh_configs_dir = EnvVars::HOME.join('.ssh')
  return unless ssh_configs_dir.directory?

  FileUtils.chmod(0o700, ssh_configs_dir)
  PathUtils.glob_pathnames(ssh_configs_dir.join('*')) do |f|
    FileUtils.chmod(0o600, f) if f.file?
  end
  debug "SSH folder permissions set for '#{ssh_configs_dir}'"
end

# Creates all directories referenced by environment variables as a
# pre-emptive safety step. Mirrors _ensure_directories_exist.
def ensure_directories_exist
  step_start
  section_header 'Creating directories defined by various env vars'
  [
    EnvVars::ANTIDOTE_HOME, EnvVars::DOTFILES_DIR, EnvVars::PROJECTS_BASE_DIR,
    EnvVars::PERSONAL_BIN_DIR, EnvVars::PERSONAL_CONFIGS_DIR, EnvVars::PERSONAL_PROFILES_DIR,
    EnvVars::XDG_CACHE_HOME, EnvVars::XDG_CONFIG_HOME, EnvVars::XDG_DATA_HOME, EnvVars::XDG_STATE_HOME
  ].each do |dir|
    next if dir.to_s.empty?

    dir.mkpath
    debug "Ensured directory exists: '#{dir.to_s.cyan}'"
  end
  step_end
end

# Clones a git repo at +url+ into +dest+ (shallow, single branch).
# Returns true on success, false if the clone fails.
# No-ops (returns true) if +dest+ is already a git repo.
# Mirrors clone_repo_into in .shellrc.
def clone_repo_into(url, dest, branch: nil)
  if GitProcessor.repo?(dest)
    info "Skipping clone -- '#{dest.to_s.cyan}' is already a git repo"
    return true
  end

  args = %w[git clone --depth=1]
  args += ['--branch', branch] if branch && !branch.empty?
  args += [url, dest.to_s]
  info "Cloning '#{url}' → '#{dest.to_s.cyan}'"
  system(*args)
end

# Clones the dotfiles repo and configures push-over-SSH.
# Mirrors _clone_dot_files_repo in the shell version.
def clone_dot_files_repo
  current_section = 'Clone dotfiles repo'
  step_start
  section_header "Installing dotfiles into '#{EnvVars::DOTFILES_DIR.to_s.cyan}'"

  git = GitProcessor.new(dir: EnvVars::DOTFILES_DIR)
  if git.repo?
    info "Skipping clone -- '#{EnvVars::DOTFILES_DIR.to_s.cyan}' is already a git repo"
    step_end
    return
  end

  # Delete the auto-generated .zshrc so it can be replaced by the one in the repo.
  zshrc = EnvVars::ZDOTDIR.join('.zshrc')
  zshrc.rmtree if zshrc.exist?

  # Clone over HTTPS since SSH keys are not present yet on a vanilla OS.
  url = "https://github.com/#{EnvVars::GH_USERNAME}/dotfiles"
  unless clone_repo_into(url, EnvVars::DOTFILES_DIR, branch: EnvVars::DOTFILES_BRANCH)
    error 'Failed to clone dotfiles repo'
    return
  end

  # Configure HTTPS for pull, SSH for push -- only if not already set.
  push_key = 'url.ssh://git@github.com/.pushInsteadOf'
  if git.config_value(push_key).nil?
    system('git', '-C', EnvVars::DOTFILES_DIR.to_s, 'config', push_key, 'https://github.com/')
  end

  prepend_to_path(EnvVars::DOTFILES_DIR.join('scripts'))

  # Set upstream to EnvVars::UPSTREAM_GH_USERNAME's repo if not already configured.
  add_upstream_script = EnvVars::DOTFILES_DIR.join('scripts', 'add-upstream-git-config.rb')
  if add_upstream_script.file?
    unless system(RUBY_BIN, add_upstream_script.to_s, '-d', EnvVars::DOTFILES_DIR.to_s, '-u', EnvVars::UPSTREAM_GH_USERNAME)
      record_warning 'Failed to add upstream git config for dotfiles repo'
    end
  end

  step_end
end

# Parses `brew shellenv` output and merges the exported variables into the
# current process environment. This is the Ruby equivalent of eval_shellenv
# in .shellrc -- it ensures homebrew bins are on PATH for subsequent system()
# calls without forking a shell.
def load_brew_shellenv(brew_bin)
  return unless brew_bin.executable?

  brew_env_out, = Open3.capture3(brew_bin.to_s, 'shellenv')
  brew_env_out.each_line do |line|
    # Parse lines of the form: export KEY="value"
    next unless (m = line.match(/^export (\w+)="([^"]*)"$/))

    ENV[m[1]] = m[2]
  end
  debug "Loaded brew shellenv from '#{brew_bin.to_s}'"
end

# Prepends +dir+ to ENV['PATH'] if it is a directory and not already present.
# Mirrors append_to_path_if_dir_exists in .shellrc (prepend is safer for homebrew).
def prepend_to_path(dir)
  dir_pn = dir.is_a?(Pathname) ? dir : Pathname.new(dir)
  return unless dir_pn.directory?
  dir_str = dir_pn.to_s
  return if ENV.fetch('PATH', '').split(':').include?(dir_str)

  ENV['PATH'] = "#{dir_str}:#{ENV.fetch('PATH', '')}"
  debug "Prepended '#{dir_str}' to PATH"
end

# Returns the brewfile content trimmed to the base section for EnvVars.first_install?.
# Strips lines at and after the first non-comment line containing 'EnvVars.first_install?',
# matching the shell sed truncation in _install_homebrew.
def first_install_brewfile_content
  brewfile = EnvVars::XDG_CONFIG_HOME.join('homebrew', 'Brewfile')
  lines = brewfile.readlines
  cutoff = lines.index { |l| l !~ /^#/ && l.include?('EnvVars.first_install?') }
  (cutoff ? lines[0...cutoff] : lines).join
end

# Installs Homebrew, taps repos, and runs brew bundle.
# Mirrors _install_homebrew in the shell version.
def install_homebrew(curl_opts)
  current_section = 'Install Homebrew'
  step_start
  section_header "Installing Homebrew into '#{EnvVars::HOMEBREW_PREFIX.to_s.cyan}'"

  if EnvVars::HOMEBREW_PREFIX.to_s.empty?
    error "'HOMEBREW_PREFIX' env var is not set; something is wrong"
    return
  end

  brew_bin = EnvVars::HOMEBREW_PREFIX.join('bin', 'brew')

  unless brew_bin.executable?
    # Prepare directories for homebrew installation.
    system('sudo', 'mkdir', '-p',
           EnvVars::HOMEBREW_PREFIX.join('tmp').to_s, EnvVars::HOMEBREW_PREFIX.join('repository').to_s,
           EnvVars::HOMEBREW_PREFIX.join('plugins').to_s, EnvVars::HOMEBREW_PREFIX.join('bin').to_s)
    system('sudo', 'chown', '-fR', "#{EnvVars::USER}:admin", EnvVars::HOMEBREW_PREFIX.to_s)
    FileUtils.chmod('u+w', EnvVars::HOMEBREW_PREFIX.to_s) rescue nil

    install_script = Tempfile.new(['brew-install', '.sh'])
    begin
      install_url = 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
      cmd = ['curl'] + curl_opts + ['-fsSL', install_url, '-o', install_script.path]
      unless system(*cmd)
        install_script.unlink
        error 'Failed to download Homebrew installation script'
        return
      end

      unless system({ 'NONINTERACTIVE' => '1' }, 'bash', install_script.path)
        error 'Homebrew installation failed'
        return
      end
    ensure
      install_script.unlink rescue nil
    end

    success 'Successfully installed Homebrew'
  else
    info 'Homebrew already installed -- skipping.'
  end

  # Ensure homebrew env vars are set for this process session.
  load_brew_shellenv(brew_bin)

  # Trust all custom taps defined in the Brewfile before running brew bundle.
  # This ensures taps are trusted before any formulae/casks from those taps are
  # installed, which is required if HOMEBREW_REQUIRE_TAP_TRUST is enforced.
  # Use 'brew bundle list --taps' to extract tap names from Brewfile, skip homebrew/* taps.
  if brew_bin.executable?
    brewfile_path = EnvVars::HOME.join('Brewfile')
    if brewfile_path.file?
      # Use brew bundle list --taps to get tap names, filter out homebrew/* taps
      tap_output, = Open3.capture2(brew_bin.to_s, 'bundle', 'list', '--taps', "--file=#{brewfile_path}")
      custom_taps = tap_output.lines.map(&:strip).reject { |tap| tap.start_with?('homebrew/') }

      if custom_taps.any?
        info "Trusting custom taps: #{custom_taps.join(', ').yellow}"
        system(brew_bin.to_s, 'trust', '--tap', '-q', *custom_taps) || true  # Don't fail if trust fails
      end
    end
  end

  # Run brew bundle. On EnvVars.first_install?, only install the base section of the Brewfile
  # to keep the initial run fast; fork the full install in the background.
  brew_bundle_exit = 0
  if EnvVars.first_install?
    content = first_install_brewfile_content
    # brew bundle --file=- reads the Brewfile from stdin.
    check_ok = system(brew_bin.to_s, 'bundle', 'check', out: File::NULL, err: File::NULL)
    unless check_ok
      IO.popen([brew_bin.to_s, 'bundle', '--file=-'], 'r+') do |io|
        io.write(content)
        io.close_write
        print io.read
      end
      brew_bundle_exit = $?.exitstatus || 0
    end
  else
    check_ok = system(brew_bin.to_s, 'bundle', 'check', out: File::NULL, err: File::NULL)
    unless check_ok
      system(brew_bin.to_s, 'bundle') || (brew_bundle_exit = 1)
    end
  end

  if brew_bundle_exit == 0
    success 'Successfully installed cmd-line and GUI apps using Homebrew'
  else
    record_warning 'Homebrew bundle install encountered errors; continuing...'
  end

  if EnvVars.first_install?
    # Fork the full Brewfile install in the background so optional/heavy packages
    # install without blocking the rest of this run. EnvVars.first_install? is unset in
    # the child so brew bundle processes the complete Brewfile.
    full_bundle_log = EnvVars::HOME.join('brew-bundle-full-install.log')
    pid = Process.spawn(
      ENV.to_h.merge('EnvVars.first_install?' => ''),
      brew_bin.to_s, 'bundle',
      out: [full_bundle_log.to_s, 'a'], err: [full_bundle_log.to_s, 'a']
    )
    Process.detach(pid)
    info "Full Brewfile install running in background (log: '#{full_bundle_log.to_s.cyan}')"
  end

  # Reload PATH and env from the now-installed homebrew.
  load_brew_shellenv(brew_bin)
  prepend_to_path(EnvVars::DOTFILES_DIR.join('scripts'))

  step_end
end

# Clones the Keybase home repo (private configs).
# Mirrors _clone_home_repo in the shell version.
def clone_home_repo
  current_section = 'Clone home repo'
  step_start
  section_header2 "Cloning 'home' repo"

  if nil_or_empty?(EnvVars::KEYBASE_HOME_REPO_NAME)
    info "Skipping -- 'EnvVars::KEYBASE_HOME_REPO_NAME' env var is not set"
    step_end
    return
  end

  url = Keybase.build_repo_url(EnvVars::KEYBASE_HOME_REPO_NAME)
  if clone_repo_into(url, EnvVars::HOME)
    set_ssh_folder_permissions

    etc_hosts_src = EnvVars::PERSONAL_CONFIGS_DIR.join('etc.hosts')
    if etc_hosts_src.file?
      system('sudo', 'cp', etc_hosts_src.to_s, '/etc/hosts')
    end
  else
    record_error 'Failed to clone home repo'
  end

  step_end
end

# Clones the Keybase profiles repo (browser profiles).
# Mirrors _clone_profiles_repo in the shell version.
def clone_profiles_repo
  current_section = 'Clone profiles repo'
  step_start
  section_header2 "Cloning 'profiles' repo"

  if nil_or_empty?(EnvVars::KEYBASE_PROFILES_REPO_NAME) || EnvVars::PERSONAL_PROFILES_DIR.to_s.empty?
    info "Skipping -- 'EnvVars::KEYBASE_PROFILES_REPO_NAME' or 'PERSONAL_PROFILES_DIR' not set"
    step_end
    return
  end

  url = Keybase.build_repo_url(EnvVars::KEYBASE_PROFILES_REPO_NAME)
  unless clone_repo_into(url, EnvVars::PERSONAL_PROFILES_DIR)
    record_error 'Failed to clone profiles repo'
  end

  step_end
end

# Sets Homebrew's zsh as the default login shell.
# macOS ships with /bin/zsh but Homebrew's zsh is newer and managed independently.
# chsh requires the target shell to be listed in /etc/shells -- adds it if absent.
# Without this, iTerm2's "Login shell" setting stays on /bin/zsh even when
# /opt/homebrew/bin/zsh is on PATH, and $SHELL stays /bin/zsh after a fresh install.
# Mirrors _set_default_shell in the shell version.
def set_default_shell
  current_section = 'Set default shell'
  step_start
  section_header 'Setting default shell to Homebrew zsh'

  brew_zsh = EnvVars::HOMEBREW_PREFIX.join('bin', 'zsh')
  unless brew_zsh.executable?
    record_error("Homebrew zsh not found at '#{brew_zsh.to_s.cyan}' -- skipping default shell change.")
    step_end
    return
  end

  # /etc/shells must list the shell before chsh will accept it.
  etc_shells_path = Pathname.new('/etc/shells')
  etc_shells = etc_shells_path.readlines.map(&:chomp)
  brew_zsh_str = brew_zsh.to_s
  if etc_shells.include?(brew_zsh_str)
    info "'#{brew_zsh_str.cyan}' already in /etc/shells -- skipping."
  else
    info "Adding '#{brew_zsh_str.cyan}' to /etc/shells"
    system('sudo', 'tee', '-a', '/etc/shells', in: StringIO.new("#{brew_zsh_str}\n"),
                                               out: File::NULL)
  end

  current_shell = EnvVars::SHELL
  if current_shell == brew_zsh_str
    info "Default shell is already '#{brew_zsh_str.cyan}' -- skipping."
  else
    system('chsh', '-s', brew_zsh_str)
    success "Default shell changed to '#{brew_zsh_str.cyan}'."
  end

  step_end
end

# ---------------------------------------------------------------------------
# Main

# Set the cron backup path before registering at_exit hooks or calling
# Cron.suspend_cron so cron_backup_file in cron.rb can read it via ENV.
ENV['_DOTFILES_CRON_BACKUP_FILE'] = EnvVars.cron_backup_file.to_s

# at_exit hooks run in LIFO order. Register in reverse so resume_cron fires
# first, then resume_softwareupdate_schedule, then the summary, and finally
# the notification -- matching the shell EXIT trap + cleanup ordering.
start_time = nil

at_exit do
  # Notification runs last -- after print_script_summary has printed the
  # collected issues so the user sees them in the terminal before the popup.
  errors = Logging.send(:step_errors)
  warnings = Logging.send(:step_warnings)
  parts = []
  parts << "#{errors.length} error(s): #{errors.join('; ')}" unless errors.empty?
  parts << "#{warnings.length} warning(s): #{warnings.join('; ')}" unless warnings.empty?

  if parts.empty?
    MacOS.notify('Fresh install completed successfully.', '✅ Fresh Install Done')
  else
    MacOS.notify("Install done -- #{parts.join(' | ')}", '⚠️ Fresh Install')
  end
end

at_exit { print_script_summary(start_time) }

at_exit { MacOS.resume_softwareupdate_schedule }

# Resume cron last (registered first = runs last in LIFO, but cron backup file
# cleanup is coupled with recron below -- this at_exit is a safety net for error
# exits only; on a normal run recron clears the backup file itself).
at_exit { Cron.resume_cron }

# Suspend cron after at_exit hooks are registered so any failure during
# suspend is still caught by the resume_cron at_exit safety net.
Cron.suspend_cron

increment_script_depth
start_time = print_script_start

# EnvVars.first_install?: on a vanilla OS ~/.gitconfig is not yet symlinked, so
# core.sshCommand is absent. Export GIT_SSH_COMMAND for this session so the
# connect timeout is honoured for all git operations. Unset it after
# install-dotfiles.rb symlinks ~/.gitconfig into place.
ENV['GIT_SSH_COMMAND'] = 'ssh -o ConnectTimeout=20' if EnvVars.first_install?

# ~/.curlrc is not yet symlinked on a vanilla OS, so its defaults are absent.
# Build resilient curl flags explicitly for all bootstrap curl calls.
# --retry-all-errors is intentionally omitted -- it causes the terminal to close.
curl_opts = if EnvVars.first_install? || !EnvVars::HOME.join('.curlrc').file?
    %w[--retry 5 --retry-delay 10 --retry-max-time 120 --max-time 150 --connect-timeout 30 --retry-connrefused]
  else
    []
  end

# ZDOTDIR must be set before any zsh is invoked downstream.
ENV['ZDOTDIR'] ||= EnvVars::ZDOTDIR.to_s

setup_jio_dns

section_header 'Downloading ~/.shellrc'
download_shellrc(curl_opts)

# Prompt for sudo once here; keep_sudo_alive starts via suspend_softwareupdate_schedule.
# suspend_softwareupdate_schedule also disables auto-updates while we work.
system('sudo', '-v')
MacOS.suspend_softwareupdate_schedule

approve_fingerprint_sudo

ensure_filevault_is_on

install_xcode_command_line_tools

set_ssh_folder_permissions

ensure_directories_exist

clone_dot_files_repo

# Ensure dotfiles/scripts is on PATH regardless of whether the repo was just
# cloned or was already present.
prepend_to_path(EnvVars::DOTFILES_DIR.join('scripts'))

section_header 'Running install-dotfiles'
current_section = 'install-dotfiles'
install_dotfiles = EnvVars::DOTFILES_DIR.join('scripts', 'install-dotfiles.rb')
if install_dotfiles.file?
  unless system(RUBY_BIN, install_dotfiles.to_s)
    record_error 'install-dotfiles.rb encountered errors'
  end
else
  record_error "install-dotfiles.rb not found at '#{install_dotfiles}'"
end

# ~/.gitconfig is now symlinked -- core.sshCommand is in effect.
# Unset GIT_SSH_COMMAND so it no longer overrides core.sshCommand.
ENV.delete('GIT_SSH_COMMAND')

# On a vanilla OS, .shellrc was curl-downloaded before the dotfiles repo was
# cloned. install-dotfiles.rb (with EnvVars.first_install? set) adopts any pre-existing
# ~/.shellrc into the repo, which can overwrite the committed version with the
# stale GitHub-cached curl content. Restore the committed version if it differs,
# so that subsequent operations use the correct up-to-date .shellrc.
if EnvVars.first_install?
  shellrc_rel = 'files/--HOME--/.shellrc'
  diff_out, = Open3.capture3('git', '-C', EnvVars::DOTFILES_DIR.to_s, 'diff', '--', shellrc_rel)
  unless diff_out.strip.empty?
    system('git', '-C', EnvVars::DOTFILES_DIR.to_s, 'checkout', '--', shellrc_rel)
    debug 'Restored committed .shellrc (curl-downloaded copy was stale)'
  end
end

# Reload homebrew env and install.
install_homebrew(curl_opts)

set_default_shell

# Migrate repos cloned before Homebrew's git (2.45+) was on PATH. The system
# git on vanilla macOS ignores -c init.defaultRefFormat=reftable and does not
# support 'git refs migrate', so clone_repo_into's migration call was a no-op
# for those early clones. Now that Homebrew's git is available, migrate them.
current_section = 'Migrate repos to reftable'
step_start
section_header 'Migrating repos to reftable format'
GitProcessor.migrate_to_reftable(folder: EnvVars::DOTFILES_DIR)
step_end

# Keybase repos (home + profiles).
unless nil_or_empty?(EnvVars::KEYBASE_USERNAME)
  section_header 'Cloning Keybase repos'

  step_start
  current_section = 'Keybase login'
  if Keybase.ensure_logged_in
    clone_home_repo
    clone_profiles_repo
  else
    record_error 'Keybase login failed -- skipping Keybase repo cloning'
  end
  step_end
else
  info "Skipping Keybase repos -- 'EnvVars::KEYBASE_USERNAME' is not set"
end

# Remove stale SSH known_hosts backup if present.
old_known_hosts = EnvVars::HOME.join('.ssh', 'known_hosts.old')
old_known_hosts.delete if old_known_hosts.file?

# Restore macOS preferences.
current_section = 'Restore preferences'
step_start
section_header 'Restore preferences'

osx_defaults = EnvVars::DOTFILES_DIR.join('scripts', 'osx-defaults.rb')
if osx_defaults.file?
  system(RUBY_BIN, osx_defaults.to_s, '-s')
  success 'Successfully baselined preferences'
else
  record_error "osx-defaults.rb not found at '#{osx_defaults}' -- baseline preferences manually"
end

capture_prefs = EnvVars::DOTFILES_DIR.join('scripts', 'capture-prefs.rb')
if capture_prefs.file?
  system(RUBY_BIN, capture_prefs.to_s, '-i')
  success 'Successfully restored preferences from backup'
else
  record_error "capture-prefs.rb not found at '#{capture_prefs}' -- import preferences manually"
end

# Open Sol.app if installed and not already running.
sol_app = Pathname.new('/Applications/Sol.app')
if sol_app.directory? &&
   !system('pgrep', '-x', 'Sol', out: File::NULL, err: File::NULL)
  system('open', '-a', sol_app.to_s)
end
step_end

# Recreate zsh completions cache.
step_start
section_header 'Recreate zsh completions'
zcompdump = EnvVars::XDG_CACHE_HOME.join('zcompdump')
PathUtils.glob_pathnames(Pathname.new("#{zcompdump}*")) { |f| f.rmtree if f.exist? }
system(
  'zsh', '-c',
  "autoload -Uz compinit && compinit -C -d '#{zcompdump}'",
  out: File::NULL, err: File::NULL
)
step_end

# Setup cron jobs.
current_section = 'Setup cron jobs'
step_start
section_header 'Setup cron jobs'
# Remove the backup before recron so the at_exit resume_cron no-op on clean exit.
# recron calls restore_cron(crontab.txt), not the backup file.
backup_pn = EnvVars.cron_backup_file
backup_pn.delete if backup_pn.file?
begin
  Cron.recron
rescue StandardError => e
  record_error "Failed to set up cron jobs: #{e.message} -- set up manually"
end
step_end

# Background tasks: long-running and safe to detach (HACKTAG: same reasoning
# as the shell &| pattern -- these can take minutes on EnvVars.first_install?).
bg_log = EnvVars::HOME.join('fresh-install-background.log')
info "Background tasks logging to '#{bg_log.to_s.cyan}'"

current_section = 'Resurrect tracked repos'
resurrect_script = EnvVars::DOTFILES_DIR.join('scripts', 'resurrect-repositories.rb')
if resurrect_script.file?
  # HACKTAG: Can take a long time on EnvVars.first_install?, so running in background to be non-blocking
  pid = Process.spawn(RUBY_BIN, resurrect_script.to_s, out: [bg_log.to_s, 'a'], err: [bg_log.to_s, 'a'])
  Process.detach(pid)
  info 'Resurrecting tracked repos in background'
else
  record_error 'resurrect-repositories.rb not found -- run manually'
end

# Note: This is also called from within 'resurrect_tracked_repos', but this redundant call
# at least processes the git repos in the ${HOME}, ${PERSONAL_PROFILES_DIR} and the ${DOTFILES_DIR}
# folders as a "first pass" while that background job is still running
current_section = 'Allow all direnv configs'
Repos.allow_all_direnv_configs

# Note: This is also called from within 'resurrect_tracked_repos', but this redundant call
# at least processes the git repos in the ${HOME}, ${PERSONAL_PROFILES_DIR} and the ${DOTFILES_DIR}
# folders as a "first pass" while that background job is still running
current_section = 'Install mise versions'
Repos.install_mise_versions

success '** Finished auto installation process **'
