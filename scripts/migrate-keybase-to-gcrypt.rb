#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/migrate-keybase-to-gcrypt.rb
#
# Migrate git repositories from Keybase to git-remote-gcrypt encrypted remotes.
# Creates encrypted GitHub remotes for specified repos and pushes all branches.
#
# Usage:
#   Standalone: migrate-keybase-to-gcrypt.rb --repo ~/path/to/repo --encrypted-url gcrypt::git@github.com:user/repo-encrypted.git
#   Module:     MigrateKeybaseToGcrypt.run(repo_dir: dir, encrypted_url: url)

require 'pathname'
require 'io/console'
require_relative 'utilities/command_utils'
require_relative 'utilities/logging'
require_relative 'utilities/cli_parser'
require_relative 'utilities/git_processor'
require_relative 'utilities/core'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module MigrateKeybaseToGcrypt
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Public API method.
  #
  # @param repo_dir [String, Pathname] Path to repository to migrate
  # @param encrypted_url [String] gcrypt URL for encrypted remote
  # @param keybase_remote_name [String] Name of Keybase remote to preserve (default: 'keybase')
  # @param encrypted_remote_name [String] Name for encrypted remote (default: 'encrypted')
  # @param verify_password [Boolean] Prompt for password twice to verify (default: true)
  # @return [Boolean] true on success, false on error
  def run(repo_dir:, encrypted_url:, keybase_remote_name: 'keybase', encrypted_remote_name: 'encrypted', verify_password: true)
    repo_path = Pathname.new(repo_dir).expand_path

    unless GitProcessor.repo?(repo_path)
      Logging.error "'#{repo_path}' is not a git repository"
      return false
    end

    Logging.info "Migrating repository: '#{repo_path.to_s.cyan}'"
    Logging.info "Encrypted remote URL: '#{encrypted_url.cyan}'"

    # Verify gcrypt is configured for symmetric encryption
    unless _verify_gcrypt_config
      Logging.record_error 'gcrypt not configured for symmetric encryption -- run setup-git-remote-gcrypt.rb first'
      return false
    end

    # Verify password entry before proceeding
    if verify_password && !_verify_password_entry
      Logging.record_error 'Password verification failed'
      return false
    end

    # Rename existing Keybase remote (preserve for rollback)
    unless _rename_remote_if_exists(repo_path, 'origin', keybase_remote_name)
      return false
    end

    # Add encrypted remote
    unless _add_encrypted_remote(repo_path, encrypted_remote_name, encrypted_url)
      return false
    end

    # Push all branches to encrypted remote
    unless _push_all_branches(repo_path, encrypted_remote_name)
      Logging.record_error 'Failed to push branches to encrypted remote'
      return false
    end

    # Verify encrypted remote works (fetch)
    unless _verify_encrypted_remote(repo_path, encrypted_remote_name)
      Logging.record_error 'Failed to verify encrypted remote'
      return false
    end

    # Set encrypted remote as default origin
    unless _set_as_origin(repo_path, encrypted_remote_name)
      return false
    end

    Logging.success "Migration complete for '#{repo_path.to_s.cyan}'"
    Logging.user_action "Keybase remote preserved as '#{keybase_remote_name.yellow}' (for rollback)"
    Logging.user_action "Encrypted remote is now 'origin'"
    Logging.user_action "Test the migration: cd #{repo_path} && git pull"
    true
  end

  # Verify gcrypt is configured for symmetric encryption.
  #
  # @return [Boolean] true if configured correctly
  def _verify_gcrypt_config
    participants = CommandUtils.query('git', 'config', '--global', '--get', 'gcrypt.participants')

    if participants != 'simple'
      Logging.warn "gcrypt.participants is '#{participants}', expected 'simple'"
      return false
    end

    true
  end
  private_class_method :_verify_gcrypt_config

  # Prompt for password twice and verify they match.
  #
  # @return [Boolean] true if passwords match
  def _verify_password_entry
    Logging.user_action 'You will be prompted for an encryption password'
    Logging.user_action 'This password will be used for ALL encrypted repos'
    Logging.user_action 'Store it in your password manager!'
    puts ''

    print 'Enter encryption password: '
    password1 = $stdin.noecho(&:gets).chomp
    puts ''

    print 'Re-enter encryption password: '
    password2 = $stdin.noecho(&:gets).chomp
    puts ''

    if password1 != password2
      Logging.error 'Passwords do not match'
      return false
    end

    if password1.empty?
      Logging.error 'Password cannot be empty'
      return false
    end

    Logging.success 'Password verified'
    true
  end
  private_class_method :_verify_password_entry

  # Rename a remote if it exists.
  #
  # @param repo_dir [Pathname] Repository path
  # @param old_name [String] Current remote name
  # @param new_name [String] New remote name
  # @return [Boolean] true on success
  def _rename_remote_if_exists(repo_dir, old_name, new_name)
    git = GitProcessor.new(dir: repo_dir)

    # Check if old remote exists
    stdout, _stderr, status = git.run('remote', 'show')
    return true unless status.success? && stdout.include?(old_name)

    # Rename remote
    Logging.info "Renaming remote '#{old_name.yellow}' → '#{new_name.yellow}'"
    _stdout, stderr, status = git.run('remote', 'rename', old_name, new_name)

    unless status.success?
      Logging.error "Failed to rename remote: #{stderr}"
      return false
    end

    Logging.success "Remote renamed: '#{old_name}' → '#{new_name}'"
    true
  end
  private_class_method :_rename_remote_if_exists

  # Add encrypted remote to repository.
  #
  # @param repo_dir [Pathname] Repository path
  # @param remote_name [String] Remote name
  # @param remote_url [String] gcrypt URL
  # @return [Boolean] true on success
  def _add_encrypted_remote(repo_dir, remote_name, remote_url)
    git = GitProcessor.new(dir: repo_dir)

    Logging.info "Adding encrypted remote '#{remote_name.yellow}'"
    _stdout, stderr, status = git.run('remote', 'add', remote_name, remote_url)

    unless status.success?
      Logging.error "Failed to add encrypted remote: #{stderr}"
      return false
    end

    Logging.success "Encrypted remote added: '#{remote_name}' → '#{remote_url}'"
    true
  end
  private_class_method :_add_encrypted_remote

  # Push all branches to encrypted remote.
  #
  # @param repo_dir [Pathname] Repository path
  # @param remote_name [String] Remote name
  # @return [Boolean] true on success
  def _push_all_branches(repo_dir, remote_name)
    git = GitProcessor.new(dir: repo_dir)

    # Get list of all local branches
    stdout, _stderr, status = git.run('branch', '--format=%(refname:short)')
    unless status.success?
      Logging.error 'Failed to list branches'
      return false
    end

    branches = stdout.split("\n").map(&:strip).reject(&:empty?)

    if branches.empty?
      Logging.warn 'No branches found to push'
      return true
    end

    Logging.info "Pushing #{branches.count} branch(es) to '#{remote_name.yellow}'"
    Logging.user_action 'You will be prompted for the encryption password'
    puts ''

    # Push each branch
    branches.each do |branch|
      Logging.info "Pushing branch: '#{branch.cyan}'"
      _stdout, stderr, status = git.run('push', remote_name, branch)

      unless status.success?
        Logging.error "Failed to push branch '#{branch}': #{stderr}"
        return false
      end

      Logging.success "Pushed branch: '#{branch}'"
    end

    Logging.success "All branches pushed to '#{remote_name}'"
    true
  end
  private_class_method :_push_all_branches

  # Verify encrypted remote works by fetching.
  #
  # @param repo_dir [Pathname] Repository path
  # @param remote_name [String] Remote name
  # @return [Boolean] true on success
  def _verify_encrypted_remote(repo_dir, remote_name)
    git = GitProcessor.new(dir: repo_dir)

    Logging.info "Verifying encrypted remote '#{remote_name.yellow}'"
    _stdout, stderr, status = git.run('fetch', remote_name, '--dry-run')

    unless status.success?
      Logging.error "Failed to verify encrypted remote: #{stderr}"
      return false
    end

    Logging.success "Encrypted remote verified: '#{remote_name}'"
    true
  end
  private_class_method :_verify_encrypted_remote

  # Set encrypted remote as origin.
  #
  # @param repo_dir [Pathname] Repository path
  # @param remote_name [String] Current encrypted remote name
  # @return [Boolean] true on success
  def _set_as_origin(repo_dir, remote_name)
    git = GitProcessor.new(dir: repo_dir)

    Logging.info "Renaming '#{remote_name.yellow}' → 'origin'"
    _stdout, stderr, status = git.run('remote', 'rename', remote_name, 'origin')

    unless status.success?
      Logging.error "Failed to rename remote to origin: #{stderr}"
      return false
    end

    Logging.success "Encrypted remote is now 'origin'"
    true
  end
  private_class_method :_set_as_origin
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = {}
  parser = CliParser.parse('[options]') do |opts|
    opts.separator 'Migrate a git repository from Keybase to git-remote-gcrypt.'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('-r', '--repo PATH', 'Path to repository to migrate') { |v| options[:repo] = v }
    opts.on('-u', '--encrypted-url URL', 'gcrypt URL for encrypted remote') { |v| options[:encrypted_url] = v }
    opts.on('--keybase-remote NAME', 'Name of Keybase remote (default: keybase)') { |v| options[:keybase_remote] = v }
    opts.on('--encrypted-remote NAME', 'Name for encrypted remote (default: encrypted)') { |v| options[:encrypted_remote] = v }
    opts.on('--no-verify', 'Skip password verification prompt') { options[:no_verify] = true }
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -r ~/home -u gcrypt::git@github.com:user/home-encrypted.git"
  end

  parser.abort_with_usage('Missing required option: --repo') if nil_or_empty?(options[:repo])
  parser.abort_with_usage('Missing required option: --encrypted-url') if nil_or_empty?(options[:encrypted_url])

  increment_script_depth
  start_time = print_script_start

  success = MigrateKeybaseToGcrypt.run(
    repo_dir: options[:repo],
    encrypted_url: options[:encrypted_url],
    keybase_remote_name: options[:keybase_remote] || 'keybase',
    encrypted_remote_name: options[:encrypted_remote] || 'encrypted',
    verify_password: !options[:no_verify]
  )

  print_script_summary(start_time)
  exit(success ? 0 : 1)
end
