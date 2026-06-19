#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/setup-login-item.rb
#
# Registers an app as a macOS login item.
#
# On macOS 14–25: uses SMAppService.loginItem(url:) via an inline Swift script.
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
#   macOS 14–25: background behaviour is determined by the app's own Info.plist
#   (LSUIElement/LSBackgroundOnly); -b emits a user_action hint instead.
#
# Usage:
#   Standalone: setup-login-item.rb [-h] -a <app-name> [-b]
#   Module:     SetupLoginItem.run(app_name: 'App', background: false)

require 'open3'

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
  def run(app_name:, background: false)
    app_path_pn = Core::ROOT.join('Applications', "#{app_name}.app")

    unless app_path_pn.directory?
      Logging.info "Application '#{app_path_pn.to_s.cyan}' not found -- skipping login item setup."
      return true  # Not an error, just nothing to do
    end

    # Detect macOS major version to choose the registration path.
    sw_out, = Open3.capture3('sw_vers', '-productVersion')
    macos_major = sw_out.strip.split('.').first.to_i

    if macos_major >= 14 && macos_major < 26
      # macOS 14–25: SMAppService.loginItem(url:) registers the app as a proper
      # login item (appears under "Open at Login", not "Legacy" in System Settings).
      # First registration lands in .requiresApproval -- the user must approve in
      # System Settings > General > Login Items before the item is active.
      # The -b flag has no effect here: Dock visibility is determined by the app's
      # own Info.plist (LSUIElement/LSBackgroundOnly), not the registration call.
      # macOS 26 removed loginItem(url:) and replaced it with loginItem(identifier:)
      # which only works for login item helpers bundled WITHIN an app -- not for
      # registering standalone third-party apps externally. macOS 26+ falls through
      # to the legacy System Events path below.
      if _register_smappservice(app_path_pn.to_s)
        Logging.success "Registered '#{app_name.yellow}' as a login item (SMAppService)"
        Logging.user_action "Open System Settings > General > Login Items and approve '#{app_name.yellow}' under 'Open at Login'."
        if background
          Logging.user_action "'#{app_name.yellow}': enable background/hidden mode via the app's own preferences or System Settings -- SMAppService does not expose a hidden-at-launch flag."
        end
        true
      else
        Logging.record_warning("Failed to register '#{app_name.yellow}' via SMAppService")
        false
      end
    else
      # macOS 13 and earlier, and macOS 26+: use the legacy System Events AppleScript.
      # Items registered this way show as "Legacy" in System Settings on macOS 13.
      # hidden=true suppresses the Dock icon at launch (background/hidden mode).
      hidden_str = background ? 'true' : 'false'
      if _register_legacy(app_name, app_path_pn.to_s, hidden_str)
        mode_label = background ? 'login item (hidden/background mode)' : 'login item'
        Logging.success "Registered '#{app_name.yellow}' as a #{mode_label} (legacy)"
        true
      else
        Logging.record_warning("Failed to register '#{app_name.yellow}' via System Events")
        false
      end
    end
  end

  # Registers +app_path+ via SMAppService.loginItem(url:) -- macOS 14–25 only.
  # APP_PATH is passed via the environment rather than heredoc interpolation so
  # that paths containing spaces or special characters are handled safely.
  # Returns true if already registered or registration succeeded; false on failure.
  # Mirrors _register_smappservice in the shell version.
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
    out, err, status = Open3.capture3(env, 'swift', '-', stdin_data: swift_src,
                                                         err: [:child, :out])
    _ = out
    _ = err
    status.success?
  end

  private_class_method :_register_smappservice

  # Registers +app_path+ via the legacy System Events AppleScript.
  # +hidden+ controls whether the app launches without a Dock icon.
  # Skips silently when already registered.
  # Mirrors _register_legacy in the shell version.
  def _register_legacy(app_name, app_path, hidden)
    items_out, = Open3.capture3(MacOS::OSASCRIPT_CMD, '-e',
                                'tell application "System Events" to get the name of every login item')
    already = items_out.split(',').any? { |i| i.strip.downcase.include?(app_name.downcase) }
    return true if already

    script = "tell application \"System Events\" to make login item at end " \
             "with properties {path:\"#{app_path}\", hidden:#{hidden}}"
    system(MacOS::OSASCRIPT_CMD, '-e', script, out: File::NULL, err: File::NULL)
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
    opts.on('-b', '--background',
            'Hidden/background mode: suppress Dock icon at launch ' \
            '(macOS 13 legacy path only; macOS 14+ apps control this via Info.plist)') do
      options[:background] = true
    end
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -a Clocker"
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -a Thaw -b"
  end

  parser.abort_with_usage('Missing required option: -a <app-name>') if nil_or_empty?(options[:app_name])

  Logging.run_script(File.basename(__FILE__, '.rb')) do
    success = SetupLoginItem.run(app_name: options[:app_name], background: options[:background] || false)
    exit(success ? 0 : 1)
  end
end
