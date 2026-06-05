#!/usr/bin/env ruby
# frozen_string_literal: true

# Shared path utilities for Ruby scripts across all scripts
#
# Usage:
#   require 'path_utils'

# Module for common file and path utilities
module PathUtils
  # Extract a path segment at a given index from a folder path
  #
  # @param folder [String] The folder path
  # @param index [Integer] Which path component to extract (-1 for last, -2 for parent, etc.)
  # @return [String] The extracted path segment
  #
  # @example
  #   PathUtils.extract_path_segment_at('/home/user/projects/myapp/src')
  #   # => 'myapp'
  def self.extract_path_segment_at(folder, index = -1)
    File.dirname(folder).split(File::SEPARATOR)[index]
  end
end
