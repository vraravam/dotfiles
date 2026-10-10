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
# so they can never drift apart on how a step is invoked.
#
# Every method is a pure wrapper (base_brewfile_content, which only reads the Brewfile, is the one
# exception to "a plain 'brew' subprocess"): it returns its result and never logs or records
# warnings itself, because the callers deliberately treat the same failure differently (cron
# records a warning per updated component; 'bupc' keeps going and only summarizes at the end).
# No method assumes a TTY or a login shell, so they behave identically under cron.
module Brew
  extend self

  # The comment line in the Brewfile that ends the base section: on a vanilla macOS only what
  # is above it is installed first, the rest follows in a background job (see BrewBundle).
  FIRST_INSTALL_SENTINEL = '# FIRST_INSTALL:'

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
  # @param brew_bin [String] The brew executable. Defaults to 'brew' from PATH; the bootstrap
  #   passes the absolute path because Homebrew may not be on PATH yet.
  # @param brewfile_content [String, nil] When given, installs from this Brewfile text (fed on
  #   stdin, output streamed live) instead of the Brewfile on disk -- used to install only the
  #   base section on a first install.
  # @return [Boolean] true if everything is (now) installed.
  def sync_bundle(brew_bin: 'brew', brewfile_content: nil)
    return true if CommandUtils.run_interactive(brew_bin, 'bundle', 'check', '-v')

    if brewfile_content
      Core.stream_command([brew_bin, 'bundle', 'install', '-q', '--file=-'], stdin_data: brewfile_content).zero?
    else
      CommandUtils.run_interactive(brew_bin, 'bundle', 'install', '-q')
    end
  end

  # The part of the Brewfile above the FIRST_INSTALL_SENTINEL comment line: the bare essentials
  # that a vanilla macOS needs before the rest of the setup can proceed. The sentinel is a
  # *comment*, so the match must not skip comment lines.
  #
  # @param brewfile [Pathname, String] Path to the Brewfile.
  # @return [String, nil] The base section, or nil when the Brewfile has no sentinel line.
  def base_brewfile_content(brewfile)
    base = []
    Core.each_line_utf8(brewfile) do |line|
      return base.join if line.start_with?(FIRST_INSTALL_SENTINEL)

      base << line
    end
    nil
  end

  # Installs the whole Brewfile in a detached background process, so the optional and heavy
  # packages do not block the rest of the setup. FIRST_INSTALL is emptied in the child so that
  # 'brew bundle' treats the run as a full install; output is appended to +log+.
  #
  # @param brew_bin [String] The brew executable.
  # @param log [Pathname, String] File the job's stdout and stderr are appended to.
  # @return [Boolean] true if the job was started (its own success is only visible in +log+).
  def bundle_in_background(log:, brew_bin: 'brew')
    log_path = Pathname.new(log)
    log_path.dirname.mkpath
    pid = Process.spawn(ENV.to_h.merge('FIRST_INSTALL' => ''), brew_bin.to_s, 'bundle',
                        out: [log_path.to_s, 'a'], err: [log_path.to_s, 'a'])
    Process.detach(pid)
    true
  rescue SystemCallError
    false
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
