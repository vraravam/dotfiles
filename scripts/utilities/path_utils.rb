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

  # Prepends a directory to PATH if it exists and is not already in PATH.
  # Mirrors the intent of append_to_path_if_dir_exists from .shellrc but prepends
  # instead (scripts directories should override system versions, not be shadowed by them).
  #
  # @param dir [Pathname, String] Directory path to prepend to PATH
  # @return [void]
  #
  # @example
  #   PathUtils.prepend_to_path(EnvVars::DOTFILES_DIR.join('scripts'))
  #   PathUtils.prepend_to_path('/usr/local/bin')
  def prepend_to_path(dir)
    return if nil_or_empty?(dir.to_s)

    dir_str = dir.to_s
    return unless Pathname.new(dir_str).directory?

    current_path = EnvVars.path
    # Check if directory is already in PATH (anywhere, not just at the start)
    path_components = current_path.split(':')
    return if path_components.include?(dir_str)

    # Prepend to PATH
    ENV['PATH'] = "#{dir_str}:#{current_path}"
    Logging.debug "Prepended to PATH: '#{dir_str.cyan}'"
  end

  # Sets correct permissions on ~/.ssh directory and its contents.
  # Directory: 700, Files: 600. Also adds SSH keys to macOS Keychain.
  #
  # @return [void]
  def set_ssh_folder_permissions
    ssh_dir = EnvVars::HOME.join('.ssh')

    Logging.info "Setting ssh config file permissions".yellow
    ensure_directories_exist(ssh_dir)

    # Set directory permissions first
    unless CommandUtils.run_silent('chmod', '700', ssh_dir.to_s)
      Logging.warn "Failed to set permissions on '#{ssh_dir.to_s.cyan}'"
      return
    end

    # Check if directory is empty
    if Dir.empty?(ssh_dir)
      Logging.warn "'#{ssh_dir.to_s.cyan}' exists but is empty. No file permissions to set."
      return
    end

    # Set file permissions
    files = ssh_dir.children.select(&:file?)
    files.each do |file|
      unless CommandUtils.run_silent('chmod', '600', file.to_s)
        Logging.warn "Failed to set permissions on '#{file.to_s.cyan}'"
      end
    end
    Logging.success "Ensured correct permissions for '#{ssh_dir.to_s.cyan}' and files within it."

    # Add keys to ssh-agent and store in macOS Keychain for persistence.
    # --apple-use-keychain (macOS 12+) stores passphrases in Keychain so keys persist
    # across reboots and are available to all processes. Without this, keys are only
    # added to the current ssh-agent session and subprocesses may not have access.
    # Fallback to -K for older macOS versions (deprecated but still works).
    key_files = ssh_dir.children.select { |f| f.file? && f.basename.to_s.start_with?('id_') && f.extname.empty? }
    if key_files.empty?
      Logging.debug "No SSH keys found in '#{ssh_dir.to_s.cyan}'"
      return
    end

    success = key_files.all? do |key_file|
      CommandUtils.run_silent('ssh-add', '--apple-use-keychain', key_file.to_s) ||
        CommandUtils.run_silent('ssh-add', '-K', key_file.to_s)
    end

    if success
      Logging.success "Added ssh identity files from '#{ssh_dir.to_s.cyan}' to ssh-agent and macOS Keychain."
    else
      Logging.warn "Failed to add some ssh identity files from '#{ssh_dir.to_s.cyan}'"
    end
  end
end
