#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'
require 'shellwords'

require_relative '../add-upstream-git-config'
require_relative '../install-dotfiles'
require_relative '../resurrect-repositories'
require_relative 'bootstrap_repos'
require_relative 'command_utils'
require_relative 'core'
require_relative 'cron'
require_relative 'default_shell'
require_relative 'env_vars'
require_relative 'git_processor'
require_relative 'gpg_encrypt'
require_relative 'homebrew_install'
require_relative 'keybase'
require_relative 'logging'
require_relative 'macos'
require_relative 'nix_bootstrap'
require_relative 'path_utils'
require_relative 'preferences_restore'
require_relative 'shellrc_check'
require_relative 'step_counter'

# Everything fresh-install-of-osx.sh does once the dotfiles repository has been cloned, as one Ruby
# process. The script itself stays shell because the steps before the clone (Xcode command-line
# tools, the clone itself) must run on a vanilla macOS with nothing but the OS; right after the
# clone it hands over by running
#   scripts/call-utility.rb --truthy FreshInstallPostClone.run --steps_done=N --start_time=EPOCH
# directly (not through the call_utility shell function, which lives in the very .shellrc that
# ShellrcCheck, this module's first step, verifies).
#
# What the shell passes on: the number of steps it already numbered, the epoch the whole run
# started at (for the closing duration line), COLUMNS, and -- through exported environment
# variables -- everything else (FIRST_INSTALL, the cron backup file, _DOTFILES_SCRIPT_DEPTH,
# _DOTFILES_ISSUES_FILE, ...). The issues the shell itself recorded before the hand-off are in the
# issues file (see Logging::Summary#adopt_issues_file), which is why the closing summary and
# notification are printed here, once, covering the whole run.
#
# Steps that need zsh functions (recompile_zsh_script, load_zsh_configs, delete_caches, compinit)
# run through 'zsh -c "source ~/.shellrc; ..."'. Nothing after the hand-off needs the shell's own
# environment to change, so the shell-only chores (re-sourcing .shellrc into the running shell,
# exporting Homebrew's environment) become changes to this process's ENV.
module FreshInstallPostClone
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Raised by a step that has already recorded why the run cannot continue, so 'run' returns false
  # without adding a second error message.
  Aborted = Class.new(StandardError)

  # Name used in issue prefixes and the summary; matches the shell script's own, so the issues the
  # shell recorded and the ones recorded here read alike.
  SCRIPT_NAME = 'fresh-install-of-osx.sh'

  FINISHED_MESSAGE = '** Finished auto installation process **'

  # Number of steps below that call '_step' -- keep in sync when adding or removing one. The shell
  # numbers its own steps before the hand-off, and passes how many (steps_done), so the total
  # shown in '[Step N of TOTAL]' is steps_done + POST_CLONE_STEPS. The Keybase, encrypted-backup and
  # tracked-repos phases print their own headers and are deliberately not numbered.
  POST_CLONE_STEPS = 10

  # Public API method.
  #
  # Cron was suspended (backed up and removed) by the shell when the whole run started. The 'Setup
  # cron jobs' step -- deliberately late, after the clones, so the hourly software-updates job cannot
  # fire during the long clone phase -- reinstalls the schedule and retires the backup on success;
  # otherwise the original schedule is restored from that backup before returning.
  #
  # @param steps_done [Integer, String] Steps the shell already numbered ('--key=value' arguments
  #   of call-utility.rb arrive as strings)
  # @param start_time [Integer, String, nil] Epoch the whole run started at, for the duration line
  # @return [Boolean] true if the installation ran to the end (recorded warnings/errors are shown in
  #   the summary and the notification), false if it was aborted.
  def run(steps_done: 0, start_time: nil)
    if EnvVars.script_depth.zero?
      ok = Logging.run_script_result(SCRIPT_NAME, FINISHED_MESSAGE) { _run(steps_done.to_i) }
    else
      # Run by the shell script, which owns the script banner and has already raised the depth:
      # print only the closing summary. The step lines' "Total" column counts from the shell's
      # start epoch (print_script_start, which sets it when Ruby is outermost, does not run here).
      Logging.state.script_start_time = _epoch(start_time)
      ok = _run(steps_done.to_i)
      Logging.script_name = SCRIPT_NAME
      Logging.print_script_summary(_epoch(start_time), FINISHED_MESSAGE)
    end
    _report_outcome(ok)
    ok
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  # @param steps_done [Integer]
  # @return [Boolean]
  def _run(steps_done)
    @steps = StepCounter.new(steps_done + POST_CLONE_STEPS, start_at: steps_done)
    @failure_message = nil
    Logging.script_name = SCRIPT_NAME
    Logging.adopt_issues_file
    _install
    true
  rescue Aborted
    false
  rescue StandardError => e
    # Last-resort handler: print directly via Kernel#warn (unconditional, never raises) rather
    # than Logging.error, which itself raises and would cause a second, unhandled exception here.
    msg = "Installation failed with unhandled exception: #{e.message}"
    msg += "\n  at #{e.backtrace.first}" if e.backtrace&.any?
    @failure_message = msg
    Kernel.warn "ERROR: #{msg}"
    false
  ensure
    # A run that stopped before the preferences step must not leave the background baseline
    # half-way through its writes or the apps stopped.
    _wrap_up_background_work
    # Issues that Ruby child processes started by a step (e.g. the post_clone commands of the
    # tracked repos) recorded join this process's own before the summary prints.
    Logging.merge_issues_file
    # Restores the original cron schedule unless the 'Setup cron jobs' step already reinstalled it
    # and deleted the backup (then there is nothing to restore).
    Cron.resume_cron if EnvVars.cron_backup_file.exist?
  end

  # The steps, in order.
  def _install
    _prepare_dotfiles_repo

    # On a first install: the curl-downloaded .shellrc must match the repo's, or GitHub's cache is stale.
    raise Aborted unless ShellrcCheck.matches_repo?

    _install_dotfiles
    _recompile_zsh_startup_files
    _restore_shellrc_after_install_dotfiles

    # ${XDG_CONFIG_HOME}/git/config is now symlinked, so core.sshCommand is in effect: stop
    # overriding it with the GIT_SSH_COMMAND the shell exported for the bootstrap.
    ENV.delete('GIT_SSH_COMMAND')

    # The macOS defaults baseline needs the repo and sudo, nothing that comes later, so on a first
    # install it runs in the background from here; the 'Restore preferences' step joins it.
    PreferencesRestore.start_baseline_in_background if EnvVars.first_install?

    # Now that the symlinks exist, load the zsh configs (caches, the antidote bundle).
    _load_zsh_configs

    _install_homebrew
    _install_nix
    _apply_nix_darwin_configuration
    _migrate_reftable

    # Coexist -- see KeybaseMigration.md.
    Logging.with_step('Setup Keybase', 'Setup Keybase') { Keybase.bootstrap_login }
    Logging.with_step('Setup encrypted backup', 'Setup encrypted backup') { GpgEncrypt.bootstrap_setup }

    _resurrect_bootstrap_repos

    old_known_hosts = EnvVars::HOME.join('.ssh', 'known_hosts.old')
    old_known_hosts.delete if old_known_hosts.file?

    _step('Restore preferences', 'Restore preferences') { PreferencesRestore.run }
    _recreate_zsh_completions
    _resurrect_tracked_repos

    # Only now: an hourly software-updates job firing during the clone phase would fight it (and
    # the detached unshallow batch) for the network and for Homebrew.
    _setup_cron_jobs
    _refresh_zsh_caches

    # Done last to avoid a password prompt in the middle of the unattended steps.
    _step('Set default shell', 'Setting default shell to nix-darwin zsh') { DefaultShell.run }
  end

  # Runs +block+ as the next numbered step: the header carries '[Step N of TOTAL]', the section name
  # (used to attribute issues in the summary) does not.
  #
  # @param section [String] Section name
  # @param label [String] Header text
  # @return [void]
  def _step(section, label, &block)
    Logging.with_step(section, "#{@steps.next_prefix}#{label}", &block)
  end

  # Runs +command+ in a zsh that has sourced ~/.shellrc, for the functions that exist only in zsh.
  #
  # @param command [String] Shell code, already escaped
  # @param env [Hash] Extra environment for the subprocess
  # @return [Boolean] true if it exited 0
  def _zsh(command, env = {})
    shellrc = EnvVars::HOME.join('.shellrc').to_s.shellescape
    CommandUtils.run_interactive(env, 'zsh', '-c', "source #{shellrc}; #{command}")
  end

  # @param value [Integer, String, nil]
  # @return [Integer, nil]
  def _epoch(value)
    nil_or_empty?(value.to_s) ? nil : value.to_i
  end

  # Puts the repo's scripts on PATH (appended, so they can never shadow a system command) -- needed
  # for add-upstream-git-config's 'git fo' -- and sets up the upstream remote, which points at the
  # repo this fork was derived from. Idempotent, and a no-op when 'upstream' already exists or the
  # origin's own owner matches UPSTREAM_GH_USERNAME.
  def _prepare_dotfiles_repo
    Logging.current_section = 'Clone dotfiles repo'
    PathUtils.append_to_path(EnvVars::DOTFILES_DIR.join('scripts'))
    upstream_ok = AddUpstreamGitConfig.run(dir: EnvVars::DOTFILES_DIR, upstream_owner: EnvVars::UPSTREAM_GH_USERNAME)
    Logging.record_warning 'Failed to add upstream git config for dotfiles repo' unless upstream_ok
  end

  # A failure is fatal: every later step depends on the symlinks install-dotfiles creates.
  def _install_dotfiles
    Logging.with_step('install-dotfiles', 'Running install-dotfiles') do
      next if InstallDotfiles.run

      Logging.record_error 'install-dotfiles encountered errors'
      raise Aborted
    end
  end

  # Force-checks and recompiles-if-needed the core startup files right now, as their own step --
  # not left to whatever recompiles them incidentally later: later steps (tracked-repos
  # resurrection) can run for tens of minutes, and correct bytecode right after install-dotfiles
  # re-creates the symlinks must not depend on reaching them. recompile_zsh_script no-ops when the
  # .zwc is current. The unconditional delete_caches at the end is still needed: a stale .zwc from
  # an earlier partial attempt can have a mtime that defeats the staleness check.
  def _recompile_zsh_startup_files
    core_files = [
      EnvVars::ZDOTDIR.join('.zshenv'),
      EnvVars::ZDOTDIR.join('.zshrc'),
      EnvVars::ZDOTDIR.join('.zlogin'),
      EnvVars::HOME.join('.shellrc'),
      EnvVars::ZDOTDIR.join('.aliases'),
    ]
    commands = core_files.map { |file| "recompile_zsh_script #{file.to_s.shellescape}" }.join('; ')
    Logging.record_warning 'Failed to recompile the zsh startup files -- they will be recompiled by the first new terminal' unless _zsh(commands)
  end

  # On a first install, install-dotfiles moves the curl-downloaded ~/.shellrc into the repo,
  # overwriting the committed version; restores the committed one so the symlink points at the
  # right content.
  def _restore_shellrc_after_install_dotfiles
    return unless EnvVars.first_install?

    relative = ShellrcCheck::REPO_SHELLRC_RELATIVE
    git = GitProcessor.new(dir: EnvVars::DOTFILES_DIR)
    _stdout, _stderr, status = git.run_alias('diff', '--quiet', '--', relative)
    return if status.success? # unchanged, nothing to restore

    git.run_alias('checkout', '--', relative)

    # Recompile again: the checkout changes .shellrc's content and mtime after the bulk recompile
    # ran, and a plain 'source' does not check .zwc staleness, so without this the validation below
    # could load bytecode compiled before the checkout. Then source the restored version to check
    # that it parses.
    shellrc = EnvVars::HOME.join('.shellrc').to_s.shellescape
    recompiled = _zsh("recompile_zsh_script #{shellrc}")
    valid = CommandUtils.run_interactive({ 'DEBUG' => 'true' }, 'zsh', '-c', "source #{shellrc}")
    Logging.record_warning 'The restored ~/.shellrc could not be recompiled or sourced -- check it' unless recompiled && valid
  end

  # Sources .zshenv, .zshrc and .zlogin (through .shellrc's load_zsh_configs) in a zsh subprocess so
  # their on-disk side effects happen now rather than lazily in the user's first terminal: the
  # brew/starship/compinit caches (which need the tools installed by the earlier steps) and the
  # antidote plugin bundle. The environment those files export cannot be handed back to this process.
  def _load_zsh_configs
    return if _zsh('load_zsh_configs', 'DEBUG' => 'true')

    Logging.record_warning 'Failed to load the zsh configs -- caches and the antidote bundle will be rebuilt by the first new terminal instead'
  end

  # Installing Homebrew itself is fatal when it fails (HomebrewInstall has recorded why). There is
  # no Brewfile step: nix-darwin's homebrew module drives 'brew bundle' during the switch below.
  def _install_homebrew
    prefix = EnvVars::HOMEBREW_PREFIX
    _step('Install Homebrew', "Installing homebrew into '#{prefix.to_s.cyan}'") do
      raise Aborted unless HomebrewInstall.run

      # Export Homebrew's environment into this process, so every later subprocess sees it.
      MacOS.load_brew_shellenv(prefix.join('bin', 'brew'))
    end
  end

  # Installing Nix is fatal when it fails: every package after this comes from it.
  def _install_nix
    _step('Install Nix', 'Installing Nix package manager') do
      raise Aborted unless NixBootstrap.install
    end
  end

  # Installs every nix package, applies the nix-eligible macOS defaults and installs the Homebrew
  # GUI casks, all in one 'darwin-rebuild switch'. A failure is recorded and the setup carries on.
  # The switch writes /etc/zshenv (adding nix-darwin's bin directories to PATH), so the zsh configs
  # are reloaded afterwards to pick that up.
  def _apply_nix_darwin_configuration
    _step('Apply nix-darwin configuration', 'Applying nix-darwin + home-manager configuration') do
      NixBootstrap.apply_configuration
      _load_zsh_configs
    end
  end

  # Migrates repos cloned before nix's git (2.45+) was on PATH: the system git on a vanilla
  # macOS ignores -c init.defaultRefFormat=reftable and has no 'git refs migrate', so the clone's
  # own migration call was a no-op for those early clones.
  def _migrate_reftable
    _step('Migrate repos to reftable', 'Migrating repos to reftable format') do
      GitProcessor.new(dir: EnvVars::DOTFILES_DIR) do |git|
        _stdout, _stderr, status = git.run_alias('migrate-reftable', stream: true)
        Logging.record_error "'#{'git migrate-reftable'.cyan}' failed for '#{EnvVars::DOTFILES_DIR.cyan}'" unless status.success?
      end
    end
  end

  # Clones/updates the home and browser-profiles repos (BootstrapRepos: Keybase login, bootstrap
  # config, ResurrectRepositories, early developer-environment setup), then reloads the zsh configs:
  # the home repo may just have brought in state this process has not seen yet, most notably
  # plugins.zsh (the antidote plugin bundle). If the cloned plugins.txt is newer than it,
  # regenerating the bundle now means the user's next terminal does not wait it out.
  def _resurrect_bootstrap_repos
    _step('Resurrect bootstrap repos', 'Cloning home/profiles repos') do
      BootstrapRepos.run
      _load_zsh_configs
    end
  end

  # A failure is ignored: the completions cache is non-critical.
  def _recreate_zsh_completions
    _step('Recreate zsh completions', 'Recreate zsh completions') do
      zcompdump = EnvVars::XDG_CACHE_HOME.join('zcompdump')
      PathUtils.glob_pathnames("#{zcompdump}*") { |file| file.rmtree if file.exist? }
      CommandUtils.run_silent('zsh', '-c', "autoload -Uz compinit && compinit -C -d #{zcompdump.to_s.shellescape}")
    end
  end

  # Reinstalls the schedule first; the backup is retired only once that worked (see
  # Cron.retire_backup, which keeps a differing original as '<name>.replaced'), so the 'ensure' in
  # '_run' can still restore the original schedule if it failed.
  def _setup_cron_jobs
    _step('Setup cron jobs', 'Setup cron jobs') do
      if Cron.recron
        Cron.retire_backup(EnvVars.cron_backup_file)
      else
        Logging.record_error 'recron failed -- original cron schedule preserved in backup'
      end
    rescue StandardError => e
      Logging.record_error "Failed to set up cron jobs: #{e.message} -- original cron schedule preserved in backup"
    end
  end

  # Resurrects every repo tracked in ${PERSONAL_CONFIGS_DIR}/repositories-*.yml, then runs the
  # developer-environment setup and regenerates the repo aliases (all inside
  # ResurrectRepositories.run(resurrect_all: true)). Runs synchronously: on a first install this can
  # legitimately take a while. Sets the section (no header) so issues are attributed to it.
  def _resurrect_tracked_repos
    Logging.current_section = 'Resurrect tracked repos'
    return if ResurrectRepositories.run(resurrect_all: true)

    Logging.record_warning "Failed to fully resurrect tracked repos -- see output above for details; re-run '#{'resurrect-repositories.rb -a'.cyan}' manually"
  end

  # Force-refreshes all zsh bytecode (*.zwc) and cache files. delete_caches (a shell function in
  # .aliases) deletes every *.zwc* file unconditionally and rebuilds from current source,
  # sidestepping the mtime comparison that a stale .zwc can defeat.
  def _refresh_zsh_caches
    _step('Refresh zsh bytecode caches', 'Refresh zsh bytecode caches') do
      aliases = EnvVars::ZDOTDIR.join('.aliases').to_s.shellescape
      next if _zsh("source #{aliases}; delete_caches")

      Logging.record_warning "Failed to run 'delete_caches' -- new terminals may load stale .zwc files until it is run manually"
    end
  end

  # Wraps up what steps started in the background and nothing else waits for, so the summary and the
  # notification can be truthful: the macOS defaults baseline is joined when the run stopped before
  # the preferences step.
  # Never raises (it runs from the 'ensure' of '_run').
  def _wrap_up_background_work
    PreferencesRestore.finish_pending
  rescue StandardError => e
    Kernel.warn "WARNING: could not wrap up the background work: #{e.message}"
  end

  # Process-level wrap-up, run after the summary has printed: the manual-step reminders (on
  # success) and exactly one notification, last, so the user sees the collected issues in the
  # terminal before the popup.
  #
  # @param success [Boolean] The result of the steps
  # @return [void]
  def _report_outcome(success)
    unless success
      MacOS.notify("[#{SCRIPT_NAME}] #{@failure_message || 'Installation failed. Check for error messages above.'}", '❌ Error')
      return
    end

    Logging.user_action 'Review System Settings manually: some settings (FileVault, accessibility permissions, notification preferences) require GUI interaction and cannot be automated due to TCC restrictions.'
    Logging.user_action "Repositories were cloned shallow (--depth=1) to save time and a background job is fetching their complete history. Once it has finished (check with '#{'git rev-parse --is-shallow-repository'.yellow}' in a repo), run '#{'git rebase @{u}'.yellow}' or '#{'git merge @{u}'.yellow}' in each repo to update working trees; in a NEW terminal (this one predates the updated PATH and aliases), '#{'all unshallow'.yellow}' finishes any repo that is still shallow." if EnvVars.first_install?

    issues = Logging.issue_summary_parts
    if issues.empty?
      MacOS.notify('Fresh install completed successfully.', '✅ Fresh Install Done')
    else
      MacOS.notify("Install done -- #{issues.join(' | ')}", issues.empty? ? 'Fresh Install' : '⚠️ Fresh Install')
    end
  end

  private_class_method :_run, :_install, :_step, :_zsh, :_epoch, :_prepare_dotfiles_repo, :_install_dotfiles,
                       :_recompile_zsh_startup_files, :_restore_shellrc_after_install_dotfiles, :_load_zsh_configs,
                       :_install_homebrew, :_migrate_reftable, :_resurrect_bootstrap_repos, :_recreate_zsh_completions,
                       :_setup_cron_jobs, :_resurrect_tracked_repos, :_refresh_zsh_caches, :_wrap_up_background_work, :_report_outcome
end
