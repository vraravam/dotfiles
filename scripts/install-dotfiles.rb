#!/usr/bin/env ruby

# frozen_string_literal: true

# file location: <anywhere; but advisable in the PATH>

# This script is used to install the dotfiles from this repo/folder structure to the user's home folder
# It can be invoked from any location as long as its in the PATH (and you don't need to specify the fully qualified name while invoking it).
# It can handle nested files.
# If there is already a real file (not a symbolic link), then the script will move that file into this repo, and then create the corresponding symlink. This helps preserve the current settings from the user without forcefully overriding from my repo.
# Special handling (rename + copy instead of symlink) for '.gitattributes' and '.gitignore'
# To run it, just invoke by `install-dotfiles.rb` if this folder is already setup in the PATH

# It assumes the following:
#   1. Ruby language is present in the system prior to this script being run.

require_relative 'utilities/file'
require_relative 'utilities/string'
require 'fileutils'
require 'find'
require 'pathname'

# --- Constants ---
ENV_VAR_REGEX = /--(.*?)--/ # For interpolating environment variables like --VAR--
CUSTOM_GIT_FILENAME_PATTERN = /custom\.git/ # For matching source filenames like custom.gitignore, custom.gitattributes
CUSTOM_GIT_STRING_TO_REPLACE = 'custom.git' # String to be replaced in paths
DOT_GIT_REPLACEMENT_TARGET = '.git' # Target string for replacement (e.g., custom.gitignore -> .gitignore)

IGNORED_FILENAMES = ['.DS_Store'].freeze # Filenames to ignore during processing
IGNORED_FILE_PATTERNS = [/\.zwc/].freeze # File patterns to ignore (matches anywhere in path)

# Helper to interpolate environment variables in paths like --VAR--
def interpolate_path(path_template, source_file)
  # First, check if all referenced environment variables exist.
  # This avoids partial processing if a variable is missing later.
  # It also ensures that we check for key presence, not just a truthy value.
  path_template.scan(ENV_VAR_REGEX) do |(var_name)| # scan returns array of arrays of captures e.g. [["VAR1"], ["VAR2"]]
    unless ENV.key?(var_name)
      puts "**WARN** Skipping processing involving '#{source_file}' because env var '#{var_name}' was not defined".yellow
      return nil # Exit early if any variable is not defined
    end
  end

  # If all variables are present, then perform the substitution.
  # ENV[var_name] is guaranteed to exist here due to the check above.
  path_template.gsub(ENV_VAR_REGEX) do |_match| # Use _match as the full match string isn't needed here
    ENV[$1]
  end
end

# Processes a single dotfile: moves existing real files, creates symlink/copy
def process_dotfile(source_pn, target_pn)
  puts "Processing #{source_pn.to_s.yellow} --> #{target_pn.to_s.yellow}"
  # Ensure target directory exists
  FileUtils.mkdir_p(target_pn.dirname)

  begin
    # Check target status before deciding action
    if target_pn.symlink?
      puts "  Target #{target_pn.to_s.cyan} exists as a symlink, will overwrite.".blue
    elsif target_pn.exist? # It exists and is not a symlink (real file/dir)
      puts "  Moving existing file #{target_pn.to_s.cyan} to #{source_pn.to_s.cyan} (it will become the new source in your dotfiles repo)".blue
      # Move the existing file from target to the source location in the dotfiles repo
      FileUtils.mv(target_pn, source_pn, force: true)
    else
      # Target does not exist, no backup needed
      puts "  Target #{target_pn.to_s.cyan} does not exist, creating new link/copy.".blue
    end

    # Create symlink or copy file for files matching 'custom.git'
    if source_pn.basename.to_s.match?(CUSTOM_GIT_FILENAME_PATTERN) # Special handling for git files, match on filename
      puts "  Copying #{source_pn.to_s.cyan} to #{target_pn.to_s.cyan}".blue
      FileUtils.cp(source_pn, target_pn)
    else
      puts "  Creating symlink from #{source_pn.to_s.cyan} to #{target_pn.to_s.cyan}".blue
      FileUtils.ln_sf(source_pn, target_pn)
    end
  rescue StandardError => e
    puts "**ERROR** Failed during processing of #{source_pn} -> #{target_pn}: #{e.message}".red
  end
end

puts 'Starting to install dotfiles'.green
HOME_PATH = Pathname.new(ENV['HOME']).expand_path
DOTFILES_ROOT_PATH = Pathname.new(__dir__).join('..', 'files').expand_path

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
  # Pathname#join correctly handles cases where interpolated_target_str might be an absolute path.
  target_pn = HOME_PATH.join(interpolated_target_str)
  process_dotfile(source_pn, target_pn)
end

ssh_folder = HOME_PATH + '.ssh'
global_config_link = ssh_folder + 'global_config'

# Check if the global_config symlink exists and points to a valid file
if global_config_link.symlink? && global_config_link.exist?
  default_ssh_config = ssh_folder + 'config'
  FileUtils.touch(default_ssh_config) unless default_ssh_config.exist?

  include_line = 'Include "~/.ssh/global_config"'
  begin
    if default_ssh_config.each_line.any? { |l| l.strip == include_line }
      puts "'#{include_line}' already present in '#{default_ssh_config}'".green
    else
      puts "Adding '#{include_line}' to '#{default_ssh_config}'".blue
      File.write(default_ssh_config, "\n#{include_line}\n", mode: 'a')
    end
  rescue StandardError => e
    puts "**ERROR** Failed processing SSH config '#{default_ssh_config}': #{e.message}".red
  end
else
  puts "**WARN** Skipping SSH config update because '#{global_config_link}' does not exist or is not a symlink.".yellow
end

puts "Since the '.gitignore' and '.gitattributes' files are COPIED over, any new changes being pulled in (from a newer version of the upstream repo) need to be manually reconciled between this repo and your home and profiles folders".red
