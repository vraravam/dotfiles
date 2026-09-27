#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'fileutils'
require 'tempfile'

require_relative 'command_utils'
require_relative 'core'
require_relative 'env_vars'
require_relative 'logging'

# Installs Homebrew itself (not the Brewfile) as a step of the machine setup.
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

  # Curl flags that make bootstrap downloads resilient. --retry-all-errors is deliberately
  # absent: it makes the terminal app close.
  RETRY_OPTS = %w[--retry 5 --retry-delay 10 --retry-max-time 120 --max-time 150 --connect-timeout 30 --retry-connrefused].freeze

  # Headers that bypass GitHub's CDN and intermediate proxies.
  CACHE_BUST_OPTS = ['-H', 'Cache-Control: no-cache, no-store, must-revalidate', '-H', 'Pragma: no-cache', '-H', 'Expires: 0'].freeze

  # Public API method.
  #
  # @return [Boolean] true when Homebrew is installed (already, or now); false when it could
  #   not be installed -- the reason is recorded as an error and the caller should stop, since
  #   every later step depends on Homebrew.
  def run
    ok = false
    Logging.run_script('homebrew_install', 'Installing Homebrew') do
      ok = _install(EnvVars::HOMEBREW_PREFIX)
    end
    ok
  end

  # Curl arguments for a bootstrap download: the retry flags when CURL_RETRY_OPTS is set or
  # ~/.curlrc (which carries equivalent defaults) is not linked yet, and the cache-busting
  # headers when CACHE_BUST_HEADERS is set.
  #
  # @return [Array<String>]
  def curl_opts
    opts = []
    opts.concat(CACHE_BUST_OPTS) if EnvVars.cache_bust_headers?
    opts.concat(RETRY_OPTS) if EnvVars.curl_retry_opts? || !EnvVars::HOME.join('.curlrc').file?
    opts
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

    FileUtils.chmod('u+w', prefix.to_s)
    true
  end

  # @return [Boolean]
  def _download_and_run_installer
    script = Tempfile.new(['brew-install', '.sh'])
    script.close
    begin
      # The timestamp query parameter is part of the cache-busting.
      url = "#{INSTALL_URL}?#{Time.now.to_i}"
      unless CommandUtils.run_interactive('curl', *curl_opts, '-fsSL', url, '-o', script.path)
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
