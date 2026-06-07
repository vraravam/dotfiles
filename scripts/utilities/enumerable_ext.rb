#!/usr/bin/env ruby
# frozen_string_literal: true

# Polyfills for Enumerable methods added after Ruby 2.6 (system Ruby on vanilla macOS).
# Each polyfill is guarded so the native method is used on Ruby 2.7+ without any overhead.
#
# Usage:
#   require 'enumerable_ext'

# Enumerable#filter_map was added in Ruby 2.7.
unless Enumerable.method_defined?(:filter_map)
  module Enumerable
    def filter_map(&block)
      return to_enum(:filter_map) unless block

      map(&block).compact
    end
  end
end
