#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/resurrect-repositories.rb
#
# Generates, resurrects, or verifies a set of known git repositories from a YAML config file.
#
# It assumes the following:
#   1. Ruby language is present in the system prior to this script being run.
#
# Usage:
#   Standalone: resurrect-repositories.rb [-g <folder>] [-r <config-file>] [-c <config-file>]
#   Module:     ResurrectRepositories.run(generate: nil, resurrect: nil, check: nil, filter: nil)

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
require_relative 'utilities/logging'
require_relative 'utilities/macos'
require_relative 'utilities/path_utils'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module ResurrectRepositories
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # Constants
  ORIGIN_NAME = 'origin' # Standard name for the primary remote
  FOLDER_KEY_NAME = 'folder' # Key name in YAML for the repository dir
  REMOTE_KEY_NAME = 'remote' # Key name for the primary remote
  OTHER_REMOTES_KEY_NAME = 'other_remotes' # Key name for additional remotes
  POST_CLONE_KEY_NAME = 'post_clone' # Key name for post-clone commands

  # Repository configuration object with validation
  class RepositoryConfig
    attr_reader :folder, :remote, :other_remotes, :post_clone

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
        Logging.record_warning("Repository entry '#{repo_id}' has invalid or missing 'folder' field")
        return nil
      end

      # Validate remote
      if nil_or_empty?(remote) || !remote.is_a?(String) || nil_or_empty?(remote.strip)
        Logging.record_warning("Repository entry with folder '#{folder}' has invalid or missing 'remote' field")
        return nil
      end

      # Expand environment variables in folder path
      expanded_folder = ResurrectRepositories.expand_env_vars(folder.strip)
      if nil_or_empty?(expanded_folder)
        Logging.record_warning("Repository entry '#{remote}' has folder with unresolvable environment variables: '#{folder}'")
        return nil
      end

      # Validate other_remotes (optional)
      # Flay detects similarity between these validation blocks (other_remotes and post_clone).
      # This is intentional - each field has different type requirements (Hash vs Array).
      # Extracting a generic validator would obscure the specific type validation logic.
      other_remotes = hash[OTHER_REMOTES_KEY_NAME]
      if other_remotes && !other_remotes.is_a?(Hash)
        Logging.record_warning("Repository entry '#{remote}' has invalid 'other_remotes' (must be a hash)")
        return nil
      end

      # Validate post_clone (optional)
      post_clone = hash[POST_CLONE_KEY_NAME]
      if post_clone && !post_clone.is_a?(Array)
        Logging.record_warning("Repository entry '#{remote}' has invalid 'post_clone' (must be an array)")
        return nil
      end

      new(
        folder: expanded_folder,
        remote: remote.strip,
        other_remotes: other_remotes || {},
        post_clone: post_clone || []
      )
    end

    def initialize(folder:, remote:, other_remotes:, post_clone:)
      @folder = folder
      @remote = remote
      @other_remotes = other_remotes
      @post_clone = post_clone
    end

    # Returns true if this repository should be processed based on filter
    #
    # @param filter [String, nil] Regex filter to match against folder path
    # @return [Boolean]
    def matches_filter?(filter)
      nil_or_empty?(filter) || @folder.match?(/#{filter}/i)
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
        POST_CLONE_KEY_NAME => nil_or_empty?(@post_clone) ? nil : @post_clone
      }.compact
    end
  end

  # Public API method.
  #
  # @param generate [String, nil] Directory to scan for repos and generate YAML config
  # @param resurrect [String, nil] Config file to resurrect repos from
  # @param check [String, nil] Config file to verify against disk
  # @param filter [String, nil] Regex filter to apply (uses ENV['FILTER'] if nil)
  # @return [Boolean] true on success, false on error
  def run(generate: nil, resurrect: nil, check: nil, filter: nil)
    options_count = [generate, resurrect, check].compact.size
    Logging.error 'Exactly one of generate, resurrect, or check must be specified.' if options_count != 1

    filter ||= EnvVars.filter
    @has_failures = false

    if generate
      _run_generate(generate, filter)
    elsif resurrect
      _run_resurrect(resurrect, filter)
    elsif check
      _run_check(check, filter)
    end

    !@has_failures
  end

  # Run generate mode: scan directory and output YAML config
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
  def _run_resurrect(config_file, filter)
    config_file = Pathname.new(config_file).expand_path

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
      @has_failures = true if results[:failed].any?
      @has_failures = true if Logging.warnings? || Logging.errors?
    end
  end

  private_class_method :_run_resurrect

  # Run check mode: verify repos on disk match config file
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

  # Expands environment variables in a string.
  # Handles multiple ${VAR} patterns. If an environment variable is not set,
  # the placeholder ${VAR} is kept and a warning is printed (not accumulated in summary).
  # Public method called by RepositoryConfig.from_hash for validation.
  #
  # @param dir [Object] The value in which to expand `${VAR}` patterns.
  #   Non-String values and strings without `${` are returned unchanged.
  # @return [Object] The string with all matching `${VAR}` patterns expanded,
  #   or the original object if it was not a String or did not contain `${...}` patterns.
  def self.expand_env_vars(dir)
    # Early exit if dir is not a string or doesn't contain the pattern
    return dir unless dir.is_a?(String) && dir.include?('${')

    dir.gsub(/\$\{(.*?)\}/) do |match|
      key = Regexp.last_match(1)
      ENV.fetch(key) do
        Logging.warn("Environment variable '#{key}' not set. Keeping placeholder '#{match}'.")
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
    env_vars = %w[PROJECTS_BASE_DIR XDG_CONFIG_HOME XDG_DATA_HOME HOME]
    env_vars.each do |env_var|
      value = ENV.fetch(env_var, nil)
      next if nil_or_empty?(value)
      return dir.sub(value, "${#{env_var}}").strip if dir.start_with?(value)
    end
    dir
  end

  private_class_method :_find_and_reverse_replace_env_var

  # Finds all Git repositories on disk starting from a given path.
  # Delegates to CollectionProcessor.find_directories_matching with git-specific
  # configuration (exclude hidden directories, transform to repo roots).
  #
  # @param path [String] The base path to search for Git repositories.
  # @return [Array<String>] A sorted, deduplicated array of absolute paths to the root
  #   directories of discovered Git repositories (i.e. the parent of each +.git+ dir).
  #   Returns an empty array on failure.
  # :reek:UtilityFunction -- Stateless helper for git repo discovery (intentional delegation)
  def _find_git_repos_from_disk(path)
    CollectionProcessor.find_directories_matching(
      dirs: [path],
      name_pattern: '.git',
      mindepth: 1,
      maxdepth: 999,
      exclude_regex: '.*/\\..*/\\.git',
      transform_result: ->(git_path) { Pathname.new(git_path).dirname.to_s },
      noise_patterns: ['Permission denied', 'No such file or directory']
    )
  end

  private_class_method :_find_git_repos_from_disk

  # Reads repository configurations from a YAML file.
  # Validates and filters for active repositories, expands environment variables in dir paths.
  #
  # @param filename [String] The path to the YAML configuration file.
  # @return [Array<RepositoryConfig>] An array of validated repository configuration objects.
  # :reek:FeatureEnvy -- Operates on method parameter for file I/O (intentional)
  def _read_git_repos_from_file(filename)
    filename = Pathname.new(filename) unless filename.is_a?(Pathname)

    # Use explicit UTF-8 encoding to avoid "invalid byte sequence in US-ASCII".
    raw_repos = Array(YAML.safe_load(filename.read(encoding: 'UTF-8')))

    # Filter active repos and convert to RepositoryConfig objects
    raw_repos.filter_map do |repo_hash|
      next unless repo_hash.is_a?(Hash) && repo_hash['active']

      RepositoryConfig.from_hash(repo_hash)
    end
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

    repos.select do |repo_item|
      case repo_item
      when String
        repo_item.match?(/#{filter}/i)
      when RepositoryConfig
        repo_item.matches_filter?(filter)
      when Hash
        path = repo_item[FOLDER_KEY_NAME]
        !nil_or_empty?(path) && path.match?(/#{filter}/i)
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
  #                The 'post_clone' key is intentionally not added here as per the script's design for generation.
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
  # @param repo [RepositoryConfig] The repository configuration object.
  # @param idx [Integer] The index of the current repository in the processing list (for logging).
  # @param total [Integer] The total number of repositories to process (for logging).
  # @return [Boolean] Returns false for fatal failures (clone failure, verification failure)
  #   which abort processing of this repo and mark it as failed. Returns true for success,
  #   or when non-fatal failures (remote configuration, fetch, post-clone commands) are
  #   logged as warnings but allow the repo to complete processing.
  # :reek:DuplicateMethodCall -- check_status pattern used with different error messages
  # :reek:FeatureEnvy -- Local hash tracks state during multi-step remote configuration
  def _resurrect_each(repo)
    dir = repo.folder # Assumed to be an absolute, resolved path
    dir_colored = dir.cyan
    remote_url = repo.remote
    post_clone_commands = repo.post_clone

    PathUtils.ensure_directories_exist(dir)

    # Clone or update the repository using GitProcessor module method
    unless GitProcessor.clone_repo_into(remote_url, dir)
      # Clone failure is fatal for this repo -- cannot proceed without a cloned repository
      Logging.record_error("Failed to clone '#{remote_url.cyan}' into '#{dir_colored}'")
      return false
    end

    # After cloning, verify the origin URL using GitProcessor
    git = GitProcessor.new(dir: dir)
    existing_remotes = {} # Store existing remotes {name => url}
    Logging.with_step('clone verification', 'Clone verification') do
      cloned_origin_url = git.remote_url(name: ORIGIN_NAME)
      if cloned_origin_url
        existing_remotes[ORIGIN_NAME] = cloned_origin_url
        if cloned_origin_url != remote_url
          # Verification failure is fatal for this repo -- wrong URL means wrong code
          Logging.record_error("Cloned origin URL '#{cloned_origin_url.cyan}' differs from config '#{remote_url.cyan}' for '#{dir_colored}'")
          return false
        end
      else
        # Verification failure is fatal for this repo -- cannot confirm clone succeeded
        Logging.record_error("Could not verify origin remote URL after cloning '#{dir_colored}'")
        return false
      end
    end

    # Add missing 'other_remotes'
    # Remote configuration failures are non-fatal -- origin is correct, just can't add/update additional remotes
    Logging.with_step('remote configuration', 'Remote configuration') do
      git.each_remote do |name, url|
        existing_remotes[name] = url
      end
      Logging.debug("Existing remotes: #{existing_remotes.keys.join(', ')}") unless nil_or_empty?(existing_remotes)
      unless nil_or_empty?(repo.other_remotes)
        # Flay detects similarity between set_remote_url and add_remote check_status blocks.
        # This is intentional - each operation (update vs add) has different context and error messages.
        repo.other_remotes.each do |name, remote|
          if existing_remotes.key?(name)
            if existing_remotes[name] != remote
              # Remote exists but URL is different
              Logging.info("Updating remote '#{name}' URL from '#{existing_remotes[name]}' to '#{remote}'")
              stdout, stderr, status = git.set_remote_url(name, remote)
              CommandUtils.check_status(stdout, stderr, status) do |st, output_msg|
                Logging.record_warning("Failed to update URL for remote '#{name}' in repo '#{dir_colored}' (status: #{st.exitstatus})#{output_msg}")
              end
            end
          else
            Logging.info("Adding remote '#{name}' -> '#{remote}'")
            stdout, stderr, status = git.add_remote(name, remote)
            CommandUtils.check_status(stdout, stderr, status) do |st, output_msg|
              Logging.record_warning("Failed to add remote '#{name}' for repo '#{dir_colored}' (status: #{st.exitstatus})#{output_msg}")
            end
          end
        end
      end
    end

    # Clean up stale lock files before fetch to avoid "File exists" errors
    index_lock = Pathname.new(dir).join('.git', 'index.lock')
    commit_graph_lock = Pathname.new(dir).join('.git', 'objects', 'info', 'commit-graphs', 'commit-graph-chain.lock')
    index_lock.delete if index_lock.file?
    commit_graph_lock.delete if commit_graph_lock.file?

    # Fetch failures are non-fatal -- repository exists and is usable, just couldn't pull latest changes
    Logging.with_step('fetching remotes', 'Fetching all remotes and tags...') do
      stdout, stderr, status = git.fetch_all
      CommandUtils.check_status(stdout, stderr, status) do |st, output_msg|
        Logging.record_warning("Failed to fetch all remotes and tags for repo '#{dir_colored}' (status: #{st.exitstatus})#{output_msg}")
      end
    end

    return true unless post_clone_commands.is_a?(Array) && !nil_or_empty?(post_clone_commands)

    # Post-clone command failures are non-fatal -- repository is usable, just missing post-setup steps
    Logging.with_step('post-clone commands', 'Running post-clone commands') do
      # Dir.chdir with a block automatically restores the original directory when the block exits,
      # even if an exception is raised -- no manual cleanup needed.
      Dir.chdir(dir) do
        post_clone_commands.each do |command_str|
          Logging.debug("Executing: #{command_str.dump}")
          CommandUtils.capture_output(command_str) do |status, output_msg|
            Logging.record_warning("Post-clone command #{command_str.dump} failed for repo '#{dir_colored}' (status: #{status.exitstatus})#{output_msg}")
          end
        end
      end
    end

    true # Success -- repo cloned and configured (non-fatal warnings may have been logged)
  end

  private_class_method :_resurrect_each

  # Verifies that the repositories defined in the configuration file match
  # the Git repositories found on disk within a specified scope.
  # It reports any discrepancies.
  #
  # @param repositories [Array<Hash>] An array of repository configurations from the YAML file.
  # @param discovered_count [Integer] Total count of repos before any filter was applied, used for the summary log.
  # @param filter [String] A filter string (regex) to apply to repository paths before comparison.
  # @param ref_dir [String, nil] Optional base directory to scope the comparison to (already expanded).
  # @return [void] Sets @has_failures if discrepancies are found.
  def _verify_all(repositories, discovered_count, filter, ref_dir: nil)
    # Get dir paths from the YAML configuration (already filtered by FILTER if it was set).
    # filter_map polyfill in enumerable_ext.rb covers Ruby 2.6 (system Ruby on vanilla macOS).
    yml_dirs = repositories.filter_map(&:folder).uniq.sort
    if ref_dir
      # If ref_dir is set, filter yml_dirs to include only those starting with this path
      # or exactly matching this path (if ref_dir itself is a repo path).
      # Ensure comparison is against a directory prefix by normalizing paths.
      path_prefix_for_selection = ref_dir.chomp(File::SEPARATOR)
      yml_dirs = yml_dirs.select do |dir|
        normalized_dir = dir.chomp(File::SEPARATOR)
        normalized_dir == path_prefix_for_selection || normalized_dir.start_with?(path_prefix_for_selection + File::SEPARATOR)
      end
    end

    # _find_git_repos_from_disk already returns a sorted unique array; _apply_filter preserves uniqueness.
    local_dirs = _apply_filter(_find_git_repos_from_disk(ref_dir || EnvVars::HOME), filter).sort

    # Convert to Sets for O(1) membership checks on the symmetric difference
    yml_set = Set.new(yml_dirs)
    local_set = Set.new(local_dirs)
    diff_repos = (local_set ^ yml_set).to_a.sort # ^ = symmetric difference
    common_repos = (local_set & yml_set).to_a.sort # & = intersection

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
  parser = CliParser.parse('[-g <folder>] [-r <config-file>] [-c <config-file>]') do |opts|
    opts.separator 'Generates, resurrects, or verifies a set of known git repositories from a YAML config file.'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('-g', '--generate FOLDER', 'Generate configuration from FOLDER onto stdout (usually on current laptop)',
            "  Note: this option will not handle 'post_clone' commands in the generated yaml structure") do |dir|
      options[:generate] = dir
    end
    opts.on('-r', '--resurrect CONFIG_FILE', "Resurrect 'known' codebases from CONFIG_FILE (usually on fresh laptop)") do |file|
      options[:resurrect] = file
    end
    opts.on('-c', '--check CONFIG_FILE', "Verify 'known' codebases from CONFIG_FILE (most likely will also need to specify REF_FOLDER)") do |file|
      options[:check] = file
    end
    opts.separator ''
    opts.separator 'Environment variables:'.purple
    opts.separator "  #{'FILTER'.yellow}      can be used to apply the operation to a subset of codebases (will match on folder or repo name)"
    opts.separator "  #{'REF_FOLDER'.yellow}  can be used to apply a filter when verifying against a specific yaml file"
  end

  parser.abort_with_usage('Exactly one of -g, -r, or -c must be specified.') if nil_or_empty?(options) || options.size > 1

  # Standard dual-mode CLI wrapper pattern (Flay similarity with recreate-repository.rb is intentional).
  # See ruby-scripting.md section "Dual-Mode Ruby Scripts".
  Logging.run_script do
    success = ResurrectRepositories.run(
      generate: options[:generate],
      resurrect: options[:resurrect],
      check: options[:check]
    )
    exit(success ? 0 : 1)
  end
end
