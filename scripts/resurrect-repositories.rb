#!/usr/bin/env ruby

# frozen_string_literal: true

# file location: <anywhere; but advisable in the PATH>

# It assumes the following:
#   1. Ruby language is present in the system prior to this script being run.

# Ensure utilities/ is on the load path so 'require' works regardless of whether
# RUBYLIB is set (e.g. when invoked outside of an interactive zsh session).
$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'cli_parser'
include Logging

options = {}
parser = CliParser.parse('[-g <folder>] [-r <config-file>] [-c <config-file>]') do |opts|
  opts.separator 'Generates, resurrects, or verifies a set of known git repositories from a YAML config file.'
  opts.separator ''
  opts.separator 'Options:'.purple
  opts.on('-g', '--generate FOLDER', 'Generate configuration from FOLDER onto stdout (usually on current laptop)',
          "  Note: this option will not handle 'post_clone' commands in the generated yaml structure") do |folder|
    options[:generate] = folder
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

if options.empty? || options.size > 1
  parser.abort_with_usage('Exactly one of -g, -r, or -c must be specified.')
end

require 'fileutils'
require 'pathname' # System Ruby on a vanilla macOS is 2.6; Pathname must be required explicitly because autoloading is unreliable at that version.
require 'set'
require 'shellwords'
require 'yaml'
require 'open3'

# Constants
ORIGIN_NAME = 'origin' # Standard name for the primary remote
FOLDER_KEY_NAME = 'folder' # Key name in YAML for the repository folder
REMOTE_KEY_NAME = 'remote' # Key name for the primary remote
OTHER_REMOTES_KEY_NAME = 'other_remotes' # Key name for additional remotes
POST_CLONE_KEY_NAME = 'post_clone' # Key name for post-clone commands
GIT_EXECUTABLE = 'git' # Path to git executable
GIT_CONFIG_REGEXP_CMD = ['config', '--get-regexp', '^remote\\..*\\.url'].freeze # Git subcommand to find remote URLs in git config

HOME_PATH = Pathname.new(ENV.fetch('HOME')).expand_path

# Converts a number to a string and right-justifies it with spaces to a width of 2.
#
# @param num [Numeric] The number to format.
# @return [String] The formatted string.
def _justify(num)
  num.to_s.rjust(2, ' ')
end

# Expands environment variables in a string.
# Handles multiple ${VAR} patterns. If an environment variable is not set,
# the placeholder ${VAR} is kept and a warning is logged.
#
# @param folder [Object] The value in which to expand `${VAR}` patterns.
#   Non-String values and strings without `${` are returned unchanged.
# @return [Object] The string with all matching `${VAR}` patterns expanded,
#   or the original object if it was not a String or did not contain `${...}` patterns.
def _find_and_replace_env_var(folder)
  # Early exit if folder is not a string or doesn't contain the pattern
  return folder unless folder.is_a?(String) && folder.include?('${')

  folder.gsub(/\$\{(.*?)\}/) do |match|
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
# @param folder [String] The string in which to substitute env-var values back to placeholders.
# @return [String] The string with the first matching env-var value replaced by its placeholder,
#   or the original string if no configured env-var value is non-empty and a prefix of +folder+.
def _find_and_reverse_replace_env_var(folder)
  # NOTE: List order matters — more specific (deeper) paths must come before their parents.
  # e.g. PROJECTS_BASE_DIR (a sub-path of HOME) must precede HOME; otherwise HOME would
  # match first and leave the PROJECTS_BASE_DIR-specific portion unexpanded.
  env_vars = %w[PROJECTS_BASE_DIR HOME]
  env_vars.each do |env_var|
    value = ENV[env_var]
    next if nil_or_empty?(value)
    return folder.sub(value, "${#{env_var}}").strip if folder.start_with?(value)
  end
  folder
end

# Builds the base command array for executing Git commands within a specific repository folder.
# This prefix is used to target Git operations to the correct directory.
#
# @param folder [String] The path to the Git repository.
# @return [Array<String>] An array of strings representing the Git command prefix
#   (e.g., `['git', '-C', '/path/to/repo']`).
def _build_git_context(folder)
  [GIT_EXECUTABLE, '-C', folder]
end

