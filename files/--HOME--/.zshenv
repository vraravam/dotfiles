#!/usr/bin/env zsh
# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8
# file location: ${HOME}/.zshenv
#
# .zshenv is sourced by ALL zsh invocations (interactive and non-interactive).
# Keep this file minimal - only set ZDOTDIR here.
# All other environment setup happens in .shellrc (sourced from .zshrc).

# Set ZDOTDIR to point to XDG_CONFIG_HOME/zsh (reduces clutter in ${HOME}).
# This tells zsh where to find .zshrc, .zlogin, etc.
# Must be set here because zsh reads .zshenv from ${HOME} first, then looks for
# other startup files in ${ZDOTDIR}.
export ZDOTDIR="${ZDOTDIR:-"${XDG_CONFIG_HOME:-${HOME}/.config}/zsh"}"
