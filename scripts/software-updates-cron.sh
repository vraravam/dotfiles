#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

type load_zsh_configs &> /dev/null 2>&1 || FIRST_INSTALL=true source "${HOME}/.shellrc"
load_zsh_configs

if command_exists mise; then
  echo "---- Updating mise"
  mise plugins update
  mise upgrade --bump
  mise prune -y
fi

if command_exists tldr; then
  echo "---- Updating tldr"
  tldr --update
fi

if command_exists git; then
  echo "---- Updating git-ignore"
  # 'ignore-io' updates the data from http://gitignore.io so that we can generate the '.gitignore' file contents from the cmd-line
  git ignore-io --update-list
fi

if command_exists code; then
  echo "---- Updating VSCodium extensions"
  code --update-extensions
fi

if command_exists omz; then
  echo "---- Updating omz"
  omz update
fi

echo "---- Updating brews"
bupc
