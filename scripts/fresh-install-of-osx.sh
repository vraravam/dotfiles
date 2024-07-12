#!/usr/bin/env zsh

# This script is idempotent and will restore your local setup to the same state even if run multiple times.
# In most cases, the script will provide warning messages if skipping certain steps. Each such message will be useful to give you a hint about what to do to force rerunning of that step.

# file location: <anywhere; but advisable in the PATH>

# TODO: Need to figure out the scriptable commands for the following settings:
# 1. Auto-adjust Brightness
# 2. Brightness on battery
# 3. Keyboard brightness
# 4. Replace all occurrences of '-d' with 'var_exists_and_is_directory'

######################################################################################################################
# Set DNS of 8.8.8.8 before proceeding (in some cases, for eg Jio Wifi, github doesn't resolve at all and times out) #
######################################################################################################################
echo "==> Setting DNS for WiFi"
sudo networksetup -setdnsservers Wi-Fi 8.8.8.8

#################################################################################################
# Download and source this utility script - so that the functions are available for this script #
#################################################################################################
echo "==> Download the '${HOME}/.shellrc' for loading the utility functions"
if ! type load_zsh_configs &> /dev/null 2>&1; then
  [ ! -f "${HOME}/.shellrc" ] && curl -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/master/files/.shellrc" -o "${HOME}/.shellrc"
  FIRST_INSTALL=true source "${HOME}/.shellrc"
else
  warn "skipping downloading and sourcing '${HOME}/.shellrc' since its already loaded"
fi

##################################
# Install command line dev tools #
##################################
echo "$(green "==> Installing xcode command-line tools")"
if ! xcode-select -p > /dev/null 2>&1; then
  # install using the non-gui cmd-line alone
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  softwareupdate -ia
  rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  sudo xcodebuild -license accept || true
else
  warn "skipping installation of xcode command-line tools since its already present"
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
echo "$(green "==> Verifying FileVault status")"
FILEVAULT_STATUS=$(fdesetup status)
if [[ ${FILEVAULT_STATUS} != "FileVault is On." ]]; then
  echo "$(red "FileVault is not turned on. Please encrypt your hard disk!")"
  exit 1
fi

