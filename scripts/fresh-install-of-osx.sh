#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is idempotent and will restore your local setup to the same state even if run multiple times.
# In most cases, the script will provide warning messages if skipping certain steps. Each such message will be useful to give you a hint about what to do to force rerunning of that step.

# file location: <anywhere; but advisable in the PATH>

# Exit immediately if a command exits with a non-zero status.
set -e

_cleanup_and_exit() {
  local message='Installation failed. Check for error messages above.'
  if type error &>/dev/null; then
    error "${message}"
  else
    echo "ERROR: ${message}" >&2
  fi

  if [[ -s "${CRON_BACKUP_FILE}" ]]; then
    if type warn &>/dev/null; then
      warn 'Attempting to restore cron jobs from backup...'
    else
      echo 'WARN: Attempting to restore cron jobs from backup...'
    fi
    if crontab "${CRON_BACKUP_FILE}"; then
      if type success &>/dev/null; then
        success 'Restored crontab from backup.'
      else
        echo 'SUCCESS: Restored crontab from backup.'
      fi
    else
      if type error &>/dev/null; then
        error 'Failed to restore crontab.'
      else
        echo 'ERROR: Failed to restore crontab.' >&2
      fi
    fi
  fi
  rm -f "${CRON_BACKUP_FILE}"
  exit 1
}

