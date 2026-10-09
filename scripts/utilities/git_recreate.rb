#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'core'
require_relative 'logging'

class GitProcessor
  # The destructive "recreate the local repository" workflow (force-squash, ref-format
  # conversion), kept apart from the everyday git queries and mutations in GitProcessor.
  # Mixed into GitProcessor: relies on its @dir/@dry_run state and its public methods
  # (current_branch, each_remote, config_value, fetch_all, ls_tree, commit, ...).
  module Recreate
    include Core

    # Verifies that all required git metadata is present before recreation.
    # Logs the values and raises an error if any are missing.
    #
    # @param force [Boolean] Whether this is a force recreation (for logging)
    # @return [void]
    # @raise [RuntimeError] If any required metadata is missing
    def verify_pre_recreation(force:)
      git_url = remote_url
      user_name = config_value('user.name')
      user_email = config_value('user.email')
      branch = current_branch

      Logging.info "#{'Squash commits (will lose history!):'.yellow} #{force.to_s.orange}"
      Logging.info "#{'Dry run:'.yellow} #{@dry_run.to_s.orange}"
      Logging.info "#{'Repo url:'.yellow} '#{git_url.cyan}'"
      Logging.info "#{'User name:'.yellow} '#{user_name.cyan}'"
      Logging.info "#{'User email:'.yellow} '#{user_email.cyan}'"
      Logging.info "#{'Branch:'.yellow} '#{branch.cyan}'"

      Logging.error "One or more required git metadata values are missing for '#{@dir.cyan}' -- see above" if [git_url, user_name, user_email, branch].any? { |v| nil_or_empty?(v) }
    end

    # Recreates the local git repository with verification against remote.
    # Captures remote file list before recreation, recreates repo, stages/commits all files,
    # then verifies the new local matches the old remote before allowing remote deletion.
    #
    # This is the safe force-recreate workflow that prevents data loss.
    #
    # @return [Boolean] true if recreation and verification succeeded, false otherwise.
    def verify_and_recreate_local_repo
      # Capture current branch BEFORE destroying .git
      branch_name = current_branch
      return false if nil_or_empty?(branch_name)

      # Fetch from remote to ensure we have latest remote-tracking branches
      # (needed to capture remote file list before destroying .git)
      Logging.info 'Fetching from remote to capture file list...'
      _stdout, stderr, fetch_status = fetch_all
      unless fetch_status.success?
        Logging.record_error 'Failed to fetch from remote before recreation'
        Logging.record_error "Stderr: #{stderr}" unless nil_or_empty?(stderr)
        return false
      end

      # Capture remote file list BEFORE destroying local .git
      # (recreate removes .git which loses remote tracking refs)
      remote_ref = "origin/#{branch_name}"
      remote_files = ls_tree(remote_ref)

      if nil_or_empty?(remote_files)
        Logging.record_error "Failed to get file list from remote branch '#{remote_ref.cyan}' or remote is empty"
        Logging.user_action "Ensure remote branch '#{remote_ref.yellow}' exists and has been pushed"
        return false
      end

      # Recreate repo (automatically restores config and branch name)
      return false unless _recreate

      # Stage and commit all files in local repo
      Logging.info 'Staging all files in working directory...'
      _stdout, _stderr, stage_status = stage_all
      unless stage_status.success?
        Logging.record_error 'Failed to stage files after recreation'
        return false
      end

      # Check what was actually staged (might be nothing due to gitignore)
      staged_files = ls_files
      if staged_files.empty?
        Logging.record_error 'No files staged after git add -A (check .gitignore rules in repo root)'
        Logging.user_action 'Review .gitignore and ensure files you want tracked are not excluded'
        return false
      end

      Logging.info "Staged #{staged_files.size.to_s.purple} files for commit"

      # Create initial commit with --no-verify to skip pre-commit hooks
      # (pre-commit runs RuboCop which may fail on personal scripts that don't follow dotfiles standards)
      prefix = commit_count.zero? ? 'Initial' : 'Incremental'
      message = "#{prefix} commit: #{Core.current_timestamp}"
      _stdout, stderr, commit_status = commit(message, no_verify: true)
      unless commit_status.success?
        Logging.record_error 'Failed to create commit after recreation'
        Logging.record_error "Stderr: #{stderr}" unless nil_or_empty?(stderr)
        return false
      end

      # Verify commit has files (commit succeeded but might be empty)
      if commit_count.zero?
        Logging.record_error 'No commits created after staging and committing'
        return false
      end

      # Verify file lists match
      _verify_file_lists_match(remote_files)
    end

    private

    # Verifies that new local repo file list matches the pre-captured remote file list.
    # Logs detailed diagnostics if they don't match.
    #
    # @param remote_files [Array<String>] Pre-captured remote file list (before recreate)
    # @return [Boolean] true if lists match, false otherwise
    def _verify_file_lists_match(remote_files)
      Logging.info 'Verifying file lists match between new local and old remote...'

      if @dry_run
        Logging.info "Would compare #{'HEAD'.cyan} vs pre-captured remote file list"
        return true
      end

      # Get local files list from new repo (HEAD - just committed)
      local_files = ls_tree('HEAD')

      # Compare the lists
      if local_files == remote_files
        Logging.success "✅ File lists match (#{local_files.size.to_s.purple} files) - safe to force-push"
        return true
      end

      # Lists don't match - compute differences and show detailed diagnostic output
      _log_file_list_mismatch(local_files, remote_files)
      Logging.record_error '❌ File lists DO NOT match between new local and old remote!'
      false
    end

    # Logs diagnostic output for file list mismatches.
    #
    # @param local_files [Array<String>] Files in new local repo
    # @param remote_files [Array<String>] Files in old remote
    # @return [void]
    def _log_file_list_mismatch(local_files, remote_files)
      local_only = local_files - remote_files
      remote_only = remote_files - local_files

      Logging.warn 'Aborting without deleting remote repo - local has been recreated but remote is preserved'

      _print_file_diff('Files only in new local', local_only, '+')
      _print_file_diff('Files only in old remote', remote_only, '-')
    end

    # Prints file diff diagnostics for verification failures.
    #
    # @param label [String] Description of the file set
    # @param files [Array<String>] List of files
    # @param prefix [String] Prefix character ('+' or '-')
    # @return [void]
    def _print_file_diff(label, files, prefix)
      return unless files.any?

      files_size = files.size
      Logging.warn "#{label} (#{files_size.to_s.red}):"
      files.first(10).each { |f| Logging.warn "  #{prefix} #{f.cyan}" }
      Logging.warn "  ... and #{files_size - 10} more" if files_size > 10
    end

    # Recreates the local git repository by removing .git and reinitializing.
    # Preserves working tree files, only destroys git history.
    # Automatically restores ALL configured remotes (not just 'origin' -- a repo may have
    # more than one, e.g. 'origin' == keybase://, 'origin2' == the gpg+git-bundle
    # encrypted backup, see KeybaseMigration.md; restoring only 'origin' would silently
    # and permanently discard every other remote on every force-squash), plus user.name
    # and user.email, from current repo state.
    #
    # WARNING: This method does NOT verify against remote. For force-squash operations
    # where you're destroying history, use verify_and_recreate_local_repo instead
    # to prevent data loss.
    #
    # This method is currently private. If made public in the future, it should only be used when:
    # - Converting ref format without changing history
    # - Operating on local-only repos (no remote)
    # - You have verified file lists match through other means
    #
    # @param ref_format [String] The ref-format to use (defaults to 'reftable').
    # @return [Boolean] true on success, false on failure.
    def _recreate(ref_format: 'reftable')
      git_path = @dir.join('.git')

      # Capture current state before destroying .git -- every configured remote (see
      # doc above for why this must not be limited to just 'origin').
      branch_name = current_branch
      remotes = {}
      each_remote { |name, url| remotes[name] = url }
      user_name = config_value('user.name')
      user_email = config_value('user.email')

      if @dry_run
        Logging.info "Would remove: '#{git_path.cyan}'"
      else
        return false unless repo?

        # .git can be a directory (normal clone) or a file (worktree/submodule pointer).
        # rmtree handles both: removes directory tree or deletes the file.
        git_path.rmtree
      end

      _stdout, _stderr, status = init(ref_format: ref_format, initial_branch: branch_name)
      return false unless status.success?

      # Restore every captured remote and config from captured state
      remotes.each { |name, url| add_remote(name, url) unless nil_or_empty?(url) }
      config_set('user.name', user_name) unless nil_or_empty?(user_name)
      config_set('user.email', user_email) unless nil_or_empty?(user_email)

      true
    end
  end
end
