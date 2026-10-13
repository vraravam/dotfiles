#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'core'

require_relative 'env_vars'
require_relative 'git_processor'
require_relative 'logging'
require_relative 'path_utils'

# Profiles repository management: session backup pruning and size checks.
# These operations are specific to the PERSONAL_PROFILES_DIR repository
# structure and are extracted from software-updates-cron.rb.
module ProfilesRepo
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Note: Logging methods must be qualified (Logging.debug, Logging.success, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # Date part of a session backup file name (zen-sessions-YYYY-MM-DD-HH.jsonlz4).
  BACKUP_DATE = /\Azen-sessions-(\d{4}-\d{2}-\d{2})/.freeze

  # Paths per 'git rm --cached' call, keeping the command line far below the OS argument limit.
  RM_BATCH_SIZE = 500

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Query methods (read-only state inspection)
  # ---------------------------------------------------------------------------

  # Memoized GitProcessor for the profiles repo (shared by every method that operates on it).
  #
  # @return [GitProcessor]
  def _profiles_git
    @_profiles_git ||= GitProcessor.new(dir: EnvVars::PERSONAL_PROFILES_DIR)
  end

  private_class_method :_profiles_git

  # Checks the pack size of the profiles repo and records an error if it exceeds
  # the specified limit. Suggests running recreate-repository.rb when the threshold
  # is breached.
  #
  # Uses GitProcessor#pack_size_* for 2-3x faster measurement (~10-20ms vs ~50ms).
  # Note: Measures pack size only, which is typically 70-90% of total .git size.
  #
  # @param limit_gb [Integer] Size limit in gigabytes (default: 2)
  # @return [void]
  def check_size_limit(limit_gb: 2)
    profiles_dir = EnvVars::PERSONAL_PROFILES_DIR

    unless GitProcessor.repo?(profiles_dir)
      Logging.debug "Skipping size check -- '#{profiles_dir.cyan}' is not a git repo"
      return
    end

    limit_mb = limit_gb * 1024

    if _profiles_git.pack_size_mb > limit_mb
      size_human = _profiles_git.pack_size_human
      Logging.record_error(
        "Profiles repo pack size is #{size_human} -- exceeds #{limit_gb}GB threshold. " \
        "Consider running: recreate-repository.rb -d \"#{profiles_dir.cyan}\""
      )
    else
      Logging.debug "Profiles repo pack size within #{limit_gb.to_s.purple}GB threshold"
    end
  end

  # Finds all chrome folders in browser profiles under PERSONAL_PROFILES_DIR.
  # Chrome folders are located at *Profile/Profiles/*Profile/chrome.
  # Returns only directories, not files.
  #
  # @return [Array<Pathname>] Array of chrome folder paths as Pathname objects
  def find_chrome_folders
    chrome_folders = []
    chrome_pattern = EnvVars::PERSONAL_PROFILES_DIR.join('*Profile', 'Profiles', '*Profile', 'chrome')
    PathUtils.glob_pathnames(chrome_pattern) do |path_pn|
      chrome_folders << path_pn if path_pn.directory? && GitProcessor.repo?(path_pn)
    end
    chrome_folders
  end

  # ---------------------------------------------------------------------------
  # Mutation methods (modify state)
  # ---------------------------------------------------------------------------

  # Note: Logging methods must be qualified (Logging.debug, Logging.success, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # Captures current state of profiles repo and commits with timestamp.
  # Used by software-updates-cron to snapshot browser profiles periodically.
  #
  # @return [Boolean] true if successful, false if repo is invalid or commit fails
  def capture_and_commit
    profiles_dir = EnvVars::PERSONAL_PROFILES_DIR

    unless GitProcessor.repo?(profiles_dir)
      Logging.warn "Skipping profiles repo update -- '#{profiles_dir.cyan}' is not a git repo"
      return false
    end

    Logging.debug "Updating profiles repo at '#{profiles_dir.cyan}'"

    _profiles_git.commit_all
  rescue RuntimeError => e
    # Git operations may raise RuntimeError on failures
    Logging.warn "Skipping profiles repo update -- #{e.message}"
    false
  end

  # Prunes session backup files older than the specified number of days.
  # Only tracked files matching the zen-sessions-backup pattern are considered.
  # Uses `git rm --cached` to unpin old backups from the index without deleting
  # the working tree files.
  #
  # @param days [Integer] Age threshold in days (default: 7)
  # @return [void]
  def prune_old_session_backups(days: 7)
    profiles_dir = EnvVars::PERSONAL_PROFILES_DIR

    unless GitProcessor.repo?(profiles_dir)
      Logging.debug "Skipping session backup pruning -- '#{profiles_dir.cyan}' is not a git repo"
      return
    end

    cutoff = (Time.now - days * 24 * 3600).strftime('%Y-%m-%d')

    git = _profiles_git
    tracked = git.ls_files('*/zen-sessions-backup/zen-sessions-*.jsonlz4')

    # Backups are named zen-sessions-YYYY-MM-DD-HH.jsonlz4; ISO dates compare as strings.
    old_backups = tracked.select do |tracked_file|
      date = BACKUP_DATE.match(File.basename(tracked_file))
      date && date[1] < cutoff
    end

    if nil_or_empty?(old_backups)
      Logging.debug 'No old session backups to prune'
      return
    end

    pruned_count = 0
    old_backups.each_slice(RM_BATCH_SIZE) do |batch|
      # One 'git rm --cached' per batch instead of one process per file
      _stdout, stderr, status = git.rm_cached(batch, quiet: true)
      unless status.success?
        Logging.record_warning("Failed to unpin #{batch.length.to_s.purple} old session backup(s): #{stderr.to_s.strip.lines.first}")
        next
      end

      batch.each { |f| Logging.debug "Unpinned old session backup: #{f.yellow}" }
      pruned_count += batch.length
    end

    Logging.success "Pruned #{pruned_count.to_s.purple} session backup file(s) older than #{days.to_s.purple} days" if pruned_count.positive?
  end

  # Finds and updates all browser profile chrome folders that are git repositories.
  # Chrome folders are expected at: PERSONAL_PROFILES_DIR/*Profile/Profiles/*Profile/chrome
  # Each chrome folder is updated via `git pull -r` if it's a valid git repo.
  #
  # @return [void]
  def update_chrome_folders
    profiles_dir = EnvVars::PERSONAL_PROFILES_DIR

    unless profiles_dir.directory?
      Logging.debug "Skipping chrome folder update -- PERSONAL_PROFILES_DIR not found: '#{profiles_dir.cyan}'"
      return
    end

    chrome_folders = find_chrome_folders
    return if nil_or_empty?(chrome_folders)

    chrome_folders.each do |folder_pn|
      folder_pn_colored = folder_pn.cyan

      Logging.with_step("update chrome #{folder_pn.basename}", "#{'Updating chrome folder:'.yellow} '#{folder_pn_colored}'") do
        status = nil
        GitProcessor.new(dir: folder_pn) { |git| _stdout, _stderr, status = git.pull }
        if status.success?
          Logging.success "Successfully updated: '#{folder_pn_colored}'"
        else
          Logging.record_warning("Failed to update chrome folder: '#{folder_pn_colored}'")
        end
      end
    end

    Logging.success 'Finished updating chrome folders'
  end
end
