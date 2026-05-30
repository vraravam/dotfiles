#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script will find all git repositories within the specified 'FOLDER' (defaults to current dir) filtered by 'FILTER' (defaults to empty string; accepts regex) and for a minimum depth of 'MINDEPTH' (optional; defaults to 1) and a maximum depth of 'MAXDEPTH' (optional; defaults to 4); and then runs the specified commands in each of those git repos. This script is not limited to only running 'git' commands!

set -euo pipefail

source "${HOME}/.aliases"
_SCRIPT_NAME="${0:t}"

usage() {
  print_usage "${1}" \
    "$(yellow '<any-unix-command>') --> (mandatory) The command to run in each discovered git repo (not limited to git commands)" \
    "Environment variables (all optional):" \
    "  $(yellow 'FOLDER')   --> Root directory to search for git repos (default: current dir)" \
    "  $(yellow 'FILTER')   --> Regex to filter repos by folder or repo name (default: empty = all)" \
    "  $(yellow 'MINDEPTH') --> Minimum search depth (default: 1)" \
    "  $(yellow 'MAXDEPTH') --> Maximum search depth (default: 4)" \
    "   eg: $(cyan "FOLDER=dev MINDEPTH=2 ${1} git status")" \
    "   eg: $(cyan "FOLDER=dev MINDEPTH=2 ${1} git branch -vv")" \
    "   eg: $(cyan "FOLDER=dev MINDEPTH=2 ${1} ls -l")" \
    "   eg: $(cyan "FILTER=oss ${1} ls -l")" \
    "   eg: $(cyan "FILTER='oss|zsh|omz' ${1} git fo")"
}

main() {
  while getopts ":h:" opt; do
    case ${opt} in
      h)
        usage "${_SCRIPT_NAME}"
        ;;
      :)
        warn "-${OPTARG} requires an argument"
        usage "${_SCRIPT_NAME}"
        ;;
    esac
  done
  shift $((OPTIND - 1))

  # if there are no arguments, print usage and exit
  if [[ $# -eq 0 ]]; then
    warn "Missing required arguments/switches"
    usage "${_SCRIPT_NAME}"
  fi

  section_header "$(yellow 'Running commands in git repositories')"

  # script_start_time is passed explicitly to print_script_duration below.
  # This script does not call step_start/step_end so there is no need to push
  # onto SCRIPT_START_TIMES.  If step_start/step_end are ever added here,
  # this local must also be pushed onto SCRIPT_START_TIMES so step_end can
  # compute total elapsed correctly (see design note in .shellrc).
  local script_start_time
  script_start_time="${EPOCHSECONDS}"
  print_script_start

  local mindepth maxdepth folder filter
  mindepth="${MINDEPTH:-1}"
  maxdepth="${MAXDEPTH:-4}"
  folder="${FOLDER:-.}"
  filter="${FILTER:-}"
  local total_count count dir repo

  echo "$(yellow "Finding git repos starting in folder '$(cyan "${folder}")' for a min depth of $(cyan "${mindepth}") and max depth of $(cyan "${maxdepth}")")"
  [[ "${filter}" != '' ]] && echo "$(yellow "Filtering with: $(cyan "${filter}")")"

  # Find all .git directories; use :h modifier for dirname, assoc array for sort -u dedup.
  local -A _seen=()
  local -a dir_array=()
  while IFS= read -r git_dir; do
    local d="${git_dir:h}"
    [[ -n "${filter}" && ! "${d}" =~ ${filter} ]] && continue
    if ((!${+_seen[${d}]})); then
      _seen[${d}]=1
      dir_array+=("${d}")
    fi
  done < <(find "${folder}" -mindepth "${mindepth}" -maxdepth "${maxdepth}" -type d -name '.git' 2>/dev/null)

  total_count=${#dir_array[@]}

  # Track failures
  local -a failed_repos=()
  local -a successful_repos=()

  count=1
  for dir in "${dir_array[@]}"; do
    if is_directory "${dir}" && ! is_symbolic_link "${dir}"; then
      info "[${count} of ${total_count}] '$(yellow "$*")' in '$(cyan "${dir}")'"
      if (cd "${dir}" && eval "$@"); then
        successful_repos+=("${dir}")
      else
        failed_repos+=("${dir}")
        warn "Command failed in: $(red "${dir}")"
      fi
      ((count++))
    fi
  done

  # Report summary
  echo ""
  info "$(yellow 'Summary')"
  echo "  Total repositories: ${total_count}"
  echo "  Successful: $(green ${#successful_repos[@]})"
  if is_non_empty_array failed_repos; then
    echo "Failed: $(red ${#failed_repos[@]})"
    local -a display_repos=()
    for repo in "${failed_repos[@]}"; do display_repos+=("$(red "${repo}")"); done
    echo "$(red 'Failed repositories:')$(join_array display_repos)"
  fi

  print_script_duration "${script_start_time}"

  # Exit with error if any repos failed
  is_non_empty_array failed_repos && exit 1
  exit 0
}

main "$@"
