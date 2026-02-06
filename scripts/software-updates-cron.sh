#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to run the update steps in sequence. (the main point to note is that the natsumi codebase has to be rebased without any conflicts and pushed to the remote so that the runtime ZenProfile chrome folder can be updated to a known working state)
# These are commands that need to be periodically run to upgrade any installed softwares. Rather than remembering each tool and its specific command invocation, this script comes handy.

# Do not exit immediately if a command exits with a non-zero status since this is run within a cronjob

# Since this script is invoked from cron (which uses bash shell), we need to explicitly load all zsh configs (not just shellrc)
type is_shellrc_sourced 2>&1 &> /dev/null || source "${HOME}/.shellrc"
load_zsh_configs

local script_start_time=$(date +%s)
print_script_start

perform_update() {
  local title="${1}"
  local check_cmd="${2}"
  local update_cmd="${3}"

  if command_exists "${check_cmd}"; then
    section_header "$(yellow 'Updating') $(purple "${title}")"
    if eval "${update_cmd}"; then
      success "Successfully updated: '${title}'"
    else
      warn "Failed to update: '${title}'"
    fi
  else
    debug "Command not found: '${check_cmd}'"
  fi
}

# brew doctor # Removed for cron job efficiency
perform_update 'brews' 'brew' 'brew bundle check || brew bundle'

# This is typically run only in the ${HOME} folder so as to upgrade the software versions in the "global" sense
perform_update 'mise plugins' 'mise' 'mise plugins update && mise upgrade --bump && mise prune -y'

perform_update 'tldr database' 'tldr' 'tldr --update'

# 'ignore-io' updates the data from http://gitignore.io so that we can generate the '.gitignore' file contents from the cmd-line
perform_update 'git-ignore database' 'git-ignore-io' 'git ignore-io --update-list'

perform_update 'oh-my-zsh' 'omz' 'omz update'

# Commenting out since I have started using rapidfox user.js settings
# local firefox_profiles="${PERSONAL_PROFILES_DIR}/FirefoxProfile/Profiles/DefaultProfile"
# if is_directory "${firefox_profiles}"; then
#   section_header "$(yellow 'Update betterfox user.js') in $(purple "${firefox_profiles}")"
#   curl --retry 3 --retry-delay 5 -fsSL https://raw.githubusercontent.com/yokoffing/Betterfox/main/user.js -o "${firefox_profiles}/user.js" && success "Updated betterfox user.js" || warn "Failed to update betterfox user.js"
# else
#   debug "Skipping betterfox user.js update, directory not found: ${firefox_profiles}"
# fi
# unset firefox_profiles

# Commenting out since I have started using rapidfox user.js settings
# local zen_profiles="${PERSONAL_PROFILES_DIR}/ZenProfile/Profiles/DefaultProfile"
# if is_directory "${zen_profiles}"; then
#   section_header "$(yellow 'Update betterfox user.js') in $(purple "${zen_profiles}")"
#   curl --retry 3 --retry-delay 5 -fsSL https://raw.githubusercontent.com/yokoffing/Betterfox/main/zen/user.js -o "${zen_profiles}/user.js" && success "Updated betterzen user.js" || warn "Failed to update betterzen user.js"
# else
#   debug "Skipping betterzen user.js update, directory not found: ${zen_profiles}"
# fi
# unset zen_profiles

local natsumi_codebase="${PROJECTS_BASE_DIR}/oss/natsumi-browser"
if is_git_repo "${natsumi_codebase}"; then
  section_header "$(yellow 'Update locally checked-out copy of my fork of the natsumi codebase')" # so as to get a clean pull in the Zen profile chrome directory
  git -C "${natsumi_codebase}" upreb
  # Check if the working directory is clean and the branch is up-to-date with its upstream
  if is_zero_string "$(git -C "${natsumi_codebase}" status --porcelain)" && \
        [[ "$(git -C "${natsumi_codebase}" rev-parse @)" == "$(git -C "${natsumi_codebase}" rev-parse '@{u}' 2> /dev/null)" ]]; then
    success "Natsumi codebase '${natsumi_codebase}' is clean and up-to-date."
  else
    # Warn instead of erroring out, allowing the cron job to continue
    warn "Natsumi codebase '${natsumi_codebase}' has uncommitted changes or is not up-to-date with its upstream. Manual intervention might be needed before it can be safely applied into the runtime ZenProfile."
  fi
