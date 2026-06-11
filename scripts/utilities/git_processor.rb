# frozen_string_literal: true

require 'open3'
require 'ostruct'
require 'pathname'

require_relative 'logging'

# Instance-based git operations for a specific repository directory.
# Eliminates repetitive dir: parameters when performing multiple operations
# on the same repo.
#
# Usage:
#   git = GitProcessor.new(dir: '/path/to/repo')
#   url = git.remote_url
#   branch = git.current_branch
#
#   # Or with block for automatic scoping
#   GitProcessor.new(dir: dir) do |git|
#     user_name = git.config_value('user.name')
#     git.add_remote('upstream', url)
#     git.fetch_all
#   end
#
#   # Dry-run mode logs operations instead of executing
#   GitProcessor.new(dir: dir, dry_run: true) do |git|
#     git.init
#     git.add_remote('origin', url)
#     git.stage_all
#     git.commit('Initial commit')
#   end
class GitProcessor
  attr_reader :dir

  # @param dir [String, Pathname] Repository directory
  # @param dry_run [Boolean] When true, log operations instead of executing
  def initialize(dir:, dry_run: false)
    @dir = dir.is_a?(Pathname) ? dir : Pathname.new(dir)
    @dry_run = dry_run
    yield self if block_given?
  end

  # Returns the value of a git config key, or nil if absent.
  # Mirrors get_git_config_value in .shellrc.
  #
  # @param key [String] Git config key, e.g. 'remote.origin.url'.
  # @return [String, nil]
  def config_value(key)
    out, = _execute('config', '--get', key)
    out = out.strip
    out.empty? ? nil : out
  end

  # Sets a git config value.
  #
  # @param key [String] Git config key, e.g. 'user.name'.
  # @param value [String] The value to set.
  # @param local [Boolean] When true (default), sets --local scope.
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def config_set(key, value, local: true)
    args = ['config']
    args << '--local' if local
    args << key << value
    _execute(*args)
  end

  # Returns the URL for the specified remote, or nil.
  #
  # @param name [String] Remote name (defaults to 'origin').
  # @return [String, nil]
  def remote_url(name: 'origin')
    config_value("remote.#{name}.url")
  end

  # Extracts the repository name from a remote URL.
  # Strips trailing slash and returns the last path segment.
  # Works with both SSH and HTTPS URLs.
  #
  # Examples:
  #   keybase://private/user/dotfiles/ → dotfiles
  #   git@github.com:user/repo.git → repo.git
  #   https://github.com/user/repo → repo
  #
  # @param name [String] Remote name (defaults to 'origin').
  # @return [String, nil] Repository name, or nil if remote doesn't exist.
  def remote_repo_name(name: 'origin')
    url = remote_url(name: name)
    return nil if Logging.nil_or_empty?(url)
    url.sub(/\/\z/, '').split('/').last
  end

  # Returns the current branch name, or nil if HEAD is detached or the repo is empty.
  #
  # @return [String, nil]
  def current_branch
    out, = _execute('branch', '--show-current')
    out = out.strip
    out.empty? ? nil : out
  end

  # Enumerates all remotes, yielding each remote name and URL.
  # Uses `git config --get-regexp` to fetch all remotes in one call.
  #
  # @yield [remote_name, remote_url] Called for each remote found.
  # @yieldparam remote_name [String] The name of the remote (e.g., 'origin').
  # @yieldparam remote_url [String] The URL of the remote.
  # @return [void]
  def each_remote
    return unless block_given?

    stdout, _stderr, status = _execute('config', '--get-regexp', '^remote\\..*\\.url')
    return unless status.success?

    stdout.each_line do |line|
      next if line.strip.empty?
      key, url = line.strip.split(' ', 2) # key is like 'remote.origin.url'
      remote_name = key.split('.')[1]
      yield remote_name, url
    end
  end

  # Adds a new remote.
  #
  # @param name [String] The remote name (e.g., 'upstream').
  # @param url [String] The remote URL.
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def add_remote(name, url)
    _execute('remote', 'add', name, url)
  end

  # Updates the URL of an existing remote.
  #
  # @param name [String] The remote name (e.g., 'origin').
  # @param url [String] The new remote URL.
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def set_remote_url(name, url)
    _execute('remote', 'set-url', name, url)
  end

  # Fetches from all remotes and all tags.
  #
  # @param quiet [Boolean] Whether to suppress git output (defaults to true).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def fetch_all(quiet: true)
    args = ['fetch']
    args << '-q' if quiet
    args << '--all' << '--tags'
    _execute(*args)
  end

  # Initializes a new git repository in the directory.
  #
  # @param ref_format [String] The ref-format to use (defaults to 'reftable').
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def init(ref_format: 'reftable')
    _execute('init', "--ref-format=#{ref_format}", '.')
  end

  # Stages all changes (equivalent to `git add -A .`).
  #
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def stage_all
    _execute('add', '-A', '.')
  end

  # Creates a commit with the given message.
  #
  # @param message [String] Commit message.
  # @param quiet [Boolean] Whether to suppress git output (defaults to false).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def commit(message, quiet: false)
    args = ['commit']
    args << '-q' if quiet
    args << '-m' << message
    _execute(*args)
  end

  # Pushes to a remote.
  #
  # @param remote [String] Remote name (defaults to 'origin').
  # @param branch [String] Branch name to push.
  # @param force [Boolean] Whether to force push (defaults to false).
  # @param force_with_lease [Boolean] Whether to use --force-with-lease (defaults to false).
  # @param progress [Boolean] Whether to show progress (defaults to false).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def push(remote: 'origin', branch:, force: false, force_with_lease: false, progress: false)
    unless @dry_run
      url = remote_url(name: remote)
      Logging.debug "#{'Pushing'.yellow} from '#{@dir.to_s.cyan}' to '#{url.cyan}'"
    end
    args = ['push']
    args << '--progress' if progress
    if force_with_lease
      args << '--force-with-lease'
    elsif force
      args << '-f'
    end
    args << remote << branch
    _execute(*args) do
      # Clean up stale index.lock after push operations (common with force push)
      delete_index_lock unless @dry_run
      url = remote_url(name: remote) unless url
      Logging.success "Pushed from '#{@dir.to_s.cyan}' to '#{url.cyan}'"
    end
  end

  # Runs a git alias command (e.g., 'amq', 'rfc', 'cc').
  # Git aliases are user-defined commands in .gitconfig.
  #
  # @param alias_name [String] The alias name (e.g., 'amq').
  # @param args [Array<String>] Additional arguments to pass to the alias.
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def run_alias(alias_name, *args)
    _execute(alias_name, *args)
  end

  # Deletes .git/index.lock if it exists. This is a recovery operation for
  # stale lock files that can block git operations. Rescue nil because the
  # file may not exist (which is fine -- that's the desired end state).
  #
  # @return [void]
  def delete_index_lock
    if @dry_run
      Logging.info "Would delete: '#{@dir.join('.git', 'index.lock').to_s.cyan}' (if exists)"
    else
      @dir.join('.git', 'index.lock').delete rescue nil
    end
  end

  # Returns true if this path is a git repository.
  # Checks for .git directory or file (worktree/submodule).
  #
  # @return [Boolean]
  def repo?
    @dir.join('.git').exist?
  end

  # Class method for checking if any path is a git repo.
  # Mirrors is_git_repo in .shellrc.
  #
  # @param path [String, Pathname] Path to check.
  # @return [Boolean]
  def self.repo?(path)
    return false if Logging.nil_or_empty?(path)
    # .git can be a directory (normal clone) or a file (worktree / submodule).
    path = Pathname.new(path) unless path.is_a?(Pathname)
    path.join('.git').exist?
  end

  private

  # Builds the base git command array with the -C flag.
  #
  # @return [Array<String>] The git command prefix array.
  def _git_command
    ['git', '-C', @dir.to_s]
  end

  # Executes a git command, respecting dry-run mode.
  # Automatically prepends 'git -C <dir>' to the command.
  # If a block is given, yields after execution and before returning the result.
  #
  # @param args [Array<String>] Git subcommand and arguments (e.g., 'status', '--short').
  # @yield Optional block executed after command completes (useful for cleanup/logging).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  #   In dry-run mode, returns empty strings and a mock successful status.
  def _execute(*args)
    cmd = _git_command + args
    if @dry_run
      Logging.info "Would run: #{cmd.join(' ').cyan}"
      # Return mock success response compatible with Open3.capture3
      result = ['', '', OpenStruct.new(success?: true, exitstatus: 0)]
    else
      result = Open3.capture3(*cmd)
    end
    yield if block_given?
    result
  end
end
