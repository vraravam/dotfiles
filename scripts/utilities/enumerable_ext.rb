#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8

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
