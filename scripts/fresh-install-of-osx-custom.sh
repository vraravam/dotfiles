#!/usr/bin/env zsh

# Note: This script is specific to my setup and might not be useful for others. This is being shared so as to be used as a reference if you want to mimic the same setup.

# TODO: Replace all occurrences of '-d' with 'var_exists_and_is_directory'

type load_zsh_configs &> /dev/null 2>&1 || FIRST_INSTALL=true source "${HOME}/.shellrc"
# Load all zsh config files for PATH and other env vars to take effect
# Note: Can't run 'exec zsh' here - since the previous function definitions and PATH, etc will be lost in the sub-shell
load_zsh_configs

! command_exists keybase && echo "Keybase not found in the PATH. Aborting!!!" && exit -1

######################
# Login into keybase #
######################
echo "$(green "==> Logging into keybase")"
keybase login
if [ $? -ne 0 ]; then
  echo "Could not login into keybase. Retry again."
  exit -1
fi

#######################
# Clone the home repo #
#######################
echo "$(green "==> Cloning home repo")"
if [ ! -z "${KEYBASE_USERNAME}" ] && [ ! -z "${KEYBASE_HOME_REPO_NAME}" ] && [ ! -d "${HOME}/.git" ]; then
  rm -rf "${HOME}/tmp"
  mkdir -p "${HOME}/tmp"
  git clone keybase://private/${KEYBASE_USERNAME}/${KEYBASE_HOME_REPO_NAME} "${HOME}/tmp"
  mv "${HOME}/tmp/.git" "${HOME}/"
  rm -rf "${HOME}/tmp"

  # Checkout files (these should not have any modifications/conflicts with what is in the remote repo)
  git -C "${HOME}" checkout ".[a-zA-Z]*" personal

  # Reset ssh keys' permissions so that git doesn't complain when using them
  sudo chmod -R 600 "${HOME}"/.ssh/* || true

  # Fix /etc/hosts file to block facebook #
  sudo cp "${PERSONAL_BIN_DIR}/macos/etc.hosts" /etc/hosts
else
  warn "skipping cloning of home repo since either the 'KEYBASE_USERNAME' and/or the 'KEYBASE_HOME_REPO_NAME' env vars haven't been set or a git repo is already present in '${HOME}'"
fi

###########################
# Clone the profiles repo #
###########################
echo "$(green "==> Cloning profiles repo")"
if [ ! -z "${KEYBASE_USERNAME}" ] && [ ! -z "${KEYBASE_PROFILES_REPO_NAME}" ] && [ ! -d "${PERSONAL_PROFILES_DIR}/.git" ]; then
  rm -rf "${PERSONAL_PROFILES_DIR}"
  git clone keybase://private/${KEYBASE_USERNAME}/${KEYBASE_PROFILES_REPO_NAME} "${PERSONAL_PROFILES_DIR}"
else
  warn "skipping cloning of profiles repo since either the 'KEYBASE_USERNAME' and/or the 'KEYBASE_PROFILES_REPO_NAME' env vars haven't been set or a git repo is already present in '${PERSONAL_PROFILES_DIR}'"
fi

########################################################
# Generate the repositories-oss.yml fie if not present #
########################################################
file_name="${PERSONAL_CONFIGS_DIR}/repositories-oss.yml"
echo "$(green "==> Generating ${file_name}")"
if [[ ! -f "${file_name}" ]]; then
  mkdir -p "$(dirname "${file_name}")"
  cat <<EOF > "${file_name}"
- folder: "\${PROJECTS_BASE_DIR}/oss/git_scripts"
  remote: git@github.com:vraravam/git_scripts
  active: true
EOF
else
  warn "skipping generation of '${file_name}' since it already exists"
fi

##################################################
# Resurrect repositories that I am interested in #
##################################################
echo "$(green "==> Resurrecting repos")"
if var_exists_and_is_directory "${PERSONAL_PROFILES_DIR}"; then
  for file in $(ls "${PERSONAL_CONFIGS_DIR}"/repositories-*.yml); do
    resurrect-repositories.rb -r "${file}"
  done
else
  warn "skipping resurrecting of repositories since '${PERSONAL_CONFIGS_DIR}' doesn't exist"
fi

############################################################
# post-clone operations for installing system dependencies #
############################################################
echo "$(green "==> Running post-clone operations")"
command_exists all && all restore-mtime -c
command_exists allow_all_direnv_configs && allow_all_direnv_configs
command_exists install_mise_versions && install_mise_versions
rm -rf "${HOME}/.ssh/known_hosts.old"

##############################################
# Load the direnv config for the home folder #
##############################################
# TODO: See how this can be combined into 'allow_all_direnv_configs'
cd ..
cd -

##################################################
# Load the direnv config for the profiles folder #
##################################################
# TODO: See how this can be combined into 'allow_all_direnv_configs'
if [ -d "${PERSONAL_PROFILES_DIR}" ]; then
  cd "${PERSONAL_PROFILES_DIR}"
  cd -
fi

###################################################################
# Restore the preferences from the older machine into the new one #
###################################################################
echo "$(green "==> Restore preferences")"
# "Run within a separate bash shell to avoid quitting due to errors
command_exists "osx-defaults.sh" && bash -c "osx-defaults.sh -s"
command_exists "capture-defaults.sh" && capture-defaults.sh i

################################
# Recreate the zsh completions #
################################
echo "$(green "==> Recreate zsh completions")"
rm -rf "${HOME}"/.zcompdump*; compinit

###################
# Setup cron jobs #
###################
echo "$(green "==> Setup cron jobs")"
command_exists recron && recron

# To install the latest versions of the hex, rebar and phoenix packages
# mix local.hex --force && mix local.rebar --force
# mix archive.install hex phx_new 1.4.1

# To install the native-image tool after graalvm is installed
# gu install native-image

# Enabling history for iex shell (might need to be done for each erl that is installed via mise)
# rm -rf tmp
# mkdir -p tmp
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
echo "$(green "********** Finished auto installation process: Please perform these manual steps **********")"
