#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'command_utils'
require_relative 'enumerable_ext'
require_relative 'path_utils'

# Homebrew housekeeping steps shared by the interactive 'bupc' command
# (scripts/brew-update-cleanup.rb) and the hourly cron job
# (scripts/software-updates-cron.rb), so the two can never drift apart on how a
# step is invoked. (CLI packages and casks themselves are managed by nix -- see Nix.)
#
# Every method is a pure command wrapper: it returns true/false and never logs or
# records warnings itself, because the two callers deliberately treat the same
# failure differently (cron records a warning per updated component; 'bupc' keeps
# going and only summarizes at the end). No method assumes a TTY or a login shell --
# each one is a plain 'brew' subprocess, so they behave identically under cron.
module Brew
  extend self

  # Refreshes Homebrew's own formula/cask definitions.
  #
  # @param quiet [Boolean] When true, suppresses stdout (progress output is noise in cron
  #   logs) but still surfaces stderr; when false, streams everything.
  # @return [Boolean] true if 'brew update' succeeded.
  def update(quiet: false)
    return CommandUtils.run_silent('brew', 'update', err: :err) if quiet

    CommandUtils.run_interactive('brew', 'update')
  end

  # Prunes the download cache and uninstalls orphaned dependencies -- the parts of Homebrew
  # housekeeping that nix-darwin's homebrew module does not cover (see
  # nix/darwin-configuration.nix's homebrew.onActivation.cleanup comment). Each sub-step is
  # best-effort (a failure in one does not skip the other), so the return value is not
  # meaningful and is omitted.
  #
  # @return [void]
  def cleanup
    CommandUtils.run_interactive('brew', 'cleanup', '--prune=all')
    CommandUtils.run_interactive('brew', 'autoremove')
  end

  # Lists casks (including those that update themselves, via --greedy) and formulae that
  # still need an update. Lines that are Homebrew's own progress/noise rather than package
  # names are dropped.
  #
  # @return [Array<String>] One entry per outdated package, e.g. "firefox (130.0) != 131.0"
  #   (empty when everything is current or 'brew' is not installed)
  def outdated_greedy
    return [] unless PathUtils.command_exists?('brew')

    CommandUtils.query('brew', 'outdated', '--greedy').lines.filter_map do |line|
      stripped = line.strip
      stripped unless stripped.empty? || stripped.match?(/homebrew|Downloading/i)
    end
  end
end
