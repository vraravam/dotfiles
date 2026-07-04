# SQLite3 diff driver configuration
# This file is conditionally included via ~/.gitconfig-sqlite3-enabled.inc
# (symlink created by install-dotfiles.rb when sqlite3 is in PATH).
#
# Usage in .gitattributes:
#   *.sqlite   diff=sqlite3
#   *.sqlite3  diff=sqlite3
#   *.db       diff=sqlite3
#
# Note: sqlite3 is included by default on macOS, but may not be installed
# on all Linux distributions or Windows. This conditional include ensures
# git config works correctly on systems without sqlite3.

[diff "sqlite3"]
  binary = true
  textconv = sh -c 'sqlite3 $0 .dump'
  cachetextconv = true
