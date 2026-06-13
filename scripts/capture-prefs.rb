#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/capture-prefs.rb
#
# Export or import macOS application preferences (plists) to/from the dotfiles repo.
# Handles stripping of non-portable keys, git staging on export, and system service
# reload on import.
#
# Usage:
#   capture-prefs.rb -e  # Export current prefs to git repo
#   capture-prefs.rb -i  # Import prefs from git repo to current system

$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'cli_parser'
require 'env_vars'
require 'fileutils'
require 'git_processor'
require 'logging'
require 'macos'
require 'pathname'
require 'rexml/document'
require 'set'
require 'string'
require 'tempfile'

include Logging

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Process names (pgrep -x matches) → display names for restart notification.
# Only user-specified apps; login-item apps handled by kill/restart_login_item_apps.
APPS_NEEDING_RESTART = {
  'Ghostty' => 'Ghostty',
  'iTerm2' => 'iTerm2',
  'Terminal' => 'Terminal'
}.freeze

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Aborts the script with an error message, prints summary, and exits with code 1.
# Used for fatal errors where continuing would be unsafe or meaningless.
def _abort_with_error(message, start_time)
  record_error message
  print_script_summary(start_time)
  exit(1)
end

# Loads the denied list file into a Set for O(1) lookups.
# Skips comment lines and empty lines. Aborts if file not found.
#
# @param filepath [Pathname] Path to the denied list file
# @param start_time [Integer] Script start time (for abort messages)
# @return [Set<String>] Set of denied domain names
def _load_denied_list(filepath, start_time)
  _abort_with_error("Denied list file not found: '#{filepath.to_s.cyan}'", start_time) unless filepath.file?

  denied = Set.new
  filepath.each_line do |line|
    denied.add(line.strip) unless line.comment_or_empty?
  end
  denied
end

# Loads the excluded keys file into a hash mapping domains to patterns.
# Format: <domain>|<key-or-glob-pattern> -- one entry per line.
# Converts pattern arrays to newline-separated strings for _strip_excluded_keys.
# Aborts if file not found.
#
# @param filepath [Pathname] Path to the excluded keys file
# @param start_time [Integer] Script start time (for abort messages)
# @return [Hash<String, String>] Domain → newline-separated pattern string
def _load_excluded_keys(filepath, start_time)
  _abort_with_error("Excluded keys file not found: '#{filepath.to_s.cyan}'", start_time) unless filepath.file?

  excluded_by_domain = Hash.new { |h, k| h[k] = [] }
  filepath.each_line do |line|
    next if line.comment_or_empty?
    domain, pattern = line.strip.split('|', 2).map(&:strip)
    excluded_by_domain[domain] << pattern if domain && pattern
  end
  # Convert arrays to newline-separated strings for _strip_excluded_keys
  excluded_by_domain.transform_values! { |patterns| patterns.join("\n") }
  excluded_by_domain
end

# Loads the domains list file, filtering out denied domains.
# Skips comment lines and empty lines. Aborts if file not found.
#
# @param filepath [Pathname] Path to the domains list file
# @param denied [Set<String>] Set of denied domain names to filter out
# @param start_time [Integer] Script start time (for abort messages)
# @return [Set<String>] Set of allowed domain names
def _load_domains_list(filepath, denied, start_time)
  _abort_with_error("Domains list file not found: '#{filepath.to_s.cyan}'", start_time) unless filepath.file?

  domains = Set.new
  filepath.each_line do |line|
    next if line.comment_or_empty?
    domain = line.strip
    domains.add(domain) unless denied.include?(domain)
  end
  domains
end

# Returns true if the current operation is 'export' (memoized).
# Caches the result to avoid repeated string comparisons.
def _exporting?
  @_exporting ||= @operation == 'export'
end

# Returns true if the current operation is 'import' (memoized).
# Caches the result to avoid repeated string comparisons.
def _importing?
  @_importing ||= @operation == 'import'
