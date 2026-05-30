# frozen_string_literal: true

require_relative 'string'

# Logging helpers that replicate the shell functions defined in .shellrc
# (success/info/warn/debug/error, section_header, print_script_start,
# print_script_duration, and the step_start/step_end stack-based timing helpers).
#
# Color rendering is handled by the String extensions in string.rb and is
# automatically suppressed when stdout is not a TTY.
#
# Usage:
#   require 'logging'
#   include Logging
#
# Or call methods directly on the module:
#   Logging.info('hello')
module Logging
  # Make the module usable both as `include Logging` and as `Logging.info(…)`.
  extend self

  # ---------------------------------------------------------------------------
  # General-purpose utility helpers
  # ---------------------------------------------------------------------------

  # Checks if a value is nil or empty.
  #
  # @param val [nil, #empty?] The value to check. Non-nil values must respond to +#empty?+.
  # @return [true, false]
  # @raise [NoMethodError] if +val+ is not nil and does not respond to +#empty?+.
  def nil_or_empty?(val)
    val.nil? || val.empty?
  end

  # ---------------------------------------------------------------------------
  # Semantic log-level helpers
  # These mirror success/info/warn/debug/error from .shellrc.
  #
  # These methods do NOT apply tilde substitution — color methods (.yellow,
  # .cyan, etc.) do so automatically on their arguments. Logging methods are
  # pure formatters: prefix + message. Bare puts/print call sites that display
  # paths without a color method must call replace_home_path_with_tilde explicitly.
  #
  # The shell's `error` calls `osascript` for a macOS notification; that
  # behaviour is omitted here since it is inappropriate for library code.
  # ---------------------------------------------------------------------------

  def success(message)
    puts "✅ #{'**SUCCESS**'.green} #{message}"
  end

  def info(message)
    puts "ℹ️  #{'**INFO**'.cyan} #{message}"
  end

  def warn(message)
    puts "⚠️  #{'**WARN**'.light_red} #{message}"
  end

  def debug(message)
    puts "⚙️  #{'**DEBUG**'.light_purple} #{message}"
  end

  # Prints the error message and raises a +RuntimeError+ with that message,
  # terminating the current execution path unless rescued by the caller.
  # @raise [RuntimeError]
  def error(message)
    puts "❌ #{'**ERROR**'.red} #{message} 🤓"
    raise message
  end

  # ---------------------------------------------------------------------------
  # Section / script timing helpers
  # These mirror section_header, print_script_start, print_script_duration,
  # step_start, step_end, and step_timing_init from .shellrc.
  # ---------------------------------------------------------------------------

  # Prints +char+ repeated +length+ times.
  # Defaults to '=' and terminal-width/4 columns when +length+ is not given.
  #
  # @param char [String] The character to repeat (default: '=').
  # @param length [Integer, nil] Number of repetitions; defaults to +terminal_width / 4+ when nil.
  # @return [String] The repeated character string.
  def print_chars_for_length(char: '=', length: nil)
    char * (length || terminal_width / 4)
  end

  # Prints a centred section header flanked by '=' padding, matching:
  #   echo "$(light_blue $(print_chars_for_length '=' …)) ⏳ ${header} $(light_blue …)"
  def section_header(header)
    header_str = header.replace_home_path_with_tilde
    padding_length = [((terminal_width - header_str.length) / 2) - 10, 1].max
    pad = print_chars_for_length(char: '=', length: padding_length)
    puts "#{pad.light_blue} ⏳ #{header_str} #{pad.light_blue}"
  end

  # Prints the script start timestamp, matching:
  #   echo "$(purple '==>') $(yellow 'Script started at:') $(light_blue "$(date …)")"
  def print_script_start
    puts "#{'==>'.purple} #{'Script started at:'.yellow} #{Time.now.strftime('%Y-%m-%d %H:%M:%S').light_blue}"
  end

  # Prints the script finish timestamp and total duration.
  #
  # @param start_time [Integer] Unix epoch returned by an earlier +Time.now.to_i+.
  # @return [void]
  def print_script_duration(start_time)
    now = Time.now
    human = format_duration(now.to_i - start_time)
    puts "#{'==>'.purple} #{'Script finished at:'.yellow} #{now.strftime('%Y-%m-%d %H:%M:%S').light_blue} " \
         "(#{'Total duration:'.yellow} #{human.light_blue} #{'seconds'.yellow})."
  end

  # ---------------------------------------------------------------------------
  # Stack-based step timing (mirrors step_timing_init / step_start / step_end)
  # ---------------------------------------------------------------------------

  # Pushes the current epoch time onto the script-level clock stack only if it is
  # empty, recording the overall script start time.
  # Safe to call multiple times; subsequent calls are no-ops once the stack is populated.
  def step_timing_init
    script_start_times << Time.now.to_i if nil_or_empty?(script_start_times)
  end

  # Records the start of a step (push onto the step stack).
  def step_start
    step_timing_init
    step_start_times << Time.now.to_i
  end

  # Pops the most recent step start time and prints the step duration and total elapsed,
  # mirroring the shell output: "    ⏱ step: 0h:01m:23s | elapsed: 0h:05m:00s"
  #
  # If called without a preceding +step_start+, falls back to the script start time.
  # If neither stack is initialised, falls back to the current time.
  # Both fallback paths emit a warning via +warn+.
  #
  # @return [void]
  def step_end
    now = Time.now.to_i

    step_start_time = if nil_or_empty?(step_start_times)
        if nil_or_empty?(script_start_times)
          warn('step_end called without any timing stack initialised; using current time as fallback')
          now
        else
          warn('step_end called without matching step_start; using current epoch start time as fallback')
          script_start_times.last
        end
      else
        step_start_times.pop
      end

    step_human = format_duration(now - step_start_time)
    total_human = format_duration(now - (script_start_times.last || now))

    puts "#{'    ⏱'.purple} #{'step:'.yellow} #{step_human.light_blue} #{'| elapsed:'.yellow} #{total_human.light_blue}"
  end

  # ---------------------------------------------------------------------------
  # Private implementation details
  # ---------------------------------------------------------------------------

  private

  # Per-includer stacks stored as instance variables so that each object (or
  # the top-level main object when `include`d at script level) has its own
  # independent stacks, matching the zsh array semantics.
  def script_start_times
    @script_start_times ||= []
  end

  def step_start_times
    @step_start_times ||= []
  end

  # Returns the current terminal column width, falling back to 80.
  # $stdout.winsize[1] reads the terminal dimensions via ioctl — no `tput cols` subprocess fork.
  # rescue 0 handles non-tty contexts (e.g. pipes, cron) gracefully.
  def terminal_width
    return @terminal_width if @terminal_width
    cols = $stdout.winsize[1] rescue 0
    @terminal_width = cols.nonzero? || 80
  end

  # Formats +seconds+ as "Hh:MMm:SSs".
  def format_duration(seconds)
    format('%02dh:%02dm:%02ds', seconds / 3600, (seconds % 3600) / 60, seconds % 60)
  end
end
