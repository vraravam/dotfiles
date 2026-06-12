#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# file location: <anywhere; but advisable in the PATH>

# This script will export or import the settings from the location specified in the target directory defined down below. You can backup the files to any cloud storage and retrieve into the new laptop to then get back all settings as per the original machine. The only word of caution is to use it with the same OS version (I haven't tried in any situations where the old and new machines had different OS versions - so I cannot guarantee if that might break the system in any way)

# A utility function to find the name of the app:
# Run `find_and_append_prefs` and pass in a substring contained in the name of the preference that you want to add. This will automatically add it (if not already present) into the appropriate allowed-list file.
# Explanation: This runs the `defaults find` command and searches for any match, then it traces back to the left-most child (1st of the top-level parent) in the printed JSON to then get the real unique name of the app where its settings are stored and adds it to the file mentioned above.

set -euo pipefail

_SCRIPT_NAME="${0:t}"
source "${HOME}/.aliases"

# Associative array populated in main(); read by _strip_excluded_keys.
# Keyed by domain name; value is newline-separated list of key patterns for
# that domain. Declared at script scope so the helper function can access it
# without needing it passed as a parameter (zsh does not support passing
# associative arrays by value).
typeset -A _excluded_by_domain=()

usage() {
  print_usage "${_SCRIPT_NAME}" \
    "$(yellow '-e') --> (mandatory; mutually exclusive with -i) Export preferences from the current [old] system into the dotfiles repo" \
    "$(yellow '-i') --> (mandatory; mutually exclusive with -e) Import preferences from the dotfiles repo into the current [new] system"
}

# Builds and emits a single user_action listing every running user-visible app
# that needs to be quit and restarted to pick up the just-imported preferences.
# Only user-specified apps are considered. Login-item apps (_MACOS_LOGIN_ITEM_APPS)
# are excluded because kill/restart_login_item_apps already handles them.
# Process names (left-hand keys) are what pgrep -x matches against; display names
# (right-hand values) are what appears in the message. They differ only where the
# bundle executable name does not match the app's marketed name (e.g. zoom.us → Zoom).
_notify_apps_needing_restart() {
  local -A _proc_to_name=(
    ['Ghostty']='Ghostty'
    ['iTerm2']='iTerm2'
    ['Terminal']='Terminal'
  )

  local -a _running=()
  local _proc _name
  for _proc _name in "${(@kv)_proc_to_name}"; do
    # Skip login-item apps (auto-killed and restarted) and apps not currently running.
    if (( ! ${_MACOS_LOGIN_ITEM_APPS[(Ie)${_name}]} )) && pgrep -xq "${_proc}" 2>/dev/null; then
      _running+=("${_name}")
    fi
  done

  if is_non_empty_array _running; then
    _running=("${(o)_running[@]}")
    user_action "Quit and restart to pick up imported preferences: $(join_array _running)."
  fi
}

