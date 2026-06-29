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

require 'fileutils'
require 'open3'
require 'rbconfig'
require 'shellwords'
require 'tempfile'

require_relative 'add-upstream-git-config'
require_relative 'install-dotfiles'
require_relative 'utilities/core'
require_relative 'utilities/cron'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/git_workspace'
require_relative 'utilities/keybase'
require_relative 'utilities/logging'
require_relative 'utilities/macos'
require_relative 'utilities/path_utils'

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

# Configures the dotfiles repo after it has been cloned by the bootstrap command.
# The new bootstrap workflow (GettingStarted.md) clones the repo before running this script,
# so clone logic is no longer needed here. This function only handles configuration:
# push URL setup, PATH addition, and upstream remote configuration.
# Mirrors _configure_dot_files_repo in the shell version.
def configure_dot_files_repo
  Logging.with_step('Configure dotfiles repo', "Configuring dotfiles repo at '#{EnvVars::DOTFILES_DIR.to_s.cyan}'") do
    git = GitProcessor.new(dir: EnvVars::DOTFILES_DIR)

    # On vanilla OS, bootstrap downloads a tarball (no git yet). Convert to proper git clone.
    unless git.repo?
      if EnvVars.first_install?
        info 'Converting tarball directory to git repository...'

        # Backup current directory content
        backup_dir = EnvVars::DOTFILES_DIR.parent.join("#{EnvVars::DOTFILES_DIR.basename}-tarball-backup")
        backup_dir.rmtree if backup_dir.exist?
        FileUtils.mv(EnvVars::DOTFILES_DIR.to_s, backup_dir.to_s, force: true)

        # Clone proper git repo
        url = "https://github.com/#{EnvVars::GH_USERNAME}/dotfiles"
        branch = EnvVars::DOTFILES_BRANCH
        unless GitProcessor.clone_repo_into(url, EnvVars::DOTFILES_DIR, branch: branch)
          # Restore backup if clone failed
          EnvVars::DOTFILES_DIR.rmtree if EnvVars::DOTFILES_DIR.exist?
          FileUtils.mv(backup_dir.to_s, EnvVars::DOTFILES_DIR.to_s, force: true)
          error "Failed to clone dotfiles repo from '#{url}'"
        end

        # Remove backup if clone succeeded
        FileUtils.rm_rf(backup_dir.to_s)
        success 'Successfully converted tarball to git repository'
      else
        error "Dotfiles directory '#{EnvVars::DOTFILES_DIR.to_s.cyan}' is not a git repo"
      end
    end

    # Configure HTTPS for pull, SSH for push -- only if not already set.
    push_key = 'url.ssh://git@github.com/.pushInsteadOf'
    git.config_set(push_key, 'https://github.com/') if git.config_value(push_key).nil?

    PathUtils.prepend_to_path(EnvVars::DOTFILES_DIR.join('scripts'))

    # Set upstream to EnvVars::UPSTREAM_GH_USERNAME's repo if not already configured.
    unless AddUpstreamGitConfig.run(dir: EnvVars::DOTFILES_DIR, upstream_owner: EnvVars::UPSTREAM_GH_USERNAME)
      record_warning 'Failed to add upstream git config for dotfiles repo'
    end
  end
end

# Parses `brew shellenv` output and merges the exported variables into the
# current process environment. This is the Ruby equivalent of eval_shellenv
# in .shellrc -- it ensures homebrew bins are on PATH for subsequent system()
# calls without forking a shell.

