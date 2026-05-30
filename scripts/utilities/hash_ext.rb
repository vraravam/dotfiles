#!/usr/bin/env ruby
# frozen_string_literal: true

# Extend Hash class with deep sort functionality
#
# Usage:
#   require 'hash_ext'

# Extend Hash class with additional utility methods
class Hash
  # Recursively sort a hash by keys (deep sort)
  #
  # @return [Hash] A new hash with all keys sorted recursively
  #
  # @example
  #   { b: { d: 1, c: 2 }, a: 3 }.deep_sort
  #   # => { a: 3, b: { c: 2, d: 1 } }
  def deep_sort
    transform_values { |v| v.is_a?(Hash) ? v.deep_sort : v }.sort.to_h
  end
end
