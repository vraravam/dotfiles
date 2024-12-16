#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is idempotent and will restore your local setup to the same state even if run multiple times.
# In most cases, the script will provide warning messages if skipping certain steps. Each such message will be useful to give you a hint about what to do to force rerunning of that step.

# file location: <anywhere; but advisable in the PATH>

# TODO: Need to figure out the scriptable commands for the following settings:
# 1. Auto-adjust Brightness
# 2. Brightness on battery
# 3. Keyboard brightness

######################################################################################################################
# Set DNS of 8.8.8.8 before proceeding (in some cases, for eg Jio Wifi, github doesn't resolve at all and times out) #
######################################################################################################################
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

###############################
# Do not allow rootless login #
###############################
# Note: Commented out since I am not sure if we need to do this on the office MBP or not
# ROOTLESS_STATUS=$(/usr/bin/csrutil status | awk '/status/ {print $5}' | sed 's/\.$//')
# if [[ ${ROOTLESS_STATUS} == "enabled" ]]; then
#   echo "csrutil (\"rootless\") is enabled. please disable in boot screen and run again!"
#   exit 1
# fi

#####################
# Turn on FileVault #
#####################
section_header 'Verifying FileVault status'
if [[ "$(fdesetup isactive)" != "true" ]]; then
  echo "$(red 'FileVault is not turned on. Please encrypt your hard disk!')"
  exit 1
fi

##################################
# Install command line dev tools #
##################################
section_header 'Installing xcode command-line tools'
if ! is_directory '/Library/Developer/CommandLineTools/usr/bin'; then
  reinstall_xcode_cmdline_tools
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
ZSH_CUSTOM="${ZSH_CUSTOM:-${ZSH:-${HOME}/.oh-my-zsh}/custom}"
ensure_dir_exists "${ZSH_CUSTOM}/plugins"
clone_omz_plugin_if_not_present() {
  local target_folder="${ZSH_CUSTOM}/plugins/$(basename ${1})"
  if ! is_directory "${target_folder}"; then
    clone_repo_into "${1}" "${target_folder}"
    success "Successfully cloned oh-my-zsh plugin ${1} into ${target_folder}"
  else
    warn "skipping cloning of '$(basename "${1}")' since '${target_folder}' is already present"
  fi
}
clone_omz_plugin_if_not_present https://github.com/zdharma-continuum/fast-syntax-highlighting
clone_omz_plugin_if_not_present https://github.com/zsh-users/zsh-autosuggestions
clone_omz_plugin_if_not_present https://github.com/zsh-users/zsh-completions
clone_omz_plugin_if_not_present https://github.com/romkatv/zsh-defer

####################
# Install dotfiles #
####################
section_header "Installing dotfiles into '$(yellow "${DOTFILES_DIR}")'"
if is_non_zero_string "${DOTFILES_DIR}" && ! is_git_repo "${DOTFILES_DIR}"; then
  # Delete the auto-generated .zshrc since that needs to be replaced by the one in the DOTFILES_DIR repo
  rm -rfv "${HOME}/.zshrc"

  # Note: Cloning with https since the ssh keys will not be present at this time
  clone_repo_into "https://github.com/${GH_USERNAME}/dotfiles" "${DOTFILES_DIR}"
  success "Successfully cloned the dotfiles repo into ${DOTFILES_DIR}"

  git -C "${DOTFILES_DIR}" switch "${DOTFILES_BRANCH}"
  if [[ "$(git -C "${DOTFILES_DIR}" branch --show-current)" != "${DOTFILES_BRANCH}" ]]; then
    echo "$(red "'DOTFILES_BRANCH' env var is not equal to the branch that was checked out; something is wrong. Please correct before retrying!")"
    exit -1
  fi

  # Use the https protocol for pull, but use ssh/git for push
  git -C "${DOTFILES_DIR}" config url.ssh://git@github.com/.pushInsteadOf https://github.com/

  # since this folder hasn't been added to the PATH yet, invoke with full name including the location
  eval "${DOTFILES_DIR}/scripts/install-dotfiles.rb"

  # Setup any sudo access password from cmd-line to also invoke the gui touchId prompt
  eval "${DOTFILES_DIR}/scripts/approve-fingerprint-sudo.sh"

  # Load all zsh config files for PATH and other env vars to take effect
  load_zsh_configs

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
  # Load all zsh config files for PATH and other env vars to take effect
  load_zsh_configs
  warn "skipping cloning the dotfiles repo since '${DOTFILES_DIR}' is either not defined or is already present"
fi

if ! is_non_zero_string "${HOMEBREW_PREFIX}"; then
  echo "$(red "'HOMEBREW_PREFIX' env var is not set; something is wrong. Please correct before retrying!")"
  exit -1
fi

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
sh -c "${HOMEBREW_PREFIX}/bin/brew bundle --file '${HOME}/Brewfile'"

###########################################
# Link programs to open from the cmd-line #
###########################################
replace_executable_if_exists_and_is_not_symlinked() {
  if is_executable "${1}"; then
    rm -rf "${2}"
    ln -sf "${1}" "${2}"
  else
    warn "executable '${1}' not found and so skipping symlinking"
  fi
}

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
setup_login_item() {
  if is_directory "/Applications/${1}"; then
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/${1}\", hidden:false}" 2>&1 > /dev/null && success "Successfully setup '$(yellow "${1}")' $(green "as a login item")"
  else
    warn "Couldn't find application '/Applications/${1}' and so skipping setting up as a login item"
  fi
}

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

echo "\n"
success '** Finished auto installation process: MANUALLY QUIT AND RESTART iTerm2 and Terminal apps **'