# Installs Homebrew, taps repos, and runs brew bundle.
# Mirrors _install_homebrew in the shell version.
def install_homebrew(curl_opts)
  Logging.with_step('Install Homebrew', "Installing Homebrew into '#{EnvVars::HOMEBREW_PREFIX.to_s.cyan}'") do
    if nil_or_empty?(EnvVars::HOMEBREW_PREFIX.to_s)
      error "'HOMEBREW_PREFIX' env var is not set; something is wrong"
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
        # Build cache-busting headers if CACHE_BUST_HEADERS env var is set
        cache_bust_headers = []
        if EnvVars.cache_bust_headers?
          cache_bust_headers = [
            '-H', 'Cache-Control: no-cache, no-store, must-revalidate',
            '-H', 'Pragma: no-cache',
            '-H', 'Expires: 0'
          ]
        end

        # Append timestamp query param to bust GitHub's CDN cache
        timestamp = Time.now.to_i
        install_url = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh?#{timestamp}"

        cmd = ['curl'] + cache_bust_headers + curl_opts + ['-fsSL', install_url, '-o', install_script.path]
        unless system(*cmd)
          error 'Failed to download Homebrew installation script'
        end

        unless system({ 'NONINTERACTIVE' => '1' }, 'bash', install_script.path)
          error 'Homebrew installation failed'
        end
      ensure
        install_script.unlink rescue nil
      end

      success 'Successfully installed Homebrew'
    else
      info 'Homebrew already installed -- skipping.'
    end

    # Ensure homebrew env vars are set for this process session.
    MacOS.load_brew_shellenv(brew_bin)

    # Trust custom taps and install formulae/casks from Brewfile.
    # On first install: base section only + background full install.
    # On pre-configured: full Brewfile synchronously.
    MacOS.install_homebrew_bundle(brew_bin)
  end
end

# Clones the Keybase home repo (private configs).
# Mirrors _clone_home_repo in the shell version.
def clone_home_repo
  Logging.with_step('Clone home repo', "Cloning 'home' repo") do
    if nil_or_empty?(EnvVars::KEYBASE_HOME_REPO_NAME)
      info "Skipping -- 'EnvVars::KEYBASE_HOME_REPO_NAME' env var is not set"
      return
    end

    url = Keybase.build_repo_url(EnvVars::KEYBASE_HOME_REPO_NAME)

    if GitProcessor.repo?(EnvVars::HOME)
      # Pre-configured machine: pull latest changes instead of cloning
      info 'Home repo already exists -- pulling latest changes'
      git = GitProcessor.new(dir: EnvVars::HOME)
      _out, _err, status = git.pull(rebase: true)
      if status.success?
        success 'Successfully updated home repo'
      else
        record_warning 'Failed to pull home repo -- continuing with existing backup files'
      end
    elsif GitProcessor.clone_repo_into(url, EnvVars::HOME)
      # Vanilla OS: clone succeeded
      PathUtils.set_ssh_folder_permissions

      etc_hosts_src = EnvVars::PERSONAL_CONFIGS_DIR.join('etc.hosts')
      if etc_hosts_src.file?
        system('sudo', 'cp', etc_hosts_src.to_s, '/etc/hosts')
      end
    else
      record_error 'Failed to clone home repo'
    end
  end
end

# Clones the Keybase profiles repo (browser profiles).
# Mirrors _clone_profiles_repo in the shell version.
def clone_profiles_repo
  Logging.with_step('Clone profiles repo', "Cloning 'profiles' repo") do
    if nil_or_empty?(EnvVars::KEYBASE_PROFILES_REPO_NAME) || nil_or_empty?(EnvVars::PERSONAL_PROFILES_DIR.to_s)
      info "Skipping -- 'EnvVars::KEYBASE_PROFILES_REPO_NAME' or 'PERSONAL_PROFILES_DIR' not set"
      return
    end

    url = Keybase.build_repo_url(EnvVars::KEYBASE_PROFILES_REPO_NAME)
    unless GitProcessor.clone_repo_into(url, EnvVars::PERSONAL_PROFILES_DIR)
      record_error 'Failed to clone profiles repo'
    end
  end
end

