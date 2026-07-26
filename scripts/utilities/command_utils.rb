#!/usr/bin/env ruby
# frozen_string_literal: true

# Utility methods for executing external commands with consistent error handling.

require 'open3'
require_relative 'core'
require_relative 'string'

module CommandUtils
  extend self
  include Core

  # Executes a command via Open3.capture3 and yields failure details on error.
  #
  # Captures stdout and stderr, checks the exit status, and on failure yields
  # the status object and a formatted output message string containing stdout
  # and stderr sections (with stderr colored red).
  #
  # @param command [Array<String>] Command and arguments to execute
  # @yield [status, output_message] Block receives status and formatted output on failure
  # @return [Boolean] true if command succeeded, false otherwise
  #
  # @example
  #   success = CommandUtils.capture_output('mise', '-C', dir, 'trust') do |status, output_msg|
  #     Logging.warn("mise trust failed in '#{dir.cyan}' (status: #{status.exitstatus})#{output_msg}")
  #   end
  def capture_output(*command)
    stdout, stderr, status = Open3.capture3(*command)
    check_status(stdout, stderr, status) { |st, msg| yield(st, msg) }
  end

  # Executes a command via system(), streaming stdout/stderr to terminal.
  #
  # Use this for interactive commands where users expect to see output in real-time
  # (e.g., git log, ls, etc.). Unlike capture_output, this does not buffer output.
  #
  # @param command [Array<String>] Command and arguments to execute
  # @yield Block receives no arguments; called on failure (can record warning/error)
  # @return [Boolean] true if command succeeded, false otherwise
  #
  # @example
  #   success = CommandUtils.run_interactive('git', '-C', dir, 'log', '--oneline', '-5') do
  #     Logging.record_warning("Command failed in '#{dir.cyan}' (status: #{$?.exitstatus})")
  #   end
  def run_interactive(*command)
    success = system(*command)
    yield unless success if block_given?
    success
  end

  # Executes a command and returns its stdout, stripped of whitespace.
  # Ignores stderr and exit status - use only for simple query commands where
  # failure is not expected (version checks, config queries, etc.).
  #
  # @param command [Array<String>] Command and arguments to execute
  # @return [String] Command's stdout with leading/trailing whitespace removed
  #
  # @example
  #   version = CommandUtils.query('sw_vers', '-productVersion')
  #   config_dir = CommandUtils.query('bat', '--config-dir')
  def query(*command)
    stdout, = Open3.capture3(*command)
    stdout.strip
  end

  # Checks pre-captured command output and yields formatted error details on failure.
  #
  # Use this when you've already captured stdout/stderr/status (e.g., from GitProcessor
  # wrapper methods) and want consistent error formatting without re-executing the command.
  #
  # @param stdout [String] Captured stdout from command
  # @param stderr [String] Captured stderr from command
  # @param status [Process::Status] Status object from command execution
  # @param noise_patterns [Array<String>, nil] Optional array of stderr patterns to filter out (e.g., ['Permission denied'])
  # @yield [status, output_message] Block receives status and formatted output on failure
  # @return [Boolean] true if command succeeded, false otherwise
  #
  # @example
  #   stdout, stderr, status = git.fetch_all
  #   success = CommandUtils.check_status(stdout, stderr, status) do |status, output_msg|
  #     Logging.record_warning("Fetch failed (status: #{status.exitstatus})#{output_msg}")
  #   end
  #
  # @example With stderr filtering (for commands like find that generate expected noise)
  #   noise_patterns = ['Permission denied', 'No such file or directory']
  #   stdout, stderr, status = Open3.capture3('find', path, '-name', '.git')
  #   success = CommandUtils.check_status(stdout, stderr, status, noise_patterns: noise_patterns) do |status, output_msg|
  #     Logging.record_warning("Find issues: #{output_msg}")
  #   end
  def check_status(stdout, stderr, status, noise_patterns: nil)
    unless status.success?
      if block_given?
        # Filter stderr if patterns provided
        filtered_stderr = !nil_or_empty?(noise_patterns) ? _filter_stderr_patterns(stderr, noise_patterns) : stderr

        # Build formatted output message (stdout/stderr sections)
        output_message = ''
        output_message += "\nSTDOUT: #{stdout.strip}" unless nil_or_empty?(stdout.strip)
        output_message += "\nSTDERR: #{filtered_stderr.strip}".red unless nil_or_empty?(filtered_stderr.strip)

        yield(status, output_message)
      end
    end

    status.success?
  end

  private

  # Filters out specified patterns from stderr output.
  #
  # @param stderr [String] Raw stderr output
  # @param patterns [Array<String>] Array of patterns to filter out
  # @return [String] Filtered stderr with matching patterns removed
  def _filter_stderr_patterns(stderr, patterns)
    return '' if nil_or_empty?(stderr)

    meaningful_lines = stderr.each_line.map(&:strip).reject do |line|
      # Cannot use array intersection (patterns & [line]) since patterns may be
      # substrings of the line (e.g., 'Permission denied' matches 'Permission denied (publickey)')
      nil_or_empty?(line) || patterns.any? { |pattern| line.include?(pattern) }
    end

    meaningful_lines.join("\n")
  end
end
