#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# file location: <anywhere; but advisable in the PATH>

# This script will export or import the settings from the location specified in the target directory defined down below. You can backup the files to any cloud storage and retrieve into the new laptop to then get back all settings as per the original machine. The only word of caution is to use it with the same OS version (I haven't tried in any situations where the old and new machines had different OS versions - so I cannot guarantee if that might break the system in any way)

# A trick to find the name of the app:
# Run `defaults read` in an empty window of a terminal app, then use the search functionality to search for a known word related to that app (like eg app visible name, author, some setting that's unique to that app, etc). Once you find this, trace back to the left-most child (1st of the top-level parent) in the printed JSON to then get the real unique name of the app where its settings are stored. Please note that one app might have multiple such groups / names at the top-level (for eg zoom). If this is the case, you will need to capture each name individually.

# Check for one key function defined in .shellrc to see if sourcing is needed
if ! type red &> /dev/null 2>&1 || ! type is_non_zero_string &> /dev/null 2>&1; then
  source "${HOME}/.shellrc"
fi

usage() {
  echo "$(red 'Usage'): $(yellow "${1} <e/i>")"
  echo "  $(yellow 'e')  --> Export from [old] system"
  echo "  $(yellow 'i')  --> Import into [new] system"
  exit 1
}

[ $# -ne 1 ] && usage "${0}"

# Exit immediately if a command exits with a non-zero status.
set -e

! is_non_zero_string "${PERSONAL_CONFIGS_DIR}" && error "Required env var '$(yellow 'PERSONAL_CONFIGS_DIR')' is not defined."
! is_non_zero_string "${DOTFILES_DIR}" && error "Required env var '$(yellow 'DOTFILES_DIR')' is not defined."

local target_dir="${PERSONAL_CONFIGS_DIR}/defaults"
ensure_dir_exists "${target_dir}"

local operation # Declare as local before assignment
case "${1}" in
  "e" )
    operation='export'
    # Clean up old files before exporting new ones (this also handles the case where some entry has been removed from the list of domains)
    rm -f "${target_dir}"/*.defaults || true
    ;;
  "i" )
    operation='import'
    # No cleanup needed for import
    ;;
  * )
    echo "Unknown value entered: '${1}'"
    usage "${0}"
    ;;
esac

# Note: A simple trick to find these names is to run `\ls -1 ~/Library/Preferences/*` in the command-line
# Read domains from the file into the array, splitting by newline and filtering comments/blanks
# Define the location of the domains list
local domains_file="${DOTFILES_DIR}/scripts/data/capture-prefs-domains.txt"
! is_file "${domains_file}" && error "Domains list file not found: ${domains_file}"

local app_array=("${(@f)$(grep -vE '^\s*#|^\s*$' "${domains_file}")}")
if [[ ${#app_array[@]} -eq 0 ]]; then
  warn "No domains found in ${domains_file}. Nothing to do."
  exit 0
fi

echo "Running operation: $(green "${operation}")"
for app_pref in "${app_array[@]}"; do # Declare loop variable as local directly
  echo "Processing $(cyan "${app_pref}")"
  local target_file="${target_dir}/${app_pref}.defaults"
  # Allow the loop to continue even if a specific defaults command fails
  /usr/bin/defaults "${operation}" "${app_pref}" "${target_file}" || warn "Failed to ${operation} '${app_pref}'"
done
unset app_pref

# If exporting, add the results to git staging
# Run this *after* the loop finishes exporting all files.
if [[ "${operation}" == "export" ]]; then
  # Explicitly specify the git repo in the home folder, so that this script can be run from any folder
  git -C "${HOME}" add "${target_dir}" || warn "Failed to git add '${target_dir}'"
  echo "$(green 'Export complete.') Staged changes in '${target_dir}'."
fi
echo "$(green 'Operation finished.') Processed ${#app_array[@]} domains."
