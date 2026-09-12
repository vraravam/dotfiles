#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/migrate-repo-to-encrypted-backup.rb
#
# ONE-TIME migration tool: migrates a single git repository from Keybase to the
# encrypted-backup mechanism (gpg + git bundle, see scripts/utilities/encrypted_backup.rb).
# Run this once per repository, when first moving it off Keybase -- there is nothing left
# to "migrate" for that repo afterward (Keybase support has been fully removed from this
# codebase; day-to-day pushes go through EncryptedBackup.export_and_push instead, wired up
# via the push-<basename>.sh override scripts -- see KEYBASE_MIGRATION.md).
#
# Unlike the old Keybase/gcrypt approach, this does not repurpose the live repo's remotes
# for backup transport -- the encrypted backup is a side-channel export to a separate plain
# GitHub repo. The one exception is cleanup: a dead 'origin' still pointing at a keybase://
# URL is removed (Keybase support has been fully removed from this codebase, so it can never
# work again). This removal is deliberately done here, once, rather than re-checked on every
# routine push (see push-<basename>.sh) -- a one-time migration concern belongs in the
# one-time migration tool, not the routine push path. Any other remote (or no remote at all)
# is left untouched. There is nothing to roll back if this fails: re-running it is always
# safe (it just re-bundles, re-encrypts, and re-pushes) -- but there is also nothing more to
# gain from running it again once a repo has been migrated.
#
# Usage:
#   Standalone: migrate-repo-to-encrypted-backup.rb --repo ~/path/to/repo --encrypted-repo-name home
#   Module:     MigrateRepoToEncryptedBackup.run(repo_dir: dir, encrypted_repo_name: name)

require 'pathname'

require_relative 'utilities/encrypted_backup'
require_relative 'utilities/git_processor'
require_relative 'utilities/logging'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module MigrateRepoToEncryptedBackup
  extend self

  # Public API method.
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

    _remove_stale_keybase_remote(repo_path, dry_run: dry_run)

    Logging.info "Migrating '#{repo_path.cyan}' to encrypted backup '#{encrypted_repo_name.cyan}'"

    unless EncryptedBackup.export_and_push(repo_dir: repo_path, encrypted_repo_name: encrypted_repo_name, dry_run: dry_run)
      Logging.record_error "Failed to migrate '#{repo_path.cyan}'"
      return false
    end

    return true if dry_run

    Logging.success "Migration complete for '#{repo_path.cyan}'"
    Logging.user_action "Test the restore path on a scratch directory before relying on this: EncryptedBackup.clone_and_decrypt(encrypted_repo_name: '#{encrypted_repo_name}', target_dir: '/tmp/restore-test')"
    true
  end

  # Removes 'origin' if it still points at a dead keybase:// URL -- a one-time cleanup so
  # that push wrapper scripts (push-<basename>.sh) never need to re-check this on every
  # routine push. Keybase support has been fully removed from this codebase, so a keybase://
  # remote can never work again; safe to remove unconditionally. Any other remote (or no
  # remote at all) is left untouched.
  #
  # @param repo_path [Pathname]
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [void]
  # :reek:UtilityFunction -- Stateless helper (correct design)
  def _remove_stale_keybase_remote(repo_path, dry_run: false)
    git = GitProcessor.new(dir: repo_path, dry_run: dry_run)
    url = git.remote_url
    return unless url.to_s.start_with?('keybase://')

    _stdout, stderr, status = git.remove_remote('origin')
    return if dry_run # GitProcessor already logged 'Would run: git remote remove origin'

    if status.success?
      Logging.success "Removed stale 'origin' remote ('#{url.cyan}') from '#{repo_path.cyan}'"
    else
      Logging.record_error "Failed to remove stale 'origin' remote from '#{repo_path.cyan}': #{stderr}"
    end
  end

  private_class_method :_remove_stale_keybase_remote
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = {}
  parser = CliParser.parse('[options]') do |opts|
    opts.separator 'Migrate a git repository to the gpg+git-bundle encrypted backup mechanism.'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('-r', '--repo PATH', 'Path to repository to migrate') { |v| options[:repo] = v }
    opts.on('-n', '--encrypted-repo-name NAME', 'Name of the plain GitHub repo to hold the encrypted blob') { |v| options[:encrypted_repo_name] = v }
    opts.on('--dry-run', 'Show what would be done without making changes') { options[:dry_run] = true }
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -r \"${HOME}\" -n home"
  end

  parser.abort_with_usage('Missing required option: --repo') if nil_or_empty?(options[:repo])
  parser.abort_with_usage('Missing required option: --encrypted-repo-name') if nil_or_empty?(options[:encrypted_repo_name])

  increment_script_depth
  start_time = print_script_start

  success = MigrateRepoToEncryptedBackup.run(
    repo_dir: options[:repo],
    encrypted_repo_name: options[:encrypted_repo_name],
    dry_run: options[:dry_run] || false
  )

  print_script_summary(start_time)
  exit(success ? 0 : 1)
end
