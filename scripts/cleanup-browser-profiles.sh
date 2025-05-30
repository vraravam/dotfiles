#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to cleanup browser profiles folders (delete cache, session and other files that will anyways be recreated when you restart that browser). It can be safely invoked even if that browser is running (in which case it will skip processing after printing a warning to quit that application)

# Exit immediately if a command exits with a non-zero status.
set -e

# Source shellrc only once if any required function is missing
# Check for one key function defined in .shellrc to see if sourcing is needed
type is_file &> /dev/null 2>&1 || source "${HOME}/.shellrc"

vacuum_browser_profile_folder() {
  local browser_name="${1}"   # Passed browser name
  local profile_folder="${2}" # Profile folder path
  local num_cores="${3}"      # Number of CPU cores for parallel tasks

  if pgrep -q "${browser_name}"; then
    warn "Shutdown '$(yellow "${browser_name}")' first!; skipping processing of files for ${browser_name}"
    return
  fi

  ! is_directory "${profile_folder}" && warn "skipping processing of '$(yellow "${profile_folder}")' since it doesn't exist" && return

  section_header "Vacuuming '${browser_name}' in '${profile_folder}'..."
  echo "--> Size before: $(folder_size "${profile_folder}")"

  if command_exists sqlite3; then
    # Use xargs to run sqlite3 vacuum/reindex in parallel, passing multiple files to each zsh instance
    local vacuum_failed=0
    find "${profile_folder}" -type f -iname '*.sqlite' -print0 | xargs -0 -P "${num_cores}" zsh -c '
      setopt local_options errexit # Exit subshell if sqlite3 fails
      local exit_code=0
      for db_file do
        echo "Vacuuming: ${db_file}" # Add some progress indication
        sqlite3 "$db_file" "PRAGMA journal_mode=WAL; VACUUM; REINDEX;" || { exit_code=$?; warn "sqlite3 failed (code: $exit_code) for '\''$db_file'\''"; }
        # If we want the main script to know about failures, we need a way to communicate back
        # For now, errexit in subshell + overall check below is okay
      done
    ' _ || vacuum_failed=1 # Capture if any xargs command failed; use '_' as $0 placeholder

    if [[ $vacuum_failed -ne 0 ]]; then
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
  if [[ $has_conditions -eq 1 ]]; then
      combined_find_cmd+=('-delete')
      echo "Deleting files and directories matching patterns..."
      if ! "${combined_find_cmd[@]}"; then warn "Combined find/delete operation failed (code: $?) in '${profile_folder}'."; fi
  fi

  echo "--> Size after: $(folder_size "${profile_folder}")"
  success "Successfully processed profile folder for '$(yellow "${browser_name}")'"
}

# Record start time
local start_time_seconds=$(date +%s)
echo "Script started at: $(date '+%Y-%m-%d %H:%M:%S')"

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

# Determine number of CPU cores for parallelism once
local num_cores
num_cores=$(sysctl -n hw.ncpu 2>/dev/null) || num_cores=4 # Default to 4 if detection fails
[[ ! "${num_cores}" =~ ^[0-9]+$ || "${num_cores}" -eq 0 ]] && num_cores=4 # Ensure it's a positive integer

# Define browsers and their profile folders
# Key: Browser name (used for process check)
# Value: Absolute path to the profile folder
typeset -A browser_profiles
browser_profiles=(
  # TODO: Uncomment Arc/Chrome if testing confirms safety
  # arc         "${PERSONAL_PROFILES_DIR}/ArcProfile"
  brave       "${PERSONAL_PROFILES_DIR}/BraveProfile"
  # chrome      "${PERSONAL_PROFILES_DIR}/ChromeProfile"
  firefox     "${PERSONAL_PROFILES_DIR}/FirefoxProfile"
  thunderbird "${PERSONAL_PROFILES_DIR}/ThunderbirdProfile"
  zen         "${PERSONAL_PROFILES_DIR}/ZenProfile"
)

# Loop through defined browsers and process them
local browser_name profile_folder
for browser_name profile_folder in "${(@kv)browser_profiles}"; do
  vacuum_browser_profile_folder "${browser_name}" "${profile_folder}" "${num_cores}"
done

# Record end time and calculate duration
local end_time_seconds end_time_human duration duration_human
end_time_seconds=$(date +%s)
end_time_human=$(date '+%Y-%m-%d %H:%M:%S')
duration=$((end_time_seconds - start_time_seconds))

# Simple duration formatting (you could make this fancier if needed)
duration_human=$(printf '%02dh:%02dm:%02ds' $((duration/3600)) $((duration%3600/60)) $((duration%60)))

echo "Script finished at: ${end_time_human}. Total duration: ${duration_human} (${duration} seconds)."