else
  debug "Skipping natsumi codebase check as '${natsumi_codebase}' is not a git repo."
fi
unset natsumi_codebase

local zen_browser_desktop_codebase="${PROJECTS_BASE_DIR}/oss/zen-browser-desktop"
if is_git_repo "${zen_browser_desktop_codebase}"; then
  section_header "$(yellow "Remove 'twilight' tag from") $(purple 'zen-browser-desktop') repo"
  if git -C "${zen_browser_desktop_codebase}" rev-parse -q --verify refs/tags/twilight 2>&1 &> /dev/null; then
    git -C "${zen_browser_desktop_codebase}" delete-tag twilight && success "Deleted 'twilight' tag."
  fi
fi
unset zen_browser_desktop_codebase

if command_exists ollama; then
  section_header "$(yellow 'Pull ollama models')"
  local -a ollama_models=(
    codellama
    deepseek-coder-v2
    deepseek-r1
    gpt-4
    gpt-oss:20b
    qwen3-coder:30b
  )
  for model in "${ollama_models[@]}"; do
    ollama pull "${model}"
  done
  unset model ollama_models
fi

echo '==> Finished independent updates.'

section_header "$(yellow 'Update repos in home folder')"
home pull

sleep 10  # so that GH doesn't throttle when we call a lot of times within a short time

section_header "$(yellow 'Upreb repos in oss folder')"
FOLDER="${PROJECTS_BASE_DIR}/oss" rug upreb && success 'Finished upreb for oss repos' || warn 'Failed to upreb oss repos'

section_header "$(yellow 'Capture app preferences')"
capture-prefs.sh -e && success 'Finished capturing app preferences' || warn 'Failed to capture app preferences'

section_header "$(yellow 'Update home and profiles repos')"
update_all_repos && success 'Finished updating home and profiles repos' || warn 'Failed to update home and profiles repos'

section_header "$(yellow 'Report status of all repos')"
status_all_repos

section_header "$(yellow 'Updating all browser profile chrome folders')"
# Use zsh glob qualifiers to only loop if matches exist and are directories
# (N) nullglob: if no match, the pattern expands to nothing
# (/): only match directories
local chrome_folders=("${PERSONAL_PROFILES_DIR}"/*Profile/Profiles/DefaultProfile/chrome(N/))
if [[ ${#chrome_folders[@]} -gt 0 ]]; then
  for folder in "${chrome_folders[@]}"; do
    if is_git_repo "${folder}"; then
      section_header "$(yellow 'Updating chrome folder:') $(purple "${folder}")"
      git -C "${folder}" pull -r && success "Successfully updated: '$(yellow "${folder}")'" || warn "Failed to update: '$(yellow "${folder}")'"
    else
      debug "skipping update for non-repo: '$(yellow "${folder}")'"
    fi
  done
  success 'Finished updating chrome folders'
  unset folder
fi
unset chrome_folders

section_header "$(yellow 'Checking if any greedy applications are outdated')"
if command_exists bcg; then
  outdated="$(bcg | \grep -v -iE 'homebrew|Downloading')"
  is_non_zero_string "${outdated}" && error "Found some outdated softwares that need manual updating: $(red "${outdated}")"
else
  debug 'skipping updating brews & casks'
fi

section_header "$(yellow 'Finished software updates at') $(purple "$(date)")"
print_script_duration "${script_start_time}"
