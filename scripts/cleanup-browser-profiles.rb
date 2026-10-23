#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/cleanup-browser-profiles.rb
#
# Cleans up browser profile folders by vacuuming SQLite databases larger than
# 10 MB and deleting known cache/session files. Skips processing if the target
# browser is currently running.
#
# Usage:
#   Standalone: cleanup-browser-profiles.rb [-n]
#   Module:     CleanupBrowserProfiles.run(dry_run: false)

require 'find'
require 'pathname'

require_relative 'utilities/command_utils'
require_relative 'utilities/core'
require_relative 'utilities/env_vars'
require_relative 'utilities/logging'
require_relative 'utilities/macos'
require_relative 'utilities/path_utils'
require_relative 'utilities/sqlite'
require_relative 'utilities/string_ext'

# Cleans up browser profile folders by vacuuming SQLite databases and deleting caches.
# Returns true on success (all profiles processed), false if any errors occurred.
module CleanupBrowserProfiles
  extend self
  # nil_or_empty? comes from Core; without it the module raises NoMethodError when required as a
  # library (only the CLI block's top-level 'include Logging' made it global).
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # TODO: Combine all arrays into a single array with each element having named keys
  # Exact process names (what `pgrep -x` matches -- the executable's file name, which is not
  # always the display name) per browser key. Zen ships as 'Twilight.app' but runs as 'zen'.
  BROWSER_PROCESS_NAMES = {
    'brave' => ['Brave Browser', 'Brave Browser Beta', 'Brave Browser Nightly'],
    'chrome' => ['Google Chrome', 'Google Chrome Beta', 'Google Chrome Canary', 'Chromium'],
    'firefox' => %w[firefox],
    'thunderbird' => %w[thunderbird],
    'zen' => %w[zen]
  }.freeze

  BROWSER_PROFILES = {
    'brave' => EnvVars::PERSONAL_PROFILES_DIR.join('BraveProfile'),
    'chrome' => EnvVars::PERSONAL_PROFILES_DIR.join('ChromeProfile'),
    'firefox' => EnvVars::PERSONAL_PROFILES_DIR.join('FirefoxProfile'),
    'thunderbird' => EnvVars::PERSONAL_PROFILES_DIR.join('ThunderbirdProfile'),
    'zen' => EnvVars::PERSONAL_PROFILES_DIR.join('ZenProfile')
  }.freeze

  # SQLite databases larger than this are vacuumed.
  MIN_VACUUM_DB_BYTES = 10 * 1024 * 1024

  # Characters that make a cleanup pattern a glob rather than a literal name.
  GLOB_CHARS = /[*?\[{]/.freeze

  # Matching flags equal to the old per-pattern Dir.glob(profile/**/pattern, FNM_CASEFOLD) calls:
  # case-insensitive, and a leading '.' in a name is matched only by a pattern that spells it out
  # (no FNM_DOTMATCH), exactly like Dir.glob.
  MATCH_FLAGS = File::FNM_CASEFOLD | File::FNM_EXTGLOB

  # Cleans up browser profile folders.
  #
  # @param dry_run [Boolean] Show what would be done without doing it
  # @return [Boolean] true on success, false if any errors occurred
  # :reek:UtilityFunction -- Module method pattern for dual-mode script (see ruby-scripting.md)
  # :reek:FeatureEnvy -- Private helpers operate on local variables (intentional extraction)
  def run(dry_run: false)
    Logging.info 'Running in DRY-RUN mode -- no changes will be made' if dry_run

    # Read once -- these patterns are the same for every browser profile, so reading them
    # inside the per-profile loop would re-read the same two files from disk on every iteration.
    file_patterns = _read_pattern_file(EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup-browser-files.txt'))
    dir_patterns = _read_pattern_file(EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup-browser-dirs.txt'))

    BROWSER_PROFILES.each do |browser_name, profile_dir|
      _vacuum_browser_profile_dir(browser_name, profile_dir, file_patterns: file_patterns, dir_patterns: dir_patterns, dry_run: dry_run)
    end

    true
  end

  # Reads non-blank, non-comment lines from +file+ into an Array.
  #
  # @param file [Pathname] Path to the pattern file
  # @return [Array<String>] Non-blank, non-comment lines, stripped
  # :reek:UtilityFunction -- Stateless file reader (correct design)
  def _read_pattern_file(file)
    return [] unless file.file?

    # Use Core.read_lines_utf8 to avoid encoding issues in non-UTF-8 environments.
    Core.read_lines_utf8(file).each_with_object([]) do |line, arr|
      arr << line.chomp.strip unless line.comment_or_empty?
    end
  end

  private_class_method :_read_pattern_file

  # Returns true if the named browser is currently running. One exact-name pgrep for all of
  # the browser's process names; a substring match (pgrep -f) would also hit every unrelated
  # process whose command line merely mentions e.g. 'zen'.
  #
  # @param browser_name [String] Key of BROWSER_PROCESS_NAMES
  # @return [Boolean] true if a matching process is running
  def _browser_running?(browser_name)
    MacOS.running_processes(BROWSER_PROCESS_NAMES.fetch(browser_name, [browser_name])).any?
  end

  private_class_method :_browser_running?

  # Returns true if the profile should be skipped (browser running or dir missing).
  #
  # @param browser_name [String] Key of BROWSER_PROCESS_NAMES used for the running check.
  # @param profile_dir [Pathname] Root of the browser profile directory.
  # @return [Boolean] true if the profile should be skipped
  # :reek:FeatureEnvy -- Operates on method parameters (intentional helper extraction)
  def _should_skip_profile?(browser_name, profile_dir)
    if _browser_running?(browser_name)
      Logging.user_action "Shutdown '#{browser_name.yellow}' first before we can process it"
      return true
    end

    unless profile_dir.directory?
      Logging.info "Skipping '#{profile_dir.cyan}' -- directory does not exist"
      return true
    end

    false
  end

  private_class_method :_should_skip_profile?

  # Walks +profile_dir+ once and sorts every entry into the SQLite databases and the items the
  # cleanup patterns select. Replaces one recursive Dir.glob per pattern (about 30 full-tree
  # walks per profile) with a single Find walk; the result sets are the same as the globs gave:
  #   * names are matched case-insensitively against the patterns (SQLite files: case-sensitive
  #     '*.sqlite'), a leading '.' needs a pattern that spells it out
  #   * hidden directories are listed (when they match) but never descended into
  #   * symlinked directories are not followed
  #   * file patterns match files and directories, dir patterns only directories
  #
  # @param profile_dir [Pathname] Root of the browser profile directory.
  # @param file_patterns [Array<String>] Name patterns (globs) to delete.
  # @param dir_patterns [Array<String>] Name patterns (globs) of directories to delete.
  # @return [Array(Array<String>, Array<String>)] SQLite database paths, and the paths to delete
  #   (file-pattern matches first, then directory-pattern matches, without duplicates)
  # :reek:FeatureEnvy -- Operates on method parameters and local variables (intentional helper extraction)
  def _scan_profile(profile_dir, file_patterns, dir_patterns)
    file_literals, file_globs = _split_patterns(file_patterns)
    dir_literals, dir_globs = _split_patterns(dir_patterns)
    root = profile_dir.to_s
    sqlite_files = []
    file_matches = []
    dir_matches = []

    Find.find(root) do |path|
      next if path == root

      name = File.basename(path)
      is_dir = File.directory?(path)
      sqlite_files << path if File.fnmatch('*.sqlite', name)
      file_matches << path if _name_matches?(name, file_literals, file_globs)
      dir_matches << path if is_dir && _name_matches?(name, dir_literals, dir_globs)
      Find.prune if is_dir && name.start_with?('.')
    end

    [sqlite_files, (file_matches + dir_matches).uniq]
  end

  private_class_method :_scan_profile

  # Splits patterns into literal names (compared case-insensitively through a Hash lookup) and
  # real globs (File.fnmatch), so most of the ~30 patterns cost one lookup per entry.
  #
  # @param patterns [Array<String>]
  # @return [Array(Hash<String,true>, Array<String>)] downcased literal names, glob patterns
  def _split_patterns(patterns)
    literals, globs = patterns.partition { |pattern| !pattern.match?(GLOB_CHARS) }
    [literals.each_with_object({}) { |name, set| set[name.downcase] = true }, globs]
  end

  private_class_method :_split_patterns

  # @param name [String] An entry's base name
  # @return [Boolean] whether it equals a literal (any case) or matches a glob
  def _name_matches?(name, literals, globs)
    literals.key?(name.downcase) || globs.any? { |glob| File.fnmatch(glob, name, MATCH_FLAGS) }
  end

  private_class_method :_name_matches?

  # Vacuums all SQLite databases in +sqlite_files+ larger than 10MB.
  #
  # @param sqlite_files [Array<String>] Database paths found by _scan_profile.
  # @param dry_run [Boolean] When true, reports what would be vacuumed without doing it.
  # @return [void]
  # :reek:FeatureEnvy -- Operates on method parameters and local variables (intentional helper extraction)
  def _vacuum_sqlite_databases(sqlite_files, dry_run)
    unless SQLite.available?
      Logging.skip_tool(SQLite::COMMAND)
      return
    end

    db_count = 0
    vacuumed = 0
    failed_dbs = []

    sqlite_files.each do |db_file_str|
      db_count += 1
      db_size = PathUtils.size_kb(db_file_str)
      next if db_size <= MIN_VACUUM_DB_BYTES

      db_file_colored = db_file_str.cyan

      if dry_run
        Logging.info "Would vacuum: '#{db_file_colored}' (#{(db_size / 1_048_576).to_s.purple}MB)"
      else
        Logging.info "Vacuuming: '#{db_file_colored}'"
        if SQLite.execute(db_file_str, 'PRAGMA journal_mode=WAL; VACUUM; REINDEX;')
          vacuumed += 1
        else
          failed_dbs << Pathname(db_file_str)
        end
      end
    end

    Logging.info "-> Processed #{vacuumed.to_s.purple} of #{db_count.to_s.purple} SQLite databases"
    Logging.record_warning("sqlite3 vacuum failed for #{failed_dbs.size.to_s.red} database(s):\n#{Logging.join_array(failed_dbs, :red)}") if failed_dbs.any?
  end

  private_class_method :_vacuum_sqlite_databases

  # Deletes the files and directories selected by the cleanup patterns.
  #
  # @param items_to_delete [Array<String>] Paths found by _scan_profile.
  # @param dry_run [Boolean] When true, reports what would be deleted without doing it.
  # @return [void]
  # :reek:FeatureEnvy -- Operates on method parameters and local variables (intentional helper extraction)
  def _delete_items(items_to_delete, dry_run)
    return if nil_or_empty?(items_to_delete)

    # Delete items (or show what would be deleted in dry-run)
    if dry_run
      max_preview_items = 20
      Logging.info 'Would delete the following files and directories:'
      puts Logging.join_array(items_to_delete.first(max_preview_items), :cyan)
      Logging.info "... and #{(items_to_delete.length - max_preview_items).to_s.purple} more items" if items_to_delete.length > max_preview_items
      return
    end

    Logging.info 'Deleting files and directories matching patterns...'
    deleted = 0
    items_to_delete.each do |path|
      path_pn = Pathname(path)
      path_pn.directory? ? path_pn.rmtree : path_pn.delete
      deleted += 1
    rescue StandardError => e
      Logging.record_warning("Failed to delete '#{path.cyan}': #{e.message}")
    end
    Logging.info "-> Deleted #{deleted.to_s.purple} items"
  end

  private_class_method :_delete_items

  # Vacuums SQLite databases larger than 10 MB and deletes known cache/session
  # files from +profile_dir+. Skips if the browser process is running.
  #
  # @param browser_name   [String] Process name used for the pgrep check.
  # @param profile_dir [Pathname, String] Root of the browser profile directory.
  # @param file_patterns [Array<String>] File glob patterns to delete (read once by caller).
  # @param dir_patterns  [Array<String>] Directory glob patterns to delete (read once by caller).
  # @param dry_run        [Boolean] When true, reports actions without performing them.
  # @return [void]
  def _vacuum_browser_profile_dir(browser_name, profile_dir, file_patterns:, dir_patterns:, dry_run:)
    profile_dir = Pathname(profile_dir)
    profile_dir_colored = profile_dir.cyan

    return if _should_skip_profile?(browser_name, profile_dir)

    Logging.with_step('vacuum', "#{'Vacuuming'.yellow} '#{browser_name.yellow}' in '#{profile_dir_colored}'...") do
      # Measure size before cleanup (only for actual runs)
      unless dry_run
        size_before_kb = PathUtils.size_kb(profile_dir)
        Logging.info "--> Size before: '#{profile_dir_colored}' --> #{PathUtils.format_size(size_before_kb).purple}"
      end

      # One walk finds both the SQLite databases and the files/directories matching cleanup patterns
      sqlite_files, items_to_delete = _scan_profile(profile_dir, file_patterns, dir_patterns)

      # Vacuum SQLite databases
      _vacuum_sqlite_databases(sqlite_files, dry_run)

      # Delete files/directories matching cleanup patterns
      _delete_items(items_to_delete, dry_run)

      # Report space savings (only for actual runs)
      unless dry_run
        size_after_kb = PathUtils.size_kb(profile_dir)
        Logging.info "--> Size after: '#{profile_dir_colored}' --> #{PathUtils.format_size(size_after_kb).purple}"
        Logging.info "-> Space saved: #{PathUtils.format_size(size_before_kb - size_after_kb).purple}"
      end

      Logging.success "Successfully processed profile dir for '#{browser_name.yellow}'"
    end
  end

  private_class_method :_vacuum_browser_profile_dir
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = { dry_run: false }
  CliParser.parse('[options]') do |opts|
    opts.separator 'Cleans up browser profile folders (vacuums SQLite DBs, deletes caches).'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('-n', '--dry-run', 'Show what would be done without doing it') { options[:dry_run] = true }
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -n"
  end

  Logging.run_script(nil, 'Finished cleaning up browser profiles') do
    success = CleanupBrowserProfiles.run(dry_run: options[:dry_run])
    exit(success ? 0 : 1)
  end
end
