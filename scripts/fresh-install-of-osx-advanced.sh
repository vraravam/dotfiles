#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# Note: This script is specific to my setup and might not be useful for others. This is being shared so as to be used as a reference if you want to mimic the same setup.

type is_non_zero_string &> /dev/null 2>&1 || source "${HOME}/.shellrc"

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
    if ! is_git_repo "${HOME}"; then
      # Note: Clone into a tmp folder since ${HOME} will not be empty, and we don't want to delete all its children
      clone_repo_into "keybase://private/${KEYBASE_USERNAME}/${KEYBASE_HOME_REPO_NAME}" "${HOME}/tmp"
      mv -fv "${HOME}/tmp/.git" "${HOME}/"
      rm -rf "${HOME}/tmp"
      success "Successfully cloned the home repo into ${HOME}"

      # Checkout files (these should not have any modifications/conflicts with what is in the remote repo)
      git -C "${HOME}" checkout ".[a-zA-Z]*" personal

      # Reset ssh keys' permissions so that git doesn't complain when using them
      set_ssh_folder_permissions

      # Fix /etc/hosts file to block facebook
      is_file "${PERSONAL_CONFIGS_DIR}/etc.hosts" && sudo cp "${PERSONAL_CONFIGS_DIR}/etc.hosts" /etc/hosts
    else
      warn "skipping cloning of home repo since a git repo is already present in '${HOME}'"
    fi
  else
    warn "skipping cloning of home repo since the 'KEYBASE_HOME_REPO_NAME' env var hasn't been set"
  fi

  ###########################
  # Clone the profiles repo #
  ###########################
  section_header 'Cloning profiles repo'
  if is_non_zero_string "${KEYBASE_PROFILES_REPO_NAME}"; then
    if ! is_git_repo "${PERSONAL_PROFILES_DIR}"; then
      clone_repo_into "keybase://private/${KEYBASE_USERNAME}/${KEYBASE_PROFILES_REPO_NAME}" "${PERSONAL_PROFILES_DIR}"
      success "Successfully cloned the profiles repo into ${PERSONAL_PROFILES_DIR}"

      # since the above lines will delete the .envrc & .gitignore that were earlier copied into the profiles folder, we will re-run the install script
      eval "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
    else
      warn "skipping cloning of profiles repo since a git repo is already present in '${PERSONAL_PROFILES_DIR}'"
    fi
  else
    warn "skipping cloning of profiles repo since the 'KEYBASE_PROFILES_REPO_NAME' env var hasn't been set"
  fi
else
  warn "skipping cloning of any keybase repo since 'KEYBASE_USERNAME' has not been set"
fi

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
if is_non_zero_string "${PERSONAL_CONFIGS_DIR}"; then
  for file in $(ls "${PERSONAL_CONFIGS_DIR}"/repositories-*.yml); do
    "${DOTFILES_DIR}/scripts/resurrect-repositories.rb" -r "${file}"
  done
else
  warn "skipping resurrecting of repositories since '${PERSONAL_CONFIGS_DIR}' doesn't exist"
fi

############################################################
# post-clone operations for installing system dependencies #
############################################################
section_header 'Running post-clone operations'
if command_exists all; then
  all restore-mtime -c
  all maintenance register --config-file "${HOME}/.gitconfig-oss.inc"
  all maintenance start
fi
command_exists allow_all_direnv_configs && allow_all_direnv_configs
command_exists install_mise_versions && install_mise_versions
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
# Run within a separate bash shell to avoid quitting due to errors
is_file "${DOTFILES_DIR}/scripts/osx-defaults.sh" && bash -c "${DOTFILES_DIR}/scripts/osx-defaults.sh -s"
is_file "${DOTFILES_DIR}/scripts/capture-defaults.sh" && "${DOTFILES_DIR}/scripts/capture-defaults.sh" i
success 'Successfully restored preferences'

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
command_exists recron && recron && success 'Successfully setup cron jobs'

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
