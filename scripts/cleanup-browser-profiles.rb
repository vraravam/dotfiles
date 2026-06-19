#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/cleanup-browser-profiles.rb
#
# Cleans up browser profile folders by vacuuming SQLite databases larger than
# 10 MB and deleting known cache/session files. Skips processing if the target
# browser is currently running.
#
# Usage:
#   Standalone: cleanup-browser-profiles.rb [-n]
#   Module:     CleanupBrowserProfiles.run(dry_run: false)

require 'open3'

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
  def run(dry_run: false)
    Logging.info 'Running in DRY-RUN mode -- no changes will be made' if dry_run

    browser_profiles = {
      'brave' => EnvVars::PERSONAL_PROFILES_DIR.join('BraveProfile'),
      'chrome' => EnvVars::PERSONAL_PROFILES_DIR.join('ChromeProfile'),
      'firefox' => EnvVars::PERSONAL_PROFILES_DIR.join('FirefoxProfile'),
      'thunderbird' => EnvVars::PERSONAL_PROFILES_DIR.join('ThunderbirdProfile'),
      'zen' => EnvVars::PERSONAL_PROFILES_DIR.join('ZenProfile')
    }

    browser_profiles.each do |browser_name, profile_dir|
      _vacuum_browser_profile_dir(browser_name, profile_dir, dry_run: dry_run)
    end

    true
  end

  # Reads non-blank, non-comment lines from +file+ into an Array.
  # Mirrors _read_pattern_file from the shell version.
  def _read_pattern_file(file)
    return [] unless file.file?
    file.readlines.each_with_object([]) do |line, arr|
      arr << line.chomp.strip unless line.comment_or_empty?
    end
  end

  private_class_method :_read_pattern_file

  # Returns true if the named browser process is currently running.
  # Mirrors pgrep check from shell version.
  def _browser_running?(browser_name)
    system('pgrep', '-i', '-f', '-q', browser_name, out: File::NULL, err: File::NULL)
  end

  private_class_method :_browser_running?

  # Converts kilobytes to bytes.
  # @param kb [Integer] Size in kilobytes
  # @return [Integer] Size in bytes
  def _kb_to_bytes(kb)
    kb * 1024
  end

  private_class_method :_kb_to_bytes

  # Converts megabytes to bytes.
  # @param mb [Integer] Size in megabytes
  # @return [Integer] Size in bytes
  def _mb_to_bytes(mb)
    mb * 1024 * 1024
  end

  private_class_method :_mb_to_bytes

  # Converts bytes to megabytes.
  # @param bytes [Integer] Size in bytes
  # @return [Integer] Size in megabytes
  def _bytes_to_mb(bytes)
    bytes / 1_048_576
  end

  private_class_method :_bytes_to_mb

  # Converts KB to human-readable format.
  # @param kb [Integer] Size in kilobytes
  # @return [String] Human-readable size (e.g., "1.5G", "234M")
  def _format_size(kb)
    if PathUtils.command_exists?('numfmt')
      size_human, = Open3.capture3('numfmt', '--to=iec', _kb_to_bytes(kb).to_s)
      size_human.chomp
    else
      "#{kb}K"
    end
  end

  private_class_method :_format_size

  # Returns true if the profile should be skipped (browser running or dir missing).
  def _should_skip_profile?(browser_name, profile_dir)
    if _browser_running?(browser_name)
      Logging.user_action "Shutdown '#{browser_name.yellow}' first -- skipping processing for '#{browser_name.yellow}'"
      return true
    end

    unless profile_dir.directory?
      Logging.info "Skipping '#{profile_dir.to_s.cyan}' -- directory does not exist"
      return true
    end

    false
  end

  private_class_method :_should_skip_profile?

  # Vacuums all SQLite databases in the profile dir larger than 10MB.
  def _vacuum_sqlite_databases(profile_dir, dry_run)
    return unless PathUtils.command_exists?('sqlite3')

    min_db_size = _mb_to_bytes(10)
    db_count = 0
    vacuumed = 0
    failed_dbs = []

    PathUtils.glob_pathnames(profile_dir.join('**', '*.sqlite')) do |db_file|
      db_count += 1
      db_size = db_file.size rescue 0
      next if db_size <= min_db_size

      if dry_run
        size_mb = _bytes_to_mb(db_size)
        Logging.info "[DRY-RUN] Would vacuum: '#{db_file.to_s.cyan}' (#{size_mb.to_s.purple}MB)"
      else
        Logging.info "Vacuuming: '#{db_file.to_s.cyan}'"
        if system('sqlite3', db_file.to_s, 'PRAGMA journal_mode=WAL; VACUUM; REINDEX;', out: File::NULL, err: File::NULL)
          vacuumed += 1
        else
          failed_dbs << db_file
        end
      end
    end

    Logging.info "-> Processed #{vacuumed.to_s.purple} of #{db_count.to_s.purple} SQLite databases"
    if failed_dbs.any?
      # Apply red color to each path, then format as bulleted list
      colored_paths = failed_dbs.map { |f| "'#{f.to_s.red}'" }
      Logging.record_warning("sqlite3 vacuum failed for #{failed_dbs.size.to_s.red} database(s):\n#{Logging.join_array(colored_paths)}")
    end
  end

  private_class_method :_vacuum_sqlite_databases

  # Finds and deletes files and directories matching cleanup patterns.
  def _delete_items(profile_dir, file_patterns, dir_patterns, dry_run)
    # Find all items to delete
    items_to_delete = []

    unless nil_or_empty?(file_patterns)
      file_patterns.each do |pattern|
        items_to_delete.concat(Dir.glob(profile_dir.join('**', pattern), File::FNM_CASEFOLD))
      end
    end

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
      Logging.info '[DRY-RUN] Would delete the following files and directories:'
      items_to_delete.first(max_preview_items).each { |p| puts "  '#{p.cyan}'" }
      Logging.info "... and #{(items_to_delete.length - max_preview_items).to_s.purple} more items" if items_to_delete.length > max_preview_items
      return
    end

    Logging.info 'Deleting files and directories matching patterns...'
    deleted = 0
    items_to_delete.each do |path|
      begin
        path_pn = Pathname.new(path)
        path_pn.directory? ? path_pn.rmtree : path_pn.delete
        deleted += 1
      rescue StandardError => e
        Logging.record_warning("Failed to delete '#{path.cyan}': #{e.message}")
      end
    end
    Logging.info "-> Deleted #{deleted.to_s.purple} items"
  end

  private_class_method :_delete_items

  # Vacuums SQLite databases larger than 10 MB and deletes known cache/session
  # files from +profile_dir+. Skips if the browser process is running.
  #
  # @param browser_name   [String] Process name used for the pgrep check.
  # @param profile_dir [Pathname, String] Root of the browser profile directory.
  # @param dry_run        [Boolean] When true, reports actions without performing them.
  def _vacuum_browser_profile_dir(browser_name, profile_dir, dry_run:)
    profile_dir = Pathname.new(profile_dir) unless profile_dir.is_a?(Pathname)
    file_patterns = _read_pattern_file(EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup-browser-files.txt'))
    dir_patterns = _read_pattern_file(EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup-browser-dirs.txt'))

    return if _should_skip_profile?(browser_name, profile_dir)

    Logging.with_step('vacuum', "#{'Vacuuming'.yellow} '#{browser_name.yellow}' in '#{profile_dir.to_s.cyan}'...") do
      # Measure size before cleanup (only for actual runs)
      size_before_kb = 0
      unless dry_run
        size_before_kb = PathUtils.dir_size_kb(profile_dir)
        Logging.info "--> Size before: '#{profile_dir.to_s.cyan}' --> #{_format_size(size_before_kb)}"
      end

      # Vacuum SQLite databases
      _vacuum_sqlite_databases(profile_dir, dry_run)

      # Find and delete files/directories matching cleanup patterns
      _delete_items(profile_dir, file_patterns, dir_patterns, dry_run)

      # Report space savings (only for actual runs)
      unless dry_run
        size_after_kb = PathUtils.dir_size_kb(profile_dir)
        Logging.info "--> Size after: '#{profile_dir.to_s.cyan}' --> #{_format_size(size_after_kb)}"
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
  parser = CliParser.parse('[options]') do |opts|
    opts.separator 'Cleans up browser profile folders (vacuums SQLite DBs, deletes caches).'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('-n', '--dry-run', 'Show what would be done without doing it') { options[:dry_run] = true }
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} -n"
  end

  Logging.run_script(File.basename(__FILE__, '.rb'), 'Finished cleaning up browser profiles') do
    success = CleanupBrowserProfiles.run(dry_run: options[:dry_run])
    exit(success ? 0 : 1)
  end
end
