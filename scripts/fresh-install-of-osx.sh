#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is idempotent and will restore your local setup to the same state even if run multiple times.
# In most cases, the script will provide warning messages if skipping certain steps. Each such message will be useful to give you a hint about what to do to force rerunning of that step.

# file location: <anywhere; but advisable in the PATH>

# Exit immediately if a command exits with a non-zero status.
set -e

# Handle errors and crontab backup
# Backup crontab and set up a trap to restore it on exit.
local CRON_BACKUP_FILE="$(mktemp)"
# Save current crontab; ignore errors if it's empty.
crontab -l > "${CRON_BACKUP_FILE}" 2> /dev/null || true # Backup crontab, ignore failure if empty

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
trap _cleanup_and_exit ERR

# Normal exit cleanup (for successful runs)
trap 'rm -f "${CRON_BACKUP_FILE}"' EXIT

# TODO: Need to figure out the scriptable commands for the following settings:
# 1. Auto-adjust Brightness
# 2. Brightness on battery
# 3. Keyboard brightness

# Note: Cannot load from shellrc since that file won't be present in a new machine (vanilla OS)
local script_start_time=$(date +%s)
echo "Script started at: $(date '+%Y-%m-%d %H:%M:%S')"

#############################################################
# Utility scripts and env vars used only within this script #
#############################################################
export ZDOTDIR="${ZDOTDIR:-"${HOME}"}"
export ZSH="${ZSH:-"${ZDOTDIR}/.oh-my-zsh"}"
export ZSH_CUSTOM="${ZSH_CUSTOM:-"${ZSH}/custom"}"

# These repos can be alternatively tracked using git submodules, but by doing so, any new change in the submodule, will show up as a new commit in the main (home) repo. To avoid this "noise", I prefer to decouple them
clone_omz_plugin_if_not_present() {
  local last_segment="$(extract_last_segment "${1}")"
  clone_repo_into "${1}" "${ZSH_CUSTOM}/plugins/${last_segment}" || warn "Failed to install '$(yellow "${last_segment}")'"
  unset last_segment
}

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
  if ! type is_shellrc_sourced 2>&1 &> /dev/null; then
    [[ ! -f "${HOME}/.shellrc" ]] && curl --retry 3 --retry-delay 5 -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/files/--HOME--/.shellrc" -o "${HOME}/.shellrc"
    DEBUG=true source "${HOME}/.shellrc"
  else
    warn "skipping downloading and sourcing '$(yellow "${HOME}/.shellrc")' since its already loaded"
  fi
}

################################################################################################
# Setup the 'sudo' command in terminal to prompt the mac touchbar for authorizing the user     #
# This will persist through software updates unlike changes directly made to '/etc/pam.d/sudo' #
# Copied from: https://apple.stackexchange.com/a/466029                                        #
################################################################################################
approve_fingerprint_sudo() {
  section_header "$(yellow 'Setting up touchId for sudo access in terminal shells')"

  if ! ioreg -c AppleBiometricSensor | \grep -q AppleBiometricSensor; then
    warn 'Touch ID hardware is not detected. Skipping configuration.'
    return 0 # Exit successfully as no action is needed
  fi

  local template_file='/etc/pam.d/sudo_local.template'
  if ! is_file "${template_file}"; then
    warn "Template file '$(yellow "${template_file}")' not found! Skipping!"
    return
  fi

  local target_file='/etc/pam.d/sudo_local'
  if ! is_file "${target_file}"; then
    # Using sh -c 'sed...' is fine here
    if sudo sh -c "sed 's/^#auth/auth/' ${template_file} > ${target_file}"; then
      success "Created new file: '$(yellow "${target_file}")'"
    else
      error "Failed to create '${target_file}'"
    fi
  else
    warn "'$(yellow "${target_file}")' is already present - not creating again"
  fi
  unset target_file
  unset template_file
}

