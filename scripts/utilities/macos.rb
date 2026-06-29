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
  # TODO: Duplicated in .aliases and macos.rb - need to find a way to have only 1 copy
  LOGIN_ITEM_APPS = [
    'Clocker',   # startAtLogin = true (com.abhishek.Clocker)
    'DockDoor',  # login item via Brewfile setup_login_items_script (SMAppService)
    'KeyCastr',  # login item via Brewfile setup_login_items_script (SMAppService)
    'KeyClu',    # launchAtLogin = true (com.0804Team.KeyClu)
    'Keybase',   # login item via Brewfile setup_login_items_script (SMAppService)
    'Mechvibes',  # login item via Brewfile setup_login_items_script (SMAppService)
    'ProtonVPN', # login item via Brewfile setup_login_items_script (SMAppService)
    'Shortcat',   # login item via Brewfile setup_login_items_script (SMAppService)
    'Sol',       # login item via Brewfile setup_login_items_script (SMAppService)
    'Stats',     # LaunchAtLoginNext = true (eu.exelban.Stats)
    'Thaw'      # login item via Brewfile setup_login_items_script (SMAppService)
  # 'Vorssaint', # login item via Brewfile setup_login_items_script (SMAppService)
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

  # Parses `brew shellenv` output and merges the exported variables into the
  # current process environment. This is the Ruby equivalent of eval_shellenv
  # in .shellrc -- it ensures homebrew bins are on PATH for subsequent system()
  # calls without forking a shell.
  #
  # @param brew_bin [Pathname, String] Path to brew binary.
  # @return [void]
  #
  # @example
  #   MacOS.load_brew_shellenv(Pathname.new('/opt/homebrew/bin/brew'))
  def load_brew_shellenv(brew_bin)
    brew_bin = Pathname.new(brew_bin) unless brew_bin.is_a?(Pathname)
    return unless brew_bin.executable?

    brew_env_out, = Open3.capture3(brew_bin.to_s, 'shellenv')
    brew_env_out.each_line do |line|
      # Parse simple export lines: export KEY="value"; (note trailing semicolon)
      if (m = line.match(/^export (\w+)="([^"]*)"/))
        ENV[m[1]] = m[2]
        next
      end

      # Handle path_helper eval line: eval "$(/usr/bin/env PATH_HELPER_ROOT="..." /usr/libexec/path_helper -s)"
      next unless (m = line.match(/eval "\$\((.+)\)"/))

      # Execute the command inside $(...) and parse its output
      cmd = m[1]
      path_helper_out, = Open3.capture3(cmd)
      path_helper_out.each_line do |ph_line|
        # Parse path_helper output: KEY="value"; export KEY;
        next unless (ph_m = ph_line.match(/^(\w+)="([^"]*)"; export \1;$/))

        ENV[ph_m[1]] = ph_m[2]
      end
    end
    Logging.debug "Loaded brew shellenv from '#{brew_bin}'"
  end

  # Returns the brewfile content trimmed to the base section for first install.
  # Strips lines at and after the first non-comment line containing 'EnvVars.first_install?',
  # matching the shell sed truncation in _install_homebrew.
  #
  # @return [String] Brewfile content (full or trimmed based on EnvVars.first_install?)
  #
  # @example
  #   content = MacOS.first_install_brewfile_content
  def first_install_brewfile_content
    lines = EnvVars::HOMEBREW_BUNDLE_FILE.readlines
    cutoff = lines.index { |l| l.include?('FIRST_INSTALL') }
    base_lines = cutoff ? lines[0...cutoff] : lines
    base_lines.reject { |l| l.comment_or_empty? }.join
  end

  # Trusts custom taps and runs brew bundle to install formulae/casks from Brewfile.
  # On first install, only installs the base section (fast essentials) and forks
  # a background process for the full Brewfile. On pre-configured machines, runs
  # the full Brewfile install synchronously.
  #
  # @param brew_bin [Pathname, String] Path to brew executable
  # @return [Boolean] true if brew bundle succeeded, false if it had errors
  #
  # @example
  #   success = MacOS.install_homebrew_bundle(EnvVars::HOMEBREW_PREFIX.join('bin', 'brew'))
  def install_homebrew_bundle(brew_bin)
    # Ensure brew_bin is a Pathname for consistent .executable? checks
    brew_bin = Pathname.new(brew_bin) unless brew_bin.is_a?(Pathname)

    # Trust all custom taps defined in the Brewfile before running brew bundle.
    # This ensures taps are trusted before any formulae/casks from those taps are
    # installed, which is required if HOMEBREW_REQUIRE_TAP_TRUST is enforced.
    if nil_or_empty?(brew_bin.to_s) || !brew_bin.executable?
      Logging.warn "Brew binary '#{brew_bin}' not executable -- skipping bundle install"
      return false
    end

    custom_taps = _custom_taps_from_brewfile(brew_bin)
    if custom_taps.any?
      Logging.info "Trusting custom taps: #{custom_taps.join(', ').yellow}"
      system(brew_bin.to_s, 'trust', '--tap', '-q', *custom_taps) || true  # Don't fail if trust fails
    end

    # Run brew bundle. On EnvVars.first_install?, only install the base section of the Brewfile
    # to keep the initial run fast; fork the full install in the background.
    brew_bundle_exit = 0
    if EnvVars.first_install?
      content = first_install_brewfile_content
      # brew bundle --file=- reads the Brewfile from stdin.
      check_ok = system(brew_bin.to_s, 'bundle', 'check', out: File::NULL, err: File::NULL)
      unless check_ok
        # Use Core.stream_command for real-time output during package installation.
        brew_bundle_exit = Core.stream_command([brew_bin.to_s, 'bundle', '--file=-'], stdin_data: content)
      end
    else
      check_ok = system(brew_bin.to_s, 'bundle', 'check', out: File::NULL, err: File::NULL)
      unless check_ok
        system(brew_bin.to_s, 'bundle') || (brew_bundle_exit = 1)
      end
    end

    if brew_bundle_exit.zero?
      Logging.success 'Successfully installed cmd-line and GUI apps using Homebrew'
    else
      Logging.record_warning 'Homebrew bundle install encountered errors; continuing...'
    end

    if EnvVars.first_install?
      # Fork the full Brewfile install in the background so optional/heavy packages
      # install without blocking the rest of this run. FIRST_INSTALL is unset in
      # the child so brew bundle processes the complete Brewfile.
      full_bundle_log = EnvVars::HOME.join('brew-bundle-full-install.log')
      pid = Process.spawn(
        ENV.to_h.merge('FIRST_INSTALL' => ''),
        brew_bin.to_s, 'bundle',
        out: [full_bundle_log.to_s, 'a'], err: [full_bundle_log.to_s, 'a']
      )
      Process.detach(pid)
      Logging.info "Full Brewfile install running in background (log: '#{full_bundle_log.to_s.cyan}')"
    end

    brew_bundle_exit.zero?
  end

  # Sets up Touch ID for sudo access in terminal shells by enabling pam_tid.so.
  # Skips if Touch ID hardware not detected or if already configured.
  #
  # @return [void]
  def approve_fingerprint_sudo
    Logging.section_header 'Setting up Touch ID for sudo access in terminal shells'

    # AppleBiometricSensor = T1/T2 chip (Intel); AppleBiometricServices = Apple Silicon.
    sensor_out, = Open3.capture3('ioreg', '-c', 'AppleBiometricSensor')
    sensor = sensor_out.include?('AppleBiometricSensor')
    services_out, = Open3.capture3('ioreg', '-c', 'AppleBiometricServices')
    services = services_out.include?('AppleBiometricServices')
    unless sensor || services
      Logging.info 'Touch ID hardware not detected -- skipping configuration.'
      return
    end

    template_file_pn = Pathname.new('/etc/pam.d/sudo_local.template')
    unless template_file_pn.file?
      Logging.warn "Template file '#{template_file_pn}' not found -- skipping."
      return
    end

    target_file_pn = Pathname.new('/etc/pam.d/sudo_local')
    if target_file_pn.file?
      Logging.info "'#{target_file_pn.to_s.cyan}' already present -- skipping."
    else
      content = template_file_pn.read.gsub(/^#auth/, 'auth')
      tmp = Tempfile.new('sudo_local')
      tmp.write(content)
      tmp.close
      result = system('sudo', 'cp', tmp.path, target_file_pn.to_s)
      tmp.unlink
      if result
        Logging.success "Created '#{target_file_pn.to_s.cyan}'"
      else
        Logging.record_error "Failed to create '#{target_file_pn.to_s.cyan}'"
      end
    end
  end

  # Verifies FileVault disk encryption is active. Raises RuntimeError if not.
  #
  # @return [void]
  # @raise [RuntimeError] if FileVault is not enabled
  def ensure_filevault_is_on
    Logging.section_header 'Verifying FileVault status'
    fv_out, = Open3.capture3('fdesetup', 'isactive')
    unless fv_out.strip == 'true'
      Logging.error 'FileVault is not turned on. Please encrypt your hard disk!'
      # Logging.error raises RuntimeError; at_exit cleanup hooks still run.
    end
  end

  # Installs Xcode Command Line Tools via non-interactive softwareupdate.
  # Skips if already installed. Raises RuntimeError if installation fails.
  #
  # @return [void]
  # @raise [RuntimeError] if installation fails
  def install_xcode_command_line_tools
    Logging.section_header 'Installing Xcode command-line tools'

    software_update_marker_file = Pathname.new('/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress')
    if system('xcode-select', '-p', out: File::NULL, err: File::NULL)
      Logging.info 'Xcode command-line tools already present -- skipping.'
      # Idempotency cleanup: remove the in-progress sentinel unconditionally.
      software_update_marker_file.delete if software_update_marker_file.exist?
      return
    end

    software_update_marker_file.write('')
    unless system('sudo', 'softwareupdate', '-ia', '--agree-to-license', '--force')
      Logging.record_warning 'softwareupdate encountered errors during Xcode CLT install'
    end
    software_update_marker_file.delete if software_update_marker_file.exist?

    unless system('xcode-select', '-p', out: File::NULL, err: File::NULL)
      Logging.error "Couldn't install Xcode command-line tools; aborting"
    end
    Logging.success 'Successfully installed Xcode command-line tools'
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  private

  # Returns custom tap names from the Brewfile (excluding homebrew/* taps).
  # Uses 'brew bundle list --taps' to extract tap declarations.
  #
  # @param brew_bin [Pathname, String] Path to brew executable
  # @return [Array<String>] Custom tap names, or empty array if Brewfile doesn't exist or brew_bin not executable
  def _custom_taps_from_brewfile(brew_bin)
    # Ensure brew_bin is a Pathname for consistent .executable? checks
    brew_bin = Pathname.new(brew_bin) unless brew_bin.is_a?(Pathname)

    return [] if nil_or_empty?(brew_bin.to_s) || !brew_bin.executable?
    return [] unless EnvVars::HOMEBREW_BUNDLE_FILE.file?

    tap_output, = Open3.capture2(brew_bin.to_s, 'bundle', 'list', '--taps', "--file=#{EnvVars::HOMEBREW_BUNDLE_FILE.to_s}")
    tap_output.lines.map(&:strip).reject { |tap| tap.start_with?('homebrew/') }
  end

  # Sets the macOS automatic software update schedule to ON or OFF.
  # Checks for sudo credentials, starts keep-alive thread, and runs softwareupdate.
  #
  # @param state [String] 'ON' or 'OFF'
  # @param action [String] 'suspend' or 'resume' (for log messages)
  # @return [void]
  def _set_softwareupdate_schedule(state, action)
    unless _has_sudo_credentials
      Logging.debug "#{action}_softwareupdate_schedule: sudo credentials not available -- skipping"
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
  private_class_method :_set_softwareupdate_schedule, :_has_sudo_credentials, :_keep_sudo_alive
end
