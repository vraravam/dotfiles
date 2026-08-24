#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'time'
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

  # Prunes session backup files older than the specified number of days.
  # Only tracked files matching the zen-sessions-backup pattern are considered.
  # Uses `git rm --cached` to unpin old backups from the index without deleting
  # the working tree files.
  #
  # @param days [Integer] Age threshold in days (default: 7)
  # @return [void]

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Query methods (read-only state inspection)
  # ---------------------------------------------------------------------------

  # Memoized profiles directory (used across all methods).
  # Returns the PERSONAL_PROFILES_DIR constant, cached after first access.
  #
  # @return [Pathname] Path to personal profiles directory
  def _profiles_dir
    @_profiles_dir ||= EnvVars::PERSONAL_PROFILES_DIR
  end
  private_class_method :_profiles_dir

  # Checks the pack size of the profiles repo and records an error if it exceeds
  # the specified limit. Suggests running recreate-repository.rb when the threshold
  # is breached.
  #
  # Uses git_repo_size_* for 2-3x faster measurement (~10-20ms vs ~50ms).
  # Note: Measures pack size only, which is typically 70-90% of total .git size.
  #
  # @param limit_gb [Integer] Size limit in gigabytes (default: 2)
  # @return [void]
  def check_size_limit(limit_gb: 2)
    unless GitProcessor.repo?(_profiles_dir)
      Logging.debug "Skipping size check -- '#{_profiles_dir}' is not a git repo"
      return
    end

    git_dir = _profiles_dir.join('.git')
    size_mb = PathUtils.git_repo_size_mb(git_dir)
    limit_mb = limit_gb * 1024

    if size_mb > limit_mb
      size_human = PathUtils.git_repo_size_human(git_dir)
      Logging.record_error(
        "Profiles repo pack size is #{size_human} -- exceeds #{limit_gb}GB threshold. " \
        "Consider running: recreate-repository.rb -d \"#{_profiles_dir.cyan}\""
      )
    else
      Logging.debug "Profiles repo pack size within #{limit_gb}GB threshold"
    end
  end

  # Finds all chrome folders in browser profiles under PERSONAL_PROFILES_DIR.
  # Chrome folders are located at *Profile/Profiles/DefaultProfile/chrome.
  # Returns only directories, not files.
  #
  # @return [Array<Pathname>] Array of chrome folder paths as Pathname objects
  def find_chrome_folders
    chrome_folders = []
    chrome_pattern = _profiles_dir.join('*Profile', 'Profiles', 'DefaultProfile', 'chrome')
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
    unless GitProcessor.repo?(_profiles_dir)
      Logging.warn "Skipping profiles repo update -- '#{_profiles_dir.cyan}' is not a git repo"
      return false
    end

    Logging.debug "Updating profiles repo at '#{_profiles_dir.cyan}'"

    # Clean up lock files and hooks
    index_lock = _profiles_dir.join('.git', 'index.lock')
    hooks_dir = _profiles_dir.join('.git', 'hooks')
    index_lock.delete if index_lock.file?
    hooks_dir.rmtree if hooks_dir.directory?

    # Stage and commit with timestamp (use block form for multiple operations)
    success = false
    GitProcessor.new(dir: _profiles_dir) do |git|
      git.add('.')
      success = git.smart_commit
    end
    success
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
    unless GitProcessor.repo?(_profiles_dir)
      Logging.debug "Skipping session backup pruning -- '#{_profiles_dir}' is not a git repo"
      return
    end

    cutoff = (Time.now - days * 24 * 3600).strftime('%Y-%m-%d')
    pruned_count = 0

    GitProcessor.new(dir: _profiles_dir) do |git|
      tracked = git.ls_files('*/zen-sessions-backup/zen-sessions-*.jsonlz4')

      old_backups = tracked.select do |tracked_file|
        tracked_path = Pathname.new(tracked_file)
        basename = tracked_path.basename('.*').to_s # strip .jsonlz4
        basename = Pathname.new(basename).basename('.*').to_s # strip potential second ext
        date_part = basename.sub('zen-sessions-', '').sub(/-\d{2}\z/, '')
        date_part < cutoff
      end

      if nil_or_empty?(old_backups)
        Logging.debug 'No old session backups to prune'
        # rubocop:disable Lint/NonLocalExitFromIterator
        return # Early exit from method (not from iterator) - false positive
        # rubocop:enable Lint/NonLocalExitFromIterator
      end

      old_backups.each do |f|
        git.rm_cached(f, quiet: true)
        Logging.debug "Unpinned old session backup: #{f.yellow}"
      end

      pruned_count = old_backups.length
    end

    Logging.success "Pruned #{pruned_count} session backup file(s) older than #{days} days"
  end

  # Finds and updates all browser profile chrome folders that are git repositories.
  # Chrome folders are expected at: PERSONAL_PROFILES_DIR/*Profile/Profiles/DefaultProfile/chrome
  # Each chrome folder is updated via `git pull -r` if it's a valid git repo.
  #
  # @return [void]
  def update_chrome_folders
    unless _profiles_dir.directory?
      Logging.debug "Skipping chrome folder update -- PERSONAL_PROFILES_DIR not found: '#{_profiles_dir.cyan}'"
      return
    end

    chrome_folders = find_chrome_folders
    return if nil_or_empty?(chrome_folders)

    chrome_folders.each do |folder_pn|
      folder_pn_colored = folder_pn.cyan

      unless GitProcessor.repo?(folder_pn)
        Logging.debug "Skipping non-repo chrome folder: '#{folder_pn_colored}'"
        next
      end

      Logging.with_step("update chrome #{folder_pn.basename}", "#{'Updating chrome folder:'.yellow} '#{folder_pn_colored}'") do
        _stdout, _stderr, status = GitProcessor.new(dir: folder_pn).pull(rebase: true)
        if status.success?
          Logging.success "Successfully updated: '#{folder_pn_colored}'"
        else
          Logging.record_warning("Failed to update chrome folder: '#{folder_pn}'")
        end
      end
    end

    Logging.success 'Finished updating chrome folders'
  end
end
