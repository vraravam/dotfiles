#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

require_relative 'command_utils'
require_relative 'core'
require_relative 'enumerable_ext'
require_relative 'path_utils'

# Homebrew steps shared by the interactive 'bupc' command (scripts/brew-update-cleanup.rb),
# the hourly cron job (scripts/software-updates-cron.rb) and the machine setup (BrewBundle),
# so they can never drift apart on how a step is invoked. What only the machine setup needs (the
# base section of the Brewfile, the retries, the background install) lives in BrewBundle.
#
# Every method is a pure wrapper around a plain 'brew' subprocess: it returns its result and never
# logs or records warnings itself, because the callers deliberately treat the same failure differently (cron
# records a warning per updated component; 'bupc' keeps going and only summarizes at the end).
# No method assumes a TTY or a login shell, so they behave identically under cron.
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

  # Whether everything in the Brewfile is already installed ('brew bundle check' exits 0). The
  # check's output stays visible so a missing package is easy to diagnose.
  #
  # @param brew_bin [String] The brew executable. Defaults to 'brew' from PATH; the bootstrap
  #   passes the absolute path because Homebrew may not be on PATH yet.
  # @return [Boolean]
  def bundle_check(brew_bin: 'brew')
    CommandUtils.run_interactive(brew_bin, 'bundle', 'check', '-v')
  end

  # One attempt at 'brew bundle install', from +content+ (Brewfile text fed on stdin, output
  # streamed live) when given, otherwise from the Brewfile on disk. There is deliberately no time
  # limit: a legitimate cask or formula build can run for tens of minutes and the quiet ('-q')
  # output gives no progress to judge a stall by, so killing it would do more harm than waiting.
  #
  # @param brew_bin [String] The brew executable.
  # @param content [String, nil] Brewfile text to install instead of the file on disk.
  # @return [Boolean] true if the install succeeded.
  def bundle_install(brew_bin: 'brew', content: nil)
    if content
      Core.stream_command([brew_bin, 'bundle', 'install', '-q', '--file=-'], stdin_data: content).zero?
    else
      CommandUtils.run_interactive(brew_bin, 'bundle', 'install', '-q')
    end
  end

  # Brings installed packages in line with the Brewfile: when 'brew bundle check' already passes
  # the install is skipped, to avoid re-checking every formula on every run.
  #
  # @return [Boolean] true if everything is (now) installed.
  def sync_bundle
    bundle_check || bundle_install
  end

  # Removes everything not declared in the Brewfile, prunes the download cache and
  # uninstalls orphaned dependencies. Each sub-step is best-effort (a failure in one
  # does not skip the others), so the return value is not meaningful and is omitted.
  #
  # @return [void]
  def cleanup
    CommandUtils.run_interactive('brew', 'bundle', 'cleanup', '-f')
    CommandUtils.run_interactive('brew', 'cleanup', '--prune=all')
    CommandUtils.run_interactive('brew', 'autoremove')
  end

  # Upgrades every outdated formula and (non-greedy) cask.
  #
  # @return [Boolean] true if the upgrade succeeded.
  def upgrade
    CommandUtils.run_interactive('brew', 'upgrade', '-y')
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