# Sets Homebrew's zsh as the default login shell.
# macOS ships with /bin/zsh but Homebrew's zsh is newer and managed independently.
# chsh requires the target shell to be listed in /etc/shells -- adds it if absent.
# Without this, iTerm2's "Login shell" setting stays on /bin/zsh even when
# /opt/homebrew/bin/zsh is on PATH, and $SHELL stays /bin/zsh after a fresh install.
# Mirrors _set_default_shell in the shell version.
def set_default_shell
  Logging.with_step('Set default shell', 'Setting default shell to Homebrew zsh') do
    brew_zsh = EnvVars::HOMEBREW_PREFIX.join('bin', 'zsh')
    unless brew_zsh.executable?
      record_error("Homebrew zsh not found at '#{brew_zsh.to_s.cyan}' -- skipping default shell change.")
      return
    end

    # Check the user's configured default shell (not the current $SHELL env var).
    # $SHELL reflects the current terminal session; dscl shows what chsh configured.
    configured_shell, = Open3.capture3('dscl', '.', '-read', EnvVars::HOME.to_s, 'UserShell')
    configured_shell = configured_shell.strip.split(':').last&.strip || ''

    brew_zsh_str = brew_zsh.to_s
    if configured_shell == brew_zsh_str
      info "Default shell is already configured as '#{brew_zsh_str.cyan}' -- skipping."
      return
    end

    # /etc/shells must list the shell before chsh will accept it.
    etc_shells_path = PathUtils::ROOT.join('etc', 'shells').expand_path
    etc_shells = etc_shells_path.readlines.map(&:chomp)
    if etc_shells.include?(brew_zsh_str)
      info "'#{brew_zsh_str.cyan}' already in '#{etc_shells_path.to_s.cyan}' -- skipping."
    else
      info "Adding '#{brew_zsh_str.cyan}' to '#{etc_shells_path.to_s.cyan}'"
      # Use Open3.popen3 to safely write to stdin and discard stdout
      Open3.popen3('sudo', 'tee', '-a', etc_shells_path.to_s) do |stdin, stdout, stderr, wait_thr|
        stdin.puts(brew_zsh_str)
        stdin.close
        stdout.read # Discard stdout (tee echoes to stdout + file)
        wait_thr.value
      end
    end

    if system('chsh', '-s', brew_zsh_str)
      success "Default shell changed to '#{brew_zsh_str.cyan}'."
    else
      record_warning "Failed to change default shell to '#{brew_zsh_str.cyan}'. You may need to run 'chsh -s #{brew_zsh_str}' manually after installation completes."
    end
  end
end

# ---------------------------------------------------------------------------
# Main

# Set the cron backup path so cron_backup_file in cron.rb can read it via ENV.
ENV['_DOTFILES_CRON_BACKUP_FILE'] = EnvVars.cron_backup_file.to_s

# at_exit hooks run in LIFO order, but we use a single consolidated block to
# ensure correct execution order: resume softwareupdate → print summary → notification
# (matching shell EXIT trap + cleanup ordering). Cron suspend/resume is handled
# by with_cron_suspended wrapper below.
start_time = nil

at_exit do
  # Resume softwareupdate schedule
  MacOS.resume_softwareupdate_schedule

  # Print summary (if start_time was set)
  print_script_summary(start_time) if start_time

  # Notification runs last -- after print_script_summary has printed the
  # collected issues so the user sees them in the terminal before the popup.
  errors = Logging.send(:step_errors)
  warnings = Logging.send(:step_warnings)
  parts = []
  parts << "#{errors.length} error(s): #{errors.join('; ')}" unless nil_or_empty?(errors)
  parts << "#{warnings.length} warning(s): #{warnings.join('; ')}" unless nil_or_empty?(warnings)

  if nil_or_empty?(parts)
    MacOS.notify('Fresh install completed successfully.', '✅ Fresh Install Done')
  else
    MacOS.notify("Install done -- #{parts.join(' | ')}", '⚠️ Fresh Install')
  end
end

