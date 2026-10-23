#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'pathname'

require_relative 'core'
require_relative 'env_vars'
require_relative 'logging'
require_relative 'path_utils'

# Cron management helpers. The shell functions in .shellrc (suspend_cron, resume_cron,
# restore_cron) and .aliases (create_crontab, recron) are thin wrappers that call these
# methods through call_utility; the .shellrc ones keep a pure-shell fallback because shell
# needs suspend_cron before the dotfiles repo is cloned. Ruby scripts never have that
# constraint -- the full interface lives here, and with_cron_suspended exists only here.
# :reek:UtilityFunction -- Intentional stateless utility module design
module Cron
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Note: Logging methods must be qualified (Logging.debug, Logging.info, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # The canonical crontab.txt file path. This is the source of truth for the
  # user's cron schedule, stored in PERSONAL_CONFIGS_DIR.
  CRONTAB_FILE = EnvVars::PERSONAL_CONFIGS_DIR.join('crontab.txt')

  # ---------------------------------------------------------------------------
  # Core primitives (called by the .shellrc wrappers of the same names)
  # ---------------------------------------------------------------------------

  # Loads +cron_file+ into the system crontab via `crontab <file>`.
  # Warns and returns early if the file does not exist.
  # Validates crontab syntax before installation.
  # Called by the restore_cron shell wrapper in .shellrc.
  # Returns true on success, false on failure (logs error but does not raise).
  #
  # @param cron_file [String, Pathname] Path to crontab file
  # @return [Boolean] true on success, false on failure
  # :reek:FeatureEnvy -- Local variable tracks file path through validation steps
  def restore_cron(cron_file)
    cron_file = Pathname(cron_file)
    cron_file_str = cron_file.to_s
    cron_file_colored = cron_file_str.cyan

    unless file?(cron_file)
      Logging.warn "No '#{cron_file_colored}' found; returning without any processing"
      return false
    end

    # Validate syntax before attempting to install
    unless _valid_crontab?(cron_file)
      Logging.record_error "Invalid crontab syntax in '#{cron_file_colored}'"
      return false
    end

    PathUtils.ensure_directories_exist(cron_file.dirname)
    unless CommandUtils.run_silent('crontab', cron_file_str)
      Logging.record_error "Failed to restore crontab from '#{cron_file_colored}'"
      return false
    end
    true
  end

  # Backs up the current crontab to the path in ENV['_DOTFILES_CRON_BACKUP_FILE']
  # and removes all cron jobs. On a first-install where no crontab exists yet,
  # seeds the backup from crontab.txt (if present) so resume_cron can restore a
  # known-good state. Cleans up old backups (keeps last 5).
  # Called by the suspend_cron shell wrapper in .shellrc.
  #
  # @return [Boolean] true on success, false on failure
  # :reek:FeatureEnvy -- Local variable tracks backup file through multi-step workflow
  def suspend_cron
    Logging.debug 'Suspending cron jobs...'
    backup_file = EnvVars.cron_backup_file

    # Attempt to capture the active crontab into the backup file.
    # crontab -l fails (exit 1) when no crontab exists - use check_status to detect success
    crontab_output, stderr_str, status = Open3.capture3('crontab', '-l')
    success = CommandUtils.check_status(nil, stderr_str, status)

    if CommandUtils.dry_run?
      Logging.info "Would back up the crontab to '#{backup_file.cyan}'"
    else
      _save_backup(backup_file, success ? crontab_output : nil)
    end

    CommandUtils.run_silent('crontab', '-r')
    _cleanup_old_backups
    # In dry-run mode the commands above only logged; claiming success would be false.
    Logging.success 'Cron jobs suspended' unless CommandUtils.dry_run?
    true
  end

  # Restores the crontab from the backup written by suspend_cron and deletes
  # the backup file. If the backup is empty (genuine first-install with no prior
  # crontab.txt), does nothing. Called by the resume_cron shell wrapper in .shellrc.
  # :reek:FeatureEnvy -- Local variable tracks backup file through restoration steps
  def resume_cron
    Logging.debug 'Resuming cron jobs...'
    backup_file = EnvVars.cron_backup_file
    if CommandUtils.dry_run?
      # suspend_cron wrote no backup in dry-run mode, so there is nothing on disk to inspect.
      Logging.info "Would restore the crontab from the backup '#{backup_file.cyan}' and delete the backup"
      return
    end

    if backup_file.file? && !nil_or_empty?(backup_file)
      Logging.success 'Cron jobs resumed from backup' if restore_cron(backup_file)
      # Error already logged by restore_cron if it failed
    else
      Logging.info 'No cron backup to restore; skipping'
    end
    return unless backup_file.exist?

    unless PathUtils.safe_for_write?(backup_file)
      Logging.warn "Refusing to delete cron backup file in root directory: '#{backup_file.cyan}'"
      return
    end
    backup_file.delete
  end

  # ---------------------------------------------------------------------------
  # Higher-level helpers (called by the .aliases wrappers of the same names)
  # ---------------------------------------------------------------------------

  # Seeds +file+ with the standard crontab header and the software-updates-cron
  # schedule. Can be called manually via the shell wrapper to generate a template.
  # No longer called by recron (which now preserves existing crontabs and falls back
  # to tracked crontab.txt). Users who need a template can run:
  #   create_crontab ${PERSONAL_CONFIGS_DIR}/crontab.txt
  # Called by the create_crontab shell wrapper in .aliases.
  #
  # @param file [String, Pathname] Path to write the crontab template to
  def create_crontab(file)
    shell = EnvVars::SHELL
    username = EnvVars::USER
    home = EnvVars::HOME
    downloads = EnvVars::DOWNLOADS
    homebrew_prefix = EnvVars::HOMEBREW_PREFIX
    nix_profile_home = EnvVars::NIX_PROFILE_HOME
    personal_bin = EnvVars::PERSONAL_BIN_DIR
    personal_configs = EnvVars::PERSONAL_CONFIGS_DIR
    personal_profiles = EnvVars::PERSONAL_PROFILES_DIR
    dotfiles_dir = EnvVars::DOTFILES_DIR
    projects_base = EnvVars::PROJECTS_BASE_DIR

    file = Pathname(file)

    file.open(mode: 'w') do |f|
      f.puts '# Reference: https://crontab.guru/'
      f.puts
      f.puts '# Env'
      f.puts "SHELL=\"#{shell}\""
      f.puts "HOME=\"#{home}\""
      f.puts "USER=\"#{username}\""
      f.puts "HOMEBREW_PREFIX=\"#{homebrew_prefix}\""
      f.puts "NIX_PROFILE_HOME=\"#{nix_profile_home}\""
      f.puts "PERSONAL_BIN_DIR=\"#{personal_bin}\""
      f.puts "PERSONAL_CONFIGS_DIR=\"#{personal_configs}\""
      f.puts "PERSONAL_PROFILES_DIR=\"#{personal_profiles}\""
      f.puts "DOTFILES_DIR=\"#{dotfiles_dir}\""
      f.puts "PROJECTS_BASE_DIR=\"#{projects_base}\""
      f.puts '# Disable all mail generation from cron jobs (rely on macOS notifications instead)'
      f.puts 'MAILTO=""'
      f.puts '# Terminal width for Ruby logging (cron has no TTY, default 80 cols)'
      f.puts 'COLUMNS=80'
      f.puts '# PATH: nix profile + homebrew + system utils + personal bin + dotfiles scripts ' \
             '(needed for run-all.rb, capture-prefs.rb etc.)'
      # Cron does not expand ${VAR} references in environment variables -- use literal expanded paths
      f.puts "PATH=#{nix_profile_home}/bin:#{homebrew_prefix}/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:#{personal_bin}:#{dotfiles_dir}/scripts"
      f.puts
      f.puts "# Note: Need to use the full path to scripts inside the sub-shell since that's not a logged-in shell"
      f.puts '# MAILTO="" (above) disables all mail generation.'
      f.puts '# Wrapper script captures ALL output to temp file (~/Downloads/software-updates-cron-last-run.log).'
      f.puts '# Main log file only appended if exit code is non-zero (errors/warnings occurred).'
      f.puts '# Run history (STARTED/COMPLETED/FAILED) written to ~/Downloads/software-updates-run-log for audit trail.'
      f.puts '# Check: cat ~/Downloads/software-updates-run-log to see run history (start/completion/failure markers).'
      f.puts '# Check: cat ~/Downloads/software-updates-cron-last-run.log to see all output from last run (debugging).'
      f.puts '# Check: tail ~/Downloads/software-updates-cron.log to see error/warning output only.'
      # Use expanded paths (cron doesn't expand ${VAR} in command lines reliably)
      # Run every hour at minute 0
      # Temp log captures ALL output; main log only gets appended on errors/warnings
      f.puts "0 *   *   *   *   tmplog=#{downloads}/software-updates-cron-last-run.log; ruby #{dotfiles_dir}/scripts/software-updates-cron.rb 2>&1 | tee \"${tmplog}\"; exitcode=$?; [ \"${exitcode}\" -ne 0 ] && cat \"${tmplog}\" >> #{downloads}/software-updates-cron.log; exit \"${exitcode}\""
    end
  end

  # Restores crontab schedule using fallback logic:
  # 1. Capture existing system crontab to temp file (crontab -l)
  # 2. If empty -> fallback to ${PERSONAL_CONFIGS_DIR}/crontab.txt (tracked in repo)
  # 3. If that is missing or empty -> fallback to the backup suspend_cron wrote
  #    (_DOTFILES_CRON_BACKUP_FILE): during a fresh install the live crontab was removed by the
  #    suspend long before this runs, so step 1 is always empty there and the backup is the only
  #    copy of the user's original schedule
  # 4. If all are empty -> user_action to create schedule, don't modify system crontab
  # 5. If non-empty schedule found -> load it into system crontab
  #
  # This ensures:
  # - Existing cron jobs are preserved (don't overwrite user's custom schedules)
  # - Tracked crontab.txt is used as fallback on vanilla OS, and wins over the backup because it
  #   is the source of truth (see CRONTAB_FILE)
  # - The original schedule is never silently dropped when crontab.txt does not exist
  # - No default schedule imposed if user has neither
  #
  # Called by the recron shell wrapper in .aliases.
  #
  # @return [Boolean] false only when a schedule was found but could not be loaded into the
  #   system crontab; true when it was loaded or there was nothing to load.
  # :reek:FeatureEnvy -- Local variable manages temp file lifecycle through validation
  def recron
    Logging.run_script_result('recron') do
      loaded = true
      Logging.debug 'Setting up crontab'

      # Step 1: Capture existing system crontab to temp file
      require 'tempfile'
      temp_crontab = Tempfile.new(['crontab', '.txt'])
      begin
        # crontab -l exits 1 if no crontab exists; redirect stderr to suppress "no crontab" message
        # A read, so it goes through Open3 (not CommandUtils.run_silent) and really runs in dry-run mode.
        existing_crontab, = Open3.capture3('crontab', '-l')
        temp_crontab.write(existing_crontab)
        temp_crontab.close

        # Step 2: Check if temp file has content (existing crontab)
        crontab_file_colored = CRONTAB_FILE.cyan
        schedule_source = nil
        if temp_crontab.size.positive?
          Logging.debug "Found existing crontab with #{temp_crontab.size.to_s.purple} bytes"
          schedule_source = Pathname(temp_crontab.path)
        elsif _non_empty_file?(CRONTAB_FILE)
          # Step 2b: Fallback to tracked crontab.txt if it exists and is non-empty
          Logging.debug "No existing crontab; falling back to '#{crontab_file_colored}'"
          schedule_source = CRONTAB_FILE
        elsif _non_empty_file?(EnvVars.cron_backup_file)
          # Step 3: Fallback to the backup of the schedule that was running before the suspend
          Logging.info "No existing crontab and no '#{crontab_file_colored}'; restoring the schedule from the backup '#{EnvVars.cron_backup_file.cyan}'"
          schedule_source = EnvVars.cron_backup_file
        else
          # Step 4: Nothing anywhere - user action needed
          Logging.user_action "No crontab found and '#{crontab_file_colored}' does not exist. Create '#{crontab_file_colored}' with your desired schedule and run '#{'recron'.yellow}' to install it. Track the file in your home repo for backup."
        end

        # Step 5: Load non-empty schedule into system crontab
        if schedule_source
          loaded = restore_cron(schedule_source)
          Logging.success 'Crontab set up successfully' if loaded && !CommandUtils.dry_run?
          # Error already logged by restore_cron if it failed
        end
      ensure
        temp_crontab.unlink
      end
      loaded
    end
  end

  # Disposes of the cron backup once a crontab has been installed successfully (never call it
  # otherwise: until then the backup is the only copy of the original schedule). Deletes the
  # backup, unless it holds a schedule different from the one now installed (the tracked
  # crontab.txt won over it): then it is renamed to '<name>.replaced' instead, so the original is
  # still recoverable but resume_cron (which only looks at the exact backup name) can never put
  # it back over the new schedule.
  #
  # @param backup [Pathname, nil] The backup file; defaults to the suspend_cron backup.
  # @return [void]
  def retire_backup(backup = nil)
    backup ||= EnvVars.cron_backup_file
    return unless backup.exist?

    unless PathUtils.safe_for_write?(backup)
      Logging.warn "Refusing to delete cron backup file in root directory: '#{backup.cyan}'"
      return
    end

    installed = CommandUtils.query('crontab', '-l')
    original = backup.read(encoding: 'UTF-8')
    if nil_or_empty?(original) || original.strip == installed.strip
      if CommandUtils.dry_run?
        Logging.info "Would delete the cron backup '#{backup.cyan}'"
      else
        backup.delete
      end
    else
      kept = Pathname("#{backup}.replaced")
      if CommandUtils.dry_run?
        Logging.info "Would rename the cron backup '#{backup.cyan}' to '#{kept.cyan}' (it differs from the installed schedule)"
      else
        backup.rename(kept)
        Logging.info "The previous cron schedule differed from the one installed -- kept as '#{kept.cyan}'"
      end
    end
  end

  # Wraps a block in the cron bracket: suspend cron, yield, call recron to
  # restore it, then retire the backup (only if recron succeeded) so any at_exit hook is a no-op.
  # Restores cron via an ensure clause so it
  # always runs, regardless of how the block exits: a normal return, an exception, OR a
  # non-local 'return' from inside the block (e.g. 'return false unless x' in a caller
  # like recreate-repository.rb) -- confirmed empirically that a bare 'begin/rescue
  # StandardError' (this method's previous implementation) does NOT catch a non-local
  # return; only 'ensure' is guaranteed to run in that case, since a 'return' is Ruby
  # control flow, not a raised exception, and never touches the 'rescue' clause at all.
  #
  # In CommandUtils dry-run mode (see CommandUtils.with_dry_run) every step still runs but only
  # logs: each crontab command through CommandUtils, and each backup file write/delete through
  # its own dry-run check, so nothing is suspended, written or restored for real.
  #
  # @example
  #   Cron.with_cron_suspended { run_main_logic }
  #   CommandUtils.with_dry_run(true) { Cron.with_cron_suspended { run_main_logic } }
  def with_cron_suspended
    suspend_cron
    completed_normally = false
    begin
      yield
      completed_normally = true
    ensure
      # Deliberately no 'return' anywhere in this ensure clause (including inside the
      # methods it calls being inlined here) -- doing so would silently swallow an
      # in-flight exception instead of letting it propagate after cleanup, a classic
      # Ruby gotcha. _finish_cron_suspension_successfully is a separate method precisely
      # so its own internal 'return unless backup.exist?' can't accidentally end up
      # textually inside this ensure block.
      if completed_normally
        _finish_cron_suspension_successfully
      else
        resume_cron
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  private

  # Success path for with_cron_suspended: reinstalls the (possibly-updated) crontab and
  # cleans up the backup file -- but only if the reinstall succeeded, because the backup is then
  # the only copy of the original schedule. Split out from with_cron_suspended itself so its
  # early 'return unless backup.exist?' can never end up textually inside that method's
  # 'ensure' clause (see the safety note there).
  def _finish_cron_suspension_successfully
    backup = EnvVars.cron_backup_file
    unless recron
      Logging.warn "Could not reinstall the crontab -- keeping the backup of the original schedule: '#{backup.cyan}'"
      return
    end
    retire_backup(backup)
  end

  # @param path [Pathname]
  # @return [Boolean] whether +path+ is a regular file with content
  def _non_empty_file?(path)
    file?(path) && path.size.positive?
  end

  # Validates crontab syntax using crontab's built-in validation.
  # Attempts to install to system crontab without actually committing.
  # Uses a temporary test installation to validate syntax.
  #
  # @param file [Pathname] Crontab file to validate
  # @return [Boolean] true if valid, false if invalid
  # :reek:FeatureEnvy -- Validates file properties and content line-by-line
  def _valid_crontab?(file)
    # crontab command validates syntax automatically when loading a file.
    # To test without modifying the active crontab, we'd need to:
    # 1. Backup current crontab
    # 2. Try to install test file
    # 3. Restore original crontab
    # This is complex and racey. Instead, rely on crontab's exit code during actual install.
    # For now, just check the file is readable and non-empty.
    return false unless file.file? && file.readable?
    return false if file.size.zero?

    # Basic validation: check for obviously malformed lines
    # Valid lines: comments (#), env vars (KEY=value), or cron entries (5-7 fields)
    # Use Core.each_line_utf8 to avoid encoding issues in non-UTF-8 environments.
    Core.each_line_utf8(file) do |line|
      stripped = line.strip
      next if nil_or_empty?(stripped)
      next if stripped.start_with?('#')
      next if stripped =~ /^[A-Z_]+=.*/

      # Cron entry must have at least 6 fields (5 time fields + command)
      fields = stripped.split(/\s+/)
      return false if fields.size < 6
    end

    true
  end

  # Writes the cron backup: the active crontab when there is one, else a seed from the tracked
  # crontab.txt, else an empty file (so resume_cron has something to read).
  #
  # @param backup_file [Pathname] Where to write the backup
  # @param crontab_output [String, nil] The active crontab, nil when 'crontab -l' failed
  # @return [void]
  def _save_backup(backup_file, crontab_output)
    if !nil_or_empty?(crontab_output)
      backup_file.write(crontab_output)
      Logging.debug "Backed up existing crontab to '#{backup_file.cyan}'"
    elsif CRONTAB_FILE.file?
      # No active crontab (e.g. FIRST_INSTALL) but a known-good crontab.txt exists.
      IO.copy_stream(CRONTAB_FILE.to_s, backup_file.to_s)
      Logging.debug "Seeded cron backup from '#{CRONTAB_FILE.cyan}'"
    else
      backup_file.write('')
      Logging.debug 'No existing crontab or crontab.txt; created empty backup'
    end
  end

  # Removes old cron backup files, keeping only the 5 most recent.
  # Backup files follow pattern: ${TMPDIR}/crontab_backup*
  # Sorts by mtime (newest first) and deletes oldest.
  def _cleanup_old_backups
    backup_dir = EnvVars::TMPDIR
    pattern = backup_dir.join('crontab_backup*')
    backups = Dir.glob(pattern.to_s).map { |f| Pathname(f) }
                 .select(&:file?)
                 .sort_by(&:mtime)
                 .reverse

    return if backups.size <= 5

    backups[5..-1].each do |old_backup|
      next unless PathUtils.safe_for_write?(old_backup)

      if CommandUtils.dry_run?
        Logging.info "Would delete old cron backup: '#{old_backup.cyan}'"
        next
      end

      old_backup.delete
      Logging.debug "Deleted old cron backup: '#{old_backup.cyan}'"
    end
  end
end
