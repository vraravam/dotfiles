#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'json'

require_relative 'command_utils'
require_relative 'core'
require_relative 'logging'
require_relative 'path_utils'

# Keybase helpers for login, repo creation/deletion, and URL validation.
# These are used by scripts that interact with Keybase git repos (recreate-repository.rb)
# and by fresh-install-of-osx.sh (_ensure_keybase_logged_in delegates to ensure_logged_in).
module Keybase
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Note: Logging methods must be qualified (Logging.debug, Logging.error, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Query methods (read-only state inspection)
  # ---------------------------------------------------------------------------

  # Note: Logging methods must be qualified (Logging.debug, Logging.error, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # Returns the username of the currently logged-in Keybase user, derived
  # directly from 'keybase status' -- Keybase's own persistent login state is
  # the single source of truth, so nothing needs to be pre-configured in this
  # repo to know "whose account is this" (mirrors how GH_USERNAME is derived
  # from the cloned repo's git remote rather than stored statically).
  #
  # @return [String, nil] the logged-in username, or nil if keybase isn't
  #   installed or nobody is logged in
  def username
    return nil unless PathUtils.command_exists?('keybase')

    status = _status
    status && status['LoggedIn'] ? status['Username'] : nil
  end

  # Returns true if the URL is a Keybase git repo URL (keybase://...).
  #
  # @param url [String]
  # @return [Boolean]
  # :reek:UtilityFunction -- Stateless URL validator
  def keybase_url?(url)
    url.to_s.start_with?('keybase://')
  end

  # ---------------------------------------------------------------------------
  # Mutation methods (modify state)
  # ---------------------------------------------------------------------------

  # Ensures keybase is installed and someone is logged in, prompting an
  # interactive login if not. Whoever completes the login becomes the active
  # account -- no target username is required in advance.
  # Returns false on failure so callers can decide whether to abort or continue.
  # Called by fresh-install-of-osx.sh (_ensure_keybase_logged_in) and recreate-repository.rb.
  #
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [Boolean] true if logged in (or would log in), false otherwise.
  # :reek:UtilityFunction -- Stateless utility that operates only on arguments
  def ensure_logged_in(dry_run: false)
    unless PathUtils.command_exists?('keybase')
      Logging.record_error "'keybase' command not found in PATH -- install via Homebrew first"
      return false
    end

    if dry_run
      Logging.info 'Would ensure keybase login'
      return true
    end

    Logging.debug 'Checking keybase login status'

    status = _status
    if status && status['LoggedIn']
      Logging.debug "Already logged into keybase as '#{status['Username'].purple}'"
      return true
    end

    CommandUtils.run_interactive('keybase', 'login') do
      Logging.record_error 'Could not log into keybase -- retry after logging in manually'
    end
  end

  # Deletes the named Keybase repo (irreversible). Passes -f to skip confirmation.
  # Logs a warning if deletion fails (expected if repo doesn't exist).
  #
  # @param repo_name [String]
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [void]
  # :reek:UtilityFunction -- Stateless utility that operates only on arguments
  def delete_repo(repo_name, dry_run: false)
    if dry_run
      Logging.info "Would delete keybase repo: #{repo_name.yellow}"
    else
      Logging.record_warning("Failed to delete keybase repo #{repo_name.yellow} (it might not exist)") unless CommandUtils.run_silent('keybase', 'git', 'delete', '-f', repo_name)
    end
  end

  # Creates a new private Keybase repo. Returns false if creation fails.
  #
  # @param repo_name [String]
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [Boolean] true on success or dry_run, false on failure
  # :reek:UtilityFunction -- Stateless utility that operates only on arguments
  def create_repo(repo_name, dry_run: false)
    if dry_run
      Logging.info "Would create keybase repo: #{repo_name.yellow}"
      return true
    end

    if CommandUtils.run_interactive('keybase', 'git', 'create', repo_name)
      true
    else
      Logging.record_error "Failed to create keybase repo #{repo_name.yellow}"
      false
    end
  end

  # Recreates a Keybase repo by deleting and recreating it.
  # Used when force-squashing commits destroys local history.
  #
  # @param repo_name [String]
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [Boolean] true on success or dry_run, false on failure
  def recreate_repo(repo_name, dry_run: false)
    if dry_run
      Logging.info "Would recreate keybase repo: #{repo_name.yellow}"
      return true
    end

    Logging.debug "#{'Recreating'.yellow} keybase repo '#{repo_name.cyan}'"
    delete_repo(repo_name, dry_run: dry_run)
    unless create_repo(repo_name, dry_run: dry_run)
      Logging.record_error 'Failed to recreate keybase repo -- manual intervention required'
      return false
    end
    true
  end

  private

  # Parses 'keybase status --json'. Not memoized -- must reflect login state
  # freshly after ensure_logged_in performs an interactive login.
  #
  # @return [Hash, nil] parsed status, or nil if the command failed/returned invalid JSON
  def _status
    JSON.parse(CommandUtils.query('keybase', 'status', '--json'))
  rescue JSON::ParserError
    nil
  end

  private_class_method :_status
end
