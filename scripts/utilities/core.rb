#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'

# Core utility module with minimal dependencies.
# Provides foundational helpers used by other utility modules.
# This module must have ZERO requires (except stdlib) to avoid circular dependencies.
#
# Other utility modules can include Core to get unqualified access to helpers.
module Core
  extend self

  # Filesystem root directory (/).
  # Use this instead of hardcoded '/' for consistency with other path constants.
  #
  # @example
  #   Core::ROOT.join('usr', 'bin', 'defaults')  # => Pathname('/usr/bin/defaults')
  ROOT = Pathname.new(File::SEPARATOR).freeze

  # Checks if a value is nil or empty.
  # - String: strips whitespace first, then checks if empty
  # - Array: checks if empty (no elements)
  # - Other types: converts to string and checks if empty
  #
  # @param val [Object] Value to check
  # @return [Boolean] true if val is nil or empty
  #
  # @example
  #   Core.nil_or_empty?(nil)        # => true
  #   Core.nil_or_empty?('')         # => true
  #   Core.nil_or_empty?('  ')       # => true (whitespace-only string)
  #   Core.nil_or_empty?([])         # => true
  #   Core.nil_or_empty?('text')     # => false
  #   Core.nil_or_empty?([1, 2])     # => false
  #   Core.nil_or_empty?(123)        # => false (converts to "123")
  def nil_or_empty?(val)
    return true if val.nil?

    case val
    when String
      val.strip.empty?
    when Array
      val.empty?
    else
      val.to_s.empty?
    end
  end

  # Executes a command with real-time output streaming and optional stdin data.
  # Streams stdout to the terminal as the command runs (no buffering).
  # Returns the exit status of the command.
  #
  # Use this for long-running commands where users need progress feedback
  # (brew bundle, git operations, etc.). For commands where you need to parse
  # output, use Open3.capture2/capture3 instead.
  #
  # @param cmd [Array<String>] Command and arguments to execute
  # @param stdin_data [String, nil] Optional data to write to command's stdin
  # @return [Integer] Exit status code (0 = success, non-zero = failure)
  #
  # @example Basic command (no stdin)
  #   exitstatus = Core.stream_command(['brew', 'bundle'])
  #   if exitstatus.zero?
  #     puts "Success!"
  #   else
  #     puts "Failed with exit code #{exitstatus}"
  #   end
  #
  # @example Command with stdin data
  #   brewfile_content = "tap 'homebrew/core'\nbrew 'git'"
  #   exitstatus = Core.stream_command(['brew', 'bundle', '--file=-'], stdin_data: brewfile_content)
  def stream_command(cmd, stdin_data: nil)
    io = IO.popen(cmd, 'r+')

    # Write stdin data if provided
    if stdin_data
      io.write(stdin_data)
      io.close_write
    end

    # Stream output to stdout in real-time
    IO.copy_stream(io, $stdout)
    io.close

    # Return exit status
    $?.exitstatus || 0
  end
end
