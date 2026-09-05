#!/usr/bin/env ruby
# encoding: utf-8
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
require_relative 'utilities/command_utils'
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

RUBY_BIN = RbConfig.ruby.freeze

# ---------------------------------------------------------------------------
# Bootstrap helpers

# Sets DNS to 1.1.1.1 if on Jio ISP (GitHub may otherwise not resolve).
def _setup_jio_dns
  org = CommandUtils.query('curl', '-fsS', 'https://ipinfo.io/org')
  return unless org.downcase.include?('jio')

  info 'Setting DNS for Wi-Fi from Jio ISP'
  return if CommandUtils.run_silent('networksetup', '-setdnsservers', 'Wi-Fi', '1.1.1.2', '9.9.9.9')

  warn 'Failed to set DNS for Wi-Fi'
end

# Downloads .shellrc from GitHub when needed and sources it.
def _download_and_source_shellrc(curl_opts, cache_bust_headers)
  puts "==> Ensuring '~/.shellrc' is current"

  shellrc_path = EnvVars::HOME.join('.shellrc')
  shellrc_path_str = shellrc_path.to_s
  repo_shellrc = EnvVars::DOTFILES_DIR.join('files/--HOME--/.shellrc')

  # Determine if download is needed
  reason = nil
  if EnvVars.first_install?
    # Vanilla OS: always download
    reason = 'first install'
  elsif !shellrc_path.file?
    # Pre-configured but .shellrc missing (deleted or corrupted symlink)
    reason = '.shellrc missing'
  elsif !EnvVars::DOTFILES_DIR.directory?
    # Pre-configured but DOTFILES_DIR missing (partial fresh-install or deleted repo)
    # Cannot verify staleness without repo - re-download to ensure current version
    reason = 'dotfiles repo missing'
  elsif repo_shellrc.file? && repo_shellrc.mtime > shellrc_path.mtime
    # Pre-configured: repo file is newer than existing .shellrc (git pull updated repo)
    # Downloads from GitHub to ensure fresh copy (not using potentially stale local repo file)
    reason = 'local repo file is newer'
  end

  if reason
    puts "==> Downloading .shellrc from GitHub (#{reason})"
    # Cache-busting: append timestamp to URL and add no-cache headers to ensure we bypass
    # GitHub's CDN cache and intermediate proxies to get the latest version.
    timestamp = Time.now.to_i
    url = "https://raw.githubusercontent.com/#{EnvVars::GH_USERNAME}/dotfiles/refs/heads/#{EnvVars::DOTFILES_BRANCH}/files/--HOME--/.shellrc?#{timestamp}"

    cmd = ['curl'] + cache_bust_headers + curl_opts + ['-fsSL', url, '-o', shellrc_path_str]
    Logging.error 'Failed to download .shellrc' unless system(*cmd)
  end

  # Universal validation (both first-install and pre-configured)
  # Validate: check that file is non-empty and contains the re-source guard
  # function (basic smoke test for successful download vs truncated/corrupted response).
  # Use explicit UTF-8 encoding to avoid "invalid byte sequence in US-ASCII".
  unless shellrc_path.file? && shellrc_path.size.positive? && shellrc_path.read(encoding: 'UTF-8').include?('is_shellrc_sourced')
    warn 'ERROR: .shellrc appears corrupted or empty'
    exit 1
  end

  puts "==> Verified '#{shellrc_path_str}'"

  # Running .shellrc in a zsh subprocess doesn't make its functions/env vars available
  # to this Ruby process (the subprocess's environment is discarded on exit) -- the
  # rest of this script uses the Ruby utility modules instead. This run validates the
  # file parses correctly and warms any on-disk caches .shellrc creates (e.g. Homebrew
  # shellenv, starship init), which benefits the next real interactive shell.
  system({ 'DEBUG' => 'true' }, 'zsh', '-c', "source #{shellrc_path_str.shellescape}")
  Logging.success "Successfully sourced '#{shellrc_path_str.cyan}'"
end

