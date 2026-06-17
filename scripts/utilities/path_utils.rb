#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'pathname'

require_relative 'macos'

# Command and path manipulation utilities for Ruby scripts.
#
# For environment variable paths (HOME, DOTFILES_DIR, etc.), use EnvVars instead.
# For macOS system command paths (DEFAULTS_CMD, OSASCRIPT_CMD, etc.), use MacOS instead.
#
# Usage:
#   require 'path_utils'

# Module for command existence checks and path manipulation utilities.
# Generic (cross-platform) utilities only -- macOS-specific paths are in MacOS module.
module PathUtils
  extend self

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
    system('which', command.to_s, out: File::NULL, err: File::NULL)
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
    du_out, = Open3.capture3(MacOS::DU_CMD, '-sk', dir.to_s)
    du_out.split("\t").first.to_i
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
    size_out, = Open3.capture3(MacOS::DU_CMD, '-sh', dir.to_s)
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
end
