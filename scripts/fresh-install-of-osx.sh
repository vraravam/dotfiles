#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is idempotent and will restore your local setup to the same state even if run multiple times.
# In most cases, the script will provide warning messages if skipping certain steps. Each such message will be useful to give you a hint about what to do to force rerunning of that step.

# file location: <anywhere; but advisable in the PATH>

# TODO: Need to figure out the scriptable commands for the following settings:
# 1. Auto-adjust Brightness
# 2. Brightness on battery
# 3. Keyboard brightness

set -euo pipefail
# set -E ensures the ERR trap is inherited by all helper functions defined in this file,
# so _cleanup_and_exit fires even when the failure originates inside a helper function.
set -E

_SCRIPT_NAME="${0:t}"

# Error trap cleanup and exit.
# $1 = LINENO of the failing command, captured by the caller via the trap string
# ('trap "_cleanup_and_exit ${LINENO}" ERR') so that ${LINENO} expands in the
# failing command's scope rather than inside this function.
#
# NOTE: This function duplicates logic from .shellrc (print_script_summary, error,
# resume_cron) because it must handle failures that occur BEFORE .shellrc can be
# downloaded on a vanilla OS (e.g., network failures, DNS issues, curl timeouts).
# The fallback implementations ensure the script can still display collected
# warnings/errors and restore cron even when .shellrc is unavailable.
# This is intentional defensive programming for bootstrap edge cases, not accidental
# duplication.
# Helper functions for _cleanup_and_exit that work before .shellrc is sourced.
# These mirror the versions in .shellrc but use simpler checks.
_has_step_warnings() { (( ${#_step_warnings[@]:-0} > 0 )); }
_has_step_errors() { (( ${#_step_errors[@]:-0} > 0 )); }

# Appends the warnings and errors this script recorded before the hand-off to the issues file, in
# the "<warning|error><TAB><entry>" format the Ruby side writes (see
# Logging::Summary#_append_to_issues_file), so that the closing summary and notification printed by
# FreshInstallPostClone cover the whole run.
#
# This file-based hand-off exists only because the control flow jumps between shell and Ruby: the
# shell cannot read a Ruby process's in-memory Logging state, nor can a Ruby process write into this
# script's _step_warnings/_step_errors arrays. main() exports _DOTFILES_ISSUES_FILE and empties it at
# start; the Ruby side adopts what is written here, and its child processes (capture-prefs.rb, ...)
# keep appending to it.
# Zsh dynamic scoping: _step_warnings and _step_errors (local in main) are visible here.
_hand_over_shell_issues() {
  local _hsi_issue
  if _has_step_errors; then
    for _hsi_issue in "${_step_errors[@]}"; do
      print -r -- "error"$'\t'"${_hsi_issue//$'\n'/ }" >>"${_DOTFILES_ISSUES_FILE}"
    done
  fi
  if _has_step_warnings; then
    for _hsi_issue in "${_step_warnings[@]}"; do
      print -r -- "warning"$'\t'"${_hsi_issue//$'\n'/ }" >>"${_DOTFILES_ISSUES_FILE}"
    done
  fi
}

_cleanup_and_exit() {
  local failed_line="${1:-}"

  # Print any non-fatal warnings and errors already collected before this fatal failure,
  # so the full context is visible alongside the crash message.
  # Uses print_script_summary when shellrc is loaded; falls back to plain echo for early failures.
  # Zsh dynamic scoping: _step_warnings and _step_errors (local in main) are visible here.
  if (($+functions[print_script_summary])); then
    print_script_summary
  else
    if _has_step_warnings; then
      echo '==> Collected warnings:'
      local _cae_w
      for _cae_w in "${_step_warnings[@]:-}"; do
        echo "  ⚠️  ${_cae_w}"
      done
    fi
    if _has_step_errors; then
      echo '==> Collected errors:'
      local _cae_e
      for _cae_e in "${_step_errors[@]:-}"; do
        echo "  ❌  ${_cae_e}"
      done
    fi
  fi

  local message="[fresh-install-of-osx.sh] Installation failed. Check for error messages above."
  if [[ -n "${failed_line}" ]]; then
    message="[fresh-install-of-osx.sh] Installation failed at line ${failed_line}. Check for error messages above."
  fi
  # (( $+functions[...] )) is a no-subshell zsh builtin check, faster than 'type ... &>/dev/null'
  if (($+functions[error])); then
    error "${message}"
  else
    echo "ERROR: ${message}" >&2
  fi

  # Restore cron from the backup taken at the start of main(); _DOTFILES_CRON_BACKUP_FILE is set there.
  # (( $+functions[...] )) is a no-subshell zsh builtin check, faster than 'type ... &>/dev/null'
  if (($+functions[resume_cron])); then
    resume_cron
  elif [[ -s "${_DOTFILES_CRON_BACKUP_FILE:-}" ]]; then
    # Fallback: shellrc not yet loaded, restore directly
    if crontab "${_DOTFILES_CRON_BACKUP_FILE}"; then
      echo 'SUCCESS: Restored crontab from backup.'
    else
      echo 'ERROR: Failed to restore crontab.' >&2
    fi
    rm -f "${_DOTFILES_CRON_BACKUP_FILE}"
  fi

  exit 1
}

# Set DNS to 1.1.1.2/9.9.9.9 if on Jio ISP (GitHub may otherwise not resolve).
# Split in two so the slow ipinfo lookup (up to ~10s on a bad network) can overlap with the .shellrc
# download instead of preceding it:
#   _start_jio_dns_lookup  -- starts the lookup in the background (writes <file>, sets _jio_lookup_pid)
#   _finish_jio_dns_setup  -- waits for it, applies the DNS change if needed, and sets
#                             _jio_dns_changed=1 so the caller can retry a download that failed
#                             before the change took effect.
# The _jio_* variables are plain globals shared by these two functions and their caller.
# --connect-timeout/--max-time: on a flaky or captive network this best-effort lookup must not
# stall the whole bootstrap; a timeout leaves the result empty, which is handled like any other failure.
_start_jio_dns_lookup() {
  _jio_lookup_file="$(mktemp "${TMPDIR:-/tmp}/jio_lookup.XXXXXX")"
  _jio_dns_changed=''
  # '|| true': a failed lookup (the usual case on non-Jio networks with no route, etc.) must be
  # silent and must not trip the ERR trap inside the background subshell.
  ( trap - ERR EXIT; curl -fsS --connect-timeout 5 --max-time 10 https://ipinfo.io/org 2>/dev/null >"${_jio_lookup_file}" || true ) &!
  _jio_lookup_pid=$!
}

_finish_jio_dns_setup() {
  if [[ -z "${_jio_lookup_pid:-}" ]]; then
    return 0
  fi
  # The background subshell is disowned (&!), so it cannot be 'wait'ed for: poll for its exit.
  zmodload zsh/zselect
  while kill -0 "${_jio_lookup_pid}" 2>/dev/null; do
    zselect -t 10 || true
  done
  local _org
  _org="$(<"${_jio_lookup_file}")"
  rm -f "${_jio_lookup_file}"
  _jio_lookup_pid=''
  # Pure-zsh lowercase expansion (:l) + glob match, no extra process.
  if [[ "${_org:l}" == *jio* ]]; then
    echo '==> Setting DNS for WiFi from Jio ISP'
    networksetup -setdnsservers Wi-Fi 1.1.1.2 9.9.9.9 || echo 'Warning: Failed to set DNS for Wi-Fi'
    _jio_dns_changed=1
  fi
}

# Resolve GH_USERNAME without requiring it to be permanently stored anywhere.
# On the very first (vanilla OS) run there is nothing cloned yet to derive it
# from, so an explicitly exported GH_USERNAME (from the bootstrap one-liner) is
# required. On every subsequent run (pre-configured machine, re-running this
# script to pick up updates), DOTFILES_DIR already exists locally, so this
# derives the value from its 'origin' remote instead -- meaning adopters never
# need to remember to export GH_USERNAME again after the first successful run.
# Raw form: runs before .shellrc is sourced, so is_non_zero_string/is_git_repo
# are unavailable.
_resolve_gh_username() {
  if [[ -n "${GH_USERNAME:-}" ]]; then
    return
  fi
  if [[ -n "${DOTFILES_DIR:-}" && -d "${DOTFILES_DIR}/.git" ]]; then
    GH_USERNAME="$(git -C "${DOTFILES_DIR}" remote get-url origin 2>/dev/null | /usr/bin/sed -E 's#.*[:/]([^/]+)/dotfiles(\.git)?/?$#\1#')"
  fi
  if [[ -z "${GH_USERNAME:-}" ]]; then
    echo "ERROR: GH_USERNAME is not set and could not be derived from '${DOTFILES_DIR:-<unset>}'." >&2
    echo "       Export it before running: export GH_USERNAME='your-github-username'" >&2
    exit 1
  fi
  export GH_USERNAME
}

# Resolves which branch of the dotfiles repo to bootstrap from/check out. Unlike
# GH_USERNAME (no safe default -- every fork's username differs, so an unresolvable
# value is a hard error), DOTFILES_BRANCH has a universally-correct default ('master')
# for everyone who hasn't deliberately switched to a different branch for testing, so
# this never errors out -- it only derives-or-falls-back.
#
# Only ever read before '${DOTFILES_DIR}' exists as a git repo (constructing the
# '.shellrc' download URL, and the initial 'git clone' of the dotfiles repo itself --
# see _download_and_source_shellrc/_clone_dot_files_repo); on any later re-run, the
# already-cloned repo is used directly and this value is never consulted again. Safe
# to derive from the local repo's own current branch on such a re-run (e.g. after
# manually checking out a test branch there -- see Advanced.md § 5.6), rather than
# requiring it to be kept in sync in '.shellrc' as well.
_resolve_dotfiles_branch() {
  if [[ -n "${DOTFILES_BRANCH:-}" ]]; then
    return
  fi
  if [[ -n "${DOTFILES_DIR:-}" && -d "${DOTFILES_DIR}/.git" ]]; then
    DOTFILES_BRANCH="$(git -C "${DOTFILES_DIR}" branch --show-current)"
  fi
  DOTFILES_BRANCH="${DOTFILES_BRANCH:-master}"
  export DOTFILES_BRANCH
}

# Download and source .shellrc from GitHub (before dotfiles are cloned)
_download_and_source_shellrc() {
  echo "==> Ensuring '~/.shellrc' is current"

  # Determine if download is needed
  local reason=""
  # Raw form: this function runs before .shellrc is sourced, so is_first_install
  # is not yet defined. Check FIRST_INSTALL env var directly.
  if [[ -n "${FIRST_INSTALL:-}" ]]; then
    # Vanilla OS: always download
    reason="first install"
  elif [[ ! -f "${HOME}/.shellrc" ]]; then
    # Pre-configured but .shellrc missing (deleted or corrupted symlink)
    reason=".shellrc missing"
  elif [[ ! -d "${DOTFILES_DIR}" ]]; then
    # Pre-configured but DOTFILES_DIR missing (partial fresh-install or deleted repo)
    # Cannot verify staleness without repo - re-download to ensure current version
    reason="dotfiles repo missing"
  elif [[ -f "${DOTFILES_DIR}/files/--HOME--/.shellrc" ]] && \
       [[ "${DOTFILES_DIR}/files/--HOME--/.shellrc" -nt "${HOME}/.shellrc" ]]; then
    # Pre-configured: repo file is newer than existing .shellrc (git pull updated repo)
    # Downloads from GitHub to ensure fresh copy (not using potentially stale local repo file)
    reason="local repo file is newer"
  fi

  # The download runs concurrently with the (independent) Jio DNS lookup started in main().
  # If the network turns out to be Jio, GitHub may not have resolved for the download that
  # started before the DNS change; it is then retried once, after the change.
  local shellrc_download_url shellrc_tmp_file=''
  if [[ -n "${reason}" ]]; then
    echo "==> Downloading .shellrc from GitHub (${reason})"
    # Cache-busting: append timestamp to URL and add no-cache headers to ensure we bypass
    # GitHub's CDN cache and intermediate proxies to get the latest version.
    shellrc_download_url="https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/files/--HOME--/.shellrc?$(/bin/date +%s)"
    # Downloaded to a temp file in the same directory and moved into place only on success, so a
    # failed or interrupted download never leaves a truncated ~/.shellrc behind.
    shellrc_tmp_file="${HOME}/.shellrc.download.$$"
    ( trap - ERR EXIT; curl "${_cache_bust_headers[@]}" "${_curl_retry_opts[@]}" -fsSL "${shellrc_download_url}" -o "${shellrc_tmp_file}" ) &
    local shellrc_download_pid=$!
  fi

  _finish_jio_dns_setup

  if [[ -n "${reason}" ]]; then
    local shellrc_download_status=0
    wait "${shellrc_download_pid}" || shellrc_download_status=$?
    if (( shellrc_download_status != 0 )) && [[ -n "${_jio_dns_changed:-}" ]]; then
      echo "==> Retrying the .shellrc download now that the DNS has been changed"
      shellrc_download_status=0
      curl "${_cache_bust_headers[@]}" "${_curl_retry_opts[@]}" -fsSL "${shellrc_download_url}" -o "${shellrc_tmp_file}" || shellrc_download_status=$?
    fi
    if (( shellrc_download_status != 0 )); then
      rm -f "${shellrc_tmp_file}"
      echo "ERROR: failed to download .shellrc (curl exit ${shellrc_download_status})" >&2
      return "${shellrc_download_status}"
    fi
    mv -f "${shellrc_tmp_file}" "${HOME}/.shellrc"
  fi

  # Universal validation (both first-install and pre-configured)
  # Validate: check that file is non-empty and contains the re-source guard
  # function (basic smoke test for successful download vs truncated/corrupted response).
  if [[ ! -s "${HOME}/.shellrc" ]] || ! /usr/bin/grep -q 'is_shellrc_sourced' "${HOME}/.shellrc"; then
    echo "ERROR: .shellrc appears corrupted or empty" >&2
    exit 1
  fi

  echo "==> Verified '${HOME}/.shellrc'"

  # Universal sourcing (both paths)
  # Unfunction the guard so .shellrc's own re-source check is bypassed.
  # This handles both first install and retries on a vanilla OS where the script is re-run after an error.
  # if/fi avoids the && pattern where (($+functions[...])) returning false
  # (guard not yet defined, the common case on first install) propagates a
  # non-zero exit under the ERR trap that is active by this point.
  if (($+functions[is_shellrc_sourced])); then unfunction is_shellrc_sourced; fi
  DEBUG=true source "${HOME}/.shellrc"
  success "Successfully sourced '$(cyan "${HOME}/.shellrc")'"
}

# Enable Touch ID for sudo command when running on the terminal
_approve_fingerprint_sudo() {
  step_start
  _step_header "$(yellow 'Setting up touchId for sudo access in terminal shells')"

  # AppleBiometricSensor = T1/T2 chip (Intel Macs); AppleBiometricServices = Apple Silicon
  # Check for Touch ID hardware (single ioreg call for both classes)
  # Note: Command substitution buffers all ioreg output first, avoiding SIGPIPE under pipefail
  # (grep -q would exit early and trigger SIGPIPE on ioreg).
  local biometric_output
  biometric_output="$(/usr/sbin/ioreg -c AppleBiometricSensor -c AppleBiometricServices 2>/dev/null)" || true
  if is_zero_string "${biometric_output}"; then
    info 'Touch ID hardware is not detected -- skipping configuration.'
    step_end
    return 0  # Exit successfully as no action is needed
  fi

  local template_file='/etc/pam.d/sudo_local.template'
  if ! is_file "${template_file}"; then
    warn "Template file '$(cyan "${template_file}")' not found! Skipping!"
    step_end
    return
  fi

  local target_file='/etc/pam.d/sudo_local'
  if ! is_file "${target_file}"; then
    if sudo sh -c "sed 's/^#auth/auth/' '${template_file}' > '${target_file}'"; then
      success "Created new file: '$(cyan "${target_file}")'"
    else
      error "Failed to create '$(cyan "${target_file}")'"
    fi
  else
    info "'$(cyan "${target_file}")' is already present -- skipping."
  fi
  step_end
}

# Verify FileVault disk encryption is active
_ensure_filevault_is_on() {
  step_start
  _step_header "$(yellow 'Verifying FileVault status')"
  if [[ "$(fdesetup isactive)" != 'true' ]]; then
    user_action "Enable FileVault: System Settings -> Privacy & Security -> FileVault -> Turn On FileVault"
    error 'FileVault is not turned on. Please encrypt your hard disk!'
    exit 1
  fi
  step_end
}

# Runs a command with stdout+stderr captured into <outfile> and kills it if it is still running
# after <seconds>. There is no GNU 'timeout' on a vanilla macOS, so this is a portable
# background + poll + kill. Returns the command's own status, or 124 on a timeout (same as
# GNU timeout). zselect (zsh/zselect, a built-in module) is the no-fork 200ms sleep; it returns
# non-zero when its timeout expires, which is the normal case here, hence the '|| true'.
# Usage: _run_with_timeout <seconds> <outfile> <command> [args...]
_run_with_timeout() {
  local rwt_secs="${1}" rwt_outfile="${2}"
  shift 2
  zmodload zsh/zselect
  "$@" >"${rwt_outfile}" 2>&1 &
  local rwt_pid=$!
  local rwt_ticks=0
  local rwt_max_ticks=$((rwt_secs * 5))
  local rwt_status=0
  while kill -0 "${rwt_pid}" 2>/dev/null; do
    if (( rwt_ticks >= rwt_max_ticks )); then
      kill "${rwt_pid}" 2>/dev/null || true
      zselect -t 100 || true
      kill -9 "${rwt_pid}" 2>/dev/null || true
      wait "${rwt_pid}" 2>/dev/null || true
      return 124
    fi
    zselect -t 20 || true
    rwt_ticks=$((rwt_ticks + 1))
  done
  wait "${rwt_pid}" || rwt_status=$?
  return "${rwt_status}"
}

# Extracts the Command Line Tools label from 'softwareupdate --list' output in <list-file> and
# prints it (the last match, which is the newest). Handles both formats macOS has used:
#   '* Label: Command Line Tools for Xcode-16.4'   (macOS 10.15+)
#   '* Command Line Tools for Xcode-11.5'          (older)
# Prints nothing when there is no such line.
_parse_clt_label() {
  local pcl_line pcl_label=''
  while IFS= read -r pcl_line; do
    if [[ "${pcl_line}" =~ '^\*[[:space:]]+(Label:[[:space:]]+)?(Command Line Tools.*)$' ]]; then
      pcl_label="${match[2]}"
      # Strip trailing whitespace (portable form; '%%[[:space:]]#' would need EXTENDED_GLOB).
      pcl_label="${pcl_label%"${pcl_label##*[![:space:]]}"}"
    fi
  done <"${1}"
  if [[ -n "${pcl_label}" ]]; then print -r -- "${pcl_label}"; fi
}

# Install Xcode Command Line Tools via non-interactive, non-gui softwareupdate. The (slow, ~5s+)
# 'softwareupdate --list' is only run when the tools are missing, and only the Command Line Tools
# label it reports is installed (not every recommended update, which '-ia' would do). Two numbered
# steps are kept regardless of the path taken so the 'Step N of TOTAL' count stays in sync with
# the total declared in main() and in FreshInstallPostClone.
_install_xcode_command_line_tools() {
  _current_section='Install Xcode Command Line Tools'; _current_section_manual=1
  local clt_marker='/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress'
  local clt_label=''
  local clt_missing=false
  if ! xcode-select -p &>/dev/null; then clt_missing=true; fi

  step_start
  _step_header "$(yellow 'Listing available software updates')"
  if [[ "${clt_missing}" == true ]]; then
    # The marker file must exist BEFORE listing: softwareupdate only offers the Command Line
    # Tools in its list while it is present.
    touch "${clt_marker}"
    local su_list_file
    su_list_file="$(mktemp)"
    local su_status=0
    # Bounded to 120s: on a flaky network or a stuck Software Update service this call can hang.
    _run_with_timeout 120 "${su_list_file}" softwareupdate --list || su_status=$?
    if (( su_status == 124 )); then
      _record_warning "'softwareupdate --list' timed out after 120s -- falling back to installing all recommended updates"
    elif (( su_status != 0 )); then
      _record_warning "'softwareupdate --list' failed (exit ${su_status}) -- falling back to installing all recommended updates"
    fi
    /usr/bin/grep '^\*' "${su_list_file}" || true
    clt_label="$(_parse_clt_label "${su_list_file}")"
    rm -f "${su_list_file}"
  else
    info 'Skipping listing of software updates -- xcode command-line tools already present.'
  fi
  step_end

  step_start
  _step_header "$(yellow 'Installing xcode command-line tools')"
  if [[ "${clt_missing}" == true ]]; then
    if [[ -n "${clt_label}" ]]; then
      info "Installing only '$(cyan "${clt_label}")'"
      sudo softwareupdate -i "${clt_label}" --agree-to-license || _record_warning "softwareupdate encountered errors installing '${clt_label}'"
    else
      warn 'No Command Line Tools label found in the softwareupdate list -- installing all recommended updates instead'
      sudo softwareupdate -ia --agree-to-license --force || _record_warning 'softwareupdate encountered errors'
    fi
    rm -f "${clt_marker}"
    if ! xcode-select -p 2>/dev/null; then
      error "Couldn't install xcode command-line tools; Aborting"
      exit 1
    fi

    success 'Successfully installed xcode command-line tools'
  else
    info 'Skipping installation of xcode command-line tools -- already present.'
  fi
  # Note: Duplicate the cleanup if the installation was cancelled and continued via the gui
  rm -f "${clt_marker}"
  step_end
}

# Starts the official Homebrew installer in the background so it overlaps with the rest of the
# bootstrap (the dotfiles clone, install-dotfiles, ...); the HomebrewInstall step in Ruby waits
# for it (see the contract below), verifies that brew exists and installs it itself if the
# background run failed.
#
# Only on a vanilla OS (FIRST_INSTALL set, no brew yet); opt out with FRESH_INSTALL_NO_EARLY_BREW.
# Must run after: (a) the Command Line Tools exist (the installer requires them) and (b)
# keep_sudo_alive is running -- the installer runs with NONINTERACTIVE=1 and stdin from
# /dev/null, so it can never prompt: it only works while sudo credentials are cached, which the
# keep-alive loop refreshes every 60s.
#
# Contract (exported; read by the Ruby HomebrewInstall step):
#   _DOTFILES_BREW_INSTALL_PID -- pid of the background job (poll with 'kill -0'; it is not a child
#                                 of the Ruby process, so its exit status is not available --
#                                 check for the brew binary instead)
#   _DOTFILES_BREW_INSTALL_LOG -- file with the downloader's and installer's combined output
#
# If this script is re-run while a previous installer is still alive (pid file below), that one
# is adopted rather than starting a second concurrent installer.
#
# Failure/exit behaviour: the installer is deliberately NOT killed when this script fails or is
# interrupted -- aborting an installer half way leaves a partial Homebrew that is harder to
# recover from than letting it finish. Instead the EXIT trap (see _brew_install_exit_notice)
# tells the user it is still running, with its pid and log.
_start_early_brew_install() {
  if [[ -n "${FRESH_INSTALL_NO_EARLY_BREW:-}" ]]; then
    info 'Not starting Homebrew early -- FRESH_INSTALL_NO_EARLY_BREW is set.'
    return 0
  fi
  if [[ -z "${FIRST_INSTALL:-}" ]]; then
    return 0
  fi
  if command_exists brew || is_file /opt/homebrew/bin/brew || is_file /usr/local/bin/brew; then
    return 0
  fi

  local pid_file="${TMPDIR:-/tmp}/dotfiles_brew_install.pid"
  local log_file="${TMPDIR:-/tmp}/dotfiles_brew_install.log"
  local old_pid=''
  if is_file "${pid_file}"; then old_pid="$(<"${pid_file}")"; fi
  if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
    info "A Homebrew installer from an earlier run is still running (pid ${old_pid}) -- reusing it; log: '$(cyan "${log_file}")'"
    export _DOTFILES_BREW_INSTALL_PID="${old_pid}"
    export _DOTFILES_BREW_INSTALL_LOG="${log_file}"
    return 0
  fi

  local installer_file
  installer_file="$(mktemp "${TMPDIR:-/tmp}/brew-install.XXXXXX")"
  : >"${log_file}"
  # The whole download+install runs inside the backgrounded subshell, so the (cache-busted,
  # retrying) download does not block this script either. The temp installer is removed by
  # the subshell itself when it finishes.
  # The traps are cleared first: this subshell must never run this script's ERR/EXIT cleanup (which
  # would restore cron and print a failure summary on behalf of the main script).
  (
    trap - ERR EXIT
    installer_status=0
    curl "${_cache_bust_headers[@]}" "${_curl_retry_opts[@]}" -fsSL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh?$(/bin/date +%s)" -o "${installer_file}" && \
      NONINTERACTIVE=1 /bin/bash "${installer_file}" || installer_status=$?
    rm -f "${installer_file}"
    exit "${installer_status}"
  ) </dev/null >>"${log_file}" 2>&1 &!
  export _DOTFILES_BREW_INSTALL_PID=$!
  export _DOTFILES_BREW_INSTALL_LOG="${log_file}"
  print -r -- "${_DOTFILES_BREW_INSTALL_PID}" >"${pid_file}"
  info "Started the Homebrew installer in the background (pid ${_DOTFILES_BREW_INSTALL_PID}); log: '$(cyan "${log_file}")'"
}

# EXIT-trap helper, see _start_early_brew_install: a still-running background Homebrew installer
# is left alone, but never silently.
_brew_install_exit_notice() {
  local pid="${_DOTFILES_BREW_INSTALL_PID:-}"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    echo "NOTE: the background Homebrew installer (pid ${pid}) is still running and was left running on purpose; its log: ${_DOTFILES_BREW_INSTALL_LOG:-<unknown>}. Re-running this script reuses it." >&2
  fi
}

# EXIT-trap helper: normally the crontab backup is already restored and deleted by the time the
# script exits (by _cleanup_and_exit, the Ruby side, or resume_cron). When the script leaves
# through a plain 'exit 1' that skipped those, the backup is still there and cron is still empty:
# restore it so the schedule is not lost, then remove the file. A non-empty live crontab is never
# overwritten.
_restore_leftover_cron_backup() {
  local backup="${_DOTFILES_CRON_BACKUP_FILE:-}"
  if [[ -n "${backup}" && -s "${backup}" ]] && [[ -z "$(crontab -l 2>/dev/null)" ]]; then
    if crontab "${backup}"; then
      echo 'SUCCESS: Restored crontab from leftover backup at exit.'
    else
      echo "ERROR: Failed to restore crontab at exit; backup kept at ${backup}" >&2
      return 0
    fi
  fi
  if [[ -n "${backup}" ]]; then rm -f "${backup}"; fi
}

# Create core XDG directories needed before install-dotfiles.rb runs.
# Note: ${DOTFILES_DIR} is created by clone_repo_into's ensure_dir_exists call.
# Note: ${ANTIDOTE_HOME} and other tool-specific subdirectories (e.g., ${XDG_CONFIG_HOME}/pg,
# ${XDG_STATE_HOME}/vim/undo) are created automatically by their respective tools or by
# install-dotfiles.rb when it creates symlinks to those locations.
_ensure_directories_exist() {
  step_start
  _step_header "$(yellow 'Creating XDG base directories')"
  local -a dirs=(
    "${ANTIDOTE_HOME}"
    "${ANTIDOTE_PLUGIN_ZSH:h}"
    "${XDG_CACHE_HOME}"
    "${XDG_CONFIG_HOME}"
  )
  local dir
  for dir in "${dirs[@]}"; do
    ensure_dir_exists "${dir}"
  done
  step_end
}

# Clone the dotfiles repo and configure upstream
_clone_dot_files_repo() {
  _current_section='Clone dotfiles repo'; _current_section_manual=1
  step_start
  _step_header "$(yellow 'Installing dotfiles') into '$(cyan "${DOTFILES_DIR}")'"
  # Clone if DOTFILES_DIR is not a git repo. is_git_repo checks both existence and .git presence.
  if is_non_zero_string "${DOTFILES_DIR}" && ! is_git_repo "${DOTFILES_DIR}"; then
    # Delete the auto-generated .zshrc since that needs to be replaced by the one in the DOTFILES_DIR repo
    rm -rf "${ZDOTDIR}/.zshrc"

    # Note: Cloning with https since the ssh keys will not be present at this time
    if clone_repo_into "https://github.com/${GH_USERNAME}/dotfiles" "${DOTFILES_DIR}" "${DOTFILES_BRANCH}"; then
      # Use the https protocol for pull, but use ssh/git for push (only configure if not already set)
      if ! git -C "${DOTFILES_DIR}" config --get url.ssh://git@github.com/.pushInsteadOf &>/dev/null; then
        git -C "${DOTFILES_DIR}" config url.ssh://git@github.com/.pushInsteadOf https://github.com/
      fi
    else
      error 'Failed to clone dotfiles repo'
      exit 1
    fi
  else
    info "Skipping cloning the dotfiles repo since '$(cyan "${DOTFILES_DIR}")' already exists and is a git repo"
  fi

  # The scripts folder is put on PATH and the upstream remote is set up by the first step of the Ruby
  # part (FreshInstallPostClone), which runs regardless of whether the repo was just cloned.
  step_end
}

# Runs everything that comes after the clone as one Ruby process (see FreshInstallPostClone in
# scripts/utilities/fresh_install_post_clone.rb), which owns the rest of the run: its steps, the
# closing summary and notification, and restoring cron if it fails. It is run by path, not through
# the call_utility function, because that function lives in the ~/.shellrc that the first Ruby step
# verifies. COLUMNS is not exported by the shell, so it is passed explicitly; everything else the
# Ruby side needs (FIRST_INSTALL, the cron backup file, the issues file, the script depth) is
# exported. The script cannot be `exec`ed: the EXIT trap here must still run.
# $1 = epoch the whole run started at (for the duration line), $2 = number of steps already numbered
_run_post_clone_steps() {
  local script_start_time="${1}"
  local steps_done="${2}"

  _hand_over_shell_issues

  local post_clone_status=0
  COLUMNS="${COLUMNS}" "${CALL_UTILITY_SCRIPT}" --truthy FreshInstallPostClone.run "--steps_done=${steps_done}" "--start_time=${script_start_time}" || post_clone_status=$?

  if (( post_clone_status != 0 )); then
    # What failed was already reported by the Ruby side, which also restores cron. This is only a
    # safety net for a Ruby process that died without getting to do that: the EXIT trap deletes the
    # backup, so restore it first if it is still there.
    if is_file "${_DOTFILES_CRON_BACKUP_FILE:-}"; then resume_cron || true; fi
    exit "${post_clone_status}"
  fi
}

main() {
  # Suspend cron early before .shellrc or .aliases are available -- neither
  # suspend_cron nor Cron.with_cron_suspended can be called yet, so the backup and
  # removal are done inline here. Even after both files are sourced, the
  # Cron.with_cron_suspended wrapper is not appropriate: the suspend/resume scope
  # spans the entire main(), not a single delegated function call.
  # Once .shellrc is sourced, the EXIT and ERR traps use resume_cron/recron
  # from .shellrc for restore.
  export _DOTFILES_CRON_BACKUP_FILE="${TMPDIR:-/tmp}/crontab_backup"
  # Never replace a non-empty backup with an empty one: if an earlier run crashed after
  # 'crontab -r', that backup is the only copy of the schedule, and the live crontab is empty now.
  # A non-empty live crontab is always the newest truth, so it does replace an older backup.
  local _cron_new_backup="${_DOTFILES_CRON_BACKUP_FILE}.new"
  if crontab -l >"${_cron_new_backup}" 2>/dev/null && [[ -s "${_cron_new_backup}" ]]; then
    mv -f "${_cron_new_backup}" "${_DOTFILES_CRON_BACKUP_FILE}"
  else
    rm -f "${_cron_new_backup}"
    if [[ -s "${_DOTFILES_CRON_BACKUP_FILE}" ]]; then
      echo "==> No active crontab, but an older backup exists -- keeping it: '${_DOTFILES_CRON_BACKUP_FILE}' (likely left by an interrupted earlier run; it will be restored at the end)"
    else
      : >"${_DOTFILES_CRON_BACKUP_FILE}"
    fi
  fi
  crontab -r &>/dev/null || true

  # Ruby modules and scripts append the issues they record to this file (see
  # _hand_over_shell_issues); it starts empty on every run.
  export _DOTFILES_ISSUES_FILE="${TMPDIR:-/tmp}/dotfiles_fresh_install_issues"
  : >"${_DOTFILES_ISSUES_FILE}"

  # Set ZDOTDIR before sourcing .shellrc so the value is available immediately.
  # Must match the default in .shellrc line 40 and env_vars.rb ZDOTDIR constant.
  export ZDOTDIR="${ZDOTDIR:-"${XDG_CONFIG_HOME:-${HOME}/.config}/zsh"}"

  # On a first install ${XDG_CONFIG_HOME}/git/config is not yet in place (install-dotfiles.rb
  # runs later), so core.sshCommand is absent. Export GIT_SSH_COMMAND for the entire run to
  # ensure consistent SSH options for all git operations. Keepalive prevents timeout on slow networks.
  # Raw form: this runs in main() before _download_and_source_shellrc has sourced .shellrc,
  # so is_first_install is not yet defined.
  # if/fi avoids the && pattern where [[ -n ... ]] returning false (not a first install,
  # the common case on a pre-configured machine) propagates a non-zero exit under the ERR trap.
  # Connection multiplexing (ControlMaster/ControlPersist): the many sequential git operations of a
  # bootstrap (clones, fetches, submodule updates) reuse one authenticated connection instead of
  # paying the TCP+SSH handshake each time. The socket lives in a private (0700, owner-checked) dir
  # under /tmp: ${TMPDIR} on macOS is long enough that '<dir>/<%C hash, 40 chars>' could exceed the
  # 104-byte unix-socket path limit, and ~/.ssh is tracked by the 'home' repo. Multiplexing is
  # simply left off if the directory cannot be made safe. The master exits by itself 120s after its
  # last client. Compression=no on the command line overrides 'Compression yes' of the global ssh
  # config, which is intentional for this bootstrap (the transfers are already compressed packs).
  if [[ -n "${FIRST_INSTALL:-}" ]]; then
    local _ssh_cm_dir="/tmp/.dotfiles-ssh-cm-${UID}"
    local _ssh_mux_opts=''
    if mkdir -p "${_ssh_cm_dir}" 2>/dev/null && chmod 700 "${_ssh_cm_dir}" 2>/dev/null && [[ -d "${_ssh_cm_dir}" && -O "${_ssh_cm_dir}" ]]; then
      _ssh_mux_opts=" -o ControlMaster=auto -o ControlPath=${_ssh_cm_dir}/%C -o ControlPersist=120"
    fi
    export GIT_SSH_COMMAND="ssh -o ConnectTimeout=20 -o Compression=no -o ServerAliveInterval=10 -o ServerAliveCountMax=3${_ssh_mux_opts}"
  fi

  # ~/.curlrc is not yet symlinked (install-dotfiles.rb runs later), so its defaults are
  # absent. Define resilient curl flags explicitly for all bootstrap curl calls in this
  # script. Once ~/.curlrc is in place these flags are redundant but harmless.
  # Note: defined as an array so it expands correctly without word-splitting issues.
  # Curl retry/timeout flags for bootstrap downloads before ~/.curlrc is symlinked.
  # Uses CURL_RETRY_OPTS env var as a flag - if set (to any value), enables retry options.
  # Otherwise only sets defaults when ~/.curlrc is not present.
  # Note: --retry-all-errors is intentionally omitted -- it causes the terminal app to close.
  # Raw -f used here -- .shellrc has not been sourced yet, so is_file is unavailable.

  # Curl retry/timeout flags for bootstrap downloads before ~/.curlrc is symlinked.
  # Uses CURL_RETRY_OPTS env var as a flag - if set (to any value), enables retry options.
  # Otherwise only sets defaults when ~/.curlrc is not present.
  # Note: --retry-all-errors is intentionally omitted -- it causes the terminal app to close.
  local -a _curl_retry_opts=()
  if [[ -n "${CURL_RETRY_OPTS:-}" || ! -f "${HOME}/.curlrc" ]]; then
    _curl_retry_opts=(--retry 5 --retry-delay 10 --retry-max-time 120 --max-time 150 --connect-timeout 30 --retry-connrefused)
  fi

  # Cache-busting headers for curl downloads from GitHub raw.githubusercontent.com.
  # Uses CACHE_BUST_HEADERS env var as a flag - if set (to any value), enables cache busting.
  local -a _cache_bust_headers
  if [[ -n "${CACHE_BUST_HEADERS:-}" ]]; then
    _cache_bust_headers=(-H "Cache-Control: no-cache, no-store, must-revalidate" -H "Pragma: no-cache" -H "Expires: 0")
  fi

  # Two separate accumulator arrays for non-fatal step issues:
  #   _step_warnings -- minor issues the step recovered from (e.g. a tool sub-step failed but install continued)
  #   _step_errors   -- significant failures that require manual attention (e.g. a tool was not found)
  # _record_warning/_record_error/_cleanup_and_exit/print_script_summary (all from .shellrc) read/write
  # these via zsh dynamic scoping -- locals declared here are visible in all callees.
  local _current_section='(init)'
  local _current_section_manual=0  # 0 = auto-set allowed, 1 = manual override active
  local -a _step_warnings=()
  local -a _step_errors=()

  # Progress tracking: Shows [Step N of TOTAL] in section headers
  local total_steps=14
  local current_step=0

  # Set ERR trap AFTER initializing arrays to prevent "parameter not set" errors in _cleanup_and_exit
  # if an error occurs during initialization. The trap accesses these arrays via dynamic scoping.
  trap '_cleanup_and_exit "${LINENO}"' ERR
  trap '_brew_install_exit_notice; _restore_leftover_cron_backup; _decrement_script_depth' EXIT

  # Helper function to show progress through steps
  _step_header() {
    current_step=$((current_step + 1))
    section_header "[$(purple "Step ${current_step} of ${total_steps}")] $*"
  }

  local -a _script_start_times=()
  local -a _step_start_times=()
  # This script is always the outermost one, so the depth is set to 1 outright instead of being
  # incremented: a value inherited from the terminal it was started in (a stale export from an earlier
  # session) would make it 2, and the closing summary (printed only at depth 1) and the indentation
  # of every line would silently go wrong.
  export _DOTFILES_SCRIPT_DEPTH=1
  # Note: Cannot load from shellrc since that file won't be present in a new machine (vanilla OS)
  # ${EPOCHSECONDS} is provided by the zsh/datetime built-in module -- always available, no fork.
  # Capture start epoch into both a local variable and _script_start_times.
  # The local is passed explicitly to print_script_summary at the end of main.
  # _script_start_times is used by step_end (called throughout this script) to
  # compute the "total elapsed" column independently of the local variable.
  # Both are required; see the design note above step_timing_init in .shellrc.
  local script_start_time
  # zmodload called directly -- .zshenv has not been sourced yet when this runs, so the load is not delegated.
  # Subsequent zmodload calls are no-op in zsh.
  zmodload zsh/datetime
  script_start_time="${EPOCHSECONDS}"
  _script_start_times+=("${script_start_time}")
  # current_timestamp is not yet available (shellrc not yet sourced); use strftime directly.
  local script_start_time_human
  strftime -s script_start_time_human '%Y-%m-%d %H:%M:%S' "${EPOCHSECONDS}"
  # Replicate print_script_start format using raw ANSI codes: script_name (cyan) ==> (purple)
  # 'Script started at:' (yellow) timestamp (light_blue). Cannot use color functions here --
  # this runs before _download_and_source_shellrc, so .shellrc is not yet loaded on a vanilla
  # OS, making cyan/purple/yellow/light_blue unavailable.
  printf "\033[36m%s\033[0m \033[35m==>\033[0m \033[33mScript started at:\033[0m \033[94m%s\033[0m\n" "${_SCRIPT_NAME}" "${script_start_time_human}"

  # Do not allow rootless login.
  # Note: Commented out since I am not sure if we need to do this on the office MBP or not
  # section_header "$(yellow 'Verifying rootless login enabled status')"
  # if [[ "$(/usr/bin/csrutil status | awk '/status/ {print $5}' | sed 's/\.$//')" == "enabled" ]]; then
  #   error "rootless login is enabled. Please disable in boot screen and run again"
  #   exit 1 # Irrecoverable failure
  # fi

  # Disable macOS Gatekeeper.
  # section_header "$(yellow 'Disabling macos gatekeeper')"
  # sudo spectl --master-disable

  _start_jio_dns_lookup
  _resolve_gh_username
  _resolve_dotfiles_branch
  _download_and_source_shellrc

  # Printed as early as possible (right after '.shellrc' is sourced, so 'user_action'
  # is available and ENCRYPTED_*_REPO_URL env vars are populated) rather than at the
  # much-later 'Cloning repos' step -- this manual escape hatch is only needed if the
  # external 'git-remote-gpg-encrypt' tool's interactive Keychain prompt fails or can't
  # run (e.g. no TTY), and by the time that step is reached (after xcode tools/
  # homebrew/etc.) it is too late for the user to act on this in parallel with the
  # rest of the install. Gated on the encrypted-backup env vars actually being set --
  # no point reminding someone who has disabled this mechanism entirely.
  if is_non_zero_string "${ENCRYPTED_HOME_REPO_URL:-}" || is_non_zero_string "${ENCRYPTED_PROFILES_REPO_URL:-}"; then
    user_action "The 'home'/'browser-profiles' repo clone steps later in this script read their encrypted-backup passphrase from the macOS Keychain -- you won't normally be prompted."
    user_action "If that fails, run this in another terminal now (no need to wait): security add-generic-password -A -a \"\${USER}\" -s 'git-remote-gpg-encrypt' -w"
  fi

  keep_sudo_alive
  _approve_fingerprint_sudo
  _ensure_filevault_is_on
  _install_xcode_command_line_tools
  _start_early_brew_install
  set_ssh_folder_permissions
  set_gnupg_folder_permissions
  _ensure_directories_exist
  _clone_dot_files_repo

  # Everything from here on is Ruby: the .shellrc check, install-dotfiles, Homebrew, the repos,
  # preferences, cron, the default shell, the closing summary and the notification.
  _run_post_clone_steps "${script_start_time}" "${current_step}"
}

main "$@"
