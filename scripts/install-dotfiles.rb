#!/usr/bin/env ruby

# frozen_string_literal: true

# This script is used to install the dotfiles from this repo/folder structure to the user's home folder
# It can be invoked from any location as long as its in the PATH (and you don't need to specify the fully qualified name while invoking it).
# It can handle nested files.
# If there is already a real file (not a symbolic link), then the script will move that file into this repo, and then create the corresponding symlink. This helps preserve the current settings from the user without forcefully overriding from my repo.
# Special handling (copy instead of symlink) for 'custom.git*' files (.gitignore, .gitattributes, etc.):
#   - On FIRST_INSTALL (FIRST_INSTALL env var is set): target always wins — moved into repo, then repo is copied back.
#   - Otherwise: mtime determines the winner. Target newer → moved into repo. Source newer or same age → target overwritten.
# To run it, just invoke by `install-dotfiles.rb` if this folder is already setup in the PATH

# It assumes the following:
#   1. Ruby language is present in the system prior to this script being run.

# Ensure utilities/ is on the load path so 'require' works regardless of whether
# RUBYLIB is set. This is necessary during FIRST_INSTALL (fresh-install-of-osx.sh)
# where the dotfiles repo is cloned after .shellrc is first sourced, so RUBYLIB does
# not yet include this directory when install-dotfiles.rb is first invoked.
$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'cli_parser'
require 'fileutils'
require 'find'
require 'logging'
require 'pathname' # System Ruby on a vanilla macOS is 2.6; Pathname must be required explicitly because autoloading is unreliable at that version.

include Logging

# --- Constants ---
ENV_VAR_REGEX = /--(.*?)--/.freeze # For interpolating environment variables like --VAR--
CUSTOM_GIT_FILENAME_PATTERN = /custom\.git/.freeze # For matching source filenames like custom.gitignore, custom.gitattributes
CUSTOM_GIT_STRING_TO_REPLACE = 'custom.git' # String to be replaced in paths
DOT_GIT_REPLACEMENT_TARGET = '.git' # Target string for replacement (e.g., custom.gitignore -> .gitignore)

IGNORED_FILENAMES = ['.DS_Store'].freeze # Filenames to ignore during processing
IGNORED_FILE_PATTERNS = [/\.zwc/].freeze # File patterns to ignore (matches anywhere in path)

ROOT_PATH = Pathname.new(File::SEPARATOR)
HOME_PATH = Pathname.new(ENV.fetch('HOME')).expand_path
DOTFILES_ROOT_PATH = Pathname.new(__dir__).join('..', 'files').expand_path

# Parse command-line options
options = { dry_run: false, verbose: false, force: false }
CliParser.parse('[options]') do |opts|
  opts.separator 'Installs dotfiles from this repo into the home folder by creating symlinks (or copying for custom.git* files).'
  opts.separator 'For non-custom-git files: if a real file already exists at the target it is moved into the repo first, then symlinked.'
  opts.separator 'For custom.git* files: on FIRST_INSTALL the target always wins; otherwise mtime determines which version is authoritative.'
  opts.separator ''
  opts.on('-n', '--dry-run', 'Show what would be symlinked/copied without making any changes') do
    options[:dry_run] = true
  end
  opts.on('-v', '--verbose', 'Print each file operation (symlink created, skipped, backed up, etc.)') do
    options[:verbose] = true
  end
  opts.on('-f', '--force', 'Overwrite existing non-symlink files without backing them up first') do
    options[:force] = true
  end
end

# Statistics tracking — use a Struct so the intent (a mutable bag of counters) is explicit
# and the constant itself is not a mutated Hash (which is misleading for a constant).
Stats = Struct.new(:processed, :created, :updated, :skipped, :errors, keyword_init: true)
STATS = Stats.new(processed: 0, created: 0, updated: 0, skipped: 0, errors: 0)

