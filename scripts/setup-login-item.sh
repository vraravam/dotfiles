#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to run some commands at the end of the 'brew bundle' command. They are not inlined into the Brewfile due to the need to escape quoted strings.
# Do not exit immediately if a command exits with a non-zero status since this is run within a cronjob

# Source helpers only once if any required function is missing
type is_directory &> /dev/null 2>&1 || source "${HOME}/.shellrc"

local app_path="/Applications/${1}.app"
if is_directory "${app_path}"; then
  local found=$(osascript -e 'tell application "System Events" to get the name of every login item' | \grep -i "${1}")
  if ! is_non_zero_string "${found}"; then
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"${app_path}\", hidden:false}" 2>&1 > /dev/null
    success "Successfully setup '$(yellow "${1}")' as a login item"
  fi
  unset found
else
  warn "Couldn't find application '$(yellow "${app_path}")' and so skipping setting up as a login item"
fi
unset app_path
