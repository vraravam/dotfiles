#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'

# Command and path manipulation utilities for Ruby scripts.
#
# For environment variable paths (HOME, DOTFILES_DIR, etc.), use EnvVars instead.
#
# Usage:
#   require 'path_utils'

# Module for command existence checks, path segment extraction, and path constants.
module PathUtils
  extend self

  # Filesystem root as a Pathname object. Use for joining relative paths that should
  # be resolved from the filesystem root rather than the current working directory.
  #
  # @example
  #   PathUtils::ROOT.join('.config', 'file.txt')  # => Pathname('/config/file.txt')
  ROOT = Pathname.new(File::SEPARATOR).freeze

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
