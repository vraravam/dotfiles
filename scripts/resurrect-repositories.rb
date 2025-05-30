#!/usr/bin/env ruby

# frozen_string_literal: true

# file location: <anywhere; but advisable in the PATH>

require "#{__dir__}/utilities/string.rb"

# Displays the usage instructions for the script and exits.
#
# @param exit_code [Integer] The exit code to use when terminating the script.
# @return [void]
def usage(exit_code = -1)
  puts 'This script resurrects or flags for backup all known repositories in the current machine'
  puts "#{'Usage:'.pink} #{__FILE__} [-g <folder-to-generate-config-for>] [-r <config-filename>] [-c <config-filename>]".yellow
  puts "  #{'-g'.green} generates the configuration contents onto the stdout for codebases (usually on current laptop)."
  puts "    #{"Please note that this option will not handle 'post_clone' commands in the generated yaml structure".red}"
  puts "  #{'-r'.green} resurrects 'known' codebases (usually on fresh laptop)"
  puts "  #{'-c'.green} verifies 'known' codebases"
  puts 'Environment variables:'.yellow
  puts "  #{'FILTER'.light_blue} can be used to apply the operation to a subset of codebases (will match on folder or repo name)"
  puts "  #{'REF_FOLDER'.light_blue} can be used to apply a filter when verifying against a specific yaml file that might not contain all the repos in your system"
  exit(exit_code)
end

usage(0) if ARGV[0] == '--help'
usage if ARGV.length != 2 || !['-g', '-r', '-c'].include?(ARGV[0])

require 'fileutils'
require 'set'
require 'yaml'
require 'open3'

# Constants
ORIGIN_NAME = 'origin' # Standard name for the primary remote
FOLDER_KEY_NAME = 'folder' # Key name in YAML for the repository folder
OTHER_REMOTES_KEY_NAME = 'other_remotes' # Key name for additional remotes
POST_CLONE_KEY_NAME = 'post_clone' # Key name for post-clone commands
GIT_EXECUTABLE = 'git' # Path to git executable
GIT_CONFIG_REGEXP_CMD = ['config', '--get-regexp', '^remote\\..*\\.url'].freeze # Git subcommand to find remote URLs in git config

# Checks if a value is nil or empty.
#
# @param val [Object] The value to check.
# @return [Boolean] True if the value is nil or empty, false otherwise.
def nil_or_empty?(val)
  val.nil? || val.empty?
end

# Converts a number to a string and right-justifies it with spaces to a width of 2.
#
# @param num [Numeric] The number to format.
# @return [String] The formatted string.
def justify(num)
  num.to_s.rjust(2, ' ')
end

# Expands environment variables in a string.
# Handles multiple ${VAR} patterns. If an environment variable is not set,
# the placeholder ${VAR} is kept.
#
# @param folder [String, Object] The string in which to expand environment variables.
#   If not a String, the object is returned unchanged.
# @return [String, Object] The string with environment variables expanded,
#   or the original object if it was not a String or did not contain `${...}` patterns.
def find_and_replace_env_var(folder)
  # Early exit if folder is not a string or doesn't contain the pattern
  return folder unless folder.is_a?(String) && folder.include?('${')

  folder.gsub(/\$\{(.*?)\}/) do |match|
    ENV[$1] || match # $1 is the content between ${ and }, match is the full ${VAR}
  end
end

# Builds the base command array for executing Git commands within a specific repository folder.
# This prefix is used to target Git operations to the correct directory.
#
# @param folder [String] The path to the Git repository.
# @return [Array<String>] An array of strings representing the Git command prefix
#   (e.g., `['git', '-C', '/path/to/repo']`).
def build_git_context(folder)
  [GIT_EXECUTABLE, '-C', folder]
end

# Checks if the given folder path is a Git repository (i.e., contains a .git directory).
#
# @param folder [String] The path to the folder to check.
# @return [Boolean] True if the folder is a Git repository, false otherwise.
def git_repo?(folder)
  # Ensure folder is a string and not nil before appending path components
  folder.is_a?(String) && Dir.exist?(File.join(folder, '.git'))
end

