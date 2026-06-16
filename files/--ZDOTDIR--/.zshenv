#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# This file is sourced on all invocations of the shell. It is the 1st file zsh
# reads; it's read for every shell, unless started with -f (setopt no_rcs), in
# which case all initialization files including .zshenv are skipped.
#
# This file should contain commands to set the command search path, plus other
# important environment variables. This file should not contain commands that
# produce output or assume the shell is attached to a tty.
#
# file location: ${ZDOTDIR}/.zshenv
# load order: .zshenv [.shellrc], .zshrc [.shellrc, .aliases [.shellrc]], .zlogin
################################################################################

# execute 'DEBUG=true zsh' to debug the load order of the custom zsh configuration files
if [[ -n "${DEBUG:-}" ]]; then echo "loading ${0}"; fi

# Load the .shellrc here - just to define some env vars that we need before zsh lifecycle kicks in.
# Re-source guard is inside .shellrc itself -- safe to call unconditionally.
source "${HOME}/.shellrc"

# zsh/datetime provides $EPOCHSECONDS and strftime -- used by current_timestamp,
# current_date, current_timestamp_for_filename, format_duration, step_start/end,
# and print_script_start/duration defined in .shellrc.
zmodload zsh/datetime

skip_global_compinit=1

# http://disq.us/p/f55b78
# setopt no_global_rcs
