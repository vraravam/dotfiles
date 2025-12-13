#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is idempotent and will restore your local setup to the same state even if run multiple times.
# In most cases, the script will provide warning messages if skipping certain steps. Each such message will be useful to give you a hint about what to do to force rerunning of that step.

# file location: <anywhere; but advisable in the PATH>

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
export ZSH_CUSTOM="${ZSH_CUSTOM:-"${ZSH:-"${HOME}/.oh-my-zsh"}/custom"}"

######################################################################################################################
# Set DNS of 8.8.8.8 before proceeding (in some cases, for eg Jio Wifi, github doesn't resolve at all and times out) #
######################################################################################################################
setup_jio_dns() {
  # Fetch only organization and grep quietly (-q) and case-insensitively (-i) for Jio ISP
  if curl -fsS ipinfo.io/org | \grep -qi 'jio'; then
    echo '==> Setting DNS for WiFi'
    sudo networksetup -setdnsservers Wi-Fi 8.8.8.8
  fi
}

#################################################################################################
# Download and source this utility script - so that the functions are available for this script #
#################################################################################################
download_and_source_shellrc() {
  echo "==> Download the '${HOME}/.shellrc' for loading the utility functions"
  # Check for one key function defined in .shellrc to see if sourcing is needed
  if ! type keep_sudo_alive &> /dev/null 2>&1; then
    [[ ! -f "${HOME}/.shellrc" ]] && curl --retry 3 --retry-delay 5 -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/files/--HOME--/.shellrc" -o "${HOME}/.shellrc"
    FIRST_INSTALL=true source "${HOME}/.shellrc"
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

  local template_file="/etc/pam.d/sudo_local.template"
  ! is_file "${template_file}" && warn "Template file '$(yellow "${template_file}")' not found! Skipping!"

  local target_file="/etc/pam.d/sudo_local"
  if ! is_file "${target_file}"; then
    # Using sh -c 'sed...' is fine here
    sudo sh -c "sed 's/^#auth/auth/' ${template_file} > ${target_file}" || error "Failed to create ${target_file}"
    success "Created new file: '$(yellow "${target_file}")'"
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
  [[ "$(fdesetup isactive)" != 'true' ]] && error 'FileVault is not turned on. Please encrypt your hard disk!'
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
    sudo softwareupdate -ia --agree-to-license --force
    rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    ! xcode-select -p &> /dev/null && error "Couldn't install xcode command-line tools; Aborting"

    success 'Successfully installed xcode command-line tools'
  else
    warn 'skipping installation of xcode command-line tools since its already present'
  fi
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
  section_header "$(yellow 'Installing oh-my-zsh') into '$(purple "${HOME}/.oh-my-zsh")'"
  if ! is_directory "${HOME}/.oh-my-zsh"; then
    sh -c "$(ZSH= curl --retry 3 --retry-delay 5 -fsSL https://install.ohmyz.sh/)" "" --unattended
    success "Successfully installed oh-my-zsh into '$(yellow "${HOME}/.oh-my-zsh")'"
  else
    warn "skipping installation of oh-my-zsh since '$(yellow "${HOME}/.oh-my-zsh")' is already present"
  fi
}

clone_dot_files_repo() {
  ####################
  # Install dotfiles #
  ####################
  section_header "$(yellow 'Installing dotfiles') into '$(purple "${DOTFILES_DIR}")'"
  if is_non_zero_string "${DOTFILES_DIR}" && ! is_git_repo "${DOTFILES_DIR}"; then
    # Delete the auto-generated .zshrc since that needs to be replaced by the one in the DOTFILES_DIR repo
    rm -rf "${ZDOTDIR}/.zshrc"

    # Note: Cloning with https since the ssh keys will not be present at this time
    clone_repo_into "https://github.com/${GH_USERNAME}/dotfiles" "${DOTFILES_DIR}" "${DOTFILES_BRANCH}"

    # Use the https protocol for pull, but use ssh/git for push
    git -C "${DOTFILES_DIR}" config url.ssh://git@github.com/.pushInsteadOf https://github.com/

    append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"

    # Setup the DOTFILES_DIR repo's upstream if it doesn't already point to UPSTREAM_GH_USERNAME's repo
    add-upstream-git-config.sh "${DOTFILES_DIR}" "${UPSTREAM_GH_USERNAME}"
  else
    warn "skipping cloning the dotfiles repo since '$(yellow "${DOTFILES_DIR}")' is either not defined or is already a git repo"
  fi
}

