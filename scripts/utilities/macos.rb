#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'pathname'

require_relative 'core'
require_relative 'env_vars'
require_relative 'logging'
require_relative 'string'

# macOS-specific system operations: login-item app management, softwareupdate
# schedule control, preference reload, and notification display.
#
# These are macOS-only -- callers should not require this module on Linux or Windows.
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
  # Keep in sync with Brewfile setup_login_items_script entries and
  # defaults-write login-key sections in osx-defaults.sh.
  LOGIN_ITEM_APPS = [
    'Clocker',   # startAtLogin = true (com.abhishek.Clocker)
    'DockDoor',  # login item via Brewfile setup_login_items_script (SMAppService)
    'KeyCastr',  # login item via Brewfile setup_login_items_script (SMAppService)
    'KeyClu',    # launchAtLogin = true (com.0804Team.KeyClu)
    'Keybase',   # login item via Brewfile setup_login_items_script (SMAppService)
    'Maccy',     # login item via Brewfile setup_login_items_script (SMAppService)
    'Moom',      # Start Moom at login = true (com.manytricks.Moom)
    'ProtonVPN', # login item via Brewfile setup_login_items_script (SMAppService)
    'Sol',       # login item via Brewfile setup_login_items_script (SMAppService)
    'Stats',     # LaunchAtLoginNext = true (eu.exelban.Stats)
    'Thaw'       # login item via Brewfile setup_login_items_script (SMAppService)
  ].freeze

  # Returns the current wall-clock time formatted as 'YYYY-MM-DD HH:MM:SS',
  # mirroring current_timestamp in .shellrc.
  #
  # @return [String]
  def current_timestamp
    Time.now.strftime('%Y-%m-%d %H:%M:%S')
  end

  # Checks if the script is running in a TTY (terminal) context.
  # Returns true when stdout is a TTY or FORCE_COLOR env var is set.
  # Used to gate interactive operations (app kill/restart, prompts, etc.)
  # that should not run in cron or non-interactive contexts.
  #
  # @return [Boolean] true if running in TTY context
  def running_in_tty?
    $stdout.tty? || EnvVars.force_color?
  end

  # Sends SIGTERM to every app in LOGIN_ITEM_APPS. Called before writing
  # defaults so in-memory state is flushed to disk first.
  # Failures are silenced -- apps that are not running are not an error.
  #
  # @return [void]
  def kill_login_item_apps
    LOGIN_ITEM_APPS.each do |app|
      system('killall', app, out: File::NULL, err: File::NULL)
    end
    # Finder is launchd-managed; killall causes immediate relaunch
    system('killall', 'Finder', out: File::NULL, err: File::NULL)
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
  def restart_login_item_apps
    LOGIN_ITEM_APPS.each do |app|
      system('open', '-a', app, out: File::NULL, err: File::NULL)
    end
    # Finder is launchd-managed; killall causes immediate relaunch
    system('killall', 'Finder', out: File::NULL, err: File::NULL)
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
    %w[cfprefsd Dock Finder SystemUIServer].each do |app|
      system('killall', app, out: File::NULL, err: File::NULL)
    end
    system('/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings', '-u')
  end

  # Sends a macOS notification via osascript. Visible to the user even when
  # the script is running in a non-interactive context (cron, etc.).
  #
  # @param message [String] The notification body text
  # @param title [String] The notification title (default: 'Dotfiles')
  # @return [void]
  def notify(message, title = 'Dotfiles')
    applescript = <<~APPLESCRIPT
      display notification "#{message}" with title "#{title}"
    APPLESCRIPT
    system('osascript', '-e', applescript, out: File::NULL, err: File::NULL)
  end

  # Checks for outdated Homebrew casks (with --greedy flag) and returns a
  # formatted string of outdated app names. Logs a warning if any are found.
  # Returns empty string if none are outdated or if brew is not available.
  #
  # @return [String] Comma-separated list of outdated apps, or empty string
  def check_and_notify_outdated_apps
    return '' unless PathUtils.command_exists?('brew')

    outdated_raw, = Open3.capture3('brew', 'outdated', '--greedy')
    outdated = outdated_raw.lines
                           .reject { |l| nil_or_empty?(l.strip) || l.match?(/homebrew|Downloading/i) }
                           .map(&:strip)

    return '' if nil_or_empty?(outdated)

    Logging.warn "Found outdated software needing manual update: #{outdated.join(', ').yellow}"
    outdated.join(', ')
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  private

  # Sets the macOS automatic software update schedule to ON or OFF.
  # Checks for sudo credentials, starts keep-alive thread, and runs softwareupdate.
  #
  # @param state [String] 'ON' or 'OFF'
  # @param action [String] 'suspend' or 'resume' (for log messages)
  # @return [void]
  def _set_softwareupdate_schedule(state, action)
    unless _has_sudo_credentials
      Logging.warn "#{action}_softwareupdate_schedule: sudo credentials not available -- skipping"
      return
    end
    _keep_sudo_alive
    system('sudo', 'softwareupdate', '--schedule', state)
  end

  # Checks if sudo credentials are cached (non-interactive sudo is possible).
  # Uses 'sudo -n true' which succeeds if credentials are cached, fails otherwise.
  #
  # @return [Boolean] true if sudo credentials are available
  def _has_sudo_credentials
    system('sudo', '-n', 'true', out: File::NULL, err: File::NULL)
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
        break unless system('sudo', '-v', out: File::NULL, err: File::NULL)
      end
    end
  end
end