# Fetches remote configurations using 'git config --get-regexp' and yields each remote.
#
# @param folder [String] A string to identify the repository in warning messages.
# @yield [remote_name, remote_url] Called for each remote found.
# @yieldparam remote_name [String] The name of the remote.
# @yieldparam remote_url [String] The URL of the remote.
# @return [void] This method is intended to be used with a block; its return value without a block is not defined for callers.
def find_git_remotes(folder)
  git_base_cmd = build_git_context(folder)
  config_cmd = [*git_base_cmd, *GIT_CONFIG_REGEXP_CMD]
  stdout, stderr, status = Open3.capture3(*config_cmd)

  if status.success?
    unless stdout.strip.empty?
      stdout.lines.each do |line|
        key, url = line.strip.split(' ', 2) # key is like 'remote.origin.url'
        remote_name = key.split('.')[1]
        yield remote_name, url if block_given?
      end
    end
  else
    puts "WARNING: Could not retrieve remotes using 'git config --get-regexp' for #{folder} (status: #{status.exitstatus}).".yellow
    puts "STDERR: #{stderr.strip}".red unless stderr.strip.empty?
  end
end

# Finds the URL for a specific remote in a given Git repository.
#
# @param repo_path [String] The path to the Git repository.
# @param remote_name [String] The name of the remote (e.g., 'origin').
# @return [String, nil] The URL of the remote if found, otherwise nil.
def find_git_remote_url(repo_path, remote_name)
  find_git_remotes(repo_path) do |name, url|
    return url if name == remote_name
  end
  nil
end

# Finds all Git repositories on disk starting from a given path.
# It uses the `find` command to locate .git directories.
#
# @param path [String] The base path to search for Git repositories.
# @return [Array<String>] A sorted array of paths to the Git repositories found.
def find_git_repos_from_disk(path)
  # Using array form for command execution safety if path contains special characters
  cmd = ['find', path.to_s, '-name', '.git', '-type', 'd', '-not', '-regex', '.*/\\..*/\\.git', '-prune', '-exec', 'dirname', '{}', ';']
  stdout_str, stderr_str, status = Open3.capture3(*cmd)

  unless stderr_str.empty?
    meaningful_errors = stderr_str.lines.map(&:strip).reject do |line|
      line.empty? ||
        line.include?('Permission denied') ||
        line.include?('No such file or directory')
      # Add other common noisy messages if needed
    end
    puts "WARNING: Issues encountered while searching for git repositories:\n#{meaningful_errors.join("\n")}".yellow unless meaningful_errors.empty?
  end

  if status.success? || !stdout_str.strip.empty? # Process output if command was successful or if there's any output despite error
    stdout_str.lines.map(&:strip).sort
  else
    # This case means find command failed AND produced no output, a more critical failure.
    puts "Error: `find` command failed (status #{status.exitstatus}) and produced no output.".red
    puts "STDERR from find: #{stderr_str}".red unless stderr_str.strip.empty?
    []
  end
rescue Errno::ENOENT # Specific rescue for `find` not being found
  puts 'Error: `find` command not found. Please ensure it is installed and in your PATH.'.red
  []
rescue => e # Catch other potential errors during command execution
  puts "Error executing find command: #{e.message}".red
  []
end

# Reads repository configurations from a YAML file.
# It filters for active repositories and expands environment variables in folder paths.
#
# @param filename [String] The path to the YAML configuration file.
# @return [Array<Hash>] An array of repository configuration hashes.
def read_git_repos_from_file(filename)
  yml_file = File.expand_path(filename)
  puts "Using config file: #{yml_file.green}"
  repositories = YAML.load_file(yml_file).select { |repo| repo['active'] }
  repositories.each do |repo|
    if repo[FOLDER_KEY_NAME].is_a?(String)
      repo[FOLDER_KEY_NAME] = find_and_replace_env_var(repo[FOLDER_KEY_NAME].strip)
    else
      # Provide more context for the warning
      repo_identifier = repo['remote'] || repo.inspect # Use remote URL or full inspect if no remote
      puts "WARNING: Repository entry '#{repo_identifier}' has invalid or missing '#{FOLDER_KEY_NAME}'. Skipping environment variable expansion for its folder.".yellow
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
def apply_filter(repos, filter)
  return repos if nil_or_empty?(filter)

  repos.select do |repo_item|
    path_to_check = repo_item.is_a?(String) ? repo_item : repo_item[FOLDER_KEY_NAME]
    next false if nil_or_empty?(path_to_check) # Skip if path is nil or empty

    find_and_replace_env_var(path_to_check).strip =~ /#{filter}/i
  end
end

