#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'pathname'
require 'shellwords'

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

  # Prompts for sudo credentials once ('sudo -v'), then starts a background thread that
  # refreshes them every 60 seconds for the remainder of the running script (same behavior
  # as keep_sudo_alive in .shellrc). Standalone entry point for callers (e.g.
  # fresh-install-of-osx.rb) that only need the keep-alive behavior, without the side effect
  # of also disabling the software-update schedule that suspend_softwareupdate_schedule
  # below carries. Shares the private _keep_sudo_alive helper with
  # suspend_softwareupdate_schedule/resume_softwareupdate_schedule, guarded by
  # @_sudo_alive_running so only one thread ever runs regardless of which caller started
  # it first.
  #
  # @return [void]
  def keep_sudo_alive
    CommandUtils.run_interactive('sudo', '-v')
    _keep_sudo_alive
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
    # NotificationCenter/usernoted/usernotificationsd own com.apple.ncprefs (per-app
    # notification permissions) -- without restarting these too, an imported ncprefs
    # change (e.g. via capture-prefs.rb -i) stays invisible until the next logout.
    # All are launchd-managed and relaunch automatically once killed.
    %w[Dock Finder SystemUIServer NotificationCenter usernoted usernotificationsd].each do |app|
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
        Logging.debug "Skipping duplicate notification (sent #{(now - last_sent).to_s.purple}s ago): #{message}"
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

  # Variables a throwaway 'sh' changes on its own (not exported by 'brew shellenv'), so they
  # are never copied back into this process.
  SHELLENV_IGNORED_KEYS = %w[_ SHLVL PWD OLDPWD].freeze

  # Evaluates `brew shellenv` and merges the variables it exports into the current process
  # environment, ensuring Homebrew bins are on PATH for subsequent system()/backtick calls.
  #
  # @param brew_bin [Pathname, String] Path to brew binary.
  # @return [void]
  #
  # @example
  #   MacOS.load_brew_shellenv(Pathname.new('/opt/homebrew/bin/brew'))
  # :reek:UtilityFunction -- Stateless wrapper for parsing/applying brew shellenv output (intentional)
  # :reek:FeatureEnvy -- Stateless helper operating on its own parameter (intentional)
  def load_brew_shellenv(brew_bin)
    brew_bin = Pathname.new(brew_bin) unless brew_bin.is_a?(Pathname)
    return unless brew_bin.executable?

    # Evaluate brew shellenv's output in a real shell rather than hand-parsing arbitrary shell
    # syntax -- far more robust than a regex-based parser, which cannot correctly handle
    # constructs like 'export INFOPATH="...:${INFOPATH:-}"' (variable expansion),
    # '[ -z "${MANPATH-}" ] || export ...' (conditional), or path_helper's own
    # nested 'eval "$(...)"'. env -0 dumps the resulting environment NUL-separated
    # (safe against values containing newlines).
    env_output, = Open3.capture3('sh', '-c', %(eval "$(#{Shellwords.escape(brew_bin.to_s)} shellenv)" && env -0))
    env_output.split("\0").each do |line|
      key, value = line.split('=', 2)
      next if nil_or_empty?(key) || SHELLENV_IGNORED_KEYS.include?(key)

      ENV[key] = value
    end
    Logging.debug "Loaded brew shellenv from '#{brew_bin.cyan}'"
  end

  # Sets up Touch ID for sudo access in terminal shells by enabling pam_tid.so.
  # Skips if Touch ID hardware not detected or if already configured.
  #
  # @return [void]
  # :reek:FeatureEnvy -- Local Tempfile manages content through validation/copy steps (intentional)
  def approve_fingerprint_sudo
    Logging.section_header 'Setting up Touch ID for sudo access in terminal shells'

    # AppleBiometricSensor = T1/T2 chip (Intel Macs); AppleBiometricServices = Apple Silicon
    # Check for Touch ID hardware (single ioreg call for both classes)
    biometric_output = CommandUtils.query('ioreg', '-c', 'AppleBiometricSensor', '-c', 'AppleBiometricServices')
    if nil_or_empty?(biometric_output)
      Logging.info 'Touch ID hardware not detected -- skipping configuration.'
      return
    end

    template_file_pn = Core::ROOT.join('etc', 'pam.d', 'sudo_local.template')
    unless template_file_pn.file?
      Logging.warn "Template file '#{template_file_pn.cyan}' not found -- skipping."
      return
    end

    target_file_pn = Core::ROOT.join('etc', 'pam.d', 'sudo_local')
    target_file_str = target_file_pn.to_s
    target_file_cyan = target_file_str.cyan
    if target_file_pn.file?
      Logging.info "'#{target_file_cyan}' already present -- skipping."
    else
      # Use explicit UTF-8 encoding to avoid "invalid byte sequence in US-ASCII".
      content = template_file_pn.read(encoding: 'UTF-8').gsub(/^#auth/, 'auth')
      require 'tempfile'
      tmp = Tempfile.new('sudo_local')
      tmp.write(content)
      tmp.close
      # 'install -m 0644' gives the file the same mode/owner a root shell redirect would
      # (a plain 'sudo cp' of the 0600 tempfile would leave it 0600).
      CommandUtils.run_interactive('sudo', 'install', '-m', '0644', '-o', 'root', '-g', 'wheel', tmp.path, target_file_str) do
        Logging.record_error "Failed to create '#{target_file_cyan}'"
        tmp.unlink
        return
      end
      tmp.unlink
      Logging.success "Created '#{target_file_cyan}'"
    end
  end

  # Verifies FileVault disk encryption is active. Raises RuntimeError if not.
  #
  # @return [void]
  # @raise [RuntimeError] if FileVault is not enabled
  # :reek:UtilityFunction -- Stateless system check, no instance state needed (intentional)
  def ensure_filevault_is_on
    Logging.section_header 'Verifying FileVault status'
    fv_out = CommandUtils.query('fdesetup', 'isactive')
    return if fv_out.strip == 'true'

    Logging.user_action 'Enable FileVault: System Settings → Privacy & Security → FileVault → Turn On FileVault'
    # Logging.error raises RuntimeError; at_exit cleanup hooks still run.
    Logging.error 'FileVault is not turned on. Please encrypt your hard disk!'
  end

  # Installs Xcode Command Line Tools via non-interactive softwareupdate.
  # Skips if already installed. Raises RuntimeError if installation fails.
  #
  # @return [void]
  # @raise [RuntimeError] if installation fails
  # :reek:FeatureEnvy -- Local marker-file lifecycle (write/check/delete) is intentional
  def install_xcode_command_line_tools
    # List available software updates (filtered to just package names). Always runs,
    # regardless of whether CLT is already installed. softwareupdate writes the
    # '*'-prefixed lines we care about to stderr, not stdout -- capture2e merges both
    # streams.
    Logging.section_header 'Listing available software updates'
    combined_output, = Open3.capture2e('softwareupdate', '--list')
    combined_output.each_line do |line|
      puts line if line.strip.start_with?('*')
    end

    Logging.section_header 'Installing Xcode command-line tools'
    software_update_marker_file = Core::ROOT.join('tmp', '.com.apple.dt.CommandLineTools.installondemand.in-progress')

    if CommandUtils.run_silent('xcode-select', '-p')
      Logging.info 'Xcode command-line tools already present -- skipping.'
    else
      begin
        software_update_marker_file.write('')
        CommandUtils.run_interactive('sudo', 'softwareupdate', '-ia', '--agree-to-license', '--force') do
          Logging.record_warning 'softwareupdate encountered errors during Xcode CLT install'
        end
      ensure
        software_update_marker_file.delete if software_update_marker_file.exist?
      end

      Logging.error "Couldn't install Xcode command-line tools; aborting" unless CommandUtils.run_silent('xcode-select', '-p')
      Logging.success 'Successfully installed Xcode command-line tools'
    end

    # Duplicate the cleanup if the installation was cancelled and continued via the GUI --
    # runs regardless of which branch above was taken.
    software_update_marker_file.delete if software_update_marker_file.exist?
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
    # 'sudo -n true' (never prompts, never gives up) refreshes cached credentials like the
    # keep_sudo_alive in .shellrc; 'sudo -v' could prompt from this background thread and
    # stopping at the first failure would silently end the keep-alive.
    Thread.new do
      loop do
        sleep 60
        CommandUtils.run_silent('sudo', '-n', 'true')
      end
    end
  end

  private_class_method :_process_running?, :_set_softwareupdate_schedule,
                       :_has_sudo_credentials?, :_keep_sudo_alive
end
