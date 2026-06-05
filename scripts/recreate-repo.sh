#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to recreate the git repos in the home and profiles folders. This is useful to remove dangling & orphaned commits from the remote git repo so that fresh cloning is fast.
# It assumes that a pre-existing repo on local is present - so that it can capture the relevant remote details.
# It will force removal of history if the `-f` flag is given. (The history of the profiles repo will always get deleted).

set -euo pipefail

_SCRIPT_NAME="${0:t}"
source "${HOME}/.aliases"

usage() {
  print_usage "${_SCRIPT_NAME}" \
    "$(yellow '-f')               --> (optional) force squashing into a single commit (profiles repo will automatically/always be forced anyways)" \
    "$(yellow '-d <repo-folder>') --> (mandatory) The folder which has to be processed" \
    "   eg: $(cyan "-f -d \${HOME}")                (will push to $(yellow "$(build_keybase_repo_url "${KEYBASE_HOME_REPO_NAME}")"))" \
    "   eg: $(cyan "-d \${PERSONAL_PROFILES_DIR}")  (will push to $(yellow "$(build_keybase_repo_url "${KEYBASE_PROFILES_REPO_NAME}")"))"
}

_is_keybase_repo() {
  # == glob is faster than =~ (no regex engine); no capture groups needed.
  [[ "${1:-}" == *keybase* ]]
}

# Trap handler: on any exit, restore cron from backup if _DOTFILES_CRON_BACKUP_FILE is present.
# On the success path, _DOTFILES_CRON_BACKUP_FILE is removed before recron runs, so resume_cron becomes a no-op here.
# On the failure path, resume_cron restores from the backup saved by suspend_cron.
_cleanup_recreate() {
  local exit_code=$?
  [[ ${exit_code} -ne 0 ]] && warn "Script exited with error code ${exit_code}."
  resume_cron
  _decrement_script_depth
}

main() {
  local force=N
  local folder=''
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  # Minimal trap ensures depth is restored on early-return paths (arg-parse
  # failures, missing folder) before suspend_cron and the full EXIT trap run.
  # _cleanup_recreate (registered below) replaces this and calls
  # _decrement_script_depth itself, so depth is decremented exactly once.
  trap '_decrement_script_depth' EXIT
  while getopts ":fd:" opt; do
    case ${opt} in
      f)
        force=Y
        ;;
      d)
        folder="${OPTARG}"
        ;;
      \?)
        warn "-${OPTARG} is not a valid option"
        usage
        return 1
        ;;
      :)
        warn "-${OPTARG} requires an argument"
        usage
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if is_zero_string "${folder}"; then
    warn 'Missing required arguments/switches'
    usage
    return 1
  fi

  folder="$(strip_trailing_slash "${folder}")"

  # if/fi avoids the && pattern where A returning false (folder IS the profiles
  # repo, the common case) propagates a non-zero exit under set -e.
  if [[ "$(extract_last_segment "${folder}")" == "${KEYBASE_PROFILES_REPO_NAME}" ]]; then force=Y; fi

  if ! is_git_repo "${folder}"; then
    error "'${folder}' is not a git repo. Please specify the root of a git repo to proceed. Aborting!!!"
    return 1
  fi

  section_header "$(yellow 'Processing folder'): '$(cyan "${folder}")'"
  info "$(yellow 'Squash commits (will lose history!)'): '$(cyan "${force}")'"

  # Suspend cron while this script is running. with_cron_suspended is not used
  # here because _cleanup_recreate (the EXIT trap) also logs the exit code —
  # the wrapper's standard 'trap resume_cron EXIT' cannot substitute for that.
  # The trap restores cron on failure; recron regenerates it on success.
  suspend_cron
  trap _cleanup_recreate EXIT

  # Capture information from pre-existing git repo
  local git_url
  local git_user_name
  local git_user_email
  local git_branch_name
  git_url="$(get_git_config_value remote.origin.url "${folder}")"
  git_user_name="$(get_git_config_value user.name "${folder}")"
  git_user_email="$(get_git_config_value user.email "${folder}")"
  git_branch_name="$(git -C "${folder}" branch --show-current)"

  info "$(yellow 'Repo url'): '$(cyan "${git_url}")'"
  info "$(yellow 'User name'): '$(cyan "${git_user_name}")'"
  info "$(yellow 'User email'): '$(cyan "${git_user_email}")'"
  info "$(yellow 'Branch'): '$(cyan "${git_branch_name}")'"

  if is_zero_string "${git_url}" || is_zero_string "${git_user_name}" || is_zero_string "${git_user_email}" || is_zero_string "${git_branch_name}"; then
    error "One or more required git metadata values are missing for '$(yellow "${folder}")' — see above"
    return 1
  fi

  # Before deleting the current git information, ensure that keybase is installed and logged
  # in (if the remote url is a keybase url). This avoids a scenario where we delete the git
  # history and then fail to push to the remote due to authentication issues.
  if _is_keybase_repo "${git_url}"; then
    ensure_keybase_logged_in || return 1
  fi

  git -C "${folder}" size || true
  if [[ "${force}" == 'Y' ]]; then
    rm -rf "${folder}/.git"

    git -C "${folder}" init --ref-format=reftable .

    git -C "${folder}" remote add origin "${git_url}"
    if is_non_zero_string "${git_user_name}"; then git -C "${folder}" config user.name "${git_user_name}"; fi
    if is_non_zero_string "${git_user_email}"; then git -C "${folder}" config user.email "${git_user_email}"; fi

    rm -f "${folder}/.git/index.lock"
    git -C "${folder}" add -A .
    local human_date
    current_timestamp human_date
    git -C "${folder}" commit -qm "Initial commit: ${human_date}"
  fi

  # Retry the commit in case it failed the first time
  rm -f "${folder}/.git/index.lock"
  git -C "${folder}" add -A .
  git -C "${folder}" amq

  debug "Compressing '$(yellow "${folder}")'"
  git -C "${folder}" rfc
  SKIP_SIZE_BEFORE=1 git -C "${folder}" cc

  if _is_keybase_repo "${git_url}"; then
    debug "$(blue 'Recreating') '$(yellow "${git_url}")'"

    local git_remote_repo_name
    # ${${git_url%/}##*/} strips trailing slash then everything up to the last slash —
    # pure-zsh equivalent of basename, no extract_last_segment subshell call.
    git_remote_repo_name="${${git_url%\/}##*/}"
    keybase git delete -f "${git_remote_repo_name}" || _record_warning "Failed to delete keybase repo '${git_remote_repo_name}' (it might not exist)"
    keybase git create "${git_remote_repo_name}" || error "Failed to create keybase repo '${git_remote_repo_name}'"
  fi

  debug "$(blue 'Pushing') from $(yellow "${folder}") to $(yellow "${git_url}")"
  git -C "${folder}" push --progress -fu origin "${git_branch_name}"

  rm -f "${folder}/.git/index.lock"

  # Regenerate crontab after this script finishes.
  # Clear the backup first so the EXIT trap (_cleanup_recreate -> resume_cron) becomes a no-op.
  load_zsh_configs
  rm -f "${_DOTFILES_CRON_BACKUP_FILE}"
  recron

  print_script_summary '' "The git repo in '$(yellow "${folder}")' recreated and pushed successfully to '$(yellow "${git_url}")'"
}

main "$@"
