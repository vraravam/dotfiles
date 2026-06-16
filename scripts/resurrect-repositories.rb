#!/usr/bin/env ruby

# frozen_string_literal: true

# file location: <anywhere; but advisable in the PATH>

# It assumes the following:
#   1. Ruby language is present in the system prior to this script being run.

require 'open3'
require 'pathname'
require 'set'
require 'shellwords'
require 'yaml'

require_relative 'utilities/cli_parser'
require_relative 'utilities/collection_processor'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/logging'

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

parser.abort_with_usage('Exactly one of -g, -r, or -c must be specified.') if options.empty? || options.size > 1

# Constants
ORIGIN_NAME = 'origin' # Standard name for the primary remote
FOLDER_KEY_NAME = 'folder' # Key name in YAML for the repository dir
REMOTE_KEY_NAME = 'remote' # Key name for the primary remote
OTHER_REMOTES_KEY_NAME = 'other_remotes' # Key name for additional remotes
POST_CLONE_KEY_NAME = 'post_clone' # Key name for post-clone commands

# Expands environment variables in a string.
# Handles multiple ${VAR} patterns. If an environment variable is not set,
# the placeholder ${VAR} is kept and a warning is printed (not accumulated in summary).
#
# @param dir [Object] The value in which to expand `${VAR}` patterns.
#   Non-String values and strings without `${` are returned unchanged.
# @return [Object] The string with all matching `${VAR}` patterns expanded,
#   or the original object if it was not a String or did not contain `${...}` patterns.
def _find_and_replace_env_var(dir)
  # Early exit if dir is not a string or doesn't contain the pattern
  return dir unless dir.is_a?(String) && dir.include?('${')

  dir.gsub(/\$\{(.*?)\}/) do |match|
    key = Regexp.last_match(1)
    ENV.fetch(key) do
      warn("Environment variable '#{key}' not set. Keeping placeholder '#{match}'.")
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
def _find_and_reverse_replace_env_var(dir)
  # NOTE: List order matters -- more specific (deeper) paths must come before their parents.
  # e.g. PROJECTS_BASE_DIR (a sub-path of HOME) must precede HOME; otherwise HOME would
  # match first and leave the PROJECTS_BASE_DIR-specific portion unexpanded.
  env_vars = %w[PROJECTS_BASE_DIR HOME]
  env_vars.each do |env_var|
    value = ENV.fetch(env_var, nil)
    next if nil_or_empty?(value)
    return dir.sub(value, "${#{env_var}}").strip if dir.start_with?(value)
  end
  dir
end

# Reports a git operation failure by recording a warning with the operation description,
# exit status, and optional stderr output.
#
# @param operation_desc [String] Description of the failed operation (e.g., "Failed to add remote 'upstream'").
# @param status [Process::Status] The status object from Open3.capture3.
# @param stderr [String] The stderr output from the git command.
# @return [void]
def _report_git_failure(operation_desc, status, stderr)
  message = "#{operation_desc} (status: #{status.exitstatus})"
  message += "\nSTDERR: #{stderr.strip}".red unless nil_or_empty?(stderr.strip)
  record_warning(message)
end

# Finds all Git repositories on disk starting from a given path.
# It uses the `find` command to locate .git directories.
#
# @param path [String] The base path to search for Git repositories.
# @return [Array<String>] A sorted, deduplicated array of absolute paths to the root
#   directories of discovered Git repositories (i.e. the parent of each +.git+ dir).
#   Returns an empty array on failure.
def _find_git_repos_from_disk(path)
  # Using array form for command execution safety if path contains special characters
  # Optimization: Use -print0 and handle dirname in Ruby to avoid spawning a process for every match
  cmd = ['find', path.to_s, '-name', '.git', '-type', 'd', '-not', '-regex', '.*/\\..*/\\.git', '-prune', '-print0']
  stdout_str, stderr_str, status = Open3.capture3(*cmd)

  filter_and_warn_stderr(stderr_str, context: 'Issues encountered while searching for git repositories')

  if status.success? || !nil_or_empty?(stdout_str.strip) # Process output if command was successful or if there's any output despite error
    stdout_str.split("\0").map { |git_path| Pathname.new(git_path).dirname.to_s }.uniq.sort
  else
    # This case means find command failed AND produced no output, a more critical failure.
    record_error("`find` command failed (status #{status.exitstatus}) and produced no output.")
    record_error("STDERR from find: #{stderr_str}") unless nil_or_empty?(stderr_str.strip)
    []
  end
