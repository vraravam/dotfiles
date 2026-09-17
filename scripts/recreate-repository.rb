#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/recreate-repository.rb
#
# Recreates a git repository by optionally squashing all history into a single
# commit, then force-pushing to every configured remote. Useful for removing
# dangling/orphaned commits so fresh cloning is fast. Also shrinks the payload of the
# next encrypted backup export (the external 'git-remote-gpg-encrypt' tool's
# 'git bundle create --all' always contains the entire reachable history, so a smaller
# local history directly means a smaller bundle to encrypt and push next time).
#
# MULTIPLE REMOTES: a repo may now have more than one remote (e.g. 'origin' ==
# keybase://, 'origin2' == a 'gpg-encrypt::' remote for the external
# 'git-remote-gpg-encrypt' tool -- see KeybaseMigration.md). Force mode force-pushes
# the squashed history to ALL of them (see _push_to_all_remotes), not just 'origin'.
#
# KEYBASE IS SPECIAL-CASED: a squashed force-push alone does not fully discard a
# keybase:// repo's prior history server-side the way a plain force-push does on a
# real git host -- Keybase's own git-remote-helper still retains old blobs reachable
# through its history/pruning model. Keybase.recreate_repo (scripts/utilities/keybase.rb)
# deletes and explicitly recreates the repo instead of relying on force-push alone.
# Keybase.ensure_logged_in is checked BEFORE any destructive local operation, for every
# keybase:// remote found, so a login failure is caught before local history is
# squashed away with nowhere to push it. Every other remote (a 'gpg-encrypt::' remote,
# or a plain GitHub remote) is just force-pushed directly -- no delete/recreate needed
# or possible there.
#
# Usage:
#   Standalone: recreate-repository.rb [-f] -d <repo-dir>
#   Module:     RecreateRepository.run(dir: path, force: false, dry_run: false)

require_relative 'utilities/core'
require_relative 'utilities/cron'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/keybase'
require_relative 'utilities/logging'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module RecreateRepository
  extend self
  extend Core # For nil_or_empty? as an unqualified module method call

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

    Logging.section_header "#{'Processing dir:'.yellow} '#{dir_colored}'"
    GitProcessor.new(dir: dir_pn, dry_run: dry_run) do |git|
      # Verify and log required git metadata
      git.verify_pre_recreation(force: force)

      # Suspend cron to prevent mid-operation conflicts with destructive git operations.
      Cron.with_cron_suspended(dry_run: dry_run) do
        if force
          # Before destroying local git history, ensure every keybase:// remote is
          # reachable -- otherwise we'd end up with a deleted local .git/rewritten
          # history and no way to push it anywhere.
          return false unless _ensure_keybase_remotes_reachable(git, dry_run: dry_run)

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
        # Force-pushes the (squashed, if force) history to every configured remote --
        # see _push_to_all_remotes's doc for why keybase:// remotes get a
        # delete-then-recreate treatment while every other remote is just force-pushed
        # directly.
        return false unless _push_to_all_remotes(git, branch: git.current_branch, force: force, dry_run: dry_run)

        # Build commit graph for optimized git operations (log, status, merge-base)
        git.build_commit_graph
      end
    end

    true
  end

  # Ensures every keybase:// remote configured on git is reachable (logged in) before
  # any destructive local operation runs -- mirrors the original single-remote safety
  # check (Keybase.ensure_logged_in before git.verify_and_recreate_local_repo), extended
  # to every configured remote instead of just 'origin' now that a repo may have more
  # than one (see file header comment).
  #
  # @param git [GitProcessor]
  # @param dry_run [Boolean]
  # @return [Boolean] false if any keybase:// remote's login check fails
  def _ensure_keybase_remotes_reachable(git, dry_run:)
    git.each_remote do |_remote_name, url|
      next unless Keybase.keybase_url?(url)
      return false unless Keybase.ensure_logged_in(dry_run: dry_run)
    end
    true
  end

  # Force-pushes branch to every remote configured on git's repo. A keybase:// remote
  # gets deleted and recreated first (via Keybase.recreate_repo, scripts/utilities/keybase.rb)
  # since a plain force-push does not fully discard its prior history server-side the
  # way it does on a real git host -- Keybase's own git-remote-helper still retains old
  # blobs reachable through its history/pruning model, and Keybase does not reliably
  # auto-recreate a repo on push the way a delete+create does explicitly. Every other
  # remote (a 'gpg-encrypt::' remote, or a plain GitHub remote) is just force-pushed
  # directly -- no delete/recreate needed or possible there.
  #
  # @param git [GitProcessor]
  # @param branch [String]
  # @param force [Boolean]
  # @param dry_run [Boolean]
  # @return [Boolean] true if every remote's push succeeded
  def _push_to_all_remotes(git, branch:, force:, dry_run:)
    all_succeeded = true

    git.each_remote do |remote_name, url|
      if force && Keybase.keybase_url?(url)
        repo_name = git.remote_repo_name(name: remote_name)
        if nil_or_empty?(repo_name) || !Keybase.recreate_repo(repo_name, dry_run: dry_run)
          Logging.record_error "Failed to recreate keybase repo for remote '#{remote_name.cyan}' -- skipping push to it"
          all_succeeded = false
          next
        end
      end

      _stdout, stderr, status = git.push(remote: remote_name, branch: branch, force: force)
      if status.success?
        Logging.success "Pushed to '#{remote_name.cyan}'"
      else
        Logging.record_error "Failed to push to '#{remote_name.cyan}': #{stderr}"
        all_succeeded = false
      end
    end

    all_succeeded
  end

  private_class_method :_ensure_keybase_remotes_reachable, :_push_to_all_remotes
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = { force: false, dry_run: false }
  parser = CliParser.parse('<options>') do |opts|
    opts.separator 'Recreates a git repo, optionally squashing all history, and force-pushes to every configured remote.'
    opts.separator ''
    opts.separator 'A keybase:// remote is deleted and recreated (via Keybase.recreate_repo); every other'
    opts.separator 'remote is just force-pushed directly.'
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
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -d ${PERSONAL_PROFILES_DIR}"
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
