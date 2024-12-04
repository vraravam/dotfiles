#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to recreate the git repos in the home and profiles folders. This is useful to remove dangling & orphaned commits from the remote git repo so that fresh cloning is fast.
# It assumes that a pre-existing repo on local is present - so that it can capture the relevant remote details.
# It will force removal of history if the `-f` flag is given. (The history of the profiles repo will always get deleted).

type command_exists &> /dev/null 2>&1 || source "${HOME}/.shellrc"

! command_exists keybase && echo "Keybase not found in the PATH. Aborting!!!" && exit -1

usage() {
  echo "$(red "Usage"): $(yellow "${1} [-f] <repo folder>")"
  echo " $(yellow "-f") : force recreation (profiles repo will automatically/always be forced anyways)"
  echo "    eg: $(cyan "-f ${HOME}")                (will push to $(yellow "keybase://private/${KEYBASE_USERNAME}/${KEYBASE_HOME_REPO_NAME}"))"
  echo "    eg: $(cyan "${PERSONAL_PROFILES_DIR}")  (will push to $(yellow "keybase://private/${KEYBASE_USERNAME}/${KEYBASE_PROFILES_REPO_NAME}"))"
  exit 1
}

if [ $# -eq 1 ]; then
  force=N
  folder="${1}"
elif [ $# -eq 2 ]; then
  if [[ "${1}" -eq "-f" ]]; then
    force=Y
    folder="${2}"
  else
    usage ${0}
  fi
else
  usage ${0}
fi

! is_git_repo "${folder}" && echo "'${folder}' is not a git repo. Please specify the root of a git repo to proceed. Aborting!!!" && exit 1

# For the profiles repo alone, I don't care about retaining the history
[[ "${folder}" =~ "profiles" ]] && force=Y

echo "$(yellow "Processing folder"): '${folder}'"
echo "$(yellow "force"): '${force}'"

git_cmd="git -C ${folder}"

extract_git_config_value() {
  eval "${git_cmd} config '${1}'" || exit 1 # Most likely reason for exiting is if the required git configuration hasn't been set
}

# Remove crontab while this script is running
crontab -r &> /dev/null 2>&1

# Capture information from pre-existing git repo
git_url="$(extract_git_config_value remote.origin.url)"
git_user_name="$(extract_git_config_value user.name)"
git_user_email="$(extract_git_config_value user.email)"
git_branch_name="$(eval "${git_cmd} branch --show-current")"

echo "$(yellow "Git url"): '${git_url}'"
echo "$(yellow "User name"): '${git_user_name}'"
echo "$(yellow "User email"): '${git_user_email}'"

eval "${git_cmd} size"
if [[ "${force}" == "Y" ]]; then
  rm -rf "${folder}/.git"

  eval "${git_cmd} init ."
  eval "${git_cmd} remote add origin '${git_url}'"
  eval "${git_cmd} config user.name '${git_user_name}'"
  eval "${git_cmd} config user.email '${git_user_email}'"

  # touch .gitmodules
  # rm -rf "${folder}/FirefoxProfile/Profiles/chrome"
  # eval "${git_cmd} submodule -q add -f git@github.com:drannex42/FirefoxSidebar.git '${folder}/FirefoxProfile/Profiles/chrome'"

  eval "${git_cmd} add -A ."
  eval "${git_cmd} commit -qm \"Initial commit: $(date)\""
fi

# Retry the commit in case it failed the first time
eval "${git_cmd} add -A ."
eval "${git_cmd} amq"

echo "Compressing '${folder}'"
eval "${git_cmd} rfc"
eval "SKIP_SIZE_BEFORE=1 ${git_cmd} cc"

if [[ "${git_url}" =~ "keybase" ]]; then
  echo "$(blue "Recreating") '${git_url}'"
  git_remote_name="$(echo "${git_url}" | cut -d'/' -f5)"
  keybase git delete -f "${git_remote_name}"
  keybase git create "${git_remote_name}"
fi

echo "$(blue "Pushing") from $(yellow "${folder}") to $(yellow "${git_url}")"
eval "${git_cmd} push -fuq origin '${git_branch_name}'"

rm -fv "${folder}/.git/index.lock"

eval "${git_cmd} size"

# Resurrect crontab after this script finishes
cron_file="${PERSONAL_CONFIGS_DIR}/crontab.txt"
is_file "${cron_file}" && crontab "${cron_file}"
