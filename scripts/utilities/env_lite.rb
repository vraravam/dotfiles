#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Dependency-free environment accessors for the lowest layers of the utility stack.
#
# EnvVars requires Core (for nil_or_empty?), and Core -> PathnameExt -> Colorizable sit
# underneath it, so none of those can require EnvVars without a circular dependency.
# This module has NO requires and is the one place those layers read ENV; EnvVars
# delegates its identically-named accessors here so there is a single source of truth.
#
# Everything above Core should use EnvVars, not this module.
module EnvLite
  extend self

  # @param name [String] Environment variable name
  # @return [Boolean] true when the variable is set to a non-blank value
  def set?(name)
    !ENV.fetch(name, '').strip.empty?
  end

  # @return [String] The HOME directory path ('' when unset)
  def home
    ENV.fetch('HOME', '')
  end

  # Mirrors: FORCE_COLOR env var (standard convention for forcing color output)
  #
  # @return [Boolean] true if FORCE_COLOR is set to a non-blank value
  def force_color?
    set?('FORCE_COLOR')
  end
end
