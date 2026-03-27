#!/usr/bin/env ruby

# frozen_string_literal: true

# This script is used to install the dotfiles from this repo/folder structure to the user's home folder
# It can be invoked from any location as long as its in the PATH (and you don't need to specify the fully qualified name while invoking it).
# It can handle nested files.
# If there is already a real file (not a symbolic link), then the script will move that file into this repo, and then create the corresponding symlink. This helps preserve the current settings from the user without forcefully overriding from my repo.
# Special handling (rename + copy instead of symlink) for '.gitattributes' and '.gitignore'
# To run it, just invoke by `install-dotfiles.rb` if this folder is already setup in the PATH

# It assumes the following:
#   1. Ruby language is present in the system prior to this script being run.

require_relative 'utilities/string'
require 'fileutils'
require 'find'
require 'pathname' # NOTE: This has been added explicitly due to the default version of ruby (2.6) on a vanilla macos. Once the default ruby upgrades to 3.x, we can remove
require 'optparse'

# --- Constants ---
ENV_VAR_REGEX = /--(.*?)--/.freeze # For interpolating environment variables like --VAR--
CUSTOM_GIT_FILENAME_PATTERN = /custom\.git/.freeze # For matching source filenames like custom.gitignore, custom.gitattributes
CUSTOM_GIT_STRING_TO_REPLACE = 'custom.git' # String to be replaced in paths
DOT_GIT_REPLACEMENT_TARGET = '.git' # Target string for replacement (e.g., custom.gitignore -> .gitignore)

IGNORED_FILENAMES = ['.DS_Store'].freeze # Filenames to ignore during processing
IGNORED_FILE_PATTERNS = [/\.zwc/].freeze # File patterns to ignore (matches anywhere in path)

HOME_PATH = Pathname.new(ENV.fetch('HOME')).expand_path
DOTFILES_ROOT_PATH = Pathname.new(__dir__).join('..', 'files').expand_path

# Parse command-line options
options = { dry_run: false, verbose: false, force: false }
OptionParser.new do |opts|
  opts.banner = 'Usage: install-dotfiles.rb [options]'
  opts.on('-n', '--dry-run', 'Show what would be done without doing it') do
    options[:dry_run] = true
  end
  opts.on('-v', '--verbose', 'Verbose output') do
    options[:verbose] = true
  end
  opts.on('-f', '--force', 'Force overwrite without backing up existing files') do
    options[:force] = true
  end
  opts.on('-h', '--help', 'Show this help message') do
    puts opts
    exit
  end
end.parse!

# Statistics tracking — use a Struct so the intent (a mutable bag of counters) is explicit
# and the constant itself is not a mutated Hash (which is misleading for a constant).
Stats = Struct.new(:processed, :created, :updated, :skipped, :errors, keyword_init: true)
STATS = Stats.new(processed: 0, created: 0, updated: 0, skipped: 0, errors: 0)

# Helper to interpolate environment variables in paths like --VAR--
#
# @param path_template [String] The path template containing --VAR-- placeholders.
# @param source_file [String] The source file path, used for logging purposes.
# @return [String, nil] The interpolated path, or nil if an environment variable is missing.
def interpolate_path(path_template, source_file)
  # First, check if all referenced environment variables exist.
  # This avoids partial processing if a variable is missing later.
  # It also ensures that we check for key presence, not just a truthy value.
  missing_vars = path_template.scan(ENV_VAR_REGEX).flatten.uniq.reject { |var_name| ENV.key?(var_name) }
  if missing_vars.any?
    puts "**WARN** Skipping processing involving '#{source_file}' because env var '#{missing_vars.join(', ')}' was not defined".yellow
    return nil # Exit early if any variable is not defined
  end

  # If all variables are present, then perform the substitution.
  # ENV[var_name] is guaranteed to exist here due to the check above.
  path_template.gsub(ENV_VAR_REGEX) { |_match| ENV.fetch(Regexp.last_match(1)) }
end