install_homebrew()  {
  ####################
  # Install homebrew #
  ####################
  section_header "$(yellow 'Installing homebrew') into '$(yellow "${HOMEBREW_PREFIX}")'"
  ! is_non_zero_string "${HOMEBREW_PREFIX}" && error "'HOMEBREW_PREFIX' env var is not set; something is wrong. Please correct before retrying!"

  if ! command_exists brew; then
    # Prep for installing homebrew
    sudo mkdir -p "${HOMEBREW_PREFIX}/tmp" "${HOMEBREW_PREFIX}/repository" "${HOMEBREW_PREFIX}/plugins" "${HOMEBREW_PREFIX}/bin"
    sudo chown -fR "$(whoami)":admin "${HOMEBREW_PREFIX}"
    chmod u+w "${HOMEBREW_PREFIX}"

    NONINTERACTIVE=1 bash -c "$(curl --retry 3 --retry-delay 5 -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    success 'Successfully installed homebrew'

    eval "$(${HOMEBREW_PREFIX}/bin/brew shellenv)"
  else
    warn "skipping installation of $(yellow 'homebrew') since it's already installed"
  fi
  # TODO: Need to investigate why this step exits on a vanilla OS's first run of this script
  # Note: Do not set the 'HOMEBREW_BASE_INSTALL' in this script - since its supposed to run idempotently. Also, don't run the cleanup of pre-installed brews/casks (for the same reason)
  # Run brew bundle install if check fails. Let brew handle idempotency. Continue script even if bundle fails.
  brew bundle check || brew bundle
  success 'Successfully installed cmd-line and gui apps using homebrew'

  # Note: Load all zsh config files for the 2nd time for PATH and other env vars to take effect (due to defensive programming)
  load_zsh_configs

  # Note: run the post-brew-install script once more (in case it wasn't run by the brew lifecycle due to some errors)
  post-brew-install.sh
}

