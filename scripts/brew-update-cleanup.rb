#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/brew-update-cleanup.rb
#
# Upgrades and cleans up everything: nix packages + macOS defaults + Homebrew GUI casks
# (all via the nix-darwin rebuild, the same as the 'nixup' alias), then Homebrew's own
# cache/orphan cleanup (nix-darwin's homebrew module does not cover cached downloads or
# orphaned dependencies). Aliased as 'bupc' in ${ZDOTDIR}/.aliases for quick typing, keeping
# the name for muscle memory even though the mechanism is no longer Homebrew Bundle.
#
# Homebrew metadata is refreshed first: homebrew.onActivation.autoUpdate is false (see
# nix/darwin-configuration.nix), so the rebuild would otherwise upgrade casks against stale
# formula/cask metadata.
#
# Login items: a cask's postinstall (which registers its login item) only runs when the cask is
# installed, so the login item of an app dropped from the nix configuration is removed before the
# rebuild uninstalls it, and the ones the configuration lists that are missing are registered after
# it (SetupLoginItem.unregister_removed and .register_managed; both are quiet when there is nothing
# to do).
#
# Usage:
#   Standalone: brew-update-cleanup.rb
#   Module:     BrewUpdateCleanup.run

require_relative 'utilities/brew'
require_relative 'utilities/logging'
require_relative 'utilities/nix'
require_relative 'utilities/path_utils'
require_relative 'setup-login-item'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module BrewUpdateCleanup
  extend self

  # Public API method.
  #
  # @return [Boolean] true if no step recorded a warning.
  def run
    Logging.record_warning("'#{'brew update'.cyan}' failed") unless Brew.update
    SetupLoginItem.unregister_removed
    # Skipped silently when nix-darwin is not installed (as the 'nixup' alias is only defined
    # when 'darwin-rebuild' exists), so 'bupc' still does the Homebrew parts on such a machine.
    rebuild_failed = PathUtils.command_exists?('darwin-rebuild') && !Nix.rebuild
    Logging.record_warning("'#{'darwin-rebuild switch'.cyan}' failed") if rebuild_failed
    SetupLoginItem.register_managed
    Brew.cleanup

    !Logging.warnings?
  end
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  CliParser.parse('') do |opts|
    opts.separator 'Rebuilds the nix-darwin configuration (nix packages, macOS defaults, Homebrew casks) and cleans up Homebrew.'
  end

  Logging.run_script do
    exit(BrewUpdateCleanup.run ? 0 : 1)
  end
end
