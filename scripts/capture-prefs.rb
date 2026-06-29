#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/capture-prefs.rb
#
# Export or import macOS application preferences (plists) to/from the dotfiles repo.
# Handles stripping of non-portable keys, git staging on export, and system service
# reload on import.
#
# Usage:
#   Standalone: capture-prefs.rb -e  # Export current prefs to git repo
#               capture-prefs.rb -i  # Import prefs from git repo to current system
#   Module:     CapturePrefs.run(operation: 'export')  # or 'import'

require 'fileutils'
require 'pathname'
require 'tempfile'

require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/logging'
require_relative 'utilities/macos'
require_relative 'utilities/path_utils'
require_relative 'utilities/plist'
require_relative 'utilities/string'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module CapturePrefs
  extend self

  # Process names (pgrep -x matches) → display names for restart notification.
  # Only user-specified apps; login-item apps handled by kill/restart_login_item_apps.
  APPS_NEEDING_RESTART = {
    'Ghostty' => 'Ghostty',
    'iTerm2' => 'iTerm2',
    'Terminal' => 'Terminal'
  }.freeze

  # Public API method.
  #
  # @param operation [String] Either 'export' or 'import'
  # @return [Boolean] true on success, false on error
  def run(operation:)
    unless %w[export import].include?(operation)
      Logging.error "Invalid operation: '#{operation}'. Must be 'export' or 'import'."
    end

    @operation = operation

    # Validate required env vars
    unless EnvVars::PERSONAL_CONFIGS_DIR.directory?
      Logging.error "PERSONAL_CONFIGS_DIR not found: '#{EnvVars::PERSONAL_CONFIGS_DIR.to_s.cyan}'"
    end
    unless EnvVars::DOTFILES_DIR.directory?
      Logging.error "DOTFILES_DIR not found: '#{EnvVars::DOTFILES_DIR.to_s.cyan}'"
    end

    target_dir = EnvVars::PERSONAL_CONFIGS_DIR.join('defaults')
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
    if _importing? && MacOS.running_in_tty?
      MacOS.kill_login_item_apps
      at_exit { MacOS.restart_login_item_apps }
    end

    if _exporting?
      # Clean up old files before exporting new ones (also handles removed domains)
      # .defaults files are from a past version of this script -- delete them too
      target_dir.glob('*.plist').each(&:unlink)
      target_dir.glob('.plist').each(&:unlink)
      target_dir.glob('*.defaults').each(&:unlink)
    else
      # Import: warn if the backup predates the last change to osx-defaults.rb
      if GitProcessor.repo?(EnvVars::DOTFILES_DIR) && GitProcessor.repo?(EnvVars::HOME)
        dotfiles_git = GitProcessor.new(dir: EnvVars::DOTFILES_DIR)
        home_git = GitProcessor.new(dir: EnvVars::HOME)

        osx_defaults_ts = dotfiles_git.log_timestamp('scripts/osx-defaults.rb')
        backup_ts = home_git.log_timestamp(target_dir.to_s)

        # On FIRST_INSTALL, accept any backup even if outdated -- fresh-install already
        # ran osx-defaults.rb -s to baseline current prefs, so the backup import is an
        # incremental overlay. A stale backup is better than no backup on vanilla OS.
        if osx_defaults_ts && backup_ts && backup_ts < osx_defaults_ts && !EnvVars.first_install?
          Logging.error(
            "Backup predates the last change to '#{'osx-defaults.rb'.cyan}' -- some settings added since may not be present. Run '#{'osx-defaults.rb -s'.cyan}' followed by '#{'capture-prefs.rb -e'.cyan}' on the source machine to refresh the backup first."
          )
        end
      end
    end

    # Load data files (each helper validates its own file)
    denied = _load_denied_list(
      EnvVars::DOTFILES_DIR.join('scripts', 'data', 'capture-prefs-denied-list.txt')
    )
    excluded_by_domain = _load_excluded_keys(
      EnvVars::DOTFILES_DIR.join('scripts', 'data', 'capture-prefs-excluded-keys.txt')
    )
    domains = _load_domains_list(
      EnvVars::DOTFILES_DIR.join('scripts', 'data', 'capture-prefs-allowed-list.txt'),
      denied
    )

    if nil_or_empty?(domains)
      Logging.info 'No domains found -- nothing to do.'
      return true
    end

    Logging.info "Running operation: '#{@operation.yellow}'"
    saved_count = 0

    domains.each do |app_pref|
      Logging.debug "Processing '#{app_pref.light_cyan}'"

      if _exporting?
        target_file = target_dir.join("#{app_pref}.plist")
        unless Plist.export_domain(app_pref, target_file)
          Logging.record_warning("Failed to export '#{app_pref.light_cyan}'")
          next
        end

        # Strip non-portable keys before staging to git
        Plist.strip_excluded_keys(app_pref, target_file, excluded_by_domain)

        # Delete if stripping left an empty dict
        if Plist.has_keys?(target_file)
          saved_count += 1
        else
          target_file.unlink
          Logging.debug "Deleted empty plist for '#{app_pref.light_cyan}' -- no keys remain after stripping"
        end
      else
        # Import
        target_file = target_dir.join("#{app_pref}.plist")
        unless target_file.file?
          Logging.debug "Skipping import of '#{app_pref.light_cyan}' -- no exported plist found"
          next
        end

        # Strip non-portable keys from a temp copy
        temp_plist = Tempfile.new(['capture-prefs-', '.plist'])
        FileUtils.cp(target_file.to_s, temp_plist.path)
        Plist.strip_excluded_keys(app_pref, Pathname.new(temp_plist.path), excluded_by_domain)

        unless Plist.import_domain(app_pref, temp_plist.path)
          Logging.record_warning("Failed to import '#{app_pref.light_cyan}'")
        end

        temp_plist.close
        temp_plist.unlink
      end
    end

    # Post-processing
    if _exporting?
      begin
        GitProcessor.new(dir: EnvVars::HOME) do |git|
          # Git accepts absolute paths directly - no normalization needed
          _out, _err, status = git.add(target_dir)
          Logging.record_warning("Failed to git add '#{target_dir.to_s.cyan}'") unless status.success?
        end
        Logging.success "Export complete. Staged changes in '#{target_dir.to_s.cyan}'."
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

  # Loads the denied list file into a Set for O(1) lookups.
  # Raises error if file not found.
  #
  # @param filepath [Pathname] Path to the denied list file
  # @return [Set<String>] Set of denied domain names
  def _load_denied_list(filepath)
    unless filepath.file?
      Logging.error("Denied list file not found: '#{filepath.to_s.cyan}'")
    end
    Plist.load_denied_list(filepath)
  end

  private_class_method :_load_denied_list

  # Loads the excluded keys file into a hash mapping domains to patterns.
  # Raises error if file not found.
  #
  # @param filepath [Pathname] Path to the excluded keys file
  # @return [Hash<String, String>] Domain → newline-separated pattern string
  def _load_excluded_keys(filepath)
    unless filepath.file?
      Logging.error("Excluded keys file not found: '#{filepath.to_s.cyan}'")
    end
    Plist.load_excluded_keys(filepath)
  end

  private_class_method :_load_excluded_keys

  # Loads the domains list file, filtering out denied domains.
  # Raises error if file not found.
  #
  # @param filepath [Pathname] Path to the domains list file
  # @param denied [Set<String>] Set of denied domain names to filter out
  # @return [Set<String>] Set of allowed domain names
  def _load_domains_list(filepath, denied)
    unless filepath.file?
      Logging.error("Domains list file not found: '#{filepath.to_s.cyan}'")
    end
    Plist.load_domains_list(filepath, denied)
  end

  private_class_method :_load_domains_list

  # Returns true if the current operation is 'export' (memoized).
  # Caches the result to avoid repeated string comparisons.
  def _exporting?
    @_exporting ||= @operation == 'export'
  end

  private_class_method :_exporting?

  # Returns true if the current operation is 'import' (memoized).
  # Caches the result to avoid repeated string comparisons.
  def _importing?
    @_importing ||= @operation == 'import'
  end

  private_class_method :_importing?

  # Builds and emits a single user_action listing every running user-visible app
  # that needs to be quit and restarted to pick up the just-imported preferences.
  # Only user-specified apps are considered. Login-item apps are excluded because
  # kill/restart_login_item_apps already handles them.
  def _notify_apps_needing_restart
    running = APPS_NEEDING_RESTART.select do |proc_name, display_name|
      # Skip login-item apps (auto-killed and restarted) and apps not currently running
      !MacOS::LOGIN_ITEM_APPS.include?(display_name) &&
        system('pgrep', '-xq', proc_name, out: File::NULL, err: File::NULL)
    end.values.sort

    return if nil_or_empty?(running)

    Logging.user_action "Quit and restart to pick up imported preferences: #{running.join(', ')}."
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
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -e"
  end

  if options[:export] && options[:import]
    parser.abort_with_usage('Options -e and -i are mutually exclusive')
  elsif !options[:export] && !options[:import]
    parser.abort_with_usage('Must specify either -e (export) or -i (import)')
  end

  Logging.run_script(File.basename(__FILE__, '.rb')) do
    success = CapturePrefs.run(operation: options[:export] ? 'export' : 'import')
    exit(success ? 0 : 1)
  end
end