# Helper to interpolate environment variables in paths like --VAR--
#
# @param path_template [String] The path template containing --VAR-- placeholders.
# @param source_file [String] The source file path, used for logging purposes.
# @return [String, nil] The interpolated path, or +nil+ if any referenced environment variable is missing.
def _interpolate_path(path_template, source_file)
  # First, check if all referenced environment variables exist.
  # This avoids partial processing if a variable is missing later.
  # It also ensures that we check for key presence, not just a truthy value.
  missing_vars = path_template.scan(ENV_VAR_REGEX).flatten.uniq.reject { |var_name| ENV.key?(var_name) }
  if missing_vars.any?
    warn("Skipping processing involving '#{source_file}' because env var '#{missing_vars.join(', ')}' was not defined")
    return
  end

  # If all variables are present, then perform the substitution.
  # ENV[var_name] is guaranteed to exist here due to the check above.
  path_template.gsub(ENV_VAR_REGEX) { |_match| ENV.fetch(Regexp.last_match(1)) }
end

# Processes a single dotfile: moves existing real files, creates symlink/copy
#
# @param source_pn [Pathname] The Pathname object for the source file.
# @param target_pn [Pathname] The Pathname object for the target file.
# @param dry_run [true, false] Show what would be done without doing it.
# @param verbose [true, false] Verbose output.
# @param force [true, false] Force overwrite without backing up existing files.
# @return [void]
def _process_dotfile(source_pn, target_pn, dry_run: false, verbose: false, force: false)
  source_path = source_pn.to_s.cyan
  target_path = target_pn.to_s.cyan

  STATS.processed += 1

  info("Processing '#{source_path}' --> '#{target_path}'") if dry_run || verbose

  # Ensure target directory exists
  FileUtils.mkdir_p(target_pn.dirname) unless dry_run

  if target_pn.exist? && FileUtils.identical?(target_pn, source_pn) # Avoid moving if they are already the same file (e.g., if the user re-runs the script without changes)
    debug("  Target '#{target_path}' and source '#{source_path}' are identical.".blue) if dry_run || verbose
    STATS.skipped += 1
    return
  end

  is_custom_git = source_pn.basename.to_s.match?(CUSTOM_GIT_FILENAME_PATTERN)
  first_install = ENV.fetch('FIRST_INSTALL', '').strip != ''

  # Check target status before deciding action
  if target_pn.symlink?
    info("  Target '#{target_path}' exists as a symlink, will overwrite.") if verbose
    STATS.updated += 1
  elsif target_pn.exist? # It exists and is not a symlink (real file/dir)
    if force
      info("  Forcefully overwriting existing file '#{target_path}'") if verbose
      FileUtils.rm_rf(target_pn) unless dry_run
    elsif is_custom_git && !first_install
      # mtime-based resolution: whichever file was modified more recently is authoritative.
      # On a tie, source wins (repo is authoritative on re-runs).
      target_mtime = target_pn.mtime
      source_mtime = source_pn.mtime
      if target_mtime > source_mtime
        info("  Target '#{target_path}' is newer (#{target_mtime} > #{source_mtime}); adopting it into repo and re-copying")
        FileUtils.mv(target_pn, source_pn, force: true) unless dry_run
      else
        info("  Source '#{source_path}' is newer or same age (#{source_mtime} >= #{target_mtime}); overwriting target") if verbose
        FileUtils.rm_rf(target_pn) unless dry_run
      end
    else
      # FIRST_INSTALL, or a non-custom-git file: target is always authoritative — move it into repo.
      info("  Moving existing file '#{target_path}' to '#{source_path}' (it will become the new version in your dotfiles repo)") if verbose
      FileUtils.mv(target_pn, source_pn, force: true) unless dry_run
    end
    STATS.updated += 1
  else
    # Target does not exist, no backup needed
    info("  Target '#{target_path}' does not exist, creating new link/copy.") if verbose
    STATS.created += 1
  end

  # Create symlink or copy file for files matching 'custom.git'
  if is_custom_git # Special handling for git files: copy instead of symlink
    info("  Copying '#{source_path}' to '#{target_path}'")
    FileUtils.cp(source_pn, target_pn) unless dry_run
  else
    info("  Creating symlink from '#{source_path}' to '#{target_path}'")
    FileUtils.ln_sf(source_pn, target_pn) unless dry_run
  end
