#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'open3'

require_relative 'command_utils'
require_relative 'core'
require_relative 'env_vars'
require_relative 'logging'

# Makes Homebrew's zsh the user's login shell. macOS ships /bin/zsh, but Homebrew's is newer and
# managed independently; without this, a terminal app's "Login shell" setting stays on /bin/zsh
# even when ${HOMEBREW_PREFIX}/bin/zsh is on PATH, and ${SHELL} stays /bin/zsh after a fresh
# install. fresh-install-of-osx.sh calls it through call-utility.rb at the very end of the run
# (so the password prompt does not interrupt the unattended steps); Ruby callers can use it
# directly.
module DefaultShell
  extend self

  # chsh only accepts shells listed in this file.
  ETC_SHELLS = Core::ROOT.join('etc', 'shells').freeze

  # Public API method.
  #
  # Every check is idempotent and re-run on each call: /etc/shells is validated even when chsh
  # is not needed, because a macOS update can wipe it while the user's UserShell record still
  # points at Homebrew zsh.
  #
  # @return [Boolean] false when Homebrew zsh is missing or when /etc/shells or chsh could not
  #   be updated (each of which is also recorded in this run's summary); true otherwise.
  def run
    ok = false
    Logging.run_script('default_shell', 'Setting the default shell to Homebrew zsh') do
      ok = _set_default_shell(EnvVars::HOMEBREW_PREFIX.join('bin', 'zsh'))
    end
    ok
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  # @param brew_zsh [Pathname] Homebrew's zsh
  # @return [Boolean]
  def _set_default_shell(brew_zsh)
    unless brew_zsh.executable?
      Logging.record_error "Homebrew zsh not found at '#{brew_zsh.to_s.cyan}' -- skipping default shell change."
      return false
    end

    registered = _register_in_etc_shells(brew_zsh.to_s)

    if _configured_shell == brew_zsh.to_s
      Logging.info "Default shell is already configured as '#{brew_zsh.to_s.cyan}' -- skipping."
      return registered
    end

    if CommandUtils.run_interactive('chsh', '-s', brew_zsh.to_s)
      Logging.success "Default shell changed to '#{brew_zsh.to_s.cyan}'."
      return registered
    end

    Logging.record_warning "Failed to change default shell to '#{brew_zsh.to_s.cyan}'. You may need to run '#{"chsh -s #{brew_zsh}".cyan}' manually after installation completes."
    false
  end

  # Adds +shell+ to /etc/shells when it is absent.
  #
  # @param shell [String] Absolute path of the shell
  # @return [Boolean] true when it is (now) listed
  def _register_in_etc_shells(shell)
    # Explicit UTF-8 avoids "invalid byte sequence in US-ASCII" under cron-like environments.
    if Core.read_lines_utf8(ETC_SHELLS).map(&:chomp).include?(shell)
      Logging.info "'#{shell.cyan}' already in '#{ETC_SHELLS.to_s.cyan}' -- skipping."
      return true
    end

    Logging.info "Adding '#{shell.cyan}' to '#{ETC_SHELLS.to_s.cyan}'"
    # The line goes through stdin (array form, no shell). capture3 drains tee's echo on stdout
    # and stderr, so there is nothing to discard and no pipe to deadlock on.
    _stdout, stderr, status = Open3.capture3('sudo', 'tee', '-a', ETC_SHELLS.to_s, stdin_data: "#{shell}\n")
    # An error, not fatal: the chsh that follows then fails and is recorded too.
    CommandUtils.check_status_or_record(nil, stderr, status, "Failed to add '#{shell}' to '#{ETC_SHELLS}'", severity: :error)
  end

  # What chsh configured for future sessions ('dscl'), not the ${SHELL} of the current terminal.
  #
  # @return [String] the login shell, or an empty string when it cannot be read
  def _configured_shell
    CommandUtils.query('dscl', '.', '-read', EnvVars::HOME.to_s, 'UserShell').to_s.split(':').last.to_s.strip
  end

  private_class_method :_set_default_shell, :_register_in_etc_shells, :_configured_shell
end
