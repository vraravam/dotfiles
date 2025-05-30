#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to recreate the git repos in the home and profiles folders. This is useful to remove dangling & orphaned commits from the remote git repo so that fresh cloning is fast.
# It assumes that a pre-existing repo on local is present - so that it can capture the relevant remote details.
# It will force removal of history if the `-f` flag is given. (The history of the profiles repo will always get deleted).

# Do not exit immediately if a command exits with a non-zero status since this is run even if there's no cron entry

# Source shell helpers if they aren't already loaded (check for one representative function)
if ! type red &> /dev/null 2>&1 || ! type strip_trailing_slash &> /dev/null 2>&1; then
  source "${HOME}/.shellrc"
fi

usage() {
  echo "$(red 'Usage'): $(yellow "${1} [-f] <repo folder>")"
  echo " $(yellow '-f'): force squashing into a single commit (profiles repo will automatically/always be forced anyways)"
  echo "    eg: $(cyan "-f ${HOME}")                (will push to $(yellow "$(build_keybase_repo_url "${KEYBASE_HOME_REPO_NAME}")")"
  echo "    eg: $(cyan "${PERSONAL_PROFILES_DIR}")  (will push to $(yellow "$(build_keybase_repo_url "${KEYBASE_PROFILES_REPO_NAME}")")"
  exit 1
}

if [ $# -eq 1 ]; then
  force=N
  folder="${1}"
elif [ $# -eq 2 ]; then
  if [[ "${1}" == '-f' ]]; then
    force=Y
    folder="${2}"
  else
    usage ${0}
  fi
else
  usage ${0}
fi

# Remove trailing slash if present
folder="$(strip_trailing_slash "${folder}")"

# For the profiles repo alone, I don't care about retaining the history
[[ "$(extract_last_segment "${folder}")" == "${KEYBASE_PROFILES_REPO_NAME}" ]] && force=Y

! is_git_repo "${folder}" && error "'${folder}' is not a git repo. Please specify the root of a git repo to proceed. Aborting!!!"

echo "$(yellow 'Processing folder'): '${folder}'"
echo "$(yellow "Squash commits (will lose history!)"): '${force}'"

extract_git_config_value() {
  git -C "${folder}" config --get "${1}" || error "Failed to get git config value '${1}' for folder '${folder}'"
}

# Remove crontab while this script is running
crontab -r &> /dev/null 2>&1

# Capture information from pre-existing git repo
local git_url="$(extract_git_config_value remote.origin.url)"
local git_user_name="$(extract_git_config_value user.name)"
local git_user_email="$(extract_git_config_value user.email)"
local git_branch_name="$(git -C "${folder}" branch --show-current)"

echo "$(yellow 'Repo url'): '${git_url}'"
echo "$(yellow 'User name'): '${git_user_name}'"
echo "$(yellow 'User email'): '${git_user_email}'"

git -C "${folder}" size
if [[ "${force}" == 'Y' ]]; then
  rm -rf "${folder}/.git"

  git -C "${folder}" init .
  git -C "${folder}" remote add origin "${git_url}"
  git -C "${folder}" config user.name "${git_user_name}"
  git -C "${folder}" config user.email "${git_user_email}"

  # touch .gitmodules
  # rm -rf "${folder}/FirefoxProfile/Profiles/DefaultProfile/chrome"
  # git -C "${folder}" submodule -q add -f git@github.com:drannex42/FirefoxSidebar.git "${folder}/FirefoxProfile/Profiles/DefaultProfile/chrome"

  git -C "${folder}" add -A .
  git -C "${folder}" commit -qm "Initial commit: $(date)"
fi

# Retry the commit in case it failed the first time
git -C "${folder}" add -A .
git -C "${folder}" amq

echo "Compressing '${folder}'"
git -C "${folder}" rfc
SKIP_SIZE_BEFORE=1 git -C "${folder}" cc

if [[ "${git_url}" =~ 'keybase' ]]; then
  echo "$(blue 'Recreating') '$(yellow "${git_url}")'"

  ! command_exists keybase && error "'keybase' command not found in the PATH. Aborting!!!"

  local git_remote_repo_name="$(extract_last_segment "${git_url}")"
  keybase git delete -f "${git_remote_repo_name}" || error "Failed to delete keybase repo '${git_remote_repo_name}'"
  keybase git create "${git_remote_repo_name}" || error "Failed to create keybase repo '${git_remote_repo_name}'"
  unset git_remote_repo_name
fi

echo "$(blue 'Pushing') from $(yellow "${folder}") to $(yellow "${git_url}")"
git -C "${folder}" push -fuq origin "${git_branch_name}"

rm -f "${folder}/.git/index.lock"

git -C "${folder}" size

# Resurrect crontab after this script finishes
load_zsh_configs
recron

unset folder
