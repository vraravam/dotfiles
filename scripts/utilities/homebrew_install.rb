#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'background_job'
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
#
# fresh-install-of-osx.sh may already have started the installer in the background right after
# the Xcode command-line tools step, and then exports its pid and log as _DOTFILES_BREW_INSTALL_PID
# and _DOTFILES_BREW_INSTALL_LOG. When Homebrew is absent and that pid is alive, this waits for
# it (bounded, showing the log's tail now and then) and verifies that brew exists afterwards; when
# the job is gone, failed or timed out, the normal download-and-install path below runs instead.
# FRESH_INSTALL_NO_EARLY_BREW opts out of waiting. Every step that can block has a bound.
module HomebrewInstall
  extend self
  include Core  # For nil_or_empty?
  extend Core

  INSTALL_URL = 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'

  # Longest the early background installer is waited for, in seconds.
  EARLY_INSTALL_TIMEOUT = 15 * 60

  # Seconds between liveness checks and between progress reports while waiting for it.
  EARLY_INSTALL_POLL = 2
  EARLY_INSTALL_TICK = 30

  # Limits for the installer this module runs itself: in total, and without any output (a hung
  # git clone or download). Generous, because a vanilla macOS on a slow link legitimately takes
  # a long time; the point is that no step is unbounded.
  INSTALLER_TIMEOUT = 30 * 60
  INSTALLER_INACTIVITY = 10 * 60

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

    # Before the brew check: while the background installer runs, bin/brew can already exist
    # (it is linked before the installer's own 'brew update') and must not be used yet.
    early = _join_early_installer
    if prefix.join('bin', 'brew').executable?
      if early
        Logging.success "Successfully installed #{'homebrew'.yellow} (by the background installer)"
      else
        Logging.info "Skipping installation of #{'homebrew'.yellow} -- already installed."
      end
      return true
    end

    _report_early_failure if early
    return false unless _prepare_prefix(prefix)

    _download_and_run_installer
  end

  # Joins the Homebrew installer the shell started in the background, if there is one: waits for
  # it while it is alive, bounded, and stops it when the bound is reached.
  #
  # @return [Boolean] true when there was a background installer to join (whether or not it
  #   succeeded); false when none was started, it was opted out of, or its pid is malformed
  def _join_early_installer
    pid = EnvVars.brew_install_pid
    return false if pid.zero? || EnvVars.set?('FRESH_INSTALL_NO_EARLY_BREW')

    if BackgroundJob.pid_alive?(pid)
      Logging.info "Homebrew is already being installed in the background (pid #{pid.to_s.cyan}) -- waiting for it"
      finished = BackgroundJob.wait_for_pid(pid, timeout: EARLY_INSTALL_TIMEOUT, poll: EARLY_INSTALL_POLL, tick: EARLY_INSTALL_TICK) do |elapsed|
        Logging.info "Still installing Homebrew in the background (#{elapsed}s):"
        BackgroundJob.tail(EnvVars.brew_install_log, lines: 2).each { |line| Logging.info "  #{line}" }
      end
      unless finished
        Logging.record_warning "The background Homebrew installer did not finish within #{EARLY_INSTALL_TIMEOUT / 60} minutes -- stopping it and installing again"
        BackgroundJob.terminate(pid)
      end
    end
    true
  end

  # Says why the background installer's result is not used and shows the end of its log.
  #
  # @return [void]
  def _report_early_failure
    log = EnvVars.brew_install_log
    Logging.record_warning "The background Homebrew installer left no brew behind#{log ? " (log: '#{log.cyan}')" : ''} -- installing it again"
    BackgroundJob.tail(log, lines: 5).each { |line| Logging.info "  #{line}" }
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

      verdict = BackgroundJob.run_guarded({ 'NONINTERACTIVE' => '1' }, 'bash', script.path, timeout: INSTALLER_TIMEOUT, inactivity: INSTALLER_INACTIVITY)
      unless verdict == :ok
        Logging.record_error _installer_failure_message(verdict)
        return false
      end

      Logging.success "Successfully installed #{'homebrew'.yellow}"
      true
    ensure
      script.unlink
    end
  end

  # @param verdict [Symbol] A failing BackgroundJob.run_guarded result
  # @return [String]
  def _installer_failure_message(verdict)
    case verdict
    when :timeout then "Homebrew installation was stopped: it ran longer than #{INSTALLER_TIMEOUT / 60} minutes"
    when :stalled then "Homebrew installation was stopped: no output for #{INSTALLER_INACTIVITY / 60} minutes"
    else 'Homebrew installation failed'
    end
  end

  private_class_method :_install, :_join_early_installer, :_report_early_failure, :_prepare_prefix, :_download_and_run_installer,
                       :_installer_failure_message
end
