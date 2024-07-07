#!/usr/bin/env zsh

# vim:syntax=zsh
# vim:filetype=zsh

# file location: ${HOME}/.zprofile
# load order: .zshenv, .zprofile, .shellrc, .zshrc, .zshrc.custom, .aliases, .aliases.custom, .zlogin
test -n "${FIRST_INSTALL+1}" && echo "loading ${0}"

# CAUTION! This file is NOT loaded when running only 'exec zsh'! So beware of expecting the exported variables inside this to be defined!
# Note: login shell - only env vars and other functions that don't load anything should go in here

export LANG='en_US.UTF-8'
export LANGUAGE='en_US.UTF-8'
export LC_COLLATE='en_US.UTF-8'
export LC_CTYPE='en_US.UTF-8'
export LC_MESSAGES='en_US.UTF-8'
export LC_MONETARY='en_US.UTF-8'
export LC_NUMERIC='en_US.UTF-8'
export LC_TIME='en_US.UTF-8'
export LC_ALL='en_US.UTF-8'
export LESSCHARSET='utf-8'

# Note: Change these as per your settings. Deleting them will essentially unset the var(s) and thus any aliases/paths/etc will not be processed for those deleted variable(s)
export USERNAME="$(whoami)"
export PROJECTS_BASE_DIR="${HOME}/dev"
export PERSONAL_CONFIGS_DIR="${HOME}/personal/dev"
export PERSONAL_PROFILES_DIR="${HOME}/personal/${USERNAME}/profiles"
export PERSONAL_BIN_DIR="${HOME}/.bin"
export DOTFILES_DIR="${HOME}/.bin-oss"
export KEYBASE_USERNAME="avijayr"
export KEYBASE_HOME_REPO_NAME="home"
export KEYBASE_PROFILES_REPO_NAME="profiles"

type load_file_if_exists &> /dev/null 2>&1 || source "${HOME}/.shellrc"
