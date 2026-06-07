#!/usr/bin/env ruby
# frozen_string_literal: true

# Shared path and command utilities for Ruby scripts across all scripts
#
# Usage:
#   require 'path_utils'

# Module for common file, path, and command utilities
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

  # Extract a path segment at a given index from a folder path
  #
  # @param folder [String] The folder path
  # @param index [Integer] Which path component to extract (-1 for last, -2 for parent, etc.)
  # @return [String] The extracted path segment
  #
  # @example
  #   PathUtils.extract_path_segment_at('/home/user/projects/myapp/src')
  #   # => 'myapp'
  def extract_path_segment_at(folder, index = -1)
    File.dirname(folder).split(File::SEPARATOR)[index]
  end
end
