#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/resurrect-repositories.rb
#
# Generates, resurrects, verifies, or exports git bundles for a set of known git
# repositories from a YAML config file.
#
# It assumes the following:
#   1. Ruby language is present in the system prior to this script being run.
#
# Environment variable support:
#   - FILTER and REF_FOLDER scope which repos are processed / verified against (see -h).
#   - The YAML config's 'folder' and 'bundle' values support '${VAR}' expansion (eg
#     "${PROJECTS_BASE_DIR}/oss/foo") via ENV.fetch -- an unset var keeps the literal
#     placeholder and logs a warning rather than failing. A bare '~' is NOT expanded;
#     use '${HOME}' instead. 'other_remotes' values are used as-is (no expansion).
#   - 'post_checkout' commands run inside clone_repo_into itself (in-process, .shellrc
#     functions already in scope), immediately once a fresh clone/import checks out
#     files -- strictly before origin/branch cleanup, the reftable-migrate/unshallow/
#     maintain/siu chain, and any other_remotes fallback-clone attempt or fetch. Joined
#     with ' && ' and 'eval'd as a single string, unlike 'post_clone' below.
#   - 'branch' (string) is the branch to clone (clone_repo_into's optional 3rd argument);
#     omit it to clone the remote's default branch.
#   - 'post_clone' commands are run through a shell, so normal shell '$VAR'/'${VAR}'
#     expansion applies there at execution time -- a different mechanism from the above.
#   - '-g' (generate) does the reverse: absolute paths discovered on disk are rewritten
#     back to their '${VAR}' placeholder form (checking PROJECTS_BASE_DIR, XDG_CONFIG_HOME,
#     XDG_DATA_HOME, HOME in that order) so the generated YAML stays portable.
#
# Usage:
#   Standalone: resurrect-repositories.rb [-g <folder>] [-r <config-file>] [-a] [-c <config-file>] [-b <config-file>]
#   Module:     ResurrectRepositories.run(generate: nil, resurrect: nil, resurrect_all: false, check: nil,
#                                         bundle_export: nil, filter: nil)

require 'open3'
require 'pathname'
require 'set'
require 'shellwords'
require 'yaml'

require_relative 'utilities/collection_processor'
require_relative 'utilities/command_utils'
require_relative 'utilities/core'
require_relative 'utilities/enumerable_ext'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/git_workspace'
require_relative 'utilities/logging'
require_relative 'utilities/macos'
require_relative 'utilities/path_utils'