#####################
# Turn on FileVault #
#####################
ensure_filevault_is_on() {
  section_header "$(yellow 'Verifying FileVault status')"
  if [[ "$(fdesetup isactive)" != 'true' ]]; then
    error 'FileVault is not turned on. Please encrypt your hard disk!'
    exit 1
  fi
}

##################################
# Install command line dev tools #
##################################
install_xcode_command_line_tools() {
  section_header "$(yellow 'Installing xcode command-line tools')"
  # Check if Xcode Command Line Tools are installed
  if ! xcode-select -p &> /dev/null; then
    # install using the non-gui cmd-line alone
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    sudo softwareupdate -ia --agree-to-license --force || warn 'softwareupdate encountered errors'
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    if ! xcode-select -p 2> /dev/null; then
      error "Couldn't install xcode command-line tools; Aborting"
      exit 1
    fi

    success 'Successfully installed xcode command-line tools'
  else
    warn 'skipping installation of xcode command-line tools since its already present'
  fi
  # Note: Duplicate the cleanup if the installation was cancelled and continued via the gui
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
}

#################################################################################
# Ensure that some of the directories corresponding to the env vars are created #
#################################################################################
ensure_directories_exist() {
  section_header "$(yellow 'Creating directories defined by various env vars')"
  local -a folders=("${DOTFILES_DIR}" "${PROJECTS_BASE_DIR}" "${PERSONAL_BIN_DIR}" "${PERSONAL_CONFIGS_DIR}" "${PERSONAL_PROFILES_DIR}" "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}")
  for folder in "${(@kv)folders}"; do
    ensure_dir_exists "${folder}"
  done
  unset folders
}

install_oh_my_zsh_and_custom_plugins() {
  #####################
  # Install oh-my-zsh #
  #####################
  section_header "$(yellow 'Installing oh-my-zsh') into '$(purple "${ZSH}")'"
  if ! is_directory "${ZSH}"; then
    sh -c "$(ZSH= curl --retry 3 --retry-delay 5 -fsSL https://install.ohmyz.sh/)" "" --unattended
    success "Successfully installed oh-my-zsh into '$(yellow "${ZSH}")'"
  else
    warn "skipping installation of oh-my-zsh since '$(yellow "${ZSH}")' is already present"
  fi

  ##############################
  # Install custom omz plugins #
  ##############################
  # Note: Some of these are available via brew, but enabling them will take an additional step and the only other benefit (of keeping them up-to-date using brew can still be achieved by updating the git repos directly using git commands)
  section_header "$(yellow 'Installing custom omz plugins')"
  # Note: These are not installed using homebrew since sourcing of the files needs to be explicit in .zshrc
  # Also, the order of these being referenced in the zsh session startup (for vanilla OS) will cause a warning to be printed though the rest of the shell startup sequence is still being performed. Ultimately, until they become included by default into omz, keep them here as custom plugins
    local -a omz_plugins=(
    'zdharma-continuum/fast-syntax-highlighting'
    'zsh-users/zsh-autosuggestions'
    'zsh-users/zsh-completions'
  )
  for plugin_url in "${omz_plugins[@]}"; do
    clone_omz_plugin_if_not_present "https://github.com/${plugin_url}"
  done
  unset plugin_url omz_plugins
}

clone_dot_files_repo() {
  ####################
  # Install dotfiles #
  ####################
  section_header "$(yellow 'Installing dotfiles') into '$(purple "${DOTFILES_DIR}")'"
  rm -rfv "${ZDOTDIR}/.zshrc.pre-oh-my-zsh"
  if is_non_zero_string "${DOTFILES_DIR}" && ! is_git_repo "${DOTFILES_DIR}"; then
    # Delete the auto-generated .zshrc since that needs to be replaced by the one in the DOTFILES_DIR repo
    rm -rf "${ZDOTDIR}/.zshrc"

    # Note: Cloning with https since the ssh keys will not be present at this time
    if clone_repo_into "https://github.com/${GH_USERNAME}/dotfiles" "${DOTFILES_DIR}" "${DOTFILES_BRANCH}"; then
      # Use the https protocol for pull, but use ssh/git for push
      git -C "${DOTFILES_DIR}" config url.ssh://git@github.com/.pushInsteadOf https://github.com/

      append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"

      # Setup the DOTFILES_DIR repo's upstream if it doesn't already point to UPSTREAM_GH_USERNAME's repo
      add-upstream-git-config.sh -d "${DOTFILES_DIR}" -u "${UPSTREAM_GH_USERNAME}" || warn 'Failed to add upstream git config for dotfiles repo'
    else
      error 'Failed to clone dotfiles repo'
      exit 1
    fi
  else
    warn "skipping cloning the dotfiles repo since '$(yellow "${DOTFILES_DIR}")' is either not defined or is already a git repo"
  fi
}

