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
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # How deep below HOME, DOTFILES_DIR and PROJECTS_BASE_DIR git repos are searched for.
  DEFAULT_MAXDEPTH = 6

  # A shallower search for callers that only need the repos near the top and want it fast, e.g.
  # the machine setup right after cloning just the home and browser-profiles repos.
  SHALLOW_MAXDEPTH = 3

  # Installs any missing tool versions declared via mise config files across all git repos
  # and their ancestor directories. Skips silently if mise is not on PATH.
  #
  # @param shared_dirs [Array<String>, nil] Pre-collected ancestor dirs (avoids
  #   a second find traversal when collect_ancestor_dirs was already called by
  #   the same script). Pass nil to trigger collection internally.
  # @param maxdepth [Integer] How deep to search for git repos (ignored when shared_dirs is given).
  def install_mise_versions(shared_dirs: nil, maxdepth: DEFAULT_MAXDEPTH)
    Logging.run_script('install_mise_versions', 'Installing mise in all git repos and ancestors') do
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
    end
  end

  # Activates (allows and evaluates) the .envrc of every directory that has one across all
  # git repos and their ancestor directories. Skips silently if direnv is not on PATH.
  #
  # @param shared_dirs [Array<String>, nil] See install_mise_versions.
  # @param maxdepth [Integer] See install_mise_versions.
  def activate_all_direnv_configs(shared_dirs: nil, maxdepth: DEFAULT_MAXDEPTH)
    Logging.run_script('activate_all_direnv_configs', 'Activating direnv configs in all git repos and ancestors') do
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
  # @param maxdepth [Integer] How deep to search for git repos.
  def setup_dev_environment(maxdepth: DEFAULT_MAXDEPTH)
    Logging.run_script('setup_dev_environment') do
      # Collect ancestor dirs once, reuse for both operations
      shared_dirs = collect_ancestor_dirs(maxdepth: maxdepth)

      # Both methods receive shared_dirs and skip their own collection
      activate_all_direnv_configs(shared_dirs: shared_dirs, maxdepth: maxdepth)
      install_mise_versions(shared_dirs: shared_dirs, maxdepth: maxdepth)
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
end
