#!/usr/bin/env zsh

# vim:syntax=zsh
# vim:filetype=zsh

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
  ! var_exists_and_is_directory "${1}" && return

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
  recompile_zsh_scripts "${ZDOTDIR:-${HOME}}/.aliases.custom"
  recompile_zsh_scripts "${ZDOTDIR:-${HOME}}/.aliases"
  recompile_zsh_scripts "${ZDOTDIR:-${HOME}}/.p10k.zsh"
  recompile_zsh_scripts "${ZDOTDIR:-${HOME}}/.shellrc"
  recompile_zsh_scripts "${ZDOTDIR:-${HOME}}/.zprofile"
  recompile_zsh_scripts "${ZDOTDIR:-${HOME}}/.zshenv"
  recompile_zsh_scripts "${ZDOTDIR:-${HOME}}/.zshrc.custom"
  recompile_zsh_scripts "${ZDOTDIR:-${HOME}}/.zshrc"

  find_in_folder_and_recompile "${HOME}/.bin-oss"
  find_in_folder_and_recompile "${HOME}/.bin"
  find_in_folder_and_recompile "${HOME}/dev/oss"
  find_in_folder_and_recompile "${HOME}/personal/dev"
  find_in_folder_and_recompile "${ZDOTDIR:-${HOME}}/.oh-my-zsh"
  find_in_folder_and_recompile /opt/homebrew
  find_in_folder_and_recompile /usr/local
) &!