install_homebrew() {
  ####################
  # Install homebrew #
  ####################
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

    local install_script_file="$(mktemp)"
    if curl --retry 3 --retry-delay 5 -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "${install_script_file}"; then
      NONINTERACTIVE=1 bash "${install_script_file}" || { rm -f "${install_script_file}"; error 'Homebrew installation failed'; exit 1 }
      rm -f "${install_script_file}"
      success 'Successfully installed homebrew'
    else
      rm -f "${install_script_file}"
      error 'Failed to download Homebrew installation script'
      exit 1
    fi
    unset install_script_file
  else
    warn "skipping installation of $(yellow 'homebrew') since it's already installed"
  fi

  # Note: ensure that homebrew's environment variables are set correctly for this session (even if homebrew was not installed in this session)
  local brew_shellenv
  if brew_shellenv="$("${HOMEBREW_PREFIX}/bin/brew" shellenv)"; then
    eval "${brew_shellenv}"
  else
    warn 'Failed to load homebrew shellenv'
  fi
  unset brew_shellenv

  # TODO: Need to investigate why this step exits on a vanilla OS's first run of this script
  # Note: Do not set the 'HOMEBREW_BASE_INSTALL' in this script - since its supposed to run idempotently. Also, don't run the cleanup of pre-installed brews/casks (for the same reason)
  # Run brew bundle install if check fails. Let brew handle idempotency. Continue script even if bundle fails.
  if brew bundle check || brew bundle; then
    success 'Successfully installed cmd-line and gui apps using homebrew'
  else
    warn 'Homebrew bundle install encountered errors; continuing...'
  fi

  # Note: load all zsh config files for the 2nd time for PATH and other env vars to take effect (due to defensive programming)
  load_zsh_configs

  # Note: run the post-brew-install script once more (in case it wasn't run by the brew lifecycle due to any error)
  post-brew-install.sh

  is_arm && sudo rm -rf /usr/local/bin/keybase /usr/local/bin/git-remote-keybase || true
}

clone_home_repo() {
  #######################
  # Clone the home repo #
  #######################
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
    warn "skipping cloning of home repo since the '$(yellow 'KEYBASE_HOME_REPO_NAME')' env var hasn't been set"
  fi
}

