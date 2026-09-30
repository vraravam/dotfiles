#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: <anywhere; advisable in the PATH>
#
# Idempotent macOS fresh-install and re-configuration script.
# Works on a vanilla macOS and on a pre-configured machine without errors.
#
# Usage:
#   Standalone: fresh-install-of-osx.rb
#   Module:     FreshInstallOfOsx.run -> true/false; FreshInstallOfOsx.report_outcome(success:)
#               prints the manual-step reminders and the closing notification (the CLI calls
#               it once the summary has printed)
#
# TODO: Need to figure out scriptable commands for:
# 1. Auto-adjust Brightness
# 2. Brightness on battery
# 3. Keyboard brightness

require 'rbconfig'
require 'shellwords'

require_relative 'add-upstream-git-config'
require_relative 'install-dotfiles'
require_relative 'osx-defaults'
require_relative 'resurrect-repositories'
require_relative 'utilities/brew_bundle'
require_relative 'utilities/command_utils'
require_relative 'utilities/core'
require_relative 'utilities/cron'
require_relative 'utilities/default_shell'
require_relative 'utilities/dev_environment'
require_relative 'utilities/env_vars'
require_relative 'utilities/generate_bootstrap_repositories_yaml'
require_relative 'utilities/git_processor'
require_relative 'utilities/homebrew_install'
require_relative 'utilities/keybase'
require_relative 'utilities/logging'
require_relative 'utilities/macos'
require_relative 'utilities/path_utils'
require_relative 'utilities/shellrc_check'
require_relative 'utilities/step_counter'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module FreshInstallOfOsx
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Raised by a helper that has already printed why the install cannot continue, so 'run'
  # returns false without adding a second error message.
  Aborted = Class.new(StandardError)

  # .shellrc's location inside the dotfiles repo, relative to ${DOTFILES_DIR}.
  REPO_SHELLRC_RELATIVE = ShellrcCheck::REPO_SHELLRC_RELATIVE

  # Number of '_numbered_step_label' call sites below -- keep in sync when adding or removing
  # a numbered step. The fingerprint, FileVault and Xcode CLT steps (which print their own
  # section headers), the bare install-dotfiles step, the Keybase/encrypted-backup setup
  # sections and the tracked-repos phase are deliberately not numbered.
  TOTAL_INSTALL_STEPS = 10

  # Public API method. Runs the whole installation.
  #
  # Cron is suspended before any work begins. The 'Setup cron jobs' step reinstalls the schedule
  # and removes the backup on success; otherwise the 'ensure' clause restores the original
  # schedule from that backup.
  #
  # @return [Boolean] true if the installation ran to the end (recorded warnings/errors are
  #   reported in the summary and the notification), false if it was aborted.
  def run
    @steps = StepCounter.new(TOTAL_INSTALL_STEPS)
    @failure_message = nil

    # Exported so the zsh subprocesses sourcing .shellrc (suspend_cron/resume_cron) agree on the
    # same backup file as Cron.suspend_cron/resume_cron in this process.
    ENV['_DOTFILES_CRON_BACKUP_FILE'] = EnvVars.cron_backup_file.to_s

    Cron.suspend_cron
    begin
      _install
      Logging.info '** Finished auto installation process **'
      true
    rescue Aborted
      false
    rescue StandardError => e
      # Unhandled exception during the installation. Print directly via Kernel#warn
      # (unconditional, never raises) rather than Logging.error -- this is the last-resort
      # handler, so calling a method that itself raises would trigger a second, unhandled
      # exception here.
      msg = "Installation failed with unhandled exception: #{e.message}"
      msg += "\n  at #{e.backtrace.first}" if e.backtrace&.any?
      @failure_message = msg
      Kernel.warn "ERROR: #{msg}"
      false
    ensure
      # Restores the original cron schedule unless the 'Setup cron jobs' step already
      # reinstalled it and removed the backup (then there is nothing to restore).
      Cron.resume_cron
    end
  end

  # Process-level wrap-up, run after the summary has printed: the manual-step reminders (on
  # success) and exactly one notification, last, so the user sees the collected issues in the
  # terminal before the popup.
  #
  # @param success [Boolean] The result of #run.
  # @return [void]
  def report_outcome(success:)
    unless success
      MacOS.notify("[#{File.basename(__FILE__)}] #{@failure_message || 'Installation failed. Check for error messages above.'}", '❌ Error')
      return
    end

    # Remind user of manual steps that cannot be automated
    Logging.user_action 'Review System Settings manually: some settings (FileVault, accessibility permissions, notification preferences) require GUI interaction and cannot be automated due to TCC restrictions.'

    # On FIRST_INSTALL, remind user to unshallow repos to get full history.
    Logging.user_action "Repositories were cloned shallow (--depth=1) to save time. In a NEW terminal (this one predates the updated PATH and aliases), run '#{'all unshallow'.yellow}' to fetch complete history, then '#{'git rebase @{u}'.yellow}' or '#{'git merge @{u}'.yellow}' in each repo to update working trees." if EnvVars.first_install?

    parts = Logging.issue_summary_parts
    if parts.empty?
      MacOS.notify('Fresh install completed successfully.', '✅ Fresh Install Done')
    else
      MacOS.notify("Install done -- #{parts.join(' | ')}", '⚠️ Fresh Install')
    end
  end

  # The installation steps, in order.
  def _install
    # EnvVars.first_install?: on a vanilla OS ${XDG_CONFIG_HOME}/git/config is not yet symlinked,
    # so core.sshCommand is absent. Export GIT_SSH_COMMAND for this session to ensure
    # consistent SSH options for all git operations. Keepalive prevents timeout on slow networks.
    # Unset after install-dotfiles.rb symlinks ${XDG_CONFIG_HOME}/git/config into place.
    ENV['GIT_SSH_COMMAND'] = 'ssh -o ConnectTimeout=20 -o Compression=no -o ServerAliveInterval=10 -o ServerAliveCountMax=3' if EnvVars.first_install?

    # ~/.curlrc is not yet symlinked on a vanilla OS, so its defaults are absent.
    # Build resilient curl flags explicitly for all bootstrap curl calls.
    # --retry-all-errors is intentionally omitted -- it causes the terminal to close.
    use_retry_opts = EnvVars.curl_retry_opts? || !EnvVars::HOME.join('.curlrc').file?
    curl_opts = use_retry_opts ? %w[--retry 5 --retry-delay 10 --retry-max-time 120 --max-time 150 --connect-timeout 30 --retry-connrefused] : []

    # ZDOTDIR must be set before any zsh is invoked downstream.
    ENV['ZDOTDIR'] ||= EnvVars::ZDOTDIR.to_s

    _setup_jio_dns

    gh_username = _resolve_gh_username
    dotfiles_branch = _resolve_dotfiles_branch

    # Download and source .shellrc before any other operations (provides utility functions).
    _download_and_source_shellrc(gh_username: gh_username, dotfiles_branch: dotfiles_branch, curl_opts: curl_opts)

    # Printed as early as possible (right after '.shellrc' is sourced, so ENCRYPTED_*_REPO_URL
    # env vars are populated) rather than at the much-later cloning step -- this manual escape
    # hatch is only needed if the external 'git-remote-gpg-encrypt' tool's interactive Keychain
    # prompt fails or can't run (e.g. no TTY), and by the time the cloning step is reached
    # (after xcode tools/homebrew/etc.) it is too late for the user to act on this in parallel
    # with the rest of the install. Gated on the encrypted-backup env vars actually being set --
    # no point reminding someone who has disabled this mechanism.
    if !nil_or_empty?(ENV.fetch('ENCRYPTED_HOME_REPO_URL', '')) || !nil_or_empty?(ENV.fetch('ENCRYPTED_PROFILES_REPO_URL', ''))
      Logging.user_action "The 'home'/'browser-profiles' repo clone steps later in this script read their encrypted-backup passphrase from the macOS Keychain -- you won't normally be prompted."
      Logging.user_action 'If that fails, run this in another terminal now (no need to wait): ' \
                          "security add-generic-password -A -a \"#{EnvVars::USER}\" -s 'git-remote-gpg-encrypt' -w"
    end

    # Prompt for sudo once here, then keep it alive via a background thread for the
    # rest of the script (same behavior as keep_sudo_alive in .shellrc).
    MacOS.keep_sudo_alive

    Logging.with_step('Touch ID for sudo') { MacOS.approve_fingerprint_sudo }

    Logging.with_step('Verify FileVault') { MacOS.ensure_filevault_is_on }

    Logging.with_step('Install Xcode command-line tools') { MacOS.install_xcode_command_line_tools }

    PathUtils.set_ssh_folder_permissions
    PathUtils.set_gnupg_folder_permissions

    # DOTFILES_DIR is created by clone_repo_into's mkpath call. ANTIDOTE_HOME and other
    # tool-specific subdirectories (e.g. XDG_CONFIG_HOME/pg, XDG_STATE_HOME/vim/undo) are
    # created automatically by their respective tools, or by install-dotfiles.rb when it
    # creates symlinks to those locations.
    Logging.with_step('Create directories', _numbered_step_label('Creating XDG base directories')) do
      PathUtils.ensure_directories_exist([EnvVars::XDG_CACHE_HOME, EnvVars::XDG_CONFIG_HOME])
    end

    _clone_dot_files_repo(gh_username: gh_username, dotfiles_branch: dotfiles_branch)

    # On FIRST_INSTALL: validate that curl-downloaded .shellrc matches the repo version.
    # If they differ, GitHub's CDN cache is stale -- abort with instructions.
    raise Aborted unless ShellrcCheck.matches_repo?

    # Ensure dotfiles/scripts is on PATH regardless of whether the repo was just
    # cloned or was already present.
    PathUtils.append_to_path(EnvVars::DOTFILES_DIR.join('scripts'))

    Logging.with_step('install-dotfiles', 'Running install-dotfiles') do
      # A failure here is fatal rather than recorded and continued past, since every later
      # step depends on the symlinks install-dotfiles creates.
      Logging.error 'install-dotfiles encountered errors' unless InstallDotfiles.run
    end

    _recompile_zsh_startup_files

    # On FIRST_INSTALL: install-dotfiles.rb moves curl-downloaded .shellrc into the repo,
    # overwriting the committed version. Restore it so the symlink points to correct content.
    _restore_shellrc_after_install_dotfiles

    # ${XDG_CONFIG_HOME}/git/config is now symlinked -- core.sshCommand is in effect.
    # Unset GIT_SSH_COMMAND so it no longer overrides core.sshCommand.
    ENV.delete('GIT_SSH_COMMAND')

    # Load the zsh configs now that the symlinks exist and core.sshCommand is in effect.
    _load_zsh_configs

    # Reload homebrew env and install.
    _install_homebrew

    # Note: the dotfiles repo (cloned above via _clone_dot_files_repo -> GitProcessor.clone_repo_into)
    # is already a full clone by this point -- clone_repo_into runs 'unshallow' synchronously as
    # part of the clone itself, regardless of FIRST_INSTALL. No separate unshallow step is needed here.

    # Migrate repos cloned before Homebrew's git (2.45+) was on PATH. The system
    # git on vanilla macOS ignores -c init.defaultRefFormat=reftable and does not
    # support 'git refs migrate', so clone_repo_into's migration call was a no-op
    # for those early clones. Now that Homebrew's git is available, migrate them.
    # This runs after unshallow so the complete repository is migrated in one pass.
    Logging.with_step('Migrate repos to reftable', _numbered_step_label('Migrating repos to reftable format')) do
      GitProcessor.new(dir: EnvVars::DOTFILES_DIR) do |git|
        _stdout, _stderr, status = git.run_alias('migrate-reftable', stream: true)
        Logging.record_error "'#{'git migrate-reftable'.cyan}' failed for '#{EnvVars::DOTFILES_DIR.cyan}'" unless status.success?
      end
    end

    # Log into Keybase if KEYBASE_HOME_REPO_NAME/KEYBASE_PROFILES_REPO_NAME enable it.
    # Coexists with the encrypted-backup setup below -- see KeybaseMigration.md. This is
    # a readiness/login step only; the actual clone attempt (which also calls
    # Keybase.ensure_logged_in defensively) happens in _resurrect_bootstrap_repos.
    Logging.with_step('Setup Keybase', 'Setup Keybase') do
      Logging.record_warning 'Keybase login failed -- continuing without Keybase-based backups' unless Keybase.bootstrap_login(first_install: EnvVars.first_install?)
    end

    # Verify encrypted-backup mechanism is ready (gpg installed, Keychain passphrase set --
    # see the external 'git-remote-gpg-encrypt' tool, installed via the 'vraravam/tap'
    # Homebrew tap). Coexists with Keybase above -- see KeybaseMigration.md. gnupg homedir
    # permissions were already fixed earlier in main() -- no need to repeat that here.
    Logging.with_step('Setup encrypted backup', 'Setup encrypted backup') do
      if nil_or_empty?(ENV.fetch('ENCRYPTED_HOME_REPO_URL', '')) && nil_or_empty?(ENV.fetch('ENCRYPTED_PROFILES_REPO_URL', ''))
        Logging.debug "Neither 'ENCRYPTED_HOME_REPO_URL' nor 'ENCRYPTED_PROFILES_REPO_URL' env var is set -- skipping encrypted-backup setup"
      elsif PathUtils.command_exists?('git-gpg-encrypt-setup')
        if CommandUtils.run_interactive('git-gpg-encrypt-setup')
          Logging.success 'Encrypted backup is ready to use'
        else
          Logging.record_warning 'Encrypted backup is not configured -- see instructions above'
        end
      else
        Logging.debug "'git-gpg-encrypt-setup' not found in PATH -- skipping encrypted backup setup"
      end
    end

    # Clone/update repos from whichever backup mechanism(s) are enabled (home and
    # browser-profiles) -- _resurrect_bootstrap_repos manages its own step timing and
    # section header internally, so no outer step wrapper is needed here.
    _resurrect_bootstrap_repos

    # Remove stale SSH known_hosts backup if present.
    old_known_hosts = EnvVars::HOME.join('.ssh', 'known_hosts.old')
    old_known_hosts.delete if old_known_hosts.file?

    # Restore macOS preferences.
    Logging.with_step('Restore preferences', _numbered_step_label('Restore preferences')) do
      _baseline_preferences

      capture_prefs = EnvVars::DOTFILES_DIR.join('scripts', 'capture-prefs.rb')
      if capture_prefs.file?
        # On pre-configured machines, refresh backup before import if stale.
        _refresh_preferences_backup(capture_prefs) unless EnvVars.first_install?

        # Must use subprocess instead of CapturePrefs.run(operation: 'import'):
        # capture-prefs.rb has at_exit hooks (resume softwareupdate, restart apps)
        # that must fire immediately after import completes, not at fresh-install
        # exit. Multiple invocations (export above, import here) need independent
        # cleanup lifecycles. Subprocess isolation ensures this.
        if CommandUtils.run_interactive({ 'COLUMNS' => EnvVars.columns.to_s }, RbConfig.ruby, capture_prefs.to_s, '-i')
          Logging.success 'Successfully restored preferences from backup'
        else
          Logging.record_error "capture-prefs.rb -i exited non-zero -- import preferences manually: #{capture_prefs.cyan}"
        end
      else
        Logging.record_error "capture-prefs.rb not found at '#{capture_prefs.cyan}' -- import preferences manually"
      end
    end

    # Recreate zsh completions cache.
    Logging.with_step('Recreate zsh completions', _numbered_step_label('Recreate zsh completions')) do
      zcompdump = EnvVars::XDG_CACHE_HOME.join('zcompdump')
      PathUtils.glob_pathnames(Pathname.new("#{zcompdump}*")) { |f| f.rmtree if f.exist? }
      # A failure is ignored: the completions cache is non-critical.
      CommandUtils.run_silent('zsh', '-c', "autoload -Uz compinit && compinit -C -d '#{zcompdump}'")
    end

    # Setup cron jobs.
    Logging.with_step('Setup cron jobs', _numbered_step_label('Setup cron jobs')) do
      # Reinstall the schedule first; the backup is only removed once that worked, so the
      # 'ensure' clause in 'run' can still restore the original schedule if it failed.
      if Cron.recron
        EnvVars.cron_backup_file.delete if EnvVars.cron_backup_file.file?
      else
        Logging.record_error 'recron failed -- original cron schedule preserved in backup'
      end
    rescue StandardError => e
      Logging.record_error "Failed to set up cron jobs: #{e.message} -- original cron schedule preserved in backup"
    end

    # Resurrect all repos tracked in ${PERSONAL_CONFIGS_DIR}/repositories-*.yml catalogs.
    # ResurrectRepositories.run(resurrect_all: true) (the module form of 'resurrect-repositories.rb
    # -a') resurrects every catalogue, lists the failed ones in one warning, then runs
    # DevEnvironment.setup_dev_environment and regenerate_repo_aliases itself at the very end
    # (_resurrect_bootstrap_repos above already ran setup_dev_environment once as an early safety
    # net right after the home/profiles repos were cloned; idempotent either way). Runs
    # synchronously: on a first install this can legitimately take a while (many repos to clone).
    #
    # Sets current_section (no header printed) rather than using with_step, so any
    # warning/error raised during this phase is attributed to 'Resurrect tracked repos' in
    # the final summary rather than inheriting whatever the previous with_step call set.
    Logging.current_section = 'Resurrect tracked repos'
    Logging.record_warning "Failed to fully resurrect tracked repos -- see output above for details; re-run '#{'resurrect-repositories.rb -a'.cyan}' manually" unless ResurrectRepositories.run(resurrect_all: true)

    # Force-refresh all zsh bytecode (*.zwc) and cache files. install-dotfiles.rb
    # re-symlinks .zshrc/.shellrc/.aliases on every run, but a .zwc left over from
    # an earlier partial fresh-install attempt (or a terminal opened manually
    # mid-debug) can carry a mtime that defeats recompile_zsh_script's -nt
    # staleness check -- new terminals then load bytecode compiled from stale
    # source indefinitely (e.g. missing PATH entries added by a later commit),
    # with no self-correction since plain zsh never checks .zwc staleness itself.
    # delete_caches (a shell function in .aliases) sidesteps the mtime comparison
    # entirely by deleting every *.zwc* file unconditionally and rebuilding from
    # current source. Shelled out to zsh since delete_caches has no Ruby port -- .shellrc must
    # be sourced first since .aliases' functions depend on it.
    Logging.with_step('Refresh zsh bytecode caches', _numbered_step_label('Refresh zsh bytecode caches')) do
      shellrc_path = EnvVars::HOME.join('.shellrc')
      aliases_path = EnvVars::ZDOTDIR.join('.aliases')
      cmd = "source #{shellrc_path.to_s.shellescape}; source #{aliases_path.to_s.shellescape}; delete_caches"
      Logging.record_warning "Failed to run 'delete_caches' -- new terminals may load stale .zwc files until it is run manually" unless CommandUtils.run_interactive('zsh', '-c', cmd)
    end

    # Set default shell to Homebrew zsh (done at the end to avoid password prompt mid-script).
    _set_default_shell
  end

  # ---------------------------------------------------------------------------
  # Bootstrap helpers

  # Prefixes +label+ with the next '[Step N of TOTAL]' progress label.
  #
  # @param label [String] The human-readable step label.
  # @return [String] The numbered label.
  def _numbered_step_label(label)
    "#{@steps.next_prefix}#{label}"
  end

  # Request headers that bypass GitHub's CDN and intermediate proxies; empty unless
  # CACHE_BUST_HEADERS is set.
  #
  # @return [Array<String>] curl arguments
  def _cache_bust_headers
    return [] unless EnvVars.cache_bust_headers?

    ['-H', 'Cache-Control: no-cache, no-store, must-revalidate', '-H', 'Pragma: no-cache', '-H', 'Expires: 0']
  end

  # Downloads +url+ to +dest+ with the bootstrap's resilient curl flags.
  #
  # @param url [String]
  # @param dest [Pathname, String]
  # @param curl_opts [Array<String>] retry/timeout flags (see the main block)
  # @return [Boolean] true if curl succeeded
  def _curl_download(url, dest, curl_opts)
    CommandUtils.run_interactive('curl', *_cache_bust_headers, *curl_opts, '-fsSL', url, '-o', dest.to_s)
  end

  # Sources .zshenv, .zshrc and .zlogin (through .shellrc's load_zsh_configs) in a zsh subprocess,
  # so their on-disk side effects happen now rather than lazily in the user's first terminal: the
  # brew/starship/compinit caches (which need the tools installed by the earlier steps) and the
  # antidote plugin bundle, regenerated when a freshly cloned plugins.txt is newer than plugins.zsh.
  # The environment those files export cannot be handed back to this process.
  def _load_zsh_configs
    shellrc = EnvVars::HOME.join('.shellrc').to_s.shellescape
    return if CommandUtils.run_interactive({ 'DEBUG' => 'true' }, 'zsh', '-c', "source #{shellrc}; load_zsh_configs")

    Logging.record_warning 'Failed to load the zsh configs -- caches and the antidote bundle will be rebuilt by the first new terminal instead'
  end

  # Sets DNS to 1.1.1.1 if on Jio ISP (GitHub may otherwise not resolve).
  def _setup_jio_dns
    org = CommandUtils.query('curl', '-fsS', 'https://ipinfo.io/org')
    return unless org.downcase.include?('jio')

    Logging.info 'Setting DNS for Wi-Fi from Jio ISP'
    return if CommandUtils.run_silent('networksetup', '-setdnsservers', 'Wi-Fi', '1.1.1.2', '9.9.9.9')

    Logging.warn 'Failed to set DNS for Wi-Fi'
  end

  # Resolve GH_USERNAME without requiring it to be permanently stored anywhere. On the
  # very first (vanilla OS) run there is nothing cloned yet to derive it from, so an
  # explicitly exported GH_USERNAME (from the bootstrap one-liner) is required. On every
  # subsequent run (pre-configured machine, re-running this script to pick up updates),
  # DOTFILES_DIR already exists locally, so this derives the value from its 'origin'
  # remote instead -- meaning adopters never need to remember to export GH_USERNAME
  # again after the first successful run.
  #
  # @return [String] the resolved GitHub username
  def _resolve_gh_username
    gh_username = ENV.fetch('GH_USERNAME', '')
    return gh_username unless gh_username.empty?

    dotfiles_dir = EnvVars::DOTFILES_DIR
    if GitProcessor.repo?(dotfiles_dir)
      remote_url = GitProcessor.new(dir: dotfiles_dir).remote_url.to_s
      gh_username = remote_url[%r{[:/]([^/]+)/dotfiles(\.git)?/?$}, 1].to_s
    end

    if gh_username.empty?
      Kernel.warn "ERROR: GH_USERNAME is not set and could not be derived from '#{dotfiles_dir}'."
      Kernel.warn "       Export it before running: export GH_USERNAME='your-github-username'"
      raise Aborted
    end

    ENV['GH_USERNAME'] = gh_username
    gh_username
  end

  # Resolves which branch of the dotfiles repo to bootstrap from/check out. Unlike
  # GH_USERNAME (no safe default -- every fork's username differs, so an unresolvable
  # value is a hard error), DOTFILES_BRANCH has a universally-correct default ('master')
  # for everyone who hasn't deliberately switched to a different branch for testing, so
  # this never errors out -- it only derives-or-falls-back.
  #
  # Only ever read before '${DOTFILES_DIR}' exists as a git repo (constructing the
  # '.shellrc' download URL, and the initial clone of the dotfiles repo itself); on any
  # later re-run, the already-cloned repo is used directly and this value is never
  # consulted again. Safe to derive from the local repo's own current branch on such a
  # re-run (e.g. after manually checking out a test branch there -- see Advanced.md
  # section 5.6), rather than requiring it to be kept in sync anywhere else.
  #
  # @return [String] the resolved branch name
  def _resolve_dotfiles_branch
    dotfiles_branch = ENV.fetch('DOTFILES_BRANCH', '')
    return dotfiles_branch unless dotfiles_branch.empty?

    dotfiles_dir = EnvVars::DOTFILES_DIR
    dotfiles_branch = GitProcessor.new(dir: dotfiles_dir).current_branch.to_s if GitProcessor.repo?(dotfiles_dir)
    dotfiles_branch = 'master' if dotfiles_branch.empty?

    ENV['DOTFILES_BRANCH'] = dotfiles_branch
    dotfiles_branch
  end

  # Downloads .shellrc from GitHub when needed and sources it.
  #
  # @param gh_username [String] GitHub user owning the dotfiles fork
  # @param dotfiles_branch [String] Branch to download .shellrc from
  # @param curl_opts [Array<String>] retry/timeout flags for curl
  def _download_and_source_shellrc(gh_username:, dotfiles_branch:, curl_opts:)
    Logging.info "Ensuring '#{'~/.shellrc'.cyan}' is current"

    shellrc_path = EnvVars::HOME.join('.shellrc')
    shellrc_path_str = shellrc_path.to_s
    repo_shellrc = EnvVars::DOTFILES_DIR.join(REPO_SHELLRC_RELATIVE)

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
      Logging.info "Downloading .shellrc from GitHub (#{reason})"
      # Cache-busting: append a timestamp to the URL (plus the no-cache headers, when enabled)
      # to bypass GitHub's CDN cache and intermediate proxies and get the latest version.
      timestamp = Time.now.to_i
      url = "https://raw.githubusercontent.com/#{gh_username}/dotfiles/refs/heads/#{dotfiles_branch}/#{REPO_SHELLRC_RELATIVE}?#{timestamp}"

      Logging.error 'Failed to download .shellrc' unless _curl_download(url, shellrc_path, curl_opts)
    end

    # Universal validation (both first-install and pre-configured)
    # Validate: check that file is non-empty and contains the re-source guard
    # function (basic smoke test for successful download vs truncated/corrupted response).
    # Use explicit UTF-8 encoding to avoid "invalid byte sequence in US-ASCII".
    unless shellrc_path.file? && shellrc_path.size.positive? && shellrc_path.read(encoding: 'UTF-8').include?('is_shellrc_sourced')
      Kernel.warn 'ERROR: .shellrc appears corrupted or empty'
      raise Aborted
    end

    Logging.info "Verified '#{shellrc_path_str.cyan}'"

    # Running .shellrc in a zsh subprocess doesn't make its functions/env vars available
    # to this Ruby process (the subprocess's environment is discarded on exit) -- the
    # rest of this script uses the Ruby utility modules instead. This run validates the
    # file parses correctly and warms any on-disk caches .shellrc creates (e.g. Homebrew
    # shellenv, starship init), which benefits the next real interactive shell.
    unless CommandUtils.run_interactive({ 'DEBUG' => 'true' }, 'zsh', '-c', "source #{shellrc_path_str.shellescape}")
      Kernel.warn "ERROR: failed to source '#{shellrc_path_str}'"
      raise Aborted
    end
    Logging.success "Successfully sourced '#{shellrc_path_str.cyan}'"
  end

  # Force-checks and recompiles-if-needed the core zsh startup files right now,
  # as their own explicit step -- deliberately not deferred to whatever recompiles
  # them incidentally later. Later steps in this script (e.g.
  # 'ResurrectRepositories.run(resurrect_all: true)') can run for tens of minutes; establishing correct
  # bytecode this early -- immediately after install-dotfiles.rb (re-)creates
  # these symlinks -- means it does not depend on reaching (or the timing of)
  # any later step. recompile_zsh_script (shell function, no Ruby port; called
  # via a zsh subprocess since .shellrc must be sourced first to define it)
  # no-ops when the .zwc is already current, so this costs a handful of stat
  # calls when nothing changed. This does NOT remove the need for the
  # unconditional delete_caches call near the end of this script: that call
  # exists because a stale .zwc left over from an earlier partial fresh-install
  # attempt can have a mtime that defeats this same is_file_older_than check
  # entirely (see the comment on the 'Refresh zsh bytecode caches' step below).
  def _recompile_zsh_startup_files
    shellrc_path = EnvVars::HOME.join('.shellrc')
    aliases_path = EnvVars::ZDOTDIR.join('.aliases')
    core_files = [
      EnvVars::ZDOTDIR.join('.zshenv'),
      EnvVars::ZDOTDIR.join('.zshrc'),
      EnvVars::ZDOTDIR.join('.zlogin'),
      shellrc_path,
      aliases_path,
    ]
    recompile_cmds = core_files.map { |f| "recompile_zsh_script #{f.to_s.shellescape}" }.join('; ')
    CommandUtils.run_interactive('zsh', '-c', "source #{shellrc_path.to_s.shellescape}; #{recompile_cmds}")
  end

  # Restores .shellrc from git after install-dotfiles.rb moves the downloaded version.
  # :reek:FeatureEnvy -- Multiple sequential git operations on the same repo (intentional)
  def _restore_shellrc_after_install_dotfiles
    return unless EnvVars.first_install?

    git = GitProcessor.new(dir: EnvVars::DOTFILES_DIR)
    shellrc_relative = REPO_SHELLRC_RELATIVE

    # Check if install-dotfiles.rb modified .shellrc in the repo
    _stdout, _stderr, status = git.run_alias('diff', '--quiet', '--', shellrc_relative)
    return if status.success? # No changes, nothing to restore

    # Restore committed version
    git.run_alias('checkout', '--', shellrc_relative)

    shellrc_path = EnvVars::HOME.join('.shellrc')

    # Recompile again: this checkout can change .shellrc's content/mtime after
    # _recompile_zsh_startup_files already ran, making that earlier pass stale
    # relative to this specific restore. Plain 'source' does not check .zwc staleness
    # itself, so without this the re-source below could silently load bytecode compiled
    # before this checkout, defeating the restore above entirely.
    CommandUtils.run_interactive('zsh', '-c', "source #{shellrc_path.to_s.shellescape}; recompile_zsh_script #{shellrc_path.to_s.shellescape}")

    # Re-run the restored version through zsh to validate it parses correctly
    # (same rationale as _download_and_source_shellrc above).
    CommandUtils.run_interactive({ 'DEBUG' => 'true' }, 'zsh', '-c', "source #{shellrc_path.to_s.shellescape}")
  end

  # Clones the dotfiles repo (if not already present) and configures push-over-SSH,
  # PATH, and the upstream remote.
  #
  # @param gh_username [String] GitHub user owning the dotfiles fork
  # @param dotfiles_branch [String] Branch to clone
  # :reek:NilCheck -- config_value returns nil when the key is unset (standard git config idiom)
  def _clone_dot_files_repo(gh_username:, dotfiles_branch:)
    dotfiles_dir = EnvVars::DOTFILES_DIR
    Logging.with_step('Clone dotfiles repo', _numbered_step_label("Installing dotfiles into '#{dotfiles_dir.to_s.cyan}'")) do
      if GitProcessor.repo?(dotfiles_dir)
        Logging.info "Skipping cloning the dotfiles repo since '#{dotfiles_dir.to_s.cyan}' already exists and is a git repo"
      else
        # Delete the auto-generated .zshrc since that needs to be replaced by the one in the DOTFILES_DIR repo.
        zshrc = EnvVars::ZDOTDIR.join('.zshrc')
        zshrc.rmtree if zshrc.symlink? || zshrc.exist?

        # Note: Cloning with https since the ssh keys will not be present at this time.
        url = "https://github.com/#{gh_username}/dotfiles"
        if GitProcessor.clone_repo_into(url, dotfiles_dir, branch: dotfiles_branch)
          # Use the https protocol for pull, but use ssh/git for push (only configure if not already set).
          git = GitProcessor.new(dir: dotfiles_dir)
          push_key = 'url.ssh://git@github.com/.pushInsteadOf'
          git.config_set(push_key, 'https://github.com/') if git.config_value(push_key).nil?
        else
          Logging.error 'Failed to clone dotfiles repo'
        end
      end

      # Put the repo's scripts on PATH regardless of whether the repo was just cloned or already
      # existed (a re-run, e.g. a retried vanilla install, would otherwise call
      # add-upstream-git-config's 'git fo' without the 'git-fo' subcommand on PATH). Appended,
      # so it can never shadow a system command.
      PathUtils.append_to_path(dotfiles_dir.join('scripts'))

      # Setup the dotfiles repo's upstream remote (points at the repo this fork was
      # derived from). This runs regardless of whether the repo was just cloned or
      # already existed. AddUpstreamGitConfig.run is idempotent and no-ops cleanly both
      # when 'upstream' already exists and when origin's own owner already matches
      # UPSTREAM_GH_USERNAME (e.g. running this on the upstream owner's own machine) --
      # so no GH_USERNAME comparison is needed here.
      upstream_ok = AddUpstreamGitConfig.run(dir: dotfiles_dir, upstream_owner: EnvVars::UPSTREAM_GH_USERNAME)
      Logging.record_warning 'Failed to add upstream git config for dotfiles repo' unless upstream_ok
    end
  end

  # Installs Homebrew (HomebrewInstall), then installs the Brewfile (BrewBundle).
  def _install_homebrew
    homebrew_prefix = EnvVars::HOMEBREW_PREFIX
    Logging.with_step('Install Homebrew', _numbered_step_label("Installing Homebrew into '#{homebrew_prefix.to_s.cyan}'")) do
      # Every later step depends on Homebrew, so a failure here ends the run.
      raise Aborted unless HomebrewInstall.run

      # Ensure homebrew env vars are set for this process session.
      MacOS.load_brew_shellenv(homebrew_prefix.join('bin', 'brew'))

      # Install formulae/casks from the Brewfile.
      # On first install: base section only + background full install.
      # On pre-configured: full Brewfile synchronously.
      Logging.record_warning 'Homebrew bundle install failed or had errors -- see output above; continuing...' unless BrewBundle.run(first_install: EnvVars.first_install?)

      # Reload the zsh configs now that the tools they depend on are installed.
      _load_zsh_configs
    end
  end

  # Resurrects the home and browser-profiles repos via ResurrectRepositories, using a
  # YAML config generated on the fly by GenerateBootstrapRepositoriesYaml from whichever
  # KEYBASE_*_REPO_NAME/ENCRYPTED_*_REPO_URL env vars are configured (see that module's
  # own header comment for how the primary vs fallback remote for each repo is chosen).
  # Both are called as direct module calls (not subprocesses) since this script is Ruby
  # end to end -- ResurrectRepositories already owns clone/verify/remote-configuration/
  # fetch/post-clone logic generically, including trying a repo's 'other_remotes' as a
  # fallback clone source if the primary remote fails.
  #
  # The generated YAML lives directly in $HOME (not '${PERSONAL_CONFIGS_DIR}', which is
  # itself inside the home repo and doesn't exist until this resurrects it) -- see
  # files/--HOME--/custom.gitignore for why it's safe to leave there permanently.
  def _resurrect_bootstrap_repos
    Logging.with_step('Resurrect bootstrap repos', _numbered_step_label('Cloning repos')) do
      # clone_repo_into itself does not ensure Keybase is logged in -- only needed here if
      # at least one of the two repos actually has Keybase enabled.
      keybase_home = ENV.fetch('KEYBASE_HOME_REPO_NAME', '')
      keybase_profiles = ENV.fetch('KEYBASE_PROFILES_REPO_NAME', '')
      keybase_configured = !(nil_or_empty?(keybase_home) && nil_or_empty?(keybase_profiles))
      Logging.record_warning('Keybase login failed -- continuing without Keybase-based backups') if keybase_configured && !Keybase.ensure_logged_in(start_service: true)

      bootstrap_repos_yaml = EnvVars::HOME.join('.bootstrap-repositories.yml')
      if GenerateBootstrapRepositoriesYaml.run(output_file: bootstrap_repos_yaml)
        Logging.record_warning 'Failed to fully resurrect home/profiles repos -- see output above for details' unless ResurrectRepositories.run(resurrect: bootstrap_repos_yaml)
      else
        Logging.record_error 'Failed to generate bootstrap repositories config -- skipping home/profiles repo resurrection'
      end

      # Run setup_dev_environment once now, as a safety net, immediately after the
      # home/profiles repos are cloned -- covers mise tool-version installation and
      # direnv allow for these two repos even if a later step below aborts before
      # reaching 'ResurrectRepositories.run(resurrect_all: true)' near the end of this
      # script, which also runs setup_dev_environment (for all tracked repos, including
      # these two again -- idempotent). No 'command_exists' guard is needed: this is a
      # direct module call, always available via the 'require_relative' above.
      DevEnvironment.setup_dev_environment(first_install: EnvVars.first_install?)

      # Reload the zsh configs: the home repo may just have brought in state this process has not
      # seen yet -- most notably plugins.zsh (the antidote plugin bundle). If the cloned plugins.txt is
      # newer than it, regenerating the bundle now means the user's next terminal does not wait it out.
      _load_zsh_configs
    end
  end

  # Applies the baseline macOS defaults. OsxDefaults is called as a module (it keeps no at_exit
  # hooks, so no subprocess is needed): its warnings and errors land in this script's summary and
  # notification. An exception is recorded rather than aborting the install -- a failing baseline
  # has never been fatal to the rest of the setup.
  def _baseline_preferences
    ok = OsxDefaults.run(silent: true)
    Logging.info 'Note that some of the baselined settings require a logout/restart to take effect.'
    if ok
      Logging.success 'Successfully baselined preferences'
    else
      Logging.record_error "osx-defaults failed -- baseline preferences manually: #{'osx-defaults.rb -s'.cyan}"
    end
  rescue StandardError => e
    Logging.record_error "osx-defaults failed (#{e.message}) -- baseline preferences manually: #{'osx-defaults.rb -s'.cyan}"
  end

  # Refreshes the preferences backup (export + commit) on a pre-configured machine
  # before importing, so the git-timestamp check in capture-prefs.rb -i passes.
  def _refresh_preferences_backup(capture_prefs)
    Logging.info 'Pre-configured machine detected -- refreshing preferences backup first'
    # Must use subprocess instead of CapturePrefs.run(operation: 'export'):
    # capture-prefs.rb has at_exit hooks that must fire immediately after
    # the export completes (resume softwareupdate schedule), not at the end
    # of fresh-install. Subprocess isolation ensures independent lifecycle.
    #
    # Export auto-commits inside capture-prefs.rb (uses smart_commit) -- no separate
    # commit needed here.
    if CommandUtils.run_interactive({ 'COLUMNS' => EnvVars.columns.to_s }, RbConfig.ruby, capture_prefs.to_s, '-e')
      Logging.success 'Successfully refreshed and committed preferences backup'
    else
      Logging.record_warning 'Failed to refresh backup -- will attempt import with existing backup'
    end
  end

  # Sets Homebrew's zsh as the default login shell (see DefaultShell). Done at the end to avoid a
  # password prompt mid-script.
  def _set_default_shell
    Logging.with_step('Set default shell', _numbered_step_label('Setting default shell to Homebrew zsh')) do
      DefaultShell.run
    end
  end

  private_class_method :_install, :_numbered_step_label, :_cache_bust_headers, :_curl_download, :_load_zsh_configs, :_setup_jio_dns, :_resolve_gh_username, :_resolve_dotfiles_branch, :_download_and_source_shellrc, :_recompile_zsh_startup_files, :_restore_shellrc_after_install_dotfiles, :_clone_dot_files_repo, :_install_homebrew, :_resurrect_bootstrap_repos, :_baseline_preferences, :_refresh_preferences_backup, :_set_default_shell
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  CliParser.parse('') do |opts|
    opts.separator 'Idempotent macOS fresh-install and re-configuration script.'
    opts.separator 'Works on a vanilla macOS and on a pre-configured machine without errors.'
  end

  success = false
  # run prints the completion message on success; run_script then prints the grouped
  # warnings/errors and the duration, in that order.
  Logging.run_script { success = FreshInstallOfOsx.run }
  FreshInstallOfOsx.report_outcome(success: success)
  exit(success ? 0 : 1)
end
