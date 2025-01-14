#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to cleanup browser profiles folders (delete cache, session and other files that will anyways be recreated when you restart that browser). It can be safely invoked even if that browser is running (in which case it will skip processing after printing a warning to quit that application)

type is_non_zero_string &> /dev/null 2>&1 || source "${HOME}/.shellrc"

check_app() {
  if is_non_zero_string "$(pgrep "${1}")"; then
    warn "Shutdown '${1}' first!; skipping processing of files for ${1}"
    return 1
  else
    return 0
  fi
}

find_and_destroy() {
  find "${1}" -type "${2}" -iname "${3}" -delete
}

vacuum_browser_profile_folder() {
  local profile_folder="${2}"
  ! is_directory "${profile_folder}" && warn "skipping processing of '${profile_folder}' since it doesn't exist" && return

  section_header "Vacuuming '${1}' in '${profile_folder}'..."
  echo "--> Size before: $(folder_size "${profile_folder}")"

  command_exists sqlite && find "${profile_folder}" -type f -iname '*.sqlite' -exec sqlite3 -line {} "VACUUM; REINDEX;" \;

  file_array=(
    '.DS_Store'
    '.localized'
    '.parentlock'
    '*.log'
    '*.sqlite-shm'
    '*.sqlite-wal'
    '*.bak*'
    'compatibility.ini'
    'extensions.rdf'
    'msgFilterRules.dat'
    'popstate.dat'
    'sessionstore.bak'
    'signons*.txt'
    '*healthreport*'
    'global-messages-db.sqlite'
  )
  for file in "${file_array[@]}"; do
    find_and_destroy "${profile_folder}" 'f' "${file}"
  done
  unset file
  unset file_array

  directory_array=(
    'ABphotos'
    'bookmarkbackups'
    'sessionstore-backups'
    'GoogleContacts'
    "Local\ Folders"
    'lnubackups'
    'minidumps'
    'SDThumbs'
    "smart\ mailboxes"
    'startupCache'
    'thumbnails'
    '*telemetry*'
    'weave'
    'crashes'
    '*healthreport*'
  )
  for directory in "${directory_array[@]}"; do
    find_and_destroy "${profile_folder}" 'd' "${directory}"
  done
  unset directory
  unset directory_array

  echo "--> Size after: $(folder_size "${profile_folder}")"
  success "Successfully processed profile folder for '${1}'"
  unset profile_folder
}

process_browser() {
  check_app "${1}" && vacuum_browser_profile_folder "$@"
}

# TODO: Commented out since I am moving away from Arc and will delete that folder completely
# process_browser arc "${PERSONAL_PROFILES_DIR}/ArcProfile"
process_browser brave "${PERSONAL_PROFILES_DIR}/BraveProfile"
# TODO: Commented out since I haven't tested that this works without losing auto-recreated data
# process_browser chrome "${PERSONAL_PROFILES_DIR}/ChromeProfile"
process_browser firefox "${PERSONAL_PROFILES_DIR}/FirefoxProfile"
process_browser thunderbird "${PERSONAL_PROFILES_DIR}/ThunderbirdProfile"
process_browser zen "${PERSONAL_PROFILES_DIR}/ZenProfile"
