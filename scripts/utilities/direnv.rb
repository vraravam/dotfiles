#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

require_relative 'command_utils'
require_relative 'path_utils'

# Thin command wrappers around 'direnv', in the same spirit as Brew: no iteration, no
# progress logging. DevEnvironment decides which directories to process and how to
# report the outcome.
module Direnv
  extend self

  # @return [Boolean] true if 'direnv' is on PATH
  def available?
    PathUtils.command_exists?('direnv')
  end

  # @param dir [String, Pathname] Directory to inspect
  # @return [Boolean] true if +dir+ contains an .envrc
  def envrc?(dir)
    Pathname.new(dir).join('.envrc').file?
  end

  # Trusts and then evaluates the .envrc in +dir+.
  #
  # 'direnv allow' only records trust -- it never evaluates the .envrc. The shell hook does
  # that on the next interactive 'cd', so side effects of the .envrc (e.g. the profile
  # symlinks created by the browser-profiles .envrc) would not exist until then.
  # 'direnv exec' evaluates the .envrc immediately, with no TTY or hook required.
  #
  # @param dir [String, Pathname] Directory containing the .envrc
  # @return [Boolean] true if both steps succeeded
  def activate(dir)
    CommandUtils.run_silent('direnv', 'allow', dir.to_s) && CommandUtils.run_silent('direnv', 'exec', dir.to_s, 'true')
  end
end