rescue Errno::ENOENT # Specific rescue for `find` not being found
  record_error('`find` command not found. Please ensure it is installed and in your PATH.')
  []
rescue StandardError => e # Catch other potential errors during command execution
  record_error("Error executing find command: #{e.message}")
  []
end

# Reads repository configurations from a YAML file.
# It filters for active repositories and expands environment variables in dir paths.
#
# @param filename [String] The path to the YAML configuration file.
# @return [Array<Hash>] An array of repository configuration hashes.
def _read_git_repos_from_file(filename)
  filename = Pathname.new(filename) unless filename.is_a?(Pathname)
  repositories = Array(YAML.safe_load(filename.read)).select { |repo| repo['active'] }
  repositories.each do |repo|
    if repo[FOLDER_KEY_NAME].is_a?(String)
      repo[FOLDER_KEY_NAME] = _find_and_replace_env_var(repo[FOLDER_KEY_NAME].strip)
    else
      # Provide more context for the warning
      repo_identifier = repo[REMOTE_KEY_NAME] || repo.inspect # Use remote URL or full inspect if no remote
      record_warning("Repository entry '#{repo_identifier.cyan}' has invalid or missing '#{FOLDER_KEY_NAME}'. Skipping environment variable expansion for its dir.")
    end
  end
  repositories
end

