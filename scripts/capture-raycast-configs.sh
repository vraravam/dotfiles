#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# file location: <anywhere; but advisable in the PATH>

# This script will export/import the raycast configs to/from the location specified in the target directory.
# Reference for keystrokes/keycodes: https://eastmanreference.com/complete-list-of-applescript-key-codes

# Exit immediately if a command exits with a non-zero status.
set -e

# Source shellrc only once if any required function is missing
if ! type red 2>&1 &> /dev/null || ! type yellow 2>&1 &> /dev/null || ! type ensure_dir_exists 2>&1 &> /dev/null || ! type is_file 2>&1 &> /dev/null || ! type error 2>&1 &> /dev/null || ! type success 2>&1 &> /dev/null || ! type is_non_zero_string 2>&1 &> /dev/null; then
  source "${HOME}/.shellrc"
fi

usage() {
  echo "$(red "Usage"): $(yellow "${1} -<e/i> <target-dir-location>")"
  echo "  $(yellow '-e')  --> Export from [old] system"
  echo "  $(yellow '-i')  --> Import into [new] system"
  echo "  $(yellow 'target-dir-location') --> Directory name where the config has to be exported to/imported from"
  exit 1
}

[ $# -ne 2 ] && usage "${0}"

local target_dir="${2}"
local target_file="${target_dir}/Raycast.rayconfig"
ensure_dir_exists "${target_dir}"

! is_non_zero_string "${RAYCAST_SETTINGS_PASSWORD}" && error "Cannot proceed without the 'RAYCAST_SETTINGS_PASSWORD' env var set; Aborting!!!"

warn "This script uses osascript to enter your Raycast password. This is not secure. Please be aware of the risk."

case "${1}" in
  "-e")
    is_file "${target_dir}/Raycast.rayconfig" && rm -rf "${target_dir}/Raycast.rayconfig"

    open raycast://extensions/raycast/raycast/export-settings-data

    osascript << EOF
      tell application "System Events"
        key code 36
        delay 0.3

        if (static text "Enter password" of window 1 of application process "Raycast") exists then
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
  "-i")
    ! is_file "${target_file}" && error "Couldn't find file: '$(yellow "${target_file}")' for import operation; Aborting!!!"

    open raycast://extensions/raycast/raycast/import-settings-data

    osascript << EOF
      tell application "System Events"
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
  *)
    echo "$(red 'Unknown value entered') for first argument: '${1}'"
    usage "${0}"
    ;;
esac

unset target_dir
unset target_file
