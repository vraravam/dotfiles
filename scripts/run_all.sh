#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script will find all git repositories within the specified 'FOLDER' (defaults to current dir) filtered by 'FILTER' (defaults to empty string; accepts regex) and for a minimum depth of 'MINDEPTH' (optional; defaults to 1) and a maximum depth of 'MAXDEPTH' (optional; defaults to 3); and then runs the specified commands in each of those git repos. This script is not limited to only running 'git' commands!

# Exit immediately if a command exits with a non-zero status.
set -e

# Source shell helpers if they aren't already loaded
type is_shellrc_sourced 2>&1 &> /dev/null || source "${HOME}/.shellrc"

usage() {
cat << EOF
$(red "** Usage **")
This script will find all git repositories within the specified 'FOLDER' (defaults to current dir) filtered by 'FILTER' (defaults to empty string; accepts regex) and for a minimum depth of 'MINDEPTH' (optional; defaults to 1) and a maximum depth of 'MAXDEPTH' (optional; defaults to 3); and then runs the specified commands in each of those git repos. This script is not limited to only running 'git' commands!

For eg:
FOLDER=dev MINDEPTH=2 run_all.sh git status
FOLDER=dev MINDEPTH=2 run_all.sh git branch -vv
FOLDER=dev MINDEPTH=2 run_all.sh ls -l
FILTER=oss run_all.sh ls -l
FILTER='oss|zsh|omz' run_all.sh git fo
EOF
  exit 1
}

while getopts ":h:" opt; do
  case ${opt} in
    h)
      usage "${0##*/}"
      ;;
    :)
      echo "Invalid option: -${OPTARG} requires an argument" 1>&2
      usage "${0##*/}"
      ;;
  esac
done
shift $((OPTIND - 1))

section_header 'Running commands in git repositories'

local script_start_time=$(date +%s)
print_script_start

MINDEPTH=${MINDEPTH:-1}
MAXDEPTH=${MAXDEPTH:-3}
FOLDER="${FOLDER:-.}"
FILTER="${FILTER:-}"

start_time=$(date +%s)

echo "$(yellow "Finding git repos starting in folder '$(cyan "${FOLDER}")' for a min depth of $(cyan "${MINDEPTH}") and max depth of $(cyan "${MAXDEPTH}")")"
[[ "${FILTER}" != '' ]] && echo "$(yellow "Filtering with: $(cyan "${FILTER}")")"

# Find all .git directories and store their parent directory
local dir_array=("${(@f)$(find "${FOLDER}" -mindepth "${MINDEPTH}" -maxdepth "${MAXDEPTH}" -type d -name '.git' -exec dirname {} \; 2>/dev/null | grep -iE "${FILTER}" | sort -u)}")

TOTAL_COUNT=${#dir_array[@]}

COUNT=1
for dir in "${dir_array[@]}"; do
  if is_directory "${dir}" && ! is_symbolic_link "${dir}"; then
    info "[${COUNT} of ${TOTAL_COUNT}] '$(yellow "$*")' in '$(cyan "${dir}")'"
    (cd "${dir}" && eval "$@")
    ((COUNT++))
  fi
done

print_script_duration "${script_start_time}"
