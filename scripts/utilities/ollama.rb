#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'core'
require_relative 'command_utils'
require_relative 'env_vars'
require_relative 'logging'

module Ollama
  extend self

  COMMAND = 'ollama'

  # @return [Boolean] true if 'mise' is on PATH
  def available?
    PathUtils.command_exists?(COMMAND)
  end

  # Lists every unique ollama model from the local machine.
  # @return [Array<String>] Non-blank list of models on the local machine
  def list
    unless available?
      Logging.skip_tool(COMMAND)
      return []
    end

    stdout = CommandUtils.query(COMMAND, 'list')
    stdout.lines[1..-1].filter_map { |line| line.split.first }.uniq
  end

  # Pulls (upgrades) all local ollama models.
  # @return void
  def pull(model:)
    unless available?
      Logging.skip_tool(COMMAND)
      return nil
    end

    raise ArgumentError, 'Model name expected' if model.empty?

    Logging.info "Pulling '#{model.to_s.yellow}'"
    CommandUtils.stream_command([COMMAND, 'pull', model])
    Logging.info "Successfully updated: '#{model.to_s.yellow}'"
  rescue SystemExit => e
    Logging.record_error "Failed to pull model '#{model.to_s.yellow}' -- #{e.message.red}"
  rescue StandardError => e
    Logging.record_error "Failed to pull model '#{model.to_s.yellow}' -- #{e.class.to_s.red}: #{e.message.red}"
  end
  nil
end
