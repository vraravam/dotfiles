#!/usr/bin/env zsh

# vim:syntax=zsh
# vim:filetype=zsh

# file location: ${HOME}/.zshenv
# load order: .zshenv, .zprofile, .shellrc, .zshrc, .zshrc.custom, .aliases, .aliases.custom, .zlogin
test -n "${FIRST_INSTALL+1}" && echo "loading .zshenv"

# invoked by all invocations of Zsh, so we should keep it small and merely initialise necessary variables.

# https://blog.patshead.com/2011/04/improve-your-oh-my-zsh-startup-time-maybe.html
skip_global_compinit=1

# http://disq.us/p/f55b78
# setopt noglobalrcs

export ARCH="$(uname -m)"
if [[ "${ARCH}" =~ "arm" ]]; then
  export HOMEBREW_PREFIX="/opt/homebrew"
else
  export HOMEBREW_PREFIX="/usr/local"
fi

# https://github.com/sorin-ionescu/prezto/blob/master/runcoms/zshenv
# Ensure that a non-login, non-interactive shell has a defined environment.
[[ ( "${SHLVL}" -eq 1 && ! -o LOGIN ) && -s "${ZDOTDIR:-${HOME}}/.zprofile" ]] && source "${ZDOTDIR:-${HOME}}/.zprofile"
