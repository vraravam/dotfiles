# file location: ${XDG_CONFIG_HOME}/git/config-pandoc.inc
# Pandoc diff driver configuration
# This file is conditionally included via ~/.gitconfig-pandoc-enabled.inc
# (symlink created by install-dotfiles.rb when pandoc is in PATH).
#
# Usage in .gitattributes:
#   *.docx  diff=pandoc
#   *.odt   diff=pandoc

[diff "pandoc"]
  textconv = pandoc --sandbox --to=markdown
  cachetextconv = true
