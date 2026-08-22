#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'
require_relative 'colorizable'

# Extends Pathname with color methods from Colorizable module.
# This allows pathname.cyan instead of pathname.to_s.cyan throughout the codebase.
#
# Design: When Pathname includes Colorizable, the color methods automatically
# convert to String first (via colorize's is_a? check), then apply ANSI codes.
# This means:
#   - pathname.cyan works and returns a colored String
#   - system('ls', pathname) still works (system calls pathname.to_s which returns plain String)
#   - No risk of passing ANSI codes to system commands
class Pathname
  include Colorizable
end
