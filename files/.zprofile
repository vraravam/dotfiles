#!/usr/bin/env zsh

# vim:syntax=zsh
# vim:filetype=zsh

# file location: ${HOME}/.zprofile
# load order: .zshenv, .zprofile, .shellrc, .zshrc, .zshrc.custom, .aliases, .aliases.custom, .zlogin
[ -n "${FIRST_INSTALL+1}" ] && echo "loading .zprofile"

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

export PROJECTS_BASE_DIR="${HOME}/dev"
export PERSONAL_CONFIGS_DIR="${HOME}/personal/dev"
export PERSONAL_PROFILES_DIR="${HOME}/personal/${USERNAME}/profiles"
export PERSONAL_BIN_DIR="${HOME}/.bin"
export DOTFILES_DIR="${HOME}/.bin-oss"

# Do not move this to .zshenv - since that messes up the PATH (homebrew randomly doesn't come ahead of system path)
# Note:
# 1. Added '/usr/local/bin' to the PATH since keybase, devbox, sentinelOne - all install to this hardcoded location
#    BUGFIX for keybase installation on arm macs: https://github.com/keybase/client/issues/15176#issuecomment-1150480862
export PATH="${PATH+:${PATH}}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PERSONAL_BIN_DIR}:${PERSONAL_BIN_DIR}/macos:${PROJECTS_BASE_DIR}/oss/git_scripts:${DOTFILES_DIR}/scripts"

type load_file_if_exists &> /dev/null 2>&1 || source "${HOME}/.shellrc"