main() {
  # Handle errors and crontab backup
  # Backup crontab and set up a trap to restore it on exit.
  local CRON_BACKUP_FILE
  CRON_BACKUP_FILE="$(mktemp)"
  # Save current crontab; ignore errors if it's empty.
  crontab -l >"${CRON_BACKUP_FILE}"  2>/dev/null  || true # Backup crontab, ignore failure if empty

  trap _cleanup_and_exit ERR

  # Normal exit cleanup (for successful runs)
  trap 'rm -f "${CRON_BACKUP_FILE}"' EXIT

  # TODO: Need to figure out the scriptable commands for the following settings:
  # 1. Auto-adjust Brightness
  # 2. Brightness on battery
  # 3. Keyboard brightness

  # Note: Cannot load from shellrc since that file won't be present in a new machine (vanilla OS)
  local script_start_time
  script_start_time=$(date +%s)
  _SCRIPT_START_TIME=${script_start_time}
  echo "Script started at: $(date '+%Y-%m-%d %H:%M:%S')"

  #############################################################
  # Utility scripts and env vars used only within this script #
  #############################################################
  export ZDOTDIR="${ZDOTDIR:-"${HOME}"}"

  ######################################################################################################################
  # Set DNS of 8.8.8.8 before proceeding (in some cases, for eg Jio Wifi, github doesn't resolve at all and times out) #
  ######################################################################################################################
  setup_jio_dns() {
    # Fetch only organization and grep quietly (-q) and case-insensitively (-i) for Jio ISP
    if curl -fsS https://ipinfo.io/org | \grep -qi 'jio'; then
      echo '==> Setting DNS for WiFi from Jio ISP'
      networksetup -setdnsservers Wi-Fi 8.8.8.8 || echo 'Warning: Failed to set DNS for Wi-Fi'
    fi
  }

  #################################################################################################
  # Download and source this utility script - so that the functions are available for this script #
  #################################################################################################
  download_and_source_shellrc() {
    echo "==> Download the '${HOME}/.shellrc' for loading the utility functions"
    # Check for one key function defined in .shellrc to see if sourcing is needed
    if ! type is_shellrc_sourced &>/dev/null; then
      [[ ! -f "${HOME}/.shellrc" || -n "${FIRST_INSTALL}" ]] && curl --retry 3 --retry-delay 5 -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/files/--HOME--/.shellrc" -o "${HOME}/.shellrc"
      DEBUG=true source "${HOME}/.shellrc"
    else
      warn "Skipping downloading and sourcing '$(yellow "${HOME}/.shellrc")' since its already loaded"
    fi
  }

  ################################################################################################
  # Setup the 'sudo' command in terminal to prompt the mac touchbar for authorizing the user     #
  # This will persist through software updates unlike changes directly made to '/etc/pam.d/sudo' #
  # Copied from: https://apple.stackexchange.com/a/466029                                        #
  ################################################################################################
  approve_fingerprint_sudo() {
    step_start
    section_header "$(yellow 'Setting up touchId for sudo access in terminal shells')"

    if ! ioreg -c AppleBiometricSensor | \grep -q AppleBiometricSensor; then
      warn 'Touch ID hardware is not detected. Skipping configuration.'
      step_end
      return 0 # Exit successfully as no action is needed
    fi

    local template_file='/etc/pam.d/sudo_local.template'
    if ! is_file "${template_file}"; then
      warn "Template file '$(yellow "${template_file}")' not found! Skipping!"
      step_end
      return
    fi

    local target_file='/etc/pam.d/sudo_local'
    if ! is_file "${target_file}"; then
      # Using sh -c 'sed...' is fine here
      if sudo sh -c "sed 's/^#auth/auth/' '${template_file}' > '${target_file}'"; then
        success "Created new file: '$(yellow "${target_file}")'"
      else
        error "Failed to create '${target_file}'"
      fi
    else
      warn "'$(yellow "${target_file}")' is already present - not creating again"
    fi
    step_end
  }

  #####################
  # Turn on FileVault #
  #####################
  ensure_filevault_is_on() {
    step_start
    section_header "$(yellow 'Verifying FileVault status')"
    if [[ "$(fdesetup isactive)" != 'true' ]]; then
      error 'FileVault is not turned on. Please encrypt your hard disk!'
      exit 1
    fi
    step_end
  }

  ##################################
  # Install command line dev tools #
  ##################################
  install_xcode_command_line_tools() {
    step_start
    section_header "$(yellow 'Installing xcode command-line tools')"
    # Check if Xcode Command Line Tools are installed
    if ! xcode-select -p &>/dev/null; then
      # install using the non-gui cmd-line alone
      touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
      sudo softwareupdate -ia --agree-to-license --force || warn 'softwareupdate encountered errors'
      rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
      if ! xcode-select -p 2>/dev/null; then
        error "Couldn't install xcode command-line tools; Aborting"
        exit 1
      fi

      success 'Successfully installed xcode command-line tools'
    else
      warn 'Skipping installation of xcode command-line tools since its already present'
    fi
    # Note: Duplicate the cleanup if the installation was cancelled and continued via the gui
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    step_end
  }

  #################################################################################
  # Ensure that some of the directories corresponding to the env vars are created #
  #################################################################################
  ensure_directories_exist() {
    step_start
    section_header "$(yellow 'Creating directories defined by various env vars')"
    local -a folders=("${ANTIDOTE_HOME}" "${DOTFILES_DIR}" "${PROJECTS_BASE_DIR}" "${PERSONAL_BIN_DIR}" "${PERSONAL_CONFIGS_DIR}" "${PERSONAL_PROFILES_DIR}" "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}")
    for folder in "${folders[@]}"; do
      ensure_dir_exists "${folder}"
    done
    step_end
  }

  clone_dot_files_repo() {
    ####################
    # Install dotfiles #
    ####################
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
        add-upstream-git-config.sh -d "${DOTFILES_DIR}" -u "${UPSTREAM_GH_USERNAME}" || warn 'Failed to add upstream git config for dotfiles repo'
      else
        error 'Failed to clone dotfiles repo'
        exit 1
      fi
    else
      warn "Skipping cloning the dotfiles repo since '$(yellow "${DOTFILES_DIR}")' is either not defined or is already a git repo"
    fi
    step_end
  }

  install_homebrew() {
    ####################
    # Install homebrew #
    ####################
    step_start
    section_header "$(yellow 'Installing homebrew') into '$(yellow "${HOMEBREW_PREFIX}")'"
    if is_zero_string "${HOMEBREW_PREFIX}"; then
      error "'HOMEBREW_PREFIX' env var is not set; something is wrong. Please correct before retrying!"
      exit 1 # Irrecoverable failure
    fi

    if ! command_exists brew; then
      # Prep for installing homebrew
      sudo mkdir -p "${HOMEBREW_PREFIX}/tmp" "${HOMEBREW_PREFIX}/repository" "${HOMEBREW_PREFIX}/plugins" "${HOMEBREW_PREFIX}/bin"
      sudo chown -fR "$(whoami)":admin "${HOMEBREW_PREFIX}"
      chmod u+w "${HOMEBREW_PREFIX}"

      local install_script_file
      install_script_file="$(mktemp)"
      if curl --retry 3 --retry-delay 5 -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "${install_script_file}"; then
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
      warn "Skipping installation of $(yellow 'homebrew') since it's already installed"
    fi

    # Note: ensure that homebrew's environment variables are set correctly for this session (even if homebrew was not installed in this session)
    eval_shellenv "${HOMEBREW_PREFIX}/bin/brew" shellenv

    # Note: Temporarily disable the ERR trap since brew commands may fail on a vanilla OS (e.g. rate limits, missing deps).
    if [[ -n "${FIRST_INSTALL}" ]]; then
      trap - ERR
      # Note: On a first install, the number and size of downloads is large - allow up to 1hr for any single curl transfer.
      export HOMEBREW_CURL_EXTRA_CURL_ARGS="--connect-timeout 300 --max-time 3600"
    fi

    # Explicitly tap all taps from the Brewfile first (before brew bundle)
    \grep -E "^tap " "${HOME}/Brewfile" | awk '{print $2}' | tr -d "'\""  | while read -r tap_name; do
      brew tap "${tap_name}" || true
    done
    # Note: Do not set the 'FIRST_INSTALL' in this script - since its supposed to run idempotently. Also, don't run the cleanup of pre-installed brews/casks (for the same reason)
    # Run brew bundle install if check fails. Let brew handle idempotency. Continue script even if bundle fails.
    # Note: Split into taps, formulae and casks separately so that curl doesnt timeout, and failures are isolated and reported clearly.
    # Note: Each pass includes the Brewfile preamble (non tap/brew/cask lines) to preserve Ruby DSL context (e.g. cask_args, is_arm).
    # Note: For FIRST_INSTALL, only process lines up to the first 'FIRST_INSTALL' guard in the Brewfile (which marks the end of the base install section).
    if [[ -n "${FIRST_INSTALL}" ]]; then
      local brewfile_content brewfile_preamble
      brewfile_content="$(sed "/^[^#].*FIRST_INSTALL/q" "${HOME}/Brewfile" | \grep -Ev "^[^#].*FIRST_INSTALL")"
      brewfile_preamble="$(print "${brewfile_content}" | \grep -Ev "^tap |^brew |^cask ")"
      if brew bundle check || \
        (brew bundle --file=- <<< "${brewfile_preamble}"$'\n'"$(print "${brewfile_content}" | \grep -E "^tap ")" && \
        brew bundle --file=- <<< "${brewfile_preamble}"$'\n'"$(print "${brewfile_content}" | \grep -E "^brew ")" && \
        brew bundle --file=- <<< "${brewfile_preamble}"$'\n'"$(print "${brewfile_content}" | \grep -E "^cask ")"); then
        success 'Successfully installed cmd-line and gui apps using homebrew'
      else
        warn 'Homebrew bundle install encountered errors; continuing...'
      fi
    else
      if brew bundle check || brew bundle; then
        success 'Successfully installed cmd-line and gui apps using homebrew'
      else
        warn 'Homebrew bundle install encountered errors; continuing...'
      fi
    fi

    # Note: load all zsh config files for the 2nd time for PATH and other env vars to take effect (due to defensive programming)
    load_zsh_configs

    # Note: run the post-brew-install script once more (in case it wasn't run by the brew lifecycle due to any error)
    # Note: When running with FIRST_INSTALL, some errors might come on a vanilla OS - warn and continue instead of failing.
    post-brew-install.sh || { [[ -n "${FIRST_INSTALL}" ]] && warn 'post-brew-install encountered errors; continuing...'; }

    if [[ -n "${FIRST_INSTALL}" ]]; then
      unset HOMEBREW_CURL_EXTRA_CURL_ARGS
      trap _cleanup_and_exit ERR
    fi

    is_arm && sudo rm -rf /usr/local/bin/keybase /usr/local/bin/git-remote-keybase || true
    step_end
  }

  clone_home_repo() {
    #######################
    # Clone the home repo #
    #######################
    step_start
    section_header "$(yellow 'Cloning') $(purple 'home') repo"
    if is_non_zero_string "${KEYBASE_HOME_REPO_NAME}"; then
      if clone_repo_into "$(build_keybase_repo_url "${KEYBASE_HOME_REPO_NAME}")" "${HOME}"; then
        # Reset ssh keys' permissions so that git doesn't complain when using them
        set_ssh_folder_permissions

        # Fix /etc/hosts file to block facebook
        is_file "${PERSONAL_CONFIGS_DIR}/etc.hosts" && sudo cp "${PERSONAL_CONFIGS_DIR}/etc.hosts" /etc/hosts
      else
        warn 'Failed to clone home repo'
      fi
    else
      warn "Skipping cloning of home repo since the '$(yellow 'KEYBASE_HOME_REPO_NAME')' env var hasn't been set"
    fi
    step_end
  }

  clone_profiles_repo() {
    ###########################
    # Clone the profiles repo #
    ###########################
    step_start
    section_header "$(yellow 'Cloning') $(purple 'profiles') repo"
    if is_non_zero_string "${KEYBASE_PROFILES_REPO_NAME}" && is_non_zero_string "${PERSONAL_PROFILES_DIR}"; then
      if ! clone_repo_into "$(build_keybase_repo_url "${KEYBASE_PROFILES_REPO_NAME}")" "${PERSONAL_PROFILES_DIR}"; then
        warn 'Failed to clone profiles repo'
      fi
    else
      warn "Skipping cloning of profiles repo since either the '$(yellow 'KEYBASE_PROFILES_REPO_NAME')' or the '$(yellow 'PERSONAL_PROFILES_DIR')' env var hasn't been set"
    fi
    step_end
  }

  ###############################
  # Do not allow rootless login #
  ###############################
  # Note: Commented out since I am not sure if we need to do this on the office MBP or not
  # section_header "$(yellow 'Verifying rootless login enabled status')"
  # if [[ "$(/usr/bin/csrutil status | awk '/status/ {print $5}' | sed 's/\.$//')" == "enabled" ]]; then
  #   error "rootless login is enabled. Please disable in boot screen and run again"
  #   exit 1 # Irrecoverable failure
  # fi

  ############################
  # Disable macos gatekeeper #
  ############################
  # section_header "$(yellow 'Disabling macos gatekeeper')"
  # sudo spectl --master-disable

  setup_jio_dns

  # if this is being run on a machine that's already configured, then remove the cron jobs (it's backed up, and will be restored on failure or regenerated on success)
  crontab -r &>/dev/null  || true

  download_and_source_shellrc

  keep_sudo_alive

  approve_fingerprint_sudo

  ensure_filevault_is_on

  install_xcode_command_line_tools

  set_ssh_folder_permissions

  ensure_directories_exist


  clone_dot_files_repo

  # run this outside of the clone function, since it needs to be run irrespective of whether the dotfiles repo was pre-existing or not
  append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"
  install-dotfiles.rb

  # Load all zsh config files for PATH and other env vars to take effect
  DEBUG=true load_zsh_configs

  install_homebrew

  section_header2 "$(yellow 'Installing antidote plugins and generating antidote plugin bundle')"
  update_antidote_and_regenerate_plugin_bundle

  if is_non_zero_string "${KEYBASE_USERNAME}"; then
    if ! command_exists keybase; then
      error 'Keybase not found in the PATH. Aborting!!!'
      exit 1 # Irrecoverable failure
    fi

    ######################
    # Login into keybase #
    ######################
    step_start
    section_header "$(yellow 'Logging into keybase')"
    if keybase status --json 2>/dev/null | \grep -q '"logged_in":true'; then
      warn "Skipping keybase login since '$(yellow "${KEYBASE_USERNAME}")' is already logged in"
    elif ! keybase login; then
      error 'Could not login into keybase. Retry after logging in.'
      exit 1 # Irrecoverable failure
    fi
    step_end

    clone_home_repo

    clone_profiles_repo
  else
    warn "Skipping cloning of any keybase repo since '$(yellow 'KEYBASE_USERNAME')' has not been set"
  fi

  is_file "${SSH_CONFIGS_DIR}/known_hosts.old" && rm -f "${SSH_CONFIGS_DIR}/known_hosts.old"

  ###################################################################
  # Restore the preferences from the older machine into the new one #
  ###################################################################
  step_start
  section_header "$(yellow 'Restore preferences')"
  if command_exists 'osx-defaults.sh'; then
    osx-defaults.sh -s
    success 'Successfully baselines preferences'
  else
    warn "Skipping baselining of preferences since '$(yellow 'osx-defaults.sh')' couldn't be found in the PATH; Please baseline manually and follow it up with re-import of the backed-up preferences"
  fi

  if command_exists 'capture-prefs.sh'; then
    capture-prefs.sh -i
    success 'Successfully restored preferences from backup'
  else
    warn "Skipping importing of preferences since '$(yellow 'capture-prefs.sh')' couldn't be found in the PATH; Please set it up manually"
  fi

  if is_directory '/Applications/Sol.app' && ! pgrep -x 'Sol' &>/dev/null; then
    open /Applications/Sol.app
  fi
  step_end

  ################################
  # Recreate the zsh completions #
  ################################
  step_start
  section_header "$(yellow 'Recreate zsh completions')"
  rm -rf "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"* &>/dev/null  || true
  autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}" &>/dev/null  || true
  step_end

  ###################
  # Setup cron jobs #
  ###################
  step_start
  section_header "$(yellow 'Setup cron jobs')"
  if command_exists recron; then
    recron
    success 'Successfully setup cron jobs'
  else
    warn "Skipping setting up of cron jobs since '$(yellow 'recron')' couldn't be found; Please set it up manually"
  fi
  step_end

  ###########################
  # Resurrect tracked repos #
  ###########################
  # For now, to save time while re-imaging/setting up the laptop, we'll skip resurrecting all the tracked repos
  # resurrect_tracked_repos

  if command_exists allow_all_direnv_configs; then
    allow_all_direnv_configs
  else
    warn "Skipping registering all direnv configs since '$(yellow 'allow_all_direnv_configs')' couldn't be found in the PATH; Please run it manually"
  fi

  if command_exists install_mise_versions; then
    install_mise_versions
  else
    warn "Skipping installation of languages since '$(yellow 'install_mise_versions')' couldn't be found in the PATH; Please run it manually"
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

  echo "\n"
  success '** Finished auto installation process: Remember to do the following steps! **'
  echo "$(yellow "1. Run the 'bupc' alias to finish setting up all other applications managed by homebrew")"
  echo "$(yellow "2. MANUALLY QUIT AND RESTART iTerm2 and Terminal apps")"

  print_script_duration "${script_start_time}"
}

main "$@"
