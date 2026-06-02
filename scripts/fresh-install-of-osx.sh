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

# Error trap cleanup and exit
_cleanup_and_exit() {
  # Print any non-fatal warnings and errors already collected before this fatal failure,
  # so the full context is visible alongside the crash message.
  # Uses print_script_summary when shellrc is loaded; falls back to plain echo for early failures.
  # Zsh dynamic scoping: _step_warnings and _step_errors (local in main) are visible here.
  if (($+functions[print_script_summary])); then
    print_script_summary
  else
    if (($+_step_warnings)) && [[ "${#_step_warnings[@]}" -gt 0 ]]; then
      echo '==> Collected warnings:'
      local _cae_w
      for _cae_w in "${_step_warnings[@]}"; do
        echo "  ⚠️  ${_cae_w}"
      done
    fi
    if (($+_step_errors)) && [[ "${#_step_errors[@]}" -gt 0 ]]; then
      echo '==> Collected errors:'
      local _cae_e
      for _cae_e in "${_step_errors[@]}"; do
        echo "  ❌  ${_cae_e}"
      done
    fi
  fi

  local message='Installation failed. Check for error messages above.'
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
  # Previously: curl ... | grep -qi 'jio' — two processes + pipe.
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
    # Unfunction the guard so .shellrc's own re-source check is bypassed.
    # This also handles retries on a vanilla OS where the script is re-run after an error.
    (($+functions[is_shellrc_sourced]))   && unfunction is_shellrc_sourced
    curl "${_curl_opts[@]}" -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/files/--HOME--/.shellrc" -o "${HOME}/.shellrc"
    echo "==> Successfully downloaded '${HOME}/.shellrc'"
  else
    # Pre-configured OS: skip downloading; the built-in guard makes the source below a no-op if already loaded.
    info "Skipping downloading '$(yellow "${HOME}/.shellrc")' since this is not a first install"
  fi
  DEBUG=true source "${HOME}/.shellrc"
  success "Successfully sourced '$(yellow "${HOME}/.shellrc")'"
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
  [[ -n "$(/usr/sbin/ioreg -c AppleBiometricSensor  2>/dev/null | /usr/bin/grep AppleBiometricSensor)"  ]] && has_biometric_sensor=1  || true
  [[ -n "$(/usr/sbin/ioreg -c AppleBiometricServices 2>/dev/null | /usr/bin/grep AppleBiometricServices)" ]] && has_biometric_services=1 || true
  if [[ "${has_biometric_sensor}" == 0 && "${has_biometric_services}" == 0 ]]; then
    info 'Touch ID hardware is not detected — skipping configuration.'
    step_end
    return 0  # Exit successfully as no action is needed
  fi

  local template_file='/etc/pam.d/sudo_local.template'
  if ! is_file "${template_file}"; then
    warn "Template file '$(yellow "${template_file}")' not found! Skipping!"
    step_end
    return
  fi

  local target_file='/etc/pam.d/sudo_local'
  if ! is_file "${target_file}"; then
    if sudo sh -c "sed 's/^#auth/auth/' '${template_file}' > '${target_file}'"; then
      success "Created new file: '$(yellow "${target_file}")'"
    else
      error "Failed to create '${target_file}'"
    fi
  else
    info "'$(yellow "${target_file}")' is already present — skipping."
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
    info 'Skipping installation of xcode command-line tools — already present.'
  fi
  # Note: Duplicate the cleanup if the installation was cancelled and continued via the gui
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  step_end
}

# Create all directories referenced by env vars as a pre-emptive safety step
_ensure_directories_exist() {
  step_start
  section_header "$(yellow 'Creating directories defined by various env vars')"
  local -a folders=("${ANTIDOTE_HOME}" "${DOTFILES_DIR}" "${PROJECTS_BASE_DIR}" "${PERSONAL_BIN_DIR}" "${PERSONAL_CONFIGS_DIR}" "${PERSONAL_PROFILES_DIR}" "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}")
  for folder in "${folders[@]}"; do
    ensure_dir_exists "${folder}"
  done
  step_end
}

# Clone the dotfiles repo and configure upstream
_clone_dot_files_repo() {
  _current_section='Clone dotfiles repo'
  step_start
  section_header "$(yellow 'Installing dotfiles') into '$(purple "${DOTFILES_DIR}")'"
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
      add-upstream-git-config.sh -d "${DOTFILES_DIR}" -u "${UPSTREAM_GH_USERNAME}" || _record_warning 'Failed to add upstream git config for dotfiles repo'
    else
      error 'Failed to clone dotfiles repo'
      exit 1
    fi
  else
    info "Skipping cloning the dotfiles repo since '$(yellow "${DOTFILES_DIR}")' is either not defined or is already a git repo"
  fi
  step_end
}

