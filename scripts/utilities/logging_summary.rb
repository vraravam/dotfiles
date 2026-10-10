#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'core'
require_relative 'env_vars'

module Logging
  # Run reporting: script/step timing, deferred warning/error collection and the
  # end-of-run summaries. Mixed into Logging; relies on Logging#state, #emit, #info,
  # #warn, #section_header, #script_name and #outermost_script?.
  module Summary
    include Core

    # Prints the script start timestamp, prefixed with the script name. Mirrors:
    #   echo "$(cyan "${_SCRIPT_NAME:-}") $(purple '==>') $(yellow 'Script started at:') $(light_blue "...")"
    # Returns the start time as a Unix epoch integer so the caller can pass it to
    # print_script_duration. This deviates from the shell version (which cannot
    # return a value) but eliminates the two-call pattern and ensures the logged
    # timestamp and the in-memory start time are identical.
    # Only prints when this is the outermost script -- see outermost_script?.
    #
    # @return [Integer] Unix epoch of the logged start time.
    def print_script_start
      start = state.script_start_time = Time.now.to_i
      return start unless outermost_script?
      # Suppressed when running inside a direnv subshell (same as info/success).
      return start if EnvVars.suppress_log?

      emit("#{script_name.cyan} #{'==>'.purple} #{'Script started at:'.yellow} #{Core.current_timestamp.light_blue}", level: 0)
      start
    end

    # Prints the script finish timestamp and total duration.
    #
    # @param start_time [Integer] Unix epoch returned by an earlier +Time.now.to_i+.
    # @return [void]
    def print_script_duration(start_time)
      return unless outermost_script?
      # Suppressed when running inside a direnv subshell (same as info/success).
      return if EnvVars.suppress_log?

      human = format_duration(Core.duration_since(start_time))
      emit("#{script_name.cyan} #{'==>'.purple} #{'Script finished at:'.yellow} #{Core.current_timestamp.light_blue} " \
           "(#{'Total duration:'.yellow} #{human.light_blue} #{'seconds'.yellow}).", level: 0)
    end

    # ---------------------------------------------------------------------------
    # Deferred error/warning collection
    # These mirror _record_warning, _record_error, and print_script_summary from
    # .shellrc. Each entry is prefixed with [script_name][current_section] for
    # traceability. print_script_summary prints collected issues grouped by type.
    # No macOS notification is sent -- osascript is not appropriate for library code.
    # ---------------------------------------------------------------------------

    # Sets the current logical section name, used as context in record_warning /
    # record_error entries. Mirrors the _current_section local in shell scripts.
    # Automatically strips ANSI codes to ensure clean error messages.
    #
    # @param name [String] The section name to set as current context
    def current_section=(name)
      state.current_section = _strip_ansi(name.to_s)
      state.current_section_manual = true # Mark as manually set
    end

    # Wraps a block of code with step lifecycle management (current_section, step_start, step_end).
    # Ensures step_end is called even if the block raises an exception.
    #
    # @param section_name [String] Name for current_section tracking
    # @param header [String, nil] Optional section header to print (uses section_header if provided)
    # @yield Block of code to execute within the step lifecycle
    # @return [void]
    #
    # @example
    #   Logging.with_step('Install Homebrew', "Installing Homebrew into '#{path}'") do
    #     # ... install logic ...
    #   end
    def with_step(section_name, header = nil)
      self.current_section = section_name
      step_start
      section_header(header) if header

      yield
    ensure
      step_end
    end

    # Appends a non-critical issue to the warnings collection and emits an inline
    # warn so the issue is visible in the log at the point it occurs.
    #
    # @param message [String] The warning message to record
    def record_warning(message)
      _record_message(step_warnings, message)
    end

    # Appends a significant non-fatal failure to the errors collection and emits
    # an inline warn so the failure is visible in the log at the point it occurs.
    #
    # @param message [String] The error message to record
    def record_error(message)
      _record_message(step_errors, message)
    end

    # Prints a grouped summary of all collected warnings and errors, prefixing
    # each section header with the script name, then prints the total duration.
    # Mirrors print_script_summary in .shellrc. No macOS notification -- callers
    # that need one must handle it themselves.
    #
    # Accepts an optional +start_time+ (Unix epoch returned by +print_script_start+).
    # When provided, calls +print_script_duration+ so the caller never needs to
    # invoke it separately. This deviates from the shell version, which cannot
    # call print_script_duration from within print_script_summary because shell
    # functions cannot propagate a return value for the start time.
    # When omitted (e.g. early-exit paths inside methods that cannot access the
    # top-level start-time local), the duration line is skipped.
    #
    # Accepts an optional +message+ to print before the warnings/errors sections.
    # Mirrors the second parameter of the shell version.
    #
    # @param start_time [Integer, nil] Unix epoch of script start, or nil to skip duration.
    # @param message [String, nil] Optional success message to print before summary.
    def print_script_summary(start_time = nil, message = nil)
      # outermost_script? encapsulates the _DOTFILES_SCRIPT_DEPTH check -- see its
      # definition for the full rationale.
      return unless outermost_script?

      info(message) unless nil_or_empty?(message)
      _print_collected_messages(step_warnings, 'warning(s)', :yellow) unless nil_or_empty?(step_warnings)
      _print_collected_messages(step_errors, 'error(s) -- manual attention needed', :red) unless nil_or_empty?(step_errors)
      print_script_duration(start_time) if start_time
    end

    # Returns the live collection of collected warnings. Public so callers (e.g.
    # software-updates-cron.rb notification block) can read them without
    # reaching into private state via instance_variable_get.
    #
    # @return [Array<String>] Collected warning messages
    def step_warnings
      state.warnings
    end

    # Returns the live collection of collected errors. Public for the same reason
    # as step_warnings above.
    #
    # @return [Array<String>] Collected error messages
    def step_errors
      state.errors
    end

    # Returns true if any warnings have been recorded during script execution.
    # Prefer this over directly checking step_warnings.any? for cleaner code.
    #
    # @return [Boolean] true if warnings exist, false otherwise
    #
    # @example
    #   @has_failures = true if Logging.warnings? || Logging.errors?
    def warnings?
      step_warnings.any?
    end

    # Returns true if any errors have been recorded during script execution.
    # Prefer this over directly checking step_errors.any? for cleaner code.
    #
    # @return [Boolean] true if errors exist, false otherwise
    #
    # @example
    #   exit(1) if Logging.errors?
    def errors?
      step_errors.any?
    end

    # One entry per non-empty issue collection -- "N error(s): a; b" then "N warning(s): c" -- for
    # building a single grouped notification (software-updates-cron.rb, fresh-install-of-osx.rb).
    # Empty when nothing was recorded.
    #
    # @return [Array<String>] Zero, one or two entries (errors first)
    def issue_summary_parts
      parts = []
      parts << "#{step_errors.length} error(s): #{step_errors.join('; ')}" if errors?
      parts << "#{step_warnings.length} warning(s): #{step_warnings.join('; ')}" if warnings?
      parts
    end

    # Formats +seconds+ as "Hh:MMm:SSs". Public so callers that build their own
    # notification or summary strings can format a duration without reaching into
    # private state via send().
    #
    # @param seconds [Integer] Duration in seconds to format
    # @return [String] Formatted duration string (e.g. "00h:05m:30s")
    # :reek:FeatureEnvy -- Stateless formatter operating on argument
    def format_duration(seconds)
      # rubocop:disable Style/FormatStringToken
      format('%02dh:%02dm:%02ds', seconds / 3600, (seconds % 3600) / 60, seconds % 60)
      # rubocop:enable Style/FormatStringToken
    end

    # Prints a summary of processing results from a hash returned by
    # CollectionProcessor.process_items or similar iteration helpers.
    #
    # @param results [Hash] Results hash with keys:
    #   - :total [Integer] Total items processed (excludes skipped)
    #   - :successful [Array<String>] Successful item names
    #   - :failed [Array<String>] Failed item names
    #   - :skipped [Integer] Count of skipped items (optional)
    # @param item_label [String] What to call each item (default: 'repositories')
    #
    # @example
    #   results = CollectionProcessor.process_items(...) { |item| ... }
    #   print_results_summary(results)
    #   print_results_summary(results, item_label: 'files')
    def print_results_summary(results, item_label: 'repositories')
      # Only print when this is the outermost script -- suppresses nested summaries
      # when called from a wrapper script/function that prints its own final summary.
      return unless outermost_script?

      total = results[:total]
      successful = results[:successful]
      failed = results[:failed]

      puts ''
      info('Summary'.yellow)
      emit("Total #{item_label}: #{total}", level: 1)
      emit("Successful:         #{successful.length.to_s.green}", level: 1)

      unless nil_or_empty?(failed)
        singular = item_label.sub(/ies$/, 'y').sub(/s$/, '')
        plural = item_label
        count_label = failed.length == 1 ? singular : plural

        emit("Failed:             #{failed.length.to_s.red}", level: 1)
        emit("Failed #{count_label}:".red, level: 0)
        puts join_array(failed, :red)
      end

      info "Skipped: #{results[:skipped].to_s.purple}" if results[:skipped]&.positive?
    end

    private

    # Pushes the current epoch seconds onto the step timing stack. Called by
    # with_step at the start of a step. Mirrors step_start in .shellrc.
    def step_start
      state.step_start_times.push(Time.now.to_i)
    end

    # Pops the most recent step start time from the stack, computes elapsed time,
    # and logs it. Called by with_step's ensure block. Mirrors step_end in .shellrc.
    def step_end
      now = Time.now.to_i

      # No step timing available (unbalanced step_end) - skip timing output
      return if nil_or_empty?(state.step_start_times)

      step_start_time = state.step_start_times.pop
      delta_step = now - step_start_time

      # Compute total elapsed from script start if available
      script_start_time = state.script_start_time || now
      delta_total = now - script_start_time

      # Format: "(Step: XXs  Total: YYs)"
      emit("(#{'Step:'.yellow} #{delta_step.to_s.light_blue}s  #{'Total:'.yellow} #{delta_total.to_s.light_blue}s)", level: 0)
    end

    # Prints collected warnings or errors with proper indentation.
    # Temporarily decrements depth so both header and messages print one level less indented.
    #
    # @param messages [Array<String>] Collection of warning/error messages
    # @param label [String] Label for the message type (e.g., 'warning(s)', 'error(s)')
    # @param color [Symbol] Color method to apply to count (e.g., :yellow, :red)
    # @return [void]
    def _print_collected_messages(messages, label, color)
      decrement_script_depth
      section_header("#{script_name.cyan} #{"#{messages.length} #{label}".send(color)}")
      messages.each { |msg| warn(msg) }
      increment_script_depth
    end

    # Appends a message to a collection with script/section prefix and emits inline warning.
    #
    # @param collection [Array<String>] Target collection (step_warnings or step_errors)
    # @param message [String] The message to record
    # @return [void]
    def _record_message(collection, message)
      collection << "[#{script_name || 'unknown'}][#{state.current_section || 'unknown'}] #{message}"
      warn(message)
    end
  end
end
