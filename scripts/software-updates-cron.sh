#!/usr/bin/env zsh

type load_zsh_configs &> /dev/null 2>&1 || FIRST_INSTALL=true source "${HOME}/.shellrc"

load_zsh_configs

if command_exists mise; then
  echo "---- Updating all mise plugins"
  mise plugins update
  mise upgrade
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
  echo "---- Update VSCodium extensions"
  code --update-extensions
fi

# TODO: Need to load an omz shell (which cannot be done in cron), and only then can upgrade
# echo "---- Updating omz"
# omz update
