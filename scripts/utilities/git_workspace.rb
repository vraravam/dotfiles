# frozen_string_literal: true

require 'pathname'
require 'set'

require_relative 'collection_processor'
require_relative 'env_vars'
require_relative 'logging'
require_relative 'path_utils'

# Git workspace discovery and developer environment setup. Shell functions in
# .aliases delegate to these Ruby methods (install_mise_versions,
# allow_all_direnv_configs, setup_dev_environment, regenerate_repo_aliases).
#
# Responsibilities:
# - Finding git repositories within a directory tree
# - Installing mise tool versions across repos
# - Authorizing direnv configs across repos
# - Generating shell aliases for quick repo navigation
#
# The +shared_dirs:+ keyword argument allows callers (Ruby scripts, not shell)
# to optimize by collecting ancestor dirs once and passing to multiple methods,
# avoiding repeated find traversals.
module GitWorkspace
  extend self

  # Directories that are always excluded from repo searches (huge, rarely contain repos)
  DEFAULT_PRUNE_DIRS = %w[node_modules .cache .Trash].freeze

  # Mise config filenames that indicate a directory has version declarations.
  MISE_CONFIG_FILES = %w[
    .mise.toml
    .tool-versions
    .ruby-version
    .python-version
    .node-version
    .java-version
    .nvmrc
  ].freeze

  # ---------------------------------------------------------------------------
  # Git repo discovery
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

    CollectionProcessor.find_directories_matching(
      dirs: dirs,
      name_pattern: '.git',
      mindepth: mindepth,
      maxdepth: maxdepth,
      filter: filter,
      prune_dirs: prune_dirs,
      skip_symlinks: skip_symlinks,
      transform_result: ->(git_dir) { File.dirname(git_dir) }
    )
  end

  # ---------------------------------------------------------------------------
  # Mise version installation
  # ---------------------------------------------------------------------------

  # Installs any missing tool versions declared via mise config files across
  # all git repos and their ancestor directories. Skips silently if mise is not
  # on PATH. Mirrors install_mise_versions in .aliases.
  #
  # @param shared_dirs [Array<String>, nil] Pre-collected ancestor dirs (avoids
  #   a second find traversal when collect_ancestor_dirs was already called by
  #   the same script). Pass nil to trigger collection internally.
  # @param first_install [Boolean] When true, uses shallow search depth (3 vs 6).
  def install_mise_versions(shared_dirs: nil, first_install: false)
    # Only set script name and increment depth if we're at depth 0 (not yet
    # incremented by a caller). Shell wrappers don't increment, so standalone
    # calls start at 0. Nested Ruby calls will be at depth >= 1, so they skip
    # script name override and timing infrastructure entirely.
    current_depth = ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i
    if current_depth.zero?
      Logging.script_name = 'install_mise_versions'
      Logging.increment_script_depth
      script_start_time = Logging.print_script_start
    end

    Logging.section_header2 'Installing mise in all git repos and ancestors'

    unless PathUtils.command_exists?('mise')
      Logging.debug "Couldn't find 'mise' in PATH -- skipping mise config loading"
      return
    end

    all_dirs = shared_dirs || collect_ancestor_dirs(first_install: first_install)

    # Filter to dirs that actually have a mise config, then sort by depth so
    # parents come before children (shallower paths have fewer separators).
    dirs_with_config = all_dirs.select do |dir|
      dir_pn = Pathname.new(dir)
      MISE_CONFIG_FILES.any? { |cfg| dir_pn.join(cfg).file? }
    end
    sorted = dirs_with_config.sort_by { |d| d.count(File::SEPARATOR) }

    # Use CollectionProcessor for unified progress logging and error tracking
    results = CollectionProcessor.process_items(
      sorted,
      operation_desc: 'Installing mise tools'
    ) do |dir, _idx, _total|
      system('mise', '-C', dir, 'trust', '-y', '-a')
      system('mise', '-C', dir, 'install')
    end

    Logging.print_results_summary(results)
    Logging.print_script_summary(script_start_time) if current_depth.zero?
  end

  # ---------------------------------------------------------------------------
  # direnv config authorisation
  # ---------------------------------------------------------------------------

  # Runs 'direnv allow' for every directory that has an .envrc file across all
  # git repos and their ancestor directories. Skips silently if direnv is not
  # on PATH. Mirrors allow_all_direnv_configs in .aliases.
  #
  # @param shared_dirs [Array<String>, nil] See install_mise_versions.
  # @param first_install [Boolean] When true, uses shallow search depth (3 vs 6).
  def allow_all_direnv_configs(shared_dirs: nil, first_install: false)
    # Only set script name and increment depth if we're at depth 0 (not yet
    # incremented by a caller). Shell wrappers don't increment, so standalone
    # calls start at 0. Nested Ruby calls will be at depth >= 1, so they skip
    # script name override and timing infrastructure entirely.
    current_depth = ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i
    if current_depth.zero?
      Logging.script_name = 'allow_all_direnv_configs'
      Logging.increment_script_depth
      script_start_time = Logging.print_script_start
    end

    Logging.section_header2 'Allowing direnv configs in all git repos and ancestors'

    unless PathUtils.command_exists?('direnv')
      Logging.debug "Couldn't find 'direnv' in PATH -- skipping direnv config loading"
      return
    end

    all_dirs = shared_dirs || collect_ancestor_dirs(first_install: first_install)

    # Filter to dirs with .envrc, sort parents before children.
    dirs_with_envrc = all_dirs
      .select { |dir| Pathname.new(dir).join('.envrc').file? }
      .sort_by { |d| d.count(File::SEPARATOR) }

    # Use CollectionProcessor for unified progress logging and error tracking
    results = CollectionProcessor.process_items(
      dirs_with_envrc,
      operation_desc: 'Allowing direnv in'
    ) do |dir, _idx, _total|
      system('direnv', 'allow', dir)
    end

    Logging.print_results_summary(results)
    Logging.print_script_summary(script_start_time) if current_depth.zero?
  end

  # ---------------------------------------------------------------------------
  # Combined dev environment setup (optimized batch operation)
  # ---------------------------------------------------------------------------

  # Runs both mise installation and direnv authorization in a single pass,
  # collecting ancestor directories once and reusing for both operations.
  # This avoids redundant filesystem traversals -- saves 200-500ms per run
  # compared to calling install_mise_versions and allow_all_direnv_configs
  # independently.
  #
  # Designed for callers that need both operations (e.g., software-updates-cron.sh).
  # Single-operation callers should continue using the individual methods.
  #
  # @param first_install [Boolean] When true, uses shallow search depth (3 vs 6).
  def setup_dev_environment(first_install: false)
    current_depth = ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i
    if current_depth.zero?
      Logging.script_name = 'setup_dev_environment'
      Logging.increment_script_depth
      script_start_time = Logging.print_script_start
    end

    # Collect ancestor dirs once, reuse for both operations
    shared_dirs = collect_ancestor_dirs(first_install: first_install)

    # Both methods receive shared_dirs and skip their own collection
    allow_all_direnv_configs(shared_dirs: shared_dirs, first_install: first_install)
    install_mise_versions(shared_dirs: shared_dirs, first_install: first_install)

    Logging.print_script_summary(script_start_time) if current_depth.zero?
  end

  # ---------------------------------------------------------------------------
  # Repo alias cache regeneration
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
  def regenerate_repo_aliases(force: false)
    projects_base = EnvVars::PROJECTS_BASE_DIR
    return unless projects_base.directory?

    cache_file = EnvVars::XDG_CACHE_HOME.join('repo-aliases-cache.zsh')

    cache_stale = !cache_file.file? ||
                  projects_base.mtime > cache_file.mtime

    unless force || cache_stale
      return
    end

    if force
      Logging.info 'Regenerating repo aliases cache...'
    elsif EnvVars.debug?
      Logging.debug 'Regenerating repo aliases cache (stale or missing)'
    end

    # Find all repo roots under PROJECTS_BASE_DIR
    repo_roots = find_git_repos(
      dirs: projects_base,
      maxdepth: 6,
      additional_prune: %w[Library Caches],  # Add to defaults (node_modules, .cache, .Trash)
      skip_symlinks: true
    )

    # Collect parent dirs (ancestors of repo roots, up to but not including PROJECTS_BASE_DIR)
    parent_dirs = _collect_ancestors(
      repo_roots,
      stop_at: Pathname.new(projects_base),
      include_repo_root: false,
      include_stop_boundary: false
    )

    # Sort by depth so shallower (more general) aliases come first in the cache file
    sorted_dirs = parent_dirs.sort_by { |d| d.count(File::SEPARATOR) }

    cache_file.open('w') do |f|
      sorted_dirs.each do |dir_path|
        relative = dir_path.sub("#{projects_base}#{File::SEPARATOR}", '')
        # Alias name: replace path separator with '-'; value: sets FOLDER for run-all.rb.
        alias_name = relative.gsub(File::SEPARATOR, '-')
        f.puts "alias #{alias_name}=\"FOLDER='#{dir_path}' MAXDEPTH=4 rug\""
      end
    end

    if force
      count = cache_file.readlines.length
      Logging.success "Repo aliases cache regenerated (#{count.to_s.green} aliases)"
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  private

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
  def _collect_ancestors(repo_roots, stop_at:, include_repo_root: false, include_stop_boundary: false)
    seen = Set.new

    repo_roots.each do |repo_root|
      dir = Pathname.new(repo_root)
      dir = dir.dirname unless include_repo_root

      while dir != PathUtils::ROOT
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

  # Finds all git repos under HOME, DOTFILES_DIR, and PROJECTS_BASE_DIR (up to
  # +find_maxdepth+ levels deep) and returns a deduplicated array of every ancestor
  # directory from each repo root up to (and including) HOME.
  #
  # @param first_install [Boolean] When true, uses a shallower search depth (3
  #   instead of 6) to keep vanilla-OS boot time low.
  # @return [Array<String>] Unique ancestor directory paths.
  def collect_ancestor_dirs(first_install: false)
    maxdepth = first_install ? 3 : 6
    dirs = [EnvVars::HOME, EnvVars::DOTFILES_DIR, EnvVars::PROJECTS_BASE_DIR]

    # Find all repo roots using the consolidated method
    repo_roots = find_git_repos(
      dirs: dirs,
      maxdepth: maxdepth,
      additional_prune: %w[Library Caches],  # Add to defaults (node_modules, .cache, .Trash)
      skip_symlinks: true
    )

    # Walk up from each repo root to HOME, collecting all ancestors
    _collect_ancestors(
      repo_roots,
      stop_at: EnvVars::HOME,
      include_repo_root: true,
      include_stop_boundary: true
    )
  end
end
