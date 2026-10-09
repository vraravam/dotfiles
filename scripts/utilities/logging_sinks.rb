#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

require_relative 'core'
require_relative 'env_vars'

module Logging
  # Log-level filtering and the optional LOG_FILE sink (text or JSON, with rotation).
  # Mixed into Logging; relies on Logging#state and Logging#warn.
  module Sinks
    include Core

    # Log levels in priority order (lowest to highest severity).
    # Used for filtering based on LOG_LEVEL environment variable.
    LOG_LEVELS = {
      debug: 0,
      info: 1,
      success: 2,
      warn: 3,
      error: 4,
      user_action: 5
    }.freeze

    # Maximum size of the log file before it is rotated.
    MAX_LOG_BYTES = 10 * 1024 * 1024

    # Number of rotated backups kept (log.1 .. log.N).
    LOG_BACKUPS = 5

    private

    # Maps the severity marker embedded in a formatted console message back to its level,
    # so the file sink can record the same level the console prefix implies.
    #
    # @param message [String] Formatted console message (may contain ANSI codes)
    # @return [Symbol] Log level (:info when no marker is present)
    # :reek:UtilityFunction -- Stateless classifier of its argument
    def _log_level_for(message)
      case message
      when /\*\*SUCCESS\*\*/ then :success
      when /\*\*WARN\*\*/ then :warn
      when /\*\*DEBUG\*\*/ then :debug
      when /\*\*ERROR\*\*/ then :error
      when /\*\*ACTION\*\*/ then :user_action
      else :info
      end
    end

    # Checks if a log message at the given level should be printed.
    # Compares requested level against LOG_LEVEL environment variable.
    # Returns true if message level >= configured minimum level.
    #
    # Log levels (severity order): debug < info < success < warn < error < user_action
    #
    # Examples:
    #   LOG_LEVEL=debug -> show all messages
    #   LOG_LEVEL=info  -> show info, success, warn, error, user_action (default)
    #   LOG_LEVEL=warn  -> show only warn, error, user_action
    #   LOG_LEVEL=error -> show only error
    #
    # @param level [Symbol] The log level to check (:debug, :info, :success, :warn, :error, :user_action)
    # @return [Boolean] true if message should be logged, false otherwise
    def _should_log?(level)
      # Cache the configured minimum level (avoid repeated ENV lookups)
      state.min_log_level ||= LOG_LEVELS.fetch(EnvVars.log_level, LOG_LEVELS[:info])

      # Allow message if its priority >= configured minimum
      LOG_LEVELS[level] >= state.min_log_level
    end

    # Writes log entry to file if LOG_FILE is set.
    # Handles log rotation (keeps LOG_BACKUPS files of at most MAX_LOG_BYTES each).
    # Format determined by LOG_FORMAT env var (json or human-readable).
    #
    # @param level [Symbol] Log level
    # @param message [String] Log message (plain text, no color codes)
    # @return [void]
    def _write_to_log_file(level, message)
      log_file = EnvVars.log_file
      return if nil_or_empty?(log_file)

      log_path = Pathname.new(log_file)
      _rotate_log_if_needed(log_path)

      # Determine format
      format = EnvVars.log_format

      entry = if format == 'json'
                _format_json_log_entry(level, message)
              else
                _format_text_log_entry(level, message)
              end

      File.open(log_path, 'a') do |f|
        f.puts(entry)
      end
    rescue StandardError => e
      # Log file write failures should not crash the script
      warn "Failed to write to log file: #{e.message}" if EnvVars.debug?
    end

    # Formats log entry as JSON.
    #
    # @param level [Symbol] Log level
    # @param message [String] Log message
    # @return [String] JSON-formatted log entry
    def _format_json_log_entry(level, message)
      # Required lazily: file logging is opt-in, and json + time cost ~9ms to load, which
      # every script (including per-command git aliases) would otherwise pay at startup.
      require 'json'
      require 'time' # Time#iso8601 is not core in Ruby 2.6

      {
        timestamp: Time.now.utc.iso8601,
        level: level.to_s.upcase,
        message: message.strip,
        script: EnvVars.log_script_name,
        depth: EnvVars.script_depth,
        section: state.current_section
      }.to_json
    end

    # Formats log entry as human-readable text.
    #
    # @param level [Symbol] Log level
    # @param message [String] Log message
    # @return [String] Text-formatted log entry
    def _format_text_log_entry(level, message)
      "[#{Core.current_timestamp}] [#{level.to_s.upcase}] #{message.strip}"
    end

    # Rotates the log file once it exceeds MAX_LOG_BYTES, keeping log.1 .. log.LOG_BACKUPS.
    #
    # @param log_path [Pathname] Path to log file
    # @return [void]
    def _rotate_log_if_needed(log_path)
      return unless log_path.file?
      return if log_path.size < MAX_LOG_BYTES

      require 'fileutils' # only a rotation needs it (loaded lazily, see _format_json_log_entry)

      # Rotate existing backups (log.4 -> log.5, log.3 -> log.4, etc.)
      (LOG_BACKUPS - 1).downto(1) do |i|
        old_file = Pathname.new("#{log_path}.#{i}")
        new_file = Pathname.new("#{log_path}.#{i + 1}")
        FileUtils.mv(old_file.to_s, new_file.to_s) if old_file.exist?
      end

      # Move current log to .1
      FileUtils.mv(log_path.to_s, "#{log_path}.1")

      # Delete the backup that would exceed LOG_BACKUPS, if a previous run left one.
      oldest = Pathname.new("#{log_path}.#{LOG_BACKUPS + 1}")
      oldest.delete if oldest.exist?
    end
  end
end
