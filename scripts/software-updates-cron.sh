#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

type load_zsh_configs &> /dev/null 2>&1 || FIRST_INSTALL=true source "${HOME}/.shellrc"
load_zsh_configs

if command_exists mise; then
  section_header "Updating mise"
  mise plugins update
  mise upgrade --bump
  mise prune -y
else
  debug "skipping updating mise"
fi

if command_exists tldr; then
  section_header "Updating tldr"
  tldr --update
else
  debug "skipping updating tldr"
fi

if command_exists git; then
  section_header "Updating git-ignore"
  # 'ignore-io' updates the data from http://gitignore.io so that we can generate the '.gitignore' file contents from the cmd-line
  git ignore-io --update-list
else
  debug "skipping updating git-ignore"
fi

if command_exists code; then
  section_header "Updating VSCodium extensions"
  code --update-extensions
else
  debug "skipping updating code extensions"
fi

if command_exists omz; then
  section_header "Updating omz"
  omz update
else
  debug "skipping updating omz"
fi

echo "---- Updating brews"
bupc
