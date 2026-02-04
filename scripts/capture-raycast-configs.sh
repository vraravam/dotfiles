#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# file location: <anywhere; but advisable in the PATH>

# This script will export/import the raycast configs to/from the location specified in the target directory.
# Reference for keystrokes/keycodes: https://eastmanreference.com/complete-list-of-applescript-key-codes

# Exit immediately if a command exits with a non-zero status.
set -e

# Source shellrc only once if any required function is missing
type is_shellrc_sourced 2>&1 &> /dev/null || source "${HOME}/.shellrc"

usage() {
  echo "$(red "Usage"): $(yellow "${1}") -e|-i <target-dir-location>"
  echo "  $(yellow '-e <target-dir-location>')  --> Export from [old] system"
  echo "  $(yellow '-i <target-dir-location>')  --> Import into [new] system"
  exit 1
}

local operation
local target_dir

while getopts ":e:i:" opt; do
  case ${opt} in
    e)
      operation='export'
      target_dir="${OPTARG}"
      ;;
    i)
      operation='import'
      target_dir="${OPTARG}"
      ;;
    \?)
      usage "${0##*/}"
      ;;
    :)
      echo "Invalid option: -${OPTARG} requires an argument" 1>&2
      usage "${0##*/}"
      ;;
  esac
done
shift $((OPTIND - 1))

if is_zero_string "${operation}" || is_zero_string "${target_dir}"; then
  usage "${0##*/}"
fi

local target_file="${target_dir}/Raycast.rayconfig"
ensure_dir_exists "${target_dir}"

is_zero_string "${RAYCAST_SETTINGS_PASSWORD}" && error "Cannot proceed without the 'RAYCAST_SETTINGS_PASSWORD' env var set; Aborting!!!"

warn 'This script uses osascript to enter your Raycast password. This is not secure. Please be aware of the risk.'

case "${operation}" in
  'export')
    is_file "${target_dir}/Raycast.rayconfig" && rm -rf "${target_dir}/Raycast.rayconfig"

    open raycast://extensions/raycast/raycast/export-settings-data

    osascript << EOF
      tell application 'System Events'
        key code 36
        delay 0.3

        if (static text 'Enter password' of window 1 of application process 'Raycast') exists then
          keystroke "${RAYCAST_SETTINGS_PASSWORD}"
          delay 0.3

          key code 36
          delay 0.3

          keystroke "${RAYCAST_SETTINGS_PASSWORD}"
          delay 0.3

          key code 36
          delay 0.3
        end if

        key code 5 using {command down, shift down}
        delay 0.3

        keystroke "${target_dir}"
        delay 0.3

        key code 36
        delay 0.3

        key code 36
        delay 0.5

        key code 53
      end tell
EOF

    mv "${target_dir}"/Raycast*.rayconfig "${target_file}"
    success "Successfully exported raycast configs to: $(yellow "${target_file}")"
    ;;
  'import')
    ! is_file "${target_file}" && error "Couldn't find file: '$(yellow "${target_file}")' for import operation; Aborting!!!"

    open raycast://extensions/raycast/raycast/import-settings-data

    osascript << EOF
      tell application 'System Events'
        key code 36
        delay 0.3

        key code 5 using {command down, shift down}
        delay 0.3

        keystroke "${target_dir}/Raycast.rayconfig"
        delay 0.3

        key code 36
        delay 0.5

        key code 36
        delay 0.3

        keystroke "${RAYCAST_SETTINGS_PASSWORD}"
        key code 36
        delay 0.3

        key code 36
        delay 0.3

        key code 36
        delay 2

        key code 53
        key code 53
      end tell
EOF

    success "Successfully imported raycast configs from: $(yellow "${target_file}")"
    ;;
esac
