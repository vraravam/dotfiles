#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'
require 'set'

require_relative 'collection_processor'
require_relative 'core'
require_relative 'env_vars'
require_relative 'git_processor'
require_relative 'logging'
require_relative 'profiles_repo'

# Git workspace discovery and reporting across the repositories this setup tracks. Shell
# aliases delegate to these Ruby methods (status_all_repos, update_all_repos,
# regenerate_repo_aliases).
#
# Responsibilities:
# - Finding git repositories (and their ancestor directories) within a directory tree
# - Reporting status of, and committing changes in, the fixed set of tracked repos
# - Generating shell aliases for quick repo navigation
#
# Developer-environment setup (mise, direnv) lives in DevEnvironment; the single-repo git
# operations themselves live in GitProcessor.
module GitWorkspace
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Directories that are always excluded from repo searches (huge, rarely contain repos)
  DEFAULT_PRUNE_DIRS = %w[node_modules .cache .Trash].freeze

  # ---------------------------------------------------------------------------
  # Git repo discovery
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Query methods (read-only state inspection)
  # ---------------------------------------------------------------------------

  # Finds all git repositories under the given directories, returning their root
  # paths (directories containing .git). Supports filtering, depth control, and
  # directory pruning.
  #
  # Delegates to CollectionProcessor.find_directories_matching for the low-level
  # find operation, adding git-specific defaults and semantics (search for .git
  # directories, return their parents as repo roots, prune common repo cruft).
  #
  # @param dirs [Array<String, Pathname>, String, Pathname] Root directory/directories to search
  # @param mindepth [Integer] Minimum search depth (default: 1)
  # @param maxdepth [Integer] Maximum search depth (default: 6)
  # @param filter [String, Regexp, nil] Only include repos matching this pattern
  # @param additional_prune [Array<String>] Additional directories to prune beyond
  #   the defaults (node_modules, .cache, .Trash). Pass [] for no additional pruning.
  # @param skip_symlinks [Boolean] Skip repo roots that are symlinks (default: true)
  # @return [Array<String>] Repo root paths, deduplicated and sorted alphabetically
  def find_git_repos(dirs:, mindepth: 1, maxdepth: 6, filter: nil, additional_prune: [], skip_symlinks: true)
    prune_dirs = DEFAULT_PRUNE_DIRS + Array(additional_prune)

    repos = CollectionProcessor.find_directories_matching(
      dirs: dirs,
      name_pattern: '.git',
      mindepth: mindepth,
      maxdepth: maxdepth,
      filter: filter,
      prune_dirs: prune_dirs,
      skip_symlinks: skip_symlinks,
      transform_result: ->(git_dir) { File.dirname(git_dir) }
    )

    # Filter out nested repos: remove any repo that sits inside another repo's
    # working tree. A repo is nested if any of its ancestor directories (between
    # the repo and the search root) contains a .git directory.
    # Example: ~/dev/project/.git is found, then ~/dev/project/nested/.git is
    # rejected because ~/dev/project is between ~/dev/project/nested and ~/dev.
    # search_roots is computed once here (not per-repo, not per-ancestor-level) and
    # uses a Set for O(1) membership checks instead of Array#include?'s O(n) scan.
    search_roots = Set.new(Array(dirs).map { |d| File.expand_path(d.to_s) })

    repos.reject do |repo|
      parent = File.dirname(repo)
      # Walk up until we hit a search root or find a .git directory
      while parent != Core::ROOT.to_s
        # Check if we've reached any of the search roots - stop here
        break if search_roots.include?(parent)

        # If this ancestor is a git repo, current repo is nested
        break true if GitProcessor.repo?(parent)

        # Move up one directory
        new_parent = File.dirname(parent)
        break if new_parent == parent # Hit root

        parent = new_parent
        # Result of while loop - true means we found a parent repo
      end == true
    end
  end

  # Collects all ancestor directories of the given repo roots, walking up to a
  # specified boundary directory. Deduplicates using a Set for O(1) membership checks.
  #
  # @param repo_roots [Array<String>] Array of repository root paths
  # @param stop_at [Pathname] Upper boundary directory (exclusive unless include_stop_boundary is true)
  # @param include_repo_root [Boolean] When true, includes repo root itself in results;
  #   when false, starts from parent of repo root
  # @param include_stop_boundary [Boolean] When true, includes stop_at directory if reached;
  #   when false, stops before stop_at
  # @return [Array<String>] Deduplicated ancestor directory paths as strings
  def collect_ancestors(repo_roots, stop_at:, include_repo_root: false, include_stop_boundary: false)
    seen = Set.new

    repo_roots.each do |repo_root|
      dir = Pathname.new(repo_root)
      dir = dir.dirname unless include_repo_root

      while dir != Core::ROOT
        # Stop before reaching stop_at (unless include_stop_boundary is true)
        if dir == stop_at
          seen.add(dir) if include_stop_boundary
          break
        end

        break if seen.include?(dir)

        seen.add(dir)
        dir = dir.dirname
      end
    end

    seen.to_a.map(&:to_s)
  end

  # Reports git status for a single repository.
  #
  # @param repo_dir [Pathname, String] The repository directory
  # @param switches [Array<String>] Additional git status flags (optional)
  # @return [Boolean] true if status retrieved successfully
  # :reek:UtilityFunction -- Stateless utility that operates only on arguments
  def status_repo(repo_dir, switches: [])
    repo_dir = Pathname.new(repo_dir) unless repo_dir.is_a?(Pathname)

    unless GitProcessor.repo?(repo_dir)
      Logging.debug "Skipping status -- '#{repo_dir.cyan}' is not a git repo"
      return false
    end

    Logging.with_step("status #{repo_dir}", "#{'Status'.yellow} '#{repo_dir.cyan}'") do
      status = nil
      GitProcessor.new(dir: repo_dir) { |git| _stdout, _stderr, status = git.status(*switches) }
      status.success?
    end
  end

  # Reports git status for HOME, DOTFILES_DIR, PERSONAL_PROFILES_DIR, and all
  # chrome directories in browser profiles. Intended for quick status overview.
  #
  # @return [Boolean] true if all status checks succeeded
  # :reek:FeatureEnvy -- Accumulates status results from multiple repos
  def status_all_repos
    results = []

    # Key repos
    results << status_repo(EnvVars::HOME)
    results << status_repo(EnvVars::DOTFILES_DIR)
    results << status_repo(EnvVars::PERSONAL_PROFILES_DIR)

    # Chrome directories in browser profiles
    results.concat(ProfilesRepo.find_chrome_folders.map { |chrome_dir| status_repo(chrome_dir) })

    results.all?
  end

  # ---------------------------------------------------------------------------
  # Mutation methods (modify state)
  # ---------------------------------------------------------------------------

  # Regenerates the repo alias cache under XDG_CACHE_HOME.
  # Because the cache file is a zsh script consumed by the interactive shell
  # (not by Ruby), this method regenerates the file contents and leaves
  # sourcing to the shell layer. The shell wrapper (regenerate_repo_aliases in
  # .aliases) delegates to this implementation and handles cache loading.
  #
  # @param force [Boolean] When true, always regenerates even if the cache is
  #   up to date. When false (default), only regenerates if the cache is missing
  #   or older than PROJECTS_BASE_DIR.
  # :reek:FeatureEnvy -- Manages cache file lifecycle (stale check, write, compile)
  def regenerate_repo_aliases(force: false)
    projects_base = EnvVars::PROJECTS_BASE_DIR
    return unless projects_base.directory?

    cache_file = EnvVars::XDG_CACHE_HOME.join('repo-aliases-cache.zsh')

    cache_stale = !cache_file.file? ||
                  projects_base.mtime > cache_file.mtime

    return unless force || cache_stale

    if force
      Logging.info 'Regenerating repo aliases cache...'
    elsif EnvVars.debug?
      Logging.debug 'Regenerating repo aliases cache (stale or missing)'
    end

    # Find all repo roots under PROJECTS_BASE_DIR
    repo_roots = find_git_repos(
      dirs: projects_base,
      maxdepth: 6,
      additional_prune: %w[Library Caches], # Add to defaults (node_modules, .cache, .Trash)
      skip_symlinks: true
    )

    # Collect parent dirs (ancestors of repo roots, up to but not including PROJECTS_BASE_DIR)
    parent_dirs = collect_ancestors(
      repo_roots,
      stop_at: Pathname.new(projects_base),
      include_repo_root: false,
      include_stop_boundary: false
    )

    # Sort by depth so shallower (more general) aliases come first in the cache file
    sorted_dirs = parent_dirs.sort_by { |d| d.count(File::SEPARATOR) }

    cache_file.open('w') do |f|
      sorted_dirs.each do |dir_path|
        relative = dir_path.delete_prefix("#{projects_base}#{File::SEPARATOR}")
        # Alias name: replace path separator with '-'; value: sets FOLDER for run-all.rb.
        # Use tr instead of gsub for single-character replacement (3x faster).
        alias_name = relative.tr(File::SEPARATOR, '-')
        f.puts "alias #{alias_name}=\"FOLDER='#{dir_path}' MAXDEPTH=4 rug\""
      end
    end

    return unless force

    # Use Core.read_lines_utf8 to avoid encoding issues in non-UTF-8 environments.
    count = Core.read_lines_utf8(cache_file).length
    Logging.success "Repo aliases cache regenerated (#{count.to_s.green} aliases)"
  end

  # Stages and commits all changed files in a git repo without prompting.
  # Intended for repos that track auto-generated state (e.g., preference exports)
  # where the caller does not need to review individual changes before committing.
  #
  # @param repo_dir [Pathname, String] The repository directory
  # @param paths [Array<Pathname, String>, nil] Optional array of paths to stage within the repo
  #   (defaults to ['.'] - entire repo). Can be relative or absolute - git handles both.
  # @return [Boolean] true if successful, false if repo is invalid or git operations fail
  # :reek:UtilityFunction -- Stateless utility that operates only on arguments
  def update_repo(repo_dir, paths: nil)
    repo_dir = Pathname.new(repo_dir) unless repo_dir.is_a?(Pathname)

    unless GitProcessor.repo?(repo_dir)
      Logging.warn "Skipping repo update -- '#{repo_dir.cyan}' is not a git repo"
      return false
    end

    Logging.with_step("update #{repo_dir}", "#{'Updating'.yellow} '#{repo_dir.cyan}'") do
      success = false
      GitProcessor.new(dir: repo_dir) { |git| success = git.commit_all(paths: paths) }
      success
    end
  rescue RuntimeError => e
    # Git operations may raise RuntimeError on failures
    Logging.warn "Skipping repo update -- #{e.message}"
    false
  end

  # Updates HOME and PERSONAL_PROFILES_DIR repos by staging and committing changes.
  # Can be called from command line (via `update_all_repos` autoload function) or scripts.
  #
  # Note: HOME repo's preferences (defaults/) are also committed by capture-prefs.rb -e
  # (which auto-commits on export). This method provides a catch-all for any uncommitted
  # changes (e.g., if capture-prefs was interrupted or skipped).
  #
  # @return [Boolean] true if both repos updated successfully
  def update_all_repos
    home_success = update_repo(
      EnvVars::HOME,
      paths: [EnvVars::PERSONAL_CONFIGS_DIR.join('defaults')]
    )

    profiles_success = update_repo(
      EnvVars::PERSONAL_PROFILES_DIR,
      paths: nil
    )

    home_success && profiles_success
  end
end
