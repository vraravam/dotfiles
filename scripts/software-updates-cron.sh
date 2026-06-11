#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to run the update steps in sequence.
# These are commands that need to be periodically run to upgrade any installed softwares.
# Rather than remembering each tool and its specific command invocation, this script comes handy.

# Do not exit immediately if a command exits with a non-zero status since this is run within a cronjob

_SCRIPT_NAME="${0:t}"

# Re-source guard is inside .aliases itself -- safe to call unconditionally.
source "${HOME}/.aliases"

# Run a single update step if the check command is available
_perform_update() {
  local title="${1:?_perform_update: title required}"
  local check_cmd="${2:?_perform_update: check_cmd required}"
  local update_cmd="${3:?_perform_update: update_cmd required}"

  if command_exists "${check_cmd}"; then
    # Update section tracker before running so _record_warning can include it in the summary.
    # No 'local' here: intentionally modifies _current_section declared in main via
    # zsh dynamic scoping.
    _current_section="${title}"
    step_start
    section_header "$(yellow 'Updating') $(purple "${title}")"
    if eval "${update_cmd}"; then
      success "Successfully updated: '$(yellow "${title}")'"
    else
      # Tool update failures are warnings -- the tool is still usable; only the upgrade failed.
      _record_warning "Failed to update '$(yellow "${title}")'"
    fi
    step_end
  else
    debug "Command not found: '$(cyan "${check_cmd}")'"
  fi
}

