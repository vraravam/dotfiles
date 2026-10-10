#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'json'

require_relative 'command_utils'
require_relative 'core'
require_relative 'env_vars'
require_relative 'logging'
require_relative 'path_utils'

# Keybase helpers for login, repo creation/deletion, and URL validation.
# These are used by scripts that interact with Keybase git repos (recreate-repository.rb)
# and by fresh-install-of-osx.sh (via call_utility: bootstrap_login and ensure_logged_in).
module Keybase
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # URL scheme prefix for Keybase git repos. Used by both keybase_url? (validator) and
  # repo_url (builder) below so the literal only appears once.
  PROTOCOL = 'keybase://'

  # Where the Keybase cask installs the app; its command-line tools live in SharedSupport/bin.
  APP_PATH = Core::ROOT.join('Applications', 'Keybase.app').freeze

  # How many one-second polls ensure_service_running waits for the service to answer.
  SERVICE_START_ATTEMPTS = 15

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

  # Whether Keybase is enabled for this machine: at least one of KEYBASE_HOME_REPO_NAME /
  # KEYBASE_PROFILES_REPO_NAME is set (see KeybaseMigration.md for the other backup mechanism).
  #
  # @return [Boolean]
  def configured?
    !(nil_or_empty?(EnvVars::KEYBASE_HOME_REPO_NAME) && nil_or_empty?(EnvVars::KEYBASE_PROFILES_REPO_NAME))
  end

  # The 'Setup Keybase' step of the bootstrap: a readiness/login step only, the clone itself is
  # done later by the repository resurrection. Logging in is attempted only on the first-time
  # vanilla-OS install, non-interactively (no y/N gate); re-runs on an already-configured machine
  # must not block on a login attempt every time, so they just report and carry on.
  #
  # @param first_install [Boolean] True on a vanilla macOS.
  # @return [Boolean] false only when a login was attempted and failed.
  def bootstrap_login(first_install: false)
    unless configured?
      Logging.debug "Neither 'KEYBASE_HOME_REPO_NAME' nor 'KEYBASE_PROFILES_REPO_NAME' env var is set -- skipping Keybase setup"
      return true
    end

    unless PathUtils.command_exists?('keybase')
      Logging.info "Skipping Keybase setup since '#{'keybase'.yellow}' is not installed"
      return true
    end

    # Already logged in (from a previous run, or 'keybase login' run manually): never re-ask,
    # which is what keeps the idempotent re-run pleasant.
    if username
      Logging.success 'Already logged into Keybase'
      return true
    end

    unless first_install
      Logging.info "Skipping Keybase login -- not logged in. Run 'keybase login' manually, then re-run this script, to enable it."
      return true
    end

    return false unless ensure_logged_in(start_service: true)

    Logging.success 'Successfully logged into Keybase'
    true
  end

  # Returns true if the URL is a Keybase git repo URL (keybase://...).
  #
  # @param url [String]
  # @return [Boolean]
  # :reek:UtilityFunction -- Stateless URL validator
  def keybase_url?(url)
    url.to_s.start_with?(PROTOCOL)
  end

  # Builds the keybase:// URL for the given repo name, owned by whoever is currently
  # logged into Keybase. Derived dynamically via 'username' above (reads 'keybase
  # status') -- no username is stored anywhere; whoever completed the interactive
  # login (see 'ensure_logged_in' below) owns the account.
  #
  # @param repo_name [String] Bare Keybase repo name (e.g. 'home').
  # @return [String]
  # :reek:UtilityFunction -- Stateless URL builder
  def repo_url(repo_name)
    "#{PROTOCOL}private/#{username}/#{repo_name}"
  end

  # ---------------------------------------------------------------------------
  # Mutation methods (modify state)
  # ---------------------------------------------------------------------------

  # Links the 'keybase' and 'git-remote-keybase' command-line tools from the installed app into
  # +bin_dir+ (normally ${HOMEBREW_PREFIX}/bin).
  #
  # Homebrew cask 'postinstall:' hooks only run when 'brew bundle install' actually (re)installs
  # the cask. If 'brew bundle check' already reported success (e.g. Keybase.app was left behind
  # by an earlier partial run of the idempotent install), the hook never fires and the CLI
  # symlinks stay missing although the app itself is usable. The Brewfile's own hook creates the
  # same links; this is a redundant safety net for exactly that case, and 'ln -sf' makes it safe
  # to run every time. When the app is absent (Keybase disabled) nothing happens.
  #
  # @param bin_dir [Pathname, String] Directory to place the symlinks in.
  # @return [Boolean] true if the links were (re)created, false if the app is not installed.
  def link_cli_into(bin_dir)
    return false unless APP_PATH.directory?

    require 'fileutils'
    support_bin = APP_PATH.join('Contents', 'SharedSupport', 'bin')
    %w[keybase git-remote-keybase].each do |tool|
      FileUtils.ln_sf(support_bin.join(tool).to_s, Pathname.new(bin_dir).join(tool).to_s)
    end
    true
  end

  # The keybase CLI talks to a background service (keybased) that is normally started
  # when Keybase.app first launches -- e.g. via the login item registered by the
  # Brewfile's postinstall hook, which only takes effect on the *next* login. On a
  # single-session vanilla-OS run the user never logs out/in, so the service is never
  # started, and 'keybase login' fails with "dial unix .../keybased.sock: no such file
  # or directory". Launch the app hidden (no Dock/focus steal) and wait briefly for the
  # service to come up before attempting login.
  #
  # Requested explicitly through ensure_logged_in(start_service: true) by the bootstrap, so
  # other callers such as recreate-repository.rb are unaffected. The ownership fix always runs;
  # the service is only started when 'keybase status' fails.
  #
  # @return [void]
  def ensure_service_running
    return unless PathUtils.command_exists?('keybase')

    _fix_google_support_ownership
    return if _service_up?

    Logging.info 'Starting Keybase service'
    CommandUtils.run_silent('open', '-g', '-a', 'Keybase')
    SERVICE_START_ATTEMPTS.times do
      break if _service_up?

      sleep 1
    end
  end

  # Ensures keybase is installed and someone is logged in, prompting an
  # interactive login if not. If KEYBASE_USERNAME is set, it is passed to
  # 'keybase login <username>' (so the prompt for the account is skipped); otherwise
  # whoever completes the login becomes the active account. Already being logged in
  # (as any account) is accepted as-is.
  # Returns false on failure so callers can decide whether to abort or continue.
  # Called by bootstrap_login and recreate-repository.rb.
  #
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @param start_service [Boolean] When true, makes sure the keybase service is running first
  #   (see ensure_service_running) -- needed on a vanilla OS where Keybase.app was never launched.
  # @return [Boolean] true if logged in (or would log in), false otherwise.
  # :reek:UtilityFunction -- Stateless utility that operates only on arguments
  def ensure_logged_in(dry_run: false, start_service: false)
    unless PathUtils.command_exists?('keybase')
      Logging.record_error "'keybase' command not found in PATH -- install via Homebrew first"
      return false
    end

    if dry_run
      Logging.info 'Would ensure keybase login'
      return true
    end

    ensure_service_running if start_service

    Logging.debug 'Checking keybase login status'

    status = _status
    if status && status['LoggedIn']
      Logging.debug "Already logged into keybase as '#{status['Username'].purple}'"
      return true
    end

    username = EnvVars::KEYBASE_USERNAME
    Logging.info "Logging into keybase as '#{username.purple}'" if username
    CommandUtils.run_interactive('keybase', 'login', *username) do
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

  # @return [Boolean] whether the keybase service answers 'keybase status' (exit 0)
  def _service_up?
    CommandUtils.run_silent('keybase', 'status')
  end

  private_class_method :_service_up?

  # Keybase.app's kbnm (native messaging) installer writes into each installed browser's
  # Application Support directory on first launch (e.g. .../Google/Chrome) to register its
  # browser-extension messaging host. Google's own auto-update tooling (Keystone/
  # GoogleSoftwareUpdate) is known to sometimes leave '~/Library/Application Support/Google'
  # owned by a different user (observed on a vanilla-OS run) -- if so, kbnm's mkdir fails
  # with "operation not permitted" and Keybase.app pops up a blocking error dialog, which
  # can stall this non-interactive bootstrap since there is nobody around to dismiss it.
  # Fix ownership defensively before launching, using the exact fix the dialog itself
  # suggests. sudo is assumed already primed (keep_sudo_alive runs earlier in the bootstrap).
  #
  # @return [void]
  def _fix_google_support_ownership
    google_support_dir = EnvVars::HOME.join('Library', 'Application Support', 'Google')
    return unless google_support_dir.directory?
    return if google_support_dir.stat.uid == Process.uid

    Logging.info "Fixing ownership of '#{google_support_dir.to_s.cyan}' (was owned by a different user)"
    CommandUtils.run_silent('sudo', 'chown', '-R', "#{EnvVars::USER}:staff", google_support_dir.to_s)
  end

  private_class_method :_fix_google_support_ownership

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