# Strip non-portable keys from a plist file in-place.
# Reads patterns from _excluded_by_domain (script-scoped associative array).
# Uses ruby/REXML to enumerate top-level keys (handles keys with spaces safely
# via null-byte separation) and PlistBuddy to delete matched keys.
# Individual key deletions are non-fatal -- a missing key is silently skipped.
_strip_excluded_keys() {
  local domain="${1:?_strip_excluded_keys: domain required}"
  local plist_file="${2:?_strip_excluded_keys: plist_file required}"

  # Merge domain-specific patterns with global '*' patterns (applied to every domain).
  # Use (e) subscript flag for exact key lookup -- without it, [*] and [${var}] where
  # var='*' expand to all associative array values instead of the literal '*' key.
  local _combined=''
  if is_non_zero_string "${_excluded_by_domain[(e)${domain}]:-}"; then
    _combined="${_excluded_by_domain[(e)${domain}]}"
  fi
  # Use ['*'] literal here -- (e) flag and quoted literal are both correct;
  # prefer the quoted literal form for clarity when the key is a constant.
   if is_non_zero_string "${_excluded_by_domain['*']:-}"; then
     if is_non_zero_string "${_combined}"; then
       _combined+=$'\n'"${_excluded_by_domain['*']}"
     else
       _combined="${_excluded_by_domain['*']}"
     fi
   fi
  # No patterns for this domain (neither specific nor global) -- nothing to strip.
  if is_zero_string "${_combined}"; then return 0; fi

  local -a patterns=("${(@f)_combined}")
  if is_empty_array patterns; then return 0; fi

  # Single Ruby/REXML pass: enumerate top-level keys and delete matched key-value
  # pairs. Two independent match conditions, either of which triggers deletion:
  #   1. Key name matches a shell glob pattern (File.fnmatch, '*' matches '/' and ':').
  #   2. The value element immediately following the key is a plist <date> node.
  #      Any top-level key whose value is a plist date is inherently ephemeral
  #      (ISO 8601 timestamp written by the OS/app) -- never a portable user pref.
  #      This catches date-valued keys regardless of their name, providing a
  #      type-based safety net complementary to the name-pattern list.
  # File.fnmatch without FNM_PATHNAME allows '*' to match '/' and ':',
  # matching zsh's [[ == ]] glob behaviour for these characters.
  # PlistBuddy is intentionally not used for deletion: it treats ':' as a path
  # separator in its key-path syntax, so keys whose names contain ':' (e.g.
  # _DKThrottledActivityLast_...:/app/mediaUsageActivityDate) are misinterpreted
  # as nested dict paths and silently not deleted.
  # System Ruby (2.6+) is always available on macOS -- no Homebrew dependency.
  /usr/bin/ruby -e '
    require "rexml/document"
    plist_file = ARGV.shift
    patterns   = ARGV
    doc  = REXML::Document.new(File.read(plist_file)) rescue exit(0)
    dict = doc.root.elements["dict"]
    exit 0 unless dict
    modified = false
    loop do
      children = dict.to_a.select { |e| e.is_a?(REXML::Element) }
      hit = children.each_with_index.find { |e, idx|
        next unless e.name == "key"
        value = children[idx + 1]
        patterns.any? { |p| File.fnmatch(p, e.text.to_s) } || (value && value.name == "date")
      }
      break unless hit
      el, idx = hit
      dict.delete_element(el)
      dict.delete_element(children[idx + 1]) if children[idx + 1]
      modified = true
    end
    exit 0 unless modified
    File.write(plist_file, doc.to_s)
  ' "${plist_file}" "${patterns[@]}" 2>/dev/null || true
  # Re-normalise to Apple XML plist format: REXML may alter whitespace and the
  # DOCTYPE/XML declaration compared to plutil's canonical output.
  plutil -convert xml1 "${plist_file}" 2>/dev/null || true
}

