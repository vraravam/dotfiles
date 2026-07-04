# Plist diff driver configuration (macOS-specific)
# This file is conditionally included via ~/.gitconfig-plist-enabled.inc
# (symlink created by install-dotfiles.rb when plutil is in PATH).
#
# Usage in .gitattributes:
#   *.defaults  diff=plist
#
# Note: plutil is a macOS-only tool (part of CoreFoundation framework).
# On non-macOS systems, this config won't be included and .plist files
# will show as binary diffs.

[diff "plist"]
  textconv = plutil -convert xml1 -o -
  cachetextconv = true
