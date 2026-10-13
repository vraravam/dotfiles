#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Utility methods for executing external commands with consistent error handling.

require 'open3'
require_relative 'core'
require_relative 'enumerable_ext'
require_relative 'env_vars'
require_relative 'logging'
require_relative 'string_ext'

module CommandUtils
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Curl flags for bootstrap downloads (Homebrew's installer, before ~/.curlrc is linked). A
  # long retry window rides out a flaky network during a fresh install. --retry-all-errors is
  # deliberately absent: it makes the terminal app close. The shell bootstrap in
  # fresh-install-of-osx.sh must keep its own copy -- no Ruby exists yet when it runs.
  CURL_BOOTSTRAP_RETRY_OPTS = %w[--retry 5 --retry-delay 10 --retry-max-time 120 --max-time 150 --connect-timeout 30 --retry-connrefused].freeze

  # Curl flags for routine downloads in maintenance jobs: a short retry only.
  CURL_LIGHT_RETRY_OPTS = %w[--retry 3 --retry-delay 5].freeze

  # Headers that bypass GitHub's CDN and intermediate proxies.
  CURL_CACHE_BUST_OPTS = ['-H', 'Cache-Control: no-cache, no-store, must-revalidate', '-H', 'Pragma: no-cache', '-H', 'Expires: 0'].freeze

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Query methods (read-only state inspection)
  # ---------------------------------------------------------------------------

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
  # :reek:UtilityFunction -- Stateless wrapper for command output (intentional)
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
    # Guard against nil status (shouldn't happen with Open3.capture3 but defensive coding)
    return false if status.nil?

    if !status.success? && block_given?
      # Filter stderr if patterns provided
      filtered_stderr = !nil_or_empty?(noise_patterns) ? _filter_stderr_patterns(stderr, noise_patterns) : stderr

      # Build formatted output message (stdout/stderr sections)
      output_message = ''
      output_message += "\nSTDOUT: #{stdout.strip}" unless nil_or_empty?(stdout)
      output_message += "\nSTDERR: #{filtered_stderr.strip}".red unless nil_or_empty?(filtered_stderr)

      yield(status, output_message)
    end

    status.success?
  end

  # check_status that records the failure itself: on failure, a single
  # "<message> (status: N)<stdout/stderr>" entry is added to the Logging warnings or
  # errors collection (and echoed inline), so callers don't each re-spell the block.
  #
  # Choose +severity+ by what the failure means for the run: :error for something that
  # prevents the operation's goal, :warning for something the run can continue without.
  #
  # @param stdout [String, nil] Captured stdout
  # @param stderr [String, nil] Captured stderr
  # @param status [Process::Status] Status of the command
  # @param message [String] What failed, e.g. "Failed to add remote 'x' for repo 'y'"
  # @param severity [Symbol] :warning (default) or :error
  # @param noise_patterns [Array<String>, nil] stderr patterns to ignore (see check_status)
  # @return [Boolean] true if the command succeeded, false otherwise
  #
  # @example
  #   stdout, stderr, status = git.fetch_all
  #   CommandUtils.check_status_or_record(stdout, stderr, status, "Failed to fetch '#{dir}'")
  def check_status_or_record(stdout, stderr, status, message, severity: :warning, noise_patterns: nil)
    raise ArgumentError, "severity must be :warning or :error, got #{severity.inspect}" unless %i[warning error].include?(severity)

    check_status(stdout, stderr, status, noise_patterns: noise_patterns) do |st, output_msg|
      Logging.public_send("record_#{severity}", "#{message} (status: #{st.exitstatus})#{output_msg}")
    end
  end

  # ---------------------------------------------------------------------------
  # Mutation methods (modify state)
  # ---------------------------------------------------------------------------

  # Executes a command with optional output redirection (stdout/stderr default to /dev/null).
  #
  # Useful for operations where output needs to be suppressed or redirected
  # (e.g., background process cleanup, silent file operations, progress bars).
  #
  # @param command [Array<String>] Command and arguments to execute
  # @param out [IO, String] Where to redirect stdout (default: File::NULL)
  # @param err [IO, String] Where to redirect stderr (default: File::NULL)
  # @return [Boolean] true if command succeeded (exit 0), false otherwise
  #
  # @example Suppress all output (both stdout and stderr)
  #   CommandUtils.run_silent('killall', '-TERM', 'Dropbox')
  #   CommandUtils.run_silent('defaults', 'write', domain, key, value)
  #
  # @example Suppress stdout only (show stderr)
  #   CommandUtils.run_silent('brew', 'update', err: :err)
  #
  # @example Redirect stdout to file, suppress stderr
  #   CommandUtils.run_silent('crontab', '-l', out: '/tmp/crontab.txt')
  def run_silent(*command, out: File::NULL, err: File::NULL)
    system(*command, out: out, err: err)
  end

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
  def capture_output(*command, &block)
    stdout, stderr, status = Open3.capture3(*command)
    check_status(stdout, stderr, status, &block)
  rescue Errno::ENOENT => e
    # Command not found - yield with nil status and error message
    if block_given?
      output_message = "\nERROR: #{e.message}".red
      yield(nil, output_message)
    end
    false
  end

  # Executes a command via system(), streaming stdout/stderr to terminal.
  #
  # Use this for interactive commands where users expect to see output in real-time
  # (e.g., git log, ls, etc.). Unlike capture_output, this does not buffer output.
  #
  # @param command [Array<String, Hash>] Command and arguments to execute. As with Kernel#system,
  #   a leading Hash is an env for the child and a trailing options Hash (e.g. +chdir: dir+, which
  #   runs the child in that directory without changing this process's working directory) is
  #   forwarded as is.
  # @yield Block receives no arguments; called on failure (can record warning/error)
  # @return [Boolean] true if command succeeded, false otherwise
  #
  # @example
  #   success = CommandUtils.run_interactive('git', '-C', dir, 'log', '--oneline', '-5') do
  #     Logging.record_warning("Command failed in '#{dir.cyan}' (status: #{$?.exitstatus})")
  #   end
  def run_interactive(*command)
    success = system(*command)
    yield if block_given? && !success
    success
  end

  # Curl arguments (besides -fsSL and the URL) for a download.
  #
  # With +bootstrap+: the long retry flags when CURL_RETRY_OPTS is set or ~/.curlrc (which
  # carries equivalent defaults) is not linked yet, and the cache-busting headers when
  # CACHE_BUST_HEADERS is set. Without it: the short retry flags.
  #
  # @param bootstrap [Boolean] Whether this is a fresh-install download
  # @return [Array<String>]
  def curl_opts(bootstrap: false)
    return CURL_LIGHT_RETRY_OPTS unless bootstrap

    opts = []
    opts.concat(CURL_CACHE_BUST_OPTS) if EnvVars.cache_bust_headers?
    opts.concat(CURL_BOOTSTRAP_RETRY_OPTS) if EnvVars.curl_retry_opts? || !EnvVars::HOME.join('.curlrc').file?
    opts
  end

  # Downloads +url+ to +dest+ with curl (-fsSL: fail on HTTP errors, follow redirects).
  #
  # @param url [String]
  # @param dest [String, Pathname] File to write
  # @param bootstrap [Boolean] Use the bootstrap flags (see curl_opts)
  # @param interactive [Boolean] Stream curl's own stderr to the terminal; otherwise silent
  # @return [Boolean] true if curl succeeded
  #
  # @example
  #   CommandUtils.curl_download(url, syntax_dir.join('file.sublime-syntax'))
  def curl_download(url, dest, bootstrap: false, interactive: false)
    command = ['curl', *curl_opts(bootstrap: bootstrap), '-fsSL', url.to_s, '-o', dest.to_s]
    interactive ? run_interactive(*command) : run_silent(*command)
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  private

  # Filters out specified patterns from stderr output.
  #
  # @param stderr [String] Raw stderr output
  # @param patterns [Array<String>] Array of patterns to filter out
  # @return [String] Filtered stderr with matching patterns removed
  def _filter_stderr_patterns(stderr, patterns)
    return '' if nil_or_empty?(stderr)

    # filter_map polyfill in enumerable_ext.rb provides optimized single-pass implementation for Ruby 2.6
    # Cannot use array intersection (patterns & [line]) since patterns may be
    # substrings of the line (e.g., 'Permission denied' matches 'Permission denied (publickey)')
    meaningful_lines = stderr.each_line.filter_map do |line|
      next if nil_or_empty?(line)

      stripped = line.strip
      stripped unless patterns.any? { |pattern| stripped.include?(pattern) }
    end

    meaningful_lines.join("\n")
  end
end