clone_home_repo() {
  #######################
  # Clone the home repo #
  #######################
  section_header "$(yellow 'Cloning') $(purple 'home') repo"
  if is_non_zero_string "${KEYBASE_HOME_REPO_NAME}"; then
    clone_repo_into "$(build_keybase_repo_url "${KEYBASE_HOME_REPO_NAME}")" "${HOME}"

    # Reset ssh keys' permissions so that git doesn't complain when using them
    set_ssh_folder_permissions

    # Fix /etc/hosts file to block facebook
    is_file "${PERSONAL_CONFIGS_DIR}/etc.hosts" && sudo cp "${PERSONAL_CONFIGS_DIR}/etc.hosts" /etc/hosts
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
    clone_repo_into "$(build_keybase_repo_url "${KEYBASE_PROFILES_REPO_NAME}")" "${PERSONAL_PROFILES_DIR}"

    # Clone the natsumi-browser repo into specified browser profile chrome folders and switch to the 'dev' branch
    local -a browsers=(FirefoxProfile)
    for browser in "${(@kv)browsers}"; do
      local folder="${PERSONAL_PROFILES_DIR}/${browser}"
      if is_directory "${folder}"; then
        clone_repo_into "git@github.com:${UPSTREAM_GH_USERNAME}/natsumi-browser" "${folder}/Profiles/DefaultProfile/chrome" dev
      else
        warn "skipping cloning of natsumi repo for '$(yellow "${browser}")' as its profile directory structure is not present."
      fi
      unset folder
    done
    unset browsers

    # Use zsh glob qualifiers to only loop if matches exist and are directories
    # (N) nullglob: if no match, the pattern expands to nothing
    # (/): only match directories
    local chrome_folders=("${PERSONAL_PROFILES_DIR}"/*Profile/Profiles/DefaultProfile/chrome(N/))
    if [[ ${#chrome_folders[@]} -gt 0 ]]; then
      for folder in "${chrome_folders[@]}"; do
        # Setup the chrome repo's upstream if it doesn't already point to UPSTREAM_GH_USERNAME's repo
        add-upstream-git-config.sh "${folder}" "${UPSTREAM_GH_USERNAME}"
      done
      unset folder
    else
      warn "No '*Profile/Profiles/DefaultProfile/chrome' directories found to set upstream for."
    fi
    unset chrome_folders
  else
    warn "skipping cloning of profiles repo since either the '$(yellow 'KEYBASE_PROFILES_REPO_NAME')' or the '$(yellow 'PERSONAL_PROFILES_DIR')' env var hasn't been set"
  fi
}

###############################
# Do not allow rootless login #
###############################
# Note: Commented out since I am not sure if we need to do this on the office MBP or not
# section_header "$(yellow 'Verifying rootless status')"
# [[ "$(/usr/bin/csrutil status | awk '/status/ {print $5}' | sed 's/\.$//')" == "enabled" ]] && error "csrutil ('rootless') is enabled. Please disable in boot screen and run again!"

############################
# Disable macos gatekeeper #
############################
# section_header "$(yellow 'Disabling macos gatekeeper')"
# sudo spectl --master-disable

setup_jio_dns

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
FIRST_INSTALL=true load_zsh_configs

install_homebrew

if is_non_zero_string "${KEYBASE_USERNAME}"; then
  ! command_exists keybase && error 'Keybase not found in the PATH. Aborting!!!'

  ######################
  # Login into keybase #
  ######################
  section_header "$(yellow 'Logging into keybase')"
  ! keybase login && error 'Could not login into keybase. Retry after logging in.'

  clone_home_repo

  clone_profiles_repo
else
  warn "skipping cloning of any keybase repo since '$(yellow 'KEYBASE_USERNAME')' has not been set"
fi

if is_non_zero_string "${PERSONAL_CONFIGS_DIR}"; then
  ########################################################
  # Generate the repositories-oss.yml fie if not present #
  ########################################################
  file_name="${PERSONAL_CONFIGS_DIR}/repositories-oss.yml"
  section_header "$(yellow 'Generating') $(purple "${file_name}")"
  if ! is_file "${file_name}"; then
    ensure_dir_exists "$(dirname "${file_name}")"
    cat <<EOF > "${file_name}"
- folder: "\${PROJECTS_BASE_DIR}/oss/git_scripts"
  remote: git@github.com:${UPSTREAM_GH_USERNAME}/git_scripts
  active: true
EOF
    success "Successfully generated '$(yellow "${file_name}")'"
  else
    warn "skipping generation of '$(yellow "${file_name}")' since it already exists"
  fi
  unset file_name

  # TODO: Add the github.com host to the known_hosts file so that the script is not blocked for user input
  # ssh-keyscan -H -t ED25519 github.com >> ~/.ssh/known_hosts

  ##########################################################
  # Resurrect repositories that are in the repo catalogues #
  ##########################################################
  section_header "$(yellow 'Resurrecting repos')"
  # Use zsh glob qualifier (N.) for nullglob and regular files
  for file in "${PERSONAL_CONFIGS_DIR}"/repositories-*.yml(N.); do
    resurrect-repositories.rb -r "${file}"
  done
  unset file
  success 'Successfully resurrected all tracked git repos'
else
  warn "skipping resurrecting of repositories since '$(yellow "${PERSONAL_CONFIGS_DIR}")' doesn't exist"
fi

############################################################
# post-clone operations for installing system dependencies #
############################################################
section_header "$(yellow 'Running post-clone operations')"
if command_exists all; then
  all restore-mtime -c
  all maintenance register --config-file "${HOME}/.gitconfig-oss.inc"
  all maintenance start
fi
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
rm -rf "${HOME}/.ssh/known_hosts.old"

#####################################################################################
# Load the direnv config for the home folder so that it creates necessary sym-links #
#####################################################################################
# TODO: See if this can be merged into `allow_all_direnv_configs`
section_header "$(yellow 'Allowing direnv') for $(purple "${HOME}")"
if command_exists direnv && is_directory "${HOME}" && is_file "${HOME}/.envrc"; then
  (cd "${HOME}" && direnv allow .) && success "Successfully allowed direnv for '$(yellow "${HOME}")'" || warn "Failed to allow direnv for '${HOME}'"
fi

#########################################################################################
# Load the direnv config for the profiles folder so that it creates necessary sym-links #
#########################################################################################
# TODO: See if this can be merged into `allow_all_direnv_configs`
section_header "$(yellow 'Allowing direnv') for $(purple "${PERSONAL_PROFILES_DIR}")"
if command_exists direnv && is_directory "${PERSONAL_PROFILES_DIR}" && is_file "${PERSONAL_PROFILES_DIR}/.envrc"; then
  (cd "${PERSONAL_PROFILES_DIR}" && direnv allow .) && success "Successfully allowed direnv for '$(yellow "${PERSONAL_PROFILES_DIR}")'" || warn "Failed to allow direnv for '${PERSONAL_PROFILES_DIR}'"
fi

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
rm -rf "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"
autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"

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

###############################
# Cleanup temp functions, etc #
###############################
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
