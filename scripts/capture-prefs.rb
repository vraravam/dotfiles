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
#
# The per-domain `defaults` calls run on a small thread pool (CAPTURE_PREFS_JOBS, default 6,
# 1 = serial); results are collected per domain and logged in the allowed list's order from the
# calling thread. DOTFILES_APPS_BRACKETED=1 means a caller already suspended the software-update
# schedule, stopped the login-item apps and will reload the preference services (see
# PreferencesRestore): this script then does none of that itself.

require 'pathname'
require 'set'

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
  # nil_or_empty? and file? come from Core. Without this the module works only as a script (the CLI
  # block's top-level 'include Logging' makes them global) and raises NoMethodError when it is
  # required as a library, e.g. by PreferencesRestore.
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

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

  # Records when this machine last exported its preferences (the file's mtime). PreferencesRestore
  # compares it with the age of the backup in the home repo, to tell a backup pulled from another
  # machine from one this machine wrote. The name contains 'stamp' so delete_caches keeps it.
  EXPORT_STAMP_NAME = 'capture-prefs-export-stamp'

  # Public API method: the folder inside the personal configs that holds the backed-up plists.
  #
  # @return [Pathname]
  def defaults_dir
    EnvVars::PERSONAL_CONFIGS_DIR.join('defaults')
  end

  # When this machine last exported its preferences successfully.
  #
  # @return [Time, nil] nil when it never did (or the record is gone)
  def last_export_time
    stamp = EnvVars::XDG_CACHE_HOME.join(EXPORT_STAMP_NAME)
    stamp.file? ? stamp.mtime : nil
  end

  # Public API method.
  #
  # @param operation [String] Either 'export' or 'import'
  # @param manage_apps [Boolean] Whether this run suspends the software-update schedule, stops and
  #   restarts the login-item apps and reloads the preference services itself. False when a caller
  #   already brackets the work (the default follows DOTFILES_APPS_BRACKETED).
  # @return [Boolean] true on success, false on error
  # :reek:UtilityFunction -- Uses instance variable @operation for memoized helpers
  def run(operation:, manage_apps: !EnvVars.set?('DOTFILES_APPS_BRACKETED'))
    Logging.error "Invalid operation: '#{operation.to_s.yellow}'. Must be 'export' or 'import'." unless %w[export import].include?(operation)

    @operation = operation
    @manage_apps = manage_apps

    # Extract constants used multiple times
    dotfiles_dir = EnvVars::DOTFILES_DIR

    # Validate required env vars. PERSONAL_CONFIGS_DIR does not need to already
    # exist (target_dir below creates it via ensure_directories_exist -- a fresh
    # install running this for the first time legitimately won't have it yet).
    Logging.error "DOTFILES_DIR not found: '#{dotfiles_dir.cyan}'" unless dotfiles_dir.directory?

    target_dir = defaults_dir
    PathUtils.ensure_directories_exist(target_dir)

    return _process(target_dir) unless manage_apps

    # Suspend the automatic software update schedule so background update
    # activity cannot interfere with plist reads/writes during export or import.
    # Resumed in the 'ensure' below on every exit path (normal, error, exception). Deliberately not
    # 'at_exit': that fires only when the whole process ends, which is far too late when this runs
    # in-process (see PreferencesRestore) and would stack a new hook on every call.
    MacOS.suspend_softwareupdate_schedule
    restart_apps = false
    begin
      # Kill/restart login-item apps on import only, and only when running interactively.
      # On import, apps must be stopped before writing so they cannot overwrite imported
      # values when they quit. Cron skips this -- killall would disrupt the user's running
      # session, and 'open -a' would re-launch apps mid-session. On export, macOS cfprefsd
      # has already flushed current prefs to disk; killing apps is unnecessary.
      if _importing? && Core.running_in_tty?
        MacOS.kill_login_item_apps
        restart_apps = true
      end

      _process(target_dir)
    ensure
      # Reverse order of the set-up: the apps first, then the schedule.
      MacOS.restart_login_item_apps if restart_apps
      MacOS.resume_softwareupdate_schedule
    end
  end

  # The work of #run between its set-up and its clean-up: clears the old backup on an export, then
  # exports or imports every allowed domain and the default-application handlers, and commits the
  # export or reloads the imported preferences.
  #
  # @param target_dir [Pathname] The 'defaults' folder inside the personal configs backup
  # @return [Boolean] true on success
  def _process(target_dir)
    if _exporting?
      # Clean up old files before exporting new ones (also handles removed domains)
      target_dir.glob('*.plist').each(&:unlink)
    end

    # Load data files (each must exist)
    denied = Plist.load_denied_list(_require_file(DENIED_LIST_FILE, 'Denied list'))
    excluded_by_domain = Plist.load_excluded_keys(_require_file(EXCLUDED_KEYS_FILE, 'Excluded keys'))
    domains = Plist.load_domains_list(_require_file(ALLOWED_LIST_FILE, 'Domains list'), denied)

    if nil_or_empty?(domains)
      Logging.info 'No domains found -- nothing to do.'
      return true
    end

    Logging.info "Running operation: '#{@operation.yellow}'"
    saved_count = _process_domains(domains.to_a, target_dir, excluded_by_domain)

    _sync_default_app_handlers(target_dir.join(LAUNCH_SERVICES_FILE_NAME))

    # Post-processing
    if _exporting?
      commit_failed = false
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
              commit_failed = true
              Logging.record_warning 'Failed to commit backup -- the backup in the home repo is not up to date'
            end
          end
        end
        _record_export_time unless commit_failed
        Logging.success "Export complete. Staged changes in '#{target_dir.cyan}'."
      rescue RuntimeError => e
        Logging.record_warning "Skipping git add -- #{e.message}"
      end
    else
      # Reload system services so imported preferences take effect immediately (a bracketing
      # caller does that once, after everything it wrote)
      if @manage_apps
        MacOS.reload_macos_prefs
        Logging.success 'System services reloaded -- most imported settings are now active.'
      end
      _notify_apps_needing_restart
    end

    saved_msg = _exporting? ? " -- #{saved_count.to_s.purple} files saved after stripping" : ''
    Logging.success "Operation finished. Processed #{domains.length.to_s.purple} domains (denied-list entries filtered at load time)#{saved_msg}."
    true
  end

  # Exports or imports every domain in +domains+ on a pool of CAPTURE_PREFS_JOBS threads and logs
  # the outcomes, in the order of +domains+, from this thread (Logging keeps process-global state,
  # so the workers never log).
  #
  # @param domains [Array<String>]
  # @param target_dir [Pathname] The 'defaults' backup folder
  # @param excluded_by_domain [Hash<String,Array<String>>]
  # @return [Integer] How many files an export kept (0 for an import)
  def _process_domains(domains, target_dir, excluded_by_domain)
    exporting = _exporting?
    results = parallel_map(domains, EnvVars.capture_prefs_jobs) do |app_pref|
      target_file = target_dir.join("#{app_pref}.plist")
      exporting ? _export_domain(app_pref, target_file, excluded_by_domain) : _import_domain(app_pref, target_file, excluded_by_domain)
    end

    saved_count = 0
    domains.zip(results) do |app_pref, outcome|
      app_pref_colored = app_pref.light_cyan
      Logging.debug "Processing '#{app_pref_colored}'"
      raise outcome.error if outcome.error

      case outcome.value
      when :saved then saved_count += 1
      when :export_failed then Logging.record_warning("Failed to export '#{app_pref_colored}'")
      when :emptied then Logging.debug "Deleted empty plist for '#{app_pref_colored}' -- no keys remain after stripping"
      when :import_failed then Logging.record_warning("Failed to import '#{app_pref_colored}'")
      when :not_backed_up then Logging.debug "Skipping import of '#{app_pref_colored}' -- no exported plist found"
      end
    end
    saved_count
  end

  # Worker body of an export: exports +app_pref+ to +target_file+, strips the non-portable keys
  # and removes the file again when nothing is left. Touches only that file; never logs.
  #
  # @return [Symbol] :saved, :emptied or :export_failed
  def _export_domain(app_pref, target_file, excluded_by_domain)
    return :export_failed unless Plist.export_domain(app_pref, target_file)

    # Strip non-portable keys before staging to git
    Plist.strip_excluded_keys(app_pref, target_file, excluded_by_domain)
    return :saved if Plist.keys?(target_file)

    # Delete if stripping left an empty dict
    target_file.unlink
    :emptied
  end

  # Worker body of an import. Never logs.
  #
  # @return [Symbol] :imported, :import_failed or :not_backed_up
  def _import_domain(app_pref, target_file, excluded_by_domain)
    return :not_backed_up unless file?(target_file)

    # Strip non-portable keys in memory and feed the result to `defaults import` on stdin
    xml = Plist.stripped_xml(app_pref, target_file.read(encoding: 'UTF-8'), excluded_by_domain)
    Plist.import_xml(app_pref, xml) ? :imported : :import_failed
  end

  # Writes the record of this machine's last successful export (see EXPORT_STAMP_NAME).
  #
  # @return [void]
  def _record_export_time
    stamp = EnvVars::XDG_CACHE_HOME.join(EXPORT_STAMP_NAME)
    stamp.dirname.mkpath
    stamp.write("#{Core.current_timestamp}\n")
  rescue SystemCallError => e
    Logging.debug "Could not record the export time (#{e.message})"
  end

  private_class_method :_process_domains, :_export_domain, :_import_domain, :_record_export_time

  # Outcome of one parallel_map item: the block's value, or the exception it raised.
  Outcome = Struct.new(:value, :error)

  # Maps +items+ through the block on up to +jobs+ threads. The result array is in the order of
  # +items+ whatever order the workers finish in, and an exception raised by the block is captured
  # in its Outcome (the caller decides when to re-raise) rather than killing a worker. With one job,
  # or one item, nothing is threaded.
  #
  # @param items [Array]
  # @param jobs [Integer] Maximum number of worker threads
  # @yield [item] Must not touch process-global state such as Logging
  # @return [Array<Outcome>] One per item, in order
  def parallel_map(items, jobs, &block)
    results = Array.new(items.size)
    workers = [jobs.to_i, items.size].min
    if workers <= 1
      items.each_with_index { |item, idx| results[idx] = _outcome(item, &block) }
      return results
    end

    queue = Queue.new
    items.each_index { |idx| queue << idx }
    Array.new(workers) do
      Thread.new do
        loop do
          idx = _next_index(queue)
          break unless idx

          results[idx] = _outcome(items[idx], &block)
        end
      end
    end.each(&:join)
    results
  end

  # @param queue [Queue]
  # @return [Integer, nil] The next index to work on, nil when the queue is drained
  def _next_index(queue)
    queue.pop(true)
  rescue ThreadError
    nil
  end

  # @return [Outcome]
  def _outcome(item)
    Outcome.new(yield(item), nil)
  rescue StandardError => e
    Outcome.new(nil, e)
  end

  private_class_method :_next_index, :_outcome

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

  # Validates that a required data file exists.
  #
  # @param filepath [Pathname] Path to validate
  # @param label [String] Description for the error message
  # @return [Pathname] +filepath+
  # @raise [RuntimeError] If the file doesn't exist
  # :reek:UtilityFunction -- Stateless validation helper (correct design)
  def _require_file(filepath, label)
    Logging.error("#{label} file not found: '#{filepath.cyan}'") unless filepath.file?
    filepath
  end

  private_class_method :_require_file

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

  # Returns true if the current operation is 'export'. Not memoized: #run can be called more than
  # once in one process (an export, then an import), and a cached true would carry over.
  #
  # @return [Boolean] true if @operation is 'export'
  def _exporting?
    @operation == 'export'
  end

  private_class_method :_exporting?, :_process

  # Returns true if the current operation is 'import'. Not memoized, see _exporting?.
  #
  # @return [Boolean] true if @operation is 'import'
  def _importing?
    @operation == 'import'
  end

  private_class_method :_importing?

  # Builds and emits a single user_action listing every running user-visible app
  # that needs to be quit and restarted to pick up the just-imported preferences.
  # Only user-specified apps are considered. Login-item apps are excluded because
  # kill/restart_login_item_apps already handles them.
  #
  # @return [void]
  def _notify_apps_needing_restart
    # Skip login-item apps (auto-killed and restarted); one pgrep for the rest
    candidates = APPS_NEEDING_RESTART.reject { |_proc_name, display_name| MacOS::LOGIN_ITEM_APPS.include?(display_name) }
    running = MacOS.running_processes(candidates.keys).map { |proc_name| candidates[proc_name] }.sort

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
