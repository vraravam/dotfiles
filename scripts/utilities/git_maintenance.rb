#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

require_relative 'command_utils'
require_relative 'core'
require_relative 'logging'

class GitProcessor
  # Repository housekeeping operations -- compression, commit-graph, stale lock and hook
  # cleanup, bundles and size reporting -- kept apart from the everyday git queries and
  # mutations in GitProcessor. Mixed into GitProcessor: relies on its @dir/@dry_run state
  # and its private _execute/_git_command helpers plus repo?/run_alias.
  module Maintenance
    include Core

    # Compresses the repository by expiring the entire reflog immediately and running the
    # full cleanup (prune, repack, gc). Runs 'git cc --expire=now', which does both in one
    # operation -- 'cc' always enumerates refs/heads and refs/remotes only, so stashes survive.
    #
    # @return [Boolean] true on success, false on failure.
    def compress
      if @dry_run
        Logging.info 'Would compress (reflog + gc)'
        return true
      end

      return false unless repo?

      Logging.debug "#{'Compressing'.yellow} '#{@dir.cyan}'"
      run_alias('cc', '--expire=now')
      true
    end

    # Builds the commit graph for the repository to optimize git operations.
    # Commit graphs speed up operations like git log, git merge-base, and git status.
    # Use --reachable to include all commits reachable from any ref (branches, tags).
    #
    # @return [Boolean] true on success, false on failure
    def build_commit_graph
      if @dry_run
        Logging.info 'Would build commit graph'
        return true
      end

      return false unless repo?

      Logging.debug "#{'Building commit graph'.yellow} for '#{@dir.cyan}'"
      _stdout, _stderr, status = _execute('commit-graph', 'write', '--reachable', '--changed-paths')
      status.success?
    end

    # Deletes .git/index.lock if it exists. This is a recovery operation for
    # stale lock files that can block git operations; an absent file is the
    # desired end state, not an error.
    #
    # @return [void]
    def delete_index_lock
      _delete_path(_git_path.join('index.lock'))
    end

    # Deletes .git/objects/info/commit-graphs/commit-graph-chain.lock if it exists.
    # A stale commit-graph lock (left behind by an interrupted 'git commit-graph write'
    # or a killed process) can block subsequent commit-graph writes; deleting it is
    # safe since git regenerates the commit-graph on next use.
    #
    # @return [void]
    def delete_commit_graph_lock
      _delete_path(_git_path.join('objects', 'info', 'commit-graphs', 'commit-graph-chain.lock'))
    end

    # Removes .git/hooks entirely if it exists. Used before automated operations on
    # repos that may have local hooks installed (e.g. via Husky/lint-staged) which
    # could otherwise interfere with or slow down non-interactive git calls.
    #
    # @return [void]
    def delete_hooks_dir
      _delete_path(_git_path.join('hooks'), verb: 'remove')
    end

    # Creates a git bundle file capturing all refs reachable in this repo
    # (branches, remote-tracking branches, and tags). Streams git's own
    # progress output for large repos.
    #
    # @param file [String, Pathname] Destination path for the bundle file.
    # @return [Boolean] true on success, false on failure.
    def bundle_create(file:)
      if @dry_run
        Logging.info "Would run: #{"git -C #{@dir} bundle create #{file} --all".cyan}"
        return true
      end

      return false unless repo?

      Pathname(file).dirname.mkpath
      CommandUtils.run_interactive(*_git_command, 'bundle', 'create', file.to_s, '--all')
    end

    # Returns the pack size of the repository in human-readable format. Calls the git 'size'
    # alias (which uses git count-objects internally), roughly 2-3x faster than walking the
    # directory (~10-20ms vs ~50ms). Reports pack size only (excludes refs, logs, indexes,
    # config), which is typically 70-90% of the total .git directory size.
    #
    # @return [String] Pack size such as "1.37 MiB" or "503.45 MiB" (empty if unavailable)
    def pack_size_human
      # GIT_SIZE_QUIET makes the 'size' alias print just the size. It is passed to the child
      # only (never written to this process's ENV, where it would leak on an exception).
      CommandUtils.query({ 'GIT_SIZE_QUIET' => '1' }, *_git_command, 'size')
    end

    # @return [Float] Pack size in megabytes (0.0 when the size cannot be determined)
    def pack_size_mb
      value, unit = pack_size_human.split
      return 0.0 if unit.nil?

      case unit
      when 'KiB' then value.to_f / 1024.0
      when 'MiB' then value.to_f
      when 'GiB' then value.to_f * 1024
      when 'bytes' then value.to_f / 1024.0 / 1024.0
      else 0.0
      end
    end

    private

    # Deletes a file or directory tree under .git, or only logs what it would do in dry-run
    # mode. A path that does not exist (including one removed by a concurrent git process
    # between the check and the delete) is fine; any other failure propagates.
    #
    # @param path [Pathname] What to delete
    # @param verb [String] Wording for the dry-run message ('delete' or 'remove')
    # @return [void]
    def _delete_path(path, verb: 'delete')
      if @dry_run
        Logging.info "Would #{verb}: '#{path.cyan}' (if it exists)"
        return
      end

      return unless path.exist?

      path.directory? ? path.rmtree : path.delete
    rescue Errno::ENOENT
      nil
    end
  end
end
