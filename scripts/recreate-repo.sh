#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to recreate the git repos in the home and profiles folders. This is useful to remove dangling & orphaned commits from the remote git repo so that fresh cloning is fast.
# It assumes that a pre-existing repo on local is present - so that it can capture the relevant remote details.
# It will force removal of history if the `-f` flag is given. (The history of the profiles repo will always get deleted).

# Exit immediately if a command exits with a non-zero status.
set -e

# Source shell helpers if they aren't already loaded
type is_shellrc_sourced 2>&1 &> /dev/null || source "${HOME}/.shellrc"

usage() {
  echo "$(red 'Usage'): $(yellow "${1}") [-f] -d <repo-folder>"
  echo " $(yellow '-f')               --> (optional) force squashing into a single commit (profiles repo will automatically/always be forced anyways)"
  echo " $(yellow '-d <repo-folder>') --> (mandatory) The folder which has to be processed"
  echo "    eg: $(cyan "-f -d \${HOME}")                (will push to $(yellow "$(build_keybase_repo_url "${KEYBASE_HOME_REPO_NAME}")"))"
  echo "    eg: $(cyan "-d \${PERSONAL_PROFILES_DIR}")  (will push to $(yellow "$(build_keybase_repo_url "${KEYBASE_PROFILES_REPO_NAME}")"))"
  exit 1
}

local force=N
local folder
while getopts ":fd:" opt; do
  case ${opt} in
    f)
      force=Y
      ;;
    d)
      folder="${OPTARG}"
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

if is_zero_string "${folder}"; then
  usage "${0##*/}"
fi

# Remove trailing slash if present
folder="$(strip_trailing_slash "${folder}")"

# For the profiles repo alone, I don't care about retaining the history
[[ "$(extract_last_segment "${folder}")" == "${KEYBASE_PROFILES_REPO_NAME}" ]] && force=Y

! is_git_repo "${folder}" && error "'${folder}' is not a git repo. Please specify the root of a git repo to proceed. Aborting!!!"

echo "$(yellow 'Processing folder'): '${folder}'"
echo "$(yellow 'Squash commits (will lose history!)'): '${force}'"

extract_git_config_value() {
  git -C "${folder}" config --get "${1}" || error "Failed to get git config value '${1}' for folder '${folder}'"
}

# Backup crontab and set up a trap to restore it on exit.
local CRON_BACKUP_FILE="$(mktemp)"
# Save current crontab; ignore errors if it's empty.
crontab -l > "${CRON_BACKUP_FILE}" 2> /dev/null || true # Backup crontab, ignore failure if empty

cleanup() {
  local exit_code=$?
  # Restore crontab from backup only if the script fails.
  if [[ ${exit_code} -ne 0 ]]; then
    warn "Script exited with error code ${exit_code}."
    if [[ -s "${CRON_BACKUP_FILE}" ]]; then
      warn 'Attempting to restore cron jobs from backup...'
      restore_cron "${CRON_BACKUP_FILE}" && success 'Restored crontab from backup.'
    fi
  fi
  # Clean up the backup file on any exit.
  rm -f "${CRON_BACKUP_FILE}"
}
trap cleanup EXIT

# Remove crontab while this script is running. The trap will restore it on failure.
crontab -r 2>&1 &> /dev/null || true

# Capture information from pre-existing git repo
local git_url="$(extract_git_config_value remote.origin.url)"
local git_user_name="$(extract_git_config_value user.name)"
local git_user_email="$(extract_git_config_value user.email)"
local git_branch_name="$(git -C "${folder}" branch --show-current)"
is_zero_string "${git_branch_name}" && error 'Failed to determine current branch name'

echo "$(yellow 'Repo url'): '${git_url}'"
echo "$(yellow 'User name'): '${git_user_name}'"
echo "$(yellow 'User email'): '${git_user_email}'"

git -C "${folder}" size || true
if [[ "${force}" == 'Y' ]]; then
  rm -rf "${folder}/.git"

  git -C "${folder}" init .
  git -C "${folder}" remote add origin "${git_url}"
  git -C "${folder}" config user.name "${git_user_name}"
  git -C "${folder}" config user.email "${git_user_email}"

  rm -f "${folder}/.git/index.lock"
  git -C "${folder}" add -A .
  git -C "${folder}" commit -qm "Initial commit: $(date)"
fi

# Retry the commit in case it failed the first time
rm -f "${folder}/.git/index.lock"
git -C "${folder}" add -A .
git -C "${folder}" amq

echo "Compressing '${folder}'"
git -C "${folder}" rfc
SKIP_SIZE_BEFORE=1 git -C "${folder}" cc

if [[ "${git_url}" =~ 'keybase' ]]; then
  echo "$(blue 'Recreating') '$(yellow "${git_url}")'"

  ! command_exists keybase && error "'keybase' command not found in the PATH. Aborting!!!"

  local git_remote_repo_name="$(extract_last_segment "${git_url}")"
  keybase git delete -f "${git_remote_repo_name}" || warn "Failed to delete keybase repo '${git_remote_repo_name}' (it might not exist)"
  keybase git create "${git_remote_repo_name}" || error "Failed to create keybase repo '${git_remote_repo_name}'"
  unset git_remote_repo_name
fi

echo "$(blue 'Pushing') from $(yellow "${folder}") to $(yellow "${git_url}")"
git -C "${folder}" push --progress -fu origin "${git_branch_name}"

rm -f "${folder}/.git/index.lock"

# Resurrect crontab after this script finishes
load_zsh_configs
recron

unset folder
