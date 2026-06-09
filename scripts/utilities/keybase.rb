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
  # @return [Boolean] true if logged in, false otherwise.
  def ensure_logged_in
    unless PathUtils.command_exists?('keybase')
      Logging.error "'keybase' command not found in PATH. Aborting."
      return false
    end

    Logging.debug 'Logging into keybase'

    # Use Open3 to avoid SIGPIPE from grep -q under pipefail.
    # keybase status --json returns a JSON blob; parse for logged_in:true.
    status_json, = Open3.capture3('keybase', 'status', '--json')
    if status_json.include?('"logged_in":true')
      Logging.debug "Skipping keybase login -- '#{username.purple}' is already logged in"
      return true
    end

    unless system('keybase', 'login')
      Logging.error 'Could not log into keybase. Retry after logging in manually.'
      return false
    end

    true
  end

  # Returns true if the URL is a Keybase git repo URL (keybase://...).
  #
  # @param url [String]
  # @return [Boolean]
  def keybase_url?(url)
    url.to_s.start_with?('keybase://')
  end

  # Deletes the named Keybase repo (irreversible). Passes -f to skip confirmation.
  #
  # @param repo_name [String]
  # @return [Boolean] true if the command succeeded.
  def delete_repo(repo_name)
    system('keybase', 'git', 'delete', '-f', repo_name)
  end

  # Creates a new private Keybase repo.
  #
  # @param repo_name [String]
  # @return [Boolean] true if the command succeeded.
  def create_repo(repo_name)
    system('keybase', 'git', 'create', repo_name)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  private

  # Returns the configured Keybase username.
  # Raises an error if KEYBASE_USERNAME is not set, since Keybase operations require it.
  #
  # @return [String] the username
  # @raise [RuntimeError] if KEYBASE_USERNAME is nil or empty
  def username
    EnvVars::KEYBASE_USERNAME || raise('KEYBASE_USERNAME is not set. Set it in .shellrc if you want to use Keybase functionality.')
  end
end
