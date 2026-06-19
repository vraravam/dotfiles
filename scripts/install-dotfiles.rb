#!/usr/bin/env ruby
# frozen_string_literal: true

# This script is used to install the dotfiles from this repo/dir structure to the user's home dir
# It can be invoked from any location as long as its in the PATH (and you don't need to specify the fully qualified name while invoking it).
# It can handle nested files.
# If there is already a real file (not a symbolic link), then the script will move that file into this repo, and then create the corresponding symlink. This helps preserve the current settings from the user without forcefully overriding from my repo.
# Special handling (copy instead of symlink) for 'custom.git*' files (.gitignore, .gitattributes, etc.):
#   - On FIRST_INSTALL (FIRST_INSTALL env var is set): target always wins -- moved into repo, then repo is copied back.
#   - Otherwise: mtime determines the winner. Target newer → moved into repo. Source newer or same age → target overwritten.
# To run it, just invoke by `install-dotfiles.rb` if this dir is already setup in the PATH
#
# Usage:
#   Standalone: install-dotfiles.rb [options]
#   Module:     InstallDotfiles.run(dry_run: false, verbose: false, force: false)

# It assumes the following:
#   1. Ruby language is present in the system prior to this script being run.

require 'fileutils'
require 'find'
require 'pathname' # System Ruby on a vanilla macOS is 2.6; Pathname must be required explicitly because autoloading is unreliable at that version.

require_relative 'utilities/env_vars'
require_relative 'utilities/logging'
require_relative 'utilities/path_utils'
require_relative 'utilities/string'

