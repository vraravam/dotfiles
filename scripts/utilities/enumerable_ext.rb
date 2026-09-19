#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Polyfills for Enumerable methods added after Ruby 2.6 (system Ruby on vanilla macOS).
# Each polyfill is guarded so the native method is used on Ruby 2.7+ without any overhead.
#
# Usage:
#   require 'enumerable_ext'
#
# TODO: This file can be removed once macOS ships with Ruby 2.7+ as default system Ruby.
#       All call sites can then use native filter_map with no polyfill required.

# Enumerable#filter_map was added in Ruby 2.7.
unless Enumerable.method_defined?(:filter_map)
  module Enumerable
    # Maps each item through the block, keeping only the non-nil results --
    # a single-pass alternative to `map(&block).compact` (avoids the
    # intermediate array `compact` would otherwise allocate).
    #
    # @yieldparam item each element of the enumerable
    # @return [Array, Enumerator] the filtered/mapped results, or an
    #   Enumerator if no block is given
    def filter_map(&block)
      return to_enum(:filter_map) unless block

      # Single-pass loop instead of map + compact (reduces intermediate array allocation)
      each_with_object([]) do |item, result|
        value = block.call(item)
        result << value unless value.nil?
      end
    end
  end
end
