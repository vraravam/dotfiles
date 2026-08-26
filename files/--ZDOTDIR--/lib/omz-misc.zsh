#!/usr/bin/env zsh
# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# Minimal misc library - replaces ohmyzsh/lib/misc.zsh
#
# Original: https://github.com/ohmyzsh/ohmyzsh/blob/master/lib/misc.zsh
# Original: 38 lines → Trimmed to: 15 lines
#
# Kept functionality:
# - setopt multios - enable redirect to multiple streams (echo >file1 >file2)
# - setopt long_list_jobs - show long list format job notifications
# - setopt interactivecomments - recognize comments in interactive shells
# - PAGER/LESS configuration - set pager to 'less' with raw color codes (-R)
# - Super user alias - '_' expands to 'sudo ' for quick privilege escalation
#
# Removed functionality:
# - url-quote-magic ZLE hook - automatically quotes URLs as you type
#   (not used in this configuration, adds complexity to ZLE)
# - SSH agent forwarding check - detection of SSH_AUTH_SOCK
#   (not needed, handled by ssh-agent separately)
#
# To restore removed functionality, refer to the original OMZ file linked above.
#
# file location: ${ZDOTDIR}/lib/omz-misc.zsh
################################################################################

# Essential zsh options
setopt multios              # enable redirect to multiple streams: echo >file1 >file2
setopt long_list_jobs       # show long list format job notifications
setopt interactivecomments  # recognize comments in interactive shells

# Pager configuration
if (( ${+commands[less]} )); then
  export PAGER='less'
  export LESS='-R'
fi

# Super user alias
alias _='sudo '