# Generates a hash containing information about a single Git repository.
# This includes its folder path, active status, primary remote URL, and other remotes.
#
# @param folder [String] The path to the Git repository directory.
# @return [Hash] A hash with repository details (folder, active, remote, other_remotes).
#                The 'post_clone' key is intentionally not added here as per the script's design for generation.
def generate_each(folder)
  hash = { folder: folder, active: true }
  other_remotes = {}
  find_git_remotes(folder) do |name, url|
    other_remotes[name] = url
  end

  unless other_remotes.empty?
    hash[:remote] = other_remotes.delete(ORIGIN_NAME)
    hash[OTHER_REMOTES_KEY_NAME] = other_remotes
  end

  # Fallback for origin if not found or if the above command failed
  hash[:remote] ||= find_git_remote_url(folder, ORIGIN_NAME)

  # Ensure :remote is set, even if it's an empty string (e.g. repo with no remotes)
  hash[:remote] ||= ''

  hash
end

# Resurrects a single repository based on its configuration.
# This involves cloning if it doesn't exist, ensuring remotes are correctly configured,
# fetching all data, and running post-clone commands.
#
# @param repo [Hash] The repository configuration hash. Expected keys include
#   `FOLDER_KEY_NAME`, `'remote'`, `OTHER_REMOTES_KEY_NAME` (optional),
#   and `POST_CLONE_KEY_NAME` (optional).
# @param idx [Integer] The index of the current repository in the processing list (for logging).
# @param total [Integer] The total number of repositories to process (for logging).
# @return [void]
# @note This method may call `abort` if critical operations like cloning fail,
#   which will terminate the script.
def resurrect_each(repo, idx, total)
  folder = repo[FOLDER_KEY_NAME] # Assumed to be an absolute, resolved path
  FileUtils.mkdir_p(folder)

  puts "***** Resurrecting [#{justify(idx + 1)} of #{justify(total)}]: #{folder} *****".green

  existing_remotes = {} # Store existing remotes {name => url}
  if git_repo?(folder)
    puts 'Already an existing git repo. Checking remotes...'.yellow
    find_git_remotes(folder) do |name, url|
      existing_remotes[name] = url
    end
    puts "Existing remotes: #{existing_remotes.keys.join(', ')}" unless existing_remotes.empty?
  else
    puts 'Cloning git repo...'.yellow
    # This command relies on `clone_repo_into` being available in a shell environment potentially sourced from .shellrc.
    clone_command = "source \"#{File.join(ENV['HOME'], '.shellrc')}\" && clone_repo_into \"#{repo['remote']}\" \"#{folder}\""
    _stdout_str, stderr_str, status = Open3.capture3(clone_command)

    unless status.success?
      error_message = "Failed to clone '#{repo['remote']}' into '#{folder}'; aborting (status: #{status.exitstatus})".red
      error_message += "\nClone command STDERR:\n#{stderr_str}".red unless stderr_str.strip.empty?
      abort(error_message)
    end

    # After cloning, verify the origin URL
    cloned_origin_url = find_git_remote_url(folder, ORIGIN_NAME)
    if cloned_origin_url
      existing_remotes[ORIGIN_NAME] = cloned_origin_url
      if cloned_origin_url != repo['remote']
        puts "WARNING: Cloned origin URL '#{cloned_origin_url}' differs from config '#{repo['remote']}' for #{folder}.".yellow
      end
    else
      puts "WARNING: Could not verify origin remote URL after cloning #{folder}.".yellow
      existing_remotes[ORIGIN_NAME] = repo['remote'] # Assume it matches if verification fails
    end
  end

  # Add missing 'other_remotes'
  git_base_cmd = build_git_context(folder)
  Array(repo[OTHER_REMOTES_KEY_NAME]).each do |name, remote|
    if !existing_remotes.key?(name) # Check against the fetched list
      puts "Adding remote '#{name}' -> '#{remote}'".blue
      _stdout_add, stderr_add, status_add = Open3.capture3(*git_base_cmd, 'remote', 'add', name, remote)
      unless status_add.success?
        warning_message = "WARNING: Failed to add remote '#{name}' for repo '#{folder}' (status: #{status_add.exitstatus})".yellow
        warning_message += "\nSTDERR: #{stderr_add}".yellow unless stderr_add.strip.empty?
        puts warning_message
      end
    elsif existing_remotes[name] != remote
      # Remote exists but URL is different
      puts "Updating remote '#{name}' URL from '#{existing_remotes[name]}' to '#{remote}'".blue
      _stdout_update, stderr_update, status_update = Open3.capture3(*git_base_cmd, 'remote', 'set-url', name, remote)
      unless status_update.success?
        warning_message = "WARNING: Failed to update URL for remote '#{name}' in repo '#{folder}' (status: #{status_update.exitstatus})".yellow
        warning_message += "\nSTDERR: #{stderr_update}".yellow unless stderr_update.strip.empty?
        puts warning_message
      end
    end
  end if repo[OTHER_REMOTES_KEY_NAME]

  puts 'Fetching all remotes and tags...'.blue
  _stdout, stderr, status = Open3.capture3(*git_base_cmd, 'fetch', '-q', '--all', '--tags')
  unless status.success?
    puts "WARNING: Failed to fetch all remotes and tags for repo '#{folder}'".yellow
    puts "Fetch STDERR:\n#{stderr}".yellow unless stderr.strip.empty?
  end

  if repo[POST_CLONE_KEY_NAME]
    puts 'Running post-clone commands...'.blue
    Dir.chdir(folder) do
      Array(repo[POST_CLONE_KEY_NAME]).each do |command_str|
        puts "  Executing: #{command_str.dump}".blue
        unless system(command_str)
          puts "WARNING: Post-clone command #{command_str.dump} failed for repo '#{folder}' (exit status: #{$?.exitstatus})".yellow
        end
      end
    end
  end
