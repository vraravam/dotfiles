#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# This file is sourced on all invocations of the shell. It is the 1st file zsh
# reads; it's read for every shell, even if started with -f (setopt no_rcs),
# all other initialization files are skipped.
#
# This file should contain commands to set the command search path, plus other
# important environment variables. This file should not contain commands that
# produce output or assume the shell is attached to a tty.
#
# Notice: .zshenv is the same, except that it's not read if zsh is started with -f
#
# file location: ${ZDOTDIR}/.zshenv
# load order: .zshenv [.shellrc], .zshrc [.shellrc, .zshrc.custom [.aliases [.shellrc, .aliases.custom]]], .zlogin
################################################################################

# execute 'FIRST_INSTALL=true zsh' to debug the load order of the custom zsh configuration files
test -n "${FIRST_INSTALL+1}" && echo "loading ${0}"

type load_file_if_exists &> /dev/null 2>&1 || source "${HOME}/.shellrc"

# https://blog.patshead.com/2011/04/improve-your-oh-my-zsh-startup-time-maybe.html
skip_global_compinit=1

# http://disq.us/p/f55b78
# setopt no_global_rcs

export ARCH="$(uname -m)"
if [[ "${ARCH}" =~ "arm" ]]; then
  export HOMEBREW_PREFIX="/opt/homebrew"
else
  export HOMEBREW_PREFIX="/usr/local"
fi