rescue StandardError => e
  warn("Failed during processing of '#{source_path}' -> '#{target_path}': #{e.message}")
  warn(Array(e.backtrace).join("\n"))
  STATS.errors += 1
end

# Ensures the SSH global_config Include line is present in the default SSH config.
# Extracted from top-level code so it is testable and has a clear failure boundary.
#
# @return [void]
def _ensure_ssh_include_line
  # Use Pathname for correct path joining — plain String + 'name' is string concatenation,
  # not path joining, which would produce a broken path if SSH_CONFIGS_DIR has no trailing slash.
  ssh_folder = Pathname.new(ENV.fetch('SSH_CONFIGS_DIR')).expand_path
  global_config_link = ssh_folder.join('global_config')

  unless global_config_link.exist? && global_config_link.symlink?
    warn("Skipping SSH config update because '#{global_config_link.to_s.cyan}' does not exist or is not a symlink.")
    return
  end

  default_ssh_config = ssh_folder.join('config')
  FileUtils.touch(default_ssh_config) unless default_ssh_config.exist?

  include_line = 'Include "${SSH_CONFIGS_DIR}/global_config"'
  begin
    # Use File.foreach to stream the file line-by-line instead of loading it all into memory.
    if File.foreach(default_ssh_config).any? { |l| l.strip == include_line }
      success("'#{include_line.yellow}' already present in '#{default_ssh_config.to_s.cyan}'")
    else
      info("Adding '#{include_line}' to '#{default_ssh_config.to_s.cyan}'")
      File.write(default_ssh_config, "\n#{include_line}\n", mode: 'a')
    end
  rescue StandardError => e
    warn("Failed processing SSH config '#{default_ssh_config.to_s.cyan}': #{e.message}")
  end
end

info('Starting to install dotfiles')
warn('[DRY-RUN MODE]') if options[:dry_run]

# NOTE: cannot use Dir.glob since that doesn't handle hidden files
Find.find(DOTFILES_ROOT_PATH) do |source_path_str|
  source_pn = Pathname.new(source_path_str)

  # Skip directories and ignored files/patterns
  next if source_pn.directory?
  next if IGNORED_FILENAMES.include?(source_pn.basename.to_s)
  next if IGNORED_FILE_PATTERNS.any? { |pattern| source_pn.to_s.match?(pattern) }

  # git doesn't handle symlinks well for its core config, handle separately
  relative_path_str = source_pn.relative_path_from(DOTFILES_ROOT_PATH).to_s
  transformed_relative_path_str = relative_path_str.gsub(CUSTOM_GIT_STRING_TO_REPLACE, DOT_GIT_REPLACEMENT_TARGET)

  interpolated_target_str = _interpolate_path(transformed_relative_path_str, source_pn.to_s)
  next unless interpolated_target_str # Skip if env var interpolation failed

  # since some env var might already contain the full path from the root...
  # Pathname#join correctly handles cases where interpolated_target_str might already be an absolute path.
  # if the target path is still relative after interpolation, then we should treat it as relative to the root directory
  target_pn = ROOT_PATH.join(interpolated_target_str)
  _process_dotfile(source_pn, target_pn, **options)
end

# Print statistics summary
puts ''
success('Summary:')
puts "  Processed: #{STATS.processed}"
puts "  Created:   #{STATS.created}"
puts "  Updated:   #{STATS.updated}"
puts "  Skipped:   #{STATS.skipped}"
puts "  Errors:    #{STATS.errors.positive? ? STATS.errors.to_s.red : STATS.errors}"

_ensure_ssh_include_line

warn("Since 'custom.git*' files are COPIED (not symlinked), always edit the repo source first. When re-running without FIRST_INSTALL set, the newer file wins — so a stale home-dir copy can silently overwrite repo changes if its mtime is newer.")
