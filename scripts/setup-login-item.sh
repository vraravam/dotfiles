#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to add an app as a macOS login item if not already present.

set -euo pipefail

source "${HOME}/.aliases"
_SCRIPT_NAME="${0:t}"

usage() {
  print_usage "${1}" \
    "$(yellow '-a <app-name>') --> (mandatory) The name of the application to setup as a login item"
}

main() {
  local app_name=''
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  while getopts ":a:" opt; do
    case ${opt} in
      a)
        app_name="${OPTARG}"
        ;;
      \?)
        warn "-${OPTARG} is not a valid option"
        usage "${_SCRIPT_NAME}"
        return 1
        ;;
      :)
        warn "-${OPTARG} requires an argument"
        usage "${_SCRIPT_NAME}"
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if is_zero_string "${app_name}"; then
    warn 'Missing required arguments/switches'
    usage "${_SCRIPT_NAME}"
    return 1
  fi

  local app_path="/Applications/${app_name}.app"
  if is_directory "${app_path}"; then
    local found
    local all_login_items
    all_login_items=$(osascript -e 'tell application "System Events" to get the name of every login item')
    found="${${(M)${(f)all_login_items}:#(#i)*${app_name}*}[1]}"
    if is_zero_string "${found}"; then
      osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"${app_path}\", hidden:false}" &>/dev/null &&
           success "Successfully setup '$(yellow "${app_name}")' as a login item" ||
           _record_warning "Failed to setup '$(yellow "${app_name}")' as a login item"
    fi
  else
    info "Couldn't find application '$(yellow "${app_path}")' — skipping login item setup."
  fi
  print_script_summary "${_SCRIPT_NAME}"
}

main "$@"
