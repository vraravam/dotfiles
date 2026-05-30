#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to run the update steps in sequence.
# These are commands that need to be periodically run to upgrade any installed softwares.
# Rather than remembering each tool and its specific command invocation, this script comes handy.

# Do not exit immediately if a command exits with a non-zero status since this is run within a cronjob

_SCRIPT_NAME="${0:t}"

# Re-source guard is inside .aliases itself — safe to call unconditionally.
source "${HOME}/.aliases"

# Run a single update step if the check command is available
_perform_update() {
  local title="${1}"
  local check_cmd="${2}"
  local update_cmd="${3}"

  if command_exists "${check_cmd}"; then
    step_start
    section_header "$(yellow 'Updating') $(purple "${title}")"
    if eval "${update_cmd}"; then
      success "Successfully updated: '${title}'"
    else
      warn "Failed to update: '${title}'"
    fi
    step_end
  else
    debug "Command not found: '${check_cmd}'"
  fi
}

main() {
  # LOCAL_TRAPS scopes the ERR trap to main() only — it is not inherited into called
  # functions. Without this, non-zero exits inside called functions (e.g. git sci
  # finding nothing to commit, st warning about a missing repo) fire the trap even
  # when the call site has '|| warn' or '|| true'.
  setopt LOCAL_TRAPS
  # error() calls _dotfiles_notify() which triggers an osascript notification.
  trap 'current_timestamp _trap_time; error "Software updates failed at ${_trap_time}. Check ~/software-updates-cron.log for details."' ERR

  # Capture start epoch into both a local variable and SCRIPT_START_TIMES.
  # The local is passed explicitly to print_script_duration at the end of main.
  # SCRIPT_START_TIMES is used by step_end (called throughout this script via
  # _perform_update) to compute the "total elapsed" column independently of the
  # local variable.  Both are required; see the design note above
  # step_timing_init in .shellrc.
  local script_start_time
  script_start_time="${EPOCHSECONDS}"
  SCRIPT_START_TIMES+=("${script_start_time}")
  local tracked_file f folder outdated_flat=''
  print_script_start

  # brew doctor is skipped — too slow for cron jobs
  _perform_update 'brews' 'brew' 'brew bundle check || brew bundle'

  # This is typically run only in the ${HOME} folder so as to upgrade the software versions in the "global" sense
  _perform_update 'mise plugins' 'mise' 'mise plugins update && mise upgrade --bump' # && mise prune --tools --dry-run'

  _perform_update 'tldr database' 'tldr' 'tldr --update'

  # 'ignore-io' updates the data from http://gitignore.io so that we can generate the '.gitignore' file contents from the cmd-line
  _perform_update 'git-ignore database' 'git-ignore-io' 'git ignore-io --update-list'

  _perform_update 'claude-code' 'claude' 'claude update'

  # Update antidote plugins and regenerate the static bundle
  step_start
  section_header "$(yellow 'Updating') $(purple 'antidote plugins') and regenerating plugin bundle"
  update_antidote_and_regenerate_plugin_bundle
  step_end

  # Update bat cache
  if command_exists bat; then
    step_start
    section_header "$(yellow 'Updating') $(purple 'bat') cache"
    local bat_syntax_dir
    bat_syntax_dir="$(bat --config-dir)/syntaxes"
    ensure_dir_exists "${bat_syntax_dir}"
    curl --retry 3 --retry-delay 5 -fsSL https://raw.githubusercontent.com/mattmc3/antidote/main/misc/zsh_plugins.sublime-syntax -o "${bat_syntax_dir}/zsh_plugins.sublime-syntax"
    bat cache --build
    step_end
  fi

  # Disabled: rapidfox user.js replaces betterfox for the Firefox profile
  # local firefox_profiles="${PERSONAL_PROFILES_DIR}/FirefoxProfile/Profiles/DefaultProfile"
  # if is_directory "${firefox_profiles}"; then
  #   section_header "$(yellow 'Update betterfox user.js') in $(purple "${firefox_profiles}")"
  #   curl --retry 3 --retry-delay 5 -fsSL https://raw.githubusercontent.com/yokoffing/Betterfox/main/user.js -o "${firefox_profiles}/user.js" && success "Updated betterfox user.js" || warn "Failed to update betterfox user.js"
  # else
  #   debug "Skipping betterfox user.js update, directory not found: ${firefox_profiles}"
  # fi
  # unset firefox_profiles

  # Disabled: rapidfox user.js replaces betterfox for the Zen profile
  # local zen_profiles="${PERSONAL_PROFILES_DIR}/ZenProfile/Profiles/DefaultProfile"
  # if is_directory "${zen_profiles}"; then
  #   section_header "$(yellow 'Update betterfox user.js') in $(purple "${zen_profiles}")"
  #   curl --retry 3 --retry-delay 5 -fsSL https://raw.githubusercontent.com/yokoffing/Betterfox/main/zen/user.js -o "${zen_profiles}/user.js" && success "Updated betterzen user.js" || warn "Failed to update betterzen user.js"
  # else
  #   debug "Skipping betterzen user.js update, directory not found: ${zen_profiles}"
  # fi
  # unset zen_profiles

  # TODO: Removing natsumi as a trial to check whether I can live without natsumi at all 2026-05-20
  # local natsumi_codebase="${PROJECTS_BASE_DIR}/oss/natsumi-browser"
  # if is_git_repo "${natsumi_codebase}"; then
  #   section_header "$(yellow 'Update locally checked-out copy of my fork of the natsumi codebase')" # so as to get a clean pull in the Zen profile chrome directory
  #   git -C "${natsumi_codebase}" upreb
  #   # Check if the working directory is clean and the branch is up-to-date with its upstream
  #   if is_zero_string "$(git -C "${natsumi_codebase}" status --porcelain)" &&
  #         [[ "$(git -C "${natsumi_codebase}" rev-parse @)" == "$(git -C "${natsumi_codebase}" rev-parse '@{u}' 2>/dev/null)"  ]]; then
  #     success "Natsumi codebase '${natsumi_codebase}' is clean and up-to-date."
  #   else
  #     # Warn instead of erroring out, allowing the cron job to continue
  #     warn "Natsumi codebase '${natsumi_codebase}' has uncommitted changes or is not up-to-date with its upstream. Manual intervention might be needed before it can be safely applied into the runtime ZenProfile."
  #   fi
  # else
  #   debug "Skipping natsumi codebase check as '${natsumi_codebase}' is not a git repo."
  # fi

  local zen_browser_desktop_codebase="${PROJECTS_BASE_DIR}/oss/zen-browser-desktop"
  if is_git_repo "${zen_browser_desktop_codebase}"; then
    step_start
    section_header "$(yellow "Remove 'twilight' tag from") $(purple 'zen-browser-desktop') repo"
    # Only delete the stale tag here (no rebase; upreb is handled in the subsequent blocks)
    # upreb-zen-browser-desktop.sh mirrors this logic and additionally runs _upreb when called interactively.
    if git -C "${zen_browser_desktop_codebase}" rev-parse -q --verify refs/tags/twilight &>/dev/null; then
      git -C "${zen_browser_desktop_codebase}" delete-tag twilight && success "Deleted 'twilight' tag."
    fi
    step_end
  fi

  success 'Finished independent updates.'

  if command_exists run-all.sh; then
    step_start
    section_header "$(yellow 'Update repos in home folder')"
    # Aliases ('home', 'rug') are not expanded in non-interactive shells (e.g. cron).
    # Use the equivalent direct invocation instead of the 'home pull' alias.
    FOLDER="${HOME}" FILTER='.bin|.dotfiles|zsh|mise' MAXDEPTH=5 run-all.sh git pull || warn 'Failed to pull home repos'
    step_end

    sleep 10  # so that GH doesn't throttle when we call a lot of times within a short time

    step_start
    section_header "$(yellow 'Upreb repos in oss folder')"
    # Aliases ('oss', 'rug') are not expanded in non-interactive shells (e.g. cron).
    # Use the equivalent direct invocation instead of the 'oss upreb' alias.
    FOLDER="${PROJECTS_BASE_DIR}/oss" MAXDEPTH=4 run-all.sh git upreb && success 'Finished upreb for oss repos' || warn 'Failed to upreb oss repos'
    step_end

    step_start
    section_header "$(yellow 'Restoring mtime and registering for maintenance operations')"
    # Aliases ('all', 'rug') are not expanded in non-interactive shells (e.g. cron).
    # Use the equivalent direct invocation instead of the 'all' alias.
    FOLDER='/Users/vijay' MAXDEPTH=7 run-all.sh git restore-mtime -c
    FOLDER='/Users/vijay' MAXDEPTH=7 run-all.sh git maintenance register --config-file "${HOME}/.gitconfig-oss.inc"
    FOLDER='/Users/vijay' MAXDEPTH=7 run-all.sh git maintenance start
    step_end
  fi

  # Collect repo ancestor dirs once and share across both post-clone operations
  # to avoid running the expensive find traversal twice.
  local -a all_dirs
  _collect_repo_ancestor_dirs
  _SHARED_REPO_DIRS=("${all_dirs[@]}")

  step_start
  section_header "$(yellow 'Allow all direnv configs')"
  allow_all_direnv_configs
  step_end

  step_start
  section_header "$(yellow 'Install languages using mise')"
  install_mise_versions
  step_end

  unset _SHARED_REPO_DIRS

  step_start
  section_header "$(yellow 'Regenerate repo aliases')"
  regenerate_repo_aliases
  step_end

  step_start
  section_header "$(yellow 'Capture app preferences')"
  capture-prefs.sh -e && success 'Finished capturing app preferences' || warn 'Failed to capture app preferences'
  step_end

  step_start
  section_header "$(yellow 'Prune old timestamped session backups from browser-profiles repo')"
  if is_git_repo "${PERSONAL_PROFILES_DIR}"; then
    local cutoff_date file_date
    # Compute cutoff date string (7 days ago) using pure zsh arithmetic + current_date.
    # YYYY-MM-DD strings sort lexicographically, so string comparison is correct.
    strftime -s cutoff_date '%Y-%m-%d' $((EPOCHSECONDS - 7 * 24 * 3600))
    # Pattern: zen-sessions-backup/zen-sessions-YYYY-MM-DD-HH.jsonlz4
    local -a old_backups=()
    while IFS= read -r tracked_file; do
      # Extract the date portion: YYYY-MM-DD from the filename
      file_date="${tracked_file:t:r:r}"        # strip dirs, strip .jsonlz4 → zen-sessions-YYYY-MM-DD-HH
      file_date="${file_date#zen-sessions-}"   # → YYYY-MM-DD-HH
      file_date="${file_date%%-[0-9][0-9]}"    # → YYYY-MM-DD
      if [[ "${file_date}" < "${cutoff_date}" ]]; then
        old_backups+=("${tracked_file}")
      fi
    done < <(git -C "${PERSONAL_PROFILES_DIR}" ls-files -- '*/zen-sessions-backup/zen-sessions-*.jsonlz4')

    if is_non_empty_array old_backups; then
      for f in "${old_backups[@]}"; do
        git -C "${PERSONAL_PROFILES_DIR}" rm --cached -q -- "${f}" && debug "Unpinned old session backup: $(yellow "${f}")"
      done
      success "Pruned ${#old_backups[@]} session backup file(s) older than 7 days"
    else
      debug 'No old session backups to prune'
    fi
  else
    debug "Skipping session backup pruning — not a git repo: '$(yellow "${PERSONAL_PROFILES_DIR}")'"
  fi
  step_end

  step_start
  section_header "$(yellow 'Check profiles repo size')"
  if is_git_repo "${PERSONAL_PROFILES_DIR}"; then
    local profiles_size_kb
    profiles_size_kb=$(du -sk "${PERSONAL_PROFILES_DIR}" 2>/dev/null | awk '{print $1}')
    local profiles_size_limit_kb=$((2 * 1024 * 1024))  # 2 GB
    if ((profiles_size_kb > profiles_size_limit_kb)); then
      local profiles_size_human
      profiles_size_human=$(du -sh "${PERSONAL_PROFILES_DIR}" 2>/dev/null | awk '{print $1}')
      error "Profiles repo is ${profiles_size_human} — exceeds 2GB threshold. Consider running: recreate-repo.sh -d \"${PERSONAL_PROFILES_DIR}\""
    else
      debug "Profiles repo size within 2GB threshold"
    fi
  fi
  step_end

  step_start
  section_header "$(yellow 'Update home and profiles repos')"
  # source imports the function definition into this shell. The explicit call on
  # the next line is still required because the autoload script's zsh_eval_context
  # guard ('*:file*' match) suppresses auto-execution when sourced — it only
  # runs automatically when the file is invoked directly, not when sourced.
  source "${XDG_CONFIG_HOME}/zsh/update_all_repos"
  update_all_repos && success 'Finished updating home and profiles repos' || warn 'Failed to update home and profiles repos'
  step_end

  step_start
  section_header "$(yellow 'Report status of all repos')"
  # source imports the function definition into this shell. The explicit call on
  # the next line is still required because the autoload script's zsh_eval_context
  # guard ('*:file*' match) suppresses auto-execution when sourced — it only
  # runs automatically when the file is invoked directly, not when sourced.
  source "${XDG_CONFIG_HOME}/zsh/status_all_repos"
  status_all_repos || true
  step_end

  step_start
  section_header "$(yellow 'Updating all browser profile chrome folders if they are git repos')"
  # Use zsh glob qualifiers to only loop if matches exist and are directories
  # (N) nullglob: if no match, the pattern expands to nothing
  # (/): only match directories
  local chrome_folders=("${PERSONAL_PROFILES_DIR}"/*Profile/Profiles/DefaultProfile/chrome(N/))
  if is_non_empty_array chrome_folders; then
    for folder in "${chrome_folders[@]}"; do
      if is_git_repo "${folder}"; then
        section_header2 "$(yellow 'Updating chrome folder:') $(purple "${folder}")"
        git -C "${folder}" pull -r && success "Successfully updated: '$(yellow "${folder}")'" || warn "Failed to update: '$(yellow "${folder}")'"
      else
        debug "skipping update for non-repo: '$(yellow "${folder}")'"
      fi
    done
    success 'Finished updating chrome folders'
  fi
  step_end

  step_start
  section_header "$(yellow 'Checking if any greedy applications are outdated')"
  if command_exists brew; then
    local outdated
    # 'bcg' alias (brew outdated --greedy) is not expanded in non-interactive shells (cron).
    # '|| true' prevents grep -v from triggering the ERR trap when all lines are filtered out
    # (grep -v exits 1 when no lines pass the filter).
    outdated="$(brew outdated --greedy | \grep -v -iE 'homebrew|Downloading' || true)"
    # warn (not error): outdated software needs manual attention but is not a script failure.
    # error() returns 1 and would trigger the ERR trap, firing a spurious "Software updates failed"
    # notification. Instead, warn to the terminal and notify explicitly with the plain-text list.
    if is_non_zero_string "${outdated}"; then
      warn "Found some outdated softwares that need manual updating: $(yellow "${outdated}")"
      # Replace newlines with ', ' — osascript notification cannot span multiple lines.
      # Stored in main-scoped outdated_flat so the final summary notification can include it.
      outdated_flat="${outdated//$'\n'/, }"
    fi
  else
    debug 'skipping updating brews & casks'
  fi
  step_end

  # Compute duration using format_duration from .shellrc (already sourced via .aliases).
  local _now _duration_human
  current_timestamp _now
  local _duration=$((EPOCHSECONDS - script_start_time))
  format_duration "${_duration}" _duration_human

  success "Finished software updates at $(purple "${_now}") in $(light_blue "${_duration_human}")"
  # Include outdated packages in the final notification if any were found, so the
  # notification is not immediately replaced by a subsequent one before it is seen.
  if is_non_zero_string "${outdated_flat}"; then
    _dotfiles_notify "Done (${_duration_human}). Needs manual update: ${outdated_flat}" "⚠️ Software Updates" || true
  else
    _dotfiles_notify "All updates finished at ${_now} (took ${_duration_human})." "✅ Software Updates Done" || true
  fi
  print_script_duration "${script_start_time}"
}

main "$@"
