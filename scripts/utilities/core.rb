#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'

# Core utility module with minimal dependencies.
# Provides foundational helpers used by other utility modules.
#
# **CRITICAL: This module must remain dependency-free and OS-agnostic.**
#
# Rules for adding methods to this module:
# 1. **ZERO requires** except Ruby stdlib (pathname, fileutils, etc.)
#    - Never require other utilities/* modules (creates circular dependencies)
#    - Never require gems or external dependencies
#
# 2. **OS-agnostic only** - methods must work on any platform
#    - No macOS-specific calls (osascript, defaults, softwareupdate, etc.)
#    - No Linux-specific calls (systemctl, apt, etc.)
#    - Only cross-platform Ruby stdlib and standard Unix tools
#
# 3. **Check ENV directly** when needed, not via EnvVars module
#    - EnvVars requires Core, so Core cannot require EnvVars (circular dependency)
#    - Use ENV.fetch('VAR', 'default') directly in method bodies
#
# 4. **Examples of appropriate methods for Core:**
#    - nil_or_empty? checks (pure Ruby logic)
#    - Timestamp formatting (Time.now.strftime - pure Ruby)
#    - TTY detection ($stdout.tty? - Ruby stdlib)
#    - Stream command execution (IO.popen - Ruby stdlib)
#    - Path constants (Pathname - Ruby stdlib)
#
# 5. **Examples of methods that belong elsewhere:**
#    - macOS notifications → MacOS module
#    - Git operations → GitProcessor module
#    - Homebrew queries → CommandUtils module
#    - Logging with colors → Logging module
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

  # Returns the current wall-clock time formatted as 'YYYY-MM-DD HH:MM:SS'.
  # Used for git commit messages, user-facing timestamps, and logging.
  # Mirrors current_timestamp function in .shellrc.
  #
  # @return [String] Formatted timestamp
  #
  # @example
  #   Core.current_timestamp  # => "2026-07-27 08:45:00"
  def current_timestamp
    Time.now.strftime('%Y-%m-%d %H:%M:%S')
  end

  # Checks if the script is running in a TTY (terminal) context.
  # Returns true when stdout is a TTY or FORCE_COLOR env var is set.
  # Used to gate interactive operations (app kill/restart, prompts, etc.)
  # that should not run in cron or non-interactive contexts.
  #
  # @return [Boolean] true if running in TTY context
  #
  # @example
  #   Core.running_in_tty?  # => true (in terminal), false (in cron)
  def running_in_tty?
    # Check FORCE_COLOR directly to avoid circular dependency with EnvVars
    # (EnvVars requires this module via Core)
    $stdout.tty? || !ENV.fetch('FORCE_COLOR', '').strip.empty?
  end

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
