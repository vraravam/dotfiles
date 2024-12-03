#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# This file is sourced on all invocations of the shell. It is the 1st file zsh
# reads; it's read for every shell, even if started with -f (setopt NO_RCS),
# all other initialization files are skipped.
#
# This file should contain commands to set the command search path, plus other
# important environment variables. This file should not contain commands that
# produce output or assume the shell is attached to a tty.
#
# Notice: .zshenv is the same, except that it's not read if zsh is started with -f
#
# file location: ${ZDOTDIR}/.zshenv
# load order: .zshenv, .zprofile, .zshrc [.shellrc, .zshrc.custom [.aliases [.shellrc, .aliases.custom]]], .zlogin
################################################################################

# execute 'FIRST_INSTALL=true zsh' to debug the load order of the custom zsh configuration files
test -n "${FIRST_INSTALL+1}" && echo "loading ${0}"

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
export ZDOTDIR="${HOME}"
[[ ( "${SHLVL}" -eq 1 && ! -o LOGIN ) && -s "${ZDOTDIR}/.zprofile" ]] && source "${ZDOTDIR}/.zprofile"
