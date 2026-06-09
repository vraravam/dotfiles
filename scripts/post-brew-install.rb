#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/post-brew-install.rb
#
# Runs post-bundle cleanup and plugin setup that cannot live in the Brewfile
# itself because they require knowledge of the full environment.
#
# - Removes the stale Homebrew zsh completion shim for git (required so that
#   completions from other plugins, e.g. git-extras, work correctly).
# - Trusts the taps we use.
# - Updates antidote plugins and regenerates the static bundle file.
#
# Usage: post-brew-install.rb

$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'antidote'
require 'env_vars'
require 'fileutils'
require 'logging'
require 'path_utils'

include Logging

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

increment_script_depth
start_time = print_script_start

stale_shim = EnvVars::HOMEBREW_REPOSITORY.join('share', 'zsh', 'site-functions', '_git')
if stale_shim.exist?
  FileUtils.rm_rf(stale_shim)
  debug "Removed stale git completion shim: '#{stale_shim.to_s.cyan}'"
end

section_header2 'Trusting taps from the Brewfile'
# Trust the taps that we use and know can be trusted.
if PathUtils.command_exists?('brew')
  # TODO: can this be done within the Brewfile DSL itself? or we can programmatically get the list of taps and trust them here?
  system('brew', 'trust', 'jundot/omlx', 'xykong/tap')
end

section_header2 'Updating antidote plugins and regenerating bundle'
Antidote.update_and_regenerate_bundle

print_script_summary(start_time)
