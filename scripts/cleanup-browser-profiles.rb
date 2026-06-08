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
  return [] unless File.file?(file)
  File.readlines(file).each_with_object([]) do |line, arr|
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

# Formats a folder size for display. Returns colorized string with tilde-substituted
# path and human-readable size. Color methods (.yellow, .cyan) handle tilde substitution
# automatically, so no manual HOME replacement is needed.
# Mirrors folder_size() shell function behavior.
def _folder_size(folder)
  du_out, = Open3.capture3('du', '-sh', folder.to_s)
  size = du_out.split("\t").first
  "#{folder.to_s.yellow} --> #{size.cyan}"
end

private :_read_pattern_file, :_browser_running?, :_folder_size

# Vacuums SQLite databases larger than 10 MB and deletes known cache/session
# files from +profile_folder+. Skips if the browser process is running.
#
# @param browser_name   [String] Process name used for the pgrep check.
# @param profile_folder [Pathname, String] Root of the browser profile directory.
# @param dry_run        [Boolean] When true, reports actions without performing them.
def vacuum_browser_profile_folder(browser_name, profile_folder, dry_run:)
  profile_folder = Pathname.new(profile_folder) unless profile_folder.is_a?(Pathname)
  file_patterns = _read_pattern_file(EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup-browser-files.txt'))
  dir_patterns = _read_pattern_file(EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup-browser-dirs.txt'))

  if _browser_running?(browser_name)
    user_action "Shutdown '#{browser_name.yellow}' first — skipping processing for #{browser_name}"
    return
  end

  unless File.directory?(profile_folder)
    info "Skipping '#{profile_folder.to_s.cyan}' — directory does not exist"
    return
  end

  section_header "#{'Vacuuming'.yellow} '#{browser_name.purple}' in '#{profile_folder.to_s.cyan}'..."

  size_out, = Open3.capture3('du', '-sk', profile_folder.to_s)
  size_before_kb = size_out.split("\t").first.to_i
  info "--> Size before: #{_folder_size(profile_folder)}"

  # -------------------------------------------------------------------
  # SQLite vacuum
  # -------------------------------------------------------------------
  if PathUtils.command_exists?('sqlite3')
    db_count = 0
    vacuumed = 0
    failed_dbs = []

    Dir.glob(File.join(profile_folder, '**', '*.sqlite')).each do |db_file|
      db_count += 1
      db_size = File.size(db_file) rescue 0
      next if db_size <= 10 * 1024 * 1024 # skip if <= 10 MB

      if dry_run
        size_mb = db_size / 1_048_576
        info "[DRY-RUN] Would vacuum: '#{db_file.yellow}' (#{size_mb}MB)"
      else
        info "Vacuuming: '#{db_file.yellow}'"
        if system('sqlite3', db_file, 'PRAGMA journal_mode=WAL; VACUUM; REINDEX;', out: File::NULL, err: File::NULL)
          vacuumed += 1
        else
          failed_dbs << db_file
        end
      end
    end

    info "  -> Processed #{vacuumed} of #{db_count} SQLite databases"
    if failed_dbs.any?
      failed_list = failed_dbs.map { |f| "    - #{f.cyan}" }.join("\n")
      record_warning("sqlite3 vacuum failed for #{failed_dbs.size} database(s):\n#{failed_list}")
    end
  end

  # -------------------------------------------------------------------
  # File and directory deletion
  # -------------------------------------------------------------------
  items_to_delete = []

  unless file_patterns.empty?
    file_patterns.each do |pattern|
      items_to_delete.concat(Dir.glob(File.join(profile_folder, '**', pattern), File::FNM_CASEFOLD))
    end
  end

  unless dir_patterns.empty?
    dir_patterns.each do |pattern|
      Dir.glob(File.join(profile_folder, '**', pattern), File::FNM_CASEFOLD).each do |path|
        items_to_delete << path if File.directory?(path)
      end
    end
  end

  items_to_delete.uniq!

  if dry_run
    info '[DRY-RUN] Would delete the following files and directories:'
    items_to_delete.first(20).each { |p| puts "  #{p.yellow}" }
    info "  ... and #{items_to_delete.length - 20} more items" if items_to_delete.length > 20
  elsif items_to_delete.any?
    info 'Deleting files and directories matching patterns...'
    deleted = 0
    items_to_delete.each do |path|
      begin
        File.directory?(path) ? FileUtils.rm_rf(path) : File.delete(path)
        deleted += 1
      rescue StandardError => e
        record_warning("Failed to delete '#{path.cyan}': #{e.message}")
      end
    end
    info "  -> Deleted #{deleted} items"
  end

  size_out, = Open3.capture3('du', '-sk', profile_folder.to_s)
  size_after_kb = size_out.split("\t").first.to_i
  info "--> Size after: #{_folder_size(profile_folder)}"

  unless dry_run
    saved_kb = size_before_kb - size_after_kb
    saved_bytes = saved_kb * 1024
    # Use numfmt if available for human-readable output
    if PathUtils.command_exists?('numfmt')
      saved_human, = Open3.capture3('numfmt', '--to=iec', saved_bytes.to_s)
      info "  -> Space saved: #{saved_human.chomp}"
    else
      info "  -> Space saved: #{saved_kb}K"
    end
  end

  success "Successfully processed profile folder for '#{browser_name.yellow}'"
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

info 'Running in DRY-RUN mode — no changes will be made' if options[:dry_run]

browser_profiles = {
  'brave' => EnvVars::PERSONAL_PROFILES_DIR.join('BraveProfile'),
  'chrome' => EnvVars::PERSONAL_PROFILES_DIR.join('ChromeProfile'),
  'firefox' => EnvVars::PERSONAL_PROFILES_DIR.join('FirefoxProfile'),
  'thunderbird' => EnvVars::PERSONAL_PROFILES_DIR.join('ThunderbirdProfile'),
  'zen' => EnvVars::PERSONAL_PROFILES_DIR.join('ZenProfile')
}

browser_profiles.each do |browser_name, profile_folder|
  vacuum_browser_profile_folder(browser_name, profile_folder, dry_run: options[:dry_run])
end

print_script_summary(start_time, 'Finished cleaning up browser profiles')
