#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'pathname'

require_relative 'core'
require_relative 'env_vars'
require_relative 'logging'
require_relative 'path_utils'

# Cron management helpers that replicate the shell functions split across
# .shellrc (suspend_cron, resume_cron, restore_cron) and .aliases
# (create_crontab, recron, with_cron_suspended).
#
# The split between .shellrc and .aliases exists for bootstrap reasons: shell
# needs suspend_cron before the dotfiles repo is cloned. Ruby scripts never
# have that constraint -- the full interface lives here.
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
  # Core primitives (mirror .shellrc # 1h)
  # ---------------------------------------------------------------------------

  # Loads +cron_file+ into the system crontab via `crontab <file>`.
  # Warns and returns early if the file does not exist.
  # Validates crontab syntax before installation.
  # Mirrors restore_cron in .shellrc.
  # Returns true on success, false on failure (logs error but does not raise).
  #
  # @param cron_file [String, Pathname] Path to crontab file
  # @return [Boolean] true on success, false on failure
  # :reek:FeatureEnvy -- Local variable tracks file path through validation steps
  def restore_cron(cron_file)
    cron_file = Pathname.new(cron_file) unless cron_file.is_a?(Pathname)
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
  # Mirrors suspend_cron in .shellrc.
  #
  # @return [Boolean] true on success, false on failure
  # :reek:FeatureEnvy -- Local variable tracks backup file through multi-step workflow
  def suspend_cron
    Logging.debug 'Suspending cron jobs...'
    backup_file = EnvVars.cron_backup_file
    src_file = CRONTAB_FILE

    # Attempt to capture the active crontab into the backup file.
    # crontab -l fails (exit 1) when no crontab exists - use check_status to detect success
    crontab_output, stderr_str, status = Open3.capture3('crontab', '-l')
    success = CommandUtils.check_status(nil, stderr_str, status)

    if success && !nil_or_empty?(crontab_output)
      backup_file.write(crontab_output)
      Logging.debug "Backed up existing crontab to '#{backup_file.cyan}'"
    elsif src_file.file?
      # No active crontab (e.g. FIRST_INSTALL) but a known-good crontab.txt exists.
      FileUtils.cp(src_file.to_s, backup_file.to_s)
      Logging.debug "Seeded cron backup from '#{src_file.cyan}'"
    else
      backup_file.write('')
      Logging.debug 'No existing crontab or crontab.txt; created empty backup'
    end

    CommandUtils.run_silent('crontab', '-r')
    _cleanup_old_backups
    Logging.success 'Cron jobs suspended'
    true
  end

  # Restores the crontab from the backup written by suspend_cron and deletes
  # the backup file. If the backup is empty (genuine first-install with no prior
  # crontab.txt), does nothing. Mirrors resume_cron in .shellrc.
  # :reek:FeatureEnvy -- Local variable tracks backup file through restoration steps
  def resume_cron
    Logging.debug 'Resuming cron jobs...'
    backup_file = EnvVars.cron_backup_file
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
  # Higher-level helpers (mirror .aliases # 3j)
  # ---------------------------------------------------------------------------

  # Seeds +file+ with the standard crontab header and the software-updates-cron
  # schedule. Can be called manually via the shell wrapper to generate a template.
  # No longer called by recron (which now preserves existing crontabs and falls back
  # to tracked crontab.txt). Users who need a template can run:
  #   create_crontab ${PERSONAL_CONFIGS_DIR}/crontab.txt
  # Mirrors create_crontab in .aliases.
  def create_crontab(file)
    shell = EnvVars::SHELL
    username = EnvVars::USER
    home = EnvVars::HOME
    downloads = EnvVars::DOWNLOADS
    homebrew_prefix = EnvVars::HOMEBREW_PREFIX
    personal_bin = EnvVars::PERSONAL_BIN_DIR
    personal_configs = EnvVars::PERSONAL_CONFIGS_DIR
    personal_profiles = EnvVars::PERSONAL_PROFILES_DIR
    dotfiles_dir = EnvVars::DOTFILES_DIR
    projects_base = EnvVars::PROJECTS_BASE_DIR
    homebrew_bundle = EnvVars::HOMEBREW_BUNDLE_FILE

    file = Pathname.new(file) unless file.is_a?(Pathname)

    file.open(mode: 'w') do |f|
      f.puts '# Reference: https://crontab.guru/'
      f.puts
      f.puts '# Env'
      f.puts "SHELL=\"#{shell}\""
      f.puts "HOME=\"#{home}\""
      f.puts "USER=\"#{username}\""
      f.puts "HOMEBREW_PREFIX=\"#{homebrew_prefix}\""
      f.puts "PERSONAL_BIN_DIR=\"#{personal_bin}\""
      f.puts "PERSONAL_CONFIGS_DIR=\"#{personal_configs}\""
      f.puts "PERSONAL_PROFILES_DIR=\"#{personal_profiles}\""
      f.puts "DOTFILES_DIR=\"#{dotfiles_dir}\""
      f.puts "PROJECTS_BASE_DIR=\"#{projects_base}\""
      f.puts "HOMEBREW_BUNDLE_FILE=\"#{homebrew_bundle}\""
      f.puts "HOMEBREW_BUNDLE_FILE_GLOBAL=\"#{homebrew_bundle}\""
      f.puts '# Disable all mail generation from cron jobs (rely on macOS notifications instead)'
      f.puts 'MAILTO=""'
      f.puts '# Terminal width for Ruby logging (cron has no TTY, default 80 cols)'
      f.puts 'COLUMNS=80'
      f.puts '# PATH: homebrew + system utils + personal bin + dotfiles scripts ' \
             '(needed for run-all.rb, capture-prefs.rb etc.)'
      # Cron does not expand ${VAR} references in environment variables -- use literal expanded paths
      f.puts "PATH=#{homebrew_prefix}/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:#{personal_bin}:#{dotfiles_dir}/scripts"
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
      f.puts "0 *   *   *   *   tmplog=#{downloads}/software-updates-cron-last-run.log; ruby #{dotfiles_dir}/scripts/software-updates-cron.rb 2>&1 | tee \"${tmplog}\"; exitcode=$?; [ $exitcode -ne 0 ] && cat \"${tmplog}\" >> #{downloads}/software-updates-cron.log; exit $exitcode"
    end
  end

  # Restores crontab schedule using fallback logic:
  # 1. Capture existing system crontab to temp file (crontab -l)
  # 2. If empty -> fallback to ${PERSONAL_CONFIGS_DIR}/crontab.txt (tracked in repo)
  # 3. If both empty -> user_action to create schedule, don't modify system crontab
  # 4. If non-empty schedule found -> load it into system crontab
  #
  # This ensures:
  # - Existing cron jobs are preserved (don't overwrite user's custom schedules)
  # - Tracked crontab.txt is used as fallback on vanilla OS
  # - No default schedule imposed if user has neither
  #
  # Mirrors recron in .aliases.
  # :reek:FeatureEnvy -- Local variable manages temp file lifecycle through validation
  def recron
    Logging.run_script('recron') do
      Logging.debug 'Setting up crontab'

      # Step 1: Capture existing system crontab to temp file
      require 'tempfile'
      temp_crontab = Tempfile.new(['crontab', '.txt'])
      begin
        # crontab -l exits 1 if no crontab exists; redirect stderr to suppress "no crontab" message
        CommandUtils.run_silent('crontab', '-l', out: temp_crontab.path)
        temp_crontab.close

        # Step 2: Check if temp file has content (existing crontab)
        crontab_file_colored = CRONTAB_FILE.cyan
        schedule_source = nil
        if temp_crontab.size.positive?
          Logging.debug "Found existing crontab with #{temp_crontab.size} bytes"
          schedule_source = Pathname.new(temp_crontab.path)
        elsif file?(CRONTAB_FILE)
          # Step 2b: Fallback to tracked crontab.txt if it exists and is non-empty
          Logging.debug "No existing crontab; falling back to '#{crontab_file_colored}'"
          schedule_source = CRONTAB_FILE
        else
          # Step 3: Both empty - user action needed
          Logging.user_action "No crontab found and '#{crontab_file_colored}' does not exist. Create '#{crontab_file_colored}' with your desired schedule and run '#{'recron'.yellow}' to install it. Track the file in your home repo for backup."
        end

        # Step 4: Load non-empty schedule into system crontab
        Logging.success 'Crontab set up successfully' if schedule_source && restore_cron(schedule_source)
        # Error already logged by restore_cron if it failed
      ensure
        temp_crontab.unlink
      end
    end
  end

  # Wraps a block in the cron bracket: suspend cron, yield, call recron to
  # restore it, then clear the backup so any at_exit hook is a no-op.
  # Mirrors with_cron_suspended in .aliases. Restores cron via an ensure
  # clause so it always runs even if the block raises.
  #
  # @param dry_run [Boolean] When true, logs what would happen without suspending cron.
  # @example
  #   Cron.with_cron_suspended { run_main_logic }
  #   Cron.with_cron_suspended(dry_run: true) { run_main_logic }
  def with_cron_suspended(dry_run: false)
    if dry_run
      Logging.info 'Would suspend cron jobs'
      yield
      Logging.info 'Would resume cron jobs'
      return
    end

    suspend_cron
    begin
      yield
      recron
      backup = EnvVars.cron_backup_file
      if backup.exist?
        unless PathUtils.safe_for_write?(backup)
          Logging.warn "Refusing to delete cron backup file in root directory: '#{backup.cyan}'"
          return
        end
        backup.delete
      end
    rescue StandardError
      resume_cron
      raise
    end
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  private

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

  # Removes old cron backup files, keeping only the 5 most recent.
  # Backup files follow pattern: ${TMPDIR}/crontab_backup*
  # Sorts by mtime (newest first) and deletes oldest.
  def _cleanup_old_backups
    backup_dir = EnvVars::TMPDIR
    pattern = backup_dir.join('crontab_backup*')
    backups = Dir.glob(pattern.to_s).map { |f| Pathname.new(f) }
                 .select(&:file?)
                 .sort_by(&:mtime)
                 .reverse

    return if backups.size <= 5

    backups[5..-1].each do |old_backup|
      next unless PathUtils.safe_for_write?(old_backup)

      old_backup.delete
      Logging.debug "Deleted old cron backup: '#{old_backup.cyan}'"
    end
  end
end
