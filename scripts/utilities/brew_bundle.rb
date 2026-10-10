#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

require_relative 'brew'
require_relative 'core'
require_relative 'env_vars'
require_relative 'keybase'
require_relative 'logging'

# Installs everything in the Brewfile (found through HOMEBREW_BUNDLE_FILE) as part of the
# machine setup. fresh-install-of-osx.sh calls it through call-utility.rb once the dotfiles
# repository is cloned and install-dotfiles has linked ~/Brewfile; Ruby callers can use it
# directly. The individual brew commands live in Brew -- this module decides which ones to
# run, in which order, and reports on them.
#
# On a vanilla macOS (+first_install+) only the base section of the Brewfile -- everything
# above its '# FIRST_INSTALL:' comment line -- is installed synchronously so the rest of the
# setup can proceed, and the whole Brewfile is then installed in a background job. On a
# pre-configured machine the whole Brewfile is installed synchronously (a no-op when
# 'brew bundle check' already passes).
module BrewBundle
  extend self

  # Output of the background full install on a first install.
  FULL_INSTALL_LOG = EnvVars::DOWNLOADS.join('brew-bundle-full-install.log').freeze

  # Public API method.
  #
  # @param first_install [Boolean] True on a vanilla macOS: base section first, the rest in the
  #   background.
  # Uses ${HOMEBREW_PREFIX}/bin/brew rather than 'brew' from PATH, since Homebrew may not be on
  # PATH yet during the bootstrap.
  #
  # @return [Boolean] false when Homebrew or the Brewfile could not be used, or when
  #   'brew bundle' reported errors; the caller decides how to record that.
  def run(first_install: false)
    ok = false
    Logging.run_script('brew_bundle', 'Installing the Brewfile with Homebrew') do
      ok = _install(first_install: first_install, brew_bin: EnvVars::HOMEBREW_PREFIX.join('bin', 'brew'))
    end
    ok
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  # @param first_install [Boolean]
  # @param brew_bin [Pathname]
  # @return [Boolean]
  def _install(first_install:, brew_bin:)
    unless brew_bin.executable?
      Logging.warn "Brew binary '#{brew_bin.cyan}' is not executable -- skipping the bundle install"
      return false
    end

    base_content = first_install ? _first_install_content : nil
    return false if first_install && base_content.nil?

    bundled = Brew.sync_bundle(brew_bin: brew_bin.to_s, brewfile_content: base_content)
    Logging.success 'Successfully installed cmd-line and gui apps using homebrew' if bundled

    Keybase.link_cli_into(brew_bin.dirname)

    _start_full_install(brew_bin) if first_install

    bundled
  end

  # The text to install first on a vanilla macOS: the base section of the Brewfile. A Brewfile
  # without the sentinel is installed whole (with a warning), which is also what happened before
  # the sentinel existed.
  #
  # @return [String, nil] nil when the Brewfile does not exist.
  def _first_install_content
    brewfile = EnvVars::HOMEBREW_BUNDLE_FILE
    unless brewfile.file?
      Logging.warn "Brewfile not found at '#{brewfile.cyan}' -- skipping the bundle install"
      return nil
    end

    Brew.base_brewfile_content(brewfile) || begin
      Logging.warn "No '#{Brew::FIRST_INSTALL_SENTINEL}' sentinel found in '#{brewfile.cyan}' -- the whole Brewfile is treated as the base section"
      Core.read_lines_utf8(brewfile).join
    end
  end

  # Starts the detached install of everything in the Brewfile.
  #
  # @param brew_bin [Pathname]
  # @return [void]
  def _start_full_install(brew_bin)
    if Brew.bundle_in_background(brew_bin: brew_bin.to_s, log: FULL_INSTALL_LOG)
      Logging.info "Full Brewfile install running in background (log: '#{FULL_INSTALL_LOG.cyan}')"
    else
      Logging.warn "Could not start the background Brewfile install -- run 'brew bundle' once the setup is done"
    end
  end

  private_class_method :_install, :_first_install_content, :_start_full_install
end
