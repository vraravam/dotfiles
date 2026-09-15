#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/migrate-repo-to-encrypted-backup.rb
#
# ONE-TIME setup tool: adds the encrypted-backup mechanism (gpg + git bundle, see
# scripts/utilities/encrypted_backup.rb) to a git repository as an additional, independent
# backup -- alongside Keybase, not instead of it. Run this once per repository, when first
# setting up the encrypted backup for it -- there is nothing left to "migrate" for that repo
# afterward (day-to-day pushes go through EncryptedBackup.export_and_push instead, wired up
# via the push-<basename>.sh override scripts, which also still push 'origin' normally --
# see KEYBASE_MIGRATION.md).
#
# This never touches the live repo's remotes -- the encrypted backup is a side-channel
# export to a completely separate plain GitHub repo. If 'origin' points at a keybase://
# URL (or anything else, or nothing at all), it is left exactly as-is: the whole point of
# running this is to have both backups available side-by-side, so you can choose which one
# to restore from on a new machine. There is nothing to roll back if this fails: re-running
# it is always safe (it just re-bundles, re-encrypts, and re-pushes) -- but there is also
# nothing more to gain from running it again once a repo has been set up.
#
# Usage:
#   Standalone (single repo):     migrate-repo-to-encrypted-backup.rb --repo ~/path/to/repo --encrypted-repo-name home
#   Standalone (all known repos): migrate-repo-to-encrypted-backup.rb
#   Module (single repo):         MigrateRepoToEncryptedBackup.run(repo_dir: dir, encrypted_repo_name: name)
#   Module (all known repos):     MigrateRepoToEncryptedBackup.run_all

require 'pathname'

require_relative 'utilities/encrypted_backup'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/logging'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module MigrateRepoToEncryptedBackup
  extend self

  # Configuration for the known repos migrated by run_all.
  REPOS = [
    { name: 'home', path: EnvVars::HOME, encrypted_repo_name: EnvVars::ENCRYPTED_HOME_REPO_NAME },
    { name: 'browser-profiles', path: EnvVars::PERSONAL_PROFILES_DIR, encrypted_repo_name: EnvVars::ENCRYPTED_PROFILES_REPO_NAME },
  ].freeze

  # Public API method -- migrates a single repository. This is the fundamental
  # operation; run_all below is a convenience loop over REPOS calling this directly.
  #
  # @param repo_dir [String, Pathname] Path to repository to migrate
  # @param encrypted_repo_name [String] Name of the plain GitHub repo to hold the encrypted blob
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [Boolean] true on success, false on error
  def run(repo_dir:, encrypted_repo_name:, dry_run: false)
    repo_path = Pathname.new(repo_dir).expand_path

    unless GitProcessor.repo?(repo_path)
      Logging.record_error "'#{repo_path.cyan}' is not a git repository"
      return false
    end

    Logging.info "Setting up encrypted backup for '#{repo_path.cyan}' -> '#{encrypted_repo_name.cyan}' (existing remotes, if any, are left untouched)"

    unless EncryptedBackup.export_and_push(repo_dir: repo_path, encrypted_repo_name: encrypted_repo_name, dry_run: dry_run)
      Logging.record_error "Failed to migrate '#{repo_path.cyan}'"
      return false
    end

    return true if dry_run

    Logging.success "Migration complete for '#{repo_path.cyan}'"
    Logging.user_action "Test the restore path on a scratch directory before relying on this: EncryptedBackup.clone_and_decrypt(encrypted_repo_name: '#{encrypted_repo_name}', target_dir: '/tmp/restore-test')"
    true
  end

  # Public API method -- convenience wrapper that migrates all known repos (home and
  # browser-profiles) in a single run, looping over REPOS and calling run directly
  # (no subprocess) for each. Run this once, when first setting up the encrypted backup.
  #
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [Boolean] true on success (all repos migrated), false if any failed
  def run_all(dry_run: false)
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

      success = run(repo_dir: repo_path, encrypted_repo_name: repo_config[:encrypted_repo_name], dry_run: dry_run)

      if success
        Logging.success "Migrated: #{repo_name.cyan}"
      else
        failed_repos << repo_name
        Logging.warn "Failed to migrate: #{repo_name}"
      end

      puts ''
    end

    _print_run_all_summary(total, failed_repos)

    failed_repos.empty?
  end

  # Prints the run_all migration summary (counts + list of failures, if any).
  #
  # @param total [Integer]
  # @param failed_repos [Array<String>]
  # @return [void]
  # :reek:UtilityFunction -- Stateless helper (correct design)
  def _print_run_all_summary(total, failed_repos)
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

  private_class_method :_print_run_all_summary
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = {}
  parser = CliParser.parse('[options]') do |opts|
    opts.separator 'Migrate git repositories to the gpg+git-bundle encrypted backup mechanism.'
    opts.separator ''
    opts.separator 'With no --repo, migrates all known repos (home, browser-profiles) in one run.'
    opts.separator 'With --repo (and --encrypted-repo-name), migrates only that repository.'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('-r', '--repo PATH', 'Path to a specific repository to migrate (omit to migrate all known repos)') { |v| options[:repo] = v }
    opts.on('-n', '--encrypted-repo-name NAME', 'Name of the plain GitHub repo to hold the encrypted blob (required with --repo)') { |v| options[:encrypted_repo_name] = v }
    opts.on('--dry-run', 'Show what would be done without making changes') { options[:dry_run] = true }
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} --repo \"${HOME}\" --encrypted-repo-name home"
    opts.separator "  eg: #{File.basename(__FILE__).cyan}  # migrates all known repos"
  end

  # --repo and --encrypted-repo-name must be provided together, or neither (neither means
  # "migrate all known repos").
  if options[:repo] && nil_or_empty?(options[:encrypted_repo_name])
    parser.abort_with_usage('--encrypted-repo-name is required when --repo is given')
  elsif options[:encrypted_repo_name] && nil_or_empty?(options[:repo])
    parser.abort_with_usage('--repo is required when --encrypted-repo-name is given')
  end

  increment_script_depth
  start_time = print_script_start

  success = if options[:repo]
              MigrateRepoToEncryptedBackup.run(
                repo_dir: options[:repo],
                encrypted_repo_name: options[:encrypted_repo_name],
                dry_run: options[:dry_run] || false
              )
            else
              MigrateRepoToEncryptedBackup.run_all(dry_run: options[:dry_run] || false)
            end

  print_script_summary(start_time)
  exit(success ? 0 : 1)
end
