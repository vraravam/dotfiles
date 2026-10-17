#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

require_relative 'background_job'
require_relative 'brew'
require_relative 'core'
require_relative 'env_vars'
require_relative 'keybase'
require_relative 'logging'
require_relative '../setup-login-item'

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
#
# Afterwards the login items of the installed apps the Brewfile manages are (re)registered
# (SetupLoginItem.register_managed), which is idempotent.
#
# The background job is never joined here: #report_full_install (called by the closing summary)
# says whether it is still running, finished or failed, so the run never claims everything is
# installed while casks are still being installed.
module BrewBundle
  extend self

  # Output of the background full install on a first install.
  FULL_INSTALL_LOG = EnvVars::DOWNLOADS.join('brew-bundle-full-install.log').freeze

  # Extra attempts at a failed 'brew bundle install', and the pause before each.
  INSTALL_RETRIES = 1
  INSTALL_RETRY_DELAY = 5

  # The comment line in the Brewfile that ends the base section: on a vanilla macOS only what is
  # above it is installed first, the rest follows in a background job.
  FIRST_INSTALL_SENTINEL = '# FIRST_INSTALL:'

  # Public API method.
  #
  # Uses ${HOMEBREW_PREFIX}/bin/brew rather than 'brew' from PATH, since Homebrew may not be on
  # PATH yet during the bootstrap.
  #
  # @param first_install [Boolean] True on a vanilla macOS: base section first, the rest in the
  #   background. Defaults to FIRST_INSTALL from the environment, which the install script exports,
  #   so it passes nothing.
  # @return [Boolean] false when Homebrew or the Brewfile could not be used, or when
  #   'brew bundle' reported errors; each of those is already recorded as a warning.
  def run(first_install: EnvVars.first_install?)
    Logging.run_script_result('brew_bundle', 'Installing the Brewfile with Homebrew') do
      installed = _install(first_install: first_install, brew_bin: EnvVars::HOMEBREW_PREFIX.join('bin', 'brew'))
      # 'brew bundle' only runs a cask's postinstall (which registers its login item) when it
      # installs the cask, so casks that were already installed (a re-run, or after 'implode') get
      # their login items here. Done even when the install reported errors, since the casks that
      # are present still need them. Its own failures are recorded as warnings and do not change
      # the result of the install.
      SetupLoginItem.register_managed
      installed
    end
  end

  # The part of the Brewfile above the FIRST_INSTALL_SENTINEL comment line: the bare essentials
  # that a vanilla macOS needs before the rest of the setup can proceed. The sentinel is a
  # *comment*, so the match must not skip comment lines.
  #
  # @param brewfile [Pathname, String] Path to the Brewfile.
  # @return [String, nil] The base section, or nil when the Brewfile has no sentinel line.
  def base_brewfile_content(brewfile)
    base = []
    Core.each_line_utf8(brewfile) do |line|
      return base.join if line.start_with?(FIRST_INSTALL_SENTINEL)

      base << line
    end
    nil
  end

  # Installs the whole Brewfile in a background process, so the optional and heavy packages do
  # not block the rest of the setup. FIRST_INSTALL is emptied in the child so that 'brew bundle'
  # treats the run as a full install; output is appended to +log+. The caller keeps the returned
  # job to report on it later (BackgroundJob.status) -- it is never joined here.
  #
  # @param brew_bin [String] The brew executable.
  # @param log [Pathname, String] File the job's stdout and stderr are appended to.
  # @return [BackgroundJob::Job, nil] nil when the job could not be started.
  def bundle_in_background(log:, brew_bin: 'brew')
    BackgroundJob.start({ 'FIRST_INSTALL' => '' }, brew_bin.to_s, 'bundle', log: log)
  end

  # The state of the background full install, for the closing summary.
  #
  # @return [Symbol] :none (never started), :running, :succeeded or :failed
  def full_install_state
    job = @full_install_job
    return :none unless job

    status = BackgroundJob.status(job)
    return :running unless status

    status.success? ? :succeeded : :failed
  end

  # Records the outcome of the background full install: a warning when it failed (with the log to
  # look at), an info line while it is still running or when it has finished.
  #
  # @return [Symbol] See #full_install_state
  def report_full_install
    state = full_install_state
    log = FULL_INSTALL_LOG.cyan
    case state
    when :running
      Logging.info "The full Brewfile install is still running in the background (log: '#{log}')"
    when :failed
      status = BackgroundJob.status(@full_install_job)
      Logging.record_warning "The background full Brewfile install failed (exit status #{status.exitstatus.inspect}) -- see '#{log}' and re-run 'brew bundle'"
    when :succeeded
      Logging.success 'The background full Brewfile install finished successfully'
    end
    state
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  # @param first_install [Boolean]
  # @param brew_bin [Pathname]
  # @return [Boolean]
  def _install(first_install:, brew_bin:)
    unless brew_bin.executable?
      Logging.record_warning "Brew binary '#{brew_bin.cyan}' is not executable -- skipping the bundle install"
      return false
    end

    @full_install_job = nil
    base_content = first_install ? _first_install_content : nil
    return false if first_install && base_content.nil?

    # With the base content the full-file 'brew bundle check' is skipped: on a vanilla macOS it
    # cannot pass. A failed install is attempted once more after a short pause (flaky downloads).
    bundled = _sync(brew_bin.to_s, base_content)
    if bundled
      Logging.success 'Successfully installed cmd-line and gui apps using homebrew'
    else
      Logging.record_warning 'Homebrew bundle install encountered errors; continuing...'
    end

    Keybase.link_cli_into(brew_bin.dirname)

    _start_full_install(brew_bin) if first_install

    bundled
  end

  # Installs +content+ (the base section, on a first install) or the whole Brewfile. Without
  # +content+ the install is skipped when 'brew bundle check' already passes; with it the check is
  # skipped, because on a vanilla macOS it can never pass and costs seconds (it evaluates the
  # Brewfile again). A failed install is attempted INSTALL_RETRIES more times after
  # INSTALL_RETRY_DELAY seconds: a cask download is occasionally flaky and succeeds the second time.
  #
  # @param brew_bin [String]
  # @param content [String, nil]
  # @return [Boolean] true if everything is (now) installed.
  def _sync(brew_bin, content)
    return true if content.nil? && Brew.bundle_check(brew_bin: brew_bin)

    attempts_left = INSTALL_RETRIES
    loop do
      return true if Brew.bundle_install(brew_bin: brew_bin, content: content)
      return false unless attempts_left.positive?

      attempts_left -= 1
      sleep INSTALL_RETRY_DELAY
    end
  end

  # The text to install first on a vanilla macOS: the base section of the Brewfile. A Brewfile
  # without the sentinel is installed whole (with a warning), which is also what happened before
  # the sentinel existed.
  #
  # @return [String, nil] nil when the Brewfile does not exist.
  def _first_install_content
    brewfile = EnvVars::HOMEBREW_BUNDLE_FILE
    unless brewfile.file?
      Logging.record_warning "Brewfile not found at '#{brewfile.cyan}' -- skipping the bundle install"
      return nil
    end

    base_brewfile_content(brewfile) || begin
      Logging.record_warning "No '#{FIRST_INSTALL_SENTINEL}' sentinel found in '#{brewfile.cyan}' -- the whole Brewfile is treated as the base section"
      Core.read_lines_utf8(brewfile).join
    end
  end

  # Starts the detached install of everything in the Brewfile.
  #
  # @param brew_bin [Pathname]
  # @return [void]
  def _start_full_install(brew_bin)
    @full_install_job = bundle_in_background(brew_bin: brew_bin.to_s, log: FULL_INSTALL_LOG)
    if @full_install_job
      Logging.info "Full Brewfile install running in background (log: '#{FULL_INSTALL_LOG.cyan}')"
    else
      Logging.record_warning "Could not start the background Brewfile install -- run 'brew bundle' once the setup is done"
    end
  end

  private_class_method :_install, :_sync, :_first_install_content, :_start_full_install
end
