#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to run the update steps in sequence. (the main point to note is that the natsumi codebase has to be rebased without any conflicts and pushed to the remote so that the runtime ZenProfile chrome folder can be updated to a known working state)
# These are commands that (based on the softwares installed), need to be periodically run to upgrade those softwares.
# Rather than remembering each tool and its specific command invocation, this script comes handy.

type load_zsh_configs &> /dev/null 2>&1 || source "${HOME}/.shellrc"
FIRST_INSTALL=true load_zsh_configs

debug 'PATH'

if command_exists bupc; then
  section_header 'Running brew doctor'
  brew doctor
  section_header 'Updating brews'
  bupc
  success 'Successfully updated brews'
else
  debug 'skipping updating brews & casks'
fi

if command_exists mise; then
  section_header 'Updating mise'
  mise plugins update
  # This is typically run only in the ${HOME} folder so as to upgrade the software versions in the "global" sense
  mise upgrade --bump
  mise prune -y
  success 'Successfully updated mise plugins'
else
  debug 'skipping updating mise'
fi

if command_exists tldr; then
  section_header 'Updating tldr'
  tldr --update
  success 'Successfully updated tldr database'
else
  debug 'skipping updating tldr'
fi

if command_exists git-ignore-io; then
  section_header 'Updating git-ignore'
  # 'ignore-io' updates the data from http://gitignore.io so that we can generate the '.gitignore' file contents from the cmd-line
  git ignore-io --update-list
  success 'Successfully updated gitignore database'
else
  debug 'skipping updating git-ignore'
fi

if command_exists code; then
  section_header 'Updating VSCodium extensions'
  code --update-extensions
  success 'Successfully updated VSCodium extensions'
else
  debug 'skipping updating code extensions'
fi

if command_exists omz; then
  section_header 'Updating omz'
  omz update
  success 'Successfully updated oh-my-zsh'
else
  debug 'skipping updating omz'
fi

local firefox_profiles="${PERSONAL_PROFILES_DIR}/FirefoxProfile/Profiles"
if is_directory "${firefox_profiles}"; then
  section_header 'Update betterfox user.js'
  curl -fsSL https://raw.githubusercontent.com/yokoffing/Betterfox/main/user.js -o "${firefox_profiles}/user.js"
fi
unset firefox_profiles

local natsumi_codebase="${PROJECTS_BASE_DIR}/oss/natsumi-browser"
if is_git_repo "${natsumi_codebase}"; then
  section_header 'Update locally checked-out copy of my fork of the natsumi codebase' # so as to get a clean pull in the Zen profile chrome directory
  git -C "${natsumi_codebase}" upreb
  [[ ! "$(git -C "${natsumi_codebase}" st)" =~ 'up to date' ]] && error "Need to manually resolve status of '${natsumi_codebase}' before it can be applied into the runtime ZenProfile"
fi
unset natsumi_codebase

local zen_browser_desktop_codebase="${PROJECTS_BASE_DIR}/oss/zen-browser-desktop"
if is_git_repo "${zen_browser_desktop_codebase}"; then
  section_header "Remove 'twilight' tag from zen-browser-desktop repo"
  git -C "${zen_browser_desktop_codebase}" delete-tag twilight
fi
unset zen_browser_desktop_codebase

section_header 'Update repos in home folder'
home pull

sleep 10  # so that GH doesn't throttle when we call a lot of times within a short time

section_header 'Upreb oss repos'
upreb

section_header 'Capture app preferences'
capture-defaults.sh e

section_header 'Update home and profiles repos'
update_all_repos

section_header 'Report status of home and profiles repos'
status_all_repos

section_header 'Updating all browser profile chrome folders'
# HACK: To fix issue where someone does not have any such 'DefaultProfile/chrome'.... (need to find a correct fix)
# otherwise, the next 'for' loop fails and errors out
ensure_dir_exists "${PERSONAL_PROFILES_DIR}/DummyProfile/Profiles/DefaultProfile/chrome"
for folder in "${PERSONAL_PROFILES_DIR}"/*Profile/Profiles/DefaultProfile/chrome; do
  if is_git_repo "${folder}"; then
    git -C "${folder}" pull -r
    success "Successfully updated natsumi-browser into the folder: '$(yellow "${folder}")'"
  else
    debug "skipping updating '$(yellow "${folder}")' since it's not a git repo"
  fi
done
unset folder
rm -rf "${PERSONAL_PROFILES_DIR}/DummyProfile/"
