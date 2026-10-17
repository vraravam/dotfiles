#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/setup-login-item.rb
#
# Registers an app as a macOS login item.
#
# On macOS 14-25: uses SMAppService.loginItem(url:) via an inline Swift script.
#   Items appear under "Open at Login" in System Settings (not "Legacy").
#   First-time registration lands in "Requires Approval" -- the user must
#   approve in System Settings > General > Login Items before it is active.
#   Requires Xcode Command Line Tools (always present when Homebrew is installed).
#
# On macOS 26+: SMAppService.loginItem(url:) was removed; falls back to the
#   legacy System Events AppleScript path (same as macOS 13 and earlier).
#
# On macOS 13 and earlier: uses the legacy System Events AppleScript.
#   Items show as "Legacy" in System Settings on macOS 13.
#
# The -b flag enables hidden/background mode (no Dock icon at launch).
#   macOS 13 and earlier: sets hidden:true in the legacy AppleScript call.
#   macOS 14-25: background behaviour is determined by the app's own Info.plist
#   (LSUIElement/LSBackgroundOnly); -b emits a user_action hint instead.
#
# The inverse (used by 'implode' to get a machine back to a first-install state): --remove-managed
# unregisters the login item of every app this repo registers -- the '-a' names in the Brewfile's
# 'setup_login_items_script' lines plus MacOS::LOGIN_ITEM_APPS. Apps that are not installed, and
# apps that have no login item, are skipped without complaint.
#
# Usage:
#   Standalone: setup-login-item.rb [-h] -a <app-name> [-b]
#               setup-login-item.rb [-h] --register-managed
#               setup-login-item.rb [-h] --remove-managed
#   Module:     SetupLoginItem.run(app_name: 'App', background: false)
#               SetupLoginItem.register_managed
#               SetupLoginItem.remove_managed

