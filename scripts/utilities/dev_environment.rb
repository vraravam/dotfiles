#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

require_relative 'collection_processor'
require_relative 'core'
require_relative 'direnv'
require_relative 'env_vars'
require_relative 'git_workspace'
require_relative 'logging'
require_relative 'mise'

# Developer-environment setup across every git repo and its ancestor directories: installs
# the tool versions mise declares and activates direnv's .envrc files. Shell functions in
# .aliases delegate to these methods (install_mise_versions, activate_all_direnv_configs,
# setup_dev_environment).
#
# The +shared_dirs:+ keyword argument allows callers (Ruby scripts, not shell) to optimize
# by collecting ancestor dirs once and passing them to multiple methods, avoiding repeated
# find traversals. The tool-specific commands live in Mise and Direnv.
module DevEnvironment
  extend self

  # How deep below HOME, DOTFILES_DIR and PROJECTS_BASE_DIR git repos are searched for.
  DEFAULT_MAXDEPTH = 6

  # A shallower search for callers that only need the repos near the top and want it fast, e.g.
  # the machine setup right after cloning just the home and browser-profiles repos.
  SHALLOW_MAXDEPTH = 3

  # setup_dev_environment runs hourly from cron and costs seconds of mise/direnv forks even when
  # nothing changed. It skips the per-directory work while the digest of every candidate
  # directory's mise config / .envrc files (paths + mtimes) is unchanged and was recorded less
  # than SETUP_STAMP_MAX_AGE seconds ago. The stamp file holds the digest; its mtime is the age.
  SETUP_STAMP_NAME = 'dev-environment-setup-stamp'
  SETUP_STAMP_MAX_AGE = 24 * 3600

  # Set to a non-empty value to run the full setup regardless of the stamp.
  FORCE_ENV_VAR = 'FORCE_DEV_ENV_SETUP'

  # Installs any missing tool versions declared via mise config files across all git repos
  # and their ancestor directories. Skips silently if mise is not on PATH.
  #
  # @param shared_dirs [Array<String>, nil] Pre-collected ancestor dirs (avoids
  #   a second find traversal when collect_ancestor_dirs was already called by
  #   the same script). Pass nil to trigger collection internally.
  # @param maxdepth [Integer] How deep to search for git repos (ignored when shared_dirs is given).
  # @return [Hash, nil] CollectionProcessor results (nil when mise is not installed)
  def install_mise_versions(shared_dirs: nil, maxdepth: DEFAULT_MAXDEPTH)
    Logging.run_script_result('install_mise_versions', 'Installing mise in all git repos and ancestors') do
      unless Mise.available?
        Logging.debug "Couldn't find 'mise' in PATH -- skipping mise config loading"
        return
      end

      all_dirs = shared_dirs || collect_ancestor_dirs(maxdepth: maxdepth)

      # Filter to dirs that actually have a mise config, then sort by depth so
      # parents come before children (shallower paths have fewer separators).
      sorted = all_dirs.select { |dir| Mise.config?(dir) }.sort_by { |d| d.count(File::SEPARATOR) }

      # Use CollectionProcessor for unified progress logging and error tracking
      results = CollectionProcessor.process_items(
        sorted,
        operation_desc: 'Installing mise tools'
      ) do |dir, _idx, _total|
        dir_colored = dir.to_s.cyan

        trust_success = Mise.trust(dir) do |status, output_msg|
          exit_code = status&.exitstatus || 'unknown'
          Logging.warn("mise trust failed in '#{dir_colored}' (status: #{exit_code})#{output_msg}")
        end

        install_exitstatus = Mise.install(dir)
        install_success = install_exitstatus.zero?
        Logging.warn("mise install failed in '#{dir_colored}' (exit code: #{install_exitstatus})") unless install_success

        # Return boolean: true only if both operations succeeded
        trust_success && install_success
      end

      Logging.print_results_summary(results)
      results
    end
  end

  # Activates (allows and evaluates) the .envrc of every directory that has one across all
  # git repos and their ancestor directories. Skips silently if direnv is not on PATH.
  #
  # @param shared_dirs [Array<String>, nil] See install_mise_versions.
  # @param maxdepth [Integer] See install_mise_versions.
  # @return [Hash, nil] CollectionProcessor results (nil when direnv is not installed)
  def activate_all_direnv_configs(shared_dirs: nil, maxdepth: DEFAULT_MAXDEPTH)
    Logging.run_script_result('activate_all_direnv_configs', 'Activating direnv configs in all git repos and ancestors') do
      unless Direnv.available?
        Logging.debug "Couldn't find 'direnv' in PATH -- skipping direnv config loading"
        return
      end

      all_dirs = shared_dirs || collect_ancestor_dirs(maxdepth: maxdepth)

      # Filter to dirs with .envrc, sort parents before children.
      dirs_with_envrc = all_dirs
        .select { |dir| Direnv.envrc?(dir) }
        .sort_by { |d| d.count(File::SEPARATOR) }

      # Use CollectionProcessor for unified progress logging and error tracking
      results = CollectionProcessor.process_items(
        dirs_with_envrc,
        operation_desc: 'Activating direnv in'
      ) do |dir, _idx, _total|
        Direnv.activate(dir)
      end

      Logging.print_results_summary(results)
      results
    end
  end

  # Runs both mise installation and direnv activation in a single pass, collecting ancestor
  # directories once and reusing them for both operations. This avoids redundant filesystem
  # traversals -- saves 200-500ms per run compared to calling install_mise_versions and
  # activate_all_direnv_configs independently.
  #
  # Designed for callers that need both operations (e.g., software-updates-cron.rb).
  # Single-operation callers should continue using the individual methods.
  #
  # Skipped while nothing changed (see SETUP_STAMP_NAME); the stamp is only refreshed after a
  # run in which every directory succeeded, so failures are retried on the next call.
  #
  # @param maxdepth [Integer] How deep to search for git repos.
  # @param force [Boolean] Run even when the stamp says nothing changed (also: FORCE_ENV_VAR).
  def setup_dev_environment(maxdepth: DEFAULT_MAXDEPTH, force: false)
    Logging.run_script('setup_dev_environment') do
      # Collect ancestor dirs once, reuse for both operations
      shared_dirs = collect_ancestor_dirs(maxdepth: maxdepth)

      digest = _config_digest(shared_dirs)
      stamp = EnvVars::XDG_CACHE_HOME.join(SETUP_STAMP_NAME)
      forced = force || !ENV.fetch(FORCE_ENV_VAR, '').empty?
      if !forced && _stamp_current?(stamp, digest)
        Logging.debug "Dev environment config files unchanged since the last setup -- skipping mise/direnv setup (set #{FORCE_ENV_VAR}=1 to force)"
        return
      end

      # Both methods receive shared_dirs and skip their own collection
      direnv_results = activate_all_direnv_configs(shared_dirs: shared_dirs, maxdepth: maxdepth)
      mise_results = install_mise_versions(shared_dirs: shared_dirs, maxdepth: maxdepth)

      _write_stamp(stamp, digest) if [direnv_results, mise_results].all? { |results| results.nil? || results[:failed].empty? }
    end
  end

  # Finds all git repos under HOME, DOTFILES_DIR, and PROJECTS_BASE_DIR (up to a
  # given depth) and returns a deduplicated array of every ancestor
  # directory from each repo root up to (and including) HOME.
  #
  # @param maxdepth [Integer] How deep to search for git repos.
  # @return [Array<String>] Unique ancestor directory paths.
  def collect_ancestor_dirs(maxdepth: DEFAULT_MAXDEPTH)
    home = EnvVars::HOME

    dirs = [home, EnvVars::DOTFILES_DIR, EnvVars::PROJECTS_BASE_DIR]

    repo_roots = GitWorkspace.find_git_repos(
      dirs: dirs,
      maxdepth: maxdepth,
      additional_prune: %w[Library Caches], # Add to defaults (node_modules, .cache, .Trash)
      skip_symlinks: true
    )

    # Walk up from each repo root to HOME, collecting all ancestors
    GitWorkspace.collect_ancestors(
      repo_roots,
      stop_at: home,
      include_repo_root: true,
      include_stop_boundary: true
    )
  end

  private

  # Digest of every mise config file and .envrc in +dirs+, by path and mtime.
  #
  # @param dirs [Array<String, Pathname>]
  # @return [String] hex digest
  def _config_digest(dirs)
    require 'digest/md5'

    watched = Mise::CONFIG_FILES + ['.envrc']
    entries = dirs.sort_by(&:to_s).flat_map do |dir|
      # One directory listing instead of a stat per candidate name
      present = _watched_children(dir, watched)
      present.sort.map { |name| "#{File.join(dir.to_s, name)}\0#{File.mtime(File.join(dir.to_s, name)).to_f}" }
    rescue SystemCallError
      # a file vanished between listing and stat
      ["#{dir}\0gone"]
    end
    Digest::MD5.hexdigest(entries.join("\n"))
  end

  # Names from +watched+ present in +dir+; empty when the directory cannot be listed.
  def _watched_children(dir, watched)
    Dir.children(dir.to_s) & watched
  rescue SystemCallError
    []
  end

  private_class_method :_config_digest, :_watched_children

  # @return [Boolean] whether +stamp+ holds +digest+ and is younger than SETUP_STAMP_MAX_AGE
  def _stamp_current?(stamp, digest)
    stamp.file? && !Core.elapsed?(stamp.mtime.to_i, SETUP_STAMP_MAX_AGE) && stamp.read(encoding: 'UTF-8') == digest
  end

  private_class_method :_stamp_current?

  def _write_stamp(stamp, digest)
    stamp.dirname.mkpath
    stamp.write(digest)
  end

  private_class_method :_write_stamp
end
