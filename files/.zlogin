#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab fileencoding=utf-8

# file location: ${HOME}/.zlogin
# load order: .zshenv, .zprofile, .shellrc, .zshrc, .zshrc.custom, .aliases, .aliases.custom, .zlogin
test -n "${FIRST_INSTALL+1}" && echo "loading ${0}"

recompile_zsh_scripts() {
  if [[ -s "${1}" && (! -s "${1}.zwc" || "${1}" -nt "${1}.zwc") ]]; then
    echo "recompiling ${1}"
    zrecompile -pq "${1}"
  fi
}

find_in_folder_and_recompile() {
  ! is_directory "${1}" && return

  # TODO: This still doesn't handle '.pnpm' folders - need to investigate later
  for f in $(find "${1}" -maxdepth 4 -name "*.sh" -o -name "*.zsh" ! -path "**/node_modules/**"); do
    recompile_zsh_scripts "${f}"
  done
}

# Execute code in the background to not affect the current session
(
  # <https://github.com/zimfw/zimfw/blob/master/login_init.zsh>
  setopt LOCAL_OPTIONS EXTENDED_GLOB
  autoload -U zrecompile

  # zsh config files can be compiled to improve performance
  # Based from: https://github.com/romkatv/zsh-bench/blob/master/configs/ohmyzsh%2B/setup
  recompile_zsh_scripts "${ZDOTDIR}/.zprofile"
  recompile_zsh_scripts "${ZDOTDIR}/.zshenv"
  recompile_zsh_scripts "${ZDOTDIR}/.zshrc.custom"
  recompile_zsh_scripts "${ZDOTDIR}/.zshrc"

  find_in_folder_and_recompile "${ZDOTDIR}/.oh-my-zsh"

  # omz doesn't know about these files, and so we don't depend on 'ZDOTDIR'
  recompile_zsh_scripts "${HOME}/.aliases.custom"
  recompile_zsh_scripts "${HOME}/.aliases"
  recompile_zsh_scripts "${HOME}/.p10k.zsh"
  recompile_zsh_scripts "${HOME}/.shellrc"

  find_in_folder_and_recompile "${DOTFILES_DIR}"
  find_in_folder_and_recompile "${PERSONAL_BIN_DIR}"
  find_in_folder_and_recompile "${PROJECTS_BASE_DIR}"
  find_in_folder_and_recompile "${PERSONAL_CONFIGS_DIR}"
  # explicitly use both intel and m1 install locations of homebrew
  find_in_folder_and_recompile /opt/homebrew
  find_in_folder_and_recompile /usr/local
) &!