# Validates that curl-downloaded .shellrc matches the repo version.
def _validate_shellrc_matches_repo
  return unless EnvVars.first_install?
  return unless EnvVars::DOTFILES_DIR.directory?

  shellrc_home = EnvVars::HOME.join('.shellrc')
  shellrc_repo = EnvVars::DOTFILES_DIR.join('files/--HOME--/.shellrc')

  return unless shellrc_home.file? && shellrc_repo.file?

  # Use /usr/bin/diff to compare files (exit 0 = identical, exit 1 = differ)
  _stdout, _stderr, status = Open3.capture3('/usr/bin/diff', '-q', shellrc_home.to_s, shellrc_repo.to_s)

  return if status.success? # Files match, validation passed

  # Files differ -- GitHub cache is stale
  warn 'ERROR: [FIRST_INSTALL] The curl-downloaded ~/.shellrc differs from the repo version.'
  warn 'This indicates GitHub\'s raw.githubusercontent.com cache is stale.'
  warn ''
  warn 'Diff output:'
  diff_output, = Open3.capture3('/usr/bin/diff', '-u', shellrc_home.to_s, shellrc_repo.to_s)
  warn diff_output.lines.first(50).join
  warn ''
  warn 'Wait 5-10 minutes for the cache to refresh, then re-run this script.'
  warn 'Alternatively, manually copy the repo version:'
  warn "  cp '#{shellrc_repo}' '#{shellrc_home}'"
  warn "  source '#{shellrc_home}'"
  warn "  #{$PROGRAM_NAME} #{ARGV.join(' ')}"
  exit 1
end

# Restores .shellrc from git after install-dotfiles.rb moves the downloaded version.
# :reek:FeatureEnvy -- Multiple sequential git operations on the same repo (intentional)
def _restore_shellrc_after_install_dotfiles
  return unless EnvVars.first_install?

  git = GitProcessor.new(dir: EnvVars::DOTFILES_DIR)
  shellrc_relative = 'files/--HOME--/.shellrc'

  # Check if install-dotfiles.rb modified .shellrc in the repo
  _stdout, _stderr, status = git.run_alias('diff', '--quiet', '--', shellrc_relative)
  return if status.success? # No changes, nothing to restore

  # Restore committed version
  git.run_alias('checkout', '--', shellrc_relative)

  # Re-run the restored version through zsh to validate it parses correctly
  # (same rationale as _download_and_source_shellrc above).
  shellrc_path = EnvVars::HOME.join('.shellrc')
  system({ 'DEBUG' => 'true' }, 'zsh', '-c', "source #{shellrc_path.to_s.shellescape}")
end

# Clones the dotfiles repo (if not already present) and configures push-over-SSH,
# PATH, and the upstream remote.
# :reek:NilCheck -- config_value returns nil when the key is unset (standard git config idiom)
def _clone_dot_files_repo
  dotfiles_dir = EnvVars::DOTFILES_DIR
  Logging.with_step('Clone dotfiles repo', "Installing dotfiles into '#{dotfiles_dir.to_s.cyan}'") do
    if GitProcessor.repo?(dotfiles_dir)
      info "Skipping cloning the dotfiles repo since '#{dotfiles_dir.to_s.cyan}' already exists and is a git repo"
    else
      # Delete the auto-generated .zshrc since that needs to be replaced by the one in the DOTFILES_DIR repo.
      zshrc = EnvVars::ZDOTDIR.join('.zshrc')
      zshrc.rmtree if zshrc.exist?

      # Note: Cloning with https since the ssh keys will not be present at this time.
      url = "https://github.com/#{EnvVars::GH_USERNAME}/dotfiles"
      if GitProcessor.clone_repo_into(url, dotfiles_dir, branch: EnvVars::DOTFILES_BRANCH)
        # Use the https protocol for pull, but use ssh/git for push (only configure if not already set).
        git = GitProcessor.new(dir: dotfiles_dir)
        push_key = 'url.ssh://git@github.com/.pushInsteadOf'
        git.config_set(push_key, 'https://github.com/') if git.config_value(push_key).nil?

        PathUtils.prepend_to_path(dotfiles_dir.join('scripts'))
      else
        error 'Failed to clone dotfiles repo'
      end
    end

    # Setup the dotfiles repo's upstream if GH_USERNAME differs from UPSTREAM_GH_USERNAME.
    # This runs regardless of whether the repo was just cloned or already existed.
    if EnvVars::GH_USERNAME != EnvVars::UPSTREAM_GH_USERNAME
      upstream_ok = AddUpstreamGitConfig.run(dir: dotfiles_dir, upstream_owner: EnvVars::UPSTREAM_GH_USERNAME)
      record_warning 'Failed to add upstream git config for dotfiles repo' unless upstream_ok
    end
  end
