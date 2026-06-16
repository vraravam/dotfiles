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
# ('trap "_cleanup_and_exit ${LINENO}" ERR') so that $LINENO expands in the
# failing command's scope rather than inside this function.
#
# NOTE: This function duplicates logic from .shellrc (print_script_summary, error,
# resume_cron) because it must handle failures that occur BEFORE .shellrc can be
# downloaded on a vanilla OS (e.g., network failures, DNS issues, curl timeouts).
# The fallback implementations ensure the script can still display collected
# warnings/errors and restore cron even when .shellrc is unavailable.
# This is intentional defensive programming for bootstrap edge cases, not accidental
# duplication.
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
      for _cae_w in "${_step_warnings[@]}"; do
        echo "  ⚠️  ${_cae_w}"
      done
    fi
    if _has_step_errors; then
      echo '==> Collected errors:'
      local _cae_e
      for _cae_e in "${_step_errors[@]}"; do
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

# Set DNS to 1.1.1.1 if on Jio ISP (GitHub may otherwise not resolve)
_setup_jio_dns() {
  local _org
  # Capture curl output into a variable first; then test with a glob match.
  # Previously: curl ... | /usr/bin/grep -qi 'jio' -- two processes + pipe.
  # Now: single curl fork, pure-zsh lowercase expansion (:l) + glob match.
  _org=$(curl -fsS https://ipinfo.io/org 2>/dev/null)
  if [[ "${_org:l}" == *jio* ]]; then
    echo '==> Setting DNS for WiFi from Jio ISP'
    networksetup -setdnsservers Wi-Fi 1.1.1.1 || echo 'Warning: Failed to set DNS for Wi-Fi'
  fi
}

# Download and source .shellrc from GitHub (before dotfiles are cloned)
_download_and_source_shellrc() {
  echo "==> Download the '~/.shellrc' for loading the utility functions"
  # Raw form: this function runs before .shellrc is sourced, so is_first_install
  # is not yet defined. All post-source occurrences use is_first_install instead.
  if [[ -n "${FIRST_INSTALL:-}" ]]; then
    # Vanilla OS: always force a fresh download and re-source.
    # Cache-busting: append timestamp to URL and add no-cache headers to ensure we bypass
    # GitHub's CDN cache and intermediate proxies to get the latest version.
    curl "${_cache_bust_headers[@]}" "${_curl_retry_opts[@]}" -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/files/--HOME--/.shellrc?$(/bin/date +%s)" -o "${HOME}/.shellrc"
    echo "==> Successfully downloaded '${HOME}/.shellrc'"
  else
    # Pre-configured OS: skip downloading; the built-in guard makes the source below a no-op if already loaded.
    info "Skipping downloading '$(yellow "${HOME}/.shellrc")' since this is not a first install"
  fi
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
  section_header "$(yellow 'Setting up touchId for sudo access in terminal shells')"

  # AppleBiometricSensor = T1/T2 chip (Intel Macs); AppleBiometricServices = Apple Silicon
  # Note: pipe + grep -q triggers SIGPIPE on ioreg under pipefail (grep exits early after
  # first match, ioreg gets SIGPIPE exit 141, pipefail surfaces that instead of grep's 0).
  # Command substitution buffers all ioreg output first, avoiding the SIGPIPE entirely.
  local has_biometric_sensor=0 has_biometric_services=0
  local biometric_sensor_output biometric_services_output
  biometric_sensor_output="$(/usr/sbin/ioreg -c AppleBiometricSensor 2>/dev/null | /usr/bin/grep AppleBiometricSensor)" || true
  biometric_services_output="$(/usr/sbin/ioreg -c AppleBiometricServices 2>/dev/null | /usr/bin/grep AppleBiometricServices)" || true
  if is_non_zero_string "${biometric_sensor_output}"; then has_biometric_sensor=1; fi
  if is_non_zero_string "${biometric_services_output}"; then has_biometric_services=1; fi
  if [[ "${has_biometric_sensor}" == 0 && "${has_biometric_services}" == 0 ]]; then
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
      error "Failed to create '${target_file}'"
    fi
  else
    info "'$(cyan "${target_file}")' is already present -- skipping."
  fi
  step_end
}

# Verify FileVault disk encryption is active
_ensure_filevault_is_on() {
  step_start
  section_header "$(yellow 'Verifying FileVault status')"
  if [[ "$(fdesetup isactive)" != 'true' ]]; then
    error 'FileVault is not turned on. Please encrypt your hard disk!'
    exit 1
  fi
  step_end
}

# Install Xcode Command Line Tools via non-interactive, non-gui softwareupdate
_install_xcode_command_line_tools() {
  _current_section='Install Xcode Command Line Tools'
  step_start
  section_header "$(yellow 'Installing xcode command-line tools')"
  if ! xcode-select -p &>/dev/null; then
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    sudo softwareupdate -ia --agree-to-license --force || _record_warning 'softwareupdate encountered errors'
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    if ! xcode-select -p 2>/dev/null; then
      error "Couldn't install xcode command-line tools; Aborting"
      exit 1
    fi

    success 'Successfully installed xcode command-line tools'
  else
    info 'Skipping installation of xcode command-line tools -- already present.'
  fi
  # Note: Duplicate the cleanup if the installation was cancelled and continued via the gui
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  step_end
}

# Create all directories referenced by env vars as a pre-emptive safety step
_ensure_directories_exist() {
  step_start
  section_header "$(yellow 'Creating directories defined by various env vars')"
  local -a dirs=("${ANTIDOTE_HOME}" "${DOTFILES_DIR}" "${PROJECTS_BASE_DIR}" "${PERSONAL_BIN_DIR}" "${PERSONAL_CONFIGS_DIR}" "${PERSONAL_PROFILES_DIR}" "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}")
  local dir
  for dir in "${dirs[@]}"; do
    ensure_dir_exists "${dir}"
  done
  step_end
}

# Clone the dotfiles repo and configure upstream
_clone_dot_files_repo() {
  _current_section='Clone dotfiles repo'
  step_start
  section_header "$(yellow 'Installing dotfiles') into '$(cyan "${DOTFILES_DIR}")'"
  if is_non_zero_string "${DOTFILES_DIR}" && ! is_git_repo "${DOTFILES_DIR}"; then
    # Delete the auto-generated .zshrc since that needs to be replaced by the one in the DOTFILES_DIR repo
    rm -rf "${ZDOTDIR}/.zshrc"

    # Note: Cloning with https since the ssh keys will not be present at this time
    if clone_repo_into "https://github.com/${GH_USERNAME}/dotfiles" "${DOTFILES_DIR}" "${DOTFILES_BRANCH}"; then
      # Use the https protocol for pull, but use ssh/git for push (only configure if not already set)
      if ! git -C "${DOTFILES_DIR}" config --get url.ssh://git@github.com/.pushInsteadOf &>/dev/null; then
        git -C "${DOTFILES_DIR}" config url.ssh://git@github.com/.pushInsteadOf https://github.com/
      fi
      append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"
      # Setup the DOTFILES_DIR repo's upstream if it doesn't already point to UPSTREAM_GH_USERNAME's repo
      add-upstream-git-config.rb -d "${DOTFILES_DIR}" -u "${UPSTREAM_GH_USERNAME}" || _record_warning 'Failed to add upstream git config for dotfiles repo'
    else
      error 'Failed to clone dotfiles repo'
      exit 1
    fi
  else
    info "Skipping cloning the dotfiles repo since '$(cyan "${DOTFILES_DIR}")' is either not defined or is already a git repo"
  fi
  step_end
}

# Install homebrew, tap repos, and run brew bundle
_install_homebrew() {
  _current_section='Install Homebrew'
  step_start
  section_header "$(yellow 'Installing homebrew') into '$(cyan "${HOMEBREW_PREFIX}")'"
  if is_zero_string "${HOMEBREW_PREFIX}"; then
    error "'HOMEBREW_PREFIX' env var is not set; something is wrong. Please correct before retrying!"
    exit 1  # Irrecoverable failure
  fi

  if ! command_exists brew; then
    # Prep for installing homebrew
    sudo mkdir -p "${HOMEBREW_PREFIX}/tmp" "${HOMEBREW_PREFIX}/repository" "${HOMEBREW_PREFIX}/plugins" "${HOMEBREW_PREFIX}/bin"
    sudo chown -fR "${USER}":admin "${HOMEBREW_PREFIX}"
    chmod u+w "${HOMEBREW_PREFIX}"

    local install_script_file
    install_script_file="$(mktemp)"
    # Cache-busting: add no-cache headers and timestamp to ensure we get the latest Homebrew installer
    if curl "${_cache_bust_headers[@]}" "${_curl_retry_opts[@]}" -fsSL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh?$(/bin/date +%s)" -o "${install_script_file}"; then
      NONINTERACTIVE=1 bash "${install_script_file}" || {
        rm -f "${install_script_file}"
        error 'Homebrew installation failed'
        exit 1
      }
      rm -f "${install_script_file}"
      success 'Successfully installed homebrew'
    else
      rm -f "${install_script_file}"
      error 'Failed to download Homebrew installation script'
      exit 1
    fi
  else
    info "Skipping installation of $(yellow 'homebrew') -- already installed."
  fi

  # Ensure homebrew's environment variables are set correctly for this session.
  eval_shellenv "${HOMEBREW_PREFIX}/bin/brew" shellenv

  # Trust all custom taps defined in the Brewfile before running brew bundle.
  # This ensures taps are trusted before any formulae/casks from those taps are
  # installed, which is required if HOMEBREW_REQUIRE_TAP_TRUST is enforced.
  # Use 'brew bundle list --taps' to extract tap names from Brewfile, skip homebrew/* taps.
  if command_exists brew; then
    local -a custom_taps
    # Read tap names into array, excluding homebrew/* taps (core/cask don't need trusting)
    custom_taps=($(brew bundle list --taps --file="${HOMEBREW_BUNDLE_FILE}" | /usr/bin/grep -v "^homebrew/"))

    if is_non_empty_array custom_taps; then
      info "Trusting custom taps: '$(yellow "${custom_taps[*]}")'"
      brew trust --tap -q "${custom_taps[@]}" || true  # Don't fail if trust fails
    fi
  fi

  # Taps are no longer used in the FIRST_INSTALL base Brewfile section.
  # The tap commands below are kept for reference in case a tap is needed again.
  # /usr/bin/grep -E "^tap " "${HOMEBREW_BUNDLE_FILE}" | awk '{print $2}' | tr -d "'\"" | while read -r tap_name; do
  #   brew tap "${tap_name}" || true
  # done

  # Note: Do not set the 'FIRST_INSTALL' in this script - since its supposed to run idempotently. Also, don't run the cleanup of pre-installed brews/casks (for the same reason)
  # Run brew bundle install if check fails. Let brew handle idempotency. Continue script even if bundle fails.
  # Note: Split into taps, formulae and casks separately so that curl doesnt timeout, and failures are isolated and reported clearly.
  # Note: Each pass includes the Brewfile preamble (non tap/brew/cask lines) to preserve Ruby DSL context (e.g. cask_args, is_arm).
  # Note: For FIRST_INSTALL, only process lines up to the first 'FIRST_INSTALL' guard in the Brewfile (which marks the end of the base install section).
  local _brew_bundle_exit=0
  if is_first_install; then
    local brewfile_content
    brewfile_content="$(sed "/^[^#].*FIRST_INSTALL/q" "${HOMEBREW_BUNDLE_FILE}")"
    brewfile_content="${brewfile_content%$'\n'*FIRST_INSTALL*}"  # strip the FIRST_INSTALL guard line itself
    brew bundle check || brew bundle --file=- <<<"${brewfile_content}" || _brew_bundle_exit=$?
  else
    brew bundle check || brew bundle || _brew_bundle_exit=$?
  fi

  if [[ "${_brew_bundle_exit}" -eq 0 ]]; then
    success 'Successfully installed cmd-line and gui apps using homebrew'
  else
    _record_warning 'Homebrew bundle install encountered errors; continuing...'
  fi

  if is_first_install; then
    # The base section is done; fork the full Brewfile install in the background so
    # optional/heavy packages install without blocking the rest of this run.
    # FIRST_INSTALL is unset in the subshell so brew bundle runs the complete Brewfile.
    local _full_bundle_log="${HOME}/brew-bundle-full-install.log"
    # Temporarily disable ERR trap: background job failures should not abort the main script.
    # The background job logs to _full_bundle_log; users can check that file for issues.
    trap - ERR
    FIRST_INSTALL= brew bundle >>"${_full_bundle_log}"  2>&1 &|
    trap '_cleanup_and_exit "${LINENO}"' ERR
    info "Full Brewfile install running in background (log: '$(cyan "${_full_bundle_log}")')"
  fi

  # Note: load all zsh config files for the 2nd time for PATH and other env vars to take effect (due to defensive programming)
  DEBUG=true load_zsh_configs

  if is_first_install; then
    trap '_cleanup_and_exit "${LINENO}"' ERR
  fi

  # TODO: Commented out to avoid the second touchId popup. Need to investigate how to solve this.
  # is_arm && sudo rm -rf /usr/local/bin/keybase /usr/local/bin/git-remote-keybase || true
  step_end
}

# Set the default login shell to Homebrew's zsh.
# macOS ships with /bin/zsh but Homebrew's zsh is newer and managed independently.
# chsh requires the target shell to be listed in /etc/shells -- add it if absent.
# Without this, iTerm2's "Login shell" setting uses /bin/zsh (system) even when
# /opt/homebrew/bin/zsh is on PATH, and $SHELL stays /bin/zsh after a fresh install.
_set_default_shell() {
  _current_section='Set default shell'
  step_start
  section_header "$(yellow 'Setting default shell to Homebrew zsh')"

  local _brew_zsh="${HOMEBREW_PREFIX}/bin/zsh"

  if ! is_executable "${_brew_zsh}"; then
    _record_error "Homebrew zsh not found at '$(cyan "${_brew_zsh}")' -- skipping default shell change."
    step_end
    return 1
  fi

  # /etc/shells must list the shell before chsh will accept it.
  if ! /usr/bin/grep -qxF "${_brew_zsh}" /etc/shells; then
    info "Adding '$(yellow "${_brew_zsh}")' to /etc/shells"
    echo "${_brew_zsh}" | sudo tee -a /etc/shells >/dev/null
  else
    info "'$(yellow "${_brew_zsh}")' already in /etc/shells -- skipping."
  fi

  # Check which zsh would be invoked by PATH, not just what SHELL is set to.
  # On FIRST_INSTALL, SHELL is still /bin/zsh but Homebrew's bin directory is now
  # in PATH, so 'which zsh' returns the Homebrew version. Skip chsh if the correct
  # zsh is already active in the current session.
  local active_zsh
  active_zsh="$(which zsh)"
  if [[ "${active_zsh}" == "${_brew_zsh}" ]]; then
    info "Active zsh in PATH is already '$(yellow "${_brew_zsh}")' -- skipping chsh."
  else
    if chsh -s "${_brew_zsh}"; then
      success "Default shell changed to '$(cyan "${_brew_zsh}")'."
    else
      _record_warning "Failed to change default shell to '$(cyan "${_brew_zsh}")'. You may need to run 'chsh -s ${_brew_zsh}' manually after the installation completes."
    fi
  fi

  step_end
}

# Ensures keybase is installed and the current user is logged in.
# Thin wrapper that delegates to Ruby Keybase.ensure_logged_in.
# Returns non-zero on failure so callers can check the exit code.
#
# IMPORTANT: This is called after load_zsh_configs, which re-sources .shellrc
# after unfunctioning the guard. By that point, DOTFILES_DIR exists (cloned by
# _clone_dot_files_repo), so .shellrc sets RUBYLIB correctly, making 'require'
# work without $LOAD_PATH.unshift.
_ensure_keybase_logged_in() {
  if ! command_exists keybase; then
    error "'keybase' command not found in the PATH. Aborting!!!"
    return 1
  fi
  ruby -e "require 'keybase'; exit(Keybase.ensure_logged_in ? 0 : 1)"
}

# Builds the keybase:// URL for the given repo name owned by KEYBASE_USERNAME.
# Usage: _build_keybase_repo_url <repo-name>
_build_keybase_repo_url() {
  echo "keybase://private/${KEYBASE_USERNAME:-}/${1:-}"
}

# Clone the Keybase home repo (private configs)
_clone_home_repo() {
  _current_section='Clone home repo'
  step_start
  section_header2 "$(yellow 'Cloning') '$(cyan "${KEYBASE_HOME_REPO_NAME:-}")' repo"
  if is_non_zero_string "${KEYBASE_HOME_REPO_NAME:-}"; then
    if is_git_repo "${HOME}"; then
      # Pre-configured machine: pull latest changes to get fresh backup files
      info "Home repo already exists -- pulling latest changes"
      if git -C "${HOME}" pull --rebase; then
        success "Successfully updated home repo"
      else
        _record_warning "Failed to pull home repo -- continuing with existing backup files"
      fi
    elif clone_repo_into "$(_build_keybase_repo_url "${KEYBASE_HOME_REPO_NAME:-}")" "${HOME}"; then
      # Vanilla OS: clone succeeded
      # Reset ssh keys' permissions so that git doesn't complain when using them
      set_ssh_folder_permissions

      # Fix /etc/hosts file to block facebook
      if is_file "${PERSONAL_CONFIGS_DIR}/etc.hosts"; then sudo cp "${PERSONAL_CONFIGS_DIR}/etc.hosts" /etc/hosts; fi
    else
      _record_error 'Failed to clone home repo'
    fi
  else
    info "Skipping cloning of home repo since the '$(purple 'KEYBASE_HOME_REPO_NAME')' env var hasn't been set"
  fi
  step_end
}

# Clone the Keybase profiles repo (browser profiles)
_clone_profiles_repo() {
  _current_section='Clone profiles repo'
  step_start
  section_header2 "$(yellow 'Cloning') '$(cyan "${KEYBASE_PROFILES_REPO_NAME:-}")' repo"
  if is_non_zero_string "${KEYBASE_PROFILES_REPO_NAME:-}" && is_non_zero_string "${PERSONAL_PROFILES_DIR}"; then
    if ! clone_repo_into "$(_build_keybase_repo_url "${KEYBASE_PROFILES_REPO_NAME:-}")" "${PERSONAL_PROFILES_DIR}"; then
      _record_error 'Failed to clone profiles repo'
    fi
  else
    info "Skipping cloning of profiles repo since either the '$(purple 'KEYBASE_PROFILES_REPO_NAME')' or the '$(purple 'PERSONAL_PROFILES_DIR')' env var hasn't been set"
  fi
  step_end
}

main() {
  # Suspend cron early before .shellrc or .aliases are available -- neither
  # suspend_cron nor with_cron_suspended can be called yet, so the backup and
  # removal are done inline here. Even after both files are sourced, the
  # with_cron_suspended wrapper is not appropriate: the suspend/resume scope
  # spans the entire main(), not a single delegated function call.
  # Once .shellrc is sourced, the EXIT and ERR traps use resume_cron/recron
  # from .shellrc for restore.
  export _DOTFILES_CRON_BACKUP_FILE="${TMPDIR:-/tmp}/crontab_backup"
  crontab -l >"${_DOTFILES_CRON_BACKUP_FILE}"  2>/dev/null || : >"${_DOTFILES_CRON_BACKUP_FILE}"
  crontab -r &>/dev/null || true

  trap '_cleanup_and_exit "${LINENO}"' ERR
  trap 'rm -f "${_DOTFILES_CRON_BACKUP_FILE}"; _decrement_script_depth' EXIT

  export ZDOTDIR="${ZDOTDIR:-"${HOME}"}"

  # On a first install ~/.gitconfig is not yet in place (install-dotfiles.rb runs later),
  # so core.sshCommand is absent. Export GIT_SSH_COMMAND for the entire run to ensure the
  # connect timeout is honoured uniformly for all git operations.
  # Raw form: this runs in main() before _download_and_source_shellrc has sourced .shellrc,
  # so is_first_install is not yet defined.
  # if/fi avoids the && pattern where [[ -n ... ]] returning false (not a first install,
  # the common case on a pre-configured machine) propagates a non-zero exit under the ERR trap.
  if [[ -n "${FIRST_INSTALL:-}" ]]; then export GIT_SSH_COMMAND="ssh -o ConnectTimeout=20"; fi

  # ~/.curlrc is not yet symlinked (install-dotfiles.rb runs later), so its defaults are
  # absent. Define resilient curl flags explicitly for all bootstrap curl calls in this
  # script. Once ~/.curlrc is in place these flags are redundant but harmless.
  # Note: defined as an array so it expands correctly without word-splitting issues.
  # Curl retry/timeout flags for bootstrap downloads before ~/.curlrc is symlinked.
  # Uses CURL_RETRY_OPTS env var as a flag - if set (to any value), enables retry options.
  # Otherwise only sets defaults when ~/.curlrc is not present.
  # Note: --retry-all-errors is intentionally omitted -- it causes the terminal app to close.
  # Raw -f used here -- .shellrc has not been sourced yet, so is_file is unavailable.
  local -a _curl_retry_opts
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
  local -a _step_warnings=()
  local -a _step_errors=()
  local -a _script_start_times=()
  local -a _step_start_times=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  # Note: Cannot load from shellrc since that file won't be present in a new machine (vanilla OS)
  # $EPOCHSECONDS is provided by the zsh/datetime built-in module -- always available, no fork.
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

  _setup_jio_dns
  _download_and_source_shellrc
  keep_sudo_alive
  _approve_fingerprint_sudo
  _ensure_filevault_is_on
  _install_xcode_command_line_tools
  set_ssh_folder_permissions
  _ensure_directories_exist
  _clone_dot_files_repo

  # On FIRST_INSTALL: validate that the curl-downloaded ~/.shellrc matches the repo version
  # BEFORE install-dotfiles.rb runs (which would move the curl-downloaded version into the
  # repo, making them identical). If they differ, the GitHub-cached version is stale and
  # will cause failures when .zshrc sources it (e.g., missing parameter guards).
  # Abort early and instruct the user to wait for GitHub's cache to refresh.
  # Note: This only runs on vanilla OS (FIRST_INSTALL set). On pre-configured machines,
  # ~/.shellrc is already a symlink to the repo version, so this check is not needed.
  # Note: Use raw zsh tests here -- utility functions may be from the stale curl-downloaded
  # .shellrc, so we avoid depending on them for the validation logic itself.
  if [[ -n "${FIRST_INSTALL:-}" && -n "${DOTFILES_DIR:-}" && -d "${DOTFILES_DIR}" ]]; then
    if ! /usr/bin/diff -q "${HOME}/.shellrc" "${DOTFILES_DIR}/files/--HOME--/.shellrc" >/dev/null 2>&1; then
      echo "ERROR: [FIRST_INSTALL] The curl-downloaded ~/.shellrc differs from the repo version." >&2
      echo "This indicates GitHub's raw.githubusercontent.com cache is stale." >&2
      echo "" >&2
      echo "Diff output:" >&2
      /usr/bin/diff -u "${HOME}/.shellrc" "${DOTFILES_DIR}/files/--HOME--/.shellrc" | head -50 >&2
      echo "" >&2
      echo "Wait 5-10 minutes for the cache to refresh, then re-run this script." >&2
      echo "Alternatively, manually copy the repo version:" >&2
      echo "  cp '${DOTFILES_DIR}/files/--HOME--/.shellrc' '${HOME}/.shellrc'" >&2
      echo "  source '${HOME}/.shellrc'" >&2
      echo "  ${0} \$@" >&2
      exit 1
    fi
  fi

  # run this outside of the clone function, since it needs to be run irrespective of whether the dotfiles repo was pre-existing or not
  append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"
  install-dotfiles.rb

  # On FIRST_INSTALL: install-dotfiles.rb moves the curl-downloaded ~/.shellrc into the repo,
  # overwriting the committed version. Even though we validated they matched before install-dotfiles.rb,
  # we need to restore the committed version so the symlink points to the correct content.
  # Then force re-source so the functions in the current process are from the restored version.
  if is_first_install; then
    if ! git -C "${DOTFILES_DIR}" diff --quiet -- 'files/--HOME--/.shellrc'; then
      git -C "${DOTFILES_DIR}" checkout -- 'files/--HOME--/.shellrc'
      # Force re-source the restored version by unfunctioning the guard immediately before sourcing
      if (($+functions[is_shellrc_sourced])); then unfunction is_shellrc_sourced; fi
      DEBUG=true source "${HOME}/.shellrc"
    fi
  fi

  # ~/.gitconfig is now symlinked by install-dotfiles.rb -- core.sshCommand is in effect.
  # Unset GIT_SSH_COMMAND immediately so it no longer overrides core.sshCommand.
  # Must happen before any subsequent git operations.
  unset GIT_SSH_COMMAND

   # Load all zsh config files for PATH and other env vars to take effect
   # load_zsh_configs internally calls unfunction for both is_shellrc_sourced and
   # is_aliases_sourced, so no need to do it here.
   DEBUG=true load_zsh_configs
   # ~/.zsh_plugins.zsh (the antidote bundle) is checked into the home git repo and was
   # symlinked by install-dotfiles.rb above, so it is present on both vanilla OS and
   # pre-configured machines. .zshrc sources the bundle, which defines zsh-defer, and
   # then defers .aliases loading to the next ZLE idle event. In a non-interactive
   # script context there is no ZLE idle event, so the deferred callback never fires.
   # Source .aliases directly to make its functions (resurrect_tracked_repos, etc.)
   # available in this process.
   # The is_aliases_sourced guard inside .aliases prevents double-loading.
   load_file_if_exists "${HOME}/.aliases"

   _install_homebrew

  # Migrate repos cloned before Homebrew's git (2.45+) was on PATH. The system
  # git on a vanilla macOS ignores -c init.defaultRefFormat=reftable and does not
  # support 'git refs migrate', so clone_repo_into's migration call was a no-op
  # for those early clones. Now that Homebrew's git is available, migrate them.
  _current_section='Migrate repos to reftable'
  step_start
  section_header "$(yellow 'Migrating repos to reftable format')"
  migrate_git_repo_to_reftable "${DOTFILES_DIR}"
  step_end

  if is_non_zero_string "${KEYBASE_USERNAME:-}"; then
    section_header "$(yellow 'Cloning') '$(cyan 'keybase')' repos"
    # Login into Keybase
    step_start
    _ensure_keybase_logged_in || return 1
    step_end

    _clone_home_repo

    _clone_profiles_repo
  else
    info "Skipping cloning of any keybase repo since '$(yellow 'KEYBASE_USERNAME')' has not been set"
  fi

  if is_file "${HOME}/.ssh/known_hosts.old"; then rm -f "${HOME}/.ssh/known_hosts.old"; fi

  # Restore the preferences from the older machine into the new one.
  _current_section='Restore preferences'
  step_start
  section_header "$(yellow 'Restore preferences')"
  if command_exists 'osx-defaults.sh'; then
    osx-defaults.sh -s
    success 'Successfully baselines preferences'
  else
    _record_error "Skipping baselining of preferences since '$(purple 'osx-defaults.sh')' couldn't be found in the PATH; Please baseline manually and follow it up with re-import of the backed-up preferences"
  fi

  if command_exists 'capture-prefs.rb'; then
    # On pre-configured machines, refresh backup before import if stale
    if ! is_first_install; then
      info "Pre-configured machine detected -- refreshing preferences backup first"
      if capture-prefs.rb -e; then
        success 'Successfully refreshed preferences backup'
        # Commit using git sci (amends if ahead of remote, creates new if not)
        # capture-prefs.rb -e already staged the files, so just commit
        # This updates the backup's git timestamp so import validation passes
        if is_git_repo "${HOME}"; then
          # sci aborts with message if nothing staged (returns 0 but doesn't commit)
          if git -C "${HOME}" sci "Preferences backup: $(date '+%Y-%m-%d %H:%M:%S')"; then
            success "Committed preferences backup"
          else
            _record_warning "Failed to commit backup -- timestamp check may fail"
          fi
        else
          _record_warning "HOME is not a git repo -- skipping commit, timestamp check may fail"
        fi
      else
        _record_warning 'Failed to refresh backup -- will attempt import with existing backup'
      fi
    fi

    capture-prefs.rb -i
    success 'Successfully restored preferences from backup'
  else
    _record_error "Skipping importing of preferences since '$(purple 'capture-prefs.rb')' couldn't be found in the PATH; Please set it up manually"
  fi

  # Launch Sol.app if installed and not already running
  if is_directory '/Applications/Sol.app'; then
    if ! pgrep -x 'Sol' &>/dev/null; then
      open /Applications/Sol.app
    fi
  fi
  info "About to call step_end after preferences restoration..."
  step_end
  info "step_end completed successfully"

  # Recreate the zsh completions.
  info "Starting zsh completions section..."
  step_start
  section_header "$(yellow 'Recreate zsh completions')"
  rm -rf "${XDG_CACHE_HOME}/zcompdump"* &>/dev/null  || true
  autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump" &>/dev/null  || true
  step_end

  # Setup cron jobs.
  _current_section='Setup cron jobs'
  step_start
  section_header "$(yellow 'Setup cron jobs')"
  if command_exists recron; then
    # Remove the backup before calling recron so that if any subsequent step fails the EXIT trap
    # finds nothing to restore, preventing a stale backup file from persisting across runs.
    rm -f "${_DOTFILES_CRON_BACKUP_FILE}"
    recron
  else
    _record_error "Skipping setting up of cron jobs since '$(purple 'recron')' couldn't be found; Please set it up manually"
  fi
  step_end

  # Resurrect tracked repos. With shallow cloning (FIRST_INSTALL), large repos
  # download much faster, making this call non-blocking enough to run in-line.
  # resurrect_tracked_repos calls setup_dev_environment internally.
  _current_section='Resurrect tracked repos'
  info "Checking if resurrect_tracked_repos function is available..."
  if command_exists resurrect_tracked_repos; then
    info "resurrect_tracked_repos found -- calling it now"
    resurrect_tracked_repos
  else
    _record_error "Skipping resurrecting tracked repos since '$(purple 'resurrect_tracked_repos')' couldn't be found in the PATH; Please run it manually"
  fi

  # To install the latest versions of the hex, rebar and phoenix packages
  # mix local.hex --force && mix local.rebar --force
  # mix archive.install hex phx_new 1.4.1

  # To install the native-image tool after graalvm is installed
  # gu install native-image

  # vagrant plugin install vagrant-vbguest

  # Default tooling for dotnet projects
  # dotnet tool install -g dotnet-sonarscanner
  # dotnet tool install -g dotnet-format

  # Set default shell to Homebrew zsh - done at the end to avoid blocking the
  # automated flow with password prompts. On vanilla OS without cached sudo
  # credentials, chsh requires password entry.
  _set_default_shell

  # Print grouped summary of all collected warnings and errors, print duration,
  # then send exactly one notification. Exit code is unchanged (0) -- the summary
  # is informational only.
  print_script_summary "${script_start_time}" '** Finished auto installation process **'
  # On FIRST_INSTALL, remind user to unshallow repos to get full history.
  if is_non_zero_string "${FIRST_INSTALL:-}"; then
    user_action "Repositories were cloned shallow (--depth=1) to save time during the first installation process. Run '$(yellow 'all pull-unshallow')' to pull full history."
  fi

  local -a _notification_parts=()
  _build_notification_parts _notification_parts 'long'
  if is_non_empty_array _notification_parts; then
    local _notification_body
    _notification_body="${(j: | :)_notification_parts}"
    _dotfiles_notify "Install done -- ${_notification_body}" "⚠️ Fresh Install" || true
  else
    _dotfiles_notify "Fresh install completed successfully." "✅ Fresh Install Done" || true
  fi
}

main "$@"
