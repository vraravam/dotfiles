#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'core'
require_relative 'colorizable'

class String
  include Core        # For instance methods (in blocks)
  extend Core         # For module methods
  include Colorizable # Color methods (cyan, yellow, etc.)

  # Checks if the string should be skipped when reading config/data files.
  # Returns true for empty lines (after stripping) or comment lines (starting with '#').
  # Common pattern when parsing text files with comments.
  #
  # @return [true, false]
  def comment_or_empty?
    stripped = strip
    nil_or_empty?(stripped) || stripped.start_with?('#')
  end
end
