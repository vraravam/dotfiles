#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'command_utils'
require_relative 'core'
require_relative 'env_vars'
require_relative 'logging'
require_relative 'nix'
require_relative 'path_utils'
require_relative '../setup-login-item'

# The Nix steps of the machine setup, which replace 'brew bundle': installing the Nix package
# manager and applying this repo's nix-darwin + home-manager configuration (nix packages, macOS
# defaults and, through nix-darwin's homebrew module, the Homebrew GUI casks). Homebrew itself
# must still be installed first (HomebrewInstall) -- nix-darwin does not install it.
# FreshInstallPostClone calls these; Ruby callers can use them directly.
module NixBootstrap
  extend self
  include Core  # For nil_or_empty?
  extend Core

  # The Determinate Systems installer, rather than the plain nixos.org one: it is what
  # nix-darwin's own docs point adopters at, handles the multi-user daemon setup reliably in one
  # non-interactive pass, and ships a clean 'sudo /nix/nix-installer uninstall' for a full revert.
  INSTALL_URL = 'https://install.determinate.systems/nix'

  # Where the daemon-mode installer puts the multi-user profile's bin directory, regardless of
  # whether nix-darwin has been applied yet (its own /run/current-system/sw/bin only exists after
  # the first successful switch).
  PROFILE_BIN = Core::ROOT.join('nix', 'var', 'nix', 'profiles', 'default', 'bin').freeze

  # A stale file written by an older version of this setup's own Touch ID step. nix-darwin refuses
  # to activate ("Unexpected files in /etc") the first time it takes over a file it does not
  # recognize, so it is moved aside once; the '.before-nix-darwin' copy is the "already migrated"
  # marker that keeps this idempotent.
  STALE_SUDO_LOCAL = Core::ROOT.join('etc', 'pam.d', 'sudo_local').freeze

  # Environment kept through sudo: darwin-rebuild no longer elevates itself for the activation
  # phase, so it runs under sudo, and without these the flake's '--impure' evaluation would read
  # root's home instead of the user's ~/.shellrc, 'nix'/'darwin-rebuild' (under PROFILE_BIN) would
  # not be found, and the casks' postinstall hooks would see an empty ${DOTFILES_DIR}.
  SUDO_KEEP_ENV = %w[USER USERNAME HOME PATH DOTFILES_DIR].freeze

  # Public API method. Installs Nix unless it is already there and puts it on this process's PATH.
  #
  # @return [Boolean] true when 'nix' is available afterwards; false, with the reason recorded as
  #   an error, when it could not be installed -- everything after depends on it.
  def install
    Logging.run_script_result('nix_install', 'Installing the Nix package manager') { _install }
  end

  # Public API method. Applies the flake's nix-darwin + home-manager configuration.
  #
  # @return [Boolean] false when the switch failed (recorded as a warning); the setup carries on.
  def apply_configuration
    Logging.run_script_result('nix_darwin_switch', 'Applying the nix-darwin + home-manager configuration') do
      applied = _apply
      # Homebrew only runs a cask's postinstall (which registers its login item) when the switch
      # installs the cask, so casks that were already installed (a re-run, or after 'implode') get
      # their login items here. Its own failures are recorded as warnings and do not change the result.
      SetupLoginItem.register_managed
      applied
    end
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  # @return [Boolean]
  def _install
    if PathUtils.command_exists?('nix')
      Logging.info "Skipping installation of #{'Nix'.yellow} -- already installed."
    else
      return false unless _download_and_run_installer
    end

    PathUtils.append_to_path(PROFILE_BIN)
    return true if PathUtils.command_exists?('nix')

    Logging.record_error "'nix' command not found in PATH after installation"
    false
  end

  # @return [Boolean]
  def _download_and_run_installer
    require 'tempfile' # only needed when Nix is actually being installed (tempfile pulls in rbconfig)
    script = Tempfile.new(['nix-install', '.sh'])
    script.close
    begin
      url = "#{INSTALL_URL}?#{Time.now.to_i}" # the timestamp busts GitHub-style CDN caches
      unless CommandUtils.curl_download(url, script.path, bootstrap: true, interactive: true)
        Logging.record_error 'Failed to download the Nix installation script'
        return false
      end

      unless CommandUtils.run_interactive('sh', script.path, 'install', '--no-confirm')
        Logging.record_error 'Nix installation failed'
        return false
      end

      Logging.success "Successfully installed #{'Nix'.yellow}"
      true
    ensure
      script.unlink
    end
  end

  # @return [Boolean]
  def _apply
    _back_up_stale_sudo_local

    if CommandUtils.run_interactive(*_switch_command)
      Logging.success 'Successfully applied the nix-darwin configuration (nix packages, macOS defaults and Homebrew GUI casks)'
      return true
    end

    Logging.record_warning 'darwin-rebuild switch encountered errors; continuing...'
    false
  end

  # The command that applies the configuration. The first-ever activation on a machine has no
  # darwin-rebuild yet -- it is installed BY applying this configuration -- so 'nix run
  # nix-darwin' bootstraps it through the same 'switch'.
  #
  # @return [Array<String>]
  def _switch_command
    sudo = ['sudo', "--preserve-env=#{SUDO_KEEP_ENV.join(',')}"]
    if PathUtils.command_exists?('darwin-rebuild')
      sudo + ['darwin-rebuild', 'switch', '--flake', Nix.flake, '--impure']
    else
      sudo + ['nix', '--extra-experimental-features', 'nix-command flakes', 'run', 'nix-darwin', '--', 'switch', '--flake', Nix.flake, '--impure']
    end
  end

  # @return [void]
  def _back_up_stale_sudo_local
    backup = Pathname("#{STALE_SUDO_LOCAL}.before-nix-darwin")
    return unless STALE_SUDO_LOCAL.file? && !backup.file?

    Logging.warn "Backing up pre-nix-darwin '#{STALE_SUDO_LOCAL.to_s.cyan}' to '#{backup.to_s.cyan}' (leftover from an older version of this setup) before nix-darwin's first activation..."
    return if CommandUtils.run_interactive('sudo', 'mv', STALE_SUDO_LOCAL.to_s, backup.to_s)

    Logging.record_warning "Could not move '#{STALE_SUDO_LOCAL.to_s.cyan}' aside -- nix-darwin's first activation may refuse to run"
  end

  private_class_method :_install, :_download_and_run_installer, :_apply, :_switch_command, :_back_up_stale_sudo_local
end
