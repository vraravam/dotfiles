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

require 'open3'

require_relative 'utilities/command_utils'
require_relative 'utilities/env_vars'
require_relative 'utilities/logging'
require_relative 'utilities/path_utils'

# Cleans up browser profile folders by vacuuming SQLite databases and deleting caches.
# Returns true on success (all profiles processed), false if any errors occurred.
module CleanupBrowserProfiles
  extend self

  # Cleans up browser profile folders.
  #
  # @param dry_run [Boolean] Show what would be done without doing it
  # @return [Boolean] true on success, false if any errors occurred
  # :reek:UtilityFunction -- Module method pattern for dual-mode script (see ruby-scripting.md)
  # :reek:FeatureEnvy -- Private helpers operate on local variables (intentional extraction)
  def run(dry_run: false)
    Logging.info 'Running in DRY-RUN mode -- no changes will be made' if dry_run

    profiles_dir = EnvVars::PERSONAL_PROFILES_DIR

    browser_profiles = {
      'brave' => profiles_dir.join('BraveProfile'),
      'chrome' => profiles_dir.join('ChromeProfile'),
      'firefox' => profiles_dir.join('FirefoxProfile'),
      'thunderbird' => profiles_dir.join('ThunderbirdProfile'),
      'zen' => profiles_dir.join('ZenProfile')
    }

    # Read once -- these patterns are the same for every browser profile, so reading them
    # inside the per-profile loop would re-read the same two files from disk on every iteration.
    file_patterns = _read_pattern_file(EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup-browser-files.txt'))
    dir_patterns = _read_pattern_file(EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup-browser-dirs.txt'))

    browser_profiles.each do |browser_name, profile_dir|
      _vacuum_browser_profile_dir(browser_name, profile_dir, file_patterns: file_patterns, dir_patterns: dir_patterns, dry_run: dry_run)
    end

    true
  end

  # Reads non-blank, non-comment lines from +file+ into an Array.
  # Mirrors _read_pattern_file from the shell version.
  # :reek:UtilityFunction -- Stateless file reader (correct design)
  def _read_pattern_file(file)
    return [] unless file.file?

    # Use Core.read_lines_utf8 to avoid encoding issues in non-UTF-8 environments.
    Core.read_lines_utf8(file).each_with_object([]) do |line, arr|
      arr << line.chomp.strip unless line.comment_or_empty?
    end
  end

  private_class_method :_read_pattern_file

  # Returns true if the named browser process is currently running.
  # Mirrors pgrep check from shell version.
  # :reek:UtilityFunction -- Stateless process check (correct design)
  def _browser_running?(browser_name)
    CommandUtils.run_silent('pgrep', '-i', '-f', '-q', browser_name)
  end

  private_class_method :_browser_running?

  # Converts kilobytes to bytes.
  # @param kb [Integer] Size in kilobytes
  # @return [Integer] Size in bytes
  # :reek:UtilityFunction -- Pure conversion function (correct design)
  def _kb_to_bytes(kb) # rubocop:disable Naming/MethodParameterName
    kb * 1024
  end

  private_class_method :_kb_to_bytes

  # Converts megabytes to bytes.
  # @param mb [Integer] Size in megabytes
  # @return [Integer] Size in bytes
  # :reek:UtilityFunction -- Pure conversion function (correct design)
  def _mb_to_bytes(mb) # rubocop:disable Naming/MethodParameterName
    mb * 1024 * 1024
  end

  private_class_method :_mb_to_bytes

  # Converts bytes to megabytes.
  # @param bytes [Integer] Size in bytes
  # @return [Integer] Size in megabytes
  # :reek:UtilityFunction -- Pure conversion function (correct design)
  def _bytes_to_mb(bytes)
    bytes / 1_048_576
  end

  private_class_method :_bytes_to_mb

  # Converts KB to human-readable format.
  # @param kb [Integer] Size in kilobytes
  # @return [String] Human-readable size (e.g., "1.5G", "234M")
  def _format_size(kb) # rubocop:disable Naming/MethodParameterName
    if PathUtils.command_exists?('numfmt')
      CommandUtils.query('numfmt', '--to=iec', _kb_to_bytes(kb).to_s)
    else
      "#{kb}K"
    end
  end

  private_class_method :_format_size

  # Returns true if the profile should be skipped (browser running or dir missing).
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

  # Vacuums all SQLite databases in the profile dir larger than 10MB.
  # :reek:FeatureEnvy -- Operates on method parameters and local variables (intentional helper extraction)
  def _vacuum_sqlite_databases(profile_dir, dry_run)
    return unless PathUtils.command_exists?('sqlite3')

    min_db_size = _mb_to_bytes(10)
    db_count = 0
    vacuumed = 0
    failed_dbs = []

    PathUtils.glob_pathnames(profile_dir.join('**', '*.sqlite')) do |db_file|
      db_count += 1
      db_size = db_file.exist? ? db_file.size : 0
      next if db_size <= min_db_size

      db_file_str = db_file.to_s
      db_file_colored = db_file_str.cyan

      if dry_run
        Logging.info "Would vacuum: '#{db_file_colored}' (#{_bytes_to_mb(db_size).to_s.purple}MB)"
      else
        Logging.info "Vacuuming: '#{db_file_colored}'"
        if CommandUtils.run_silent('sqlite3', db_file_str, 'PRAGMA journal_mode=WAL; VACUUM; REINDEX;')
          vacuumed += 1
        else
          failed_dbs << db_file
        end
      end
    end

    Logging.info "-> Processed #{vacuumed.to_s.purple} of #{db_count.to_s.purple} SQLite databases"
    Logging.record_warning("sqlite3 vacuum failed for #{failed_dbs.size.to_s.red} database(s):\n#{Logging.join_array(failed_dbs, :red)}") if failed_dbs.any?
  end

  private_class_method :_vacuum_sqlite_databases

  # Finds and deletes files and directories matching cleanup patterns.
  # :reek:FeatureEnvy -- Operates on method parameters and local variables (intentional helper extraction)
  def _delete_items(profile_dir, file_patterns, dir_patterns, dry_run)
    # Find all items to delete
    items_to_delete = []

    items_to_delete.concat(file_patterns.flat_map { |pattern| Dir.glob(profile_dir.join('**', pattern), File::FNM_CASEFOLD) }) unless nil_or_empty?(file_patterns)

    unless nil_or_empty?(dir_patterns)
      dir_patterns.each do |pattern|
        PathUtils.glob_pathnames(profile_dir.join('**', pattern), File::FNM_CASEFOLD) do |path_pn|
          items_to_delete << path_pn.to_s if path_pn.directory?
        end
      end
    end

    items_to_delete.uniq!
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
      path_pn = Pathname.new(path)
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
  def _vacuum_browser_profile_dir(browser_name, profile_dir, file_patterns:, dir_patterns:, dry_run:)
    profile_dir = Pathname.new(profile_dir) unless profile_dir.is_a?(Pathname)
    profile_dir_colored = profile_dir.cyan

    return if _should_skip_profile?(browser_name, profile_dir)

    Logging.with_step('vacuum', "#{'Vacuuming'.yellow} '#{browser_name.yellow}' in '#{profile_dir_colored}'...") do
      # Measure size before cleanup (only for actual runs)
      unless dry_run
        size_before_kb = PathUtils.dir_size_kb(profile_dir)
        Logging.info "--> Size before: '#{profile_dir_colored}' --> #{_format_size(size_before_kb)}"
      end

      # Vacuum SQLite databases
      _vacuum_sqlite_databases(profile_dir, dry_run)

      # Find and delete files/directories matching cleanup patterns
      _delete_items(profile_dir, file_patterns, dir_patterns, dry_run)

      # Report space savings (only for actual runs)
      unless dry_run
        size_after_kb = PathUtils.dir_size_kb(profile_dir)
        Logging.info "--> Size after: '#{profile_dir_colored}' --> #{_format_size(size_after_kb)}"
        Logging.info "-> Space saved: #{_format_size(size_before_kb - size_after_kb)}"
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
