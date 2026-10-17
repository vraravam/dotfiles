#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative '../capture-prefs'
require_relative 'background_job'
require_relative 'command_utils'
require_relative 'core'
require_relative 'env_vars'
require_relative 'git_processor'
require_relative 'logging'
require_relative 'macos'

# The 'Restore preferences' step of the machine setup: baselines the macOS defaults
# (osx-defaults.sh -s), then restores the application preferences from the backup
# (capture-prefs.rb). fresh-install-of-osx.sh calls it through call-utility.rb once the dotfiles
# repository is cloned; Ruby callers can use it directly.
#
# One bracket around both operations (DOTFILES_APPS_BRACKETED=1 is what tells osx-defaults.sh and
# CapturePrefs that it exists): the software-update schedule is suspended and the login-item apps
# are stopped once before, and one reload of the macOS preference services plus the restart of the
# apps and the schedule happen once after. Neither child brackets on its own then.
#
# On a first install the baseline can run in the background from right after install-dotfiles
# (#start_baseline_in_background -- it needs the repository and sudo, not Homebrew and not the
# home repo) while Homebrew and the clones proceed; #run then waits for it before restoring the
# backup, which needs the baseline done and the home repo cloned. Its output goes to a log file
# whose summary is replayed when it is joined, and a failure is recorded as an issue. Opt out with
# FRESH_INSTALL_SERIAL_DEFAULTS=1.
#
# On a pre-configured machine the step either refreshes the backup from the machine (export and
# commit) or, when the backup in the home repo is newer than anything this machine exported,
# imports it -- see #_restore for why those two are alternatives and never both.
#
# capture-prefs runs in-process (CapturePrefs.run); osx-defaults.sh stays a subprocess, being a
# shell script.
module PreferencesRestore
  extend self

  # Where the background baseline's output goes.
  BASELINE_LOG = EnvVars::DOWNLOADS.join('osx-defaults-baseline.log').freeze

  # Longest the baseline is waited for (it normally takes a few minutes), the seconds between
  # checks and between progress lines, and the number of log lines replayed as its summary.
  BASELINE_TIMEOUT = 30 * 60
  BASELINE_POLL = 1
  BASELINE_TICK = 60
  BASELINE_SUMMARY_LINES = 30

  # Env var that tells the children the bracket is already in place.
  BRACKETED_ENV = { 'DOTFILES_APPS_BRACKETED' => '1' }.freeze

  # Public API method.
  #
  # A failing sub-step never stops the rest of the setup: it is recorded and the next one runs.
  #
  # @param first_install [Boolean] True on a vanilla macOS, where there is no backup to refresh.
  #   Defaults to FIRST_INSTALL from the environment.
  # @return [Boolean] false when any sub-step failed or osx-defaults.sh was missing; each is recorded.
  def run(first_install: EnvVars.first_install?)
    Logging.run_script_result('preferences_restore', 'Restoring preferences') do
      _begin_bracket
      baselined = _baseline
      restored = _restore(first_install)
      baselined && restored
    ensure
      _end_bracket
    end
  end

  # Starts the baseline in the background (see the module comment), opening the bracket first.
  # Does nothing, and returns false so the caller carries on as before (#run then baselines in
  # the foreground), when FRESH_INSTALL_SERIAL_DEFAULTS is set, osx-defaults.sh is missing, or
  # sudo credentials are not cached: a background job cannot ask for the password without
  # fighting the foreground steps for the terminal.
  #
  # @return [Boolean] true when the baseline is now running in the background
  def start_baseline_in_background
    return false if @baseline_job || EnvVars.set?('FRESH_INSTALL_SERIAL_DEFAULTS')

    script = _script('osx-defaults.sh')
    return false unless script.file?

    unless CommandUtils.run_silent('sudo', '-n', 'true')
      Logging.info 'sudo credentials are not cached -- the macOS defaults baseline will run in the foreground'
      return false
    end

    _begin_bracket
    BASELINE_LOG.delete if BASELINE_LOG.file?
    @baseline_job = BackgroundJob.start(BRACKETED_ENV, script.to_s, '-s', log: BASELINE_LOG)
    unless @baseline_job
      _end_bracket
      return false
    end

    Logging.info "Baselining the macOS defaults in the background (log: '#{BASELINE_LOG.cyan}'); it is joined before the preferences are restored"
    true
  end

  # Cleans up when the run stops before #run was reached: waits for the background baseline (it
  # must not be left half-way through its writes) and closes the bracket. A no-op otherwise.
  #
  # @return [void]
  def finish_pending
    _join_baseline if @baseline_job
    _end_bracket
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  # Opens the bracket once: suspends the software-update schedule and, interactively only (a
  # killall would disrupt a user's session otherwise), stops the login-item apps so they cannot
  # overwrite what is written when they quit.
  #
  # @return [void]
  def _begin_bracket
    return if @bracket_open

    MacOS.suspend_softwareupdate_schedule
    @apps_stopped = Core.running_in_tty?
    MacOS.kill_login_item_apps if @apps_stopped
    @bracket_open = true
  end

  # Closes the bracket (a no-op when it is not open): one reload so everything written takes
  # effect, then the apps, then the schedule -- the reverse of the set-up.
  #
  # @return [void]
  def _end_bracket
    return unless @bracket_open

    @bracket_open = false
    begin
      MacOS.reload_macos_prefs
    ensure
      MacOS.restart_login_item_apps if @apps_stopped
      MacOS.resume_softwareupdate_schedule
    end
  end

  # @return [Boolean]
  def _baseline
    return _join_baseline if @baseline_job

    script = _script('osx-defaults.sh')
    unless script.file?
      Logging.record_error "osx-defaults.sh not found at '#{script.to_s.cyan}' -- baseline preferences manually and follow it up with a re-import of the backed-up preferences"
      return false
    end

    # A shell script: run through its own shebang, not the Ruby interpreter.
    unless CommandUtils.run_interactive(BRACKETED_ENV, script.to_s, '-s')
      Logging.record_error "osx-defaults.sh exited non-zero -- baseline preferences manually: #{script.to_s.cyan}"
      return false
    end

    Logging.success 'Successfully baselined preferences'
    true
  end

  # Waits for the background baseline, replays the end of its log as the summary and records a
  # failure (non-zero exit, or a timeout after which it is stopped).
  #
  # @return [Boolean]
  def _join_baseline
    job = @baseline_job
    @baseline_job = nil
    Logging.info "Waiting for the macOS defaults baseline that runs in the background (log: '#{job.log.cyan}')" if BackgroundJob.running?(job)

    status = BackgroundJob.wait(job, timeout: BASELINE_TIMEOUT, poll: BASELINE_POLL, tick: BASELINE_TICK) do |elapsed|
      Logging.info "Still baselining the macOS defaults (#{elapsed}s)"
    end

    if status.nil?
      BackgroundJob.terminate(job.pid)
      Logging.record_error "osx-defaults.sh did not finish within #{BASELINE_TIMEOUT / 60} minutes and was stopped -- baseline preferences manually: #{_script('osx-defaults.sh').to_s.cyan}"
      return false
    end

    _replay_summary(job.log)
    unless status.success?
      Logging.record_error "osx-defaults.sh exited non-zero (see '#{job.log.cyan}') -- baseline preferences manually: #{_script('osx-defaults.sh').to_s.cyan}"
      return false
    end

    Logging.success 'Successfully baselined preferences'
    true
  end

  # Prints the end of the background run's log, which holds the script's own summary.
  #
  # @param log [Pathname]
  # @return [void]
  def _replay_summary(log)
    lines = BackgroundJob.tail(log, lines: BASELINE_SUMMARY_LINES)
    return if lines.empty?

    Logging.info "Summary of the macOS defaults baseline (full log: '#{log.cyan}'):"
    lines.each { |line| puts line }
  end

  # Restores the preferences from the backup.
  #
  # First install: import the backup on top of the baseline.
  #
  # Pre-configured machine -- the two directions are alternatives, never both:
  # - Exporting writes this machine's current values into the backup and commits them; importing
  #   straight afterwards would only write those same values back (`defaults import` merges, so it
  #   neither adds nor removes anything), so after a successful export the import is skipped.
  # - The export replaces the backup wholesale, though. When the backup in the home repo was
  #   committed after this machine's last export (it was pulled from another machine), exporting
  #   would overwrite those newer settings with this machine's older ones, so the backup is
  #   imported instead and left untouched.
  # - When this machine has never exported (no record of it), the backup's age is unknown and the
  #   long-standing behavior applies: refresh it from this machine.
  #
  # @param first_install [Boolean]
  # @return [Boolean]
  def _restore(first_install)
    return _import_backup if first_install

    if _backup_newer_than_last_export?
      Logging.info "The preferences backup in the home repo is newer than this machine's last export -- importing it instead of exporting over it"
      return _import_backup
    end

    return _import_backup(refreshed: false) unless _refresh_backup

    Logging.info 'Skipping the import: it would only write back the preferences that were just exported'
    true
  end

  # @param refreshed [Boolean] false when refreshing the backup failed first (the result is then false)
  # @return [Boolean]
  def _import_backup(refreshed: true)
    unless _capture_prefs('import')
      Logging.record_error "Importing the preferences failed -- import them manually: #{'capture-prefs.rb -i'.cyan}"
      return false
    end

    Logging.success 'Successfully restored preferences from backup'
    refreshed
  end

  # Exports and commits the current preferences on a pre-configured machine. The export
  # auto-commits inside CapturePrefs, so no separate commit is needed here.
  #
  # @return [Boolean] false when the refresh failed (the import then runs from the existing backup)
  def _refresh_backup
    Logging.info 'Pre-configured machine detected -- refreshing preferences backup first'
    if _capture_prefs('export')
      Logging.success 'Successfully refreshed and committed preferences backup'
      return true
    end

    Logging.record_warning 'Failed to refresh backup -- will attempt import with existing backup'
    false
  end

  # Whether the last commit touching the backup folder in the home repo is younger than this
  # machine's last export: it can then only have come from elsewhere. False whenever either time
  # is unknown.
  #
  # @return [Boolean]
  def _backup_newer_than_last_export?
    exported = CapturePrefs.last_export_time
    return false unless exported

    stdout, _stderr, status = GitProcessor.new(dir: EnvVars::HOME).run_alias('log', '-1', '--format=%ct', '--', CapturePrefs.defaults_dir.to_s, read_only: true)
    return false unless status.success? && stdout.strip.match?(/\A\d+\z/)

    Time.at(stdout.strip.to_i) > exported
  rescue StandardError => e
    Logging.debug "Could not compare the backup's age with the last export (#{e.message})"
    false
  end

  # Runs CapturePrefs in-process, inside the bracket (so it neither brackets nor reloads on its
  # own). An error it raises (Logging.error raises) is trapped and printed here, because a failing
  # preferences step must not stop the rest of the setup.
  #
  # @param operation [String] 'export' or 'import'
  # @return [Boolean]
  def _capture_prefs(operation)
    CapturePrefs.run(operation: operation, manage_apps: false)
  rescue StandardError => e
    Logging.warn "capture-prefs #{operation} failed: #{e.message}"
    false
  end

  # @param name [String]
  # @return [Pathname]
  def _script(name)
    EnvVars::DOTFILES_DIR.join('scripts', name)
  end

  private_class_method :_begin_bracket, :_end_bracket, :_baseline, :_join_baseline, :_replay_summary, :_restore,
                       :_import_backup, :_refresh_backup, :_backup_newer_than_last_export?, :_capture_prefs, :_script
end
