#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'logging'
require_relative 'string_ext'

# Numbers the steps of a long-running script as '[Step N of TOTAL]' so progress is visible in
# the log. Shared by the scripts that report step progress (software-updates-cron.rb,
# fresh-install-of-osx.rb) so the format and color cannot drift apart.
#
# The total is declared up front and has to be kept in sync with the number of numbered steps;
# steps that print their own headers can be left unnumbered.
class StepCounter
  # @param total [Integer] Number of numbered steps the script runs.
  def initialize(total)
    @total = total
    @current = 0
  end

  # Advances the counter and returns the progress prefix, e.g. "[Step 3 of 20] " (the label is
  # purple). Use it where the step's own title/header is composed by the caller.
  #
  # @return [String] The prefix, with a trailing space.
  def next_prefix
    @current += 1
    "[#{"Step #{@current} of #{@total}".purple}] "
  end

  # Runs +block+ as the next numbered step: the progress prefix goes in front of +title+ (which
  # is also the current-section name used to attribute warnings and errors in the summary).
  #
  # @param title [String] Step title.
  # @param message [String, nil] Optional section header to print.
  # @yield The step's work.
  # @return [void]
  def step(title, message = nil, &block)
    Logging.with_step("#{next_prefix}#{title}", message, &block)
  end
end
