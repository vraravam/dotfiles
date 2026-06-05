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
    # Update section tracker before running so _record_warning can include it in the summary.
    # No 'local' here: intentionally modifies _current_section declared in main via
    # zsh dynamic scoping.
    _current_section="${title}"
    step_start
    section_header "$(yellow 'Updating') $(purple "${title}")"
    if eval "${update_cmd}"; then
      success "Successfully updated: '${title}'"
    else
      # Tool update failures are warnings — the tool is still usable; only the upgrade failed.
      _record_warning "Failed to update '${title}'"
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

  # Two separate accumulator arrays for non-fatal step issues:
  #   _step_warnings — recoverable tool-level failures (e.g. a brew/mise/tldr update step failed)
  #   _step_errors   — significant infrastructure failures (e.g. repo pull, capture-prefs, size limit)
  # _record_warning/_record_error/print_script_summary (all from .shellrc via .aliases) read/write
  # these via zsh dynamic scoping — locals declared here are visible in all callees.
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  trap '_decrement_script_depth' EXIT
  # ERR trap: collect unexpected failures into _step_errors instead of notifying immediately.
  # A single grouped notification is sent at the end of main once all steps have run.
  trap '_record_error "Unexpected failure at line ${LINENO} (exit ${?})"' ERR

  # Capture start epoch into both a local variable and _script_start_times.
  # The local is passed explicitly to print_script_summary at the end of main.
  # _script_start_times is used by step_end (called throughout this script via
  # _perform_update) to compute the "total elapsed" column independently of the
  # local variable.  Both are required; see the design note above
  # step_timing_init in .shellrc.
  local script_start_time
  script_start_time="${EPOCHSECONDS}"
  _script_start_times+=("${script_start_time}")
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
  _current_section='antidote plugins'
  step_start
  section_header "$(yellow 'Updating') $(purple 'antidote plugins') and regenerating plugin bundle"
  update_antidote_and_regenerate_plugin_bundle
  step_end

  # Update bat cache
  if command_exists bat; then
    _current_section='bat cache'
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

  # Disabled: rapidfox user.js replaces betterfox for the Zen profile
  # local zen_profiles="${PERSONAL_PROFILES_DIR}/ZenProfile/Profiles/DefaultProfile"
  # if is_directory "${zen_profiles}"; then
  #   section_header "$(yellow 'Update betterfox user.js') in $(purple "${zen_profiles}")"
  #   curl --retry 3 --retry-delay 5 -fsSL https://raw.githubusercontent.com/yokoffing/Betterfox/main/zen/user.js -o "${zen_profiles}/user.js" && success "Updated betterzen user.js" || warn "Failed to update betterzen user.js"
  # else
  #   debug "Skipping betterzen user.js update, directory not found: ${zen_profiles}"
  # fi

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
    _current_section='zen-browser-desktop tag cleanup'
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
    _current_section='Update repos in home folder'
    step_start
    section_header "$(yellow 'Update non-keybase repos in home folder')"
    # Aliases ('home', 'rug') are not expanded in non-interactive shells (e.g. cron).
    # Use the equivalent direct invocation instead of the 'home pull' alias.
    # run-all.sh records a warning (not an error) per failing repo: a dirty skip is
    # an expected state in a personal repo, not a script failure.
    FOLDER="${HOME}" FILTER='.bin|zsh|mise' MAXDEPTH=5 run-all.sh git pull-safe || _record_warning 'Some home repos could not be auto-updated — working tree may be dirty. Rebase manually.'
    step_end

    sleep 10  # so that GH doesn't throttle when we call a lot of times within a short time

    _current_section='Upreb repos in oss folder'
    step_start
    section_header "$(yellow 'Upreb repos in oss folder')"
    # Aliases ('oss', 'rug') are not expanded in non-interactive shells (e.g. cron).
    # Use the equivalent direct invocation instead of the 'oss upreb' alias.
    # 'git upreb' now aborts early if the working tree is dirty rather than failing mid-workflow
    # (after fetch+rebase but before push). A dirty skip exits non-zero so run-all.sh records
    # a per-repo warning. Not _record_error: a dirty skip is expected, not a script failure.
    FOLDER="${PROJECTS_BASE_DIR}/oss" MAXDEPTH=4 run-all.sh git upreb && success 'Finished upreb for oss repos' || _record_warning 'Some oss repos could not be auto-updated — working tree may be dirty. Run upreb manually.'
    step_end

    _current_section='Restore mtime and register for maintenance'
    step_start
    section_header "$(yellow 'Restoring mtime and registering for maintenance operations')"
    # Aliases ('all', 'rug') are not expanded in non-interactive shells (e.g. cron).
    # Use the equivalent direct invocation instead of the 'all' alias.
    FOLDER="${HOME}" MAXDEPTH=7 run-all.sh git restore-mtime -c
    FOLDER="${HOME}" MAXDEPTH=7 run-all.sh git maintenance register --config-file "${HOME}/.gitconfig-oss.inc"
    FOLDER="${HOME}" MAXDEPTH=7 run-all.sh git maintenance start
    step_end
  fi

  # Collect repo ancestor dirs once and share across both post-clone operations
  # to avoid running the expensive find traversal twice.
  local -a all_dirs
  _collect_repo_ancestor_dirs
  _SHARED_REPO_DIRS=("${all_dirs[@]}")

  _current_section='Allow all direnv configs'
  step_start
  section_header "$(yellow 'Allow all direnv configs')"
  allow_all_direnv_configs
  step_end

  _current_section='Install languages using mise'
  step_start
  section_header "$(yellow 'Install languages using mise')"
  install_mise_versions
  step_end

  unset _SHARED_REPO_DIRS

  _current_section='Regenerate repo aliases'
  step_start
  section_header "$(yellow 'Regenerate repo aliases')"
  regenerate_repo_aliases
  step_end

  _current_section='Capture app preferences'
  step_start
  section_header "$(yellow 'Capture app preferences')"
  capture-prefs.sh -e && success 'Finished capturing app preferences' || _record_error 'Failed to capture app preferences'
  step_end

  _current_section='Prune old session backups'
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

  _current_section='Check profiles repo size'
  step_start
  section_header "$(yellow 'Check profiles repo size')"
  if is_git_repo "${PERSONAL_PROFILES_DIR}"; then
    local profiles_size_kb
    profiles_size_kb=$(du -sk "${PERSONAL_PROFILES_DIR}" 2>/dev/null | awk '{print $1}')
    local profiles_size_limit_kb=$((2 * 1024 * 1024))  # 2 GB
    if ((profiles_size_kb > profiles_size_limit_kb)); then
      local profiles_size_human
      profiles_size_human=$(du -sh "${PERSONAL_PROFILES_DIR}" 2>/dev/null | awk '{print $1}')
      # _record_error instead of error(): error() calls _dotfiles_notify() which would
      # send an immediate notification before the grouped summary at the end of main.
      _record_error "Profiles repo is ${profiles_size_human} — exceeds 2GB threshold. Consider running: recreate-repo.sh -d \"${PERSONAL_PROFILES_DIR}\""
    else
      debug "Profiles repo size within 2GB threshold"
    fi
  fi
  step_end

  _current_section='Update home and profiles repos'
  step_start
  section_header "$(yellow 'Update home and profiles repos')"
  # source imports the function definition into this shell. The explicit call on
  # the next line is still required because the autoload script's zsh_eval_context
  # guard ('*:file*' match) suppresses auto-execution when sourced — it only
  # runs automatically when the file is invoked directly, not when sourced.
  source "${XDG_CONFIG_HOME}/zsh/update_all_repos"
  update_all_repos && success 'Finished updating home and profiles repos' || _record_error 'Failed to update home and profiles repos'
  step_end

  _current_section='Report status of all repos'
  step_start
  section_header "$(yellow 'Report status of all repos')"
  # source imports the function definition into this shell. The explicit call on
  # the next line is still required because the autoload script's zsh_eval_context
  # guard ('*:file*' match) suppresses auto-execution when sourced — it only
  # runs automatically when the file is invoked directly, not when sourced.
  source "${XDG_CONFIG_HOME}/zsh/status_all_repos"
  status_all_repos || true
  step_end

  _current_section='Update chrome folders'
  step_start
  section_header "$(yellow 'Updating all browser profile chrome folders if they are git repos')"
  # Inline (N/) glob qualifiers break editor syntax highlighting (parsed as function calls).
  # Use localoptions NULL_GLOB in an anonymous function so unmatched globs expand to
  # nothing instead of erroring. The trailing / restricts matches to directories.
  local -a chrome_folders
  () {
    setopt localoptions NULL_GLOB
    chrome_folders=("${PERSONAL_PROFILES_DIR}"/*Profile/Profiles/DefaultProfile/chrome/)
  }
  if is_non_empty_array chrome_folders; then
    for folder in "${chrome_folders[@]}"; do
      if is_git_repo "${folder}"; then
        section_header2 "$(yellow 'Updating chrome folder:') $(purple "${folder}")"
        # Chrome folder update failures are warnings — CSS customisation is non-critical.
        git -C "${folder}" pull -r && success "Successfully updated: '$(yellow "${folder}")'" || _record_warning "Failed to update chrome folder: '${folder}'"
      else
        debug "skipping update for non-repo: '$(yellow "${folder}")'"
      fi
    done
    success 'Finished updating chrome folders'
  fi
  step_end

  _current_section='Check for outdated applications'
  step_start
  section_header "$(yellow 'Checking if any greedy applications are outdated')"
  if command_exists brew; then
    local outdated
    # 'bcg' alias (brew outdated --greedy) is not expanded in non-interactive shells (cron).
    # '|| true' prevents grep -v from triggering the ERR trap when all lines are filtered out
    # (grep -v exits 1 when no lines pass the filter).
    outdated="$(brew outdated --greedy | \grep -v -iE 'homebrew|Downloading' || true)"
    # warn (not _record_warning): outdated software is an advisory notice, not a step failure.
    # It is surfaced in the final notification separately via outdated_flat.
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

  # Print grouped summary of all collected warnings and errors (warnings first,
  # then errors), print duration, then send exactly one notification regardless
  # of how many steps had issues.
  print_script_summary "${script_start_time}" 'Finished software updates'
  local _notification_parts=()
  if is_non_empty_array _step_errors; then
    local _errors_summary
    # Join with '; ' for the notification body — osascript cannot span multiple lines.
    _errors_summary="${(j:; :)_step_errors}"
    _notification_parts+=("${#_step_errors[@]} error(s): ${_errors_summary}")
  fi
  if is_non_empty_array _step_warnings; then
    local _warnings_summary
    _warnings_summary="${(j:; :)_step_warnings}"
    _notification_parts+=("${#_step_warnings[@]} warning(s): ${_warnings_summary}")
  fi
  # Build notification message and title, then append outdated packages if any.
  local _msg _title_icon
  if is_non_empty_array _notification_parts; then
    _title_icon='⚠️'
    _msg=" — ${(j: | :)_notification_parts}"
  else
    _title_icon='✅'
    _msg="."
  fi
  # Escalate icon to ⚠️ when outdated packages need manual attention, even if
  # there were no errors or warnings. Yellow = action required; not an error.
  # Explicit if avoids firing the ERR trap when outdated_flat is empty (clean run).
  if is_non_zero_string "${outdated_flat}"; then
    _title_icon='⚠️'
    _msg+=". Needs manual update: ${outdated_flat}"
  fi

  # Compute duration using format_duration from .shellrc (already sourced via .aliases).
  local _now _duration_human _duration
  current_timestamp _now
  _duration=$((EPOCHSECONDS - script_start_time))
  format_duration "${_duration}" _duration_human

  _dotfiles_notify "Done at ${_now} (took ${_duration_human})${_msg}" "${_title_icon} Software Updates" || true
}

main "$@"