clone_profiles_repo() {
  ###########################
  # Clone the profiles repo #
  ###########################
  section_header "$(yellow 'Cloning') $(purple 'profiles') repo"
  if is_non_zero_string "${KEYBASE_PROFILES_REPO_NAME}" && is_non_zero_string "${PERSONAL_PROFILES_DIR}"; then
    if ! clone_repo_into "$(build_keybase_repo_url "${KEYBASE_PROFILES_REPO_NAME}")" "${PERSONAL_PROFILES_DIR}"; then
      warn 'Failed to clone profiles repo'
    fi
  else
    warn "skipping cloning of profiles repo since either the '$(yellow 'KEYBASE_PROFILES_REPO_NAME')' or the '$(yellow 'PERSONAL_PROFILES_DIR')' env var hasn't been set"
  fi
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
crontab -r 2>&1 &> /dev/null || true

download_and_source_shellrc

keep_sudo_alive

approve_fingerprint_sudo

ensure_filevault_is_on

install_xcode_command_line_tools

set_ssh_folder_permissions

ensure_directories_exist

install_oh_my_zsh_and_custom_plugins

clone_dot_files_repo

# run this outside of the clone function, since it needs to be run irrespective of whether the dotfiles repo was pre-existing or not
append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"
install-dotfiles.rb

# Load all zsh config files for PATH and other env vars to take effect
DEBUG=true load_zsh_configs

install_homebrew

if is_non_zero_string "${KEYBASE_USERNAME}"; then
  if ! command_exists keybase; then
    error 'Keybase not found in the PATH. Aborting!!!'
    exit 1 # Irrecoverable failure
  fi

  ######################
  # Login into keybase #
  ######################
  section_header "$(yellow 'Logging into keybase')"
  if ! keybase login; then
    error 'Could not login into keybase. Retry after logging in.'
    exit 1 # Irrecoverable failure
  fi

  clone_home_repo

  clone_profiles_repo
else
  warn "skipping cloning of any keybase repo since '$(yellow 'KEYBASE_USERNAME')' has not been set"
fi

rm -rf "${SSH_CONFIGS_DIR}/known_hosts.old"

###################################################################
# Restore the preferences from the older machine into the new one #
###################################################################
section_header "$(yellow 'Restore preferences')"
if command_exists 'osx-defaults.sh'; then
  osx-defaults.sh -s
  success 'Successfully baselines preferences'
else
  warn "skipping baselining of preferences since '$(yellow 'osx-defaults.sh')' couldn't be found in the PATH; Please baseline manually and follow it up with re-import of the backed-up preferences"
fi

if command_exists 'capture-prefs.sh'; then
  capture-prefs.sh -i
  success 'Successfully restored preferences from backup'
else
  warn "skipping importing of preferences since '$(yellow 'capture-prefs.sh')' couldn't be found in the PATH; Please set it up manually"
fi

if is_directory '/Applications/Raycast.app'; then
  open /Applications/Raycast.app
fi

################################
# Recreate the zsh completions #
################################
section_header "$(yellow 'Recreate zsh completions')"
rm -rf "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"* 2>&1 &> /dev/null || true
autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}" 2>&1 &> /dev/null || true

###################
# Setup cron jobs #
###################
section_header "$(yellow 'Setup cron jobs')"
if command_exists recron; then
  recron
  success 'Successfully setup cron jobs'
else
  warn "skipping setting up of cron jobs since '$(yellow 'recron')' couldn't be found in the PATH; Please set it up manually"
fi

###########################
# Resurrect tracked repos #
###########################
# For now, to save time while re-imaging/setting up the laptop, we'll skip resurrecting all the tracked repos
# resurrect_tracked_repos

if command_exists allow_all_direnv_configs; then
  allow_all_direnv_configs
else
  warn "skipping registering all direnv configs since '$(yellow 'allow_all_direnv_configs')' couldn't be found in the PATH; Please run it manually"
fi

if command_exists install_mise_versions; then
  install_mise_versions
else
  warn "skipping installation of languages since '$(yellow 'install_mise_versions')' couldn't be found in the PATH; Please run it manually"
fi

###############################
# Cleanup temp functions, etc #
###############################
unfunction clone_omz_plugin_if_not_present
unfunction setup_jio_dns
unfunction download_and_source_shellrc
unfunction approve_fingerprint_sudo
unfunction ensure_filevault_is_on
unfunction install_xcode_command_line_tools
unfunction ensure_directories_exist
unfunction install_oh_my_zsh_and_custom_plugins
unfunction clone_dot_files_repo
unfunction install_homebrew
unfunction clone_home_repo
unfunction clone_profiles_repo

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
echo "$(yellow "1. set the 'RAYCAST_SETTINGS_PASSWORD' env var, and then run the 'capture-raycast-configs.sh' script to import your Raycast configuration into the new machine.")"
echo "$(yellow "2. Run the 'bupc' alias to finish setting up all other applications managed by homebrew")"
echo "$(yellow "3. MANUALLY QUIT AND RESTART iTerm2 and Terminal apps")"

print_script_duration "${script_start_time}"
