#!/usr/bin/env ruby
# frozen_string_literal: true

# Command-line option parsing utilities with standard error handling
#
# Usage:
#   require 'cli_parser'

require 'optparse'

require_relative 'logging'

# Module for parsing command-line options with standard error handling
module CliParser
  # OptionParser subclass that adds abort_with_usage as an instance method.
  class Parser < OptionParser
    include Logging

    # Override OptionParser#warn to use Logging#warn instead of the default
    # behaviour which prepends the program name (e.g. "script: message").
    def warn(message)
      Logging.warn(message)
    end

    # Print a formatted error message followed by the usage banner, then exit 1.
    # Intended for post-parse validation failures.
    #
    # @param message [String] The error message to display
    def abort_with_usage(message)
      warn(message)
      puts self
      exit 1
    end
  end

  # Parse command-line options with automatic help handling and error reporting
  #
  # @param banner [String] Usage banner text (e.g., "<folder> <output-file>")
  # @yield [Parser] Block that defines the options
  # @return [Parser] The configured parser
  #
  # @example
  #   CliParser.parse('<folder>') do |opts|
  #     opts.separator 'Arguments:'
  #     opts.separator '  <folder>  Target folder'
  #     opts.on('-v', '--verbose', 'Verbose output') { |v| options[:verbose] = v }
  #   end
  def self.parse(banner)
    parser = Parser.new do |opts|
      opts.banner = "#{'Usage'.red}: #{File.basename($PROGRAM_NAME).cyan} #{banner.yellow}"
      opts.separator ''
      if block_given?
        yield(opts)
        opts.separator ''
      end
      opts.on('-h', '--help', 'Show this help message') do
        puts opts
        exit
      end
    end

    begin
      parser.parse!
    rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
      parser.abort_with_usage(e.message)
    end

    parser
  end
end
