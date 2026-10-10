#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

require_relative 'command_utils'
require_relative 'core'
require_relative 'path_utils'

# Thin command wrappers around 'mise' (the polyglot tool-version manager), in the same
# spirit as Brew: no iteration, no progress logging. DevEnvironment decides which
# directories to process and how to report the outcome.
module Mise
  extend self
  extend Core # For module methods (stream_command)

  # Config filenames that indicate a directory declares tool versions.
  CONFIG_FILES = %w[
    .mise.toml
    .tool-versions
    .ruby-version
    .python-version
    .node-version
    .java-version
    .nvmrc
  ].freeze

  # @return [Boolean] true if 'mise' is on PATH
  def available?
    PathUtils.command_exists?('mise')
  end

  # @param dir [String, Pathname] Directory to inspect
  # @return [Boolean] true if +dir+ contains any file mise reads tool versions from
  def config?(dir)
    dir_path = Pathname.new(dir)
    CONFIG_FILES.any? { |cfg| dir_path.join(cfg).file? }
  end

  # Trusts every mise config file in +dir+ (quick, output is captured).
  #
  # @param dir [String, Pathname] Directory whose configs to trust
  # @yield [status, output_message] Called only on failure (see CommandUtils.capture_output)
  # @return [Boolean] true if trusting succeeded
  def trust(dir, &block)
    CommandUtils.capture_output('mise', '-C', dir.to_s, 'trust', '-y', '-a', &block)
  end

  # Installs the tool versions declared in +dir+. Output is streamed because downloads and
  # builds are slow and the user wants to see progress.
  #
  # @param dir [String, Pathname] Directory whose declared versions to install
  # @return [Integer] exit status of 'mise install' (0 on success)
  def install(dir)
    stream_command(['mise', '-C', dir.to_s, 'install'])
  end
end
