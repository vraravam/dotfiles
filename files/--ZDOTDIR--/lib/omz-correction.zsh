#!/usr/bin/env zsh
# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# Minimal correction library - replaces ohmyzsh/lib/correction.zsh
#
# Original: https://github.com/ohmyzsh/ohmyzsh/blob/master/lib/correction.zsh
# Original: 10 lines → Trimmed to: 1 line
#
# Kept functionality:
# - setopt correct_all - enable command autocorrection for typos
#   When enabled, zsh will suggest corrections for mistyped commands:
#   Example: "gti status" → "zsh: correct 'gti' to 'git' [nyae]?"
#
# Removed functionality:
# - Defensive guards checking if correction is already enabled
# - Extensive documentation comments
#
# To disable command correction, add "unsetopt correct_all" to your .zshrc
# after sourcing this file, or comment out the line below.
#
# To restore original structure, refer to the original OMZ file linked above.
#
# file location: ${ZDOTDIR}/lib/omz-correction.zsh
################################################################################

# Command correction - autocorrect typos
setopt correct_all