# Module contains the business logic.
# Returns true/false instead of calling exit().
# :reek:TooManyConstants -- One constant per YAML key name; grouping them into a
# single Hash/Struct would obscure the direct correspondence to YAML keys used
# throughout RepositoryConfig.from_hash/to_h below.
module ResurrectRepositories
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Constants
  ORIGIN_NAME = 'origin' # Standard name for the primary remote
  FOLDER_KEY_NAME = 'folder' # Key name in YAML for the repository dir
  REMOTE_KEY_NAME = 'remote' # Key name for the primary remote
  OTHER_REMOTES_KEY_NAME = 'other_remotes' # Key name for additional remotes
  POST_CHECKOUT_KEY_NAME = 'post_checkout' # Key name for post-checkout commands
  POST_CLONE_KEY_NAME = 'post_clone' # Key name for post-clone commands
  BUNDLE_KEY_NAME = 'bundle' # Key name for an optional local git bundle file
  BRANCH_KEY_NAME = 'branch' # Key name for an optional branch to clone
  # Glob (relative to PERSONAL_CONFIGS_DIR) matching every repository catalogue that
  # resurrect_all mode processes.
  CATALOGUE_GLOB = 'repositories-*.yml'
  # Preference order for reverse env-var substitution in _find_and_reverse_replace_env_var
  # (most specific/deepest path first -- see that method's docs for why order matters).
  ENV_VAR_REVERSE_LOOKUP_ORDER = %w[PROJECTS_BASE_DIR XDG_CONFIG_HOME XDG_DATA_HOME HOME].freeze

  # Repository configuration object with validation
  class RepositoryConfig
    # Explicit (not left to a caller's top-level `include Logging`) so the class also works when
    # ResurrectRepositories is used as a module from another script.
    include Core
    extend Core

    attr_reader :folder, :remote, :other_remotes, :post_checkout, :post_clone, :bundle, :branch

    # Creates a new repository configuration from a hash.
    #
    # @param hash [Hash] Repository configuration from YAML
    # @return [RepositoryConfig, nil] Config object or nil if validation fails
    def self.from_hash(hash)
      # Validate required fields
      unless hash.is_a?(Hash)
        Logging.record_warning("Invalid repository entry (not a hash): #{hash.inspect}")
        return nil
      end

      folder = hash[FOLDER_KEY_NAME]
      remote = hash[REMOTE_KEY_NAME]

      # Validate folder
      if nil_or_empty?(folder) || !folder.is_a?(String) || nil_or_empty?(folder.strip)
        repo_id = remote || hash.inspect
        Logging.record_warning("Repository entry '#{repo_id.to_s.cyan}' has invalid or missing 'folder' field")
        return nil
      end

      # Validate remote
      if nil_or_empty?(remote) || !remote.is_a?(String) || nil_or_empty?(remote.strip)
        Logging.record_warning("Repository entry with folder '#{folder.to_s.cyan}' has invalid or missing 'remote' field")
        return nil
      end

      # Expand environment variables in folder path
      expanded_folder = ResurrectRepositories.expand_env_vars(folder.strip)
      if nil_or_empty?(expanded_folder)
        Logging.record_warning("Repository entry '#{remote.to_s.cyan}' has folder with unresolvable environment variables: '#{folder.to_s.cyan}'")
        return nil
      end

      # Validate the optional fields. Each has its own type requirement, reported by _invalid_field.
      other_remotes = hash[OTHER_REMOTES_KEY_NAME]
      return _invalid_field(remote, OTHER_REMOTES_KEY_NAME, 'a hash') if other_remotes && !other_remotes.is_a?(Hash)

      # post_checkout: shell commands run right after checkout (see #initialize).
      post_checkout = hash[POST_CHECKOUT_KEY_NAME]
      return _invalid_field(remote, POST_CHECKOUT_KEY_NAME, 'an array') if post_checkout && !post_checkout.is_a?(Array)

      post_clone = hash[POST_CLONE_KEY_NAME]
      return _invalid_field(remote, POST_CLONE_KEY_NAME, 'an array') if post_clone && !post_clone.is_a?(Array)

      # bundle: path to a local git bundle file. When present and the target folder is not
      # yet a git repo, resurrect mode imports from this bundle instead of cloning from
      # 'remote' over the network; bundle-export mode writes to this path.
      bundle = hash[BUNDLE_KEY_NAME]
      return _invalid_field(remote, BUNDLE_KEY_NAME, 'a non-empty string') if bundle && (!bundle.is_a?(String) || nil_or_empty?(bundle.strip))

      expanded_bundle = ResurrectRepositories.expand_env_vars(bundle&.strip)

      # branch: branch to clone instead of the remote's default (see clone_repo_into).
      branch = hash[BRANCH_KEY_NAME]
      return _invalid_field(remote, BRANCH_KEY_NAME, 'a non-empty string') if branch && (!branch.is_a?(String) || nil_or_empty?(branch.strip))

      new(
        folder: expanded_folder,
        remote: remote.strip,
        other_remotes: other_remotes || {},
        post_checkout: post_checkout || [],
        post_clone: post_clone || [],
        bundle: expanded_bundle,
        branch: branch&.strip
      )
    end

    # Records the warning for an optional field of the wrong type.
    #
    # @param remote [String] The entry's remote, used to identify it in the message.
    # @param key [String] The offending YAML key.
    # @param expected [String] Human-readable required type, e.g. 'a hash'.
    # @return [nil] Always nil, so callers can `return _invalid_field(...)`.
    def self._invalid_field(remote, key, expected)
      Logging.record_warning("Repository entry '#{remote.to_s.cyan}' has invalid '#{key}' (must be #{expected})")
      nil
    end
    private_class_method :_invalid_field

    # Creates a repository configuration. Prefer .from_hash for YAML-sourced data --
    # this constructor performs no validation of its own.
    #
    # @param folder [String] Absolute, already-expanded path to the repository directory.
    # @param remote [String] Primary remote URL (the 'origin' remote).
    # @param other_remotes [Hash<String, String>] Additional remote name -> URL pairs.
    # @param post_checkout [Array<String>] Shell commands 'eval'd once immediately after a
    #   fresh clone/import checks out files -- strictly before origin/branch cleanup, the
    #   reftable-migrate/unshallow/maintain/siu chain, and any other_remotes fallback-clone
    #   attempt or fetch. For repos with files needing permissions fixed before anything
    #   else uses them (e.g. $HOME's '.ssh'/'.gnupg' keys) -- see clone_repo_into's own
    #   comment in .shellrc for the full rationale. Joined with ' && ' and passed as a
    #   single 'eval'd string (unlike 'post_clone', each entry does not run independently).
    # @param post_clone [Array<String>] Shell commands to run once after cloning.
    # @param bundle [String, nil] Optional path to a local git bundle file to import from/export to.
    # @param branch [String, nil] Optional branch to clone instead of the remote's default.
    def initialize(folder:, remote:, other_remotes:, post_checkout:, post_clone:, bundle: nil, branch: nil)
      @folder = folder
      @remote = remote
      @other_remotes = other_remotes
      @post_checkout = post_checkout
      @post_clone = post_clone
      @bundle = bundle
      @branch = branch
    end

    # Returns true if this repository should be processed based on filter
    #
    # @param filter_re [Regexp, nil] Pre-compiled case-insensitive regex to match against folder path
    # @return [Boolean]
    def matches_filter?(filter_re)
      nil_or_empty?(filter_re) || @folder.match?(filter_re)
    end

    # Keyword arguments for GitProcessor.clone_repo_into (everything except the url and
    # destination, which differ per clone attempt). 'post_checkout' entries are joined with
    # ' && ' into the single string clone_repo_into 'eval's.
    #
    # @return [Hash{Symbol => Object}]
    def clone_options
      {
        branch: @branch,
        bundle: @bundle,
        post_checkout_hook: @post_checkout.join(' && ')
      }
    end

    # Converts back to hash for YAML generation
    #
    # @return [Hash]
    def to_h
      {
        FOLDER_KEY_NAME => @folder,
        'active' => true,
        REMOTE_KEY_NAME => @remote,
        OTHER_REMOTES_KEY_NAME => nil_or_empty?(@other_remotes) ? nil : @other_remotes,
        POST_CHECKOUT_KEY_NAME => nil_or_empty?(@post_checkout) ? nil : @post_checkout,
        POST_CLONE_KEY_NAME => nil_or_empty?(@post_clone) ? nil : @post_clone,
        BUNDLE_KEY_NAME => @bundle,
        BRANCH_KEY_NAME => @branch
      }.compact
    end
  end

  # Public API method.
  #
  # @param generate [String, nil] Directory to scan for repos and generate YAML config
  # @param resurrect [String, nil] Config file to resurrect repos from
  # @param resurrect_all [Boolean] Resurrect every repositories-*.yml catalogue in
  #   PERSONAL_CONFIGS_DIR, then run the post-clone developer-environment setup
  # @param check [String, nil] Config file to verify against disk
  # @param bundle_export [String, nil] Config file to export git bundles from (for repos with a 'bundle' key)
  # @param filter [String, nil] Regex filter to apply (uses ENV['FILTER'] if nil)
  # @return [Boolean] true on success, false on error
  def run(generate: nil, resurrect: nil, resurrect_all: false, check: nil, bundle_export: nil, filter: nil)
    options_count = [generate, resurrect, (true if resurrect_all), check, bundle_export].compact.size
    Logging.error 'Exactly one of generate, resurrect, resurrect_all, check, or bundle_export must be specified.' if options_count != 1

    filter ||= EnvVars.filter
    @has_failures = false

    if generate
      _run_generate(generate, filter)
    elsif resurrect
      _run_resurrect(resurrect, filter)
    elsif resurrect_all
      _run_resurrect_all(filter)
    elsif check
      _run_check(check, filter)
    elsif bundle_export
      _run_bundle_export(bundle_export, filter)
    end

    !@has_failures
  end

  # Run generate mode: scan directory and output YAML config
  #
  # @param discovery_dir [String] Directory to scan on disk for git repositories.
  # @param filter [String, nil] Regex filter string to apply to discovered repo paths.
  # @return [void]
  def _run_generate(discovery_dir, filter)
    Logging.with_step('generate config', 'Generating repository configuration') do
      discovery_dir = Pathname.new(discovery_dir).expand_path.to_s
      Logging.info("#{'Discovering repos under discovery directory:'.yellow} '#{discovery_dir.cyan}'")
      Logging.info("#{'Using filter:'.yellow} '#{filter.cyan}'") unless nil_or_empty?(filter)
      repositories = _find_git_repos_from_disk(discovery_dir)
      discovered_count = repositories.length
      repositories = _apply_filter(repositories, filter)
      generated = repositories.map { |dir| _generate_each(dir) }
      puts generated.to_yaml

      puts ''
      Logging.info('Summary'.yellow)
      Logging.emit("Discovered repositories: #{discovered_count.to_s.purple}", level: 1)
      Logging.emit("After filter:            #{repositories.length.to_s.purple}", level: 1) unless nil_or_empty?(filter)
      Logging.emit("Generated entries:       #{generated.length.to_s.green}", level: 1)
    end
  end

  private_class_method :_run_generate

  # Run resurrect mode: clone/update repos from config file
  #
  # @param config_file [String, Pathname] Path to the YAML config file to resurrect from.
  # @param filter [String, nil] Regex filter string to apply to configured repo paths.
  # @return [Boolean] true if any repo in this file failed or any warning/error was
  #   recorded while processing it (also sets @has_failures). Warnings recorded before this
  #   call are deliberately ignored so callers processing several files can tell which
  #   specific file had problems.
  def _run_resurrect(config_file, filter)
    config_file = Pathname.new(config_file).expand_path
    warnings_before = Logging.step_warnings.size
    errors_before = Logging.step_errors.size
    file_failed = false

    Logging.with_step('resurrect repos', "Processing '#{config_file.cyan}'") do
      _log_filter_if_present(filter)
      repositories = _read_git_repos_from_file(config_file.to_s)
      repositories = _apply_filter(repositories, filter)

      results = CollectionProcessor.process_items(
        repositories,
        item_name_proc: :folder.to_proc,
        operation_desc: 'Resurrecting'
      ) do |repo, _idx, _total|
        _resurrect_each(repo)
      end

      Logging.print_results_summary(results)
      file_failed = results[:failed].any? ||
                    Logging.step_warnings.size > warnings_before ||
                    Logging.step_errors.size > errors_before
    end

    @has_failures = true if file_failed
    file_failed
  end

  private_class_method :_run_resurrect

  # Run resurrect-all mode: resurrect every repositories-*.yml catalogue found in
  # PERSONAL_CONFIGS_DIR, then run the post-clone developer-environment setup (mise
  # versions, direnv allow) and refresh the repo-alias cache. Catalogues that had
  # failures are listed together in one warning so the end-of-run summary points at the
  # exact files to re-run with '-r'.
  #
  # @param filter [String, nil] Regex filter string to apply to configured repo paths.
  # @return [void] Sets @has_failures if any catalogue had failures.
  def _run_resurrect_all(filter)
    Logging.with_step('resurrect all', 'Resurrecting all tracked git repos') do
      config_dir = EnvVars::PERSONAL_CONFIGS_DIR
      catalogues = config_dir.directory? ? config_dir.glob(CATALOGUE_GLOB).select(&:file?).sort : []

      if catalogues.empty?
        Logging.debug "Skipping resurrecting of repositories since no '#{CATALOGUE_GLOB.cyan}' found in '#{config_dir.cyan}'"
      else
        failed_files = catalogues.select { |file| _run_resurrect(file, filter) }
        if failed_files.empty?
          Logging.success 'Successfully resurrected all tracked git repos'
        else
          failed_list = Logging.join_array(failed_files, :red)
          Logging.record_warning("#{"Failed to process #{failed_files.length} file(s):".red}\n#{failed_list}")
        end
      end

      # Post-clone operations for installing system dependencies. Both are idempotent and
      # safe to run even when no catalogue was found (e.g. only the bootstrap repos exist).
      GitWorkspace.setup_dev_environment(first_install: EnvVars.first_install?)
      GitWorkspace.regenerate_repo_aliases
    end
  end

  private_class_method :_run_resurrect_all

  # Run check mode: verify repos on disk match config file
  #
  # @param config_file [String, Pathname] Path to the YAML config file to verify against.
  # @param filter [String, nil] Regex filter string to apply to configured repo paths.
  # @return [void] Sets @has_failures if discrepancies are found (via _verify_all).
  def _run_check(config_file, filter)
    config_file = Pathname.new(config_file).expand_path

    Logging.with_step('check repos', "Verifying '#{config_file.cyan}'") do
      _log_filter_if_present(filter)
      reference_dir = EnvVars.ref_folder
      Logging.info("#{'Reference dir:'.yellow} '#{reference_dir.cyan}'") unless nil_or_empty?(reference_dir)
      repositories = _read_git_repos_from_file(config_file.to_s)
      discovered_count = repositories.length
      repositories = _apply_filter(repositories, filter)
      _verify_all(repositories, discovered_count, filter, ref_dir: reference_dir)
    end
  end

  private_class_method :_run_check

  # Run bundle-export mode: create git bundle files for repos that have a 'bundle' key.
  #
  # @param config_file [String, Pathname] Path to the YAML config file to read repos from.
  # @param filter [String, nil] Regex filter string to apply to configured repo paths.
  # @return [void] Sets @has_failures if any bundle export failed.
  def _run_bundle_export(config_file, filter)
    config_file = Pathname.new(config_file).expand_path

    Logging.with_step('bundle export', "Processing '#{config_file.cyan}'") do
      _log_filter_if_present(filter)
      repositories = _read_git_repos_from_file(config_file.to_s)
      repositories = _apply_filter(repositories, filter)
      repositories = repositories.reject { |repo| nil_or_empty?(repo.bundle) }

      if repositories.empty?
        Logging.info("No repository entries with a '#{BUNDLE_KEY_NAME.yellow}' key found -- nothing to export.")
        next
      end

      results = CollectionProcessor.process_items(
        repositories,
        item_name_proc: :folder.to_proc,
        operation_desc: 'Exporting'
      ) do |repo, _idx, _total|
        _bundle_export_each(repo)
      end

      Logging.print_results_summary(results)
      @has_failures = true if results[:failed].any?
      @has_failures = true if Logging.warnings? || Logging.errors?
    end
  end

  private_class_method :_run_bundle_export

  # Exports a single repository to its configured 'bundle' file.
  #
  # @param repo [RepositoryConfig] The repository configuration object (must have a 'bundle' value).
  # @return [Boolean] true on success, false on error.
  # :reek:UtilityFunction -- Stateless helper operating on a RepositoryConfig (correct design)
  def _bundle_export_each(repo)
    folder = repo.folder
    dir_colored = folder.cyan
    bundle_colored = repo.bundle.cyan

    unless GitProcessor.repo?(folder)
      Logging.record_error("'#{dir_colored}' is not a git repo -- cannot export bundle '#{bundle_colored}'")
      return false
    end

    Logging.info("Exporting '#{dir_colored}' to bundle '#{bundle_colored}' (this may take a while for large repos)...")
    exported = false
    GitProcessor.new(dir: folder) { |git| exported = git.bundle_create(file: repo.bundle) }
    unless exported
      Logging.record_error("Failed to export '#{dir_colored}' to bundle '#{bundle_colored}'")
      return false
    end

    Logging.success("Successfully exported '#{dir_colored}' to bundle '#{bundle_colored}'")
    true
  end

  private_class_method :_bundle_export_each

  # Expands environment variables in a string.
  # Handles multiple ${VAR} patterns. If an environment variable is not set,
  # the placeholder ${VAR} is kept and a warning is printed (not accumulated in summary).
  # Public method called by RepositoryConfig.from_hash for validation.
  #
  # Safe to call with nil (e.g. an optional YAML field that wasn't present) --
  # returned unchanged, no error. Callers do not need to guard against nil
  # themselves.
  #
  # @param dir [Object] The value in which to expand `${VAR}` patterns.
  #   nil, other non-String values, and strings without `${` are returned unchanged.
  # @return [Object] The string with all matching `${VAR}` patterns expanded,
  #   or the original object if it was nil, not a String, or did not contain `${...}` patterns.
  def self.expand_env_vars(dir)
    # Early exit if dir is not a string or doesn't contain the pattern
    return dir unless dir.is_a?(String) && dir.include?('${')

    dir.gsub(/\$\{(.*?)\}/) do |match|
      key = Regexp.last_match(1)
      ENV.fetch(key) do
        Logging.warn("Environment variable '#{key.yellow}' not set. Keeping placeholder '#{match.yellow}'.")
        match
      end
    end
  end

  # Replaces occurrences of pre-expanded env-var values with their `${VAR}` placeholders
  # so that generated YAML references env vars rather than hard-coded paths.
  # Only the first matching env-var prefix is replaced (first-match-wins).
  #
  # @param dir [String] The string in which to substitute env-var values back to placeholders.
  # @return [String] The string with the first matching env-var value replaced by its placeholder,
  #   or the original string if no configured env-var value is non-empty and a prefix of +dir+.
  # :reek:FeatureEnvy -- Operates on method parameter (intentional string transformation)
  def _find_and_reverse_replace_env_var(dir)
    # NOTE: List order matters -- more specific (deeper) paths must come before their parents.
    # e.g. PROJECTS_BASE_DIR (a sub-path of HOME) must precede HOME; otherwise HOME would
    # match first and leave the PROJECTS_BASE_DIR-specific portion unexpanded.
    ENV_VAR_REVERSE_LOOKUP_ORDER.each do |env_var|
      value = ENV.fetch(env_var, nil)
      next if nil_or_empty?(value)
      return dir.sub(value, "${#{env_var}}").strip if dir.start_with?(value)
    end
    dir
  end

  private_class_method :_find_and_reverse_replace_env_var

  # Single source of truth for the order in which this script lists and processes
  # repositories, used by every mode (generate, resurrect, check, bundle-export).
  # Alphabetical by path, case-insensitive, with the exact (case-sensitive) path as a
  # tie-breaker so ordering stays deterministic when two paths differ only by case.
  # A parent folder always sorts before its own subfolders (it is a string prefix of
  # them), so a repo nested inside another configured repo is processed after its parent.
  #
  # @param items [Array] Paths (Strings), or any objects a block can extract a path from.
  # @yield [item] Optional; returns the path to sort +item+ by (e.g. +repo.folder+).
  #   Without a block, each item is itself treated as the path.
  # @return [Array] A new array holding the same items, sorted by path.
  # :reek:UtilityFunction -- Stateless sorting helper (intentional)
  def _sort_by_path(items)
    items.sort_by do |item|
      path = (block_given? ? yield(item) : item).to_s
      [path.downcase, path]
    end
  end

  private_class_method :_sort_by_path

  # Finds all Git repositories on disk starting from a given path.
  # Delegates to CollectionProcessor.find_directories_matching with git-specific
  # configuration (exclude hidden directories, transform to repo roots).
  #
  # @param path [String] The base path to search for Git repositories.
  # @return [Array<String>] A deduplicated array of absolute paths to the root
  #   directories of discovered Git repositories (i.e. the parent of each +.git+ dir),
  #   ordered by _sort_by_path. Returns an empty array on failure.
  # :reek:UtilityFunction -- Stateless helper for git repo discovery (intentional delegation)
  def _find_git_repos_from_disk(path)
    repos = CollectionProcessor.find_directories_matching(
      dirs: [path],
      name_pattern: '.git',
      mindepth: 1,
      maxdepth: 999,
      exclude_regex: '.*/\\..*/\\.git',
      transform_result: ->(git_path) { Pathname.new(git_path).dirname.to_s },
      noise_patterns: ['Permission denied', 'No such file or directory']
    )
    # CollectionProcessor sorts case-sensitively (shared with other callers); re-sort here
    # so this script's ordering is uniform across modes.
    _sort_by_path(repos)
  end

  private_class_method :_find_git_repos_from_disk

  # Reads repository configurations from a YAML file.
  # Validates and filters for active repositories, expands environment variables in dir paths.
  #
  # The result is ordered by _sort_by_path on the expanded folder rather than left in YAML
  # file order, so every mode (resurrect, check, bundle-export) processes and reports
  # repositories in a predictable order regardless of how the file was authored.
  #
  # @param filename [String, Pathname] The path to the YAML configuration file.
  # @return [Array<RepositoryConfig>] Validated repository configuration objects, sorted by folder.
  # :reek:FeatureEnvy -- Operates on method parameter for file I/O (intentional)
  def _read_git_repos_from_file(filename)
    filename = Pathname.new(filename) unless filename.is_a?(Pathname)

    # Use explicit UTF-8 encoding to avoid "invalid byte sequence in US-ASCII".
    raw_repos = Array(YAML.safe_load(filename.read(encoding: 'UTF-8')))

    # Filter active repos and convert to RepositoryConfig objects
    repos = raw_repos.filter_map do |repo_hash|
      next unless repo_hash.is_a?(Hash) && repo_hash['active']

      RepositoryConfig.from_hash(repo_hash)
    end

    _sort_by_path(repos, &:folder)
  end

  private_class_method :_read_git_repos_from_file

  # Applies a filter to a list of repositories or repository paths.
  # The filter is a regular expression string matched against the repository dir path.
  #
  # @param repos [Array<String, Hash, RepositoryConfig>] An array of repository paths (Strings),
  #   repository configuration hashes, or RepositoryConfig objects.
  # @param filter [String] The regular expression string to filter by.
  #   If nil or empty, the original `repos` array is returned.
  # @return [Array<String, Hash, RepositoryConfig>] The filtered array, maintaining the type of elements from the input `repos` array.
  # :reek:FeatureEnvy -- Polymorphic dispatch on array elements (intentional type checking)
  def _apply_filter(repos, filter)
    return repos if nil_or_empty?(filter)

    # Compile once here rather than once per repo_item -- avoids recompiling the same
    # Regexp on every element of repos.select (see ruby-scripting.md's hot-path guidance).
    filter_re = Regexp.new(filter, Regexp::IGNORECASE)

    repos.select do |repo_item|
      case repo_item
      when String
        repo_item.match?(filter_re)
      when RepositoryConfig
        repo_item.matches_filter?(filter_re)
      when Hash
        path = repo_item[FOLDER_KEY_NAME]
        !nil_or_empty?(path) && path.match?(filter_re)
      else
        false
      end
    end
  end

  private_class_method :_apply_filter

  # Generates a hash containing information about a single Git repository.
  # This includes its dir path, active status, primary remote URL, and other remotes.
  #
  # @param dir [String] The path to the Git repository directory.
  # @return [Hash] A hash with repository details (folder, active, remote, other_remotes).
  #                The 'post_checkout'/'post_clone' keys are intentionally not added here as per the script's design for generation.
  # :reek:FeatureEnvy -- Builds hash for YAML serialization (intentional data structure construction)
  def _generate_each(dir)
    hash = { folder: _find_and_reverse_replace_env_var(dir), active: true }

    # Get origin URL and other remotes using GitProcessor
    GitProcessor.new(dir: dir) do |git|
      hash[:remote] = git.remote_url || ''

      # Collect other remotes (excluding origin)
      other_remotes = {}
      git.each_remote do |name, url|
        other_remotes[name] = url unless name == ORIGIN_NAME
      end

      hash[OTHER_REMOTES_KEY_NAME] = other_remotes unless nil_or_empty?(other_remotes)
    end

    hash.transform_keys(&:to_s)
  end

  private_class_method :_generate_each

  # Resurrects a single repository based on its configuration.
  # This involves cloning if it doesn't exist, verifying the clone, ensuring remotes are
  # correctly configured, fetching all data, and running post-clone commands.
  # On FIRST_INSTALL, GitProcessor.clone_repo_into uses --depth=1 (shallow clone).
  #
  # If cloning from 'remote' fails and 'dir' still isn't a git repo, each 'other_remotes'
  # entry is tried in turn (in YAML order) as an alternate clone source -- e.g. a mirror
  # reachable via a different transport/backup mechanism -- before giving up entirely.
  # This only ever engages on a fresh clone: a pre-existing repo already succeeded
  # (clone_repo_into is a no-op) regardless of which remote it was originally cloned
  # from, so no fallback attempt is made in that case.
  #
  # @param repo [RepositoryConfig] The repository configuration object.
  # @return [Boolean] Returns false for fatal failures (clone failure, verification failure)
  #   which abort processing of this repo and mark it as failed. Returns true for success,
  #   or when non-fatal failures (remote configuration, fetch, post-clone commands) are
  #   logged as warnings but allow the repo to complete processing.
  def _resurrect_each(repo)
    dir = repo.folder # Assumed to be an absolute, resolved path
    dir_colored = dir.cyan

    PathUtils.ensure_directories_exist(dir)

    effective_origin_url, remaining_other_remotes = _clone_with_fallback(repo, dir)
    unless effective_origin_url
      # Clone/import failure is fatal for this repo -- cannot proceed without a repository
      Logging.record_error("Failed to clone '#{repo.remote.cyan}' (and any configured fallback) into '#{dir_colored}'")
      return false
    end

    git = GitProcessor.new(dir: dir)
    return false unless _verify_origin(git, dir_colored, effective_origin_url, repo.other_remotes)

    _sync_other_remotes(git, dir_colored, remaining_other_remotes)
    _fetch_all_remotes(git, dir_colored)
    _run_post_clone_commands(repo.post_clone, dir, dir_colored)

    true # Success -- repo cloned and configured (non-fatal warnings may have been logged)
  end

  private_class_method :_resurrect_each

  # Clones (or imports from a bundle) the repository into +dir+, falling back to each
  # 'other_remotes' entry in YAML order when the primary 'remote' cannot be cloned.
  #
  # clone_repo_into internally decides the source: if 'dir' is not yet a git repo and
  # 'bundle' is a file that exists, it imports from the bundle instead of cloning
  # 'remote' over the network (much faster/more reliable for huge repos). If 'dir'
  # is already a git repo, both the bundle and this call are no-ops that just fall
  # through to fixing up remotes afterwards. Bundle import leaves 'origin' missing on
  # purpose (git clone <bundle-file> would otherwise point it at the literal bundle
  # path) -- _verify_origin adds it back from config. Either way, the same reftable
  # migration, maintenance, and submodule-update steps run afterward, since they live
  # inside clone_repo_into itself rather than being duplicated here.
  #
  # Fallbacks only engage when the primary clone genuinely failed, so every existing
  # single-remote repo is completely unaffected.
  #
  # @param repo [RepositoryConfig] The repository configuration.
  # @param dir [String] Absolute repository directory.
  # @return [Array(String, Hash), nil] [URL that became 'origin', remotes still to be
  #   configured], or nil when neither the primary nor any fallback could be cloned.
  #   The 'other_remotes' entry that served as the clone source is now 'origin' itself, so
  #   its name is re-purposed for the original 'remote' value: that URL failed but should
  #   still be recorded as a remote so it can be retried manually later.
  def _clone_with_fallback(repo, dir)
    clone_options = repo.clone_options
    return [repo.remote, repo.other_remotes] if GitProcessor.clone_repo_into(repo.remote, dir, **clone_options)

    repo.other_remotes.each do |name, url|
      Logging.info("Failed to clone primary remote -- trying '#{name.cyan}' ('#{url.cyan}') as a fallback clone source")
      next unless GitProcessor.clone_repo_into(url, dir, **clone_options)

      return [url, repo.other_remotes.merge(name => repo.remote)]
    end

    nil
  end

  private_class_method :_clone_with_fallback

  # Verifies the cloned 'origin' URL matches the configuration, adding a missing 'origin'
  # (e.g. after a bundle import) from config.
  #
  # @param git [GitProcessor] Processor for the repository.
  # @param dir_colored [String] Colorized directory for messages.
  # @param expected_url [String] The URL 'origin' must point at.
  # @param other_remotes [Hash{String => String}] Configured additional remotes, consulted
  #   only to explain a mismatch (see _fallback_clone_hint).
  # @return [Boolean] false when 'origin' points elsewhere or cannot be added (fatal for
  #   this repo -- wrong URL means wrong code); true otherwise.
  def _verify_origin(git, dir_colored, expected_url, other_remotes)
    Logging.with_step('clone verification', 'Clone verification') do
      cloned_origin_url = git.remote_url(name: ORIGIN_NAME)
      if cloned_origin_url
        next true if cloned_origin_url == expected_url

        Logging.record_error("Cloned origin URL '#{cloned_origin_url.cyan}' differs from config '#{expected_url.cyan}' for '#{dir_colored}'" \
                             "#{_fallback_clone_hint(cloned_origin_url, expected_url, other_remotes)}")
        next false
      end

      # Pre-existing repo with no 'origin' remote (e.g. just restored from a bundle import)
      # -- not fatal; add it from config instead of failing.
      Logging.info("No 'origin' remote found for pre-existing repo '#{dir_colored}' -- adding it from config: '#{expected_url.cyan}'")
      stdout, stderr, status = git.add_remote(ORIGIN_NAME, expected_url)
      CommandUtils.check_status_or_record(stdout, stderr, status,
                                          "Failed to add missing 'origin' remote '#{expected_url.cyan}' for repo '#{dir_colored}'", severity: :error)
    end
  end

  private_class_method :_verify_origin

  # Extra text for the origin-mismatch error when the actual 'origin' is one of the
  # configured 'other_remotes' URLs. That is the state a fallback clone leaves behind (the
  # mirror became 'origin' and the unreachable primary was kept under the mirror's name),
  # so a later run sees a mismatch the tool itself created. The mismatch stays fatal --
  # the config is the source of truth -- but the message says how to resolve it.
  #
  # @param actual_url [String] The URL 'origin' currently points at.
  # @param expected_url [String] The URL the configuration expects.
  # @param other_remotes [Hash{String => String}] Configured additional remotes.
  # @return [String] Hint text (leading space included), or '' when no entry matches.
  # :reek:UtilityFunction -- Stateless message builder (intentional)
  def _fallback_clone_hint(actual_url, expected_url, other_remotes)
    name = (other_remotes || {}).key(actual_url)
    return '' unless name

    " -- 'origin' matches 'other_remotes' entry '#{name.to_s.yellow}', which looks like an earlier fallback clone. " \
    "Either set 'remote' in the config to '#{actual_url.cyan}', or point 'origin' back at '#{expected_url.cyan}'"
  end

  private_class_method :_fallback_clone_hint

  # Adds or re-points every configured additional remote. Failures are non-fatal: 'origin'
  # is already correct, only the extra remotes could not be configured.
  #
  # @param git [GitProcessor] Processor for the repository.
  # @param dir_colored [String] Colorized directory for messages.
  # @param desired [Hash{String => String}] Remote name => URL from the configuration.
  # @return [void]
  # :reek:FeatureEnvy -- Operates on the remotes of the processor passed in
  def _sync_other_remotes(git, dir_colored, desired)
    Logging.with_step('remote configuration', 'Remote configuration') do
      existing = {}
      git.each_remote { |name, url| existing[name] = url }
      Logging.debug("Existing remotes: #{existing.keys.join(', ').yellow}") unless nil_or_empty?(existing)

      desired.each do |name, url|
        name_colored = name.to_s.yellow
        if !existing.key?(name)
          Logging.info("Adding remote '#{name_colored}' -> '#{url.to_s.cyan}'")
          stdout, stderr, status = git.add_remote(name, url)
          CommandUtils.check_status_or_record(stdout, stderr, status, "Failed to add remote '#{name_colored}' for repo '#{dir_colored}'")
        elsif existing[name] != url
          Logging.info("Updating remote '#{name_colored}' URL from '#{existing[name].to_s.cyan}' to '#{url.to_s.cyan}'")
          stdout, stderr, status = git.set_remote_url(name, url)
          CommandUtils.check_status_or_record(stdout, stderr, status, "Failed to update URL for remote '#{name_colored}' in repo '#{dir_colored}'")
        end
      end
    end
  end

  private_class_method :_sync_other_remotes

  # Fetches all remotes and tags. A failure is non-fatal: the repository exists and is
  # usable, it just could not pull the latest changes.
  #
  # @param git [GitProcessor] Processor for the repository.
  # @param dir_colored [String] Colorized directory for messages.
  # @return [void]
  def _fetch_all_remotes(git, dir_colored)
    # Stale lock files make the fetch fail with "File exists"
    git.delete_index_lock
    git.delete_commit_graph_lock

    Logging.with_step('fetching remotes', 'Fetching all remotes and tags...') do
      stdout, stderr, status = git.fetch_all
      CommandUtils.check_status_or_record(stdout, stderr, status, "Failed to fetch all remotes and tags for repo '#{dir_colored}'")
    end
  end

  private_class_method :_fetch_all_remotes

  # Runs the configured post-clone shell commands inside +dir+. Failures are non-fatal:
  # the repository is usable, just missing post-setup steps.
  #
  # @param commands [Array<String>, nil] Shell command strings.
  # @param dir [String] Directory to run them in.
  # @param dir_colored [String] Colorized directory for messages.
  # @return [void]
  def _run_post_clone_commands(commands, dir, dir_colored)
    return unless commands.is_a?(Array) && !nil_or_empty?(commands)

    Logging.with_step('post-clone commands', 'Running post-clone commands') do
      # Dir.chdir with a block restores the original directory when the block exits,
      # even if an exception is raised -- no manual cleanup needed.
      Dir.chdir(dir) do
        commands.each do |command_str|
          Logging.debug("Executing: #{command_str.dump}")
          CommandUtils.capture_output(command_str) do |status, output_msg|
            Logging.record_warning("Post-clone command #{command_str.dump} failed for repo '#{dir_colored}' (status: #{status&.exitstatus || 'unknown'})#{output_msg}")
          end
        end
      end
    end
  end

  private_class_method :_run_post_clone_commands

  # Verifies that the repositories defined in the configuration file match
  # the Git repositories found on disk within a specified scope.
  # It reports any discrepancies.
  #
  # @param repositories [Array<RepositoryConfig>] An array of repository configurations from the YAML file.
  # @param discovered_count [Integer] Total count of repos before any filter was applied, used for the summary log.
  # @param filter [String] A filter string (regex) to apply to repository paths before comparison.
  # @param ref_dir [Pathname, String, nil] Optional base directory to scope the comparison to
  #   (already expanded). EnvVars.ref_folder supplies a Pathname; it is converted to a String
  #   only where it is compared against the String folder paths from the YAML config.
  # @return [void] Sets @has_failures if discrepancies are found.
  def _verify_all(repositories, discovered_count, filter, ref_dir: nil)
    # Get dir paths from the YAML configuration (already filtered by FILTER if it was set).
    # filter_map polyfill in enumerable_ext.rb covers Ruby 2.6 (system Ruby on vanilla macOS).
    yml_dirs = _sort_by_path(repositories.filter_map(&:folder).uniq)
    if ref_dir
      # If ref_dir is set, filter yml_dirs to include only those starting with this path
      # or exactly matching this path (if ref_dir itself is a repo path).
      # Ensure comparison is against a directory prefix by normalizing paths.
      path_prefix_for_selection = ref_dir.to_s.chomp(File::SEPARATOR)
      yml_dirs = yml_dirs.select do |dir|
        normalized_dir = dir.chomp(File::SEPARATOR)
        normalized_dir == path_prefix_for_selection || normalized_dir.start_with?(path_prefix_for_selection + File::SEPARATOR)
      end
    end

    # _find_git_repos_from_disk already returns a sorted unique array; _apply_filter preserves
    # both uniqueness and order.
    local_dirs = _apply_filter(_find_git_repos_from_disk(ref_dir || EnvVars::HOME), filter)

    # Convert to Sets for O(1) membership checks on the symmetric difference
    yml_set = Set.new(yml_dirs)
    local_set = Set.new(local_dirs)
    diff_repos = _sort_by_path((local_set ^ yml_set).to_a) # ^ = symmetric difference
    common_repos = _sort_by_path((local_set & yml_set).to_a) # & = intersection

    puts ''
    Logging.info('Summary'.yellow)
    Logging.emit("Discovered repositories: #{discovered_count.to_s.purple}", level: 1)
    Logging.emit("After filter:            #{repositories.length.to_s.purple}", level: 1) unless nil_or_empty?(filter)
    Logging.emit("Verified entries:        #{common_repos.length.to_s.green}", level: 1)
    Logging.emit("Common repositories:\n#{Logging.join_array(common_repos, :cyan, level: 2)}", level: 1)
    if diff_repos.any?
      Logging.record_warning("Please correlate the following #{diff_repos.length.to_s.red} differences in projects manually:\n#{Logging.join_array(diff_repos, :cyan)}")
      @has_failures = true
    else
      Logging.success('Everything is kosher!')
    end
  end

  private_class_method :_verify_all

  # Logs filter information if present
  #
  # @param filter [String, nil] Filter string to log
  # @return [void]
  def _log_filter_if_present(filter)
    Logging.emit("#{'Using filter:'.yellow} '#{filter.cyan}'", level: 0) unless nil_or_empty?(filter)
  end

  private_class_method :_log_filter_if_present
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = {}
  parser = CliParser.parse('[-g <folder>] [-r <config-file>] [-a] [-c <config-file>] [-b <config-file>]') do |opts|
    opts.separator 'Generates, resurrects, verifies, or exports git bundles for a set of known git repositories from a YAML config file.'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('-g', '--generate FOLDER', 'Generate configuration from FOLDER onto stdout (usually on current laptop)',
            "  Note: this option will not handle 'post_checkout'/'post_clone' commands in the generated yaml structure") do |dir|
      options[:generate] = dir
    end
    opts.on('-r', '--resurrect CONFIG_FILE', "Resurrect 'known' codebases from CONFIG_FILE (usually on fresh laptop)",
            "  Repos with a 'bundle' key are imported from that file instead of cloned, if the target folder doesn't exist yet") do |file|
      options[:resurrect] = file
    end
    opts.on('-a', '--all', "Resurrect every '#{ResurrectRepositories::CATALOGUE_GLOB}' catalogue in PERSONAL_CONFIGS_DIR, then",
            '  install mise tool versions, allow direnv configs and refresh the repo aliases cache') do
      options[:resurrect_all] = true
    end
    opts.on('-c', '--check CONFIG_FILE', "Verify 'known' codebases from CONFIG_FILE (most likely will also need to specify REF_FOLDER)") do |file|
      options[:check] = file
    end
    opts.on('-b', '--bundle-export CONFIG_FILE', "Export a git bundle for each repo in CONFIG_FILE that has a 'bundle' key (usually on current laptop)") do |file|
      options[:bundle_export] = file
    end
    opts.separator ''
    opts.separator 'Environment variables:'.purple
    opts.separator "  #{'FILTER'.yellow}      can be used to apply the operation to a subset of codebases (will match on folder or repo name)"
    opts.separator "  #{'REF_FOLDER'.yellow}  can be used to apply a filter when verifying against a specific yaml file"
  end

  parser.abort_with_usage('Exactly one of -g, -r, -a, -c, or -b must be specified.') if nil_or_empty?(options) || options.size > 1

  # Standard dual-mode CLI wrapper pattern (Flay similarity with recreate-repository.rb is intentional).
  # See ruby-scripting.md section "Dual-Mode Ruby Scripts".
  Logging.run_script do
    success = ResurrectRepositories.run(
      generate: options[:generate],
      resurrect: options[:resurrect],
      resurrect_all: options[:resurrect_all],
      check: options[:check],
      bundle_export: options[:bundle_export]
    )
    exit(success ? 0 : 1)
  end
end