# Applies a filter to a list of repositories or repository paths.
# The filter is a regular expression string matched against the repository dir path.
#
# @param repos [Array<String, Hash>] An array of repository paths (Strings)
#   or repository configuration hashes (where each hash is expected to have a `FOLDER_KEY_NAME` key).
# @param filter [String] The regular expression string to filter by.
#   If nil or empty, the original `repos` array is returned.
# @return [Array<String, Hash>] The filtered array, maintaining the type of elements from the input `repos` array.
def _apply_filter(repos, filter)
  return repos if nil_or_empty?(filter)

  repos.select do |repo_item|
    path_to_check = repo_item.is_a?(String) ? repo_item : repo_item[FOLDER_KEY_NAME]
    next false if nil_or_empty?(path_to_check) # Skip if path is nil or empty

    _find_and_replace_env_var(path_to_check).strip.match?(/#{filter}/i)
  end
end

# Generates a hash containing information about a single Git repository.
# This includes its dir path, active status, primary remote URL, and other remotes.
#
# @param dir [String] The path to the Git repository directory.
# @return [Hash] A hash with repository details (folder, active, remote, other_remotes).
#                The 'post_clone' key is intentionally not added here as per the script's design for generation.
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

# Resurrects a single repository based on its configuration.
# This involves cloning if it doesn't exist, verifying the clone, ensuring remotes are
# correctly configured, fetching all data, and running post-clone commands.
# On FIRST_INSTALL, clone_repo_into uses --depth=1 automatically (shallow clone).
#
# @param repo [Hash] The repository configuration hash. Expected keys include
#   `folder`, `remote`, `other_remotes` (optional), and `post_clone` (optional).
# @param idx [Integer] The index of the current repository in the processing list (for logging).
# @param total [Integer] The total number of repositories to process (for logging).
# @return [Boolean] Returns false for fatal failures (clone failure, verification failure)
#   which abort processing of this repo and mark it as failed. Returns true for success,
#   or when non-fatal failures (remote configuration, fetch, post-clone commands) are
#   logged as warnings but allow the repo to complete processing.
def _resurrect_each(repo, idx, total)
  dir = repo[FOLDER_KEY_NAME] # Assumed to be an absolute, resolved path
  Pathname.new(dir).mkpath

  existing_remotes = {} # Store existing remotes {name => url}
  # NOTE: clone_repo_into is a shell function defined in .shellrc, which is sourced
  # automatically via .zshenv on every zsh invocation -- so a login shell (`-l`) is
  # sufficient; no explicit `source .shellrc` is needed.
  # The remote URL and folder come from a trusted YAML config authored by the user,
  # but we still use `/bin/zsh -lc` explicitly (rather than a bare string passed to
  # capture3) to make the shell invocation unambiguous and to avoid surprises from $SHELL.
  # clone_repo_into automatically uses --depth=1 (shallow clone) when FIRST_INSTALL is set.
  clone_command = "clone_repo_into #{repo[REMOTE_KEY_NAME].shellescape} #{dir.shellescape}"
  stdout_str, stderr_str, status = Open3.capture3({ 'FORCE_COLOR' => '1' }, '/bin/zsh', '-lc', clone_command)
  print stdout_str
  unless status.success?
    # Clone failure is fatal for this repo -- cannot proceed without a cloned repository
    error_message = "Failed to clone '#{repo[REMOTE_KEY_NAME].cyan}' into '#{dir.cyan}' (status: #{status.exitstatus})"
    error_message += "\nClone command STDERR:\n#{stderr_str}" unless nil_or_empty?(stderr_str.strip)
    record_error(error_message)
    return false
  end

  # After cloning, verify the origin URL using GitProcessor
  git = GitProcessor.new(dir: dir)
  section_header2('Clone verification')
  cloned_origin_url = git.remote_url(name: ORIGIN_NAME)
  if cloned_origin_url
    existing_remotes[ORIGIN_NAME] = cloned_origin_url
    if cloned_origin_url != repo[REMOTE_KEY_NAME]
      # Verification failure is fatal for this repo -- wrong URL means wrong code
      record_error("Cloned origin URL '#{cloned_origin_url.cyan}' differs from config '#{repo[REMOTE_KEY_NAME].cyan}' for '#{dir.cyan}'")
      return false
    end
  else
    # Verification failure is fatal for this repo -- cannot confirm clone succeeded
    record_error("Could not verify origin remote URL after cloning '#{dir.cyan}'")
    return false
  end

  # Add missing 'other_remotes'
  # Remote configuration failures are non-fatal -- origin is correct, just can't add/update additional remotes
  section_header2('Remote configuration')
  git.each_remote do |name, url|
    existing_remotes[name] = url
  end
  debug("Existing remotes: #{existing_remotes.keys.join(', ')}") unless nil_or_empty?(existing_remotes)
  if repo[OTHER_REMOTES_KEY_NAME].is_a?(Hash)
    repo[OTHER_REMOTES_KEY_NAME].each do |name, remote|
      if existing_remotes.key?(name)
        if existing_remotes[name] != remote
          # Remote exists but URL is different
          info("Updating remote '#{name}' URL from '#{existing_remotes[name]}' to '#{remote}'")
          _stdout, stderr, status = git.set_remote_url(name, remote)
          unless status.success?
            _report_git_failure("Failed to update URL for remote '#{name}' in repo '#{dir.cyan}'", status, stderr)
          end
        end
      else
        info("Adding remote '#{name}' -> '#{remote}'")
        _stdout, stderr, status = git.add_remote(name, remote)
        unless status.success?
          _report_git_failure("Failed to add remote '#{name}' for repo '#{dir.cyan}'", status, stderr)
        end
      end
    end
  end

  # Fetch failures are non-fatal -- repository exists and is usable, just couldn't pull latest changes
  section_header2('Fetching all remotes and tags...')
  _stdout, stderr, status = git.fetch_all
  unless status.success?
    _report_git_failure("Failed to fetch all remotes and tags for repo '#{dir.cyan}'", status, stderr)
  end

  return unless repo[POST_CLONE_KEY_NAME].is_a?(Array) && !repo[POST_CLONE_KEY_NAME].empty?

  # Post-clone command failures are non-fatal -- repository is usable, just missing post-setup steps
  section_header2('Running post-clone commands')
  # Dir.chdir with a block automatically restores the original directory when the block exits,
  # even if an exception is raised -- no manual cleanup needed.
  Dir.chdir(dir) do
    repo[POST_CLONE_KEY_NAME].each do |command_str|
      debug("Executing: #{command_str.dump}")
      _stdout, stderr, status = Open3.capture3(command_str)
      unless status.success?
        _report_git_failure("Post-clone command #{command_str.dump} failed for repo '#{dir.cyan}'", status, stderr)
      end
    end
  end

  true # Success -- repo cloned and configured (non-fatal warnings may have been logged)
end

# Verifies that the repositories defined in the configuration file match
# the Git repositories found on disk within a specified scope.
# It reports any discrepancies.
#
# @param repositories [Array<Hash>] An array of repository configurations from the YAML file.
# @param discovered_count [Integer] Total count of repos before any filter was applied, used for the summary log.
# @param filter [String] A filter string (regex) to apply to repository paths before comparison.
# @param ref_dir [String, nil] Optional base directory to scope the comparison to (already expanded).
# @return [void] Exits with 1 if discrepancies are found.
def _verify_all(repositories, discovered_count, filter, ref_dir: nil)
  # Get dir paths from the YAML configuration (already filtered by FILTER if it was set).
  # filter_map polyfill in enumerable_ext.rb covers Ruby 2.6 (system Ruby on vanilla macOS).
  yml_dirs = repositories.filter_map { |repo| repo[FOLDER_KEY_NAME] }.uniq.sort
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

  puts('')
  info('Summary'.yellow)
  puts("  Discovered repositories: #{discovered_count.to_s.purple}")
  puts("  After filter:            #{repositories.length.to_s.purple}") unless nil_or_empty?(filter)
  puts("  Verified entries:        #{common_repos.length.to_s.green}")
  puts("  Common repositories:\n  #{common_repos.map(&:cyan).join("\n  ")}")
  if diff_repos.any?
    record_warning("Please correlate the following #{diff_repos.length.to_s.red} differences in projects manually:\n  #{diff_repos.map(&:cyan).join("\n  ")}")
    print_script_summary(script_start_time)
    @has_failures = true
  else
    success('Everything is kosher!')
  end
end

private :_find_and_replace_env_var, :_find_and_reverse_replace_env_var,
        :_report_git_failure, :_find_git_repos_from_disk, :_read_git_repos_from_file,
        :_apply_filter, :_generate_each, :_resurrect_each, :_verify_all

# main program
filter = EnvVars.filter

# Increment script depth and register at_exit decrement. print_script_start checks
# outermost_script? to decide whether to print the banner.
# Both calls must come before any logging.
increment_script_depth
script_start_time = print_script_start

if options[:generate]
  section_header('Generating repository configuration')
  discovery_dir = Pathname.new(options[:generate]).expand_path.to_s
  info("#{'Discovering repos under discovery directory:'.yellow} '#{discovery_dir.cyan}'")
  info("#{'Using filter:'.yellow} '#{filter.cyan}'") unless nil_or_empty?(filter)
  repositories = _find_git_repos_from_disk(discovery_dir)
  discovered_count = repositories.length
  repositories = _apply_filter(repositories, filter)
  generated = repositories.map { |dir| _generate_each(dir) }
  puts generated.to_yaml

  puts('')
  info('Summary'.yellow)
  puts("  Discovered repositories: #{discovered_count.to_s.purple}")
  puts("  After filter:            #{repositories.length.to_s.purple}") unless nil_or_empty?(filter)
  puts("  Generated entries:       #{generated.length.to_s.green}")
elsif options[:resurrect]
  section_header('Resurrecting repositories')
  config_file = Pathname.new(options[:resurrect]).expand_path.to_s
  info("#{'Config file:'.yellow} '#{config_file.cyan}'")
  info("#{'Using filter:'.yellow} '#{filter.cyan}'") unless nil_or_empty?(filter)
  repositories = _read_git_repos_from_file(config_file)
  repositories = _apply_filter(repositories, filter)

  results = CollectionProcessor.process_items(
    repositories,
    item_name_proc: ->(repo) { repo[FOLDER_KEY_NAME] },
    operation_desc: 'Resurrecting'
  ) do |repo, idx, total|
    _resurrect_each(repo, idx, total)
  end

  print_results_summary(results)
  print_script_summary(script_start_time)
  # Set @has_failures flag if any repos failed. The exit code at the end of the
  # script checks this flag and exits with code 1, which propagates to the calling
  # shell for error detection in loops.
  @has_failures = true if results[:failed].any?
elsif options[:check]
  section_header('Verifying repositories')
  config_file = Pathname.new(options[:check]).expand_path.to_s
  info("#{'Config file:'.yellow} '#{config_file.cyan}'")
  info("#{'Using filter:'.yellow} '#{filter.cyan}'") unless nil_or_empty?(filter)
  reference_dir = EnvVars.ref_folder
  info("#{'Reference dir:'.yellow} '#{reference_dir.cyan}'") unless nil_or_empty?(reference_dir)
  repositories = _read_git_repos_from_file(config_file)
  discovered_count = repositories.length
  repositories = _apply_filter(repositories, filter)
  _verify_all(repositories, discovered_count, filter, ref_dir: reference_dir)
end

print_script_summary(script_start_time)

# Exit with appropriate code. Exit 1 if there were any failures (repos with fatal
# errors that returned false) OR any warnings (fetch failures, post-clone failures, etc.).
# This is intentionally stricter than other scripts because the calling shell
# function (resurrect_tracked_repos) needs to distinguish "clean success" from
# "success with issues" to avoid printing "Successfully resurrected all tracked
# git repos" when there were fetch failures or other warnings.
exit(1) if defined?(@has_failures) && @has_failures
exit(1) if step_warnings.any?