#################################
# Setup ssh scripts/directories #
#################################
mkdir -p "${HOME}/.ssh"
sudo chmod -R 600 "${HOME}"/.ssh/* || true

############################
# Disable macos gatekeeper #
############################
# sudo spectl --master-disable

#####################
# Install oh-my-zsh #
#####################
echo "$(green "==> Installing oh-my-zsh")"
if [ ! -d "${HOME}/.oh-my-zsh" ]; then
  ZSH= curl -fsSL http://install.ohmyz.sh | sh
else
  warn "skipping installation of oh-my-zsh since '${HOME}/.oh-my-zsh' is already present"
fi

##############################
# Install custom omz plugins #
##############################
echo "$(green "==> Installing custom omz plugins")"
ZSH_CUSTOM="${ZSH_CUSTOM:-${ZSH:-${HOME}/.oh-my-zsh}/custom}"
mkdir -p "${ZSH_CUSTOM}/plugins"
clone_if_not_present() {
  target_folder="${ZSH_CUSTOM}/plugins/$(basename ${1})"
  if [ ! -d "${target_folder}" ]; then
    git clone "${1}" "${target_folder}"
  else
    warn "skipping cloning of '${1}' since '${target_folder}' is already present"
  fi
}
# clone_if_not_present https://github.com/mroth/evalcache # Commented out since I'm going to try using it via omz's built-in plugin system
clone_if_not_present https://github.com/zdharma-continuum/fast-syntax-highlighting
clone_if_not_present https://github.com/zsh-users/zsh-autosuggestions
clone_if_not_present https://github.com/zsh-users/zsh-completions

####################
# Install dotfiles #
####################
echo "$(green "==> Installing dotfiles")"
if [[ ! -z "${DOTFILES_DIR}" && ! -d "${DOTFILES_DIR}" ]]; then
  # Delete the auto-generated .zshrc since that needs to be replaced by the one in the .bin-oss repo
  rm -rfv "${HOME}/.zshrc"

  # Note: Cloning with https since the ssh keys will not be present at this time
  git clone "https://github.com/${GH_USERNAME}/dotfiles" "${DOTFILES_DIR}"

  # Use the https protocol for pull, but use ssh/git for push
  git -C "${DOTFILES_DIR}" config url.ssh://git@github.com/.pushInsteadOf https://github.com/

  # since this folder hasn't been added to the PATH yet, invoke with full name including the location
  eval "${DOTFILES_DIR}/scripts/install-dotfiles.rb"

  # Setup any sudo access password from cmd-line to also invoke the gui touchId prompt
  eval "${DOTFILES_DIR}/scripts/approve-fingerprint-sudo.sh"

  # Load all zsh config files for PATH and other env vars to take effect
  # Note: Can't run 'exec zsh' here - since the previous function definitions and PATH, etc will be lost in the sub-shell
  load_zsh_configs

  # Setup the .bin-oss repo's upstream if it doesn't already point to vraravam's repo
  git -C "${DOTFILES_DIR}" remote -vv | grep "${UPSTREAM_GH_USERNAME}"
  if [ $? -ne 0 ]; then
    git -C "${DOTFILES_DIR}" remote add upstream "https://github.com/${UPSTREAM_GH_USERNAME}/dotfiles"
    git -C "${DOTFILES_DIR}" fetch --all
  else
    warn "skipping setting new upstream remote for the dotfiles repo"
  fi
else
  # Load all zsh config files for PATH and other env vars to take effect
  load_zsh_configs
  warn "skipping cloning the dotfiles repo since '${DOTFILES_DIR}' is not defined or already present"
fi

####################
# Install homebrew #
####################
echo "$(green "==> Installing homebrew")"
if ! command_exists brew; then
  # Prep for installing homebrew
  sudo mkdir -p "${HOMEBREW_PREFIX}/tmp" "${HOMEBREW_PREFIX}/repository" "${HOMEBREW_PREFIX}/plugins" "${HOMEBREW_PREFIX}/bin"
  sudo chown -fR "$(whoami)":admin "${HOMEBREW_PREFIX}"
  chmod u+w "${HOMEBREW_PREFIX}"

  bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

  eval "$(${HOMEBREW_PREFIX}/bin/brew shellenv)"
else
  warn "skipping installation of homebrew since it's already installed"
fi
brew bundle check || brew bundle --all || true

###########################################
# Link programs to open from the cmd-line #
###########################################
echo "$(green "==> Linking VSCode/VSCodium for command-line invocation")"
replace_executable_if_exists_and_is_not_symlinked() {
  if [ -e "${1}" ]; then
    rm -fv "${2}" && ln -sf "${1}" "${2}"
  else
    warn "executable '${1}' not found and so skipping symlinking"
  fi
}

if [ -d "/Applications/VSCodium - Insiders.app" ]; then
  # Symlink from the embedded executable for codium-insiders
  replace_executable_if_exists_and_is_not_symlinked "/Applications/VSCodium - Insiders.app/Contents/Resources/app/bin/codium-insiders" "${HOMEBREW_PREFIX}/bin/codium-insiders"
  # if we are using 'vscodium-insiders' only, symlink it to 'codium' for ease of typing
  replace_executable_if_exists_and_is_not_symlinked "${HOMEBREW_PREFIX}/bin/codium-insiders" "${HOMEBREW_PREFIX}/bin/codium"
  # extra: also symlink for 'code'
  replace_executable_if_exists_and_is_not_symlinked "${HOMEBREW_PREFIX}/bin/codium" "${HOMEBREW_PREFIX}/bin/code"
elif [ -d "/Applications/VSCodium.app" ]; then
  # Symlink from the embedded executable for codium
  replace_executable_if_exists_and_is_not_symlinked "/Applications/VSCodium.app/Contents/Resources/app/bin/codium" "${HOMEBREW_PREFIX}/bin/codium"
  # extra: also symlink for 'code'
  replace_executable_if_exists_and_is_not_symlinked "${HOMEBREW_PREFIX}/bin/codium" "${HOMEBREW_PREFIX}/bin/code"
elif [ -d "/Applications/VSCode.app" ]; then
  # Symlink from the embedded executable for code
  replace_executable_if_exists_and_is_not_symlinked "/Applications/VSCode.app/Contents/Resources/app/bin/code" "${HOMEBREW_PREFIX}/bin/code"
else
  warn "skipping symlinking vscode/vscodium for command-line invocation"
fi

echo "$(green "==> Linking rider for command-line invocation")"
if [ -d "/Applications/Rider.app" ]; then
  replace_executable_if_exists_and_is_not_symlinked "/Applications/Rider.app/Contents/MacOS/rider" "${HOMEBREW_PREFIX}/bin/rider"
else
  warn "skipping symlinking rider for command-line invocation"
fi

echo "$(green "==> Linking idea-ce for command-line invocation")"
if [ -d "/Applications/IntelliJ IDEA CE.app" ]; then
  replace_executable_if_exists_and_is_not_symlinked "/Applications/IntelliJ IDEA CE.app/Contents/MacOS/idea" "${HOMEBREW_PREFIX}/bin/idea"
else
  warn "skipping symlinking idea for command-line invocation"
fi

# defaults write -g NSFileViewer -string org.yanex.marta
# To revert back to use Finder as default file manager you can enter
# defaults delete -g NSFileViewer
# ln -sf /Applications/Marta.app/Contents/Resources/launcher ${HOMEBREW_PREFIX}/bin/marta

#####################
# Setup login items #
#####################
echo "$(green "==> Setting up login items")"
setup_login_item() {
  if [ -d "/Applications/${1}" ]; then
    echo "Setting up '${1}' as a login item" && osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/${1}\", hidden:false}" 2>&1 > /dev/null
  else
    warn "Couldn't find application '/Applications/${1}' and so skipping setting up as a login item"
  fi
}

app_list=(
  'AlDente.app'
  'Clocker.app'
  'Cloudflare WARP.app'
  'Command X.app'
  'iBar.app'
  'Itsycal.app'
  'KeepingYouAwake.app'
  'Keybase.app'
  'Raycast.app'
  'Stats.app'
)
for app in "${app_list[@]}"; do
  setup_login_item "${app}"
done

echo "\n"
echo "$(green "********** Finished auto installation process: MANUALLY QUIT AND RESTART iTerm2 and Terminal apps **********")"