# Install homebrew, tap repos, and run brew bundle
_install_homebrew() {
  _current_section='Install Homebrew'
  step_start
  section_header "$(yellow 'Installing homebrew') into '$(yellow "${HOMEBREW_PREFIX}")'"
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
    if curl "${_curl_opts[@]}" -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "${install_script_file}"; then
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
    info "Skipping installation of $(yellow 'homebrew') — already installed."
  fi

  # Note: ensure that homebrew's environment variables are set correctly for this session (even if homebrew was not installed in this session)
  eval_shellenv "${HOMEBREW_PREFIX}/bin/brew" shellenv

  # Note: Temporarily disable the ERR trap since brew commands may fail on a vanilla OS (e.g. rate limits, missing deps).
  if is_first_install; then
    trap - ERR
  fi

  # Since we have moved away from any taps in the FIRST_INSTALL, this logic is no longer required.
  # TODO: Cleanup once this has been tested on a vanilla OS
  # \grep -E "^tap " "${HOMEBREW_BUNDLE_FILE}" | awk '{print $2}' | tr -d "'\"" | while read -r tap_name; do
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
    FIRST_INSTALL= brew bundle >>"${_full_bundle_log}"  2>&1 &|
    info "Full Brewfile install running in background (log: $(yellow "${_full_bundle_log}"))"
  fi

  # Note: load all zsh config files for the 2nd time for PATH and other env vars to take effect (due to defensive programming)
  load_zsh_configs
  # Note: run the post-brew-install script once more (in case it wasn't run by the brew lifecycle due to any error)
  # Note: When running with FIRST_INSTALL, some errors might come on a vanilla OS - warn and continue instead of failing.
  post-brew-install.sh || { is_first_install && _record_warning 'post-brew-install encountered errors; continuing...'; }

  if is_first_install; then
    trap _cleanup_and_exit ERR
  fi

  # TODO: Commented out to avoid the second touchId popup. Need to investigate how to solve this.
  # is_arm && sudo rm -rf /usr/local/bin/keybase /usr/local/bin/git-remote-keybase || true
  step_end
}

# Clone the Keybase home repo (private configs)
_clone_home_repo() {
  _current_section='Clone home repo'
  step_start
  section_header2 "$(yellow 'Cloning') $(purple 'home') repo"
  if is_non_zero_string "${KEYBASE_HOME_REPO_NAME}"; then
    if clone_repo_into "$(build_keybase_repo_url "${KEYBASE_HOME_REPO_NAME}")" "${HOME}"; then
      # Reset ssh keys' permissions so that git doesn't complain when using them
      set_ssh_folder_permissions

      # Fix /etc/hosts file to block facebook
      if is_file "${PERSONAL_CONFIGS_DIR}/etc.hosts"; then sudo cp "${PERSONAL_CONFIGS_DIR}/etc.hosts" /etc/hosts; fi
    else
      _record_error 'Failed to clone home repo'
    fi
  else
    info "Skipping cloning of home repo since the '$(yellow 'KEYBASE_HOME_REPO_NAME')' env var hasn't been set"
  fi
  step_end
}

# Clone the Keybase profiles repo (browser profiles)
_clone_profiles_repo() {
  _current_section='Clone profiles repo'
  step_start
  section_header2 "$(yellow 'Cloning') $(purple 'profiles') repo"
  if is_non_zero_string "${KEYBASE_PROFILES_REPO_NAME}" && is_non_zero_string "${PERSONAL_PROFILES_DIR}"; then
    if ! clone_repo_into "$(build_keybase_repo_url "${KEYBASE_PROFILES_REPO_NAME}")" "${PERSONAL_PROFILES_DIR}"; then
      _record_error 'Failed to clone profiles repo'
    fi
  else
    info "Skipping cloning of profiles repo since either the '$(yellow 'KEYBASE_PROFILES_REPO_NAME')' or the '$(yellow 'PERSONAL_PROFILES_DIR')' env var hasn't been set"
  fi
  step_end
}