end

# Installs Homebrew, taps repos, and runs brew bundle.
def _install_homebrew(curl_opts)
  homebrew_prefix = EnvVars::HOMEBREW_PREFIX
  homebrew_prefix_str = homebrew_prefix.to_s
  Logging.with_step('Install Homebrew', "Installing Homebrew into '#{homebrew_prefix_str.cyan}'") do
    error "'HOMEBREW_PREFIX' env var is not set; something is wrong" if nil_or_empty?(homebrew_prefix_str)

    brew_bin = homebrew_prefix.join('bin', 'brew')

    if brew_bin.executable?
      info 'Homebrew already installed -- skipping.'
    else
      # Prepare directories for homebrew installation.
      system('sudo', 'mkdir', '-p',
             homebrew_prefix.join('tmp').to_s, homebrew_prefix.join('repository').to_s,
             homebrew_prefix.join('plugins').to_s, homebrew_prefix.join('bin').to_s)
      system('sudo', 'chown', '-fR', "#{EnvVars::USER}:admin", homebrew_prefix_str)
      begin
        FileUtils.chmod('u+w', homebrew_prefix_str)
      rescue StandardError
        nil
      end

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
        Logging.error 'Failed to download Homebrew installation script' unless system(*cmd)

        Logging.error 'Homebrew installation failed' unless system({ 'NONINTERACTIVE' => '1' }, 'bash', install_script.path)
      ensure
        begin
          install_script.unlink
        rescue StandardError
          nil
        end
      end

      success 'Successfully installed Homebrew'
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
def _clone_home_repo
  Logging.with_step('Clone home repo', "Cloning 'home' repo") do
    if nil_or_empty?(EnvVars::KEYBASE_HOME_REPO_NAME)
      info "Skipping -- 'EnvVars::KEYBASE_HOME_REPO_NAME' env var is not set"
      return
    end

    url = Keybase.build_repo_url(EnvVars::KEYBASE_HOME_REPO_NAME)

    if GitProcessor.repo?(EnvVars::HOME)
      # Pre-configured machine: pull latest changes to get fresh backup files.
      # GitProcessor#pull delegates to the 'pull-safe' git alias (with-retry hang
      # protection + a clean-working-tree guard), consistent with every other
      # repo-sync path in this script.
      info 'Home repo already exists -- pulling latest changes'
      git = GitProcessor.new(dir: EnvVars::HOME)
      _stdout, _stderr, status = git.pull
      if status.success?
        success 'Successfully updated home repo'
      else
        record_warning 'Failed to pull home repo -- continuing with existing backup files'
      end
    elsif GitProcessor.clone_repo_into(url, EnvVars::HOME)
      # Vanilla OS: clone succeeded
      PathUtils.set_ssh_folder_permissions

      etc_hosts_src = EnvVars::PERSONAL_CONFIGS_DIR.join('etc.hosts')
      system('sudo', 'cp', etc_hosts_src.to_s, '/etc/hosts') if etc_hosts_src.file?
    else
      record_error 'Failed to clone home repo'
    end
  end
end

# Clones the Keybase profiles repo (browser profiles).
def _clone_profiles_repo
  Logging.with_step('Clone profiles repo', "Cloning 'profiles' repo") do
    if nil_or_empty?(EnvVars::KEYBASE_PROFILES_REPO_NAME) || nil_or_empty?(EnvVars::PERSONAL_PROFILES_DIR.to_s)
      info "Skipping -- 'EnvVars::KEYBASE_PROFILES_REPO_NAME' or 'PERSONAL_PROFILES_DIR' not set"
      return
    end

    url = Keybase.build_repo_url(EnvVars::KEYBASE_PROFILES_REPO_NAME)
    record_error 'Failed to clone profiles repo' unless GitProcessor.clone_repo_into(url, EnvVars::PERSONAL_PROFILES_DIR)
  end
