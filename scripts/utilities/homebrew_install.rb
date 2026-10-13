#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'command_utils'
require_relative 'core'
require_relative 'env_vars'
require_relative 'logging'

# Installs Homebrew itself (not the Brewfile -- see BrewBundle) as a step of the machine setup.
# fresh-install-of-osx.sh calls it through call-utility.rb once the dotfiles repository is
# cloned; Ruby callers can use it directly. A no-op when ${HOMEBREW_PREFIX}/bin/brew exists.
#
# The caller's shell cannot pick up Homebrew's environment from a subprocess, so exporting
# 'brew shellenv' into the running script stays the caller's job.
module HomebrewInstall
  extend self
  include Core  # For nil_or_empty?
  extend Core

  INSTALL_URL = 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'

  # Public API method.
  #
  # @return [Boolean] true when Homebrew is installed (already, or now); false when it could
  #   not be installed -- the reason is recorded as an error and the caller should stop, since
  #   every later step depends on Homebrew.
  def run
    Logging.run_script_result('homebrew_install', 'Installing Homebrew') { _install(EnvVars::HOMEBREW_PREFIX) }
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  # @param prefix [Pathname] ${HOMEBREW_PREFIX}
  # @return [Boolean]
  def _install(prefix)
    if nil_or_empty?(prefix.to_s)
      Logging.record_error "'HOMEBREW_PREFIX' env var is not set; something is wrong. Please correct before retrying!"
      return false
    end

    if prefix.join('bin', 'brew').executable?
      Logging.info "Skipping installation of #{'homebrew'.yellow} -- already installed."
      return true
    end

    return false unless _prepare_prefix(prefix)

    _download_and_run_installer
  end

  # Creates the directories the installer expects and hands the prefix to the current user.
  #
  # @param prefix [Pathname]
  # @return [Boolean]
  def _prepare_prefix(prefix)
    dirs = %w[tmp repository plugins bin].map { |dir| prefix.join(dir).to_s }
    unless CommandUtils.run_interactive('sudo', 'mkdir', '-p', *dirs)
      Logging.record_error "Failed to create the Homebrew directories under '#{prefix.to_s.cyan}'"
      return false
    end

    unless CommandUtils.run_interactive('sudo', 'chown', '-fR', "#{EnvVars::USER}:admin", prefix.to_s)
      Logging.record_error "Failed to take ownership of '#{prefix.to_s.cyan}'"
      return false
    end

    File.chmod(File.stat(prefix.to_s).mode | 0o200, prefix.to_s) # u+w
    true
  end

  # @return [Boolean]
  def _download_and_run_installer
    require 'tempfile' # only needed when Homebrew is actually being installed
    script = Tempfile.new(['brew-install', '.sh'])
    script.close
    begin
      # The timestamp query parameter is part of the cache-busting.
      url = "#{INSTALL_URL}?#{Time.now.to_i}"
      unless CommandUtils.curl_download(url, script.path, bootstrap: true, interactive: true)
        Logging.record_error 'Failed to download Homebrew installation script'
        return false
      end

      unless CommandUtils.run_interactive({ 'NONINTERACTIVE' => '1' }, 'bash', script.path)
        Logging.record_error 'Homebrew installation failed'
        return false
      end

      Logging.success "Successfully installed #{'homebrew'.yellow}"
      true
    ensure
      script.unlink
    end
  end

  private_class_method :_install, :_prepare_prefix, :_download_and_run_installer
end
