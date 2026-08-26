#!/usr/bin/env zsh
# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# Minimal functions library - replaces ohmyzsh/lib/functions.zsh
#
# Original: https://github.com/ohmyzsh/ohmyzsh/blob/master/lib/functions.zsh
# Original: 284 lines → Trimmed to: 55 lines (4 functions kept)
#
# Kept functions:
# - env_default() - set environment variable to default if not already set
#   Used by: OMZ plugins that need default env var values
# - mkcd()/takedir() - create directory and cd into it
#   Used by: Interactive usage, convenience function
# - open_command() - open file with default application (macOS)
#   Used by: Various OMZ plugins (extract, copyfile, etc.)
# - omz_urlencode() - URL-encode strings (simplified implementation)
#   Used by: ohmyzsh/lib/termsupport.zsh (deferred) for terminal title/CWD tracking
#
# Removed functions (20+ unused utilities):
# - omz_urldecode, display_plugin_list, omz_diagnostic_dump
# - All git-related helpers (moved to git plugin which was removed)
# - take/takeurl/takegit variants (download/clone and cd)
# - All clipboard/encoding helpers not used by active plugins
#
# To restore removed functions, refer to the original OMZ file linked above.
#
# file location: ${ZDOTDIR}/lib/omz-functions.zsh
################################################################################

# env_default: set environment variable to a default value if not already set
# Usage: env_default 'PAGER' 'less'
# Used by: OMZ plugins and custom configs
env_default() {
  [[ ${parameters[$1]} = *-export* ]] && return 0
  export "$1=$2" && return 3
}

# mkcd/takedir: create directory and cd into it
# Usage: mkcd new-directory
mkcd() {
  [[ -n "$1" ]] && mkdir -p "$1" && cd "$1"
}
alias takedir=mkcd

# open_command: open file with default application (macOS)
# Usage: open_command file.txt
# Used by: Various OMZ plugins
open_command() {
  local open_cmd='open'
  ${=open_cmd} "$@" &>/dev/null
}

# omz_urlencode: URL-encode a string
# Usage: omz_urlencode [-r] [-m] [-P] <string>
# Flags: -r (keep reserved chars), -m (keep mark chars), -P (spaces as %20)
# Used by: termsupport.zsh (deferred, for terminal title/CWD tracking)
# This is a simplified version - full OMZ implementation is 80+ lines with
# UTF-8 encoding conversion and Termux workarounds
omz_urlencode() {
  emulate -L zsh
  local -a opts
  zparseopts -D -E -a opts r m P

  local str="$@"
  local spaces_as_plus
  [[ -z $opts[(r)-P] ]] && spaces_as_plus=1

  local url_str="" i byte
  local dont_escape="[A-Za-z0-9_.!~*'()-]"

  for (( i = 1; i <= ${#str}; ++i )); do
    byte="$str[i]"
    if [[ "$byte" =~ "$dont_escape" ]]; then
      url_str+="$byte"
    elif [[ "$byte" == " " && -n $spaces_as_plus ]]; then
      url_str+="+"
    else
      printf -v hex '%%%02X' "'$byte"
      url_str+="$hex"
    fi
  done
  echo -E "$url_str"
}