# Installs dotfiles from the repo into the home directory.
# Returns true on success (zero errors), false if any errors occurred.
module InstallDotfiles
  extend self

  # --- Constants ---
  ENV_VAR_REGEX = /--(.*?)--/.freeze # For interpolating environment variables like --VAR--
  CUSTOM_GIT_PREFIX = 'custom.git' # Prefix in source filenames (custom.gitignore, custom.gitattributes) that gets replaced with '.git'
  DOT_GIT_REPLACEMENT_TARGET = '.git' # Target string for replacement (e.g., custom.gitignore -> .gitignore)

  IGNORED_FILENAMES = ['.DS_Store'].freeze # Filenames to ignore during processing
  IGNORED_FILE_PATTERNS = [/\.zwc/].freeze # File patterns to ignore (matches anywhere in path)

  # Statistics tracking -- use a Struct so the intent (a mutable bag of counters) is explicit
  Stats = Struct.new(:processed, :created, :updated, :skipped, :errors, keyword_init: true)

  # Installs dotfiles by creating symlinks (or copying for custom.git* files).
  #
  # @param dry_run [Boolean] Show what would be done without making changes
  # @param verbose [Boolean] Print each file operation
  # @param force [Boolean] Overwrite existing files without backing them up
  # @return [Boolean] true if no errors, false if any errors occurred
  def run(dry_run: false, verbose: false, force: false)
    stats = Stats.new(processed: 0, created: 0, updated: 0, skipped: 0, errors: 0)

    Logging.info('Starting to install dotfiles')
    Logging.warn('[DRY-RUN MODE]') if dry_run

    # NOTE: cannot use Dir.glob since that doesn't handle hidden files
    Find.find(EnvVars::DOTFILES_DIR.join('files')) do |source_path_str|
      source_pn = Pathname.new(source_path_str)

      # Skip directories and ignored files/patterns
      next if source_pn.directory?
      next if IGNORED_FILENAMES.include?(source_pn.basename.to_s)
      next if IGNORED_FILE_PATTERNS.any? { |pattern| source_pn.to_s.match?(pattern) }

      # git doesn't handle symlinks well for its core config, handle separately
      relative_path_str = source_pn.relative_path_from(EnvVars::DOTFILES_DIR.join('files')).to_s
      transformed_relative_path_str = relative_path_str.gsub(CUSTOM_GIT_PREFIX, DOT_GIT_REPLACEMENT_TARGET)

      interpolated_target_str = _interpolate_path(transformed_relative_path_str, source_pn.to_s)
      next unless interpolated_target_str # Skip if env var interpolation failed

      # since some env var might already contain the full path from the root...
      # Pathname#join correctly handles cases where interpolated_target_str might already be an absolute path.
      # if the target path is still relative after interpolation, then we should treat it as relative to the root directory
      target_pn = Core::ROOT.join(interpolated_target_str)
      _process_dotfile(source_pn, target_pn, stats, dry_run: dry_run, verbose: verbose, force: force)
    end

    # Print statistics summary
    puts ''
    Logging.success('Summary:')
    puts "  Processed: #{stats.processed.to_s.purple}"
    puts "  Created:   #{stats.created.to_s.green}"
    puts "  Updated:   #{stats.updated.to_s.green}"
    puts "  Skipped:   #{stats.skipped.to_s.purple}"
    puts "  Errors:    #{stats.errors.positive? ? stats.errors.to_s.red : stats.errors}"

    _ensure_ssh_include_line

    Logging.warn("Since 'custom.git*' files are COPIED (not symlinked), always edit the repo source first. When re-running without FIRST_INSTALL set, the newer file wins -- so a stale home-dir copy can silently overwrite repo changes if its mtime is newer.")

    stats.errors.zero?
  end

  # Helper to interpolate environment variables in paths like --VAR--
  #
  # @param path_template [String] The path template containing --VAR-- placeholders.
  # @param source_file [String] The source file path, used for logging purposes.
  # @return [String, nil] The interpolated path, or +nil+ if any referenced environment variable is missing.
  def _interpolate_path(path_template, source_file)
    # First, check if all referenced environment variables exist.
    # Check both ENV (runtime) and EnvVars (constants) - on vanilla OS, env vars
    # aren't exported to ENV until .shellrc is sourced, but EnvVars constants
    # provide the default values.
    missing_vars = path_template.scan(ENV_VAR_REGEX).flatten.uniq.reject do |var_name|
      ENV.key?(var_name) || EnvVars.const_defined?(var_name)
    end
    if missing_vars.any?
      Logging.warn("Skipping processing involving '#{source_file}' because env var '#{missing_vars.join(', ')}' was not defined")
      return
    end

    # If all variables are present, perform substitution.
    # Prefer ENV (user override) over EnvVars constant (default).
    path_template.gsub(ENV_VAR_REGEX) do |_match|
      var_name = Regexp.last_match(1)
      if ENV.key?(var_name)
        ENV.fetch(var_name)
      else
        EnvVars.const_get(var_name).to_s
      end
    end
  end

  private_class_method :_interpolate_path

  # Processes a single dotfile: moves existing real files, creates symlink/copy
  #
  # @param source_pn [Pathname] The Pathname object for the source file.
  # @param target_pn [Pathname] The Pathname object for the target file.
  # @param stats [Stats] Statistics tracking object.
  # @param dry_run [Boolean] Show what would be done without doing it.
  # @param verbose [Boolean] Verbose output.
  # @param force [Boolean] Force overwrite without backing up existing files.
  # @return [void]
  def _process_dotfile(source_pn, target_pn, stats, dry_run: false, verbose: false, force: false)
    source_path = source_pn.to_s.cyan
    target_path = target_pn.to_s.cyan

    stats.processed += 1

    Logging.info("Processing '#{source_path}' --> '#{target_path}'") if dry_run || verbose

    # Ensure target directory exists
    PathUtils.ensure_directories_exist(target_pn.dirname) unless dry_run

    if target_pn.exist? && File.identical?(target_pn, source_pn) # Avoid moving if they are already the same file (e.g., if the user re-runs the script without changes)
      Logging.debug("  Target '#{target_path}' and source '#{source_path}' are identical.") if dry_run || verbose
      stats.skipped += 1
      return
    end

    is_custom_git = source_pn.basename.to_s.include?(CUSTOM_GIT_PREFIX)

    # Check target status before deciding action
    if target_pn.symlink?
      Logging.info("  Target '#{target_path}' exists as a symlink, will overwrite.") if verbose
      stats.updated += 1
    elsif target_pn.exist? # It exists and is not a symlink (real file/dir)
      if force
        Logging.info("  Forcefully overwriting existing file '#{target_path}'") if verbose
        target_pn.rmtree unless dry_run
      elsif is_custom_git && !EnvVars.first_install?
        # For custom.git files, check if they're already identical (content + timestamp)
        # before doing any mtime comparison or file operations
        if FileUtils.identical?(source_pn, target_pn) && target_pn.mtime == source_pn.mtime
          Logging.debug("  Target '#{target_path}' is identical to source (content + timestamp); skipping") if verbose
          stats.skipped += 1
          return
        end

        # mtime-based resolution: whichever file was modified more recently is authoritative.
        # On a tie, source wins (repo is authoritative on re-runs).
        target_mtime = target_pn.mtime
        source_mtime = source_pn.mtime
        if target_mtime > source_mtime
          Logging.info("  Target '#{target_path}' is newer (#{target_mtime} > #{source_mtime}); adopting it into repo and re-copying")
          FileUtils.mv(target_pn, source_pn, force: true) unless dry_run
        else
          Logging.info("  Source '#{source_path}' is newer or same age (#{source_mtime} >= #{target_mtime}); overwriting target") if verbose
          target_pn.rmtree unless dry_run
        end
      else
        # FIRST_INSTALL, or a non-custom-git file: target is always authoritative -- move it into repo.
        Logging.info("  Moving existing file '#{target_path}' to '#{source_path}' (it will become the new version in your dotfiles repo)") if verbose
        FileUtils.mv(target_pn, source_pn, force: true) unless dry_run
      end
      stats.updated += 1
    else
      # Target does not exist, no backup needed
      Logging.info("  Target '#{target_path}' does not exist, creating new link/copy.") if verbose
      stats.created += 1
    end

    # Create symlink or copy file for files matching 'custom.git'
    if is_custom_git # Special handling for git files: copy instead of symlink
      Logging.info("  Copying '#{source_path}' to '#{target_path}'")
      FileUtils.cp(source_pn, target_pn, preserve: true) unless dry_run
    else
      Logging.info("  Creating symlink from '#{source_path}' to '#{target_path}'")
      FileUtils.ln_sf(source_pn, target_pn) unless dry_run
    end
  rescue StandardError => e
    Logging.warn("Failed during processing of '#{source_path}' -> '#{target_path}': #{e.message}")
    Logging.warn(Array(e.backtrace).join("\n"))
    stats.errors += 1
  end

  private_class_method :_process_dotfile

  # Ensures the SSH global_config Include line is present in the default SSH config.
  # Extracted from top-level code so it is testable and has a clear failure boundary.
  #
  # @return [void]
  def _ensure_ssh_include_line
    ssh_dir = EnvVars::HOME.join('.ssh').expand_path.freeze
    global_config_link = ssh_dir.join('global_config')

    unless global_config_link.exist? && global_config_link.symlink?
      Logging.warn("Skipping SSH config update because '#{global_config_link.to_s.cyan}' does not exist or is not a symlink.")
      return
    end

    default_ssh_config = ssh_dir.join('config')
    default_ssh_config.write('') unless default_ssh_config.exist?

    include_line = 'Include ~/.ssh/global_config'
    begin
      # Use Pathname#each_line to stream the file line-by-line instead of loading it all into memory.
      if default_ssh_config.each_line.any? { |l| l.strip == include_line }
        Logging.success("'#{include_line.cyan}' already present in '#{default_ssh_config.to_s.cyan}'")
      else
        Logging.info("Adding '#{include_line.cyan}' to '#{default_ssh_config.to_s.cyan}'")
        default_ssh_config.write("\n#{include_line}\n", mode: 'a')
      end
    rescue StandardError => e
      Logging.warn("Failed processing SSH config '#{default_ssh_config.to_s.cyan}': #{e.message}")
    end
  end

  private_class_method :_ensure_ssh_include_line
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  # Parse command-line options
  options = { dry_run: false, verbose: false, force: false }
  CliParser.parse('[options]') do |opts|
    opts.separator 'Installs dotfiles from this repo into the home dir by creating symlinks (or copying for custom.git* files).'
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

  Logging.run_script(File.basename(__FILE__, '.rb')) do
    success = InstallDotfiles.run(**options)
    exit(success ? 0 : 1)
  end
end
