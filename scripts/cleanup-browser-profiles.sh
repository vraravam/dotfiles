#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to cleanup browser profiles folders (delete cache, session and other files that will anyways be recreated when you restart that browser). It can be safely invoked even if that browser is running (in which case it will skip processing after printing a warning to quit that application)

# Exit immediately if a command exits with a non-zero status.
set -e

# Source shellrc only once if any required function is missing
# Check for one key function defined in .shellrc to see if sourcing is needed
type is_shellrc_sourced 2>&1 &> /dev/null || source "${HOME}/.shellrc"

local script_start_time=$(date +%s)
print_script_start

vacuum_browser_profile_folder() {
  local browser_name="${1}"   # Passed browser name
  local profile_folder="${2}" # Profile folder path

  if pgrep -i -f -q "${browser_name}"; then
    warn "Shutdown '$(yellow "${browser_name}")' first!; skipping processing of files for ${browser_name}"
    return 0 # Success, nothing to do
  fi

  if ! is_directory "${profile_folder}"; then
    warn "skipping processing of '$(yellow "${profile_folder}")' since it doesn't exist"
    return 0 # Success, nothing to do
  fi

  section_header "$(yellow 'Vacuuming') '$(purple "${browser_name}")' in '$(yellow "${profile_folder}")'..."
  echo "--> Size before: $(folder_size "${profile_folder}")"

  if command_exists sqlite3; then
    local vacuum_failed=0
    while IFS= read -r -d '' db_file; do
      echo "Vacuuming: ${db_file}" # Add some progress indication
      if ! sqlite3 "${db_file}" 'PRAGMA journal_mode=WAL; VACUUM; REINDEX;'; then
        warn "sqlite3 failed for '${db_file}'"
        vacuum_failed=1
      fi
    done < <(find "${profile_folder}" -type f -iname '*.sqlite' -print0)

    if [[ ${vacuum_failed} -ne 0 ]]; then
      warn "One or more sqlite vacuum/reindex operations failed in ${profile_folder}"
    fi
  fi

  # --- Combined Deletion Logic ---
  # Build find arguments for files
  local file_find_args=()
  if [[ ${#file_patterns[@]} -gt 0 ]]; then
    for pattern in "${file_patterns[@]}"; do
      [[ ${#file_find_args[@]} -gt 0 ]] && file_find_args+=('-o')
      file_find_args+=('-iname' "${pattern}")
    done
  fi

  # Build find arguments for directories
  local dir_find_args=()
  if [[ ${#dir_patterns[@]} -gt 0 ]]; then
    for pattern in "${dir_patterns[@]}"; do
      [[ ${#dir_find_args[@]} -gt 0 ]] && dir_find_args+=('-o')
      dir_find_args+=('-iname' "${pattern}")
    done
  fi

  # Construct and execute the combined find command if patterns exist
  local combined_find_cmd=('find' "${profile_folder}" '-mindepth' '1')
  local has_conditions=0 # Flag to track if any conditions were added

  if [[ ${#file_find_args[@]} -gt 0 ]]; then
    combined_find_cmd+=('\(' '-type' 'f' '\(' "${file_find_args[@]}" '\)' '\)')
    has_conditions=1
  fi
  if [[ ${#dir_find_args[@]} -gt 0 ]]; then
    # Add '-o' separator if file conditions were already added
    [[ $has_conditions -eq 1 ]] && combined_find_cmd+=('-o')
    combined_find_cmd+=('\(' '-type' 'd' '-depth' '\(' "${dir_find_args[@]}" '\)' '\)')
    has_conditions=1 # Ensure flag is set even if only dir patterns exist
  fi

  # Add -delete action and execute only if conditions were specified
  if [[ ${has_conditions} -eq 1 ]]; then
      combined_find_cmd+=('-delete')
      echo 'Deleting files and directories matching patterns...'
      if ! "${combined_find_cmd[@]}"; then warn "Combined find/delete operation failed (code: $?) in '${profile_folder}'."; fi
  fi

  echo "--> Size after: $(folder_size "${profile_folder}")"
  success "Successfully processed profile folder for '$(yellow "${browser_name}")'"
}

# Pre-read patterns from files
local -a file_patterns dir_patterns
local file_patterns_file="${DOTFILES_DIR}/scripts/data/cleanup-browser-files.txt"
local dir_patterns_file="${DOTFILES_DIR}/scripts/data/cleanup-browser-dirs.txt"

if is_file "${file_patterns_file}"; then
  file_patterns=("${(@f)$(grep -vE '^\s*#|^\s*$' "${file_patterns_file}")}") || warn "Failed to read file patterns from '${file_patterns_file}'"
else
  warn "File patterns file not found: '${file_patterns_file}'"
fi

if is_file "${dir_patterns_file}"; then
  dir_patterns=("${(@f)$(grep -vE '^\s*#|^\s*$' "${dir_patterns_file}")}") || warn "Failed to read directory patterns from '${dir_patterns_file}'"
else
  warn "Directory patterns file not found: '${dir_patterns_file}'"
fi

# Define browsers and their profile folders
# Key: Browser name (used for process check)
# Value: Absolute path to the profile folder
typeset -A browser_profiles
browser_profiles=(
  brave       "${PERSONAL_PROFILES_DIR}/BraveProfile"
  chrome      "${PERSONAL_PROFILES_DIR}/ChromeProfile"
  firefox     "${PERSONAL_PROFILES_DIR}/FirefoxProfile"
  thunderbird "${PERSONAL_PROFILES_DIR}/ThunderbirdProfile"
  zen         "${PERSONAL_PROFILES_DIR}/ZenProfile"
)

# Loop through defined browsers and process them
local browser_name profile_folder
for browser_name profile_folder in "${(@kv)browser_profiles}"; do
  vacuum_browser_profile_folder "${browser_name}" "${profile_folder}"
done

print_script_duration "${script_start_time}"
