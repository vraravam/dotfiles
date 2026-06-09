#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'  # System Ruby on a vanilla macOS is 2.6; Pathname must be required explicitly because autoloading is unreliable at that version.

# Centralized environment variable access for dotfiles scripts.
#
# Path constants are expanded Pathname objects.
# Non-path constants are frozen strings or nil.
# Runtime flags are methods (evaluated dynamically on each access).
#
# All values mirror shell export statements in .shellrc and provide sensible
# fallbacks for use during FIRST_INSTALL before .shellrc is sourced.
#
# Usage:
#   require 'env_vars'
#
#   # Path constants (Pathname objects)
#   puts EnvVars::HOME                              # Pathname object
#   puts EnvVars::HOME.to_s                         # String path
#   EnvVars::DOTFILES_DIR.join('scripts', 'foo.rb') # Pathname manipulation
#
#   # Non-path constants (String or nil)
#   puts EnvVars::USER                              # String (always set)
#   puts EnvVars::KEYBASE_USERNAME                  # String or nil
#
  #   # Runtime flag methods (evaluated dynamically)
  #   if EnvVars.debug?                               # Boolean
  #     folder = EnvVars.folder || Dir.pwd            # String (expanded path) or nil
  #     filter = EnvVars.filter                       # String (stripped) or nil
  #   end
