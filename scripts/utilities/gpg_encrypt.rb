#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'command_utils'
require_relative 'core'
require_relative 'env_vars'
require_relative 'logging'
require_relative 'path_utils'

# Helpers for the 'gpg-encrypt::<url>' pseudo-URL scheme used by the external
# 'git-remote-gpg-encrypt' tool (installed via the 'vraravam/tap' Homebrew tap -- see
# files/--HOME--/Brewfile). Mirrors Keybase (scripts/utilities/keybase.rb) as the other
# backup-mechanism module -- see KeybaseMigration.md for how the two coexist.
#
# Unlike Keybase, there is no login/session state to manage here -- the tool itself
# (git-gpg-encrypt-setup/git-gpg-encrypt-restore) is invoked directly as a shell command
# (from the shell clone_repo_into function), so this module owns the URL scheme and the
# readiness check run by the machine setup.
module GpgEncrypt
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # URL scheme prefix recognized by clone_repo_into (both GitProcessor.clone_repo_into
  # and the shell function it delegates to) as a special-case that delegates to
  # 'git gpg-encrypt-restore' instead of a plain 'git clone'.
  PROTOCOL = 'gpg-encrypt::'

  # The external tool's readiness command.
  SETUP_COMMAND = 'git-gpg-encrypt-setup'

  # Whether encrypted-backup is enabled for this machine: at least one of
  # ENCRYPTED_HOME_REPO_URL / ENCRYPTED_PROFILES_REPO_URL is set (see KeybaseMigration.md for the
  # other backup mechanism).
  #
  # @return [Boolean]
  def configured?
    !(nil_or_empty?(EnvVars::ENCRYPTED_HOME_REPO_URL) && nil_or_empty?(EnvVars::ENCRYPTED_PROFILES_REPO_URL))
  end

  # The 'Setup encrypted backup' step of the machine setup: verifies the mechanism is ready (gpg
  # installed, Keychain passphrase set) by running the external tool's own setup command, which
  # explains on screen what is missing. Coexists with the Keybase step.
  #
  # @return [Boolean] false only when the setup command ran and failed; skipping because the
  #   mechanism is not configured, or the tool is not installed, is not a failure. A failure is
  #   recorded as a warning.
  def bootstrap_setup
    unless configured?
      Logging.debug "Neither 'ENCRYPTED_HOME_REPO_URL' nor 'ENCRYPTED_PROFILES_REPO_URL' env var is set -- skipping encrypted-backup setup"
      return true
    end

    unless PathUtils.command_exists?(SETUP_COMMAND)
      Logging.debug "'#{SETUP_COMMAND}' not found in PATH -- skipping encrypted backup setup"
      return true
    end

    unless CommandUtils.run_interactive(SETUP_COMMAND)
      Logging.record_warning 'Encrypted backup is not configured -- see instructions above'
      return false
    end

    Logging.success 'Encrypted backup is ready to use'
    true
  end

  # Builds the 'gpg-encrypt::<url>' pseudo-URL for the given plain clone URL.
  #
  # @param plain_url [String] Plain clone URL of the underlying (encrypted) git repo.
  # @return [String]
  # :reek:UtilityFunction -- Stateless URL builder
  def url(plain_url)
    "#{PROTOCOL}#{plain_url}"
  end
end
