#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

module Logging
  # All mutable run state of the Logging module, in ONE object shared by every caller.
  #
  # Logging is mixed in two ways: `Logging.info(...)` (module methods via `extend self`)
  # and `include Logging` (instance methods on the including object, e.g. the top-level
  # main object of a CLI script). Instance variables would give each of those receivers its
  # own private warning/error lists, so a `record_warning` made through one was invisible
  # to a `print_script_summary` made through the other. Keeping the state here (see
  # Logging#state) makes bare and `Logging.`-qualified calls interchangeable.
  class State
    # @return [String, nil] script name override (nil falls back to $PROGRAM_NAME)
    attr_accessor :script_name
    # @return [String, nil] current logical section, used to attribute recorded issues
    attr_accessor :current_section
    # @return [Boolean] true once the section was set explicitly (stops auto-updates)
    attr_accessor :current_section_manual
    # @return [Integer, nil] Unix epoch recorded by print_script_start
    attr_accessor :script_start_time
    # @return [Integer, nil] cached terminal width
    attr_accessor :terminal_width
    # @return [Integer, nil] cached minimum log level priority
    attr_accessor :min_log_level
    # @return [Array<String>] collected warnings
    attr_reader :warnings
    # @return [Array<String>] collected errors
    attr_reader :errors
    # @return [Array<Integer>] stack of step start times (Unix epoch seconds)
    attr_reader :step_start_times
    # @return [Hash{Integer => String}] memoized indentation per script depth
    attr_reader :indent_cache

    def initialize
      reset!
    end

    # Restores the pristine state. Used by specs; scripts never need it.
    #
    # @return [void]
    def reset!
      @script_name = nil
      @current_section = nil
      @current_section_manual = false
      @script_start_time = nil
      @terminal_width = nil
      @min_log_level = nil
      @warnings = []
      @errors = []
      @step_start_times = []
      @indent_cache = {}
    end
  end

  # The process-wide state instance returned by Logging#state.
  STATE = State.new
end
