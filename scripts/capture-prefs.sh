#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# file location: <anywhere; but advisable in the PATH>

# This script will export or import the settings from the location specified in the target directory defined down below. You can backup the files to any cloud storage and retrieve into the new laptop to then get back all settings as per the original machine. The only word of caution is to use it with the same OS version (I haven't tried in any situations where the old and new machines had different OS versions - so I cannot guarantee if that might break the system in any way)

# A utility function to find the name of the app:
# Run `find_and_append_prefs` and pass in a substring contained in the name of the preference that you want to add. This will automatically add it (if not already present) into the appropriate allowed-list file.
# Explanation: This runs the `defaults find` command and searches for any match, then it traces back to the left-most child (1st of the top-level parent) in the printed JSON to then get the real unique name of the app where its settings are stored and adds it to the file mentioned above.

set -euo pipefail

source "${HOME}/.shellrc"
_SCRIPT_NAME="${0:t}"

usage() {
  print_usage "${1}" \
    "$(yellow '-e') --> (mandatory; mutually exclusive with -i) Export preferences from the current [old] system into the dotfiles repo" \
    "$(yellow '-i') --> (mandatory; mutually exclusive with -e) Import preferences from the dotfiles repo into the current [new] system"
}

main() {
  local operation=''
  while getopts ":ei" opt; do
    case ${opt} in
      e)
        operation='export'
        ;;
      i)
        operation='import'
        ;;
      \?)
        warn "-${OPTARG} is not a valid option"
        usage "${_SCRIPT_NAME}"
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if is_zero_string "${operation}"; then
    warn "Missing required arguments/switches"
    usage "${_SCRIPT_NAME}"
  fi

  is_zero_string "${PERSONAL_CONFIGS_DIR}" && error "Required env var '$(yellow 'PERSONAL_CONFIGS_DIR')' is not defined."
  is_zero_string "${DOTFILES_DIR}" && error "Required env var '$(yellow 'DOTFILES_DIR')' is not defined."

  local target_dir="${PERSONAL_CONFIGS_DIR}/defaults"
  ensure_dir_exists "${target_dir}"

  if [[ "${operation}" == 'export' ]]; then
    # Clean up old files before exporting new ones (this also handles the case where some entry has been removed from the list of domains)
    # Use extglob-style brace expansion to also remove dot-prefixed files like .defaults
    # (*.defaults does not match .defaults in zsh/bash by default)
    rm -f "${target_dir}"/*.defaults "${target_dir}"/.defaults 2>/dev/null || true
  fi

  # Note: A simple trick to find these names is to run `\ls -1 ~/Library/Preferences/*` in the command-line
  # Read domains from the file into the array, splitting by newline and filtering comments/blanks
  # Define the location of the domains list
  local domains_file="${DOTFILES_DIR}/scripts/data/capture-prefs-allowed-list.txt"
  ! is_file "${domains_file}" && error "Domains list file not found: ${domains_file}"

  local denied_list_file="${DOTFILES_DIR}/scripts/data/capture-prefs-denied-list.txt"
  ! is_file "${denied_list_file}" && error "Denied list file not found: ${denied_list_file}"

  # Load denied list into an associative array for O(1) lookups.
  # while+read: no subprocess fork; =~ and ${//} skip comments and blanks.
  typeset -A _denied=()
  local _bl_line
  while IFS= read -r _bl_line; do
    [[ "${_bl_line}" =~ '^[[:space:]]*#' || -z "${_bl_line//[[:space:]]/}" ]] && continue
    _denied["${_bl_line}"]=1
  done <"${denied_list_file}"

  local -a app_array=()
  local _line
  # while+read replaces $("${(@f)$(grep -vE ...)}"): no grep subprocess fork.
  # =~ regex skips comment lines; ${_line//[[:space:]]/} detects blank lines.
  while IFS= read -r _line; do
    [[ "${_line}" =~ '^[[:space:]]*#' || -z "${_line//[[:space:]]/}" ]] && continue
    app_array+=("${_line}")
  done <"${domains_file}"
  if is_empty_array app_array; then
    warn "No domains found in '$(yellow "${domains_file}")'. Nothing to do."
    exit 0
  fi

  info "Running operation: $(green "${operation}")"
  local app_pref
  for app_pref in "${app_array[@]}"; do
    # Defensive guard: skip empty domain names (would produce a stale .defaults file)
    is_zero_string "${app_pref}" && continue
    # Skip domains on the denied list — they contain machine-specific or account-bound
    # data that is meaningless or harmful when exported/imported across machines.
    if ((${+_denied[${app_pref}]})); then
      warn "Skipping denied domain '$(yellow "${app_pref}")' — contains machine-specific data (see capture-prefs-denied-list.txt)"
      continue
    fi
    debug "Processing $(cyan "${app_pref}")"
    local target_file="${target_dir}/${app_pref}.defaults"
    # Allow the loop to continue even if a specific defaults command fails
    /usr/bin/defaults "${operation}" "${app_pref}" "${target_file}" || warn "Failed to ${operation} '${app_pref}'"
  done

  # If exporting, add the results to git staging
  # Run this *after* the loop finishes exporting all files.
  if [[ "${operation}" == 'export' ]]; then
    # Explicitly specify the git repo in the home folder, so that this script can be run from any folder
    git -C "${HOME}" add "${target_dir}" || warn "Failed to git add '${target_dir}'"
    success "Export complete. Staged changes in '$(cyan "${target_dir}")'."
  fi
  success "Operation finished. Processed $(cyan "${#app_array[@]}") domains (denied-list entries skipped with warnings)."
}

main "$@"
