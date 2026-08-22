#!/usr/bin/env ruby
# encoding: utf-8
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
        is_keybase_repo = Keybase.keybase_url?(git.remote_url)

        # Before destroying git history, ensure Keybase is reachable so we do not end
        # up with a deleted local .git and no way to push.
        return false if is_keybase_repo && !Keybase.ensure_logged_in(dry_run: dry_run)

        if force
          # Recreate with verification (captures remote files, recreates, stages, commits, verifies)
          return false unless git.verify_and_recreate_local_repo

          # File lists match - safe to delete remote and push
          # Keybase repo recreation only happens when force-squashing commits, because
          # that's when we've destroyed local history. Without force, we're just
          # compressing and pushing existing commits - no remote recreation needed.
          return false if is_keybase_repo && !Keybase.recreate_repo(git.remote_repo_name, dry_run: dry_run)
        else
          # Stage and commit all files in local repo
          git.stage_all
          git.smart_commit
        end

        git.compress
        # Push to remote (force push after recreation, normal push otherwise)
        git.push(remote: 'origin', branch: git.current_branch, force: force)

        # Build commit graph for optimized git operations (log, status, merge-base)
        git.build_commit_graph
      end
    end

    true
  end
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
