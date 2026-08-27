#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'pathname'

require_relative 'command_utils'
require_relative 'core'
require_relative 'enumerable_ext'
require_relative 'env_vars'
require_relative 'logging'
require_relative 'path_utils'
require_relative 'string_ext'

# macOS-specific system operations: login-item app management, softwareupdate
# schedule control, preference reload, and notification display.
#
# These are macOS-only -- callers should not require this module on Linux or Windows.
# :reek:TooManyConstants -- macOS command paths need explicit definitions
module MacOS
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Note: Logging methods must be qualified (Logging.debug, Logging.warn, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # macOS system command paths (absolute paths for reliability in cron/non-interactive contexts)
  DEFAULTS_CMD = Core::ROOT.join('usr', 'bin', 'defaults').to_s.freeze
  DU_CMD = Core::ROOT.join('usr', 'bin', 'du').to_s.freeze
  OSASCRIPT_CMD = Core::ROOT.join('usr', 'bin', 'osascript').to_s.freeze
  PLUTIL_CMD = Core::ROOT.join('usr', 'bin', 'plutil').to_s.freeze
  ZSH_CMD = Core::ROOT.join('bin', 'zsh').to_s.freeze

  # Login-item apps that are killed before defaults writes and restarted after.
  # This is the single source of truth for the login-item app list.
  # Keep in sync with Brewfile setup_login_items_script entries and
  # defaults-write login-key sections in osx-defaults.sh.
  LOGIN_ITEM_APPS = [
    'Clocker',    # startAtLogin = true (com.abhishek.Clocker)
    # 'DockDoor',   # login item via Brewfile setup_login_items_script (SMAppService)
    'KeyCastr',   # login item via Brewfile setup_login_items_script (SMAppService)
    'KeyClu',     # launchAtLogin = true (com.0804Team.KeyClu)
    'Keybase',    # login item via Brewfile setup_login_items_script (SMAppService)
    'Mechvibes',  # login item via Brewfile setup_login_items_script (SMAppService)
    'ProtonVPN',  # login item via Brewfile setup_login_items_script (SMAppService)
    'Shortcat',   # login item via Brewfile setup_login_items_script (SMAppService)
    # 'Sol',        # login item via Brewfile setup_login_items_script (SMAppService)
    # 'Stats',      # LaunchAtLoginNext = true (eu.exelban.Stats)
    'Thaw',       # login item via Brewfile setup_login_items_script (SMAppService)
    'Vorssaint',  # login item via Brewfile setup_login_items_script (SMAppService)
  ].freeze

  # Sends SIGTERM to every app in LOGIN_ITEM_APPS. Called before writing
  # defaults so in-memory state is flushed to disk first.
  # Failures are silenced -- apps that are not running are not an error.
  #
  # Sleeps 1 second after sending signals to ensure apps have fully terminated
  # before the caller proceeds with defaults writes. This prevents race conditions
  # where an app's shutdown handler might flush preferences to disk after we've
  # already started writing new values.
  #
  # @return [void]

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Mutation methods (modify state)
  # ---------------------------------------------------------------------------

  # Sends SIGTERM to every app in LOGIN_ITEM_APPS. Called before writing
  # defaults so in-memory state is flushed to disk first.
  # Verifies each app is running before attempting to kill it.
  # Retries with SIGKILL (-9) if SIGTERM fails after 2 seconds.
  #
  # Sleeps 1 second after sending signals to ensure apps have fully terminated
  # before the caller proceeds with defaults writes. This prevents race conditions
  # where an app's shutdown handler might flush preferences to disk after we've
  # already started writing new values.
  #
  # @return [void]
  def kill_login_item_apps
    LOGIN_ITEM_APPS.each do |app|
      next unless _process_running?(app)

      Logging.debug "Terminating '#{app.cyan}'..."
      if CommandUtils.run_silent('killall', '-TERM', app)
        # Wait for graceful shutdown
        sleep 2
        # Verify termination succeeded
        if _process_running?(app)
          Logging.warn "#{app.yellow} did not terminate gracefully, forcing kill..."
          CommandUtils.run_silent('killall', '-9', app)
          sleep 1
        end
      else
        Logging.warn "Failed to terminate '#{app.yellow}'"
      end
    end

    # Finder is launchd-managed; killall causes immediate relaunch
    CommandUtils.run_silent('killall', 'Finder')

    # Give apps time to fully terminate before defaults writes begin
    sleep 1
  end

  # Re-opens every app in LOGIN_ITEM_APPS. Called from an EXIT trap
  # after defaults writes complete so the user is never left with login-item
  # apps dead.
  # Finder is launchd-managed: killall causes an immediate auto-relaunch with
  # fresh prefs. open -a would be a no-op since launchd already relaunched it
  # after kill_login_item_apps -- so killall is used again here to force a
  # second relaunch that reads the newly-written defaults.
  #
  # @return [void]
  # :reek:UtilityFunction -- Stateless utility that operates only on constants
  def restart_login_item_apps
    LOGIN_ITEM_APPS.each do |app|
      CommandUtils.run_silent('open', '-a', app)
    end
    # Finder is launchd-managed; killall causes immediate relaunch
    CommandUtils.run_silent('killall', 'Finder')
  end

  # Turns off the macOS automatic software update schedule and starts a
  # background thread to keep sudo credentials alive. The keep-alive thread
  # guards against duplicate launches -- it is a no-op if already running.
  #
  # @return [void]
  def suspend_softwareupdate_schedule
    _set_softwareupdate_schedule('OFF', 'suspend')
  end

  # Turns the macOS automatic software update schedule back on. Called from the
  # EXIT trap in osx-defaults.sh and capture-prefs.rb so it runs on both normal
  # and error exits. Guards with sudo check so it is safe to call from cron --
  # if sudo credentials are not cached (no terminal), warns and skips rather than
  # hanging. keep_sudo_alive's duplicate-loop guard makes it a no-op when the
  # background loop is already running.
  #
  # @return [void]
  def resume_softwareupdate_schedule
    _set_softwareupdate_schedule('ON', 'resume')
  end

  # Reloads macOS system preferences by killing preference-related processes
  # and invoking activateSettings. Called after defaults writes to ensure
  # changes are immediately visible without logout/restart.
  #
  # @return [void]
  def reload_macos_prefs
    # Kill cfprefsd first to flush the preferences cache to disk.
    # cfprefsd is the macOS preferences daemon that caches defaults in memory.
    # Killing it forces a write of all pending changes to the plist files.
    CommandUtils.run_silent('killall', 'cfprefsd')

    # Wait for cfprefsd to finish flushing changes to disk before restarting apps.
    # Without this delay, Finder/Dock may restart and read stale preferences before
    # cfprefsd has finished writing the new values.
    sleep 1

    # Now kill the apps so they reload preferences on restart.
    # Finder and Dock restart automatically. SystemUIServer manages menu bar extras.
    %w[Dock Finder SystemUIServer].each do |app|
      CommandUtils.run_silent('killall', app)
    end

    system('/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings', '-u')
  end

  # Sends a macOS notification using terminal-notifier (preferred) or osascript (fallback).
  # Visible to the user even when the script is running in a non-interactive context (cron, etc.).
  # Rate-limits duplicate notifications within 60 seconds to prevent spam.
  #
  # Prefers terminal-notifier for richer notification control (sound, subtitle, actions).
  # Falls back to osascript (always available on macOS) if terminal-notifier not installed.
  #
  # @param message [String] The notification body text
  # @param title [String] The notification title (default: 'Dotfiles')
  # @return [void]
  def notify(message, title = 'Dotfiles')
    key = "#{title}:#{message}"
    now = Time.now.to_i

    # Check if we've sent this notification recently
    @_notification_history ||= {}
    if @_notification_history.key?(key)
      last_sent = @_notification_history[key]
      if now - last_sent < 60
        Logging.debug "Skipping duplicate notification (sent #{now - last_sent}s ago): #{message}"
        return
      end
    end

    # Strip ANSI color codes (message may contain color methods like .cyan, .purple)
    # ANSI escape sequences match pattern: ESC [ ... m
    clean_message = message.to_s.gsub(/\e\[[0-9;]*m/, '')
    clean_title = title.to_s.gsub(/\e\[[0-9;]*m/, '')

    # Prefer terminal-notifier for richer notifications (sound, subtitle, actions, etc.)
    # Fall back to osascript if terminal-notifier not installed (vanilla OS compatibility)
    if PathUtils.command_exists?('terminal-notifier')
      # terminal-notifier supports: custom sound, subtitle, group, actions, app bundle ID
      # -sound default: plays system notification sound (osascript is silent by default)
      CommandUtils.run_silent('terminal-notifier', '-message', clean_message, '-title', clean_title, '-sound', 'default')
    else
      # osascript fallback: simpler, no sound, but always available (single-line AppleScript)
      CommandUtils.run_silent('osascript', '-e', "display notification \"#{clean_message}\" with title \"#{clean_title}\"")
    end

    # Record this notification
    @_notification_history[key] = now

    # Cleanup old entries (older than 5 minutes)
    @_notification_history.delete_if { |_k, timestamp| now - timestamp > 300 }
  end

  # Checks for outdated Homebrew casks (with --greedy flag) and returns a
  # formatted string of outdated app names. Logs a warning if any are found.
  # Returns empty string if none are outdated or if brew is not available.
  #
  # @return [String] Comma-separated list of outdated apps, or empty string
  def check_and_notify_outdated_apps
    return '' unless PathUtils.command_exists?('brew')

    outdated_raw = CommandUtils.query('brew', 'outdated', '--greedy')
    # filter_map polyfill in enumerable_ext.rb provides optimized single-pass implementation for Ruby 2.6
    outdated = outdated_raw.lines.filter_map do |line|
      next if nil_or_empty?(line)

      stripped = line.strip
      stripped unless stripped.match?(/homebrew|Downloading/i)
    end

    return '' if nil_or_empty?(outdated)

    Logging.warn "Found outdated software needing manual update: #{outdated.join(', ').yellow}"
    outdated.join(', ')
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  private

  # Checks if a process with the given name is running.
  # Uses pgrep to search for exact process name match.
  #
  # @param process_name [String] Name of the process to check
  # @return [Boolean] true if process is running, false otherwise
  def _process_running?(process_name)
    CommandUtils.run_silent('pgrep', '-x', process_name)
  end

  # Sets the macOS automatic software update schedule to ON or OFF.
  # Checks for sudo credentials, starts keep-alive thread, and runs softwareupdate.
  #
  # @param state [String] 'ON' or 'OFF'
  # @param action [String] 'suspend' or 'resume' (for log messages)
  # @return [void]
  def _set_softwareupdate_schedule(state, action)
    unless _has_sudo_credentials?
      Logging.debug "#{action}_softwareupdate_schedule: sudo credentials not available -- skipping"
      return
    end
    _keep_sudo_alive
    CommandUtils.run_silent('sudo', 'softwareupdate', '--schedule', state)
  end

  # Checks if sudo credentials are cached (non-interactive sudo is possible).
  # Uses 'sudo -n true' which succeeds if credentials are cached, fails otherwise.
  #
  # @return [Boolean] true if sudo credentials are available
  def _has_sudo_credentials?
    CommandUtils.run_silent('sudo', '-n', 'true')
  end

  # Starts a background thread that runs 'sudo -v' every 60 seconds to keep
  # sudo credentials alive. Guarded by @_sudo_alive_running flag so it is safe
  # to call multiple times -- only one thread ever runs.
  #
  # @return [void]
  def _keep_sudo_alive
    return if @_sudo_alive_running

    @_sudo_alive_running = true
    Thread.new do
      loop do
        sleep 60
        break unless CommandUtils.run_silent('sudo', '-v')
      end
    end
  end

  private_class_method :_process_running?, :_set_softwareupdate_schedule,
                       :_has_sudo_credentials?, :_keep_sudo_alive
end