require_relative 'utilities/command_utils'
require_relative 'utilities/logging'
require_relative 'utilities/macos'
require_relative 'utilities/path_utils'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module SetupLoginItem
  extend self

  # Public API method.
  #
  # @param app_name [String] Name of the application (e.g., 'Clocker')
  # @param background [Boolean] Enable hidden/background mode (default: false)
  # @return [Boolean] true on success, false on error
  # :reek:FeatureEnvy
  def run(app_name:, background: false)
    app_path_pn = Core::ROOT.join('Applications', "#{app_name}.app")
    app_path_str = app_path_pn.to_s
    app_name_colored = app_name.yellow

    unless app_path_pn.directory?
      Logging.info "Application '#{app_path_pn.cyan}' not found -- skipping login item setup."
      return true # Not an error, just nothing to do
    end

    # Detect macOS major version to choose the registration path.
    macos_major = CommandUtils.query('sw_vers', '-productVersion').split('.').first.to_i

    if macos_major >= 14 && macos_major < 26
      # macOS 14-25: SMAppService.loginItem(url:) registers the app as a proper
      # login item (appears under "Open at Login", not "Legacy" in System Settings).
      # First registration lands in .requiresApproval -- the user must approve in
      # System Settings > General > Login Items before the item is active.
      # The -b flag has no effect here: Dock visibility is determined by the app's
      # own Info.plist (LSUIElement/LSBackgroundOnly), not the registration call.
      # macOS 26 removed loginItem(url:) and replaced it with loginItem(identifier:)
      # which only works for login item helpers bundled WITHIN an app -- not for
      # registering standalone third-party apps externally. macOS 26+ falls through
      # to the legacy System Events path below.
      if _register_smappservice(app_path_str)
        Logging.success "Registered '#{app_name_colored}' as a login item (SMAppService)"
        Logging.user_action "Open System Settings > General > Login Items and approve '#{app_name_colored}' under 'Open at Login'."
        Logging.user_action "'#{app_name_colored}': enable background/hidden mode via the app's own preferences or System Settings -- SMAppService does not expose a hidden-at-launch flag." if background
        true
      else
        Logging.record_warning("Failed to register '#{app_name_colored}' via SMAppService")
        false
      end
    else
      # macOS 13 and earlier, and macOS 26+: use the legacy System Events AppleScript.
      # Items registered this way show as "Legacy" in System Settings on macOS 13.
      # hidden=true suppresses the Dock icon at launch (background/hidden mode).
      # rubocop:disable Style/IfInsideElse
      if _register_legacy(app_name, app_path_str, background ? 'true' : 'false')
        Logging.success "Registered '#{app_name_colored}' as a #{background ? 'login item (hidden/background mode)' : 'login item'} (legacy)"
        true
      else
        Logging.record_warning("Failed to register '#{app_name_colored}' via System Events")
        false
      end
      # rubocop:enable Style/IfInsideElse
    end
  end

  # Matches the '-a <app>' of a 'setup_login_items_script' call on a Brewfile line that is not
  # commented out (a '#' that does not start a '#{...}' interpolation disables the line).
  BREWFILE_LOGIN_ITEM = /\A(?:[^#\n]|\#\{)*setup_login_items_script\}\\"\s+-a\s+'([^']+)'/.freeze

  # The apps the Brewfile registers as login items: the '-a' names of its active
  # 'setup_login_items_script' lines. The Brewfile is optional (it may be absent).
  #
  # @param brewfile [Pathname] The Brewfile to scan.
  # @return [Array<String>] Unique app names (case-insensitively), in first-seen order.
  def brewfile_app_names(brewfile: EnvVars::HOMEBREW_BUNDLE_FILE)
    names = brewfile.file? ? Core.read_lines_utf8(brewfile).map { |line| line[BREWFILE_LOGIN_ITEM, 1] }.compact : []
    names.uniq(&:downcase)
  end

  # Names of every app this repo may have registered as a login item: #brewfile_app_names plus
  # MacOS::LOGIN_ITEM_APPS (the single source of truth for the apps the preference scripts
  # restart). Only used where everything is to be cleared (--remove-managed, 'implode'); the
  # day-to-day paths (#register_managed, #unregister_removed) follow the Brewfile alone.
  #
  # @param brewfile [Pathname] The Brewfile to scan.
  # @return [Array<String>] Unique app names (case-insensitively), in first-seen order.
  def managed_app_names(brewfile: EnvVars::HOMEBREW_BUNDLE_FILE)
    (brewfile_app_names(brewfile: brewfile) + MacOS::LOGIN_ITEM_APPS).uniq(&:downcase)
  end

  # Where the Brewfile's login-item apps are remembered between runs, so an app dropped from the
  # Brewfile can be recognized later (the Brewfile no longer mentions it). Under the state
  # directory, because the cache directories are wiped.
  RECORD_FILE = EnvVars::XDG_STATE_HOME.join('dotfiles', 'login-item-apps').freeze

  # Registers the login item of every app the Brewfile lists, that is installed and has no login
  # item yet. 'brew bundle' only runs a cask's postinstall (which calls this script) when it
  # installs the cask, so after the login items were removed (implode, or by hand) a re-run would
  # never restore them for casks that are already installed. Quiet when nothing is missing: an app
  # that is already registered (including one still awaiting approval) is left alone without any
  # output, and an app that is not installed yet is skipped (its own postinstall registers it).
  #
  # @param brewfile [Pathname] The Brewfile to read.
  # @param record [Pathname] File remembering the Brewfile's apps (see RECORD_FILE).
  # @return [Boolean] true unless an installed app could not be registered
  def register_managed(brewfile: EnvVars::HOMEBREW_BUNDLE_FILE, record: RECORD_FILE)
    names = brewfile_app_names(brewfile: brewfile)
    _write_record(record, names) if brewfile.file?
    installed = names.select { |name| Core::ROOT.join('Applications', "#{name}.app").directory? }
    return true if installed.empty?

    _unregistered(installed).map { |name| run(app_name: name) }.all?
  end

  # Unregisters the login item of each app that the previous run saw in the Brewfile and the
  # Brewfile no longer lists -- one by one, never everything. Meant to run before the cleanup that
  # uninstalls such apps, while the app (needed to address its login item) is still there. The very
  # first run only learns the current apps, so nothing is removed on a machine without a record.
  #
  # @param brewfile [Pathname] The Brewfile to read.
  # @param record [Pathname] File remembering the Brewfile's apps (see RECORD_FILE).
  # @return [Boolean] true unless a login item of a dropped app could not be removed
  def unregister_removed(brewfile: EnvVars::HOMEBREW_BUNDLE_FILE, record: RECORD_FILE)
    return true unless brewfile.file?

    current = brewfile_app_names(brewfile: brewfile)
    kept = current.map(&:downcase)
    dropped = _read_record(record).reject { |name| kept.include?(name.downcase) }
    installed = dropped.select { |name| Core::ROOT.join('Applications', "#{name}.app").directory? }
    removed = installed.empty? ? true : remove(app_names: installed)
    # A dropped app whose login item could not be removed stays in the record for the next run.
    _write_record(record, removed ? current : current + installed)
    removed
  end

  # @param record [Pathname]
  # @return [Array<String>] The remembered app names (empty when there is no record yet).
  def _read_record(record)
    record.file? ? Core.read_lines_utf8(record).map(&:strip).reject(&:empty?) : []
  end

  # @param record [Pathname]
  # @param names [Array<String>]
  # @return [void]
  def _write_record(record, names)
    record.dirname.mkpath
    record.write(names.map { |name| "#{name}\n" }.join)
  end

  # Unregisters the login item of every app from #managed_app_names.
  #
  # @return [Boolean] true on success (including when there was nothing to remove)
  def remove_managed
    remove(app_names: managed_app_names)
  end

  # Unregisters the login items of +app_names+ using the same mechanism #run registered them with
  # (SMAppService on macOS 14-25, System Events otherwise). An app that is not installed, or whose
  # login item does not exist, is skipped: that is the state being asked for.
  #
  # @param app_names [Array<String>] Names of the applications (e.g., 'Clocker')
  # @return [Boolean] true unless an existing login item could not be removed
  def remove(app_names:)
    installed = app_names.select { |name| Core::ROOT.join('Applications', "#{name}.app").directory? }
    return true if installed.empty?

    macos_major = CommandUtils.query('sw_vers', '-productVersion').split('.').first.to_i
    if macos_major >= 14 && macos_major < 26
      _unregister_smappservice(installed.map { |name| Core::ROOT.join('Applications', "#{name}.app").to_s })
    else
      _unregister_legacy(installed)
    end
  end

  # The subset of +app_names+ (installed apps) that has no login item yet. When that cannot be
  # determined, every app is returned, which only costs the output #run prints for each.
  #
  # @param app_names [Array<String>] Names of installed applications.
  # @return [Array<String>]
  def _unregistered(app_names)
    macos_major = CommandUtils.query('sw_vers', '-productVersion').split('.').first.to_i
    if macos_major >= 14 && macos_major < 26
      _unregistered_smappservice(app_names)
    else
      items = CommandUtils.query(MacOS::OSASCRIPT_CMD, '-e', 'tell application "System Events" to get the name of every login item')
      existing = items.split(',').map { |item| item.strip.downcase }
      app_names.reject { |name| existing.any? { |item| item.include?(name.downcase) } }
    end
  end

  # SMAppService status of every app in ONE swift run (compiling the script is the slow part),
  # macOS 14-25 only. Enabled and awaiting-approval items count as registered.
  #
  # @param app_names [Array<String>]
  # @return [Array<String>] The names without a login item (all of them if swift failed).
  # :reek:UtilityFunction -- Stateless helper for SMAppService status lookup (intentional)
  def _unregistered_smappservice(app_names)
    swift_src = <<~'SWIFT'
      import Foundation
      import ServiceManagement

      guard let appPaths = ProcessInfo.processInfo.environment["APP_PATHS"] else {
        fputs("APP_PATHS env var not set\n", stderr)
        exit(1)
      }

      for appPath in appPaths.split(separator: "\n").map(String.init) {
        let service = SMAppService.loginItem(url: URL(fileURLWithPath: appPath))
        switch service.status {
        case .enabled, .requiresApproval:
          break
        default:
          print("missing \(appPath)")
        }
      }
    SWIFT

    paths = app_names.map { |name| Core::ROOT.join('Applications', "#{name}.app").to_s }
    env = ENV.to_h.merge('APP_PATHS' => paths.join("\n"))
    stdout, _stderr, status = Open3.capture3(env, 'swift', '-', stdin_data: swift_src)
    return app_names unless status.success?

    missing = stdout.lines.select { |line| line.start_with?('missing ') }.map { |line| line.delete_prefix('missing ').strip }
    app_names.select { |name| missing.include?(Core::ROOT.join('Applications', "#{name}.app").to_s) }
  end

  # Unregisters +app_paths+ via SMAppService.loginItem(url:) in ONE swift run (compiling the
  # script is the slow part), macOS 14-25 only. The paths travel in the environment, newline
  # separated, never spliced into the source.
  #
  # @param app_paths [Array<String>] Absolute paths to the .app bundles.
  # @return [Boolean] true if every registered item was unregistered.
  # :reek:UtilityFunction -- Stateless helper for SMAppService unregistration (intentional)
  def _unregister_smappservice(app_paths)
    swift_src = <<~'SWIFT'
      import Foundation
      import ServiceManagement

      guard let appPaths = ProcessInfo.processInfo.environment["APP_PATHS"] else {
        fputs("APP_PATHS env var not set\n", stderr)
        exit(1)
      }

      var failed = false
      for appPath in appPaths.split(separator: "\n").map(String.init) {
        let service = SMAppService.loginItem(url: URL(fileURLWithPath: appPath))
        switch service.status {
        case .enabled, .requiresApproval:
          do {
            try service.unregister()
            print("removed \(appPath)")
          } catch {
            fputs("SMAppService unregistration failed for \(appPath): \(error)\n", stderr)
            failed = true
          }
        default:
          // Not registered (or not found): already in the state we want.
          break
        }
      }
      exit(failed ? 1 : 0)
    SWIFT

    env = ENV.to_h.merge('APP_PATHS' => app_paths.join("\n"))
    stdout, stderr, status = Open3.capture3(env, 'swift', '-', stdin_data: swift_src)
    stdout.each_line do |line|
      Logging.info "Removed login item of '#{line.delete_prefix('removed ').strip.cyan}'" if line.start_with?('removed ')
    end
    Logging.record_warning("Failed to remove some login items via SMAppService#{"\n#{stderr}" unless stderr.empty?}") unless status.success?
    status.success?
  end

  # Removes the legacy System Events login items named like +app_names+ (exact match,
  # case-insensitive). Used on macOS 13 and earlier, and on macOS 26+.
  #
  # @param app_names [Array<String>] Names of the applications.
  # @return [Boolean] true if every existing item was removed.
  # :reek:UtilityFunction -- Stateless helper for legacy AppleScript removal (intentional)
  def _unregister_legacy(app_names)
    items_out = CommandUtils.query(MacOS::OSASCRIPT_CMD, '-e',
                                   'tell application "System Events" to get the name of every login item')
    existing = items_out.split(',').map(&:strip)
    wanted = app_names.map(&:downcase)
    existing.select { |item| wanted.include?(item.downcase) }.map do |item|
      removed = CommandUtils.run_silent(MacOS::OSASCRIPT_CMD, '-e',
                                        "tell application \"System Events\" to delete login item \"#{item}\"")
      Logging.info "Removed login item of '#{item.cyan}'" if removed
      Logging.record_warning("Failed to remove the login item of '#{item.cyan}' via System Events") unless removed
      removed
    end.all?
  end

  # Registers +app_path+ via SMAppService.loginItem(url:) -- macOS 14-25 only.
  # APP_PATH is passed via the environment rather than heredoc interpolation so
  # that paths containing spaces or special characters are handled safely.
  #
  # @param app_path [String] Absolute path to the .app bundle to register.
  # @return [Boolean] true if already registered or registration succeeded, false on failure.
  # :reek:UtilityFunction -- Stateless helper for SMAppService registration (intentional)
  def _register_smappservice(app_path)
    swift_src = <<~'SWIFT'
      import Foundation
      import ServiceManagement

      guard let appPath = ProcessInfo.processInfo.environment["APP_PATH"] else {
        fputs("APP_PATH env var not set\n", stderr)
        exit(1)
      }

      let service = SMAppService.loginItem(url: URL(fileURLWithPath: appPath))
      switch service.status {
      case .enabled, .requiresApproval:
        // Already registered (approved or awaiting approval) -- nothing to do.
        exit(0)
      default:
        do {
          try service.register()
        } catch {
          // register() can throw even when the item ends up registered -- this is a
          // known macOS behaviour on reinstall (stale prior entry in the SMAppService
          // database). Re-check the status before treating the exception as a failure.
          switch service.status {
          case .enabled, .requiresApproval:
            exit(0)
          default:
            fputs("SMAppService registration failed: \(error)\n", stderr)
            exit(1)
          }
        }
      }
    SWIFT

    env = ENV.to_h.merge('APP_PATH' => app_path)

    # Log compilation errors if swift fails
    CommandUtils.capture_output(env, 'swift', '-', stdin_data: swift_src, err: %i[child out]) do |st, output_msg|
      Logging.debug("Swift compilation failed (status: #{st&.exitstatus || 'unknown'})#{output_msg}")
    end
  end

  private_class_method :_register_smappservice, :_unregister_smappservice, :_unregister_legacy,
                       :_unregistered, :_unregistered_smappservice, :_read_record, :_write_record

  # Registers +app_path+ via the legacy System Events AppleScript.
  # +hidden+ controls whether the app launches without a Dock icon.
  # Skips silently when already registered.
  #
  # @param app_name [String] Name of the application (used to check existing login items).
  # @param app_path [String] Absolute path to the .app bundle to register.
  # @param hidden [String] AppleScript boolean literal ('true' or 'false') controlling Dock visibility at launch.
  # @return [Boolean] true if already registered or registration succeeded, false on failure.
  # :reek:UtilityFunction -- Stateless helper for legacy AppleScript registration (intentional)
  def _register_legacy(app_name, app_path, hidden)
    items_out = CommandUtils.query(MacOS::OSASCRIPT_CMD, '-e',
                                   'tell application "System Events" to get the name of every login item')
    already = items_out.split(',').any? { |i| i.strip.downcase.include?(app_name.downcase) }
    return true if already

    script = 'tell application "System Events" to make login item at end ' \
             "with properties {path:\"#{app_path}\", hidden:#{hidden}}"
    CommandUtils.run_silent(MacOS::OSASCRIPT_CMD, '-e', script)
  end

  private_class_method :_register_legacy
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = {}
  parser = CliParser.parse('[options]') do |opts|
    opts.separator 'Registers an app as a macOS login item.'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('-a', '--app APP', 'Name of the application to register as a login item') do |v|
      options[:app_name] = v
    end
    opts.on('--register-managed',
            'Register the login items of every installed app this repo manages (idempotent; the inverse of --remove-managed)') do
      options[:register_managed] = true
    end
    opts.on('--remove-managed',
            'Remove the login items of every app this repo registers (Brewfile entries and MacOS::LOGIN_ITEM_APPS)') do
      options[:remove_managed] = true
    end
    opts.on('-b', '--background',
            'Hidden/background mode: suppress Dock icon at launch ' \
            '(macOS 13 legacy path only; macOS 14+ apps control this via Info.plist)') do
      options[:background] = true
    end
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -a Clocker"
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -a Thaw -b"
    opts.separator "  eg: #{File.basename(__FILE__).cyan} --register-managed"
    opts.separator "  eg: #{File.basename(__FILE__).cyan} --remove-managed"
  end

  parser.abort_with_usage('Missing required option: -a <app-name>') if nil_or_empty?(options[:app_name]) && !options[:remove_managed] && !options[:register_managed]

  # Note: This script uses Logging.run_script instead of the manual
  # increment_script_depth + print_script_start + print_script_summary pattern.
  # This is a standalone utility (not called from fresh-install or other scripts),
  # so the simplified run_script wrapper is appropriate. If this script is later
  # integrated into a larger workflow, run_script automatically suppresses banners
  # when script_depth >= 1 (see logging.rb lines 464-471).
  Logging.run_script do
    success = if options[:register_managed]
                SetupLoginItem.register_managed
              elsif options[:remove_managed]
                SetupLoginItem.remove_managed
              else
                SetupLoginItem.run(app_name: options[:app_name], background: options[:background] || false)
              end
    exit(success ? 0 : 1)
  end
end
