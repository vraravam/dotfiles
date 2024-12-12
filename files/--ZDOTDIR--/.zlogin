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
# load order: .zshenv [.shellrc], .zshrc [.shellrc, .zshrc.custom [.aliases [.shellrc, .aliases.custom]]], .zlogin
################################################################################

# execute 'FIRST_INSTALL=true zsh' to debug the load order of the custom zsh configuration files
test -n "${FIRST_INSTALL+1}" && echo "loading ${0}"

type is_directory &> /dev/null 2>&1 || source "${HOME}/.shellrc"

recompile_zsh_scripts() {
  if [[ -s "${1}" && (! -s "${1}.zwc" || "${1}" -nt "${1}.zwc") ]]; then
    echo "recompiling ${1}"
    zrecompile -pq "${1}"
  fi
}

find_in_folder_and_recompile() {
  ! is_directory "${1}" && return

  # TODO: This still doesn't handle '.pnpm' folders - need to investigate later
  for f in $(find "${1}" -maxdepth 5 -name "*.sh" -o -name "*.zsh" ! -path "**/node_modules/**"); do
    recompile_zsh_scripts "${f}"
  done
}

# Execute code in the background to not affect the current session
(
  # <https://github.com/zimfw/zimfw/blob/master/login_init.zsh>
  autoload -U zrecompile

  # zsh config files can be compiled to improve performance
  # Based from: https://github.com/romkatv/zsh-bench/blob/master/configs/ohmyzsh%2B/setup
  recompile_zsh_scripts "${ZDOTDIR}/.zshenv"
  recompile_zsh_scripts "${ZDOTDIR}/.zshrc"
  recompile_zsh_scripts "${ZDOTDIR}/.zlogin"

  find_in_folder_and_recompile "${ZDOTDIR}/.oh-my-zsh"

  # omz doesn't know about these files, and so we don't depend on 'ZDOTDIR'
  recompile_zsh_scripts "${HOME}/.aliases.custom"
  recompile_zsh_scripts "${HOME}/.aliases"
  recompile_zsh_scripts "${HOME}/.p10k.zsh"
  recompile_zsh_scripts "${HOME}/.shellrc"
  recompile_zsh_scripts "${HOME}/.zshrc.custom"

  find_in_folder_and_recompile "${DOTFILES_DIR}"
  find_in_folder_and_recompile "${PERSONAL_BIN_DIR}"
  find_in_folder_and_recompile "${PROJECTS_BASE_DIR}"
  # explicitly use both intel and m1 install locations of homebrew
  find_in_folder_and_recompile /opt/homebrew
  find_in_folder_and_recompile /usr/local
) &!