# Checks if the given folder path is a Git repository (i.e., contains a .git directory).
#
# @param folder [String] The path to the folder to check.
# @return [true, false] True if the folder is a Git repository, false otherwise.
def git_repo?(folder)
  # Ensure folder is a string and not nil before appending path components
  folder.is_a?(String) && Dir.exist?(File.join(folder, '.git'))
end

# Fetches remote configurations using 'git config --get-regexp' and yields each remote.
#
# @param folder [String] The path to the Git repository. Used as the working directory
#   for the git command and in warning messages when the command fails.
# @yield [remote_name, remote_url] Called for each remote found.
# @yieldparam remote_name [String] The name of the remote.
# @yieldparam remote_url [String] The URL of the remote.
# @return [void] When called without a block the git command is still executed
#   but results are silently discarded.
def _find_git_remotes(folder)
  git_base_cmd = _build_git_context(folder)
  config_cmd = [*git_base_cmd, *GIT_CONFIG_REGEXP_CMD]
  stdout, stderr, status = Open3.capture3(*config_cmd)

  if status.success?
    stdout.each_line do |line|
      next if line.strip.empty?
      key, url = line.strip.split(' ', 2) # key is like 'remote.origin.url'
      remote_name = key.split('.')[1]
      yield remote_name, url if block_given?
    end
  else
    warn("Could not retrieve remotes using 'git config --get-regexp' for '#{folder.cyan}' (status: #{status.exitstatus}).")
    warn("STDERR: #{stderr.strip}".red) unless nil_or_empty?(stderr.strip)
  end
end

# Finds the URL for a specific remote in a given Git repository.
#
# @param repo_path [String] The path to the Git repository.
# @param remote_name [String] The name of the remote (e.g., 'origin').
# @return [String, nil] The URL of the remote if found, otherwise nil.
def _find_git_remote_url(repo_path, remote_name)
  _find_git_remotes(repo_path) do |name, url|
    return url if name == remote_name
  end
end

# Finds all Git repositories on disk starting from a given path.
# It uses the `find` command to locate .git directories.
#
# @param path [String] The base path to search for Git repositories.
# @return [Array<String>] A sorted, deduplicated array of absolute paths to the root
#   directories of discovered Git repositories (i.e. the parent of each +.git+ folder).
#   Returns an empty array on failure.
def _find_git_repos_from_disk(path)
  # Using array form for command execution safety if path contains special characters
  # Optimization: Use -print0 and handle dirname in Ruby to avoid spawning a process for every match
  cmd = ['find', path.to_s, '-name', '.git', '-type', 'd', '-not', '-regex', '.*/\\..*/\\.git', '-prune', '-print0']
  stdout_str, stderr_str, status = Open3.capture3(*cmd)

  unless nil_or_empty?(stderr_str)
    meaningful_errors = stderr_str.each_line.map(&:strip).reject do |line|
      nil_or_empty?(line) ||
        line.include?('Permission denied') ||
        line.include?('No such file or directory')
      # Add other common noisy messages if needed
    end
    warn("Issues encountered while searching for git repositories:\n#{meaningful_errors.join("\n")}") if meaningful_errors.any?
  end

  if status.success? || !nil_or_empty?(stdout_str.strip) # Process output if command was successful or if there's any output despite error
    stdout_str.split("\0").map { |git_path| File.dirname(git_path) }.uniq.sort
  else
    # This case means find command failed AND produced no output, a more critical failure.
    warn("`find` command failed (status #{status.exitstatus}) and produced no output.")
    warn("STDERR from find: #{stderr_str}") unless nil_or_empty?(stderr_str.strip)
    []
  end
rescue Errno::ENOENT # Specific rescue for `find` not being found
  warn('`find` command not found. Please ensure it is installed and in your PATH.')
  []
rescue StandardError => e # Catch other potential errors during command execution
  warn("Error executing find command: #{e.message}")
  []
end

