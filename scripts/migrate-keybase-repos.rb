#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8

# file location: ${DOTFILES_DIR}/scripts/migrate-keybase-repos.rb
#
# Convenience script to migrate both home and browser-profiles repos from Keybase to gcrypt.
# Migrates to:
#   - ~/home → gcrypt::git@github.com:vraravam/home.git
#   - ~/personal/<user>/browser-profiles → gcrypt::git@github.com:vraravam/browser-profiles.git
#
# Usage:
#   Standalone: migrate-keybase-repos.rb
#   Module:     MigrateKeybaseRepos.run

require 'pathname'
require 'io/console'
require_relative 'utilities/command_utils'
require_relative 'utilities/logging'
require_relative 'utilities/env_vars'
require_relative 'utilities/path_utils'
require_relative 'migrate-keybase-to-gcrypt'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module MigrateKeybaseRepos
  extend self

  # Configuration for repos to migrate
  REPOS = [
    {
      name: 'home',
      path: EnvVars::HOME,
      encrypted_url: 'gcrypt::git@github.com:vraravam/home.git'
    },
    {
      name: 'browser-profiles',
      path: EnvVars::PERSONAL_PROFILES_DIR,
      encrypted_url: 'gcrypt::git@github.com:vraravam/browser-profiles.git'
    }
  ].freeze

  # Public API method.
  #
  # @return [Boolean] true on success (all repos migrated), false if any failed
  def run
    Logging.info "Migrating #{REPOS.count} repositories from Keybase to git-remote-gcrypt"
    puts ''

    # Verify gcrypt is installed
    unless PathUtils.command_exists?('git-remote-gcrypt')
      Logging.error 'git-remote-gcrypt not found -- install it first: brew install git-remote-gcrypt'
      return false
    end

    # Verify gcrypt is configured
    participants = CommandUtils.query('git', 'config', '--global', '--get', 'gcrypt.participants')
    if participants != 'simple'
      Logging.error 'git-remote-gcrypt not configured -- run setup-git-remote-gcrypt.rb first'
      return false
    end

    Logging.user_action 'You will be prompted ONCE for an encryption password'
    Logging.user_action 'This password will be used for ALL encrypted repos'
    Logging.user_action 'Make sure to store it in your password manager!'
    puts ''

    # Verify password once at the start
    print 'Enter encryption password (will be used for all repos): '
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
    puts ''

    # Migrate each repo
    failed_repos = []

    REPOS.each_with_index do |repo_config, index|
      current_section = "[#{index + 1}/#{REPOS.count}] #{repo_config[:name]}"
      Logging.section_header "Migrating: #{repo_config[:name].cyan}"

      unless repo_config[:path].directory?
        Logging.warn "Repository not found: '#{repo_config[:path]}' -- skipping"
        failed_repos << repo_config[:name]
        puts ''
        next
      end

      success = MigrateKeybaseToGcrypt.run(
        repo_dir: repo_config[:path],
        encrypted_url: repo_config[:encrypted_url],
        verify_password: false # Already verified once
      )

      if success
        Logging.success "Migrated: #{repo_config[:name].cyan}"
      else
        failed_repos << repo_config[:name]
        Logging.warn "Failed to migrate: #{repo_config[:name]}"
      end

      puts ''
    end

    # Summary
    puts ''
    Logging.section_header 'Migration Summary'.yellow
    puts "  Total repos:    #{REPOS.count.to_s.purple}"
    puts "  Migrated:       #{(REPOS.count - failed_repos.count).to_s.green}"
    puts "  Failed:         #{failed_repos.count.positive? ? failed_repos.count.to_s.red : failed_repos.count}"

    if failed_repos.any?
      puts ''
      puts '  Failed repos:'.red
      failed_repos.each do |name|
        puts "    - #{name.red}"
      end
    end

    puts ''
    Logging.user_action 'Test each migrated repo: cd <repo> && git pull'
    Logging.user_action 'Keybase remotes preserved as \'keybase\' (for rollback if needed)'
    Logging.user_action 'When confident, you can remove Keybase remotes: git remote remove keybase'

    failed_repos.empty?
  end
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  include Logging

  increment_script_depth
  start_time = print_script_start

  success = MigrateKeybaseRepos.run

  print_script_summary(start_time)
  exit(success ? 0 : 1)
end
