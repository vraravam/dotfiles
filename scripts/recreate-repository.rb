#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/recreate-repository.rb
#
# Recreates a git repository by optionally squashing all history into a single
# commit, then force-pushing to the remote. Useful for removing dangling/orphaned
# commits so fresh cloning is fast. Also shrinks the payload of the next encrypted
# backup export (see scripts/utilities/encrypted_backup.rb): 'git bundle create --all'
# always contains the entire reachable history, so a smaller local history directly
# means a smaller bundle to encrypt and push next time.
#
# IMPORTANT: force mode does NOT delete and recreate the remote repository (that was
# a Keybase-specific workaround, removed along with Keybase support -- GitHub accepts
# a force-push of arbitrarily-diverged/squashed history directly, no special-casing
# needed). Force mode only squashes ALL local history into a single commit, then
# force-pushes that one commit to the existing remote. The remote repo itself is
# never deleted, recreated, or otherwise touched beyond the force-push.
#
# SAFETY CHECK FOR ENCRYPTED-BACKUP WRAPPER REPOS: this script's built-in "verify file
# lists match" safety check (see GitProcessor#verify_and_recreate_local_repo) is nearly
# vacuous for a one-file repo -- it only catches the file going missing entirely or a
# stray extra file appearing, not a stale/corrupted blob with the right path but wrong
# content. When -d points at a directory under ${XDG_CACHE_HOME}/encrypted-backups/ (an
# encrypted-backup wrapper repo -- see scripts/utilities/encrypted_backup.rb), force mode
# automatically runs EncryptedBackup.verify_current_blob_decryptable? first (decrypts the
# current blob and runs 'git bundle verify' on it) and refuses to squash if that fails --
# this is automatic and requires no special flag, specifically so the ordinary
# 'recreate-repository.rb -f -d <dir>' muscle memory stays safe without needing a
# different command for wrapper repos.
#
# Usage:
#   Standalone: recreate-repository.rb [-f] -d <repo-dir>
#   Module:     RecreateRepository.run(dir: path, force: false, dry_run: false)

require_relative 'utilities/cron'
require_relative 'utilities/encrypted_backup'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/logging'

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
  # :reek:UtilityFunction -- Module method pattern for dual-mode script (see ruby-scripting.md)
  def run(dir:, force: false, dry_run: false)
    dir = dir.to_s.chomp(File::SEPARATOR)
    dir_pn = Pathname.new(dir)

    Logging.info '🔍 DRY RUN MODE -- No changes will be made'.red if dry_run

    # The profiles repo is always force-squashed.
    force = true if dir_pn == EnvVars::PERSONAL_PROFILES_DIR

    dir_colored = dir.cyan
    Logging.error "'#{dir_colored}' is not a git repo. Please specify the root of a git repo." unless GitProcessor.repo?(dir)

    if force
      encrypted_repo_name = _encrypted_backup_repo_name(dir_pn)
      if encrypted_repo_name && !EncryptedBackup.verify_current_blob_decryptable?(encrypted_repo_name: encrypted_repo_name)
        Logging.record_error "'#{dir_colored}' is an encrypted-backup wrapper repo for '#{encrypted_repo_name}', " \
                             'and its current blob failed the decrypt/integrity check -- refusing to squash ' \
                             '(would risk losing the last known-good backup)'
        return false
      end
    end

    Logging.section_header "#{'Processing dir:'.yellow} '#{dir_colored}'"
    GitProcessor.new(dir: dir_pn, dry_run: dry_run) do |git|
      # Verify and log required git metadata
      git.verify_pre_recreation(force: force)

      # Suspend cron to prevent mid-operation conflicts with destructive git operations.
      Cron.with_cron_suspended(dry_run: dry_run) do
        if force
          # Squashes ALL local history into a single commit (captures remote file list
          # first, recreates local .git, stages, commits, then verifies the new single
          # commit's file list matches the remote's before proceeding -- see
          # GitProcessor#verify_and_recreate_local_repo). No remote delete/recreate here;
          # the squashed commit is force-pushed to the existing remote below, same as
          # any other force-push.
          return false unless git.verify_and_recreate_local_repo
        else
          # Stage and commit all files in local repo
          git.stage_all
          git.smart_commit
        end

        git.compress
        # Push the (squashed, if force) history to the existing remote. Force-pushing
        # squashed history directly is sufficient -- no remote delete/recreate step.
        git.push(remote: 'origin', branch: git.current_branch, force: force)

        # Build commit graph for optimized git operations (log, status, merge-base)
        git.build_commit_graph
      end
    end

    true
  end

  # Detects whether dir_pn is an encrypted-backup wrapper repo (a child of
  # ${XDG_CACHE_HOME}/encrypted-backups/, see EncryptedBackup.wrapper_repo_dir) and, if so,
  # returns its encrypted_repo_name. Derives the expected path via
  # EncryptedBackup.wrapper_repo_dir itself (rather than reconstructing the
  # 'encrypted-backups' path segment here) so the two stay in sync automatically if that
  # convention ever changes. Exact-match only -- a nested subdirectory of a wrapper repo is
  # not itself a wrapper repo. Does not require dir_pn to currently exist or be a valid repo,
  # callers already validate that separately.
  #
  # @param dir_pn [Pathname]
  # @return [String, nil] the encrypted_repo_name, or nil if dir_pn isn't a wrapper repo
  # :reek:UtilityFunction -- Stateless helper (correct design)
  def _encrypted_backup_repo_name(dir_pn)
    expanded = dir_pn.expand_path
    candidate_name = expanded.basename.to_s
    expanded == EncryptedBackup.wrapper_repo_dir(candidate_name) ? candidate_name : nil
  end

  private_class_method :_encrypted_backup_repo_name
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
    opts.separator 'Force mode against an encrypted-backup wrapper repo (${XDG_CACHE_HOME}/encrypted-backups/*)'
    opts.separator 'automatically verifies the current blob decrypts and is a valid git bundle first, and'
    opts.separator 'refuses to squash if it does not -- no special flag needed for this.'
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

  # Standard dual-mode CLI wrapper pattern (Flay similarity with resurrect-repositories.rb is intentional):
  # - Logging.run_script handles script infrastructure (depth tracking, timing, summary)
  # - Module.run() contains business logic
  # - exit(success ? 0 : 1) converts boolean to shell exit code
  # See ruby-scripting.md section "Dual-Mode Ruby Scripts" for rationale.
  Logging.run_script do
    success = RecreateRepository.run(dir: options[:dir], force: options[:force], dry_run: options[:dry_run])
    exit(success ? 0 : 1)
  end
end
