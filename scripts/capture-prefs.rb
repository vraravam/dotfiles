#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/capture-prefs.rb
#
# Export or import macOS application preferences (plists) to/from the dotfiles repo.
# Handles stripping of non-portable keys, git staging on export, and system service
# reload on import.
#
# Usage:
#   Standalone: capture-prefs.rb -e  # Export current prefs to git repo
#               capture-prefs.rb -i  # Import prefs from git repo to current system
#               capture-prefs.rb -f <search>  # Discover and append matching domains to the allowed list
#   Module:     CapturePrefs.run(operation: 'export')  # or 'import'
#               CapturePrefs.find_and_append(search: 'ghostty')

require 'fileutils'
require 'pathname'
require 'set'
require 'tempfile'

require_relative 'utilities/command_utils'
require_relative 'utilities/core'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/launch_services'
require_relative 'utilities/logging'
require_relative 'utilities/macos'
require_relative 'utilities/path_utils'
require_relative 'utilities/plist'
require_relative 'utilities/string_ext'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module CapturePrefs
  extend self

  # Process names (pgrep -x matches) -> display names for restart notification.
  # Only user-specified apps; login-item apps handled by kill/restart_login_item_apps.
  APPS_NEEDING_RESTART = {
    'Ghostty' => 'Ghostty',
    'iTerm2' => 'iTerm2',
    'Terminal' => 'Terminal'
  }.freeze

  # Data files that drive which domains are processed and which keys are stripped.
  DATA_DIR = EnvVars::DOTFILES_DIR.join('scripts', 'data').freeze
  ALLOWED_LIST_FILE = DATA_DIR.join('capture-prefs-allowed-list.txt').freeze
  DENIED_LIST_FILE = DATA_DIR.join('capture-prefs-denied-list.txt').freeze
  EXCLUDED_KEYS_FILE = DATA_DIR.join('capture-prefs-excluded-keys.txt').freeze

  # Default-application handlers (default browser, mail client, URL schemes, file types) are
  # not an ordinary defaults domain -- see LaunchServices. Stored under their own file name,
  # whose base name is on the denied list so the per-domain export/import loop (and
  # 'capture-prefs.rb -f') never treats it as a domain to 'defaults import'.
  LAUNCH_SERVICES_FILE_NAME = 'default-app-handlers.plist'

  # Public API method.
  #
  # @param operation [String] Either 'export' or 'import'
  # @return [Boolean] true on success, false on error
  # :reek:UtilityFunction -- Uses instance variable @operation for memoized helpers
  def run(operation:)
    Logging.error "Invalid operation: '#{operation.to_s.yellow}'. Must be 'export' or 'import'." unless %w[export import].include?(operation)

    @operation = operation

    # Extract constants used multiple times
    personal_configs_dir = EnvVars::PERSONAL_CONFIGS_DIR
    dotfiles_dir = EnvVars::DOTFILES_DIR

    # Validate required env vars. PERSONAL_CONFIGS_DIR does not need to already
    # exist (target_dir below creates it via ensure_directories_exist -- a fresh
    # install running this for the first time legitimately won't have it yet).
    Logging.error "DOTFILES_DIR not found: '#{dotfiles_dir.cyan}'" unless dotfiles_dir.directory?

    target_dir = personal_configs_dir.join('defaults')
    PathUtils.ensure_directories_exist(target_dir)

    # Suspend the automatic software update schedule so background update
    # activity cannot interfere with plist reads/writes during export or import.
    # Resume on exit (both clean and error exits).
    MacOS.suspend_softwareupdate_schedule
    at_exit { MacOS.resume_softwareupdate_schedule }

    # Kill/restart login-item apps on import only, and only when running interactively.
    # On import, apps must be stopped before writing so they cannot overwrite imported
    # values when they quit. Cron skips this -- killall would disrupt the user's running
    # session, and 'open -a' would re-launch apps mid-session. On export, macOS cfprefsd
    # has already flushed current prefs to disk; killing apps is unnecessary.
    if _importing? && Core.running_in_tty?
      MacOS.kill_login_item_apps
      at_exit { MacOS.restart_login_item_apps }
    end

    if _exporting?
      # Clean up old files before exporting new ones (also handles removed domains)
      # .defaults files are from a past version of this script -- delete them too
      target_dir.glob('*.plist').each(&:unlink)
      target_dir.glob('.plist').each(&:unlink)
      target_dir.glob('*.defaults').each(&:unlink)
    end

    # Load data files (each helper validates its own file)
    denied = _load_denied_list(DENIED_LIST_FILE)
    excluded_by_domain = _load_excluded_keys(EXCLUDED_KEYS_FILE)
    domains = _load_domains_list(ALLOWED_LIST_FILE, denied)

    if nil_or_empty?(domains)
      Logging.info 'No domains found -- nothing to do.'
      return true
    end

    Logging.info "Running operation: '#{@operation.yellow}'"
    saved_count = 0

    domains.each do |app_pref|
      app_pref_colored = app_pref.light_cyan
      Logging.debug "Processing '#{app_pref_colored}'"

      target_file = target_dir.join("#{app_pref}.plist")

      if _exporting?
        unless Plist.export_domain(app_pref, target_file)
          Logging.record_warning("Failed to export '#{app_pref_colored}'")
          next
        end

        # Strip non-portable keys before staging to git
        Plist.strip_excluded_keys(app_pref, target_file, excluded_by_domain)

        # Delete if stripping left an empty dict
        if Plist.keys?(target_file)
          saved_count += 1
        else
          target_file.unlink
          Logging.debug "Deleted empty plist for '#{app_pref_colored}' -- no keys remain after stripping"
        end
      else
        # Import
        unless file?(target_file)
          Logging.debug "Skipping import of '#{app_pref_colored}' -- no exported plist found"
          next
        end

        # Strip non-portable keys from a temp copy
        temp_plist = Tempfile.new(['capture-prefs-', '.plist'])
        temp_plist_path = temp_plist.path
        FileUtils.cp(target_file.to_s, temp_plist_path)
        Plist.strip_excluded_keys(app_pref, Pathname.new(temp_plist_path), excluded_by_domain)

        Logging.record_warning("Failed to import '#{app_pref_colored}'") unless Plist.import_domain(app_pref, temp_plist_path)

        temp_plist.close
        temp_plist.unlink
      end
    end

    _sync_default_app_handlers(target_dir.join(LAUNCH_SERVICES_FILE_NAME))

    # Post-processing
    if _exporting?
      begin
        GitProcessor.new(dir: EnvVars::HOME) do |git|
          # Git accepts absolute paths directly - no normalization needed
          _stdout, _stderr, status = git.add(target_dir)
          Logging.record_warning("Failed to git add '#{target_dir.cyan}'") unless status.success?

          # Auto-commit staged changes (both fresh-install and cron want this)
          # Uses smart_commit: amends if ahead of remote (single commit), creates new if not
          if git.repo?
            if git.smart_commit("Preferences backup: #{Core.current_timestamp}")
              Logging.success 'Committed preferences backup to HOME repo'
            else
              Logging.record_warning 'Failed to commit backup -- import timestamp check may fail'
            end
          end
        end
        Logging.success "Export complete. Staged changes in '#{target_dir.cyan}'."
      rescue RuntimeError => e
        Logging.record_warning "Skipping git add -- #{e.message}"
      end
    else
      # Reload system services so imported preferences take effect immediately
      MacOS.reload_macos_prefs
      Logging.success 'System services reloaded -- most imported settings are now active.'
      _notify_apps_needing_restart
    end

    saved_msg = _exporting? ? " -- #{saved_count.to_s.purple} files saved after stripping" : ''
    Logging.success "Operation finished. Processed #{domains.length.to_s.purple} domains (denied-list entries filtered at load time)#{saved_msg}."
    true
  end

  # Finds every preference domain whose NAME contains +search+ (case-insensitive) and
  # appends the ones not yet listed to the allowed list, then re-sorts the file
  # (case-insensitive, duplicates removed). Matching is on domain names (from
  # 'defaults domains'), not on key/value contents as 'defaults find' does, because
  # content matching pulls in unrelated domains that merely mention the app (Finder
  # recents, launcher usage stats, etc.). Domains on the denied list (machine-specific or
  # account-bound data -- see capture-prefs-denied-list.txt) are reported and never
  # appended.
  #
  # @param search [String] Case-insensitive substring to look for in domain names.
  # @return [Boolean] true on success, false if no domain matched.
  def find_and_append(search:)
    search = search.to_s.strip
    Logging.error 'Usage: capture-prefs.rb -f <search-string>' if search.empty?

    denied = Plist.load_denied_list(DENIED_LIST_FILE)
    allowed = Plist.load_domains_list(ALLOWED_LIST_FILE, Set.new)

    # 'defaults domains' prints one comma-separated line.
    all_domains = CommandUtils.query(MacOS::DEFAULTS_CMD, 'domains').split(', ').map(&:strip)
    matches = all_domains.select { |domain| domain.downcase.include?(search.downcase) }

    if matches.empty?
      Logging.warn "No preference domain name contains '#{search.yellow}' (the app may not have written any preferences yet)"
      return false
    end

    matches.each do |domain|
      if denied.include?(domain)
        Logging.warn "Skipping '#{domain.light_cyan}' -- it is on the denied list (machine-specific data; see '#{DENIED_LIST_FILE.cyan}')"
      elsif allowed.include?(domain)
        Logging.info "'#{domain.light_cyan}' is already in the allowed list"
      else
        allowed.add(domain)
        Logging.success "Appended '#{domain.light_cyan}' to the allowed list"
      end
    end

    # Sort key mirrors the locale-aware order the file has always been kept in: compare
    # case-insensitively, and on a tie put the lowercase spelling first (swapcase flips
    # which of the two sorts earlier in plain byte order).
    sorted = allowed.to_a.sort_by { |domain| [domain.downcase, domain.swapcase] }
    ALLOWED_LIST_FILE.write("#{sorted.join("\n")}\n", encoding: 'UTF-8')
    true
  end

  # Loads the denied list file into a Set for O(1) lookups.
  # Raises error if file not found.
  #
  # @param filepath [Pathname] Path to the denied list file
  # @return [Set<String>] Set of denied domain names
  # @raise [RuntimeError] If the denied list file doesn't exist
  def _load_denied_list(filepath)
    _ensure_file_exists(filepath, 'Denied list')
    Plist.load_denied_list(filepath)
  end

  private_class_method :_load_denied_list

  # Loads the excluded keys file into a hash mapping domains to patterns.
  # Raises error if file not found.
  #
  # @param filepath [Pathname] Path to the excluded keys file
  # @return [Hash<String, String>] Domain -> newline-separated pattern string
  # @raise [RuntimeError] If the excluded keys file doesn't exist
  def _load_excluded_keys(filepath)
    _ensure_file_exists(filepath, 'Excluded keys')
    Plist.load_excluded_keys(filepath)
  end

  private_class_method :_load_excluded_keys

  # Validates that a required file exists, raising error if not.
  #
  # @param filepath [Pathname] Path to validate
  # @param description [String] Description for error message
  # @return [void]
  # @raise [RuntimeError] If file doesn't exist
  # :reek:UtilityFunction -- Stateless validation helper (correct design)
  def _ensure_file_exists(filepath, description)
    Logging.error("#{description} file not found: '#{filepath.cyan}'") unless filepath.file?
  end

  private_class_method :_ensure_file_exists

  # Loads the domains list file, filtering out denied domains.
  # Raises error if file not found.
  #
  # @param filepath [Pathname] Path to the domains list file
  # @param denied [Set<String>] Set of denied domain names to filter out
  # @return [Set<String>] Set of allowed domain names
  # @raise [RuntimeError] If the domains list file doesn't exist
  # :reek:UtilityFunction -- Stateless delegation wrapper (correct design)
  def _load_domains_list(filepath, denied)
    Logging.error("Domains list file not found: '#{filepath.cyan}'") unless filepath.file?
    Plist.load_domains_list(filepath, denied)
  end

  private_class_method :_load_domains_list

  # Exports (or imports) the default-application handlers to/from +file+. Importing them
  # means a freshly installed browser (e.g. Zen) does not ask to become the default
  # browser on first launch.
  #
  # @param file [Pathname] Handlers plist inside the defaults backup folder
  # @return [void]
  def _sync_default_app_handlers(file)
    if _exporting?
      Logging.record_warning('Failed to export default application handlers') unless LaunchServices.export_handlers(file)
    elsif file?(file)
      Logging.record_warning('Failed to import default application handlers') unless LaunchServices.import_handlers(file)
    else
      Logging.debug 'Skipping import of default application handlers -- no exported plist found'
    end
  end

  private_class_method :_sync_default_app_handlers

  # Returns true if the current operation is 'export' (memoized).
  # Caches the result to avoid repeated string comparisons.
  #
  # @return [Boolean] true if @operation is 'export'
  def _exporting?
    @_exporting ||= @operation == 'export'
  end

  private_class_method :_exporting?

  # Returns true if the current operation is 'import' (memoized).
  # Caches the result to avoid repeated string comparisons.
  #
  # @return [Boolean] true if @operation is 'import'
  def _importing?
    @_importing ||= @operation == 'import'
  end

  private_class_method :_importing?

  # Builds and emits a single user_action listing every running user-visible app
  # that needs to be quit and restarted to pick up the just-imported preferences.
  # Only user-specified apps are considered. Login-item apps are excluded because
  # kill/restart_login_item_apps already handles them.
  #
  # @return [void]
  def _notify_apps_needing_restart
    running = APPS_NEEDING_RESTART.select do |proc_name, display_name|
      # Skip login-item apps (auto-killed and restarted) and apps not currently running
      !MacOS::LOGIN_ITEM_APPS.include?(display_name) &&
        CommandUtils.run_silent('pgrep', '-xq', proc_name)
    end.values.sort

    return if nil_or_empty?(running)

    Logging.user_action "Quit and restart to pick up imported preferences: #{running.join(', ').yellow}."
  end

  private_class_method :_notify_apps_needing_restart
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = {}
  parser = CliParser.parse('[options]') do |opts|
    opts.separator 'Export or import macOS application preferences to/from the dotfiles repo.'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('-e', '--export', 'Export preferences from current system to dotfiles repo') do
      options[:export] = true
    end
    opts.on('-i', '--import', 'Import preferences from dotfiles repo to current system') do
      options[:import] = true
    end
    opts.on('-f', '--find SEARCH', 'Append every preference domain whose name contains SEARCH (case-insensitive)',
            '  to the allowed list; domains on the denied list are skipped with a warning') do |search|
      options[:find] = search
    end
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -e"
    opts.separator "      #{File.basename(__FILE__).cyan} -f ghostty"
  end

  parser.abort_with_usage('Options -e, -i and -f are mutually exclusive') if options.size > 1
  parser.abort_with_usage('Must specify one of -e (export), -i (import) or -f (find and append)') if options.empty?

  Logging.run_script do
    operation = options[:export] ? 'export' : 'import'
    success = options[:find] ? CapturePrefs.find_and_append(search: options[:find]) : CapturePrefs.run(operation: operation)
    exit(success ? 0 : 1)
  end
end
