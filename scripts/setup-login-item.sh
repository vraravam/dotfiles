#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# file location: $DOTFILES_DIR/scripts/setup-login-item.sh
#
# Registers an app as a macOS login item.
#
# On macOS 14+: uses SMAppService.loginItem(url:) via an inline Swift script.
#   Items appear under "Open at Login" in System Settings (not "Legacy").
#   First-time registration lands in "Requires Approval" state -- the user must
#   approve in System Settings > General > Login Items before the item is active.
#   Requires Xcode Command Line Tools (always present when Homebrew is installed).
#
# On macOS 13 and earlier: falls back to the legacy System Events AppleScript.
#   Items show as "Legacy" in System Settings on macOS 13+.
#
# The -b flag enables hidden/background mode (no Dock icon at launch).
#   macOS 13 and earlier: sets hidden:true in the legacy AppleScript call.
#   macOS 14+: background behaviour is determined by the app's own Info.plist
#   (LSUIElement/LSBackgroundOnly); -b emits a user_action hint instead.
#
# Usage: setup-login-item.sh [-h] -a <app-name> [-b]

set -euo pipefail

_SCRIPT_NAME="${0:t}"
# Re-source guard is inside .aliases itself -- safe to call unconditionally.
source "${HOME}/.aliases"

usage() {
  print_usage "${_SCRIPT_NAME}" \
    "$(yellow '-a') <app-name>  (mandatory) Application name to register as a login item" \
    "$(yellow '-b')             Hidden/background mode: suppress Dock icon at launch" \
    "                           (macOS 13 legacy path only; macOS 14+ apps control this via Info.plist)" \
    "$(yellow '-h')             Show this help"
}

# Registers the app at $1 via SMAppService.loginItem(url:) -- macOS 14+ only.
# APP_PATH is passed via environment rather than heredoc interpolation so that
# paths containing spaces or special characters are handled safely.
# Returns 0 if already registered or registration succeeded; 1 on failure.
_register_smappservice() {
  local app_path="${1}"
  APP_PATH="${app_path}" swift - <<'SWIFT' 2>/dev/null
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
}

# Registers the app at $2 via the legacy System Events AppleScript.
# $1 = app name (used for the already-registered idempotency check).
# $3 = hidden flag: "true" suppresses the Dock icon at launch.
# Skips silently when the app is already in the login items list.
_register_legacy() {
  local name="${1}" app_path="${2}" hidden="${3}"
  local all_login_items found
  all_login_items=$(osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null || true)
  found="${${(M)${(f)all_login_items}:#(#i)*${name}*}[1]}"
  if is_non_zero_string "${found}"; then
    return 0 # already registered
  fi
  osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"${app_path}\", hidden:${hidden}}" &>/dev/null
}

main() {
  local app_name=''
  local background='false'
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  trap '_decrement_script_depth' EXIT

  while getopts ":a:bh" opt; do
    case "${opt}" in
      a)
        app_name="${OPTARG}"
        ;;
      b)
        background='true'
        ;;
      h)
        usage
        return 0
        ;;
      :)
        warn "Option -${OPTARG} requires an argument."
        usage
        return 1
        ;;
      ?)
        warn "Unknown option: -${OPTARG}"
        usage
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if is_zero_string "${app_name}"; then
    warn 'Missing required argument: -a <app-name>'
    usage
    return 1
  fi

  local app_path="/Applications/${app_name}.app"
  if ! is_directory "${app_path}"; then
    info "Application '$(yellow "${app_path}")' not found -- skipping."
    print_script_summary
    return 0
  fi

  local version macos_major
  version=$(sw_vers -productVersion)
  macos_major="${version%%.*}"

  if [[ "${macos_major}" -ge 14 && "${macos_major}" -lt 26 ]]; then
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
    if _register_smappservice "${app_path}"; then
      success "Registered '$(purple "${app_name}")' as a login item (SMAppService)"
      user_action "Open System Settings > General > Login Items and approve '$(purple "${app_name}")' under 'Open at Login'."
      if [[ "${background}" == 'true' ]]; then
        user_action "'$(purple "${app_name}")': enable background/hidden mode via the app's own preferences or System Settings -- SMAppService does not expose a hidden-at-launch flag."
      fi
    else
      _record_warning "Failed to register '$(purple "${app_name}")' via SMAppService"
    fi
  else
    # macOS 13 and earlier: SMAppService.loginItem(url:) is macOS 14+ only.
    # The legacy System Events AppleScript is the only viable CLI option.
    # Items registered this way show as "Legacy" in System Settings on macOS 13.
    # hidden=true suppresses the Dock icon at launch (background/hidden mode).
    if _register_legacy "${app_name}" "${app_path}" "${background}"; then
      local mode_label='login item'
      if [[ "${background}" == 'true' ]]; then
        mode_label='login item (hidden/background mode)'
      fi
      success "Registered '$(purple "${app_name}")' as a ${mode_label} (legacy)"
    else
      _record_warning "Failed to register '$(purple "${app_name}")' via System Events"
    fi
  fi

  print_script_summary
}

main "$@"