module EnvVars
  # Current user's login name.
  # Mirrors: $USER (always set by the shell)
  USER = ENV.fetch('USER', ENV.fetch('USERNAME', '')).freeze

  # Current user's default shell.
  # Mirrors: $SHELL (always set by the shell)
  SHELL = ENV.fetch('SHELL', '/bin/zsh').freeze

  # ---------------------------------------------------------------------------
  # Path variables (Pathname objects)
  # ---------------------------------------------------------------------------

  # User's home directory.
  # Mirrors: export HOME (always set by the shell)
  HOME = Pathname.new(ENV.fetch('HOME', '~')).expand_path.freeze

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
    ENV.fetch('PERSONAL_PROFILES_DIR', HOME.join('personal', USER, 'browser-profiles'))
  ).expand_path.freeze

  # Projects base directory (where all git repos live).
  # Mirrors: export PROJECTS_BASE_DIR="${HOME}/dev"
  PROJECTS_BASE_DIR = Pathname.new(
    ENV.fetch('PROJECTS_BASE_DIR', HOME.join('dev'))
  ).expand_path.freeze

  # XDG base directory specification paths.
  # Mirrors: XDG_* exports in .shellrc
  XDG_CACHE_HOME = Pathname.new(
    ENV.fetch('XDG_CACHE_HOME', HOME.join('.cache'))
  ).expand_path.freeze

  XDG_CONFIG_HOME = Pathname.new(
    ENV.fetch('XDG_CONFIG_HOME', HOME.join('.config'))
  ).expand_path.freeze

  XDG_DATA_HOME = Pathname.new(
    ENV.fetch('XDG_DATA_HOME', HOME.join('.local', 'share'))
  ).expand_path.freeze

  XDG_STATE_HOME = Pathname.new(
    ENV.fetch('XDG_STATE_HOME', HOME.join('.local', 'state'))
  ).expand_path.freeze

  # Homebrew paths.
  # Mirrors: HOMEBREW_* exports (set by brew shellenv)
  HOMEBREW_PREFIX = Pathname.new(ENV.fetch('HOMEBREW_PREFIX', '/opt/homebrew')).expand_path.freeze
  HOMEBREW_REPOSITORY = Pathname.new(ENV.fetch('HOMEBREW_REPOSITORY', HOMEBREW_PREFIX)).expand_path.freeze

  # Antidote plugin manager paths.
  # Mirrors: ANTIDOTE_* exports in .shellrc (platform-specific and brew-dependent)
  # Note: On macOS ANTIDOTE_HOME defaults to ~/Library/Caches/antidote, on Linux to $XDG_CACHE_HOME/antidote
  ANTIDOTE_HOME = Pathname.new(ENV.fetch('ANTIDOTE_HOME', HOME.join('Library', 'Caches', 'antidote'))).expand_path.freeze
  ANTIDOTE_ZSH = Pathname.new(ENV.fetch('ANTIDOTE_ZSH', HOMEBREW_PREFIX.join('opt', 'antidote', 'share', 'antidote', 'antidote.zsh'))).expand_path.freeze
  ANTIDOTE_PLUGIN_ZSH = Pathname.new(ENV.fetch('ANTIDOTE_PLUGIN_ZSH', HOME.join('.zsh_plugins.zsh'))).expand_path.freeze
  ANTIDOTE_PLUGIN_TXT = Pathname.new(ENV.fetch('ANTIDOTE_PLUGIN_TXT', HOME.join('.zsh_plugins.txt'))).expand_path.freeze

  # ---------------------------------------------------------------------------
  # Non-path variables (String objects)
  # ---------------------------------------------------------------------------

  # GitHub username for dotfiles repository.
  # Mirrors: export GH_USERNAME (set in .shellrc or manually)
  GH_USERNAME = ENV.fetch('GH_USERNAME', '').freeze

  # Upstream GitHub username (for forks).
  # Mirrors: export UPSTREAM_GH_USERNAME (set in .shellrc or manually)
  UPSTREAM_GH_USERNAME = ENV.fetch('UPSTREAM_GH_USERNAME', 'vraravam').freeze

  # Dotfiles repository branch name.
  # Mirrors: export DOTFILES_BRANCH (default: master)
  DOTFILES_BRANCH = ENV.fetch('DOTFILES_BRANCH', 'master').freeze

  # Keybase username.
  # Mirrors: export KEYBASE_USERNAME (set in .shellrc or manually)
  # Returns nil when not set or empty (if user does not want Keybase functionality), otherwise returns stripped string.
  KEYBASE_USERNAME = ENV.fetch('KEYBASE_USERNAME', nil)&.then { |s| s.strip.empty? ? nil : s.strip }

  # Keybase repository names for encrypted backups.
  # Mirrors: export KEYBASE_*_REPO_NAME (set in .shellrc or manually)
  # Returns nil when not set or empty (if user does not want Keybase functionality), otherwise returns stripped string.
  KEYBASE_HOME_REPO_NAME = ENV.fetch('KEYBASE_HOME_REPO_NAME', nil)&.then { |s| s.strip.empty? ? nil : s.strip }
  KEYBASE_PROFILES_REPO_NAME = ENV.fetch('KEYBASE_PROFILES_REPO_NAME', nil)&.then { |s| s.strip.empty? ? nil : s.strip }

  # ---------------------------------------------------------------------------
  # Runtime flags and temporary operation variables (evaluated dynamically)
  # These are implemented as class methods (not constants) because they can
  # change between invocations or during script execution.
  # ---------------------------------------------------------------------------

  # Filter pattern for repo operations (run-all.rb, resurrect-repositories.rb).
  # Mirrors: export FILTER (set temporarily for filtering operations)
  # Returns nil when not set or empty (after stripping whitespace), otherwise returns stripped string.
  def self.filter
    ENV.fetch('FILTER', nil)&.then { |s| s.strip.empty? ? nil : s.strip }
  end

  # Reference folder for repo verification (resurrect-repositories.rb).
  # Mirrors: export REF_FOLDER (set temporarily for verification operations)
  # Returns nil when not set or empty (after stripping whitespace), otherwise returns expanded absolute path.
  def self.ref_folder
    ENV.fetch('REF_FOLDER', nil)&.then { |s| s.strip.empty? ? nil : File.expand_path(s.strip) }
  end

  # Base folder for repo operations (run-all.rb).
  # Mirrors: export FOLDER (set temporarily for run-all operations, defaults to current directory)
  # Returns nil when not set or empty (after stripping whitespace), otherwise returns expanded absolute path.
  def self.folder
    ENV.fetch('FOLDER', nil)&.then { |s| s.strip.empty? ? nil : File.expand_path(s.strip) }
  end

  # Search depth limits for repo operations (run-all.rb).
  # Mirrors: export MINDEPTH / MAXDEPTH (set temporarily for run-all operations)
  def self.mindepth
    ENV.fetch('MINDEPTH', '1').to_i
  end

  def self.maxdepth
    ENV.fetch('MAXDEPTH', '4').to_i
  end

  # First install mode (vanilla OS, no dotfiles yet).
  # Mirrors: export FIRST_INSTALL=1 (set in fresh-install bootstrap)
  def self.first_install?
    !ENV.fetch('FIRST_INSTALL', '').empty?
  end

  # Debug mode (verbose logging).
  # Mirrors: export DEBUG=1 (set manually for debugging)
  def self.debug?
    !ENV.fetch('DEBUG', '').empty?
  end
end
