#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'  # System Ruby on a vanilla macOS is 2.6; Pathname must be required explicitly because autoloading is unreliable at that version.

# Centralized environment variable access for dotfiles scripts.
# All constants are expanded Pathname objects that mirror the shell export
# statements in .shellrc and provide sensible fallbacks for use during
# FIRST_INSTALL before .shellrc is sourced.
#
# All constants are Pathname objects for consistency. Convert to string with .to_s
# when passing to system commands or when building non-path strings.
#
# Usage:
#   require 'env_vars'
#   puts EnvVars::HOME                              # Pathname object
#   puts EnvVars::HOME.to_s                         # String path
#   EnvVars::DOTFILES_DIR.join('scripts', 'foo.rb') # Pathname manipulation
module EnvVars
  # User's home directory.
  # Mirrors: export HOME (always set by the shell)
  HOME = Pathname.new(ENV.fetch('HOME', '')).expand_path.freeze

  # Dotfiles repository directory.
  # Mirrors: export DOTFILES_DIR="${XDG_CONFIG_HOME}/dotfiles"
  DOTFILES_DIR = Pathname.new(
    ENV.fetch('DOTFILES_DIR', HOME.join('.config', 'dotfiles'))
  ).expand_path.freeze

  # Personal bin directory (non-public scripts).
  # Mirrors: export PERSONAL_BIN_DIR="${HOME}/personal/dev/bin"
  PERSONAL_BIN_DIR = Pathname.new(
    ENV.fetch('PERSONAL_BIN_DIR', HOME.join('personal', 'dev', 'bin'))
  ).expand_path.freeze

  # Personal configs directory (sensitive config files).
  # Mirrors: export PERSONAL_CONFIGS_DIR="${HOME}/personal/dev/configs"
  PERSONAL_CONFIGS_DIR = Pathname.new(
    ENV.fetch('PERSONAL_CONFIGS_DIR', HOME.join('personal', 'dev', 'configs'))
  ).expand_path.freeze

  # Personal profiles directory (browser profiles).
  # Mirrors: export PERSONAL_PROFILES_DIR="${HOME}/personal/${USER}/browser-profiles"
  PERSONAL_PROFILES_DIR = Pathname.new(
    ENV.fetch('PERSONAL_PROFILES_DIR', HOME.join('personal', ENV.fetch('USER', ENV.fetch('USERNAME', '')), 'browser-profiles'))
  ).expand_path.freeze

  # Homebrew prefix directory.
  # Mirrors: export HOMEBREW_PREFIX (set by brew shellenv)
  HOMEBREW_PREFIX = Pathname.new(ENV.fetch('HOMEBREW_PREFIX', '/opt/homebrew')).expand_path.freeze

  # Homebrew repository directory.
  # Mirrors: export HOMEBREW_REPOSITORY (set by brew shellenv)
  HOMEBREW_REPOSITORY = Pathname.new(ENV.fetch('HOMEBREW_REPOSITORY', HOMEBREW_PREFIX)).expand_path.freeze
end
