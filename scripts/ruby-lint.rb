#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8

# file location: ${DOTFILES_DIR}/scripts/ruby-lint.rb
#
# Runs comprehensive static analysis on Ruby files using multiple tools:
# - RuboCop (style and lint checks)
# - Reek (code smell detection)
# - Flay (duplication detection)
# - Flog (complexity analysis)
#
# This is a MANUAL deep-analysis tool. For automatic commit-time validation,
# see .config/git/hooks/pre-commit which runs fast checks on staged files only.
#
# Use this script for:
# - Periodic codebase health checks
# - Detecting project-wide code smells and duplication
# - Complexity analysis across entire directories
#
# Usage:
#   Standalone: ruby-lint.rb [<dir>|<file>]
#   Module:     RubyLint.run(target: 'scripts/')

require 'pathname'
require_relative 'utilities/logging'
require_relative 'utilities/env_vars'
require_relative 'utilities/path_utils'
require_relative 'utilities/command_utils'

# Runs static analysis on Ruby files
module RubyLint
  extend self

  # Run all static analysis tools on target
  #
  # @param target [String, Pathname] Directory or file to analyze
  # @return [Boolean] true if all checks pass, false if any fail
  def run(target: nil)
    target ||= EnvVars::DOTFILES_DIR.join('scripts')
    target_path = Pathname.new(target).expand_path

    unless target_path.exist?
      Logging.error "Target does not exist: '#{target_path.to_s.cyan}'"
      return false
    end

    Logging.info "Running static analysis on '#{target_path.to_s.cyan}'"

    tools = [
      { name: 'RuboCop', command: 'rubocop', args: [target_path.to_s] },
      { name: 'Reek', command: 'reek', args: [target_path.to_s] },
      { name: 'Flay', command: 'flay', args: [target_path.to_s] },
      { name: 'Flog', command: 'flog', args: [target_path.to_s] }
    ]

    results = {}
    tools.each do |tool|
      next unless PathUtils.command_exists?(tool[:command])

      Logging.info "Running #{tool[:name].yellow}..."
      results[tool[:name]] = system(tool[:command], *tool[:args])
      puts '' # Blank line between tools
    end

    # Check for missing tools
    missing = tools.reject { |t| PathUtils.command_exists?(t[:command]) }
    if missing.any?
      missing_list = missing.map { |t| "'#{t[:command].cyan}'" }.join(', ')
      Logging.warn "Missing tools (install with #{'gem install <name>'.cyan}): #{missing_list}"
    end

    # Report summary
    passed = results.values.all? { |v| v }
    if passed
      Logging.success 'All static analysis checks passed'
    else
      failed_list = results.select { |_k, v| !v }.keys.map { |name| name.yellow }.join(', ')
      Logging.warn "Failed checks: #{failed_list}"
    end

    passed
  end
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = {}
  parser = CliParser.parse('[<target>]') do |opts|
    opts.separator 'Runs comprehensive static analysis on Ruby files.'
    opts.separator ''
    opts.separator 'Arguments:'.purple
    opts.separator "  #{'<target>'.yellow}  Directory or file to analyze (default: scripts/)"
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} scripts/"
    opts.separator "  eg: #{File.basename(__FILE__).cyan} scripts/my-script.rb"
  end

  target = ARGV.first

  # Note: Using Logging.run_script instead of manual increment_script_depth pattern.
  # This is a standalone utility (not called from other scripts), so the simplified
  # run_script wrapper is appropriate. It handles depth tracking, script name, and
  # ensures proper cleanup automatically.
  Logging.run_script(File.basename(__FILE__, '.rb')) do
    success = RubyLint.run(target: target)
    exit(success ? 0 : 1)
  end
end