end

# Refreshes the preferences backup (export + commit) on a pre-configured machine
# before importing, so the git-timestamp check in capture-prefs.rb -i passes.
def _refresh_preferences_backup(capture_prefs)
  info 'Pre-configured machine detected -- refreshing preferences backup first'
  # Must use subprocess instead of CapturePrefs.run(operation: 'export'):
  # capture-prefs.rb has at_exit hooks that must fire immediately after
  # the export completes (resume softwareupdate schedule), not at the end
  # of fresh-install. Subprocess isolation ensures independent lifecycle.
  unless system(RUBY_BIN, capture_prefs.to_s, '-e')
    record_warning 'Failed to refresh backup -- will attempt import with existing backup'
    return
  end
  success 'Successfully refreshed preferences backup'

  # Commit using smart_commit (amends if ahead of remote, creates new if not).
  # capture-prefs.rb -e already staged the files, so just commit -- this updates
  # the backup's git timestamp so the import validation in capture-prefs.rb passes.
  unless GitProcessor.repo?(EnvVars::HOME)
    record_warning 'HOME is not a git repo -- skipping commit, timestamp check may fail'
    return
  end

  git = GitProcessor.new(dir: EnvVars::HOME)
  if git.smart_commit("Preferences backup: #{Core.current_timestamp}")
    success 'Committed preferences backup'
  else
    record_warning 'Failed to commit backup -- timestamp check may fail'
  end
end

# Sets Homebrew's zsh as the default login shell.
# macOS ships with /bin/zsh but Homebrew's zsh is newer and managed independently.
# chsh requires the target shell to be listed in /etc/shells -- adds it if absent.
# Without this, iTerm2's "Login shell" setting stays on /bin/zsh even when
# /opt/homebrew/bin/zsh is on PATH, and $SHELL stays /bin/zsh after a fresh install.
def _set_default_shell
  Logging.with_step('Set default shell', 'Setting default shell to Homebrew zsh') do
    brew_zsh = EnvVars::HOMEBREW_PREFIX.join('bin', 'zsh')
    unless brew_zsh.executable?
      record_error("Homebrew zsh not found at '#{brew_zsh.to_s.cyan}' -- skipping default shell change.")
      return
    end

    # Check the user's configured default shell (not the current $SHELL env var).
    # $SHELL reflects the current terminal session; dscl shows what chsh configured.
    configured_shell = CommandUtils.query('dscl', '.', '-read', EnvVars::HOME.to_s, 'UserShell')
    configured_shell = configured_shell.split(':').last&.strip || ''

    brew_zsh_str = brew_zsh.to_s
    brew_zsh_cyan = brew_zsh_str.cyan
    if configured_shell == brew_zsh_str
      info "Default shell is already configured as '#{brew_zsh_cyan}' -- skipping."
      return
    end

    # /etc/shells must list the shell before chsh will accept it.
    # Use explicit UTF-8 encoding to avoid "invalid byte sequence in US-ASCII".
    etc_shells_path = Core::ROOT.join('etc', 'shells').expand_path
    etc_shells_path_str = etc_shells_path.to_s
    etc_shells = Core.read_lines_utf8(etc_shells_path).map(&:chomp)
    if etc_shells.include?(brew_zsh_str)
      info "'#{brew_zsh_cyan}' already in '#{etc_shells_path_str.cyan}' -- skipping."
    else
      info "Adding '#{brew_zsh_cyan}' to '#{etc_shells_path_str.cyan}'"
      # Use Open3.popen3 to safely write to stdin and discard stdout
      Open3.popen3('sudo', 'tee', '-a', etc_shells_path_str) do |stdin, stdout, _stderr, wait_thr|
        stdin.puts(brew_zsh_str)
        stdin.close
        stdout.read # Discard stdout (tee echoes to stdout + file)
        wait_thr.value
      end
    end

    if CommandUtils.run_interactive('chsh', '-s', brew_zsh_str)
      success "Default shell changed to '#{brew_zsh_cyan}'."
    else
      record_warning "Failed to change default shell to '#{brew_zsh_cyan}'. You may need to run 'chsh -s #{brew_zsh_str}' manually after installation completes."
    end
  end
