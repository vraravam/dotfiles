#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is idempotent and will restore your local setup to the same state even if run multiple times.
# In most cases, the script will provide warning messages if skipping certain steps. Each such message will be useful to give you a hint about what to do to force rerunning of that step.

# file location: <anywhere; but advisable in the PATH>

# TODO: Need to figure out the scriptable commands for the following settings:
# 1. Auto-adjust Brightness
# 2. Brightness on battery
# 3. Keyboard brightness

#############################################################
# Utility scripts and env vars used only within this script #
#############################################################
ZSH_CUSTOM="${ZSH_CUSTOM:-${ZSH:-${HOME}/.oh-my-zsh}/custom}"

set_ssh_folder_permissions() {
  local target_folder="${HOME}/.ssh"
  ensure_dir_exists "${target_folder}"
  if dir_has_children "${target_folder}"; then
    sudo chmod -R 600 "${target_folder}"/*
    success "Successfully set permissions for all files in '${target_folder}'"
  else
    warn "Couldn't find any files in '${target_folder}' to set permissions for"
  fi
}

clone_repo_into() {
  ensure_dir_exists "${2}"
  if ! is_git_repo "${2}"; then
    local tmp_folder="$(mktemp -d)"
    git -C "${tmp_folder}" clone -q "${1}" . --recurse-submodules
    mv "${tmp_folder}/.git" "${2}"
    rm -rf "${tmp_folder}"
    git -C "${2}" checkout .
    # TODO: Not sure if the above will handle submodules
    success "Successfully cloned '${1}' into '${2}'"
  else
    warn "Skipping cloning of '${1}' since '${2}' is already a git repo"
  fi
}

clone_omz_plugin_if_not_present() {
  clone_repo_into "${1}" "${ZSH_CUSTOM}/plugins/$(basename "${1}")"
}

replace_executable_if_exists_and_is_not_symlinked() {
  if is_executable "${1}"; then
    rm -rf "${2}"
    ln -sf "${1}" "${2}"
  else
    warn "executable '${1}' not found and so skipping symlinking"
  fi
}

setup_login_item() {
  local app_path="/Applications/${1}"
  if is_directory "${app_path}"; then
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"${app_path}\", hidden:false}" 2>&1 > /dev/null && success "Successfully setup '$(yellow "${1}")' $(green 'as a login item')"
  else
    warn "Couldn't find application '${app_path}' and so skipping setting up as a login item"
  fi
}

build_keybase_repo_url() {
  echo "keybase://private/${KEYBASE_USERNAME}/${1}"
}

ensure_safe_load_direnv() {
  if [[ "$(pwd)" == "${1}" ]]; then
    pushd ..; popd
  else
    pushd "${1}"; pushd ..; popd; popd
  fi
  success "Successfully allowed 'direnv' config for '${1}'"
}

######################################################################################################################
# Set DNS of 8.8.8.8 before proceeding (in some cases, for eg Jio Wifi, github doesn't resolve at all and times out) #
######################################################################################################################
# TODO: Only needed for India/Jio networks, need to figure out a way to not have this for other global locations
echo '==> Setting DNS for WiFi'
sudo networksetup -setdnsservers Wi-Fi 8.8.8.8

#################################################################################################
# Download and source this utility script - so that the functions are available for this script #
#################################################################################################
echo "==> Download the '${HOME}/.shellrc' for loading the utility functions"
if ! type warn &> /dev/null 2>&1; then
  ! test -f "${HOME}/.shellrc" && curl -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/files/--HOME--/.shellrc" -o "${HOME}/.shellrc"
  FIRST_INSTALL=true source "${HOME}/.shellrc"
else
  warn "skipping downloading and sourcing '${HOME}/.shellrc' since its already loaded"
fi

###############################################################################################
# Ask for the administrator password upfront and keep it alive until this script has finished #
###############################################################################################
keep_sudo_alive

###############################
# Do not allow rootless login #
###############################
# Note: Commented out since I am not sure if we need to do this on the office MBP or not
# section_header 'Verifying rootless status'
# [[ "$(/usr/bin/csrutil status | awk '/status/ {print $5}' | sed 's/\.$//')" == "enabled" ]] && error "csrutil ('rootless') is enabled. Please disable in boot screen and run again!"

#####################
# Turn on FileVault #
#####################
section_header 'Verifying FileVault status'
[[ "$(fdesetup isactive)" != "true" ]] && error 'FileVault is not turned on. Please encrypt your hard disk!'

##################################
# Install command line dev tools #
##################################
section_header 'Installing xcode command-line tools'
if ! is_directory '/Library/Developer/CommandLineTools/usr/bin'; then
  # install using the non-gui cmd-line alone
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  sudo softwareupdate -ia --agree-to-license --force
  rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  success 'Successfully installed xcode command-line tools'
else
  warn 'skipping installation of xcode command-line tools since its already present'
fi

#################################
# Setup ssh scripts/directories #
#################################
section_header 'Setting ssh config file permissions'
set_ssh_folder_permissions

#################################################################################
# Ensure that some of the directories corresponding to the env vars are created #
#################################################################################
section_header 'Creating directories defined by various env vars'
ensure_dir_exists "${DOTFILES_DIR}"
ensure_dir_exists "${PROJECTS_BASE_DIR}"
ensure_dir_exists "${PERSONAL_BIN_DIR}"
ensure_dir_exists "${PERSONAL_CONFIGS_DIR}"
ensure_dir_exists "${PERSONAL_PROFILES_DIR}"
ensure_dir_exists "${XDG_CACHE_HOME}"
ensure_dir_exists "${XDG_CONFIG_HOME}"
ensure_dir_exists "${XDG_DATA_HOME}"
ensure_dir_exists "${XDG_STATE_HOME}"

############################
# Disable macos gatekeeper #
############################
# section_header 'Disabling macos gatekeeper'
# sudo spectl --master-disable

#####################
# Install oh-my-zsh #
#####################
section_header "Installing oh-my-zsh into '$(yellow "${HOME}/.oh-my-zsh")'"
if ! is_directory "${HOME}/.oh-my-zsh"; then
  sh -c "$(ZSH= curl -fsSL https://install.ohmyz.sh/)" "" --unattended
  success "Successfully installed oh-my-zsh into '$(yellow "${HOME}/.oh-my-zsh")'"
else
  warn "skipping installation of oh-my-zsh since '${HOME}/.oh-my-zsh' is already present"
fi

##############################
# Install custom omz plugins #
##############################
# Note: Some of these are available via brew, but enabling them will take an additional step and the only other benefit (of keeping them up-to-date using brew can still be achieved by updating the git repos directly)
section_header 'Installing custom omz plugins'
clone_omz_plugin_if_not_present https://github.com/zdharma-continuum/fast-syntax-highlighting
clone_omz_plugin_if_not_present https://github.com/zsh-users/zsh-autosuggestions
clone_omz_plugin_if_not_present https://github.com/zsh-users/zsh-completions

####################
# Install dotfiles #
####################
section_header "Installing dotfiles into '$(yellow "${DOTFILES_DIR}")'"
if is_non_zero_string "${DOTFILES_DIR}" && ! is_git_repo "${DOTFILES_DIR}"; then
  # Delete the auto-generated .zshrc since that needs to be replaced by the one in the DOTFILES_DIR repo
  rm -rf "${ZDOTDIR}/.zshrc"

  # Note: Cloning with https since the ssh keys will not be present at this time
  clone_repo_into "https://github.com/${GH_USERNAME}/dotfiles" "${DOTFILES_DIR}"

  git -C "${DOTFILES_DIR}" switch "${DOTFILES_BRANCH}"
  local_branch="$(git -C "${DOTFILES_DIR}" branch --show-current)"
  [[ "${local_branch}" != "${DOTFILES_BRANCH}" ]] && error "'DOTFILES_BRANCH' env var is not equal to the branch that was checked out: '${local_branch}'; something is wrong. Please correct before retrying!"

  append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"

  # Use the https protocol for pull, but use ssh/git for push
  git -C "${DOTFILES_DIR}" config url.ssh://git@github.com/.pushInsteadOf https://github.com/

  install-dotfiles.rb

  # Setup any sudo access password from cmd-line to also invoke the gui touchId prompt
  approve-fingerprint-sudo.sh

  # Setup the DOTFILES_DIR repo's upstream if it doesn't already point to vraravam's repo
  git -C "${DOTFILES_DIR}" remote -vv | grep "${UPSTREAM_GH_USERNAME}"
  if [ $? -ne 0 ]; then
    git -C "${DOTFILES_DIR}" remote add upstream "https://github.com/${UPSTREAM_GH_USERNAME}/dotfiles"
    git -C "${DOTFILES_DIR}" fetch --all
    success 'Successfully set new upstream remote for the dotfiles repo'
  else
    warn 'skipping setting new upstream remote for the dotfiles repo'
  fi
else
  warn "skipping cloning the dotfiles repo since '${DOTFILES_DIR}' is either not defined or is already present"
fi

! is_non_zero_string "${HOMEBREW_PREFIX}" && error "'HOMEBREW_PREFIX' env var is not set; something is wrong. Please correct before retrying!"

# Load all zsh config files for PATH and other env vars to take effect
load_zsh_configs

####################
# Install homebrew #
####################
section_header "Installing homebrew into '$(yellow "${HOMEBREW_PREFIX}")'"
if ! command_exists brew; then
  # Prep for installing homebrew
  sudo mkdir -p "${HOMEBREW_PREFIX}/tmp" "${HOMEBREW_PREFIX}/repository" "${HOMEBREW_PREFIX}/plugins" "${HOMEBREW_PREFIX}/bin"
  sudo chown -fR "$(whoami)":admin "${HOMEBREW_PREFIX}"
  chmod u+w "${HOMEBREW_PREFIX}"

  NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  success 'Successfully installed homebrew'

  eval "$(${HOMEBREW_PREFIX}/bin/brew shellenv)"
else
  warn "skipping installation of homebrew since it's already installed"
fi
# TODO: Need to investigate why this step exits on a vanilla OS's first run of this script
brew bundle check || brew bundle --all --cleanup || true
success 'Successfully installed cmd-line and gui apps using homebrew'

# Note: Load all zsh config files for the 2nd time for PATH and other env vars to take effect (due to defensive programming)
load_zsh_configs

###########################################
# Link programs to open from the cmd-line #
###########################################
section_header 'Linking keybase for command-line invocation'
if is_directory '/Applications/Keybase.app'; then
  replace_executable_if_exists_and_is_not_symlinked '/Applications/Keybase.app/Contents/SharedSupport/bin/keybase' "${HOMEBREW_PREFIX}/bin/keybase"
  replace_executable_if_exists_and_is_not_symlinked '/Applications/Keybase.app/Contents/SharedSupport/bin/git-remote-keybase' "${HOMEBREW_PREFIX}/bin/git-remote-keybase"
  success 'Successfully linked keybase into PATH'
else
  warn 'skipping symlinking keybase for command-line invocation'
fi

section_header 'Linking VSCode/VSCodium for command-line invocation'
if is_directory '/Applications/VSCodium - Insiders.app'; then
  # Symlink from the embedded executable for codium-insiders
  replace_executable_if_exists_and_is_not_symlinked '/Applications/VSCodium - Insiders.app/Contents/Resources/app/bin/codium-insiders' "${HOMEBREW_PREFIX}/bin/codium-insiders"
  # if we are using 'vscodium-insiders' only, symlink it to 'codium' for ease of typing
  replace_executable_if_exists_and_is_not_symlinked "${HOMEBREW_PREFIX}/bin/codium-insiders" "${HOMEBREW_PREFIX}/bin/codium"
  # extra: also symlink for 'code'
  replace_executable_if_exists_and_is_not_symlinked "${HOMEBREW_PREFIX}/bin/codium" "${HOMEBREW_PREFIX}/bin/code"
  success 'Successfully linked vscodium-insiders into PATH'
elif is_directory '/Applications/VSCodium.app'; then
  # Symlink from the embedded executable for codium
  replace_executable_if_exists_and_is_not_symlinked '/Applications/VSCodium.app/Contents/Resources/app/bin/codium' "${HOMEBREW_PREFIX}/bin/codium"
  # extra: also symlink for 'code'
  replace_executable_if_exists_and_is_not_symlinked "${HOMEBREW_PREFIX}/bin/codium" "${HOMEBREW_PREFIX}/bin/code"
  success 'Successfully linked vscodium into PATH'
elif is_directory '/Applications/VSCode.app'; then
  # Symlink from the embedded executable for code
  replace_executable_if_exists_and_is_not_symlinked '/Applications/VSCode.app/Contents/Resources/app/bin/code' "${HOMEBREW_PREFIX}/bin/code"
  success 'Successfully linked vscode into PATH'
else
  warn 'skipping symlinking vscode/vscodium for command-line invocation'
fi

section_header 'Linking rider for command-line invocation'
if is_directory '/Applications/Rider.app'; then
  replace_executable_if_exists_and_is_not_symlinked '/Applications/Rider.app/Contents/MacOS/rider' "${HOMEBREW_PREFIX}/bin/rider"
  success 'Successfully linked rider into PATH'
else
  warn 'skipping symlinking rider for command-line invocation'
fi

section_header 'Linking idea/idea-ce for command-line invocation'
if is_directory '/Applications/IntelliJ IDEA CE.app'; then
  replace_executable_if_exists_and_is_not_symlinked '/Applications/IntelliJ IDEA CE.app/Contents/MacOS/idea' "${HOMEBREW_PREFIX}/bin/idea"
  success 'Successfully linked idea-ce into PATH'
elif is_directory '/Applications/IntelliJ IDEA.app'; then
  replace_executable_if_exists_and_is_not_symlinked '/Applications/IntelliJ IDEA.app/Contents/MacOS/idea' "${HOMEBREW_PREFIX}/bin/idea"
  success 'Successfully linked idea into PATH'
else
  warn 'skipping symlinking idea/idea-ce for command-line invocation'
fi

#####################
# Setup login items #
#####################
section_header 'Setting up login items'
app_list=(
  'AlDente.app'
  'Clocker.app'
  'Ice.app'
  'Itsycal.app'
  'KeepingYouAwake.app'
  'Keybase.app'
  'KeyCastr.app'
  'Raycast.app'
  'Stats.app'
  'ZoomHider.app'
)
for app in "${app_list[@]}"; do
  setup_login_item "${app}"
done

if is_non_zero_string "${KEYBASE_USERNAME}"; then
  ! command_exists keybase && error 'Keybase not found in the PATH. Aborting!!!'

  ######################
  # Login into keybase #
  ######################
  section_header 'Logging into keybase'
  ! keybase login && error 'Could not login into keybase. Retry after logging in.'

  #######################
  # Clone the home repo #
  #######################
  section_header 'Cloning home repo'
  if is_non_zero_string "${KEYBASE_HOME_REPO_NAME}"; then
    clone_repo_into "$(build_keybase_repo_url "${KEYBASE_HOME_REPO_NAME}")" "${HOME}"

    # Reset ssh keys' permissions so that git doesn't complain when using them
    set_ssh_folder_permissions

    # Fix /etc/hosts file to block facebook
    is_file "${PERSONAL_CONFIGS_DIR}/etc.hosts" && sudo cp "${PERSONAL_CONFIGS_DIR}/etc.hosts" /etc/hosts
  else
    warn "skipping cloning of home repo since the 'KEYBASE_HOME_REPO_NAME' env var hasn't been set"
  fi

  ###########################
  # Clone the profiles repo #
  ###########################
  section_header 'Cloning profiles repo'
  if is_non_zero_string "${KEYBASE_PROFILES_REPO_NAME}" && is_non_zero_string "${PERSONAL_PROFILES_DIR}"; then
    clone_repo_into "$(build_keybase_repo_url "${KEYBASE_PROFILES_REPO_NAME}")" "${PERSONAL_PROFILES_DIR}"

    # Clone the natsumi-browser repo into the ZenProfile/Profiles/chrome folder
    is_directory "${PERSONAL_PROFILES_DIR}/ZenProfile/Profiles/" && clone_repo_into "git@github.com:greeeen-dev/natsumi-browser" "${PERSONAL_PROFILES_DIR}/ZenProfile/Profiles/chrome"
  else
    warn "skipping cloning of profiles repo since either the 'KEYBASE_PROFILES_REPO_NAME' or the 'PERSONAL_PROFILES_DIR' env var hasn't been set"
  fi
else
  warn "skipping cloning of any keybase repo since 'KEYBASE_USERNAME' has not been set"
fi

if is_non_zero_string "${PERSONAL_CONFIGS_DIR}"; then
  ########################################################
  # Generate the repositories-oss.yml fie if not present #
  ########################################################
  file_name="${PERSONAL_CONFIGS_DIR}/repositories-oss.yml"
  section_header "Generating ${file_name}"
  if ! is_file "${file_name}"; then
    ensure_dir_exists "$(dirname "${file_name}")"
    cat <<EOF > "${file_name}"
- folder: "\${PROJECTS_BASE_DIR}/oss/git_scripts"
  remote: git@github.com:${UPSTREAM_GH_USERNAME}/git_scripts
  active: true
EOF
    success "Successfully generated ${file_name}"
  else
    warn "skipping generation of '${file_name}' since it already exists"
  fi

  ##################################################
  # Resurrect repositories that I am interested in #
  ##################################################
  section_header 'Resurrecting repos'
  for file in $(ls "${PERSONAL_CONFIGS_DIR}"/repositories-*.yml); do
    resurrect-repositories.rb -r "${file}"
  done
  success 'Successfully resurrected all tracked git repos'
else
  warn "skipping resurrecting of repositories since '${PERSONAL_CONFIGS_DIR}' doesn't exist"
fi

############################################################
# post-clone operations for installing system dependencies #
############################################################
section_header 'Running post-clone operations'
if command_exists all; then
  all utimes
  all maintenance register --config-file "${HOME}/.gitconfig-oss.inc"
  all maintenance start
fi
if command_exists allow_all_direnv_configs; then
  allow_all_direnv_configs
else
  warn "skipping registering all direnv configs since 'allow_all_direnv_configs' couldn't be found in the PATH; Please run it manually"
fi

if command_exists install_mise_versions; then
  install_mise_versions
else
  warn "skipping installation of languages since 'install_mise_versions' couldn't be found in the PATH; Please run it manually"
fi
rm -rf "${HOME}/.ssh/known_hosts.old"

#####################################################################################
# Load the direnv config for the home folder so that it creates necessary sym-links #
#####################################################################################
ensure_safe_load_direnv "${HOME}"

#########################################################################################
# Load the direnv config for the profiles folder so that it creates necessary sym-links #
#########################################################################################
ensure_safe_load_direnv "${PERSONAL_PROFILES_DIR}"

###################################################################
# Restore the preferences from the older machine into the new one #
###################################################################
section_header 'Restore preferences'
if command_exists 'osx-defaults.sh'; then
  osx-defaults.sh -s
  success 'Successfully baselines preferences'
else
  warn "skipping baselining of preferences since 'osx-defaults.sh' couldn't be found in the PATH; Please baseline manually and follow it up with re-import of the backed-up preferences"
fi

if command_exists 'capture-defaults.sh'; then
  capture-defaults.sh i
  success 'Successfully restored preferences from backup'
else
  warn "skipping importing of preferences since 'capture-defaults.sh' couldn't be found in the PATH; Please set it up manually"
fi

################################
# Recreate the zsh completions #
################################
section_header 'Recreate zsh completions'
rm -rf "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"
autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"

###################
# Setup cron jobs #
###################
section_header 'Setup cron jobs'
if command_exists recron; then
  recron
  success 'Successfully setup cron jobs'
else
  warn "skipping setting up of cron jobs since 'recron' couldn't be found in the PATH; Please set it up manually"
fi

# To install the latest versions of the hex, rebar and phoenix packages
# mix local.hex --force && mix local.rebar --force
# mix archive.install hex phx_new 1.4.1

# To install the native-image tool after graalvm is installed
# gu install native-image

# Enabling history for iex shell (might need to be done for each erl that is installed via mise)
# rm -rf tmp
# ensure_dir_exists tmp
# cd tmp || exit
# git clone https://github.com/ferd/erlang-history.git
# cd erlang-history || exit
# sudo make install
# cd ../.. || exit
# rm -rf tmp

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
success '** Finished auto installation process: MANUALLY QUIT AND RESTART iTerm2 and Terminal apps **'
