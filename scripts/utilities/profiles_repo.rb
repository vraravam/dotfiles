# frozen_string_literal: true

require 'open3'
require 'time'

require_relative 'env_vars'
require_relative 'git_processor'
require_relative 'logging'
require_relative 'path_utils'

# Profiles repository management: session backup pruning and size checks.
# These operations are specific to the PERSONAL_PROFILES_DIR repository
# structure and are extracted from software-updates-cron.rb.
module ProfilesRepo
  extend self

  # Note: Logging methods must be qualified (Logging.debug, Logging.success, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # Prunes session backup files older than the specified number of days.
  # Only tracked files matching the zen-sessions-backup pattern are considered.
  # Uses `git rm --cached` to unpin old backups from the index without deleting
  # the working tree files.
  #
  # @param days [Integer] Age threshold in days (default: 7)
  # @return [void]
  def prune_old_session_backups(days: 7)
    unless GitProcessor.repo?(EnvVars::PERSONAL_PROFILES_DIR)
      Logging.debug "Skipping session backup pruning -- '#{EnvVars::PERSONAL_PROFILES_DIR}' is not a git repo"
      return
    end

    cutoff = (Time.now - days * 24 * 3600).strftime('%Y-%m-%d')

    tracked_out, = Open3.capture3(
      'git', '-C', EnvVars::PERSONAL_PROFILES_DIR.to_s,
      'ls-files', '--', '*/zen-sessions-backup/zen-sessions-*.jsonlz4'
    )
    tracked = tracked_out.split("\n")

    old_backups = tracked.select do |tracked_file|
      basename = File.basename(tracked_file, '.*')  # strip .jsonlz4
      basename = File.basename(basename, '.*')      # strip potential second ext
      date_part = basename.sub('zen-sessions-', '').sub(/-\d{2}\z/, '')
      date_part < cutoff
    end

    if old_backups.empty?
      Logging.debug 'No old session backups to prune'
      return
    end

    old_backups.each do |f|
      system('git', '-C', EnvVars::PERSONAL_PROFILES_DIR.to_s, 'rm', '--cached', '-q', '--', f)
      Logging.debug "Unpinned old session backup: #{f.yellow}"
    end

    Logging.success "Pruned #{old_backups.length} session backup file(s) older than #{days} days"
  end

  # Checks the size of the profiles repo .git directory and records an error
  # if it exceeds the specified limit. Suggests running recreate-repo.rb when
  # the threshold is breached.
  #
  # @param limit_gb [Integer] Size limit in gigabytes (default: 2)
  # @return [void]
  def check_size_limit(limit_gb: 2)
    unless GitProcessor.repo?(EnvVars::PERSONAL_PROFILES_DIR)
      Logging.debug "Skipping size check -- '#{EnvVars::PERSONAL_PROFILES_DIR}' is not a git repo"
      return
    end

    git_dir = EnvVars::PERSONAL_PROFILES_DIR.join('.git')
    size_kb = PathUtils.dir_size_kb(git_dir)
    limit_kb = limit_gb * 1024 * 1024

    if size_kb > limit_kb
      size_human = PathUtils.dir_size_human(git_dir)
      Logging.record_error(
        "Profiles repo .git directory is #{size_human} -- exceeds #{limit_gb}GB threshold. " \
        "Consider running: recreate-repo.rb -d \"#{EnvVars::PERSONAL_PROFILES_DIR.to_s.cyan}\""
      )
    else
      Logging.debug "Profiles repo .git directory size within #{limit_gb}GB threshold"
    end
  end
end
