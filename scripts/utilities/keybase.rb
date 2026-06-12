# frozen_string_literal: true

require 'open3'

require_relative 'env_vars'
require_relative 'logging'
require_relative 'path_utils'

# Keybase helpers for login, repo creation/deletion, and URL validation.
# These are used by scripts that interact with Keybase git repos (recreate-repo.rb)
# and by fresh-install-of-osx.sh (_ensure_keybase_logged_in delegates to ensure_logged_in).
module Keybase
  extend self

  # Note: Logging methods must be qualified (Logging.debug, Logging.error, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  # Ensures keybase is installed and the current user is logged in.
  # Returns false on failure so callers can decide whether to abort or continue.
  # Called by fresh-install-of-osx.sh (_ensure_keybase_logged_in) and recreate-repo.rb.
  #
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [Boolean] true if logged in (or would log in), false otherwise.
  def ensure_logged_in(dry_run: false)
    unless PathUtils.command_exists?('keybase')
      Logging.error "'keybase' command not found in PATH. Aborting."
      return false
    end

    if dry_run
      Logging.info "Would ensure keybase login for '#{EnvVars::KEYBASE_USERNAME.purple}'"
      return true
    end

    Logging.debug 'Logging into keybase'

    # Use Open3 to avoid SIGPIPE from grep -q under pipefail.
    # keybase status --json returns a JSON blob; parse for logged_in:true.
    status_json, = Open3.capture3('keybase', 'status', '--json')
    if status_json.include?('"logged_in":true')
      Logging.debug "Skipping keybase login -- '#{EnvVars::KEYBASE_USERNAME.purple}' is already logged in"
      return true
    end

    unless system('keybase', 'login')
      Logging.error 'Could not log into keybase. Retry after logging in manually.'
      return false
    end

    true
  end

  # Builds the keybase:// URL for the given repo name owned by KEYBASE_USERNAME.
  #
  # @param repo_name [String]
  # @return [String] keybase://private/username/repo_name
  def build_repo_url(repo_name)
    "keybase://private/#{username}/#{repo_name}"
  end

  # Returns true if the URL is a Keybase git repo URL (keybase://...).
  #
  # @param url [String]
  # @return [Boolean]
  def keybase_url?(url)
    url.to_s.start_with?('keybase://')
  end

  # Deletes the named Keybase repo (irreversible). Passes -f to skip confirmation.
  # Logs a warning if deletion fails (expected if repo doesn't exist).
  #
  # @param repo_name [String]
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [void]
  def delete_repo(repo_name, dry_run: false)
    if dry_run
      Logging.info "Would delete keybase repo: '#{repo_name.yellow}'"
    else
      Logging.record_warning("Failed to delete keybase repo '#{repo_name.yellow}' (it might not exist)") unless system('keybase', 'git', 'delete', '-f', repo_name)
    end
  end

  # Creates a new private Keybase repo. Raises an error if creation fails.
  #
  # @param repo_name [String]
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [void]
  def create_repo(repo_name, dry_run: false)
    if dry_run
      Logging.info "Would create keybase repo: '#{repo_name.yellow}'"
    else
      Logging.error "Failed to create keybase repo '#{repo_name.yellow}'" unless system('keybase', 'git', 'create', repo_name)
    end
  end
end
