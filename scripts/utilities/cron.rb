# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'pathname'

require_relative 'env_vars'
require_relative 'logging'

# Cron management helpers that replicate the shell functions split across
# .shellrc (suspend_cron, resume_cron, restore_cron) and .aliases
# (create_crontab, recron, with_cron_suspended).
#
# The split between .shellrc and .aliases exists for bootstrap reasons: shell
# needs suspend_cron before the dotfiles repo is cloned. Ruby scripts never
# have that constraint -- the full interface lives here.
module Cron
  extend self

  # Note: Logging methods must be qualified (Logging.debug, Logging.info, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # The canonical crontab.txt file path. This is the source of truth for the
  # user's cron schedule, stored in PERSONAL_CONFIGS_DIR.
  CRONTAB_FILE = EnvVars::PERSONAL_CONFIGS_DIR.join('crontab.txt')

  # ---------------------------------------------------------------------------
  # Core primitives (mirror .shellrc § 1h)
  # ---------------------------------------------------------------------------

  # Loads +cron_file+ into the system crontab via `crontab <file>`.
  # Warns and returns early if the file does not exist.
  # Mirrors restore_cron in .shellrc.
  def restore_cron(cron_file)
    cron_file = Pathname.new(cron_file) unless cron_file.is_a?(Pathname)
    unless cron_file.file?
      Logging.warn "No '#{cron_file.to_s.cyan}' found; returning without any processing"
      return
    end
    cron_file.dirname.mkpath
    raise "Failed to restore crontab from '#{cron_file.to_s.cyan}'" unless system('crontab', cron_file.to_s)
  end

  # Backs up the current crontab to the path in ENV['_DOTFILES_CRON_BACKUP_FILE']
  # and removes all cron jobs. On a first-install where no crontab exists yet,
  # seeds the backup from crontab.txt (if present) so resume_cron can restore a
  # known-good state. Mirrors suspend_cron in .shellrc.
  def suspend_cron
    Logging.debug 'Suspending cron jobs...'
    backup_file = EnvVars.cron_backup_file
    src_file = CRONTAB_FILE

    # Attempt to capture the active crontab into the backup file.
    crontab_output, _err, cron_status = Open3.capture3('crontab', '-l')
    if cron_status.success? && !crontab_output.empty?
      backup_file.write(crontab_output)
      Logging.debug "Backed up existing crontab to '#{backup_file.to_s.cyan}'"
    elsif src_file.file?
      # No active crontab (e.g. FIRST_INSTALL) but a known-good crontab.txt exists.
      FileUtils.cp(src_file.to_s, backup_file.to_s)
      Logging.debug "Seeded cron backup from '#{src_file.to_s.cyan}'"
    else
      backup_file.write('')
      Logging.debug 'No existing crontab or crontab.txt; created empty backup'
    end

    system('crontab', '-r', out: File::NULL, err: File::NULL)
    Logging.success 'Cron jobs suspended'
  end

  # Restores the crontab from the backup written by suspend_cron and deletes
  # the backup file. If the backup is empty (genuine first-install with no prior
  # crontab.txt), does nothing. Mirrors resume_cron in .shellrc.
  def resume_cron
    Logging.debug 'Resuming cron jobs...'
    backup_file = EnvVars.cron_backup_file
    if backup_file.file? && !backup_file.empty?
      restore_cron(backup_file)
      Logging.success 'Cron jobs resumed from backup'
    else
      Logging.info 'No cron backup to restore; skipping'
    end
    backup_file.delete if backup_file.exist?
  end

  # ---------------------------------------------------------------------------
  # Higher-level helpers (mirror .aliases § 3j)
  # ---------------------------------------------------------------------------

  # Seeds +file+ with the standard crontab header and the software-updates-cron
  # schedule. Called by recron only when crontab.txt does not already exist
  # (bootstrap / first-install path). Mirrors create_crontab in .aliases.
  def create_crontab(file)
    shell = EnvVars::SHELL
    username = EnvVars::USER
    file = Pathname.new(file) unless file.is_a?(Pathname)

    # PATH line must have no inline comment -- crontab treats '#' as part of the
    # value, corrupting the last directory entry and causing 'command not found'.
    path = [
      EnvVars::HOMEBREW_PREFIX.join('bin').to_s,
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      '/usr/sbin',
      '/sbin',
      EnvVars::PERSONAL_BIN_DIR.to_s,
      EnvVars::DOTFILES_DIR.join('scripts').to_s
    ].join(':')

    cron_cmd = EnvVars::DOTFILES_DIR.join('scripts', 'software-updates-cron.rb')
    log_file = EnvVars::HOME.join('software-updates-cron.log')

    file.open(mode: 'w') do |f|
      f.puts '# Reference: https://crontab.guru/'
      f.puts
      f.puts "# Note: 'chronic' is a utility installed using 'moreutils' from homebrew " \
             'and is needed so that a successful run of any cron job does not cause a mail ' \
             'to get generated unless in case of error scenarios'
      f.puts
      f.puts '# Env'
      f.puts "SHELL=\"#{shell}\""
      f.puts "USERNAME=\"#{username}\""
      f.puts "HOME=\"#{EnvVars::HOME}\""
      f.puts '# PATH: homebrew + system utils + personal bin + dotfiles scripts ' \
             '(needed for chronic, run-all.rb, capture-prefs.rb etc.)'
      f.puts "PATH=#{path}"
      f.puts
      f.puts "# Note: Need to use the full path to scripts inside the sub-shell since that's not a logged-in shell"
      f.puts '# chronic suppresses output on success (exit 0), outputs everything on failure (exit non-zero).'
      f.puts '# Success runs write timestamp to ~/.software-updates-last-success for audit trail.'
      f.puts '# Check: cat ~/.software-updates-last-success to see last successful run.'
      f.puts "0   *   *   *   *   chronic ruby #{cron_cmd} 2>&1 | tee -a #{log_file}"
    end
  end

  # Loads the system crontab from ${PERSONAL_CONFIGS_DIR}/crontab.txt.
  # If crontab.txt does not exist yet (bootstrap / first-install), seeds it
  # first via create_crontab so there is always a known-good file on disk.
  # Edit crontab.txt directly to change the schedule; recron will pick it up.
  # Mirrors recron in .aliases.
  def recron
    # Only set script name and increment depth if we're at depth 0 (not yet
    # incremented by a caller). Shell wrappers don't increment, so standalone
    # calls start at 0. Nested Ruby calls will be at depth >= 1, so they skip
    # script name override and timing infrastructure entirely.
    current_depth = EnvVars.script_depth
    if current_depth.zero?
      Logging.script_name = 'recron'
      Logging.increment_script_depth
      script_start_time = Logging.print_script_start
    end

    Logging.debug 'Setting up crontab'
    unless CRONTAB_FILE.file?
      Logging.debug "'#{CRONTAB_FILE.to_s.cyan}' not found -- seeding from template"
      create_crontab(CRONTAB_FILE)
    end
    restore_cron(CRONTAB_FILE)
    Logging.success 'Crontab set up successfully'

    Logging.print_script_summary(script_start_time) if current_depth.zero?
  end

  # Wraps a block in the cron bracket: suspend cron, yield, call recron to
  # restore it, then clear the backup so any at_exit hook is a no-op.
  # Mirrors with_cron_suspended in .aliases. Restores cron via an ensure
  # clause so it always runs even if the block raises.
  #
  # @example
  #   Cron.with_cron_suspended { run_main_logic }
  def with_cron_suspended
    suspend_cron
    begin
      yield
      recron
      backup = EnvVars.cron_backup_file
      backup.delete if backup.exist?
    rescue StandardError
      resume_cron
      raise
    end
  end
end
