# frozen_string_literal: true

require 'fileutils'
require 'open3'

require_relative 'env_vars'
require_relative 'logging'

# Cron management helpers that replicate the shell functions split across
# .shellrc (suspend_cron, resume_cron, restore_cron) and .aliases
# (_create_crontab, recron, with_cron_suspended).
#
# The split between .shellrc and .aliases exists for bootstrap reasons: shell
# needs suspend_cron before the dotfiles repo is cloned. Ruby scripts never
# have that constraint — the full interface lives here.
module Cron
  extend self

  # Note: Logging methods must be qualified (Logging.debug, Logging.info, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # The canonical crontab.txt file path. This is the source of truth for the
  # user's cron schedule, stored in PERSONAL_CONFIGS_DIR.
  CRONTAB_FILE = EnvVars::PERSONAL_CONFIGS_DIR.join('crontab.txt').to_s.freeze

  # ---------------------------------------------------------------------------
  # Core primitives (mirror .shellrc § 1h)
  # ---------------------------------------------------------------------------

  # Loads +cron_file+ into the system crontab via `crontab <file>`.
  # Warns and returns early if the file does not exist.
  # Mirrors restore_cron in .shellrc.
  def restore_cron(cron_file)
    unless File.file?(cron_file)
      Logging.warn "No '#{cron_file}' found; returning without any processing"
      return
    end
    FileUtils.mkdir_p(File.dirname(cron_file))
    raise "Failed to restore crontab from '#{cron_file}'" unless system('crontab', cron_file)
  end

  # Backs up the current crontab to the path in ENV['_DOTFILES_CRON_BACKUP_FILE']
  # and removes all cron jobs. On a first-install where no crontab exists yet,
  # seeds the backup from crontab.txt (if present) so resume_cron can restore a
  # known-good state. Mirrors suspend_cron in .shellrc.
  def suspend_cron
    Logging.debug 'Suspending cron jobs...'
    backup_file = cron_backup_file
    src_file = CRONTAB_FILE

    # Attempt to capture the active crontab into the backup file.
    crontab_output, _err, cron_status = Open3.capture3('crontab', '-l')
    if cron_status.success? && !crontab_output.empty?
      File.write(backup_file, crontab_output)
      Logging.debug "Backed up existing crontab to '#{backup_file}'"
    elsif File.file?(src_file)
      # No active crontab (e.g. FIRST_INSTALL) but a known-good crontab.txt exists.
      FileUtils.cp(src_file, backup_file)
      Logging.debug "Seeded cron backup from '#{src_file}'"
    else
      File.write(backup_file, '')
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
    backup_file = cron_backup_file
    if File.file?(backup_file) && File.size(backup_file) > 0
      restore_cron(backup_file)
      Logging.success 'Cron jobs resumed from backup'
    else
      Logging.info 'No cron backup to restore; skipping'
    end
    File.delete(backup_file) if File.exist?(backup_file)
  end

  # ---------------------------------------------------------------------------
  # Higher-level helpers (mirror .aliases § 3j)
  # ---------------------------------------------------------------------------

  # Seeds +file+ with the standard crontab header and the software-updates-cron
  # schedule. Called by recron only when crontab.txt does not already exist
  # (bootstrap / first-install path). Mirrors _create_crontab in .aliases.
  def create_crontab(file)
    shell = ENV.fetch('SHELL', '/bin/zsh')
    username = ENV.fetch('USERNAME', ENV.fetch('USER', ''))

    # PATH line must have no inline comment — crontab treats '#' as part of the
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

    cron_cmd = EnvVars::DOTFILES_DIR.join('scripts', 'software-updates-cron.sh').to_s
    log_file = EnvVars::HOME.join('software-updates-cron.log').to_s

    File.open(file, 'w') do |f|
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
             '(needed for chronic, run-all.rb, capture-prefs.sh etc.)'
      f.puts "PATH=#{path}"
      f.puts
      f.puts "# Note: Need to use the full path to scripts inside the sub-shell since that's not a logged-in shell"
      # Wrap with zsh -c so tee is inside chronic's scope — chronic must see both
      # the shell script and tee together to suppress output on success.
      f.puts "0   *   *   *   *   chronic zsh -c '#{cron_cmd} 2>&1 | tee -a #{log_file}'"
    end
  end

  # Loads the system crontab from ${PERSONAL_CONFIGS_DIR}/crontab.txt.
  # If crontab.txt does not exist yet (bootstrap / first-install), seeds it
  # first via create_crontab so there is always a known-good file on disk.
  # Edit crontab.txt directly to change the schedule; recron will pick it up.
  # Mirrors recron in .aliases.
  def recron
    Logging.debug 'Setting up crontab'
    unless File.file?(CRONTAB_FILE)
      Logging.debug "'#{CRONTAB_FILE}' not found — seeding from template"
      create_crontab(CRONTAB_FILE)
    end
    restore_cron(CRONTAB_FILE)
    Logging.success 'Crontab set up successfully'
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
      backup = cron_backup_file
      File.delete(backup) if File.exist?(backup)
    rescue StandardError
      resume_cron
      raise
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  private

  # The path to the temporary crontab backup file. Written by suspend_cron,
  # read by resume_cron, and deleted by recron / resume_cron on success.
  # Mirrors _DOTFILES_CRON_BACKUP_FILE in .shellrc, which sets this var
  # internally — Ruby scripts may not have sourced .shellrc, so fall back to
  # the same default path the shell function uses.
  def cron_backup_file
    ENV.fetch('_DOTFILES_CRON_BACKUP_FILE') do
      File.join(ENV.fetch('TMPDIR', '/tmp'), 'crontab_backup')
    end
  end
end
