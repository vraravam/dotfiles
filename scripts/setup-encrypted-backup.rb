#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/setup-encrypted-backup.rb
#
# Verifies the encrypted-backup mechanism (gpg + git bundle, see
# scripts/utilities/encrypted_backup.rb) is ready to use: gnupg installed, and a
# passphrase configured in the macOS Keychain. Delegates entirely to
# EncryptedBackup.prompt_and_store_passphrase for the "missing passphrase" case -- that
# method already handles both the interactive (prompts via 'security add-generic-password's
# own masked, double-entry prompt) and non-interactive (logs setup instructions and returns
# false) branches, so this script doesn't need its own TTY check.
#
# NOT one-time itself -- this script is idempotent and safe to run every time (it's called
# on every fresh-install-of-osx.sh run, and does nothing visible if already configured --
# see EncryptedBackup.prompt_and_store_passphrase's debug-level log for that case, hidden
# unless DEBUG=true). What IS effectively one-time-per-machine is the underlying Keychain
# entry it creates: it does not sync via iCloud Keychain (see KEYBASE_MIGRATION.md), so this
# script will prompt again (or need the manual 'security add-generic-password' command run
# again) on every new machine, exactly once each.
#
# Usage:
#   Standalone: setup-encrypted-backup.rb
#   Module:     SetupEncryptedBackup.run

require_relative 'utilities/encrypted_backup'
require_relative 'utilities/logging'
require_relative 'utilities/path_utils'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module SetupEncryptedBackup
  extend self

  # Public API method.
  #
  # @return [Boolean] true if ready to use, false otherwise
  def run
    unless PathUtils.command_exists?('gpg')
      Logging.record_error "'gpg' command not found in PATH -- install via Homebrew first (brew 'gnupg')"
      return false
    end

    EncryptedBackup.prompt_and_store_passphrase
  end
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  CliParser.parse('[no options]') do |opts|
    opts.separator 'Verifies the encrypted-backup mechanism is ready to use: gnupg installed, and a'
    opts.separator "passphrase configured in the macOS Keychain. Prompts interactively for one if it's"
    opts.separator 'missing and a real TTY is available; otherwise logs setup instructions.'
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan}"
  end

  increment_script_depth
  start_time = print_script_start

  success = SetupEncryptedBackup.run

  print_script_summary(start_time)
  exit(success ? 0 : 1)
end
