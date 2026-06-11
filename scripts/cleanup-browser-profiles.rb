#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/cleanup-browser-profiles.rb
#
# Cleans up browser profile folders by vacuuming SQLite databases larger than
# 10 MB and deleting known cache/session files. Skips processing if the target
# browser is currently running.
#
# Usage: cleanup-browser-profiles.rb [-n]

$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'cli_parser'
require 'env_vars'
require 'fileutils'
require 'logging'
require 'open3'
require 'path_utils'

include Logging

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Reads non-blank, non-comment lines from +file+ into an Array.
# Mirrors _read_pattern_file from the shell version.
def _read_pattern_file(file)
  return [] unless file.file?
  file.readlines.each_with_object([]) do |line, arr|
    stripped = line.chomp.strip
    next if stripped.empty? || stripped.start_with?('#')
    arr << stripped
  end
end

# Returns true if the named browser process is currently running.
# Mirrors pgrep check from shell version.
def _browser_running?(browser_name)
  system('pgrep', '-i', '-f', '-q', browser_name, out: File::NULL, err: File::NULL)
end

# Converts kilobytes to bytes.
# @param kb [Integer] Size in kilobytes
# @return [Integer] Size in bytes
def _kb_to_bytes(kb)
  kb * 1024
end

# Converts megabytes to bytes.
# @param mb [Integer] Size in megabytes
# @return [Integer] Size in bytes
def _mb_to_bytes(mb)
  mb * 1024 * 1024
end

# Converts bytes to megabytes.
# @param bytes [Integer] Size in bytes
# @return [Integer] Size in megabytes
def _bytes_to_mb(bytes)
  bytes / 1_048_576
end

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

# Returns dir size in kilobytes.
# @param dir [Pathname, String] The dir to measure
# @return [Integer] Size in KB
def _dir_size(dir)
  du_out, = Open3.capture3('du', '-sk', dir.to_s)
  du_out.split("\t").first.to_i
end

# Returns true if the profile should be skipped (browser running or dir missing).
def _should_skip_profile?(browser_name, profile_dir)
  if _browser_running?(browser_name)
    user_action "Shutdown '#{browser_name.yellow}' first -- skipping processing for '#{browser_name.yellow}'"
    return true
  end

  unless profile_dir.directory?
    info "Skipping '#{profile_dir.to_s.cyan}' -- directory does not exist"
    return true
  end

  false
end

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
      info "[DRY-RUN] Would vacuum: '#{db_file.to_s.cyan}' (#{size_mb.to_s.purple}MB)"
    else
      info "Vacuuming: '#{db_file.to_s.cyan}'"
      if system('sqlite3', db_file.to_s, 'PRAGMA journal_mode=WAL; VACUUM; REINDEX;', out: File::NULL, err: File::NULL)
        vacuumed += 1
      else
        failed_dbs << db_file
      end
    end
  end

  info "-> Processed #{vacuumed.to_s.purple} of #{db_count.to_s.purple} SQLite databases"
  if failed_dbs.any?
    # Apply red color to each path, then format as bulleted list
    colored_paths = failed_dbs.map { |f| "'#{f.to_s.red}'" }
    record_warning("sqlite3 vacuum failed for #{failed_dbs.size.to_s.red} database(s):\n#{join_array(colored_paths)}")
  end
end

# Finds and deletes files and directories matching cleanup patterns.
def _delete_items(profile_dir, file_patterns, dir_patterns, dry_run)
  # Find all items to delete
  items_to_delete = []

  unless file_patterns.empty?
    file_patterns.each do |pattern|
      items_to_delete.concat(Dir.glob(profile_dir.join('**', pattern), File::FNM_CASEFOLD))
    end
  end

  unless dir_patterns.empty?
    dir_patterns.each do |pattern|
      PathUtils.glob_pathnames(profile_dir.join('**', pattern), File::FNM_CASEFOLD) do |path_pn|
        items_to_delete << path_pn.to_s if path_pn.directory?
      end
    end
  end

  items_to_delete.uniq!
  return if items_to_delete.empty?

  # Delete items (or show what would be deleted in dry-run)
  if dry_run
    max_preview_items = 20
    info '[DRY-RUN] Would delete the following files and directories:'
    items_to_delete.first(max_preview_items).each { |p| puts "  '#{p.cyan}'" }
    if items_to_delete.length > max_preview_items
      info "... and #{(items_to_delete.length - max_preview_items).to_s.purple} more items"
    end
    return
  end

  info 'Deleting files and directories matching patterns...'
  deleted = 0
  items_to_delete.each do |path|
    begin
      path_pn = Pathname.new(path)
      path_pn.directory? ? FileUtils.rm_rf(path_pn) : path_pn.delete
      deleted += 1
    rescue StandardError => e
      record_warning("Failed to delete '#{path.cyan}': #{e.message}")
    end
  end
  info "-> Deleted #{deleted.to_s.purple} items"
