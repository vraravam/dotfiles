# frozen_string_literal: true

require_relative 'env_vars'
require_relative 'logging'
require_relative 'path_utils'

# Repo discovery and maintenance helpers. Shell functions in .aliases delegate
# to these Ruby methods (install_mise_versions, allow_all_direnv_configs,
# regenerate_repo_aliases).
#
# The +shared_dirs:+ keyword argument allows callers (Ruby scripts, not shell)
# to optimize by collecting ancestor dirs once and passing to multiple methods,
# avoiding repeated find traversals.
module Repos
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
  # @param folders [Array<String, Pathname>, String, Pathname] Root directory/directories to search
  # @param mindepth [Integer] Minimum search depth (default: 1)
  # @param maxdepth [Integer] Maximum search depth (default: 6)
  # @param filter [String, Regexp, nil] Only include repos matching this pattern
  # @param additional_prune [Array<String>] Additional directories to prune beyond
  #   the defaults (node_modules, .cache, .Trash). Pass [] for no additional pruning.
  # @param skip_symlinks [Boolean] Skip repo roots that are symlinks (default: true)
  # @return [Array<String>] Repo root paths, deduplicated and sorted alphabetically
  def find_git_repos(folders:, mindepth: 1, maxdepth: 6, filter: nil, additional_prune: [], skip_symlinks: true)
    # Convert Pathname objects to strings, rejecting nil and empty strings
    folders = Array(folders).compact.map(&:to_s).reject { |f| f.empty? }
    prune = DEFAULT_PRUNE_DIRS + Array(additional_prune)

    # Build prune expression: ( -name dir1 -o -name dir2 ... ) -prune -o
    prune_expr = prune.empty? ? [] : ['('] + prune.flat_map { |d| ['-o', '-name', d] }.drop(1) + [')', '-prune', '-o']

    find_cmd = [
      'find', *folders,
      '-mindepth', mindepth.to_s,
      '-maxdepth', maxdepth.to_s,
      *prune_expr,
      '-type', 'd',
      '-name', '.git',
      '-print'
    ]

    seen = {}
    results = []
    filter_re = filter.is_a?(Regexp) ? filter : (filter ? Regexp.new(filter) : nil)

    IO.popen(find_cmd, err: File::NULL) do |io|
      io.each_line do |line|
        # Repo root = parent of .git directory
        repo_root = File.dirname(line.chomp)
        next if filter_re && !repo_root.match?(filter_re)
        next if seen[repo_root]
        next if skip_symlinks && File.symlink?(repo_root)

        seen[repo_root] = true
        results << repo_root
      end
    end

    # Return sorted for deterministic output. Callers may re-sort by different
    # criteria (e.g., depth) for their specific needs.
    results.sort
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

    total = sorted.length
    sorted.each_with_index do |dir, idx|
      # --dry-run-code exits 0 when all tools are installed, non-zero otherwise.
      if system('mise', '-C', dir, 'install', '--dry-run-code',
                out: File::NULL, err: File::NULL)
        Logging.debug "[#{(idx + 1).to_s.purple}/#{total.to_s.purple}] '#{dir.cyan}' -- all tools already installed"
        next
      end
      Logging.info "[#{(idx + 1).to_s.purple}/#{total.to_s.purple}] installing mise tools in '#{dir.cyan}'"
      system('mise', '-C', dir, 'trust', '-y', '-a')
      system('mise', '-C', dir, 'install')
    end
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

    total = dirs_with_envrc.length
    dirs_with_envrc.each_with_index do |dir, idx|
      Logging.info "[#{(idx + 1).to_s.purple}/#{total.to_s.purple}] allowing direnv for '#{dir.cyan}'"
      if system('direnv', 'allow', dir)
        Logging.success "Successfully allowed direnv for '#{dir.cyan}'"
      else
        Logging.warn "Failed to allow direnv for '#{dir.cyan}'"
      end
    end
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
      folders: projects_base,
      maxdepth: 6,
      additional_prune: %w[Library Caches],  # Add to defaults (node_modules, .cache, .Trash)
      skip_symlinks: true
    )

    # Collect parent folders (ancestors of repo roots, up to but not including PROJECTS_BASE_DIR)
    seen = {}
    parent_folders = []
    projects_base_str = projects_base.to_s

    repo_roots.each do |repo_root|
      # First ancestor to alias = parent of repo root
      ancestor = File.dirname(repo_root)
      while ancestor != projects_base_str && ancestor != PathUtils::ROOT.to_s
        break if seen[ancestor]
        seen[ancestor] = true
        parent_folders << ancestor
        ancestor = File.dirname(ancestor)
      end
    end

    cache_file.open('w') do |f|
      parent_folders.each do |folder_path|
        relative = folder_path.sub("#{projects_base_str}#{File::SEPARATOR}", '')
        # Alias name: replace path separator with '-'; value: sets FOLDER for run-all.rb.
        alias_name = relative.gsub(File::SEPARATOR, '-')
        f.puts "alias #{alias_name}=\"FOLDER='#{folder_path}' MAXDEPTH=4 rug\""
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

  # Finds all git repos under HOME, DOTFILES_DIR, and PROJECTS_BASE_DIR (up to
  # +find_maxdepth+ levels deep) and returns a deduplicated array of every ancestor
  # directory from each repo root up to (and including) HOME.
  #
  # @param first_install [Boolean] When true, uses a shallower search depth (3
  #   instead of 6) to keep vanilla-OS boot time low.
  # @return [Array<String>] Unique ancestor directory paths.
  def collect_ancestor_dirs(first_install: false)
    maxdepth = first_install ? 3 : 6
    folders = [EnvVars::HOME, EnvVars::DOTFILES_DIR, EnvVars::PROJECTS_BASE_DIR]

    # Find all repo roots using the consolidated method
    repo_roots = find_git_repos(
      folders: folders,
      maxdepth: maxdepth,
      additional_prune: %w[Library Caches],  # Add to defaults (node_modules, .cache, .Trash)
      skip_symlinks: true
    )

    # Walk up from each repo root to HOME, collecting all ancestors
    seen = {}
    result = []
    home_str = EnvVars::HOME.to_s

    repo_roots.each do |repo_root|
      dir = repo_root
      while dir != PathUtils::ROOT.to_s
        break if seen[dir]
        seen[dir] = true
        result << dir
        break if dir == home_str
        dir = File.dirname(dir)
      end
    end

    result
  end
end
