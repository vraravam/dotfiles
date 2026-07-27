#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/recreate-repository.rb
#
# Recreates a git repository by optionally squashing all history into a single
# commit, then deleting and re-creating the remote Keybase repository and force-
# pushing. Useful for removing dangling/orphaned commits so fresh cloning
# is fast.
#
# Usage:
#   Standalone: recreate-repository.rb [-f] -d <repo-dir>
#   Module:     RecreateRepository.run(dir: path, force: false, dry_run: false)

require_relative 'utilities/cron'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/keybase'
require_relative 'utilities/logging'
require_relative 'utilities/macos'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module RecreateRepository
  extend self

  # Public API method.
  #
  # @param dir [String, Pathname] Repo directory to process
  # @param force [Boolean] Squash all commits into one (default: false)
  # @param dry_run [Boolean] Show what would be done without making changes (default: false)
  # @return [Boolean] true on success, false on error
  def run(dir:, force: false, dry_run: false)
    dir = dir.to_s.chomp('/')
    dir_pn = Pathname.new(dir)

    Logging.info '🔍 DRY RUN MODE -- No changes will be made'.red if dry_run

    # The profiles repo is always force-squashed.
    profiles_repo_name = EnvVars::KEYBASE_PROFILES_REPO_NAME
    force = true if profiles_repo_name && dir_pn.basename.to_s == profiles_repo_name

    unless GitProcessor.repo?(dir)
      Logging.error "'#{dir.cyan}' is not a git repo. Please specify the root of a git repo."
    end

    Logging.section_header "#{'Processing dir:'.yellow} '#{dir.cyan}'"

    # Create GitProcessor instance for this repo with dry_run mode.
    # This single instance is reused throughout for all git operations.
    git = GitProcessor.new(dir: dir_pn, dry_run: dry_run)

    git_url = git.remote_url
    user_name = git.config_value('user.name')
    user_email = git.config_value('user.email')
    branch = git.current_branch

    Logging.info "#{'Squash commits (will lose history!):'.yellow} #{force.to_s.orange}"
    Logging.info "#{'Dry run:'.yellow} #{dry_run.to_s.orange}"
    Logging.info "#{'Repo url:'.yellow} '#{git_url.cyan}'"
    Logging.info "#{'User name:'.yellow} '#{user_name.cyan}'"
    Logging.info "#{'User email:'.yellow} '#{user_email.cyan}'"
    Logging.info "#{'Branch:'.yellow} '#{branch.cyan}'"

    if [git_url, user_name, user_email, branch].any? { |v| nil_or_empty?(v) }
      Logging.error "One or more required git metadata values are missing for '#{dir.cyan}' -- see above"
    end

    # Before destroying git history, ensure Keybase is reachable so we do not end
    # up with a deleted local .git and no way to push.
    return false if Keybase.keybase_url?(git_url) && !Keybase.ensure_logged_in(dry_run: dry_run)

    # Wrap the destructive operations in cron suspension so the cron job does not
    # fire mid-operation. recron regenerates the crontab on the success path;
    # resume_cron restores from the backup on any error path.
    Cron.with_cron_suspended(dry_run: dry_run) do
      if force
        # Capture remote file list BEFORE destroying local .git
        # (recreate removes .git which loses remote tracking refs)
        remote_ref = "origin/#{branch}"
        remote_files = git.ls_tree(remote_ref)

        if remote_files.empty?
          Logging.record_error "Failed to get file list from remote branch '#{remote_ref.cyan}' or remote is empty"
          return false
        end

        # Now safe to recreate local repo (remote untouched)
        git.recreate(remote_url: git_url, user_name: user_name, user_email: user_email)
      end

      # Stage and commit all files in local repo
      git.stage_all
      git.smart_commit

      git.compress

      if force
        # Compare new local vs old remote BEFORE deleting remote.
        # This ensures we don't lose any files when recreating the remote repo.
        return false unless _verify_file_lists_match(git, remote_files, dry_run)

        # File lists match - safe to delete remote and push
        # Keybase repo recreation only happens when force-squashing commits, because
        # that's when we've destroyed local history. Without force, we're just
        # compressing and pushing existing commits - no remote recreation needed.
        if Keybase.keybase_url?(git_url)
          return false unless Keybase.recreate_repo(git.remote_repo_name, dry_run: dry_run)
        end
      end

      # Push to remote (force push after recreation, normal push otherwise)
      git.push(remote: 'origin', branch: branch, force: force)

      # Build commit graph for optimized git operations (log, status, merge-base)
      git.build_commit_graph
    end

    true
  end

  # Verifies that new local repo and old remote file lists match.
  # Called after local recreation with pre-captured remote file list.
  #
  # @param git [GitProcessor] Git processor instance
  # @param remote_files [Array<String>] Pre-captured remote file list (before recreate)
  # @param dry_run [Boolean] Dry run mode
  # @return [Boolean] true if lists match (or dry_run), false otherwise
  def _verify_file_lists_match(git, remote_files, dry_run)
    Logging.info "Verifying file lists match between new local and old remote before deleting remote..."

    if dry_run
      Logging.info "Would compare #{'HEAD'.cyan} vs pre-captured remote file list"
      return true
    end

    # Get local files list from new repo (HEAD - just committed)
    local_files = git.ls_tree('HEAD')

    # Compare the lists
    if local_files == remote_files
      Logging.success "✅ File lists match (#{local_files.size.to_s.purple} files) - safe to delete remote"
      return true
    end

    # Lists don't match - compute differences and show detailed diagnostic output
    local_only = local_files - remote_files
    remote_only = remote_files - local_files

    # Print all diagnostic information BEFORE raising error
    Logging.warn "Aborting without deleting remote repo - local has been recreated but remote is preserved"

    if local_only.any?
      Logging.warn "Files only in new local (#{local_only.size.to_s.red}):"
      local_only.first(10).each { |f| Logging.warn "  + #{f.cyan}" }
      Logging.warn "  ... and #{local_only.size - 10} more" if local_only.size > 10
    end

    if remote_only.any?
      Logging.warn "Files only in old remote (#{remote_only.size.to_s.red}):"
      remote_only.first(10).each { |f| Logging.warn "  - #{f.cyan}" }
      Logging.warn "  ... and #{remote_only.size - 10} more" if remote_only.size > 10
    end

    # Raise error AFTER printing all diagnostics
    Logging.error "❌ File lists DO NOT match between new local and old remote!"
  end

  private_class_method :_verify_file_lists_match
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = { force: false, dry_run: false }
  parser = CliParser.parse('<options>') do |opts|
    opts.separator 'Recreates a git repo, optionally squashing all history, and force-pushes to the remote.'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('-f', '--force', 'Squash all commits into one (profiles repo is always forced)') do
      options[:force] = true
    end
    opts.on('-d', '--dir DIR', 'Repo dir to process (mandatory)') { |v| options[:dir] = v }
    opts.on('-n', '--dry-run', 'Show what would be done without making changes') do
      options[:dry_run] = true
    end
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -f -d #{EnvVars::HOME}"
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -d $PERSONAL_PROFILES_DIR"
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -n -d ~/dev/my-repo  # dry-run"
  end

  parser.abort_with_usage('Missing required option: -d <dir>') if nil_or_empty?(options[:dir])

  Logging.run_script(File.basename(__FILE__, '.rb')) do
    success = RecreateRepository.run(dir: options[:dir], force: options[:force], dry_run: options[:dry_run])
    exit(success ? 0 : 1)
  end
end
