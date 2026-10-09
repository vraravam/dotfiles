#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/brew-update-cleanup.rb
#
# Updates Homebrew, syncs installed packages with the Brewfile, upgrades everything
# outdated and cleans up. Aliased as 'bupc' in ${ZDOTDIR}/.aliases for quick typing.
#
# Cleanup runs both before the Brewfile sync (so packages dropped from the Brewfile are
# not needlessly refreshed) and after it (to prune whatever the sync left behind).
# Antidote updates and tap trusting are handled by Brewfile postinstall hooks.
#
# Usage:
#   Standalone: brew-update-cleanup.rb
#   Module:     BrewUpdateCleanup.run

require_relative 'utilities/brew'
require_relative 'utilities/logging'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module BrewUpdateCleanup
  extend self

  # Public API method.
  #
  # @return [Boolean] true if no step recorded a warning.
  def run
    Logging.record_warning("'#{'brew update'.cyan}' failed") unless Brew.update
    Brew.cleanup
    Logging.record_warning("Failed to sync installed packages with the '#{'Brewfile'.cyan}'") unless Brew.sync_bundle
    Brew.cleanup
    Logging.record_warning("'#{'brew upgrade'.cyan}' failed") unless Brew.upgrade

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
    opts.separator 'Updates Homebrew, syncs with the Brewfile, upgrades everything outdated and cleans up.'
  end

  Logging.run_script do
    exit(BrewUpdateCleanup.run ? 0 : 1)
  end
end