end

# ---------------------------------------------------------------------------
# Main

# Set the cron backup path so cron_backup_file in cron.rb can read it via ENV.
ENV['_DOTFILES_CRON_BACKUP_FILE'] = EnvVars.cron_backup_file.to_s

# at_exit hooks run in LIFO order, but we use a single consolidated block to
# ensure correct execution order: resume softwareupdate, then print summary, then notification
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
  errors = Logging.step_errors
  warnings = Logging.step_warnings
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
  increment_script_depth
  start_time = print_script_start

  # EnvVars.first_install?: on a vanilla OS ~/.gitconfig is not yet symlinked, so
  # core.sshCommand is absent. Export GIT_SSH_COMMAND for this session to ensure
  # consistent SSH options for all git operations. Keepalive prevents timeout on slow networks.
  # Unset after install-dotfiles.rb symlinks ~/.gitconfig into place.
  ENV['GIT_SSH_COMMAND'] = 'ssh -o ConnectTimeout=20 -o Compression=no -o ServerAliveInterval=10 -o ServerAliveCountMax=3' if EnvVars.first_install?

  # ~/.curlrc is not yet symlinked on a vanilla OS, so its defaults are absent.
  # Build resilient curl flags explicitly for all bootstrap curl calls.
  # --retry-all-errors is intentionally omitted -- it causes the terminal to close.
  curl_opts = if EnvVars.first_install? || !EnvVars::HOME.join('.curlrc').file?
                %w[--retry 5 --retry-delay 10 --retry-max-time 120 --max-time 150 --connect-timeout 30 --retry-connrefused]
              else
                []
              end

  # Build cache-busting headers if CACHE_BUST_HEADERS env var is set
  cache_bust_headers = []
  if EnvVars.cache_bust_headers?
    cache_bust_headers = [
      '-H', 'Cache-Control: no-cache, no-store, must-revalidate',
      '-H', 'Pragma: no-cache',
      '-H', 'Expires: 0'
    ]
  end

  # ZDOTDIR must be set before any zsh is invoked downstream.
  ENV['ZDOTDIR'] ||= EnvVars::ZDOTDIR.to_s

  _setup_jio_dns

  # Download and source .shellrc before any other operations (provides utility functions).
  _download_and_source_shellrc(curl_opts, cache_bust_headers)

  # Prompt for sudo once here.
  # suspend_softwareupdate_schedule starts background thread to keep sudo alive
  # and also disables auto-updates while we work.
  system('sudo', '-v')
  MacOS.suspend_softwareupdate_schedule

  MacOS.approve_fingerprint_sudo

  MacOS.ensure_filevault_is_on

  MacOS.install_xcode_command_line_tools

  PathUtils.set_ssh_folder_permissions

  # DOTFILES_DIR is created by clone_repo_into's mkpath call. ANTIDOTE_HOME and other
  # tool-specific subdirectories (e.g. XDG_CONFIG_HOME/pg, XDG_STATE_HOME/vim/undo) are
  # created automatically by their respective tools, or by install-dotfiles.rb when it
  # creates symlinks to those locations.
  Logging.with_step('Create directories', 'Creating XDG base directories') do
    PathUtils.ensure_directories_exist([EnvVars::XDG_CACHE_HOME, EnvVars::XDG_CONFIG_HOME])
  end

  _clone_dot_files_repo

  # On FIRST_INSTALL: validate that curl-downloaded .shellrc matches the repo version.
  # If they differ, GitHub's CDN cache is stale -- abort with instructions.
  _validate_shellrc_matches_repo

  # Ensure dotfiles/scripts is on PATH regardless of whether the repo was just
  # cloned or was already present.
  PathUtils.prepend_to_path(EnvVars::DOTFILES_DIR.join('scripts'))

  Logging.with_step('install-dotfiles', 'Running install-dotfiles') do
    record_error 'install-dotfiles encountered errors' unless InstallDotfiles.run
  end

  # On FIRST_INSTALL: install-dotfiles.rb moves curl-downloaded .shellrc into the repo,
  # overwriting the committed version. Restore it so the symlink points to correct content.
  _restore_shellrc_after_install_dotfiles

  # ~/.gitconfig is now symlinked -- core.sshCommand is in effect.
  # Unset GIT_SSH_COMMAND so it no longer overrides core.sshCommand.
  ENV.delete('GIT_SSH_COMMAND')

  # Reload homebrew env and install.
  _install_homebrew(curl_opts)

  # Note: the dotfiles repo (cloned above via _clone_dot_files_repo -> GitProcessor.clone_repo_into)
  # is already a full clone by this point -- clone_repo_into runs 'unshallow' synchronously as
  # part of the clone itself, regardless of FIRST_INSTALL. No separate unshallow step is needed here.

  # Migrate repos cloned before Homebrew's git (2.45+) was on PATH. The system
  # git on vanilla macOS ignores -c init.defaultRefFormat=reftable and does not
  # support 'git refs migrate', so clone_repo_into's migration call was a no-op
  # for those early clones. Now that Homebrew's git is available, migrate them.
  # This runs after unshallow so the complete repository is migrated in one pass.
  Logging.with_step('Migrate repos to reftable', 'Migrating repos to reftable format') do
    GitProcessor.new(dir: EnvVars::DOTFILES_DIR).run_alias('migrate-reftable')
  end

  # Keybase repos (home + profiles).
  if nil_or_empty?(EnvVars::KEYBASE_USERNAME)
    info "Skipping Keybase repos -- 'EnvVars::KEYBASE_USERNAME' is not set"
  else
    Logging.section_header 'Cloning Keybase repos'

    Logging.with_step('Keybase login') do
      if Keybase.ensure_logged_in
        _clone_home_repo
        _clone_profiles_repo
      else
        record_error 'Keybase login failed -- skipping Keybase repo cloning'
      end
    end
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
      # On pre-configured machines, refresh backup before import if stale.
      _refresh_preferences_backup(capture_prefs) unless EnvVars.first_install?

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
       !CommandUtils.run_silent('pgrep', '-x', 'Sol')
      CommandUtils.run_silent('open', '-a', sol_app.to_s)
    end
  end

  # Recreate zsh completions cache.
  Logging.with_step('Recreate zsh completions', 'Recreate zsh completions') do
    zcompdump = EnvVars::XDG_CACHE_HOME.join('zcompdump')
    PathUtils.glob_pathnames(Pathname.new("#{zcompdump}*")) { |f| f.rmtree if f.exist? }
    CommandUtils.run_silent(
      'zsh', '-c',
      "autoload -Uz compinit && compinit -C -d '#{zcompdump}'"
    ) || true # Ignore failures - zsh completions are non-critical
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

  # Background tasks: long-running (can take minutes to hours on a fresh install
  # with many tracked repos) and safe to detach -- run without blocking the rest
  # of this script.
  bg_log = EnvVars::HOME.join('fresh-install-background.log')
  info "Background tasks logging to '#{bg_log.to_s.cyan}'"

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
  GitWorkspace.setup_dev_environment(first_install: EnvVars.first_install?)

  # Set default shell to Homebrew zsh (done at the end to avoid password prompt mid-script).
  _set_default_shell

  # User action reminders
  Logging.user_action 'Review System Settings and adjust as needed (Privacy & Security, Notifications, etc.)'

  # On FIRST_INSTALL, remind user to unshallow repos to get full history.
  Logging.user_action "Repositories were cloned shallow (--depth=1) to save time. Run '#{'all unshallow'.yellow}' to fetch complete history, then '#{'git rebase @{u}'.yellow}' or '#{'git merge @{u}'.yellow}' in each repo to update working trees." if EnvVars.first_install?

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

# ---------------------------------------------------------------------------
# Script execution
# ---------------------------------------------------------------------------

# This script always executes at top level (lines 403-674) when run.
# No if __FILE__ == $PROGRAM_NAME guard is needed because this is a one-time
# install script that is never required as a library by other scripts.