# Wrap entire execution in with_cron_suspended to ensure cron is suspended
# before any work begins and automatically resumed on exit (clean or error).
Cron.with_cron_suspended do
  begin
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

  # Prompt for sudo once here; keep_sudo_alive starts via suspend_softwareupdate_schedule.
  # suspend_softwareupdate_schedule also disables auto-updates while we work.
  system('sudo', '-v')
  MacOS.suspend_softwareupdate_schedule

  MacOS.approve_fingerprint_sudo

  MacOS.ensure_filevault_is_on

  MacOS.install_xcode_command_line_tools

  PathUtils.set_ssh_folder_permissions

  Logging.section_header 'Creating directories defined by various env vars'
  PathUtils.ensure_directories_exist([
    EnvVars::ANTIDOTE_HOME,
    EnvVars::DOTFILES_DIR,
    EnvVars::PROJECTS_BASE_DIR,
    EnvVars::PERSONAL_BIN_DIR,
    EnvVars::PERSONAL_CONFIGS_DIR,
    EnvVars::PERSONAL_PROFILES_DIR,
    EnvVars::XDG_CACHE_HOME,
    EnvVars::XDG_CONFIG_HOME,
    EnvVars::XDG_DATA_HOME,
    EnvVars::XDG_STATE_HOME
  ])

  configure_dot_files_repo

  # Ensure dotfiles/scripts is on PATH regardless of whether the repo was just
  # cloned or was already present.
  PathUtils.prepend_to_path(EnvVars::DOTFILES_DIR.join('scripts'))

  Logging.with_step('install-dotfiles', 'Running install-dotfiles') do
    record_error 'install-dotfiles encountered errors' unless InstallDotfiles.run
  end

  # ~/.gitconfig is now symlinked -- core.sshCommand is in effect.
  # Unset GIT_SSH_COMMAND so it no longer overrides core.sshCommand.
  ENV.delete('GIT_SSH_COMMAND')

  # Reload homebrew env and install.
  install_homebrew(curl_opts)

  set_default_shell

  # Unshallow the dotfiles repo if it was cloned with --depth=1 on FIRST_INSTALL.
  # Other repos get the user action notification below, but dotfiles should always
  # have full history available for development/maintenance. Do this before reftable
  # migration so we migrate the complete repository in one pass.
  if EnvVars.first_install?
    Logging.with_step('Unshallow dotfiles repo', 'Pulling full history for dotfiles') do
      git = GitProcessor.new(dir: EnvVars::DOTFILES_DIR)
      _out, _err, status = git.run_alias('pull-unshallow')
      if status.success?
        success 'Successfully unshallowed dotfiles repo'
      else
        record_warning "Failed to unshallow dotfiles repo -- run manually: cd '#{EnvVars::DOTFILES_DIR.to_s.cyan}' && git pull-unshallow"
      end
    end
  end

  # Migrate repos cloned before Homebrew's git (2.45+) was on PATH. The system
  # git on vanilla macOS ignores -c init.defaultRefFormat=reftable and does not
  # support 'git refs migrate', so clone_repo_into's migration call was a no-op
  # for those early clones. Now that Homebrew's git is available, migrate them.
  # This runs after unshallow so the complete repository is migrated in one pass.
  Logging.with_step('Migrate repos to reftable', 'Migrating repos to reftable format') do
    GitProcessor.new(dir: EnvVars::DOTFILES_DIR).migrate_to_reftable
  end

  # Keybase repos (home + profiles).
  unless nil_or_empty?(EnvVars::KEYBASE_USERNAME)
    section_header 'Cloning Keybase repos'

    Logging.with_step('Keybase login') do
      if Keybase.ensure_logged_in
        clone_home_repo
        clone_profiles_repo
      else
        record_error 'Keybase login failed -- skipping Keybase repo cloning'
      end
    end
  else
    info "Skipping Keybase repos -- 'EnvVars::KEYBASE_USERNAME' is not set"
  end

  # Remove stale SSH known_hosts backup if present.
  old_known_hosts = EnvVars::HOME.join('.ssh', 'known_hosts.old')
  old_known_hosts.delete if old_known_hosts.file?

  # Restore macOS preferences.
  Logging.with_step('Restore preferences', 'Restore preferences') do
    osx_defaults = EnvVars::DOTFILES_DIR.join('scripts', 'osx-defaults.rb')
    if osx_defaults.file?
      system(RUBY_BIN, osx_defaults.to_s, '-s')
      success 'Successfully baselined preferences'
    else
      record_error "osx-defaults.rb not found at '#{osx_defaults}' -- baseline preferences manually"
    end

    capture_prefs = EnvVars::DOTFILES_DIR.join('scripts', 'capture-prefs.rb')
    if capture_prefs.file?
      # On pre-configured machines, refresh backup before import if stale
      unless EnvVars.first_install?
        info 'Pre-configured machine detected -- refreshing preferences backup first'
        # Must use subprocess instead of CapturePrefs.run(operation: 'export'):
        # capture-prefs.rb has at_exit hooks that must fire immediately after
        # the export completes (resume softwareupdate schedule), not at the end
        # of fresh-install. Subprocess isolation ensures independent lifecycle.
        if system(RUBY_BIN, capture_prefs.to_s, '-e')
          success 'Successfully refreshed preferences backup'
          # Commit using smart_commit (amends if ahead of remote, creates new if not)
          # capture-prefs.rb -e already staged the files, so just commit
          # This updates the backup's git timestamp so import validation passes
          if GitProcessor.repo?(EnvVars::HOME)
            timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
            git = GitProcessor.new(dir: EnvVars::HOME)
            if git.smart_commit("Preferences backup: #{timestamp}")
              success 'Committed preferences backup'
            else
              record_warning 'Failed to commit backup -- timestamp check may fail'
            end
          else
            record_warning 'HOME is not a git repo -- skipping commit, timestamp check may fail'
          end
        else
          record_warning 'Failed to refresh backup -- will attempt import with existing backup'
        end
      end

      # Must use subprocess instead of CapturePrefs.run(operation: 'import'):
      # capture-prefs.rb has at_exit hooks (resume softwareupdate, restart apps)
      # that must fire immediately after import completes, not at fresh-install
      # exit. Multiple invocations (export above, import here) need independent
      # cleanup lifecycles. Subprocess isolation ensures this.
      system(RUBY_BIN, capture_prefs.to_s, '-i')
      success 'Successfully restored preferences from backup'
    else
      record_error "capture-prefs.rb not found at '#{capture_prefs}' -- import preferences manually"
    end

    # Open Sol.app if installed and not already running.
    sol_app = Pathname.new('/Applications/Sol.app')
    if sol_app.directory? &&
       !system('pgrep', '-x', 'Sol', out: File::NULL, err: File::NULL)
      system('open', '-a', sol_app.to_s, out: File::NULL, err: File::NULL)
    end
  end

  # Recreate zsh completions cache.
  Logging.with_step('Recreate zsh completions', 'Recreate zsh completions') do
    zcompdump = EnvVars::XDG_CACHE_HOME.join('zcompdump')
    PathUtils.glob_pathnames(Pathname.new("#{zcompdump}*")) { |f| f.rmtree if f.exist? }
    system(
      'zsh', '-c',
      "autoload -Uz compinit && compinit -C -d '#{zcompdump}'",
      out: File::NULL, err: File::NULL
    ) || true  # Ignore failures - zsh completions are non-critical
  end

  # Setup cron jobs.
  Logging.with_step('Setup cron jobs', 'Setup cron jobs') do
    # Remove the backup before recron so the at_exit resume_cron no-op on clean exit.
    # recron calls restore_cron(crontab.txt), not the backup file.
    backup_pn = EnvVars.cron_backup_file
    backup_pn.delete if backup_pn.file?
    begin
      Cron.recron
    rescue StandardError => e
      record_error "Failed to set up cron jobs: #{e.message} -- set up manually"
    end
  end

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
  current_section = 'Setup dir env'
  GitWorkspace.setup_dev_environment

  # Remind user to unshallow remaining repos cloned with --depth=1 on FIRST_INSTALL
  # (dotfiles repo is already unshallowed above; this covers home/profiles/other repos)
  if EnvVars.first_install?
    Logging.user_action "Remaining repositories were cloned shallow (--depth=1) to save time. Run '#{'all pull-unshallow'.yellow}' to pull full history (dotfiles already unshallowed)."
  end

  success '** Finished auto installation process **'
  rescue StandardError => e
    # Unhandled exception during main execution.
    # at_exit hooks will still run (softwareupdate resume, summary, notification).
    # with_cron_suspended will automatically resume cron on exit.
    # Print error details before at_exit hooks fire.
    msg = "Installation failed with unhandled exception: #{e.message}"
    # Add first backtrace line for context
    msg += "\n  at #{e.backtrace.first}" if e.backtrace&.any?
    Logging.error msg
    # Exit non-zero to signal failure
    exit 1
  end
end