end

# Verifies that the repositories defined in the configuration file match
# the Git repositories found on disk within a specified scope.
# It reports any discrepancies.
#
# @param repositories [Array<Hash>] An array of repository configurations from the YAML file.
# @param filter [String] A filter string (regex) to apply to repository paths before comparison.
# @return [void] Exits with -1 if discrepancies are found.
def verify_all(repositories, filter)
  # ENV['REF_FOLDER'] is expected to be a base directory path for comparison.
  # Both YAML-defined repositories and locally found repositories will be scoped to this path.
  ref_folder_path = ENV['REF_FOLDER'] ? File.expand_path(ENV['REF_FOLDER']) : nil

  # Get folder paths from the YAML configuration (already filtered by ENV['FILTER'] if it was set)
  yml_folders = repositories.map { |repo| repo[FOLDER_KEY_NAME] }.compact.uniq.sort
  if ref_folder_path
    # If REF_FOLDER is set, filter yml_folders to include only those starting with this path
    # or exactly matching this path (if REF_FOLDER itself is a repo path).
    # Ensure comparison is against a directory prefix by normalizing paths.
    path_prefix_for_selection = ref_folder_path.chomp(File::SEPARATOR)
    yml_folders = yml_folders.select do |folder|
      normalized_folder = folder.chomp(File::SEPARATOR)
      normalized_folder == path_prefix_for_selection || normalized_folder.start_with?(path_prefix_for_selection + File::SEPARATOR)
    end
  end

  local_folders = find_git_repos_from_disk(ref_folder_path || ENV['HOME']).uniq
  local_folders = apply_filter(local_folders, filter).uniq.sort

  # Convert to Sets for potentially faster difference/union operations on large lists
  yml_set = Set.new(yml_folders)
  local_set = Set.new(local_folders)
  diff_repos = (local_set ^ yml_set).to_a.sort # Use ^ for symmetric difference

  if diff_repos.any?
    puts "Please correlate the following #{diff_repos.length} differences projects manually:\n#{diff_repos.join("\n")}".red
    exit(-1)
  else
    puts 'Everything is kosher!'.green
  end
end

# main program
filter = (ENV['FILTER'] || '').strip
puts "Using filter: #{filter.green}" unless filter.empty?

case ARGV[0]
when '-g'
  puts "Running operation: #{'generation'.green}"
  discovery_dir = File.expand_path(ARGV[1])
  puts "Discovering repos under: #{discovery_dir.green}"
  repositories = find_git_repos_from_disk(discovery_dir)
  repositories = apply_filter(repositories, filter)
  puts repositories.map { |dir| generate_each(dir) }.to_yaml
when '-r'
  puts "Running operation: #{'resurrection'.green}"
  repositories = read_git_repos_from_file(ARGV[1])
  repositories = apply_filter(repositories, filter)
  repositories.each_with_index do |repo, idx|
    resurrect_each(repo, idx, repositories.length)
  end
when '-c'
  puts "Running operation: #{'verification'.green}"
  repositories = read_git_repos_from_file(ARGV[1])
  repositories = apply_filter(repositories, filter)
  verify_all(repositories, filter)
else
  usage
end
