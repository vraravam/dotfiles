#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8

# file location: ${DOTFILES_DIR}/scripts/setup-git-remote-gcrypt.rb
#
# Configure git-remote-gcrypt for encrypted git remotes (Keybase replacement).
# Uses symmetric encryption (password-based) for simpler key management.
#
# Usage:
#   Standalone: setup-git-remote-gcrypt.rb
#   Module:     SetupGitRemoteGcrypt.run

require 'pathname'
require_relative 'utilities/command_utils'
require_relative 'utilities/logging'
require_relative 'utilities/env_vars'
require_relative 'utilities/path_utils'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module SetupGitRemoteGcrypt
  extend self

  # Public API method.
  #
  # @return [Boolean] true on success, false on error
  def run
    unless PathUtils.command_exists?('git-remote-gcrypt')
      Logging.info 'git-remote-gcrypt not installed -- skipping configuration.'
      return true
    end

    Logging.info 'Configuring git-remote-gcrypt for symmetric encryption'

    # Use symmetric encryption (password-based) instead of GPG keys
    # This is simpler for single-user repos and works immediately after install
    unless _configure_symmetric_encryption
      Logging.record_error 'Failed to configure git-remote-gcrypt'
      return false
    end

    Logging.success 'git-remote-gcrypt configured successfully'
    Logging.user_action 'When cloning encrypted repos, you will be prompted for a password'
    Logging.user_action 'Store this password in your password manager'
    true
  end

  # Configure git to use symmetric encryption for gcrypt.
  #
  # @return [Boolean] true on success, false on failure
  def _configure_symmetric_encryption
    # gcrypt.participants = "simple" enables symmetric encryption
    # This means: password-based encryption instead of GPG keys
    # See: https://github.com/spwhitton/git-remote-gcrypt#using-a-shared-secret
    success = CommandUtils.run_silent('git', 'config', '--global', 'gcrypt.participants', 'simple')

    unless success
      Logging.error 'Failed to set gcrypt.participants'
      return false
    end

    # Configure gcrypt to always trust (no GPG key validation needed for symmetric mode)
    success = CommandUtils.run_silent('git', 'config', '--global', 'gcrypt.gpg-args', '--trust-model always')

    unless success
      Logging.warn 'Failed to set gcrypt.gpg-args (non-critical for symmetric mode)'
    end

    true
  end
  private_class_method :_configure_symmetric_encryption
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  include Logging

  increment_script_depth
  start_time = print_script_start

  success = SetupGitRemoteGcrypt.run

  print_script_summary(start_time)
  exit(success ? 0 : 1)
end