main() {
  local operation=''
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  local _saved_count=0
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  # Minimal trap ensures depth is restored on early-return paths (arg-parse
  # failures, missing env vars) before the full EXIT trap is registered below.
  trap '_decrement_script_depth' EXIT
  while getopts ":ei" opt; do
    case ${opt} in
      e)
        operation='export'
        ;;
      i)
        operation='import'
        ;;
      \?)
        warn "-${OPTARG} is not a valid option"
        usage
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if is_zero_string "${operation}"; then
    warn "Missing required arguments/switches"
    usage
    return 1
  fi

  if is_zero_string "${PERSONAL_CONFIGS_DIR}"; then
    _record_error "Required env var '$(purple 'PERSONAL_CONFIGS_DIR')' is not defined."
    print_script_summary
    return 1
  fi
  if is_zero_string "${DOTFILES_DIR}"; then
    _record_error "Required env var '$(purple 'DOTFILES_DIR')' is not defined."
    print_script_summary
    return 1
  fi

  local script_start_time="${EPOCHSECONDS}"
  print_script_start

  local target_dir="${PERSONAL_CONFIGS_DIR}/defaults"
  ensure_dir_exists "${target_dir}"

  # Kill/restart login-item apps on import only, and only when running interactively.
  # On import, apps must be stopped before writing so they cannot overwrite imported
  # values when they quit. Cron skips this -- killall would disrupt the user's running
  # session, and 'open -a' would re-launch apps mid-session. On export, macOS cfprefsd
  # has already flushed current prefs to disk; killing apps is unnecessary.
  # The canonical app list lives in _MACOS_LOGIN_ITEM_APPS (.aliases § 3n).
  # is_running_in_tty returns true when stdout is a TTY or FORCE_COLOR is set.
   if [[ "${operation}" == 'import' ]] && is_running_in_tty; then
     kill_login_item_apps
     trap 'restart_login_item_apps; resume_softwareupdate_schedule; _decrement_script_depth' EXIT
   else
     trap 'resume_softwareupdate_schedule; _decrement_script_depth' EXIT
   fi

  # Suspend the automatic software update schedule so background update
  # activity cannot interfere with plist reads/writes during export or import.
  # resume_softwareupdate_schedule is called from the EXIT trap above, covering
  # both normal and error exits. Both functions guard with sudo -n (no prompt).
  suspend_softwareupdate_schedule

  if [[ "${operation}" == 'export' ]]; then
    # Clean up old files before exporting new ones (this also handles the case where some entry has been removed from the list of domains).
    # .defaults files are from a past version of this script that used a different extension -- delete them too.
    # NULL_GLOB scoped to an anonymous function: expands unmatched patterns to nothing
    # rather than erroring. Inline (N) qualifiers confuse editor syntax highlighters
    # (they parse the qualifier as a function call, breaking highlighting for the rest
    # of the line). setopt localoptions restricts the change to this anonymous function.
    () {
      setopt localoptions NULL_GLOB
      rm -f "${target_dir}"/*.plist "${target_dir}"/.plist "${target_dir}"/*.defaults
    }
  fi

  if [[ "${operation}" == 'import' ]]; then
    # Warn if the backup predates the last change to osx-defaults.sh. When
    # osx-defaults.sh has been updated since the backup was taken, the backup
    # may be missing settings that were added in that update -- importing it
    # would silently leave those new settings unset.
    # Both repos (dotfiles and personal configs) must be git repos for this
    # check to work. git log --format=%ct returns the Unix timestamp of the
    # most recent commit touching the file/directory.
    local _osx_defaults_ts _backup_ts
    _osx_defaults_ts="$(git -C "${DOTFILES_DIR}" log --format='%ct' -n1 -- 'scripts/osx-defaults.sh' 2>/dev/null || true)"
    _backup_ts="$(git -C "${HOME}" log --format='%ct' -n1 -- "${target_dir}" 2>/dev/null || true)"
    if is_non_zero_string "${_osx_defaults_ts}" && is_non_zero_string "${_backup_ts}"; then
      if (( _backup_ts < _osx_defaults_ts )); then
        warn "Backup predates the last change to osx-defaults.sh -- some settings added since the backup may not be present."
        warn "Consider running 'osx-defaults.sh -s' followed by 'capture-prefs.sh -e' on the source machine to refresh the backup first."
      fi
    fi
  fi

  # Note: A simple trick to find these names is to run `\ls -1 ~/Library/Preferences/*` in the command-line
  # Read domains from the file into the array, splitting by newline and filtering comments/blanks
  # Define the location of the domains list
  local domains_file="${DOTFILES_DIR}/scripts/data/capture-prefs-allowed-list.txt"
  if ! is_file "${domains_file}"; then
    _record_error "Domains list file not found: '$(cyan "${domains_file}")'"
    print_script_summary "${script_start_time}"
    return 1
  fi

  local denied_list_file="${DOTFILES_DIR}/scripts/data/capture-prefs-denied-list.txt"
  if ! is_file "${denied_list_file}"; then
    _record_error "Denied list file not found: '$(cyan "${denied_list_file}")'"
    print_script_summary "${script_start_time}"
    return 1
  fi

  local excluded_keys_file="${DOTFILES_DIR}/scripts/data/capture-prefs-excluded-keys.txt"
  if ! is_file "${excluded_keys_file}"; then
    _record_error "Excluded keys file not found: '$(cyan "${excluded_keys_file}")'"
    print_script_summary "${script_start_time}"
    return 1
  fi

  # Load denied list into an associative array for O(1) lookups.
  # while+read: no subprocess fork; is_blank_or_comment_line skips comments and blanks.
  typeset -A _denied=()
  local _bl_line
  while IFS= read -r _bl_line; do
    if is_blank_or_comment_line "${_bl_line}"; then continue; fi
    _denied["${_bl_line}"]=1
  done <"${denied_list_file}"

  # Load excluded-keys file into the script-scoped _excluded_by_domain map.
  # Format: <domain>|<key-or-glob-pattern> -- one entry per line.
  # Value is newline-separated patterns; consumed by _strip_excluded_keys.
  local _ex_line _ex_dom _ex_pat
  while IFS= read -r _ex_line; do
    if is_blank_or_comment_line "${_ex_line}"; then continue; fi
    _ex_dom="${_ex_line%%|*}"
    _ex_pat="${_ex_line#*|}"
     # zsh's subscript glob-expansion makes ["${var}"] and ['*'] write to different
     # slots when var='*'. The read path in _strip_excluded_keys uses ['*'] (single-
     # quoted literal), so writes to the '*' domain must use the same literal form.
     # Non-'*' domains use (e) flag for exact match on both read and write to prevent
     # a hypothetical domain name containing glob chars from expanding unexpectedly.
     if [[ "${_ex_dom}" == '*' ]]; then
       if is_non_zero_string "${_excluded_by_domain['*']:-}"; then
         _excluded_by_domain['*']+=$'\n'"${_ex_pat}"
       else
         _excluded_by_domain['*']="${_ex_pat}"
       fi
     else
       if is_non_zero_string "${_excluded_by_domain[(e)${_ex_dom}]:-}"; then
         _excluded_by_domain[(e)${_ex_dom}]+=$'\n'"${_ex_pat}"
       else
         _excluded_by_domain[(e)${_ex_dom}]="${_ex_pat}"
       fi
     fi
  done <"${excluded_keys_file}"

  local -a app_array=()
  local _line
  # while+read replaces $("${(@f)$(grep -vE ...)}"): no grep subprocess fork.
  # is_blank_or_comment_line skips comment lines and blank lines.
  while IFS= read -r _line; do
    if is_blank_or_comment_line "${_line}"; then continue; fi
    app_array+=("${_line}")
  done <"${domains_file}"
  if is_empty_array app_array; then
    info "No domains found in '$(cyan "${domains_file}")' -- nothing to do."
    return 0
  fi

  info "Running operation: '$(yellow "${operation}")'"
  local app_pref
  for app_pref in "${app_array[@]}"; do
    # Defensive guard: skip empty domain names (would produce a stale .plist file)
    if is_zero_string "${app_pref}"; then continue; fi
    # Skip domains on the denied list -- they contain machine-specific or account-bound
    # data that is meaningless or harmful when exported/imported across machines.
    if ((${+_denied[${app_pref}]})); then
      debug "Skipping denied domain '$(light_cyan "${app_pref}")' -- contains machine-specific data (see capture-prefs-denied-list.txt)"
      continue
    fi
    debug "Processing '$(light_cyan "${app_pref}")'"
    local target_file="${target_dir}/${app_pref}.plist"
    if [[ "${operation}" == 'export' ]]; then
      # Allow the loop to continue even if a specific defaults command fails
      if /usr/bin/defaults export "${app_pref}" "${target_file}"; then
        # Convert binary plist to XML for human-readable diffs in git.
        # defaults import reads XML plist natively -- no conversion needed on import.
        # JSON is not used: plutil -convert json is lossy for <data> and <date> types,
        # and defaults import cannot round-trip JSON back to plist.
        plutil -convert xml1 "${target_file}" || _record_warning "Failed to convert '$(light_cyan "${app_pref}")' to XML plist"
        # Strip non-portable keys (device UUIDs, account credentials, ephemeral
        # sync state, display geometry) before the file is staged to git.
        _strip_excluded_keys "${app_pref}" "${target_file}"
        # Delete the file if stripping left an empty dict -- an empty plist has
        # no value in git history and cannot be imported meaningfully.
        # grep -q inside 'if' is safe under set -e: 'if' consumes the exit code.
        if ! grep -q '<key>' "${target_file}" 2>/dev/null; then
          rm -f "${target_file}"
          debug "Deleted empty plist for '$(light_cyan "${app_pref}")' -- no keys remain after stripping"
        else
          (( _saved_count += 1 )) || true
        fi
      else
        _record_warning "Failed to export '$(light_cyan "${app_pref}")'"
      fi
    else
      # Skip domains for which no exported plist exists -- the app may not have
      # been installed on the source machine when the export was run.
      if ! is_file "${target_file}"; then
        debug "Skipping import of '$(light_cyan "${app_pref}")' -- no exported plist found"
        continue
      fi
      # Strip non-portable keys from a temp copy -- the source file in target_dir
      # must not be modified during import (it lives in the git repo).
      local _tmp_plist
      _tmp_plist="$(mktemp "${TMPDIR:-/tmp}/capture-prefs-XXXXXX")"
      cp "${target_file}" "${_tmp_plist}"
      _strip_excluded_keys "${app_pref}" "${_tmp_plist}"
      /usr/bin/defaults import "${app_pref}" "${_tmp_plist}" || _record_warning "Failed to import '$(light_cyan "${app_pref}")'"
      rm -f "${_tmp_plist}"
    fi
  done

  # If exporting, add the results to git staging
  # Run this *after* the loop finishes exporting all files.
  if [[ "${operation}" == 'export' ]]; then
    # Explicitly specify the git repo in the home folder, so that this script can be run from any folder
    git -C "${HOME}" add "${target_dir}" || _record_warning "Failed to git add '$(cyan "${target_dir}")'"
    success "Export complete. Staged changes in '$(cyan "${target_dir}")'."
  else
    # Reload system services so imported preferences take effect immediately
    # without a logout. The imported domains include symbolichotkeys (keyboard
    # shortcuts), controlcenter, dock, finder, and NSGlobalDomain -- all of which
    # require their owning process to be restarted to re-read the plist.
    # Restart system services that cache preferences. reload_macos_prefs
    # kills cfprefsd/Dock/Finder/SystemUIServer and calls activateSettings
    # to flush com.apple.symbolichotkeys -- see .aliases § 3n for details.
    reload_macos_prefs
    success 'System services reloaded -- most imported settings are now active.'
    _notify_apps_needing_restart
  fi
  local _saved_msg=''
  if [[ "${operation}" == 'export' ]]; then
    _saved_msg=" -- $(purple "${_saved_count}") files saved after stripping"
  fi
  success "Operation finished. Processed $(purple "${#app_array[@]}") domains (denied-list entries skipped silently)${_saved_msg}."
  print_script_summary "${script_start_time}"
}

main "$@"
