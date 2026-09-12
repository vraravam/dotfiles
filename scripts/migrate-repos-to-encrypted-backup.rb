#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/migrate-repos-to-encrypted-backup.rb
#
# ONE-TIME migration tool: convenience wrapper to migrate both the home and
# browser-profiles repos from Keybase to the encrypted-backup mechanism (gpg + git bundle,
# see scripts/utilities/encrypted_backup.rb) in a single run:
#   - EnvVars::HOME -> ENCRYPTED_HOME_REPO_NAME
#   - EnvVars::PERSONAL_PROFILES_DIR -> ENCRYPTED_PROFILES_REPO_NAME
#
# Run this once, when first moving off Keybase. There is nothing left to migrate for either
# repo afterward -- day-to-day pushes go through EncryptedBackup.export_and_push instead, via
# the push-<basename>.sh override scripts (see KEYBASE_MIGRATION.md).
#
# Usage:
#   Standalone: migrate-repos-to-encrypted-backup.rb
#   Module:     MigrateReposToEncryptedBackup.run

require_relative 'migrate-repo-to-encrypted-backup'
require_relative 'utilities/encrypted_backup'
require_relative 'utilities/env_vars'
require_relative 'utilities/logging'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module MigrateReposToEncryptedBackup
  extend self

  # Configuration for repos to migrate
  REPOS = [
    { name: 'home', path: EnvVars::HOME, encrypted_repo_name: EnvVars::ENCRYPTED_HOME_REPO_NAME },
    { name: 'browser-profiles', path: EnvVars::PERSONAL_PROFILES_DIR, encrypted_repo_name: EnvVars::ENCRYPTED_PROFILES_REPO_NAME },
  ].freeze

  # Public API method.
  #
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [Boolean] true on success (all repos migrated), false if any failed
  def run(dry_run: false)
    total = REPOS.count
    Logging.info "Migrating #{total} repositories to the encrypted-backup mechanism"
    puts ''

    unless EncryptedBackup.passphrase_configured?
      Logging.record_error 'No passphrase found in Keychain -- run scripts/setup-encrypted-backup.rb first for setup instructions'
      return false
    end

    failed_repos = []

    REPOS.each do |repo_config|
      repo_name = repo_config[:name]
      repo_path = repo_config[:path]
      Logging.section_header "Migrating: #{repo_name.cyan}"

      unless repo_path.directory?
        Logging.warn "Repository not found: '#{repo_path.cyan}' -- skipping"
        failed_repos << repo_name
        puts ''
        next
      end

      success = MigrateRepoToEncryptedBackup.run(
        repo_dir: repo_path,
        encrypted_repo_name: repo_config[:encrypted_repo_name],
        dry_run: dry_run
      )

      if success
        Logging.success "Migrated: #{repo_name.cyan}"
      else
        failed_repos << repo_name
        Logging.warn "Failed to migrate: #{repo_name}"
      end

      puts ''
    end

    _print_summary(total, failed_repos)

    failed_repos.empty?
  end

  # Prints the migration summary (counts + list of failures, if any).
  #
  # @param total [Integer]
  # @param failed_repos [Array<String>]
  # @return [void]
  # :reek:UtilityFunction -- Stateless helper (correct design)
  def _print_summary(total, failed_repos)
    failed_count = failed_repos.count

    puts ''
    Logging.section_header 'Migration Summary'.yellow
    puts "  Total repos:    #{total.to_s.purple}"
    puts "  Migrated:       #{(total - failed_count).to_s.green}"
    puts "  Failed:         #{failed_count.positive? ? failed_count.to_s.red : failed_count}"

    if failed_repos.any?
      puts ''
      puts '  Failed repos:'.red
      failed_repos.each { |name| puts "    - #{name.red}" }
    end

    puts ''
    Logging.user_action 'Test each migrated repo by restoring to a scratch directory before relying on it.'
  end

  private_class_method :_print_summary
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = {}
  CliParser.parse('[options]') do |opts|
    opts.separator 'Migrate the home and browser-profiles repos to the encrypted-backup mechanism.'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('--dry-run', 'Show what would be done without making changes') { options[:dry_run] = true }
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan}"
  end

  increment_script_depth
  start_time = print_script_start

  success = MigrateReposToEncryptedBackup.run(dry_run: options[:dry_run] || false)

  print_script_summary(start_time)
  exit(success ? 0 : 1)
end
