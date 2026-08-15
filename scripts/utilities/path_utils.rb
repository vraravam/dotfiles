#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'pathname'

require_relative 'command_utils'
require_relative 'core'
require_relative 'logging'
require_relative 'macos'

# Command and path manipulation utilities for Ruby scripts.
#
# For environment variable paths (HOME, DOTFILES_DIR, etc.), use EnvVars instead.
# For macOS system command paths (DEFAULTS_CMD, OSASCRIPT_CMD, etc.), use MacOS instead.
# For filesystem root (/), use Core::ROOT instead.
#
# Usage:
#   require 'path_utils'

# Module for command existence checks and path manipulation utilities.
# Generic (cross-platform) utilities only -- macOS-specific paths are in MacOS module.
module PathUtils
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Cache for command existence checks (reduces which forks from N per check → 1 per command)
  @command_cache = {}

  # Checks if a command exists in the system PATH.
  # Mirrors command_exists() from .shellrc.
  # Results are cached to avoid repeated which forks for the same command.
  #
  # @param command [String] The command name to check
  # @return [Boolean] true if the command exists in PATH, false otherwise
  #
  # @example
  #   PathUtils.command_exists?('ruby')  # => true (checks via which)
  #   PathUtils.command_exists?('ruby')  # => true (cached, no fork)
  #   PathUtils.command_exists?('nosuchcommand')  # => false

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Query methods (read-only state inspection)
  # ---------------------------------------------------------------------------

  # Checks if a command exists in the system PATH.
  # Mirrors command_exists() from .shellrc.
  #
  # @param command [String] The command name to check
  # @return [Boolean] true if the command exists in PATH, false otherwise
  #
  # @example
  #   PathUtils.command_exists?('ruby')  # => true
  #   PathUtils.command_exists?('nosuchcommand')  # => false
  def command_exists?(command)
    return @command_cache[command] if @command_cache.key?(command)

    @command_cache[command] = CommandUtils.run_silent('which', command.to_s)
  end

  # Checks if a path is a valid directory (exists, is a directory, and is not root '/').
  # Mirrors is_directory() from .shellrc.
  #
  # @param path [Pathname, String, nil] Path to check
  # @return [Boolean] true if path is a non-root directory, false otherwise
  #
  # @example
  #   PathUtils.valid_directory?(Pathname.new('/tmp'))  # => true
  #   PathUtils.valid_directory?(Pathname.new('/'))     # => false (root excluded)
  #   PathUtils.valid_directory?(nil)                   # => false
  #   PathUtils.valid_directory?('')                    # => false
  def valid_directory?(path)
    return false if nil_or_empty?(path)
    return false if root_dir?(path)

    path_pn = path.is_a?(Pathname) ? path : Pathname.new(path.to_s)
    path_pn.directory?
  end

  # Checks if a path is the root directory '/'.
  # Mirrors is_root_dir() from .shellrc.
  #
  # @param path [Pathname, String, nil] Path to check
  # @return [Boolean] true if path is root '/', false otherwise
  #
  # @example
  #   PathUtils.root_dir?(Pathname.new('/'))      # => true
  #   PathUtils.root_dir?('/')                    # => true
  #   PathUtils.root_dir?(Pathname.new('/tmp'))   # => false
  #   PathUtils.root_dir?(nil)                    # => false
  def root_dir?(path)
    return false if nil_or_empty?(path)

    path_pn = path.is_a?(Pathname) ? path : Pathname.new(path.to_s)
    path_pn.to_s == File::SEPARATOR
  end

  # Checks if a path's parent directory is not root '/'.
  # Used to prevent write operations on paths directly in root directory.
  # Safe to call on both files and directories.
  #
  # @param path [Pathname, String, nil] Path to check
  # @return [Boolean] true if parent is not root, false if parent is root or path is invalid
  #
  # @example
  #   PathUtils.safe_for_write?(Pathname.new('/tmp/file'))     # => true (parent is /tmp)
  #   PathUtils.safe_for_write?(Pathname.new('/etc'))          # => false (parent is /)
  #   PathUtils.safe_for_write?(Pathname.new('/rootfile.txt')) # => false (parent is /)
  #   PathUtils.safe_for_write?(nil)                           # => false
  def safe_for_write?(path)
    return false if nil_or_empty?(path)

    path_pn = path.is_a?(Pathname) ? path : Pathname.new(path.to_s)
    parent = path_pn.parent

    !root_dir?(parent)
  end

  # Returns the size of a directory in kilobytes using du.
  # Uses MacOS::DU_CMD for reliability in cron/system contexts.
  #
  # @param dir [Pathname, String] Directory path to measure
  # @return [Integer] Size in kilobytes
  #
  # @example
  #   PathUtils.dir_size_kb(Pathname.new('/path/to/dir'))  # => 1024
  def dir_size_kb(dir)
    size_out = CommandUtils.query(MacOS::DU_CMD, '-sk', dir.to_s)
    size_out.split("\t").first.to_i
  end

  # Returns the size of a directory in human-readable format using du.
  # Uses MacOS::DU_CMD for reliability in cron/system contexts.
  #
  # @param dir [Pathname, String] Directory path to measure
  # @return [String] Human-readable size (e.g., "1.5G", "234M", "4.2K")
  #
  # @example
  #   PathUtils.dir_size_human(Pathname.new('/path/to/dir'))  # => "1.5G"
  def dir_size_human(dir)
    size_out = CommandUtils.query(MacOS::DU_CMD, '-sh', dir.to_s)
    size_out.split("\t").first
  end

  # Returns the pack size of a git repository in KB using git count-objects.
  # Approximately 2-3x faster than dir_size_kb for git repos (~10-20ms vs ~50ms).
  # Shows pack size only (excludes refs, logs, indexes, config) which is typically
  # 70-90% of total .git directory size.
  #
  # Only works for git repositories. For non-git directories, use dir_size_kb.
  #
  # @param repo_dir [Pathname, String] Git repository root or .git directory path
  # @return [Integer] Pack size in KB
  #
  # @example
  #   git_dir = EnvVars::DOTFILES_DIR.join('.git')
  #   PathUtils.git_repo_size_kb(git_dir)  # => 1408 (KB)
  def git_repo_size_kb(repo_dir)
    repo_path = repo_dir.to_s
    # If passed .git directory, use parent as repo root for git -C
    repo_path = File.dirname(repo_path) if repo_path.end_with?('.git')

    # Parse git count-objects output for size-pack line
    size_out = CommandUtils.query('git', '-C', repo_path, 'count-objects', '-vH')
    size_line = size_out.lines.find { |line| line.start_with?('size-pack:') }
    return 0 unless size_line

    # Extract number and unit (e.g., "1.37 MiB" -> ["1.37", "MiB"])
    parts = size_line.split
    size_value = parts[1].to_f
    size_unit = parts[2]

    # Convert to KB based on unit
    case size_unit
    when 'KiB' then size_value
    when 'MiB' then size_value * 1024
    when 'GiB' then size_value * 1024 * 1024
    when 'bytes' then size_value / 1024.0
    else 0
    end.to_i
  end

  # Returns the pack size of a git repository in human-readable format.
  # Calls the git size alias (which uses git count-objects internally).
  # Approximately 2-3x faster than dir_size_human for git repos (~10-20ms vs ~50ms).
  # Shows pack size only (excludes refs, logs, indexes, config) which is typically
  # 70-90% of total .git directory size.
  #
  # Only works for git repositories. For non-git directories, use dir_size_human.
  #
  # @param repo_dir [Pathname, String] Git repository root or .git directory path
  # @return [String] Pack size in human-readable format (e.g., "1.37 MiB", "503.45 MiB")
  #
  # @example
  #   git_dir = EnvVars::DOTFILES_DIR.join('.git')
  #   PathUtils.git_repo_size_human(git_dir)  # => "1.37 MiB"
  def git_repo_size_human(repo_dir)
    repo_path = repo_dir.to_s
    # If passed .git directory, use parent as repo root for git -C
    repo_path = File.dirname(repo_path) if repo_path.end_with?('.git')

    # Call git size alias with GIT_SIZE_QUIET to get just the size
    ENV['GIT_SIZE_QUIET'] = '1'
    size_out = CommandUtils.query('git', '-C', repo_path, 'size')
    ENV.delete('GIT_SIZE_QUIET')

    size_out.strip
  end

  # Extract a path segment at a given index from a dir path
  #
  # @param dir [String] The dir path
  # @param index [Integer] The segment index (default: -1, the last segment)
  # @return [String, nil] The path segment at the index, or nil if index out of bounds
  #
  # @example
  #   PathUtils.extract_path_segment_at('/home/user/projects', -1)  # => 'projects'
  def extract_path_segment_at(dir, index = -1)
    File.dirname(dir).split(File::SEPARATOR)[index]
  end

  # Yields Pathname objects for each match from Dir.glob, converting strings to Pathname.
  # Dir.glob returns strings; this helper immediately converts them so callers work with
  # Pathname throughout without repeated Pathname.new() at every call site.
  #
  # @param pattern [Pathname, String] Glob pattern (can be Pathname with embedded pattern).
  # @param flags [Integer] Optional Dir.glob flags (e.g., File::FNM_CASEFOLD).
  # @yield [pathname] Each matched path as a Pathname object.
  # @yieldparam pathname [Pathname]
  # @return [void]
  #
  # @example
  #   PathUtils.glob_pathnames(base_dir.join('**', '*.txt')) do |file|
  #     puts file.size  # file is already a Pathname
  #   end
  def glob_pathnames(pattern, flags = 0)
    return unless block_given?

    Dir.glob(pattern, flags).each do |path_str|
      yield Pathname.new(path_str)
    end
  end

  # ---------------------------------------------------------------------------
  # Mutation methods (modify state)
  # ---------------------------------------------------------------------------

  # Ensures the specified directories exist, creating them if necessary.
  # Accepts a single path or an array of paths. Skips any empty paths.
  #
  # @param dirs [Pathname, String, Array<Pathname, String>] Single directory path or array of paths
  # @return [void]
  #
  # @example Single path
  #   PathUtils.ensure_directories_exist(EnvVars::XDG_CONFIG_HOME)
  #   PathUtils.ensure_directories_exist('/tmp/my-dir')
  #
  # @example Array of paths
  #   PathUtils.ensure_directories_exist([EnvVars::XDG_CONFIG_HOME, EnvVars::XDG_CACHE_HOME])
  def ensure_directories_exist(dirs)
    # Normalize to array (handles single path or array)
    Array(dirs).each do |dir|
      next if nil_or_empty?(dir.to_s)

      (dir.is_a?(Pathname) ? dir : Pathname.new(dir)).mkpath
      Logging.debug "Ensured directory exists: '#{dir.to_s.cyan}'"
    end
  end
end