# Processes a single dotfile: moves existing real files, creates symlink/copy
#
# @param source_pn [Pathname] The Pathname object for the source file.
# @param target_pn [Pathname] The Pathname object for the target file.
# @param dry_run [Boolean] Show what would be done without doing it.
# @param verbose [Boolean] Verbose output.
# @param force [Boolean] Force overwrite without backing up existing files.
# @return [void]
def process_dotfile(source_pn, target_pn, dry_run: false, verbose: false, force: false)
  source_path = source_pn.to_s.replace_home_path_with_tilde
  target_path = target_pn.to_s.replace_home_path_with_tilde

  STATS.processed += 1

  puts "Processing #{source_path.yellow} --> #{target_path.yellow}" if dry_run || verbose

  # Ensure target directory exists
  FileUtils.mkdir_p(target_pn.dirname) unless dry_run

  if File.exist?(target_pn) && FileUtils.identical?(target_pn, source_pn) # Avoid moving if they are already the same file (e.g., if the user re-runs the script without changes)
    # puts "  Target #{target_path.cyan} and source #{source_path.cyan} are identical.".blue if verbose
    STATS.skipped += 1
    return
  end

  # Check target status before deciding action
  if File.symlink?(target_path) # NOTE: This has been added explicitly due to the default version of ruby (2.6) on a vanilla macos. Once the default ruby upgrades to 3.x, we can change to 'target_pn.symlink?'
    puts "  Target #{target_path.cyan} exists as a symlink, will overwrite.".blue if verbose
    STATS.updated += 1
  elsif target_pn.exist? # It exists and is not a symlink (real file/dir)
    if force
      puts "  Forcefully overwriting existing file #{target_path.cyan}".blue if verbose
      FileUtils.rm_rf(target_pn) unless dry_run
    else
      puts "  Moving existing file #{target_path.cyan} to #{source_path.cyan} (it will become the new version in your dotfiles repo)".blue if verbose
      # Move the existing file from target to the source location in the dotfiles repo
      FileUtils.mv(target_pn, source_pn, force: true) unless dry_run
    end
    STATS.updated += 1
  else
    # Target does not exist, no backup needed
    puts "  Target #{target_path.cyan} does not exist, creating new link/copy.".blue if verbose
    STATS.created += 1
  end

  # Create symlink or copy file for files matching 'custom.git'
  if source_pn.basename.to_s.match?(CUSTOM_GIT_FILENAME_PATTERN) # Special handling for git files, match on filename
    puts "  Copying #{source_path.cyan} to #{target_path.cyan}".blue if verbose
    FileUtils.cp(source_pn, target_pn) unless dry_run
  else
    puts "  Creating symlink from #{source_path.cyan} to #{target_path.cyan}".blue
    FileUtils.ln_sf(source_pn, target_pn) unless dry_run
  end
rescue StandardError => e
  puts "**ERROR** Failed during processing of #{source_path.cyan} -> #{target_path.cyan}: #{e.message}".red
  puts e.backtrace.join("\n").red
  STATS.errors += 1
end

# Ensures the SSH global_config Include line is present in the default SSH config.
# Extracted from top-level code so it is testable and has a clear failure boundary.
#
# @return [void]
def ensure_ssh_include_line
  # Use Pathname for correct path joining — plain String + 'name' is string concatenation,
  # not path joining, which would produce a broken path if SSH_CONFIGS_DIR has no trailing slash.
  ssh_folder = Pathname.new(ENV.fetch('SSH_CONFIGS_DIR')).expand_path
  global_config_link = ssh_folder.join('global_config')

  unless global_config_link.exist? && File.symlink?(global_config_link.to_s) # NOTE: This has been added explicitly due to the default version of ruby (2.6) on a vanilla macos. Once the default ruby upgrades to 3.x, we can change to 'global_config_link.symlink?'
    puts "**WARN** Skipping SSH config update because '#{global_config_link.to_s.replace_home_path_with_tilde}' does not exist or is not a symlink.".yellow
    return
  end

  default_ssh_config = ssh_folder.join('config')
  FileUtils.touch(default_ssh_config) unless default_ssh_config.exist?

  include_line = 'Include "${SSH_CONFIGS_DIR}/global_config"'
  begin
    # Use File.foreach to stream the file line-by-line instead of loading it all into memory.
    if File.foreach(default_ssh_config).any? { |l| l.strip == include_line }
      puts "'#{include_line}' already present in '#{default_ssh_config.to_s.replace_home_path_with_tilde}'".green
    else
      puts "Adding '#{include_line}' to '#{default_ssh_config.to_s.replace_home_path_with_tilde}'".blue
      File.write(default_ssh_config, "\n#{include_line}\n", mode: 'a')
    end
  rescue StandardError => e
    puts "**ERROR** Failed processing SSH config '#{default_ssh_config.to_s.replace_home_path_with_tilde}': #{e.message}".red
  end
end

puts 'Starting to install dotfiles'.green
puts '[DRY-RUN MODE]'.yellow if options[:dry_run]

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

  interpolated_target_str = interpolate_path(transformed_relative_path_str, source_pn.to_s)
  next unless interpolated_target_str # Skip if env var interpolation failed

  # since some env var might already contain the full path from the root...
  # Pathname#join correctly handles cases where interpolated_target_str might already be an absolute path.
  target_pn = HOME_PATH.join(interpolated_target_str)
  process_dotfile(source_pn, target_pn, **options)
end

# Print statistics summary
puts "\n#{'Summary:'.green}"
puts "  Processed: #{STATS.processed}"
puts "  Created:   #{STATS.created}"
puts "  Updated:   #{STATS.updated}"
puts "  Skipped:   #{STATS.skipped}"
if STATS.errors > 0
  puts "  Errors:    #{STATS.errors}".red
else
  puts "  Errors:    #{STATS.errors}"
end

ensure_ssh_include_line

puts "Since the '.gitignore' and '.gitattributes' files are COPIED over, any new changes being pulled in (from a newer version of the upstream repo) need to be manually reconciled between this repo and your home and profiles folders".red