main() {
  # Suspend cron early before .shellrc or .aliases are available — neither
  # suspend_cron nor with_cron_suspended can be called yet, so the backup and
  # removal are done inline here. Even after both files are sourced, the
  # with_cron_suspended wrapper is not appropriate: the suspend/resume scope
  # spans the entire main(), not a single delegated function call.
  # Once .shellrc is sourced, the EXIT and ERR traps use resume_cron/recron
  # from .shellrc for restore.
  export _DOTFILES_CRON_BACKUP_FILE="${TMPDIR:-/tmp}/crontab_backup"
  crontab -l >"${_DOTFILES_CRON_BACKUP_FILE}"  2>/dev/null || : >"${_DOTFILES_CRON_BACKUP_FILE}"
  crontab -r &>/dev/null || true

  trap _cleanup_and_exit ERR
  trap 'rm -f "${_DOTFILES_CRON_BACKUP_FILE}"; _decrement_script_depth' EXIT

  export ZDOTDIR="${ZDOTDIR:-"${HOME}"}"

  # On a first install ~/.gitconfig is not yet in place (install-dotfiles.rb runs later),
  # so core.sshCommand is absent. Export GIT_SSH_COMMAND for the entire run to ensure the
  # connect timeout is honoured uniformly for all git operations.
  # Raw form: this line runs in main() before _download_and_source_shellrc (line 418)
  # has sourced .shellrc, so is_first_install is not yet defined.
  [[ -n "${FIRST_INSTALL:-}" ]] && export GIT_SSH_COMMAND="ssh -o ConnectTimeout=20"

  # ~/.curlrc is not yet symlinked (install-dotfiles.rb runs later), so its defaults are
  # absent. Define resilient curl flags explicitly for all bootstrap curl calls in this
  # script. Once ~/.curlrc is in place these flags are redundant but harmless.
  # Note: defined as an array so it expands correctly without word-splitting issues.
  # Note: local -a initialises to an empty array (not unset), so "${_curl_opts[@]}"
  #       expands to nothing safely under set -u when ~/.curlrc is already present.
  # Note: --retry-all-errors is intentionally omitted — it causes the terminal app to close.
  # Raw -f used here — .shellrc has not been sourced yet when _curl_opts is initialized, so is_file is unavailable.
  local -a _curl_opts
  if [[ ! -f "${HOME}/.curlrc" ]]; then
    _curl_opts=(--retry 5 --retry-delay 10 --retry-max-time 120 --max-time 150 --connect-timeout 30 --retry-connrefused)
  fi

  # Two separate accumulator arrays for non-fatal step issues:
  #   _step_warnings — minor issues the step recovered from (e.g. a tool sub-step failed but install continued)
  #   _step_errors   — significant failures that require manual attention (e.g. a tool was not found)
  # _record_warning/_record_error/_cleanup_and_exit/print_script_summary (all from .shellrc) read/write
  # these via zsh dynamic scoping — locals declared here are visible in all callees.
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  # Note: Cannot load from shellrc since that file won't be present in a new machine (vanilla OS)
  # $EPOCHSECONDS is provided by the zsh/datetime built-in module — always available, no fork.
  # Capture start epoch into both a local variable and _script_start_times.
  # The local is passed explicitly to print_script_duration at the end of main.
  # _script_start_times is used by step_end (called throughout this script) to
  # compute the "total elapsed" column independently of the local variable.
  # Both are required; see the design note above step_timing_init in .shellrc.
  local script_start_time
  # zmodload called directly — .shellrc has not been sourced yet when this runs, so the load is not delegated.
  # A subsequent zmodload in .shellrc is a no-op in zsh.
  zmodload zsh/datetime
  script_start_time="${EPOCHSECONDS}"
  _script_start_times+=("${script_start_time}")
  # current_timestamp is not yet available (shellrc not yet sourced); use strftime directly.
  local script_start_time_human
  strftime -s script_start_time_human '%Y-%m-%d %H:%M:%S' "${EPOCHSECONDS}"
  echo "==> Script started at: ${script_start_time_human}"

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

  # run this outside of the clone function, since it needs to be run irrespective of whether the dotfiles repo was pre-existing or not
  append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"
  install-dotfiles.rb

  # ~/.gitconfig is now symlinked by install-dotfiles.rb — core.sshCommand is in effect.
  # Unset GIT_SSH_COMMAND so it no longer overrides core.sshCommand for the rest of the run.
  unset GIT_SSH_COMMAND

  # Load all zsh config files for PATH and other env vars to take effect
  (($+functions[is_shellrc_sourced]))   && unfunction is_shellrc_sourced
  DEBUG=true load_zsh_configs

  _install_homebrew

  if is_non_zero_string "${KEYBASE_USERNAME}"; then
    section_header "$(yellow 'Cloning') $(purple 'keybase') repos"
    # Login into Keybase.
    step_start
    ensure_keybase_logged_in || exit 1
    step_end

    _clone_home_repo

    _clone_profiles_repo
  else
    info "Skipping cloning of any keybase repo since '$(yellow 'KEYBASE_USERNAME')' has not been set"
  fi

  if is_file "${SSH_CONFIGS_DIR}/known_hosts.old"; then rm -f "${SSH_CONFIGS_DIR}/known_hosts.old"; fi

  # Restore the preferences from the older machine into the new one.
  _current_section='Restore preferences'
  step_start
  section_header "$(yellow 'Restore preferences')"
  if command_exists 'osx-defaults.sh'; then
    osx-defaults.sh -s
    success 'Successfully baselines preferences'
  else
    _record_error "Skipping baselining of preferences since '$(yellow 'osx-defaults.sh')' couldn't be found in the PATH; Please baseline manually and follow it up with re-import of the backed-up preferences"
  fi

  if command_exists 'capture-prefs.sh'; then
    capture-prefs.sh -i
    success 'Successfully restored preferences from backup'
  else
    _record_error "Skipping importing of preferences since '$(yellow 'capture-prefs.sh')' couldn't be found in the PATH; Please set it up manually"
  fi

  if is_directory '/Applications/Sol.app' && ! pgrep -x 'Sol' &>/dev/null; then
    open /Applications/Sol.app
  fi
  step_end

  # Recreate the zsh completions.
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
    _record_error "Skipping setting up of cron jobs since '$(yellow 'recron')' couldn't be found; Please set it up manually"
  fi
  step_end

  # Resurrect tracked repos.
  _current_section='Resurrect tracked repos'
  if command_exists resurrect_tracked_repos; then
    # HACKTAG: Can take a long time on FIRST_INSTALL (same as install_mise_versions). Running in background to be non-blocking
    resurrect_tracked_repos &|
  else
    _record_error "Skipping resurrecting tracked repos since '$(yellow 'resurrect_tracked_repos')' couldn't be found in the PATH; Please run it manually"
  fi

  _current_section='Allow all direnv configs'
  if command_exists allow_all_direnv_configs; then
    # HACKTAG: Can take a long time on FIRST_INSTALL (same as install_mise_versions). Running in background to be non-blocking
    allow_all_direnv_configs &|
  else
    _record_error "Skipping registering all direnv configs since '$(yellow 'allow_all_direnv_configs')' couldn't be found in the PATH; Please run it manually"
  fi

  _current_section='Install mise versions'
  if command_exists install_mise_versions; then
    # HACKTAG: For some reason this exits with an error code and can also take a long time on FIRST_INSTALL. Need to investigate a better fix
    install_mise_versions &|
  else
    _record_error "Skipping installation of languages since '$(yellow 'install_mise_versions')' couldn't be found in the PATH; Please run it manually"
  fi

  # To install the latest versions of the hex, rebar and phoenix packages
  # mix local.hex --force && mix local.rebar --force
  # mix archive.install hex phx_new 1.4.1

  # To install the native-image tool after graalvm is installed
  # gu install native-image

  # vagrant plugin install vagrant-vbguest

  # if installing jhipster for dot-net-core
  # TODO: Use the next line since the released version is only for .net 2.2:
  # npm i -g generator-jhipster-dotnetcore
  # Note: '-g' didnt work. Had to do 'npm init' and then use '--save-dev' to install and link as a local dependency
  # npm i -g jhipster/jhipster-dotnetcore
  # npm link generator-jhipster-dotnetcore
  # jhipster -d --blueprints dotnetcore

  # Default tooling for dotnet projects
  # dotnet tool install -g dotnet-sonarscanner
  # dotnet tool install -g dotnet-format

  success '** Finished auto installation process **'

  # Print grouped summary of all collected warnings and errors, then send exactly one
  # notification. Exit code is unchanged (0) — the summary is informational only.
  print_script_summary
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
  if is_non_empty_array _notification_parts; then
    local _notification_body
    _notification_body="${(j: | :)_notification_parts}"
    _dotfiles_notify "Install done — ${_notification_body}" "⚠️ Fresh Install" || true
  else
    _dotfiles_notify "Fresh install completed successfully." "✅ Fresh Install Done" || true
  fi

  print_script_duration "${script_start_time}"
}

main "$@"
