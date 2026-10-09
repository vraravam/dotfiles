#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'command_utils'

# Homebrew maintenance steps shared by the interactive 'bupc' command
# (scripts/brew-update-cleanup.rb) and the hourly cron job
# (scripts/software-updates-cron.rb), so the two can never drift apart on how a
# step is invoked.
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

  # Brings installed packages in line with the Brewfile. 'brew bundle check' exits 0
  # when everything is already installed, in which case the full install is skipped to
  # avoid re-checking every formula on every run. The check's output stays visible so a
  # missing package is easy to diagnose.
  #
  # @return [Boolean] true if everything is (now) installed.
  def sync_bundle
    CommandUtils.run_interactive('brew', 'bundle', 'check', '-v') ||
      CommandUtils.run_interactive('brew', 'bundle', 'install', '-q')
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
end
