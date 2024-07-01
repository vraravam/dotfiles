#!/usr/bin/env bash

# This script is used to recreate the git repos in the home and profiles folders. This is useful to remove dangling & orphaned commits from the remote git repo so that fresh cloning is fast.
# It assumes that a pre-existing repo on local is present - so that it can capture the relevant remote details.
# It will force removal of history if the `-f` flag is given. (The history of the profiles repo will always get deleted).

USERNAME="${USERNAME:-$(whoami)}"
PERSONAL_BIN_DIR="${PERSONAL_BIN_DIR:-"${HOME}/.bin"}"

usage() {
  echo "Usage: ${0} [-f] <repo folder>"
  echo " -f : force recreation (profiles repo will automatically/always be forced anyways)"
  echo "    eg: -f ${HOME}                             (will push to keybase://private/avijayr/home)"
  echo "    eg: ${HOME}/personal/${USERNAME}/profiles  (will push to keybase://private/avijayr/profiles)"
  exit 1
}

if [ $# -eq 1 ]; then
  force=N
  folder="${1}"
elif [ $# -eq 2 ]; then
  if [ "${1}" == "-f" ]; then
    force=Y
    folder="${2}"
  else
    usage
  fi
else
  usage
fi

# For the profiles repo alone, I don't care about retaining the history
[[ "${folder}" =~ "profiles" ]] && force=Y

echo "Processing folder: '${folder}'"
echo "force: ${force}"

git_cmd="git -C ${folder}"

extract_git_config_value() {
  ${git_cmd} config "${1}" || exit 1
}

# Remove crontab while this script is running
crontab -r

# Capture information from pre-existing git repo
git_url=$(extract_git_config_value remote.origin.url)   # "keybase://private/avijayr/home"
git_user_name=$(extract_git_config_value user.name)     # "Vijay A"
git_user_email=$(extract_git_config_value user.email)   # "vraravam@users.noreply.github.com"
git_branch_name=$(${git_cmd} branch --show-current)     # "master"

echo "==> Size of repository at '${folder}' before: $(du -sh "${folder}/.git" | cut -f1)"
if [[ "${force}" == "Y" ]]; then
  rm -rf "${folder}/.git"

  ${git_cmd} init .
  ${git_cmd} remote add origin "${git_url}"
  ${git_cmd} config user.name "${git_user_name}"
  ${git_cmd} config user.email "${git_user_email}"

  # touch .gitmodules
  # rm -rf "${folder}/FirefoxProfile/Profiles/chrome"
  # ${git_cmd} submodule -q add -f git@github.com:drannex42/FirefoxSidebar.git "${folder}/FirefoxProfile/Profiles/chrome"

  ${git_cmd} add -A .
  ${git_cmd} commit -qm "Initial commit: $(date)"
fi

# Retry the commit in case it failed the first time
${git_cmd} add -A .
${git_cmd} amq

echo "Compressing '${folder}'"
${git_cmd} rfc
${git_cmd} cc

if [[ "${git_url}" =~ "keybase" ]]; then
  echo "Recreating '${git_url}'"
  git_remote_name=$(echo "${git_url}" | cut -d'/' -f5)
  keybase git delete -f "${git_remote_name}"
  keybase git create "${git_remote_name}"
fi

echo "Pushing from '${folder}' to '${git_url}'"
${git_cmd} push -fu origin "${git_branch_name}"

rm -fv "${folder}/.git/index.lock"

echo "==> Size of repository at '${folder}' after: $(du -sh "${folder}/.git" | cut -f1)"

# Resurrect crontab after this script finishes
cron_file="${PERSONAL_BIN_DIR}/macos/crontab.txt"
test -f "${cron_file}" && crontab "${cron_file}"
