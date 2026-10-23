#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

require_relative 'command_utils'
require_relative 'core'
require_relative 'env_vars'
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

  # Commands already found on PATH. Only hits are cached: a miss must be re-checked next time,
  # because the command may be installed (e.g. by 'brew install') while this process runs.
  @command_cache = {}

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Query methods (read-only state inspection)
  # ---------------------------------------------------------------------------

  # Checks if a command exists in the system PATH.
  # Mirrors command_exists() from .shellrc.
  #
  # Scans PATH in-process (a regular, executable file per entry) rather than forking 'which',
  # which costs ~6ms per distinct command. A command containing '/' is checked as a path, like
  # the shell does. Only positive results are memoized (see @command_cache).
  #
  # @param command [String] The command name to check
  # @return [Boolean] true if the command exists in PATH, false otherwise
  #
  # @example
  #   PathUtils.command_exists?('ruby')  # => true
  #   PathUtils.command_exists?('nosuchcommand')  # => false
  def command_exists?(command)
    return true if @command_cache[command]

    found = _executable_on_path?(command.to_s)
    @command_cache[command] = true if found
    found
  end

  # Checks if a path is a valid directory (exists, is a directory, and is not root '/').
  # Mirrors is_directory() from .shellrc.
  #
  # @param path [Pathname, String, nil] Path to check
  # @return [Boolean] true if path is a non-root directory, false otherwise
  #
  # @example
  #   PathUtils.valid_directory?(Pathname('/tmp'))  # => true
  #   PathUtils.valid_directory?(Pathname('/'))     # => false (root excluded)
  #   PathUtils.valid_directory?(nil)                   # => false
  #   PathUtils.valid_directory?('')                    # => false
  def valid_directory?(path)
    return false if nil_or_empty?(path)
    return false if root_dir?(path)

    Pathname(path.to_s).directory?
  end

  # Checks if a path is the root directory '/'.
  # Mirrors is_root_dir() from .shellrc.
  #
  # @param path [Pathname, String, nil] Path to check
  # @return [Boolean] true if path is root '/', false otherwise
  #
  # @example
  #   PathUtils.root_dir?(Pathname('/'))      # => true
  #   PathUtils.root_dir?('/')                    # => true
  #   PathUtils.root_dir?(Pathname('/tmp'))   # => false
  #   PathUtils.root_dir?(nil)                    # => false
  def root_dir?(path)
    return false if nil_or_empty?(path)

    path.to_s == File::SEPARATOR
  end

  # Checks if a path's parent directory is not root '/'.
  # Used to prevent write operations on paths directly in root directory.
  # Safe to call on both files and directories.
  #
  # @param path [Pathname, String, nil] Path to check
  # @return [Boolean] true if parent is not root, false if parent is root or path is invalid
  #
  # @example
  #   PathUtils.safe_for_write?(Pathname('/tmp/file'))     # => true (parent is /tmp)
  #   PathUtils.safe_for_write?(Pathname('/etc'))          # => false (parent is /)
  #   PathUtils.safe_for_write?(Pathname('/rootfile.txt')) # => false (parent is /)
  #   PathUtils.safe_for_write?(nil)                           # => false
  def safe_for_write?(path)
    return false if nil_or_empty?(path)

    !root_dir?(Pathname(path.to_s).parent)
  end

  # Returns the size of a file/directory in kilobytes using du.
  # Uses MacOS::DU_CMD for reliability in cron/system contexts.
  # Returns 0 if the file/directory does not exist.
  #
  # @param dir [Pathname, String] File/Directory path to measure
  # @return [Integer] Size in kilobytes
  #
  # @example
  #   PathUtils.size_kb(Pathname('/path/to/dir'))  # => 1024
  # :reek:UtilityFunction -- Stateless utility that operates only on arguments
  def size_kb(dir)
    File.exist?(dir) ? CommandUtils.query(MacOS::DU_CMD, '-skA', dir.to_s).split("\t").first.to_i : 0
  end

  # Converts a size in KB to a short human-readable IEC string, the format `numfmt --to=iec`
  # produces (which is not stock macOS, so it is computed here): 1024-based units, whole numbers
  # below 1K, one decimal below 10 and a whole number from 10 up, always rounded away from zero
  # (e.g. 1.5K, 234M, 10G, 0).
  #
  # @param kb [Integer] Size in kilobytes (may be negative, e.g. space saved)
  # @return [String] e.g. "1.5G", "234M"
  def format_size(kb) # rubocop:disable Naming/MethodParameterName
    value = kb * 1024
    return value.to_s if value.abs < 1024

    units = %w[K M G T P E Z Y]
    scaled = value.abs.to_f
    unit_idx = -1
    while scaled >= 1024 && unit_idx < units.size - 1
      scaled /= 1024
      unit_idx += 1
    end
    # Rounding up can reach 1024 of this unit (1023.5K): that is 1.0 of the next one.
    shown = scaled < 10 ? (scaled * 10).ceil / 10.0 : scaled.ceil.to_f
    if shown >= 1024 && unit_idx < units.size - 1
      shown = 1.0
      unit_idx += 1
    end
    text = shown < 10 ? format('%<n>.1f', n: shown) : shown.to_i.to_s
    "#{'-' if value.negative?}#{text}#{units[unit_idx]}"
  end

  # Extract a path segment at a given index from a dir path
  #
  # @param dir [String] The dir path
  # @param index [Integer] The segment index (default: -1, the last segment)
  # @return [String, nil] The path segment at the index, or nil if index out of bounds
  #
  # @example
  #   PathUtils.extract_path_segment_at('/home/user/projects', -1)  # => 'projects'
  # :reek:UtilityFunction -- Stateless utility that operates only on arguments
  def extract_path_segment_at(dir, index = -1)
    File.dirname(dir).split(File::SEPARATOR)[index]
  end

  # Yields Pathname objects for each match from Dir.glob, converting strings to Pathname.
  # Dir.glob returns strings; this helper immediately converts them so callers work with
  # Pathname throughout without repeated Pathname() at every call site.
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
      yield Pathname(path_str)
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

      Pathname(dir).mkpath
      Logging.debug "Ensured directory exists: '#{dir.cyan}'"
    end
  end

  # Appends a directory to PATH (lowest priority, so it can never shadow a system or Homebrew
  # command) if it exists and is not already in PATH. Mirrors append_to_path_if_dir_exists in
  # .shellrc.
  #
  # @param dir [Pathname, String] Directory path to append to PATH
  # @return [void]
  #
  # @example
  #   PathUtils.append_to_path(EnvVars::DOTFILES_DIR.join('scripts'))
  # :reek:FeatureEnvy -- Stateless PATH manipulation on the given dir (intentional)
  def append_to_path(dir)
    # Checked on the string: Pathname#empty? asks whether a *directory is empty*, not whether the
    # path is blank, so nil_or_empty?(dir) would wrongly skip an existing empty directory.
    return if nil_or_empty?(dir.to_s)

    # Pathname() returns a Pathname argument as is and wraps a String, so both are handled without
    # a round trip through a string.
    path = Pathname(dir)
    return unless path.directory?

    dir_str = path.to_s
    current_path = EnvVars.path
    return if current_path.split(':').include?(dir_str)

    ENV['PATH'] = "#{current_path}:#{dir_str}"
    Logging.debug "Appended to PATH: '#{dir_str.cyan}'"
  end

  private

  # @param command [String] A bare command name, or a path (when it contains '/')
  # @return [Boolean] true when it resolves to a regular, executable file
  def _executable_on_path?(command)
    return false if command.empty?
    return _executable_file?(command) if command.include?(File::SEPARATOR)

    EnvVars.path.split(File::PATH_SEPARATOR).any? do |dir|
      !dir.empty? && _executable_file?(File.join(dir, command))
    end
  end

  # @return [Boolean] true for a regular file (symlinks followed) with an execute bit
  def _executable_file?(path)
    File.file?(path) && File.executable?(path)
  end
end