# Reads repository configurations from a YAML file.
# It filters for active repositories and expands environment variables in folder paths.
#
# @param filename [String] The path to the YAML configuration file.
# @return [Array<Hash>] An array of repository configuration hashes.
def _read_git_repos_from_file(filename)
  repositories = Array(YAML.safe_load(File.read(filename))).select { |repo| repo['active'] }
  repositories.each do |repo|
    if repo[FOLDER_KEY_NAME].is_a?(String)
      repo[FOLDER_KEY_NAME] = _find_and_replace_env_var(repo[FOLDER_KEY_NAME].strip)
    else
      # Provide more context for the warning
      repo_identifier = repo[REMOTE_KEY_NAME] || repo.inspect # Use remote URL or full inspect if no remote
      warn("Repository entry '#{repo_identifier}' has invalid or missing '#{FOLDER_KEY_NAME}'. Skipping environment variable expansion for its folder.")
    end
  end
  repositories
end

# Applies a filter to a list of repositories or repository paths.
# The filter is a regular expression string matched against the repository folder path.
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
# This includes its folder path, active status, primary remote URL, and other remotes.
#
# @param folder [String] The path to the Git repository directory.
# @return [Hash] A hash with repository details (folder, active, remote, other_remotes).
#                The 'post_clone' key is intentionally not added here as per the script's design for generation.
def _generate_each(folder)
  hash = { folder: _find_and_reverse_replace_env_var(folder), active: true }
  other_remotes = {}
  _find_git_remotes(folder) do |name, url|
    other_remotes[name] = url
  end

  unless nil_or_empty?(other_remotes)
    hash[:remote] = other_remotes.delete(ORIGIN_NAME)
    hash[OTHER_REMOTES_KEY_NAME] = other_remotes
  end

  # Ensure :remote is set, even if it's an empty string (e.g. repo with no remotes)
  hash[:remote] ||= ''

  hash.transform_keys(&:to_s)
end

