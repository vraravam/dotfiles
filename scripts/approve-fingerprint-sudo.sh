#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# To be able to use the mac touchbar for authorizing the 'sudo' command in terminal
# This will persist through software updates unlike changes directly made to '/etc/pam.d/sudo'
# Copied from: https://apple.stackexchange.com/a/466029

# Exit immediately if a command exits with a non-zero status.
set -e

# Check for one representative function to see if sourcing is needed
if ! type is_file &> /dev/null 2>&1 || ! type warn &> /dev/null 2>&1 ; then
  source "${HOME}/.shellrc"
fi

if ! ioreg -c AppleBiometricSensor | \grep -q AppleBiometricSensor; then
  warn 'Touch ID hardware is not detected. Skipping configuration.'
  exit 0 # Exit successfully as no action is needed
fi

local template_file="/etc/pam.d/sudo_local.template"
! is_file "${template_file}" && error "Template file '${template_file}' not found!"

local target_file="/etc/pam.d/sudo_local"
if ! is_file "${target_file}"; then
  # Using sh -c 'sed...' is fine here
  sudo sh -c "sed 's/^#auth/auth/' ${template_file} > ${target_file}" || error "Failed to create ${target_file}"
  success "Created new file: '$(yellow "${target_file}")'"
else
  warn "'$(yellow "${target_file}")' is already present - not creating again"
fi
unset target_file
unset template_file
