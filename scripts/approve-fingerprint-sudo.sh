#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# To be able to use the mac touchbar for authorizing the 'sudo' command in terminal
# This will persist through software updates unlike changes directly made to '/etc/pam.d/sudo'
# Copied from: https://apple.stackexchange.com/a/466029
# TODO: Need to ensure that TouchId hardware is present before running this script

type is_file &> /dev/null 2>&1 || source "${HOME}/.shellrc"

if ! is_file /etc/pam.d/sudo_local; then
  sudo sh -c 'sed "s/^#auth/auth/" /etc/pam.d/sudo_local.template > /etc/pam.d/sudo_local'
  success "Created new file: /etc/pam.d/sudo_local"
else
  warn "'/etc/pam.d/sudo_local' already present - not creating again"
fi
