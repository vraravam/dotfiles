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

# Set DNS to 1.1.1.1 if on Jio ISP (GitHub may otherwise not resolve)
_setup_jio_dns() {
  local _org
  # Capture curl output into a variable first; then test with a glob match.
  # Previously: curl ... | /usr/bin/grep -qi 'jio' -- two processes + pipe.
  # Now: single curl fork, pure-zsh lowercase expansion (:l) + glob match.
  _org=$(curl -fsS https://ipinfo.io/org 2>/dev/null)
  if [[ "${_org:l}" == *jio* ]]; then
    echo '==> Setting DNS for WiFi from Jio ISP'
    networksetup -setdnsservers Wi-Fi 1.1.1.2 9.9.9.9 || echo 'Warning: Failed to set DNS for Wi-Fi'
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

  if [[ -n "${reason}" ]]; then
    echo "==> Downloading .shellrc from GitHub (${reason})"
    # Cache-busting: append timestamp to URL and add no-cache headers to ensure we bypass
    # GitHub's CDN cache and intermediate proxies to get the latest version.
    curl "${_cache_bust_headers[@]}" "${_curl_retry_opts[@]}" -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/files/--HOME--/.shellrc?$(/bin/date +%s)" -o "${HOME}/.shellrc"
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
  _step_header "$(yellow 'Verifying FileVault status')"
  if [[ "$(fdesetup isactive)" != 'true' ]]; then
    user_action "Enable FileVault: System Settings -> Privacy & Security -> FileVault -> Turn On FileVault"
    error 'FileVault is not turned on. Please encrypt your hard disk!'
    exit 1
  fi
  step_end
}

# Install Xcode Command Line Tools via non-interactive, non-gui softwareupdate
_install_xcode_command_line_tools() {
  _current_section='Install Xcode Command Line Tools'; _current_section_manual=1
  step_start
  _step_header "$(yellow 'Listing available software updates')"
  softwareupdate --list 2>&1 | grep '^\*' || true
  step_end

  step_start
  _step_header "$(yellow 'Installing xcode command-line tools')"
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

# Create core XDG directories needed before install-dotfiles.rb runs.
# Note: ${DOTFILES_DIR} is created by clone_repo_into's ensure_dir_exists call.
# Note: ${ANTIDOTE_HOME} and other tool-specific subdirectories (e.g., ${XDG_CONFIG_HOME}/pg,
# ${XDG_STATE_HOME}/vim/undo) are created automatically by their respective tools or by
# install-dotfiles.rb when it creates symlinks to those locations.
_ensure_directories_exist() {
  step_start
  _step_header "$(yellow 'Creating XDG base directories')"
  local -a dirs=(
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
      append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"
    else
      error 'Failed to clone dotfiles repo'
      exit 1
    fi
  else
    info "Skipping cloning the dotfiles repo since '$(cyan "${DOTFILES_DIR}")' already exists and is a git repo"
  fi

  # Setup the DOTFILES_DIR repo's upstream remote (points at the repo this fork was
  # derived from). This runs regardless of whether the repo was just cloned or
  # already existed. add-upstream-git-config.rb is idempotent and no-ops cleanly
  # both when 'upstream' already exists and when origin's own owner already
  # matches UPSTREAM_GH_USERNAME (e.g. running this on the upstream owner's own
  # machine) -- so no GH_USERNAME comparison is needed here.
  COLUMNS="${COLUMNS}" add-upstream-git-config.rb -d "${DOTFILES_DIR}" -u "${UPSTREAM_GH_USERNAME}" || _record_warning 'Failed to add upstream git config for dotfiles repo'
  step_end
}

# Install homebrew, tap repos, and run brew bundle
_install_homebrew() {
  _current_section='Install Homebrew'; _current_section_manual=1
  step_start
  _step_header "$(yellow 'Installing homebrew') into '$(cyan "${HOMEBREW_PREFIX}")'"
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
    # First pass: install taps and already-trusted formulae/casks
    # Suppress stderr since untrusted-tap errors are expected and fixed by second pass
    brew bundle check -v || brew bundle install -q --file=- <<<"${brewfile_content}" || _brew_bundle_exit=$?
  else
    # First pass: install taps and already-trusted formulae/casks
    # Suppress stderr since untrusted-tap errors are expected and fixed by second pass
    brew bundle check -v || brew bundle install -q || _brew_bundle_exit=$?
  fi

  if [[ "${_brew_bundle_exit}" -eq 0 ]]; then
    success 'Successfully installed cmd-line and gui apps using homebrew'
  else
    _record_warning 'Homebrew bundle install encountered errors; continuing...'
  fi

  # Homebrew cask 'postinstall:' hooks only run when 'brew bundle install' actually
  # (re)installs the cask -- if 'brew bundle check' above already reported success (e.g.
  # Keybase.app was already present from an earlier partial run of this idempotent
  # script), postinstall never fires, silently leaving the 'keybase' CLI symlink missing
  # even though the app itself is installed and usable. The Brewfile's own postinstall
  # for this cask already creates these symlinks too -- this is a redundant safety net
  # for exactly that postinstall-skipped case. Both are safe to run every time since
  # 'ln -sf' is idempotent. No KEYBASE_*_REPO_NAME gate needed here -- if the cask was
  # never installed (Keybase disabled), the directory check below simply never matches.
  if is_directory '/Applications/Keybase.app'; then
    ln -sf '/Applications/Keybase.app/Contents/SharedSupport/bin/keybase' "${HOMEBREW_PREFIX}/bin/keybase"
    ln -sf '/Applications/Keybase.app/Contents/SharedSupport/bin/git-remote-keybase' "${HOMEBREW_PREFIX}/bin/git-remote-keybase"
  fi

  if is_first_install; then
    # The base section is done; fork the full Brewfile install in the background so
    # optional/heavy packages install without blocking the rest of this run.
    # FIRST_INSTALL is unset in the subshell so brew bundle runs the complete Brewfile.
    local _full_bundle_log="${HOME}/Downloads/brew-bundle-full-install.log"
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
# /opt/homebrew/bin/zsh is on PATH, and ${SHELL} stays /bin/zsh after a fresh install.
_set_default_shell() {
  _current_section='Set default shell'; _current_section_manual=1
  step_start
  _step_header "$(yellow 'Setting default shell to Homebrew zsh')"

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

  # Check the user's configured default shell (not the current ${SHELL} env var).
  # ${SHELL} reflects the current terminal session; dscl shows what chsh configured.
  # This ensures we only run chsh if the login shell for future sessions needs updating.
  local configured_shell
  configured_shell="$(dscl . -read ~ UserShell | awk '{print $NF}')"
  if [[ "${configured_shell}" == "${_brew_zsh}" ]]; then
    info "Default shell is already configured as '$(cyan "${_brew_zsh}")' -- skipping."
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
# work without ${LOAD_PATH}.unshift.
_ensure_keybase_logged_in() {
  if ! command_exists keybase; then
    error "'keybase' command not found in the PATH. Aborting!!!"
    return 1
  fi

  # Keybase.app's kbnm (native messaging) installer writes into each installed browser's
  # Application Support directory on first launch (e.g. .../Google/Chrome) to register its
  # browser-extension messaging host. Google's own auto-update tooling (Keystone/
  # GoogleSoftwareUpdate) is known to sometimes leave '~/Library/Application Support/Google'
  # owned by a different user (observed on a vanilla-OS run) -- if so, kbnm's mkdir fails
  # with "operation not permitted" and Keybase.app pops up a blocking error dialog, which
  # can stall this non-interactive bootstrap since there is nobody around to dismiss it.
  # Fix ownership defensively before launching, using the exact fix the dialog itself
  # suggests. sudo is already primed (keep_sudo_alive runs earlier in main()).
  local google_support_dir="${HOME}/Library/Application Support/Google"
  if is_directory "${google_support_dir}" && [[ "$(stat -f '%Su' "${google_support_dir}")" != "${USER}" ]]; then
    info "Fixing ownership of '$(cyan "${google_support_dir}")' (was owned by a different user)"
    sudo chown -R "${USER}:staff" "${google_support_dir}"
  fi

  # The keybase CLI talks to a background service (keybased) that is normally started
  # when Keybase.app first launches -- e.g. via the login item registered by the
  # Brewfile's postinstall hook, which only takes effect on the *next* login. On a
  # single-session vanilla-OS run the user never logs out/in, so the service is never
  # started, and 'keybase login' fails with "dial unix .../keybased.sock: no such file
  # or directory". Launch the app hidden (no Dock/focus steal) and wait briefly for the
  # service to come up before attempting login.
  if ! keybase status &>/dev/null; then
    info 'Starting Keybase service'
    open -g -a Keybase
    local i
    for ((i = 0; i < 15; i++)); do
      if keybase status &>/dev/null; then
        break
      fi
      sleep 1
    done
  fi

  call_ruby_utility "require 'keybase'; exit(Keybase.ensure_logged_in ? 0 : 1)"
}

# Builds the keybase:// URL for the given repo name, owned by whoever is
# currently logged into Keybase. Derived dynamically via Keybase.username
# (which reads 'keybase status') -- no username is stored anywhere; whoever
# completes the interactive login in _ensure_keybase_logged_in owns the account.
# Usage: _build_keybase_repo_url <repo-name>
_build_keybase_repo_url() {
  local username
  username="$(call_ruby_utility "require 'keybase'; puts Keybase.username")"
  echo "keybase://private/${username}/${1:-}"
}

# Configures remote_url as a git remote on target_folder -- 'origin' if no other
# remote exists yet, 'origin2' if 'origin' is already something else (e.g. the other
# backup mechanism, or a remote configured in a previous run). Idempotent: no-ops if
# remote_url is already configured as either 'origin' or 'origin2'. Shared by both
# backup mechanisms (Keybase and the gpg+git-bundle encrypted backup) so they can
# coexist on the same repo, each pushed/pulled explicitly and independently -- see
# KeybaseMigration.md. Never fans a URL into an existing remote's push URLs -- each
# mechanism always gets its own separately-named remote.
_configure_backup_remote() {
  local target_folder="${1:?}"
  local remote_url="${2:?}"

  # Already configured as either remote -- nothing more to do.
  if git -C "${target_folder}" remote get-url origin 2>/dev/null | /usr/bin/grep -qxF "${remote_url}"; then
    return 0
  fi
  if git -C "${target_folder}" remote get-url origin2 2>/dev/null | /usr/bin/grep -qxF "${remote_url}"; then
    return 0
  fi

  if ! git -C "${target_folder}" remote get-url origin &>/dev/null; then
    git -C "${target_folder}" remote add origin "${remote_url}"
    success "Added 'origin' -> '$(cyan "${remote_url}")' for '$(cyan "${target_folder}")'"
  elif ! git -C "${target_folder}" remote get-url origin2 &>/dev/null; then
    git -C "${target_folder}" remote add origin2 "${remote_url}"
    success "Added 'origin2' -> '$(cyan "${remote_url}")' for '$(cyan "${target_folder}")' (separate from 'origin' -- push/pull each explicitly)"
  else
    _record_warning "Both 'origin' and 'origin2' are already configured on '$(cyan "${target_folder}")' with different URLs -- not adding '$(cyan "${remote_url}")'. Add it manually under a different remote name if you want it too."
  fi
}

# Clones the home repo (private configs) from whichever backup mechanism(s) are
# enabled (KEYBASE_HOME_REPO_NAME and/or ENCRYPTED_HOME_REPO_URL -- see
# KeybaseMigration.md for how they coexist). Keybase is tried first (original
# mechanism, historical precedence); the gpg+git-bundle encrypted backup (external
# 'git-remote-gpg-encrypt' tool, installed via the 'vraravam/tap' Homebrew tap) is the
# fallback, or the only option if Keybase isn't enabled/available. Whichever succeeds
# performs the actual clone; if the other mechanism is also enabled, it is configured
# as an additional remote (via _configure_backup_remote) rather than cloned from again.
_clone_home_repo() {
  _current_section='Clone home repo'; _current_section_manual=1
  step_start

  local keybase_repo_name="${KEYBASE_HOME_REPO_NAME:-}"
  local encrypted_repo_url="${ENCRYPTED_HOME_REPO_URL:-}"

  if is_git_repo "${HOME}"; then
    # Pre-configured machine: pull latest changes to get fresh backup files.
    # Uses 'pull-safe' (not a bare 'pull --rebase') for 'with-retry' hang protection and
    # a clean-working-tree guard, consistent with every other repo-sync path in this script.
    _step_header 'Updating home repo'
    info "Home repo already exists -- pulling latest changes"
    configure_branch_tracking_for_origin "${HOME}"
    if git -C "${HOME}" pull-safe; then
      success "Successfully updated home repo"
    else
      _record_warning "Failed to pull home repo -- continuing with existing backup files"
    fi
  else
    _step_header 'Cloning home repo'
    local cloned_via=''

    if is_non_zero_string "${keybase_repo_name}"; then
      if command_exists keybase && _ensure_keybase_logged_in && clone_repo_into "$(_build_keybase_repo_url "${keybase_repo_name}")" "${HOME}"; then
        cloned_via='keybase'
        success "Successfully cloned home repo from Keybase"
      else
        _record_warning 'Failed to clone home repo from Keybase -- will try encrypted-backup next if enabled'
      fi
    fi

    if is_zero_string "${cloned_via}" && is_non_zero_string "${encrypted_repo_url}"; then
      # The Keychain-passphrase reminder for this step is printed much earlier, right
      # after '.shellrc' is downloaded/sourced in main() -- see the comment there for why.
      if command_exists git-gpg-encrypt-restore && git-gpg-encrypt-restore "${encrypted_repo_url}" "${HOME}"; then
        cloned_via='encrypted-backup'
        # A bundle-based import ('git clone <bundle-file>') never creates an 'origin'
        # remote at all (confirmed empirically: 'git remote get-url origin' errors
        # "No such remote" immediately after) -- 'remote add' here, not 'remote set-url'
        # (which requires the remote to already exist and would fail silently otherwise,
        # since this line's own exit code isn't checked). If Keybase is ALSO configured
        # (just failed/unavailable this run), it should still end up as 'origin' -- see
        # the '_configure_backup_remote' calls below -- so claim 'origin2' directly here
        # instead of 'origin', leaving 'origin' free for Keybase to claim.
        local remote_name='origin'
        if is_non_zero_string "${keybase_repo_name}"; then remote_name='origin2'; fi
        git -C "${HOME}" remote add "${remote_name}" "gpg-encrypt::${encrypted_repo_url}"
        success "Successfully cloned home repo from encrypted backup"
      else
        _record_error 'Failed to clone home repo from encrypted backup'
      fi
    fi

    if is_non_zero_string "${cloned_via}"; then
      # Reset ssh/gnupg permissions so git/gpg don't complain -- both '.ssh' and '.gnupg'
      # (including GPG private keys under .gnupg/private-keys-v1.d) are tracked in the home
      # repo, and git checkout does not preserve the strict permission modes either needs.
      set_ssh_folder_permissions
      set_gnupg_folder_permissions

      # Fix /etc/hosts file to block facebook
      if is_file "${PERSONAL_CONFIGS_DIR}/etc.hosts"; then sudo cp "${PERSONAL_CONFIGS_DIR}/etc.hosts" /etc/hosts; fi
    elif is_non_zero_string "${keybase_repo_name}" || is_non_zero_string "${encrypted_repo_url}"; then
      _record_error 'Failed to clone home repo from any enabled backup mechanism'
    else
      info "Skipping cloning of home repo since neither '$(yellow 'KEYBASE_HOME_REPO_NAME')' nor '$(yellow 'ENCRYPTED_HOME_REPO_URL')' env var has been set"
    fi
  fi

  # Ensure remotes for both enabled mechanisms are present, whether the repo was just
  # cloned above or already existed -- idempotent, safe to call every run.
  if is_git_repo "${HOME}"; then
    if is_non_zero_string "${keybase_repo_name}"; then
      _configure_backup_remote "${HOME}" "$(_build_keybase_repo_url "${keybase_repo_name}")"
    fi
    if is_non_zero_string "${encrypted_repo_url}"; then
      _configure_backup_remote "${HOME}" "gpg-encrypt::${encrypted_repo_url}"
    fi
  fi

  step_end
}

# Clones the browser-profiles repo (personal browser profile data) from whichever
# backup mechanism(s) are enabled -- same Keybase-first, encrypted-backup-fallback
# precedence as _clone_home_repo above.
_clone_profiles_repo() {
  _current_section='Clone profiles repo'; _current_section_manual=1
  step_start

  local keybase_repo_name="${KEYBASE_PROFILES_REPO_NAME:-}"
  local encrypted_repo_url="${ENCRYPTED_PROFILES_REPO_URL:-}"

  if is_zero_string "${PERSONAL_PROFILES_DIR}"; then
    info "Skipping cloning of profiles repo since '$(yellow 'PERSONAL_PROFILES_DIR')' env var hasn't been set"
  elif is_git_repo "${PERSONAL_PROFILES_DIR}"; then
    configure_branch_tracking_for_origin "${PERSONAL_PROFILES_DIR}"
    # This repo is periodically force-squashed by recreate-repository.rb, so it is not
    # routinely pulled here the way the home repo is above -- see the
    # pull.allowResetOnDivergedHistory config flag set below, which lets the 'pull'
    # autoload function handle that safely if/when the user pulls it manually.
    _step_header 'Profiles repo already exists -- skipping clone'
  else
    _step_header 'Cloning profiles repo'
    local cloned_via=''

    if is_non_zero_string "${keybase_repo_name}"; then
      if command_exists keybase && _ensure_keybase_logged_in && clone_repo_into "$(_build_keybase_repo_url "${keybase_repo_name}")" "${PERSONAL_PROFILES_DIR}"; then
        cloned_via='keybase'
        success "Successfully cloned browser-profiles repo from Keybase"
      else
        _record_warning 'Failed to clone browser-profiles repo from Keybase -- will try encrypted-backup next if enabled'
      fi
    fi

    if is_zero_string "${cloned_via}" && is_non_zero_string "${encrypted_repo_url}"; then
      if command_exists git-gpg-encrypt-restore && git-gpg-encrypt-restore "${encrypted_repo_url}" "${PERSONAL_PROFILES_DIR}"; then
        cloned_via='encrypted-backup'
        # See _clone_home_repo's matching comment -- a bundle-based import never
        # creates an 'origin' remote at all, so 'remote add' (not 'remote set-url').
        # If Keybase is ALSO configured, claim 'origin2' directly so Keybase can still
        # claim 'origin' via the '_configure_backup_remote' calls below.
        local remote_name='origin'
        if is_non_zero_string "${keybase_repo_name}"; then remote_name='origin2'; fi
        git -C "${PERSONAL_PROFILES_DIR}" remote add "${remote_name}" "gpg-encrypt::${encrypted_repo_url}"
        success "Successfully cloned browser-profiles repo from encrypted backup"
      else
        _record_error 'Failed to clone browser-profiles repo from encrypted backup'
      fi
    fi

    if is_zero_string "${cloned_via}"; then
      if is_non_zero_string "${keybase_repo_name}" || is_non_zero_string "${encrypted_repo_url}"; then
        _record_error 'Failed to clone browser-profiles repo from any enabled backup mechanism'
      else
        info "Skipping cloning of profiles repo since neither '$(yellow 'KEYBASE_PROFILES_REPO_NAME')' nor '$(yellow 'ENCRYPTED_PROFILES_REPO_URL')' env var has been set"
      fi
    fi
  fi

  if is_git_repo "${PERSONAL_PROFILES_DIR}"; then
    if is_non_zero_string "${keybase_repo_name}"; then
      _configure_backup_remote "${PERSONAL_PROFILES_DIR}" "$(_build_keybase_repo_url "${keybase_repo_name}")"
    fi
    if is_non_zero_string "${encrypted_repo_url}"; then
      _configure_backup_remote "${PERSONAL_PROFILES_DIR}" "gpg-encrypt::${encrypted_repo_url}"
    fi

    # This repo is periodically force-squashed by recreate-repository.rb, so 'pull'
    # (files/--XDG_CONFIG_HOME--/zsh/pull) needs to hard-reset instead of rebase when
    # local and remote history have diverged with no common ancestor -- see
    # KeybaseMigration.md. Opt-in via this per-repo config flag (idempotent, safe to
    # set on every run) rather than a dedicated pull-browser-profiles.sh override
    # script, which this replaced. Applies regardless of which backup mechanism(s) are
    # configured -- the squashing itself is what causes the divergence, not the remote.
    git -C "${PERSONAL_PROFILES_DIR}" config --local pull.allowResetOnDivergedHistory true
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
  if [[ -n "${FIRST_INSTALL:-}" ]]; then export GIT_SSH_COMMAND="ssh -o ConnectTimeout=20 -o Compression=no -o ServerAliveInterval=10 -o ServerAliveCountMax=3"; fi

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
  local _current_section_manual=0  # 0 = auto-set allowed, 1 = manual override active
  local -a _step_warnings=()
  local -a _step_errors=()

  # Progress tracking: Shows [Step N of TOTAL] in section headers
  local total_steps=14
  local current_step=0

  # Set ERR trap AFTER initializing arrays to prevent "parameter not set" errors in _cleanup_and_exit
  # if an error occurs during initialization. The trap accesses these arrays via dynamic scoping.
  trap '_cleanup_and_exit "${LINENO}"' ERR
  trap 'rm -f "${_DOTFILES_CRON_BACKUP_FILE}"; _decrement_script_depth' EXIT

  # Helper function to show progress through steps
  _step_header() {
    current_step=$((current_step + 1))
    section_header "[$(purple "Step ${current_step} of ${total_steps}")] $*"
  }

  local -a _script_start_times=()
  local -a _step_start_times=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
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

  _setup_jio_dns
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
  set_ssh_folder_permissions
  set_gnupg_folder_permissions
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
  COLUMNS="${COLUMNS}" install-dotfiles.rb

  # Force-check and recompile-if-needed the core startup files right now, as
  # their own explicit step -- deliberately not deferred to load_zsh_configs a
  # few lines below (which would also recompile .zshenv/.zshrc/.zlogin/.aliases
  # as a side effect of sourcing them). Later steps in this script (e.g.
  # resurrect_tracked_repos) can run for tens of minutes; establishing correct
  # bytecode this early -- immediately after install-dotfiles.rb (re-)creates
  # these symlinks -- means it does not depend on reaching (or the timing of)
  # any later step. recompile_zsh_script no-ops when the .zwc is already
  # current, so this costs a handful of stat calls when nothing changed.
  # This does NOT remove the need for the unconditional delete_caches call at
  # the end of this script: that call exists because a stale .zwc left over
  # from an earlier partial fresh-install attempt can have a mtime that
  # defeats this same is_file_older_than check entirely (see the comment on
  # the delete_caches step below).
  recompile_zsh_script "${ZDOTDIR}/.zshenv"
  recompile_zsh_script "${ZDOTDIR}/.zshrc"
  recompile_zsh_script "${ZDOTDIR}/.zlogin"
  recompile_zsh_script "${HOME}/.shellrc"
  recompile_zsh_script "${ZDOTDIR}/.aliases"

  # On FIRST_INSTALL: install-dotfiles.rb moves the curl-downloaded ~/.shellrc into the repo,
  # overwriting the committed version. Even though we validated they matched before install-dotfiles.rb,
  # we need to restore the committed version so the symlink points to the correct content.
  # Then force re-source so the functions in the current process are from the restored version.
  if is_first_install; then
    if ! git -C "${DOTFILES_DIR}" diff --quiet -- 'files/--HOME--/.shellrc'; then
      git -C "${DOTFILES_DIR}" checkout -- 'files/--HOME--/.shellrc'
      # Force re-source the restored version by unfunctioning the guard immediately before sourcing
      if (($+functions[is_shellrc_sourced])); then unfunction is_shellrc_sourced; fi
      # Recompile again: this checkout can change .shellrc's content/mtime after
      # the bulk recompile above already ran, making that earlier pass stale
      # relative to this specific restore. Plain 'source' (unlike
      # load_file_if_exists) does not check .zwc staleness itself, so without
      # this the re-source below could silently load bytecode compiled before
      # this checkout, defeating the restore above entirely.
      recompile_zsh_script "${HOME}/.shellrc"
      DEBUG=true source "${HOME}/.shellrc"
    fi
  fi

  # ${XDG_CONFIG_HOME}/git/config is now symlinked by install-dotfiles.rb -- core.sshCommand is in effect.
  # Unset GIT_SSH_COMMAND immediately so it no longer overrides core.sshCommand.
  # Must happen before any subsequent git operations.
  unset GIT_SSH_COMMAND

   # Load all zsh config files for PATH and other env vars to take effect
   # load_zsh_configs internally calls unfunction for both is_shellrc_sourced and
   # is_aliases_sourced, so no need to do it here.
   DEBUG=true load_zsh_configs
   # ${XDG_CONFIG_HOME}/zsh/plugins.zsh (the antidote bundle) is checked into the home git repo and was
   # symlinked by install-dotfiles.rb above, so it is present on both vanilla OS and
   # pre-configured machines. .zshrc sources the bundle, which defines zsh-defer, and
   # then defers .aliases loading to the next ZLE idle event. In a non-interactive
   # script context there is no ZLE idle event, so the deferred callback never fires.
   # Source .aliases directly to make its functions (resurrect_tracked_repos, etc.)
   # available in this process.
   # The is_aliases_sourced guard inside .aliases prevents double-loading.
   load_file_if_exists "${ZDOTDIR}/.aliases"

   _install_homebrew

  # Migrate repos cloned before Homebrew's git (2.45+) was on PATH. The system
  # git on a vanilla macOS ignores -c init.defaultRefFormat=reftable and does not
  # support 'git refs migrate', so clone_repo_into's migration call was a no-op
  # for those early clones. Now that Homebrew's git is available, migrate them.
  _current_section='Migrate repos to reftable'; _current_section_manual=1
  step_start
  _step_header "$(yellow 'Migrating repos to reftable format')"
  migrate_git_repo_to_reftable "${DOTFILES_DIR}"
  step_end

  # Log into Keybase if KEYBASE_HOME_REPO_NAME/KEYBASE_PROFILES_REPO_NAME (see
  # scripts/utilities/keybase.rb) enable it. Coexists with the encrypted-backup setup
  # below -- see KeybaseMigration.md. This is a readiness/login step only; the actual
  # clone attempt (which also calls _ensure_keybase_logged_in defensively) happens in
  # _clone_home_repo/_clone_profiles_repo below.
  _current_section='Setup Keybase'
  step_start
  section_header "$(yellow 'Setup Keybase')"
  if is_zero_string "${KEYBASE_HOME_REPO_NAME:-}" && is_zero_string "${KEYBASE_PROFILES_REPO_NAME:-}"; then
    debug "Neither 'KEYBASE_HOME_REPO_NAME' nor 'KEYBASE_PROFILES_REPO_NAME' env var is set -- skipping Keybase setup"
  elif ! command_exists keybase; then
    info "Skipping Keybase setup since '$(yellow 'keybase')' is not installed"
  elif call_ruby_utility "require 'keybase'; exit(Keybase.username ? 0 : 1)"; then
    # Already logged in (from a previous run, or 'keybase login' run manually) --
    # sync silently every time, never re-ask. This is what makes re-running this
    # idempotent script pleasant: once set up, it just stays set up.
    success 'Already logged into Keybase'
  elif is_first_install; then
    # Not logged in yet -- attempt login only on the true first-time vanilla-OS
    # bootstrap, non-interactively (no y/N gate). Re-runs on an already-configured
    # machine must NOT re-litigate this every time (see the 'else' branch below) --
    # that would turn a script designed to be safely re-run into one that blocks
    # on a login attempt every single run.
    if _ensure_keybase_logged_in; then
      success 'Successfully logged into Keybase'
    else
      _record_warning 'Keybase login failed -- continuing without Keybase-based backups'
    fi
  else
    # Pre-configured machine, not logged in, not FIRST_INSTALL: skip silently
    # rather than prompting on every maintenance re-run.
    info "Skipping Keybase login -- not logged in. Run 'keybase login' manually, then re-run this script, to enable it."
  fi
  step_end

  # Verify encrypted-backup mechanism is ready (gpg installed, Keychain passphrase set --
  # see the external 'git-remote-gpg-encrypt' tool, installed via the 'vraravam/tap'
  # Homebrew tap). Coexists with Keybase above -- see KeybaseMigration.md. gnupg
  # homedir permissions were already fixed earlier in main() (mirroring
  # set_ssh_folder_permissions) -- no need to repeat that here.
  _current_section='Setup encrypted backup'
  step_start
  section_header "$(yellow 'Setup encrypted backup')"
  if is_zero_string "${ENCRYPTED_HOME_REPO_URL:-}" && is_zero_string "${ENCRYPTED_PROFILES_REPO_URL:-}"; then
    debug "Neither 'ENCRYPTED_HOME_REPO_URL' nor 'ENCRYPTED_PROFILES_REPO_URL' env var is set -- skipping encrypted-backup setup"
  elif command_exists 'git-gpg-encrypt-setup'; then
    if git-gpg-encrypt-setup; then
      success 'Encrypted backup is ready to use'
    else
      _record_warning 'Encrypted backup is not configured -- see instructions above'
    fi
  else
    debug "git-gpg-encrypt-setup not found in PATH -- skipping encrypted backup setup"
  fi
  step_end

  # Clone repos from whichever backup mechanism(s) are enabled (home and browser-profiles)
  _current_section='Clone repos'
  step_start
  section_header "$(yellow 'Cloning repos')"

  _clone_home_repo
  _clone_profiles_repo

  step_end

  if is_file "${HOME}/.ssh/known_hosts.old"; then rm -f "${HOME}/.ssh/known_hosts.old"; fi

  # Restore the preferences from the older machine into the new one.
  step_start
  _step_header "$(yellow 'Restore preferences')"
  if command_exists 'osx-defaults.sh'; then
    osx-defaults.sh -s
    success 'Successfully baselines preferences'
  else
    _record_error "Skipping baselining of preferences since '$(purple 'osx-defaults.sh')' couldn't be found in the PATH; Please baseline manually and follow it up with re-import of the backed-up preferences"
  fi

  if command_exists 'capture-prefs.rb'; then
    # On pre-configured machines, refresh backup before import if stale
    # Export auto-commits inside capture-prefs.rb (uses smart_commit)
    if ! is_first_install; then
      info "Pre-configured machine detected -- refreshing preferences backup first"
      if COLUMNS="${COLUMNS}" capture-prefs.rb -e; then
        success 'Successfully refreshed and committed preferences backup'
      else
        _record_warning 'Failed to refresh backup -- will attempt import with existing backup'
      fi
    fi

    COLUMNS="${COLUMNS}" capture-prefs.rb -i
    success 'Successfully restored preferences from backup'
  else
    _record_error "Skipping importing of preferences since '$(purple 'capture-prefs.rb')' couldn't be found in the PATH; Please set it up manually"
  fi
  step_end

  # Recreate the zsh completions.
  step_start
  _step_header "$(yellow 'Recreate zsh completions')"
  rm -rf "${XDG_CACHE_HOME}/zcompdump"* &>/dev/null  || true
  autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump" &>/dev/null  || true
  step_end

  # Setup cron jobs.
  step_start
  _step_header "$(yellow 'Setup cron jobs')"
  if command_exists recron; then
    # Call recron first; only delete backup after successful execution.
    # This ensures the EXIT trap can still restore the original schedule if recron fails.
    if recron; then
      rm -f "${_DOTFILES_CRON_BACKUP_FILE}"
    else
      _record_error "recron failed -- original cron schedule preserved in backup"
    fi
  else
    _record_error "Skipping setting up of cron jobs since '$(purple 'recron')' couldn't be found; Please set it up manually"
  fi
  step_end

  # Resurrect tracked repos. With shallow cloning (FIRST_INSTALL), large repos
  # download much faster, making this call non-blocking enough to run in-line.
  # resurrect_tracked_repos calls setup_dev_environment internally.
  _current_section='Resurrect tracked repos'; _current_section_manual=1
  if command_exists resurrect_tracked_repos; then
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

  # Force-refresh all zsh bytecode (*.zwc) and cache files. install-dotfiles.rb
  # symlinks .zshrc/.shellrc/.aliases repeatedly across re-runs, and a stale .zwc
  # left over from an earlier partial fresh-install attempt (or a manually
  # opened terminal during debugging) can have a mtime that defeats
  # recompile_zsh_script's -nt staleness check, causing new terminals to load
  # bytecode compiled from stale source indefinitely (e.g. missing PATH entries
  # added by a later commit). delete_caches wipes every *.zwc* unconditionally
  # rather than trusting mtime comparisons, then rebuilds from current source.
  # Run this as the last content-affecting step so nothing later in the script
  # writes a cache file after the wipe.
  step_start
  _step_header "$(yellow 'Refresh zsh bytecode caches')"
  if command_exists delete_caches; then
    delete_caches
  else
    _record_warning "Skipping zsh bytecode cache refresh since '$(purple 'delete_caches')' couldn't be found; new terminals may load stale .zwc files until 'delete_caches' is run manually"
  fi
  step_end

  # Set default shell to Homebrew zsh - done at the end to avoid blocking the
  # automated flow with password prompts. On vanilla OS without cached sudo
  # credentials, chsh requires password entry.
  _set_default_shell

  # Print grouped summary of all collected warnings and errors, print duration,
  # then send exactly one notification. Exit code is unchanged (0) -- the summary
  # is informational only.
  print_script_summary "${script_start_time}" '** Finished auto installation process **'

  # Remind user of manual steps that cannot be automated
  user_action "Review System Settings manually: some settings (FileVault, accessibility permissions, notification preferences) require GUI interaction and cannot be automated due to TCC restrictions."

  # On FIRST_INSTALL, remind user to unshallow repos to get full history.
  if is_non_zero_string "${FIRST_INSTALL:-}"; then
    user_action "Repositories were cloned shallow (--depth=1) to save time. Run '$(yellow 'all unshallow')' to fetch complete history, then '$(yellow 'git rebase @{u}')' or '$(yellow 'git merge @{u}')' in each repo to update working trees."
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
