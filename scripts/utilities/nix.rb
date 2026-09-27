#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'command_utils'
require_relative 'env_vars'
require_relative 'path_utils'

# Applies the nix-darwin + home-manager configuration from this repo's flake. Shared by
# the interactive 'bupc' command (scripts/brew-update-cleanup.rb) and the hourly cron job
# (scripts/software-updates-cron.rb), mirroring the 'nixup' alias in ${ZDOTDIR}/.aliases.
#
# Like Brew, a plain subprocess with no TTY or login-shell assumption.
module Nix
  extend self

  # '--impure' is required: the flake reads '.shellrc' directly via 'builtins.readFile' to
  # derive keybaseEnabled/encryptedBackupEnabled -- see nix/flake.nix for why.
  def flake
    "#{EnvVars::DOTFILES_DIR.join('nix')}#default"
  end

  # Keeps nix packages, macOS defaults (nix/darwin-configuration.nix) and the Homebrew GUI
  # casks (via nix-darwin's homebrew module) in sync with the flake.
  #
  # @return [Boolean] true if the switch succeeded
  def rebuild
    CommandUtils.run_interactive('darwin-rebuild', 'switch', '--flake', flake, '--impure')
  end
end
