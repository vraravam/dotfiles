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
# load order: .zshenv [.shellrc], .zshrc [.shellrc, .aliases [.shellrc]], .zlogin
################################################################################

# execute 'FIRST_INSTALL=true zsh' to debug the load order of the custom zsh configuration files
[[ -n "${FIRST_INSTALL+1}" ]] && echo "loading ${0}"

# Load the .shellrc here - just to define some env vars that we need before zsh lifecycle kicks in
source "${HOME}/.shellrc"

# https://blog.patshead.com/2011/04/improve-your-oh-my-zsh-startup-time-maybe.html
skip_global_compinit=1

# http://disq.us/p/f55b78
# setopt no_global_rcs