end

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

  return if running.empty?

  user_action "Quit and restart to pick up imported preferences: #{running.join(', ')}."
end

# Strips non-portable keys from a plist file in-place.
# Reads patterns from excluded_by_domain hash.
# Uses REXML to enumerate top-level keys and delete matched key-value pairs.
# Individual key deletions are non-fatal -- a missing key is silently skipped.
#
# @param domain [String] The preference domain (e.g., 'com.apple.Finder')
# @param plist_file [Pathname] Path to the plist file to modify
# @param excluded_by_domain [Hash] Domain → newline-separated patterns
# @return [void]
def _strip_excluded_keys(domain, plist_file, excluded_by_domain)
  # Merge domain-specific patterns with global '*' patterns (applied to every domain)
  combined = []
  combined.concat(excluded_by_domain[domain].split("\n")) if excluded_by_domain.key?(domain)
  combined.concat(excluded_by_domain['*'].split("\n")) if excluded_by_domain.key?('*')
  return if combined.empty?

  # Load and parse the plist
  doc = REXML::Document.new(plist_file.read) rescue return
  dict = doc.root.elements['dict']
  return unless dict

  # Delete matched key-value pairs
  # Two independent match conditions, either of which triggers deletion:
  #   1. Key name matches a shell glob pattern (File.fnmatch, '*' matches '/' and ':')
  #   2. The value element immediately following the key is a plist <date> node.
  #      Any top-level key whose value is a plist date is inherently ephemeral
  #      (ISO 8601 timestamp written by the OS/app) -- never a portable user pref.
  #      This catches date-valued keys regardless of their name, providing a
  #      type-based safety net complementary to the name-pattern list.
  modified = false
  loop do
    children = dict.to_a.select { |e| e.is_a?(REXML::Element) }
    hit = children.each_with_index.find do |e, idx|
      next unless e.name == 'key'
      value = children[idx + 1]
      combined.any? { |p| File.fnmatch(p, e.text.to_s) } || (value && value.name == 'date')
    end
    break unless hit

    el, idx = hit
    dict.delete_element(el)
    dict.delete_element(children[idx + 1]) if children[idx + 1]
    modified = true
  end

  return unless modified

  # Write back and re-normalize to Apple XML plist format
  plist_file.write(doc.to_s)
  system('plutil', '-convert', 'xml1', plist_file.to_s, out: File::NULL, err: File::NULL)
end

private :_abort_with_error, :_load_denied_list, :_load_excluded_keys, :_load_domains_list,
        :_exporting?, :_importing?, :_notify_apps_needing_restart, :_strip_excluded_keys

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

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

@operation = options[:export] ? 'export' : 'import'

# Validate required env vars
unless EnvVars::PERSONAL_CONFIGS_DIR.directory?
  error "PERSONAL_CONFIGS_DIR not found: '#{EnvVars::PERSONAL_CONFIGS_DIR.to_s.cyan}'"
end
unless EnvVars::DOTFILES_DIR.directory?
  error "DOTFILES_DIR not found: '#{EnvVars::DOTFILES_DIR.to_s.cyan}'"
end

increment_script_depth
start_time = print_script_start

target_dir = EnvVars::PERSONAL_CONFIGS_DIR.join('defaults')
target_dir.mkpath unless target_dir.directory?

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
  # Import: warn if the backup predates the last change to osx-defaults.sh
  if GitProcessor.repo?(EnvVars::DOTFILES_DIR) && GitProcessor.repo?(EnvVars::HOME)
    dotfiles_git = GitProcessor.new(dir: EnvVars::DOTFILES_DIR)
    home_git = GitProcessor.new(dir: EnvVars::HOME)

    osx_defaults_ts = dotfiles_git.log_timestamp('scripts/osx-defaults.sh')
    backup_ts = home_git.log_timestamp(target_dir.to_s)

    if osx_defaults_ts && backup_ts && backup_ts < osx_defaults_ts
      _abort_with_error(
        "Backup predates the last change to '#{'osx-defaults.sh'.cyan}' -- some settings added since may not be present. Run '#{'osx-defaults.sh -s'.cyan}' followed by '#{'capture-prefs.rb -e'.cyan}' on the source machine to refresh the backup first.",
        start_time
      )
    end
  end