# Resurrects a single repository based on its configuration.
# This involves cloning if it doesn't exist, ensuring remotes are correctly configured,
# fetching all data, and running post-clone commands.
#
# @param repo [Hash] The repository configuration hash. Expected keys include
#   `folder`, `remote`, `other_remotes` (optional), and `post_clone` (optional).
# @param idx [Integer] The index of the current repository in the processing list (for logging).
# @param total [Integer] The total number of repositories to process (for logging).
# @return [void]
# @note Only a clone failure causes +abort+ (immediate script termination). All other
#   failures — remote configuration, fetch, and post-clone command failures — are logged
#   as warnings and execution continues.
def _resurrect_each(repo, idx, total)
  folder = repo[FOLDER_KEY_NAME] # Assumed to be an absolute, resolved path
  FileUtils.mkdir_p(folder)

  existing_remotes = {} # Store existing remotes {name => url}
  # NOTE: clone_repo_into is a shell function defined in .shellrc, which is sourced
  # automatically via .zshenv on every zsh invocation — so a login shell (`-l`) is
  # sufficient; no explicit `source .shellrc` is needed.
  # The remote URL and folder come from a trusted YAML config authored by the user,
  # but we still use `/bin/zsh -lc` explicitly (rather than a bare string passed to
  # capture3) to make the shell invocation unambiguous and to avoid surprises from $SHELL.
  clone_command = "clone_repo_into #{repo[REMOTE_KEY_NAME].shellescape} #{folder.shellescape}"
  stdout_str, stderr_str, status = Open3.capture3({ 'FORCE_COLOR' => '1' }, '/bin/zsh', '-lc', clone_command)
  print stdout_str
  unless status.success?
    error_message = "Failed to clone '#{repo[REMOTE_KEY_NAME]}' into '#{folder.cyan}'; aborting (status: #{status.exitstatus})".red
    error_message += "\nClone command STDERR:\n#{stderr_str}".red unless nil_or_empty?(stderr_str.strip)
    abort(error_message)
  end

  # After cloning, verify the origin URL
  cloned_origin_url = _find_git_remote_url(folder, ORIGIN_NAME)
  if cloned_origin_url
    existing_remotes[ORIGIN_NAME] = cloned_origin_url
    if cloned_origin_url != repo[REMOTE_KEY_NAME]
      warn("Cloned origin URL '#{cloned_origin_url}' differs from config '#{repo[REMOTE_KEY_NAME]}' for '#{folder.cyan}'.")
    end
  else
    warn("Could not verify origin remote URL after cloning '#{folder.cyan}'.")
    existing_remotes[ORIGIN_NAME] = repo[REMOTE_KEY_NAME] # Assume it matches if verification fails
  end

  # Add missing 'other_remotes'
  _find_git_remotes(folder) do |name, url|
    existing_remotes[name] = url
  end
  debug("Existing remotes: #{existing_remotes.keys.join(', ')}") unless nil_or_empty?(existing_remotes)
  git_base_cmd = _build_git_context(folder)
  if repo[OTHER_REMOTES_KEY_NAME].is_a?(Hash)
    repo[OTHER_REMOTES_KEY_NAME].each do |name, remote|
      if existing_remotes.key?(name)
        if existing_remotes[name] != remote
          # Remote exists but URL is different
          info("Updating remote '#{name}' URL from '#{existing_remotes[name]}' to '#{remote}'")
          _stdout, stderr, status = Open3.capture3(*git_base_cmd, REMOTE_KEY_NAME, 'set-url', name, remote)
          unless status.success?
            warn("Failed to update URL for remote '#{name}' in repo '#{folder.cyan}' (status: #{status.exitstatus})")
            warn("STDERR: #{stderr.strip}".red) unless nil_or_empty?(stderr.strip)
          end
        end
      else
        info("Adding remote '#{name}' -> '#{remote}'")
        _stdout, stderr, status = Open3.capture3(*git_base_cmd, REMOTE_KEY_NAME, 'add', name, remote)
        unless status.success?
          warn("Failed to add remote '#{name}' for repo '#{folder.cyan}' (status: #{status.exitstatus})")
          warn("STDERR: #{stderr.strip}".red) unless nil_or_empty?(stderr.strip)
        end
      end
    end
  end

  info('Fetching all remotes and tags...')
  _stdout, stderr, status = Open3.capture3(*git_base_cmd, 'fetch', '-q', '--all', '--tags')
  unless status.success?
    warn("Failed to fetch all remotes and tags for repo '#{folder.cyan}'")
    warn("Fetch STDERR:\n#{stderr}") unless nil_or_empty?(stderr.strip)
  end

  return unless repo[POST_CLONE_KEY_NAME].is_a?(Array)

  debug('Running post-clone commands...')
  # Use begin/ensure so the process working directory is always restored even if a command
  # raises an unexpected exception mid-loop.
  original_dir = Dir.pwd
  begin
    Dir.chdir(folder)
    repo[POST_CLONE_KEY_NAME].each do |command_str|
      debug("Executing: #{command_str.dump}")
      _stdout, stderr, status = Open3.capture3(command_str)
      unless status.success?
        warn("Post-clone command #{command_str.dump} failed for repo '#{folder.cyan}' (exit status: #{status.exitstatus})")
        warn("STDERR: #{stderr.strip}".red) unless nil_or_empty?(stderr.strip)
      end
    end
  ensure
    Dir.chdir(original_dir)
  end
end

# Verifies that the repositories defined in the configuration file match
# the Git repositories found on disk within a specified scope.
# It reports any discrepancies.
#
# @param repositories [Array<Hash>] An array of repository configurations from the YAML file.
# @param discovered_count [Integer] Total count of repos before any filter was applied, used for the summary log.
# @param filter [String] A filter string (regex) to apply to repository paths before comparison.
# @param ref_folder [String, nil] Optional base directory to scope the comparison to.
# @return [void] Exits with 1 if discrepancies are found.
def _verify_all(repositories, discovered_count, filter, ref_folder: nil)
  ref_folder_path = ref_folder ? File.expand_path(ref_folder) : nil

  # Get folder paths from the YAML configuration (already filtered by FILTER if it was set)
  yml_folders = repositories.filter_map { |repo| repo[FOLDER_KEY_NAME] }.uniq.sort
  if ref_folder_path
    # If ref_folder is set, filter yml_folders to include only those starting with this path
    # or exactly matching this path (if ref_folder itself is a repo path).
    # Ensure comparison is against a directory prefix by normalizing paths.
    path_prefix_for_selection = ref_folder_path.chomp(File::SEPARATOR)
    yml_folders = yml_folders.select do |folder|
      normalized_folder = folder.chomp(File::SEPARATOR)
      normalized_folder == path_prefix_for_selection || normalized_folder.start_with?(path_prefix_for_selection + File::SEPARATOR)
    end
  end

  # _find_git_repos_from_disk already returns a sorted unique array; _apply_filter preserves uniqueness.
  local_folders = _apply_filter(_find_git_repos_from_disk(ref_folder_path || HOME_PATH.to_s), filter).sort

  # Convert to Sets for O(1) membership checks on the symmetric difference
  yml_set = Set.new(yml_folders)
  local_set = Set.new(local_folders)
  diff_repos = (local_set ^ yml_set).to_a.sort # ^ = symmetric difference
  common_repos = (local_set & yml_set).to_a.sort # & = intersection

  puts('')
  info('Summary'.yellow)
  puts("  Discovered repositories: #{discovered_count}")
  puts("  After filter:            #{repositories.length}") unless nil_or_empty?(filter)
  puts("  Verified entries:        #{common_repos.length.green}")
  puts("  Common repositories:\n  #{common_repos.map(&:cyan).join("\n  ")}")
  if diff_repos.any?
    warn("Please correlate the following #{diff_repos.length.red} differences in projects manually:\n  #{diff_repos.map(&:cyan).join("\n  ")}")
    exit(1)
  else
    success('Everything is kosher!')
  end