main() {
  # LOCAL_TRAPS scopes the ERR trap to main() only -- it is not inherited into called
  # functions. Without this, non-zero exits inside called functions (e.g. git sci
  # finding nothing to commit, st warning about a missing repo) fire the trap even
  # when the call site has '|| warn' or '|| true'.
  setopt LOCAL_TRAPS

  # Two separate accumulator arrays for non-fatal step issues:
  #   _step_warnings -- recoverable tool-level failures (e.g. a brew/mise/tldr update step failed)
  #   _step_errors   -- significant infrastructure failures (e.g. repo pull, capture-prefs, size limit)
  # _record_warning/_record_error/print_script_summary (all from .shellrc via .aliases) read/write
  # these via zsh dynamic scoping -- locals declared here are visible in all callees.
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
  local tracked_file f outdated_flat=''
  print_script_start

  # brew doctor is skipped -- too slow for cron jobs
  _perform_update 'brews' 'brew' 'brew bundle check || brew bundle'

  # This is typically run only in the ${HOME} dir so as to upgrade the software versions in the "global" sense
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

  if command_exists run-all.rb; then
    _current_section='Update repos in home dir'
    step_start
    section_header "$(yellow 'Update non-keybase repos in home dir')"
    # Aliases ('home', 'rug') are not expanded in non-interactive shells (e.g. cron).
    # Use the equivalent direct invocation instead of the 'home pull' alias.
    # run-all.rb records a warning (not an error) per failing repo: a dirty skip is
    # an expected state in a personal repo, not a script failure.
    FOLDER="${HOME}" FILTER='.bin|zsh|mise' MAXDEPTH=5 run-all.rb git pull-safe || _record_warning 'Some home repos could not be auto-updated -- working tree may be dirty. Rebase manually.'
    step_end

    sleep 10 # so that GH doesn't throttle when we call a lot of times within a short time

    _current_section='Upreb repos in oss dir'
    step_start
    section_header "$(yellow 'Upreb repos in oss dir')"
    # Aliases ('oss', 'rug') are not expanded in non-interactive shells (e.g. cron).
    # Use the equivalent direct invocation instead of the 'oss upreb' alias.
    # 'git upreb' now aborts early if the working tree is dirty rather than failing mid-workflow
    # (after fetch+rebase but before push). A dirty skip exits non-zero so run-all.rb records
    # a per-repo warning. Not _record_error: a dirty skip is expected, not a script failure.
    FOLDER="${PROJECTS_BASE_DIR}/oss" MAXDEPTH=4 run-all.rb git upreb && success 'Finished upreb for oss repos' || _record_warning 'Some oss repos could not be auto-updated -- working tree may be dirty. Run upreb manually.'
    step_end

    _current_section='Restore mtime and register for maintenance'
    step_start
    section_header "$(yellow 'Restoring mtime and registering for maintenance operations')"
    # Aliases ('all', 'rug') are not expanded in non-interactive shells (e.g. cron).
    # Use the equivalent direct invocation instead of the 'all' alias.
    FOLDER="${HOME}" MAXDEPTH=7 run-all.rb 'git restore-mtime -c'
    FOLDER="${HOME}" MAXDEPTH=7 run-all.rb "git maintenance register --config-file '${HOME}/.gitconfig-oss.inc'"
    FOLDER="${HOME}" MAXDEPTH=7 run-all.rb 'git maintenance start'
    step_end
  fi

  _current_section='Setup dev environment (direnv + mise)'
  step_start
  section_header "$(yellow 'Setup dev environment') (direnv + mise)"
  # Use batched setup_dev_environment to collect ancestor dirs once instead of
  # twice (saves 200-500ms by avoiding redundant filesystem traversal).
  setup_dev_environment
  step_end

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
        git -C "${PERSONAL_PROFILES_DIR}" rm --cached -q -- "${f}" && debug "Unpinned old session backup: '$(cyan "${f}")'"
      done
      success "Pruned ${#old_backups[@]} session backup file(s) older than 7 days"
    else
      debug 'No old session backups to prune'
    fi
  else
    debug "Skipping session backup pruning -- not a git repo: '$(yellow "${PERSONAL_PROFILES_DIR}")'"
  fi
  step_end

  _current_section='Check profiles repo size'
  step_start
  section_header "$(yellow 'Check profiles repo size')"
  if is_git_repo "${PERSONAL_PROFILES_DIR}"; then
    # Check .git directory size, not total directory (working tree can be large)
    local du_out size_actual_kb
    du_out="$(\du -sk "${PERSONAL_PROFILES_DIR}/.git" 2>/dev/null)"
    size_actual_kb="${du_out%%$'\t'*}"  # Extract before tab (no awk fork)
    local size_threshold_kb=$((2 * 1024 * 1024))  # 2 GB
    if ((size_actual_kb > size_threshold_kb)); then
      local size_actual_human
      du_out="$(\du -sh "${PERSONAL_PROFILES_DIR}/.git" 2>/dev/null)"
      size_actual_human="${du_out%%$'\t'*}"  # Extract before tab (no awk fork)
      # _record_error instead of error(): error() calls _dotfiles_notify() which would
      # send an immediate notification before the grouped summary at the end of main.
      _record_error "Profiles repo directory is ${size_actual_human} -- exceeds 2GB threshold. Consider running: recreate-repo.rb -d \"${PERSONAL_PROFILES_DIR}\""
    else
      debug "Profiles repo directory size within 2GB threshold"
    fi
  fi
  step_end

  _current_section='Update home and profiles repos'
  step_start
  section_header "$(yellow 'Update home and profiles repos')"
  # source imports the function definition into this shell. The explicit call on
  # the next line is still required because the autoload script's zsh_eval_context
  # guard ('*:file*' match) suppresses auto-execution when sourced -- it only
  # runs automatically when the file is invoked directly, not when sourced.
  source "${XDG_CONFIG_HOME}/zsh/update_all_repos"
  update_all_repos && success 'Finished updating home and profiles repos' || _record_error 'Failed to update home and profiles repos'
  step_end

  _current_section='Report status of all repos'
  step_start
  section_header "$(yellow 'Report status of all repos')"
  # source imports the function definition into this shell. The explicit call on
  # the next line is still required because the autoload script's zsh_eval_context
  # guard ('*:file*' match) suppresses auto-execution when sourced -- it only
  # runs automatically when the file is invoked directly, not when sourced.
  source "${XDG_CONFIG_HOME}/zsh/status_all_repos"
  status_all_repos || true
  step_end

  _current_section='Update chrome dirs'
  step_start
  section_header "$(yellow 'Updating all browser profile chrome dirs if they are git repos')"
  # Inline (N/) glob qualifiers break editor syntax highlighting (parsed as function calls).
  # Use localoptions NULL_GLOB in an anonymous function so unmatched globs expand to
  # nothing instead of erroring. The trailing / restricts matches to directories.
  local -a chrome_dirs
  () {
    setopt localoptions NULL_GLOB
    chrome_dirs=("${PERSONAL_PROFILES_DIR}"/*Profile/Profiles/DefaultProfile/chrome/)
  }
  if is_non_empty_array chrome_dirs; then
    for dir in "${chrome_dirs[@]}"; do
      if is_git_repo "${dir}"; then
        section_header2 "$(yellow 'Updating chrome dir:') $(cyan "${dir}")"
        # Chrome dir update failures are warnings -- CSS customisation is non-critical.
        git -C "${dir}" pull -r && success "Successfully updated: '$(cyan "${dir}")'" || _record_warning "Failed to update chrome dir: '$(cyan "${dir}")'"
      else
        debug "skipping update for non-repo: '$(yellow "${dir}")'"
      fi
    done
    success 'Finished updating chrome dirs'
  fi
  step_end

  if command_exists brew; then
    _current_section='Check for outdated brew and brew applications'
    step_start
    section_header "$(yellow 'Check for outdated brew and brew applications')"

    step_start
    _current_section='Updating brew'
    section_header2 "$(yellow 'Updating brew')"
    brew update || true
    step_end

    step_start
    _current_section='Updating brew applications'
    section_header2 "$(yellow 'Updating brew applications')"
    local outdated
    # 'bcg' alias (brew outdated --greedy) is not expanded in non-interactive shells (cron).
    # '|| true' prevents grep -v from triggering the ERR trap when all lines are filtered out
    # (grep -v exits 1 when no lines pass the filter).
    outdated="$(brew outdated --greedy | \grep -v -iE 'homebrew|Downloading' || true)"
    # warn (not _record_warning): outdated software is an advisory notice, not a step failure.
    # It is surfaced in the final notification separately via outdated_flat.
    if is_non_zero_string "${outdated}"; then
      warn "Found some outdated softwares that need manual updating: '$(yellow "${outdated}")'"
      # Replace newlines with ', ' -- osascript notification cannot span multiple lines.
      # Stored in main-scoped outdated_flat so the final summary notification can include it.
      outdated_flat="${outdated//$'\n'/, }"
    fi
    step_end
  else
    debug 'skipping updating brews & casks'
  fi
  step_end

  # TODO: Similar to ollama, need to update the models used by omlx via cli
  if command_exists ollama; then
    _current_section='Pull ollama models'
    step_start
    section_header "$(yellow 'Pull ollama models')"
    # reference: https://insiderllm.com/guides/ollama-mac-setup-optimization/
    # reference: https://popularaitools.ai/blog/run-gemma-4-locally-opencode-2026
    # Note: This list is up-to-date as of 2026-06-06
    local -a ollama_models=(
      # deepseek-coder-v2
      # gpt-oss:20b
      # qwen3.5:9b-q8_0 # Qwen 3.5 9B (Q8): strong reasoning model
      qwen2.5-coder:14b # Qwen 2.5 Coder 14B: strong coding model
      gemma3:12b        # Gemma 3 12B: free coding model
      # gemma4:26b        # Gemma 4 26B: free coding model
      # codestral:22b     # TODO: Need to research
    )
    local model
    for model in "${ollama_models[@]}"; do
      ollama pull "${model}" && success "Pulled model: '$(yellow "${model}")'" || _record_warning "Failed to pull model: '$(yellow "${model}")'"
    done
    step_end
  else
    debug 'ollama not found -- skipping model pulls'
  fi

  # Print grouped summary of all collected warnings and errors (warnings first,
  # then errors), print duration, then send exactly one notification regardless
  # of how many steps had issues.
  print_script_summary "${script_start_time}" 'Finished software updates'
  local _notification_parts=()
  if is_non_empty_array _step_errors; then
    local _errors_summary
    # Join with '; ' for the notification body -- osascript cannot span multiple lines.
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
    _msg=" -- ${(j: | :)_notification_parts}"
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
