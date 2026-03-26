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
require 'pathname'  # Note: This has been added explicitly due to the default version of ruby (2.6). Once the default ruby upgrades to 3.x, we can remove
require 'optparse'

# --- Constants ---
ENV_VAR_REGEX = /--(.*?)--/.freeze # For interpolating environment variables like --VAR--
CUSTOM_GIT_FILENAME_PATTERN = /custom\.git/.freeze # For matching source filenames like custom.gitignore, custom.gitattributes
CUSTOM_GIT_STRING_TO_REPLACE = 'custom.git'.freeze # String to be replaced in paths
DOT_GIT_REPLACEMENT_TARGET = '.git'.freeze # Target string for replacement (e.g., custom.gitignore -> .gitignore)

IGNORED_FILENAMES = ['.DS_Store'].freeze # Filenames to ignore during processing
IGNORED_FILE_PATTERNS = [/\.zwc/].freeze # File patterns to ignore (matches anywhere in path)

HOME_PATH = Pathname.new(ENV.fetch('HOME')).expand_path
DOTFILES_ROOT_PATH = Pathname.new(__dir__).join('..', 'files').expand_path

# Parse command-line options
options = { dry_run: false, verbose: false, force: false }
OptionParser.new do |opts|
  opts.banner = "Usage: install-dotfiles.rb [options]"
  opts.on("-n", "--dry-run", "Show what would be done without doing it") do
    options[:dry_run] = true
  end
  opts.on("-v", "--verbose", "Verbose output") do
    options[:verbose] = true
  end
  opts.on("-f", "--force", "Force overwrite without backing up existing files") do
    options[:force] = true
  end
  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Statistics tracking
STATS = { processed: 0, created: 0, updated: 0, skipped: 0, errors: 0 }

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
  path_template.gsub(ENV_VAR_REGEX) { |_match| ENV.fetch($1) }
end

# Processes a single dotfile: moves existing real files, creates symlink/copy
#
# @param source_pn [Pathname] The Pathname object for the source file.
# @param target_pn [Pathname] The Pathname object for the target file.
# @param options [Hash] Options hash with :dry_run, :verbose, :force keys
# @return [void]
def process_dotfile(source_pn, target_pn, options = {})
  source_path = source_pn.to_s.replace_home_path_with_tilde
  target_path = target_pn.to_s.replace_home_path_with_tilde

  STATS[:processed] += 1

  if options[:dry_run] || options[:verbose]
    puts "Processing #{source_path.yellow} --> #{target_path.yellow}"
  end

  if options[:dry_run]
    # In dry-run mode, just show what would be done
    if target_pn.symlink?
      puts "  [DRY-RUN] Would overwrite existing symlink at #{target_path.cyan}".blue
      STATS[:updated] += 1
    elsif target_pn.exist?
      if options[:force]
        puts "  [DRY-RUN] Would forcefully overwrite #{target_path.cyan}".blue
      else
        puts "  [DRY-RUN] Would move existing file #{target_path.cyan} to #{source_path.cyan}".blue
      end
      STATS[:updated] += 1
    else
      puts "  [DRY-RUN] Would create new link/copy at #{target_path.cyan}".blue
      STATS[:created] += 1
    end

    if source_pn.basename.to_s.match?(CUSTOM_GIT_FILENAME_PATTERN)
      puts "  [DRY-RUN] Would copy (not symlink)".blue
    else
      puts "  [DRY-RUN] Would create symlink".blue
    end
    return
  end

  # Ensure target directory exists
  FileUtils.mkdir_p(target_pn.dirname) unless options[:dry_run]

  # Check target status before deciding action
  if target_pn.symlink?
    puts "  Target #{target_path.cyan} exists as a symlink, will overwrite.".blue if options[:verbose]
    STATS[:updated] += 1
  elsif target_pn.exist? # It exists and is not a symlink (real file/dir)
    if options[:force]
      puts "  Forcefully overwriting existing file #{target_path.cyan}".blue if options[:verbose]
      FileUtils.rm_rf(target_pn)
    else
      puts "  Moving existing file #{target_path.cyan} to #{source_path.cyan} (it will become the new source in your dotfiles repo)".blue if options[:verbose]
      # Move the existing file from target to the source location in the dotfiles repo
      FileUtils.mv(target_pn, source_pn, force: true)
    end
    STATS[:updated] += 1
  else
    # Target does not exist, no backup needed
    puts "  Target #{target_path.cyan} does not exist, creating new link/copy.".blue if options[:verbose]
    STATS[:created] += 1
  end

  # Create symlink or copy file for files matching 'custom.git'
  if source_pn.basename.to_s.match?(CUSTOM_GIT_FILENAME_PATTERN) # Special handling for git files, match on filename
    puts "  Copying #{source_path.cyan} to #{target_path.cyan}".blue if options[:verbose]
    FileUtils.cp(source_pn, target_pn)
  else
    puts "  Creating symlink from #{source_path.cyan} to #{target_path.cyan}".blue if options[:verbose]
    FileUtils.ln_sf(source_pn, target_pn)
  end
rescue StandardError => e
  puts "**ERROR** Failed during processing of #{source_path.cyan} -> #{target_path.cyan}: #{e.message}".red
  STATS[:errors] += 1
end

puts 'Starting to install dotfiles'.green
puts '[DRY-RUN MODE]'.yellow if options[:dry_run]

# Note: cannot use Dir.glob since that doesn't handle hidden files
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
  process_dotfile(source_pn, target_pn, options)
end

# Print statistics summary
puts "\n#{'Summary:'.green}"
puts "  Processed: #{STATS[:processed]}"
puts "  Created:   #{STATS[:created]}"
puts "  Updated:   #{STATS[:updated]}"
puts "  Skipped:   #{STATS[:skipped]}"
if STATS[:errors] > 0
  puts "  Errors:    #{STATS[:errors]}".red
else
  puts "  Errors:    #{STATS[:errors]}"
end

ssh_folder = ENV.fetch('SSH_CONFIGS_DIR')
global_config_link = ssh_folder + 'global_config'

# Check if the global_config symlink exists and points to a valid file
if global_config_link.symlink? && global_config_link.exist?
  default_ssh_config = ssh_folder + 'config'
  FileUtils.touch(default_ssh_config) unless default_ssh_config.exist?

  include_line = 'Include "${SSH_CONFIGS_DIR}/global_config"'
  begin
    if File.readlines(default_ssh_config).any? { |l| l.strip == include_line }
      puts "'#{include_line}' already present in '#{default_ssh_config.to_s.replace_home_path_with_tilde}'".green
    else
      puts "Adding '#{include_line}' to '#{default_ssh_config.to_s.replace_home_path_with_tilde}'".blue
      File.write(default_ssh_config, "\n#{include_line}\n", mode: 'a')
    end
  rescue StandardError => e
    puts "**ERROR** Failed processing SSH config '#{default_ssh_config.to_s.replace_home_path_with_tilde}': #{e.message}".red
  end
else
  puts "**WARN** Skipping SSH config update because '#{global_config_link.to_s.replace_home_path_with_tilde}' does not exist or is not a symlink.".yellow
end

puts "Since the '.gitignore' and '.gitattributes' files are COPIED over, any new changes being pulled in (from a newer version of the upstream repo) need to be manually reconciled between this repo and your home and profiles folders".red