end

# Load data files (each helper validates its own file)
denied = _load_denied_list(
  EnvVars::DOTFILES_DIR.join('scripts', 'data', 'capture-prefs-denied-list.txt'),
  start_time
)
excluded_by_domain = _load_excluded_keys(
  EnvVars::DOTFILES_DIR.join('scripts', 'data', 'capture-prefs-excluded-keys.txt'),
  start_time
)
domains = _load_domains_list(
  EnvVars::DOTFILES_DIR.join('scripts', 'data', 'capture-prefs-allowed-list.txt'),
  denied,
  start_time
)

if domains.empty?
  info 'No domains found -- nothing to do.'
  print_script_summary(start_time)
  exit(0)
end

info "Running operation: '#{@operation.yellow}'"
saved_count = 0

domains.each do |app_pref|
  debug "Processing '#{app_pref.light_cyan}'"

  if _exporting?
    target_file = target_dir.join("#{app_pref}.plist")
    if system('/usr/bin/defaults', @operation, app_pref, target_file.to_s, out: File::NULL, err: File::NULL)
      # Convert binary plist to XML for human-readable diffs in git
      unless system('plutil', '-convert', 'xml1', target_file.to_s, out: File::NULL, err: File::NULL)
        record_warning("Failed to convert '#{app_pref.light_cyan}' to XML plist -- deleting binary file")
        target_file.unlink
        next
      end

      # Strip non-portable keys before staging to git
      _strip_excluded_keys(app_pref, target_file, excluded_by_domain)

      # Delete if stripping left an empty dict
      if target_file.read.match?(/<key>/)
        saved_count += 1
      else
        target_file.unlink
        debug "Deleted empty plist for '#{app_pref.light_cyan}' -- no keys remain after stripping"
      end
    else
      record_warning("Failed to export '#{app_pref.light_cyan}'")
    end
  else
    # Import
    target_file = target_dir.join("#{app_pref}.plist")
    unless target_file.file?
      debug "Skipping import of '#{app_pref.light_cyan}' -- no exported plist found"
      next
    end

    # Strip non-portable keys from a temp copy
    temp_plist = Tempfile.new(['capture-prefs-', '.plist'])
    FileUtils.cp(target_file.to_s, temp_plist.path)
    _strip_excluded_keys(app_pref, Pathname.new(temp_plist.path), excluded_by_domain)

    unless system('/usr/bin/defaults', @operation, app_pref, temp_plist.path, out: File::NULL, err: File::NULL)
      record_warning("Failed to import '#{app_pref.light_cyan}'")
    end

    temp_plist.close
    temp_plist.unlink
  end
end

# Post-processing
if _exporting?
  GitProcessor.new(dir: EnvVars::HOME) do |git|
    rel_path = git.relative_path(target_dir)
    _out, _err, status = git.add(rel_path)
    record_warning("Failed to git add '#{target_dir.to_s.cyan}'") unless status.success?
  end
  success "Export complete. Staged changes in '#{target_dir.to_s.cyan}'."
else
  # Reload system services so imported preferences take effect immediately
  MacOS.reload_macos_prefs
  success 'System services reloaded -- most imported settings are now active.'
  _notify_apps_needing_restart
end

saved_msg = _exporting? ? " -- #{saved_count.to_s.purple} files saved after stripping" : ''
success "Operation finished. Processed #{domains.length.to_s.purple} domains (denied-list entries filtered at load time)#{saved_msg}."
print_script_summary(start_time)
