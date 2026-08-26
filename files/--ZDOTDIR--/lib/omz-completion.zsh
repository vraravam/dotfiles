#!/usr/bin/env zsh
# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# Minimal completion configuration
#
# This file replaces ohmyzsh/lib/completion.zsh with essential settings only.
#
# Original: https://github.com/ohmyzsh/ohmyzsh/blob/master/lib/completion.zsh
# Original: 78 lines → Trimmed to: 40 lines
#
# Kept functionality:
# - zmodload zsh/complist (menu selection module)
# - WORDCHARS='' (word boundary for completion)
# - setopts: auto_menu, complete_in_word, always_to_end
# - unsetopt: menu_complete, flowcontrol
# - Menu selection keybinding (Ctrl+O to accept-and-infer-next)
# - zstyle configs: menu select, case insensitive matching, special dirs
# - Completion colors for kill command process lists
# - Directory completion tag ordering (local dirs first)
# - Completion caching (${XDG_CACHE_HOME}/zcompletion)
#
# Removed functionality:
# - Solaris-specific workarounds (if uname = SunOS)
# - Overly defensive user filtering for kill completion
# - Redundant completion cache path guards
#
# Estimated savings: 0.5ms (included in 0.53ms total antidote-setup reduction)
#
# To restore removed functionality, refer to the original OMZ file linked above.
#
# file location: ${ZDOTDIR}/lib/omz-completion.zsh
################################################################################

# Load completion list module
zmodload -i zsh/complist

# Word boundaries for completion
WORDCHARS=''

# Completion behavior
unsetopt menu_complete   # do not autoselect the first completion entry
unsetopt flowcontrol     # disable flow control (Ctrl+S/Ctrl+Q)
setopt auto_menu         # show completion menu on successive tab press
setopt complete_in_word  # complete from both ends of a word
setopt always_to_end     # move cursor to the end of a completed word

# Menu selection keybinding
bindkey -M menuselect '^o' accept-and-infer-next-history

# Enable menu selection
zstyle ':completion:*:*:*:*:*' menu select

# Case insensitive completion
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|=*' 'l:|=* r:|=*'

# Complete . and .. special directories
zstyle ':completion:*' special-dirs true

# Completion colors
zstyle ':completion:*' list-colors ''
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'

# Process list for kill completion
zstyle ':completion:*:*:*:*:processes' command "ps -u $USERNAME -o pid,user,comm -w -w"

# Directory completion priority
zstyle ':completion:*:cd:*' tag-order local-directories directory-stack path-directories

# Use caching for completion
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME}/zcompletion"