end

private :_read_pattern_file, :_browser_running?, :_kb_to_bytes, :_mb_to_bytes, :_bytes_to_mb,
        :_format_size, :_dir_size, :_should_skip_profile?, :_vacuum_sqlite_databases, :_delete_items

# Vacuums SQLite databases larger than 10 MB and deletes known cache/session
# files from +profile_dir+. Skips if the browser process is running.
#
# @param browser_name   [String] Process name used for the pgrep check.
# @param profile_dir [Pathname, String] Root of the browser profile directory.
# @param dry_run        [Boolean] When true, reports actions without performing them.
def vacuum_browser_profile_dir(browser_name, profile_dir, dry_run:)
  profile_dir = Pathname.new(profile_dir) unless profile_dir.is_a?(Pathname)
  file_patterns = _read_pattern_file(EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup-browser-files.txt'))
  dir_patterns = _read_pattern_file(EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup-browser-dirs.txt'))

  return if _should_skip_profile?(browser_name, profile_dir)

  section_header "#{'Vacuuming'.yellow} '#{browser_name.yellow}' in '#{profile_dir.to_s.cyan}'..."

  # Measure size before cleanup (only for actual runs)
  size_before_kb = 0
  unless dry_run
    size_before_kb = _dir_size(profile_dir)
    info "--> Size before: '#{profile_dir.to_s.cyan}' --> #{_format_size(size_before_kb)}"
  end

  # Vacuum SQLite databases
  _vacuum_sqlite_databases(profile_dir, dry_run)

  # Find and delete files/directories matching cleanup patterns
  _delete_items(profile_dir, file_patterns, dir_patterns, dry_run)

  # Report space savings (only for actual runs)
  unless dry_run
    size_after_kb = _dir_size(profile_dir)
    info "--> Size after: '#{profile_dir.to_s.cyan}' --> #{_format_size(size_after_kb)}"
    info "-> Space saved: #{_format_size(size_before_kb - size_after_kb)}"
  end

  success "Successfully processed profile dir for '#{browser_name.yellow}'"
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

options = { dry_run: false }
parser = CliParser.parse('[options]') do |opts|
  opts.separator 'Cleans up browser profile folders (vacuums SQLite DBs, deletes caches).'
  opts.separator ''
  opts.separator 'Options:'.purple
  opts.on('-n', '--dry-run', 'Show what would be done without doing it') { options[:dry_run] = true }
  opts.separator ''
  opts.separator "  eg: #{File.basename(__FILE__).cyan} -n"
end

increment_script_depth
start_time = print_script_start

info 'Running in DRY-RUN mode -- no changes will be made' if options[:dry_run]

browser_profiles = {
  'brave' => EnvVars::PERSONAL_PROFILES_DIR.join('BraveProfile'),
  'chrome' => EnvVars::PERSONAL_PROFILES_DIR.join('ChromeProfile'),
  'firefox' => EnvVars::PERSONAL_PROFILES_DIR.join('FirefoxProfile'),
  'thunderbird' => EnvVars::PERSONAL_PROFILES_DIR.join('ThunderbirdProfile'),
  'zen' => EnvVars::PERSONAL_PROFILES_DIR.join('ZenProfile')
}

browser_profiles.each do |browser_name, profile_dir|
  vacuum_browser_profile_dir(browser_name, profile_dir, dry_run: options[:dry_run])
end

print_script_summary(start_time, 'Finished cleaning up browser profiles')
