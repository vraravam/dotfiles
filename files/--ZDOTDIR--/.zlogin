#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# This file is sourced only for login shells. It should contain commands that
# should be executed only in login shells. It should be used to set the terminal
# type and run a series of external commands (fortune, msgs, from, etc.)
# Note that using zprofile and zlogin, you are able to run commands for login
# shells before and after zshrc.
#
# file location: ${ZDOTDIR}/.zlogin
# load order: .zshenv [.shellrc], .zshrc [.shellrc, .aliases [.shellrc]], .zlogin
################################################################################

# execute 'DEBUG=true zsh' to debug the load order of the custom zsh configuration files
[[ -n "${DEBUG+1}" ]] && echo "loading ${0}"

type is_shellrc_sourced 2>&1 &> /dev/null || source "${HOME}/.shellrc"

recompile_zsh_scripts() {
  if ! is_file_empty "${1}" && (! is_file "${1}.zwc" || [[ "${1}" -nt "${1}.zwc" ]]); then
    [[ -n "${DEBUG+1}" ]] && echo "recompiling ${1}"
    zrecompile -pq "${1}" 2>&1 &> /dev/null
  fi
}

find_in_folder_and_recompile() {
  local dir_to_scan="${1}"
  local f # Loop variable

  if ! is_directory "${dir_to_scan}"; then
    echo "Warning: Directory '${dir_to_scan}' not found for zsh script recompilation." >&2
    return
  fi

  find "${dir_to_scan}" -maxdepth 5 \
    \( \( -name 'node_modules' -o -name '.pnpm' \) -type d -prune \) -o \
    \( \( -name '*.sh' -o -name '*.zsh' \) -type f -print0 \) |
    while IFS= read -r -d $'\0' f; do
    recompile_zsh_scripts "${f}"
  done
}

# <https://github.com/zimfw/zimfw/blob/master/login_init.zsh>
autoload -Uz zrecompile

# zsh config files can be compiled to improve performance
# Based from: https://github.com/romkatv/zsh-bench/blob/master/configs/ohmyzsh%2B/setup
recompile_zsh_scripts "${ZDOTDIR}/.zshenv"
recompile_zsh_scripts "${ZDOTDIR}/.zshrc"
recompile_zsh_scripts "${ZDOTDIR}/.zlogin"

find_in_folder_and_recompile "${ZSH}"

# omz doesn't know about these files, and so we don't depend on 'ZDOTDIR'
recompile_zsh_scripts "${HOME}/.aliases"
recompile_zsh_scripts "${HOME}/.p10k.zsh"
recompile_zsh_scripts "${HOME}/.shellrc"

find_in_folder_and_recompile "${DOTFILES_DIR}"
find_in_folder_and_recompile "${PERSONAL_BIN_DIR}"
find_in_folder_and_recompile "${PROJECTS_BASE_DIR}"
# explicitly use both intel and arm install locations of homebrew
find_in_folder_and_recompile /opt/homebrew
find_in_folder_and_recompile /usr/local

[[ -n "${DEBUG+1}" ]] && echo "Finished recompiling zsh scripts."
