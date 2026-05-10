#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to run some commands at the end of the 'brew bundle' command. They are not inlined into the Brewfile due to the need to escape quoted strings.

# Exit immediately if a command exits with a non-zero status.
set -e

# Source helpers only once if any required function is missing
type is_shellrc_sourced &>/dev/null || source "${HOME}/.shellrc"

usage() {
  echo "$(red 'Usage'): $(yellow "${${(%):-%x}##*/}") -a <app-name>"
  echo "  $(yellow '-a <app-name>') --> (mandatory) The name of the application to setup as a login item"
  exit 1
}

main() {
  local app_name
  while getopts ":a:" opt; do
    case ${opt} in
      a)
        app_name="${OPTARG}"
        ;;
      \?)
        usage
        ;;
      :)
        echo "Invalid option: -${OPTARG} requires an argument" 1>&2
        usage
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if is_zero_string "${app_name}"; then
    usage
  fi

  local app_path="/Applications/${app_name}.app"
  if is_directory "${app_path}"; then
    local found
    found=$(osascript -e 'tell application "System Events" to get the name of every login item' | \grep -i "${app_name}" || true)
    if is_zero_string "${found}"; then
      osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"${app_path}\", hidden:false}" &>/dev/null  && success "Successfully setup '$(yellow "${app_name}")' as a login item" || warn "Failed to setup '$(yellow "${app_name}")' as a login item"
    fi
  else
    warn "Couldn't find application '$(yellow "${app_path}")' and so skipping setting up as a login item"
  fi
}

main "$@"
