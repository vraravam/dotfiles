#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# This file is sourced only for login shells (i.e. shells invoked with "-" as
# the first character of argv[0], and shells invoked with the -l flag). It's
# read after zshenv.
#
# file location: ${HOME}/.zprofile
# load order: .zshenv, .zprofile [.shellrc], .zshrc [.zshrc.custom [.aliases [.aliases.custom]]], .zlogin
################################################################################

# execute 'FIRST_INSTALL=true zsh' to debug the load order of the custom zsh configuration files
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

export XDG_CACHE_HOME="${HOME}/.cache"
export XDG_CONFIG_HOME="${HOME}/.config"

# Note: Change these as per your settings. Deleting them will essentially unset the var(s) and thus any aliases/paths/etc will not be processed for those deleted variable(s)
export GH_USERNAME="vraravam"
export UPSTREAM_GH_USERNAME="vraravam" # Note: Do NOT change this
export PROJECTS_BASE_DIR="${HOME}/dev"
export PERSONAL_CONFIGS_DIR="${HOME}/personal/dev/configs"
export PERSONAL_BIN_DIR="${HOME}/personal/dev/bin"
export PERSONAL_PROFILES_DIR="${HOME}/personal/$(whoami)/profiles"
export DOTFILES_DIR="${HOME}/.bin-oss"
export KEYBASE_USERNAME="avijayr"
export KEYBASE_HOME_REPO_NAME="home"
export KEYBASE_PROFILES_REPO_NAME="profiles"