end

# main program
filter = (ENV['FILTER'] || '').strip

script_start_time = Time.now.to_i
print_script_start

if options[:generate]
  section_header('Generating repository configuration')
  discovery_dir = File.expand_path(options[:generate])
  puts("#{'Discovering repos under discovery directory:'.yellow} '#{discovery_dir.cyan}'")
  puts("#{'Using filter:'.yellow} '#{filter.cyan}'") unless nil_or_empty?(filter)
  repositories = _find_git_repos_from_disk(discovery_dir)
  discovered_count = repositories.length
  repositories = _apply_filter(repositories, filter)
  filtered_count = repositories.length
  generated = repositories.map { |dir| _generate_each(dir) }
  puts generated.to_yaml

  puts('')
  info('Summary'.yellow)
  puts("  Discovered repositories: #{discovered_count}")
  puts("  After filter:            #{filtered_count}") unless nil_or_empty?(filter)
  puts("  Generated entries:       #{generated.length.green}")
elsif options[:resurrect]
  section_header('Resurrecting repositories')
  config_file = File.expand_path(options[:resurrect])
  puts("#{'Config file:'.yellow} '#{config_file.cyan}'")
  puts("#{'Using filter:'.yellow} '#{filter.cyan}'") unless nil_or_empty?(filter)
  repositories = _read_git_repos_from_file(config_file)
  repositories = _apply_filter(repositories, filter)
  successful_repos = []
  failed_repos = []
  repositories.each.with_index(1) do |repo, idx|
    folder = repo[FOLDER_KEY_NAME]
    info("[#{_justify(idx)} of #{_justify(repositories.length)}] #{'Resurrecting'.yellow}: '#{folder.cyan}'")
    begin
      _resurrect_each(repo, idx, repositories.length)
      successful_repos << folder
    rescue StandardError => e
      warn("Resurrection failed for '#{folder.cyan}': #{e.message}")
      failed_repos << folder
    end
  end

  puts('')
  info('Summary'.yellow)
  puts("  Total repositories: #{repositories.length}")
  puts("  Successful:         #{successful_repos.length.to_s.green}")
  if failed_repos.any?
    puts("Failed:             #{failed_repos.length.red}")
    puts('Failed repositories:'.red)
    failed_repos.each { |failed_folder| puts("  - '#{failed_folder.red}'") }
    print_script_duration(script_start_time)
    exit(1)
  end
elsif options[:check]
  section_header('Verifying repositories')
  config_file = File.expand_path(options[:check])
  puts("#{'Config file:'.yellow} '#{config_file.cyan}'")
  puts("#{'Using filter:'.yellow} '#{filter.cyan}'") unless nil_or_empty?(filter)
  reference_folder = ENV['REF_FOLDER']&.then { |f| File.expand_path(f) }
  puts("#{'Reference folder:'.yellow} '#{reference_folder.cyan}'") unless nil_or_empty?(reference_folder)
  repositories = _read_git_repos_from_file(config_file)
  discovered_count = repositories.length
  repositories = _apply_filter(repositories, filter)
  _verify_all(repositories, discovered_count, filter, ref_folder: reference_folder)
end

print_script_duration(script_start_time)
