# frozen_string_literal: true

require 'open3'

# Git helper utilities for common git inspection operations.
module GitHelpers
  extend self

  # Returns the value of a git config key for the repo at +folder+, or nil if
  # the key is absent. Mirrors get_git_config_value in .shellrc.
  #
  # @param key    [String] Git config key, e.g. 'remote.origin.url'.
  # @param folder [String] Path to the repo (defaults to Dir.pwd).
  # @return [String, nil]
  def config_value(key, folder: Dir.pwd)
    out, = Open3.capture3(*_git_command(folder), 'config', '--get', key)
    out = out.strip
    out.empty? ? nil : out
  end

  # Returns the URL for the specified remote of the repo at +folder+, or nil.
  #
  # @param folder [String] Path to the repo (defaults to Dir.pwd).
  # @param name [String] Remote name (defaults to 'origin').
  # @return [String, nil]
  def remote_url(folder: Dir.pwd, name: 'origin')
    config_value("remote.#{name}.url", folder: folder)
  end

  # Returns the current branch name for the repo at +folder+, or nil if HEAD
  # is detached or the repo is empty.
  #
  # @param folder [String] Path to the repo (defaults to Dir.pwd).
  # @return [String, nil]
  def current_branch(folder: Dir.pwd)
    out, = Open3.capture3(*_git_command(folder), 'branch', '--show-current')
    out = out.strip
    out.empty? ? nil : out
  end

  # Enumerates all remotes in the repo at +folder+, yielding each remote name
  # and URL. Uses `git config --get-regexp` to fetch all remotes in one call.
  #
  # @param folder [String] Path to the repo (defaults to Dir.pwd).
  # @yield [remote_name, remote_url] Called for each remote found.
  # @yieldparam remote_name [String] The name of the remote (e.g., 'origin').
  # @yieldparam remote_url [String] The URL of the remote.
  # @return [void]
  def each_remote(folder: Dir.pwd)
    return unless block_given?

    stdout, _stderr, status = Open3.capture3(*_git_command(folder), 'config', '--get-regexp', '^remote\\..*\\.url')
    return unless status.success?

    stdout.each_line do |line|
      next if line.strip.empty?
      key, url = line.strip.split(' ', 2) # key is like 'remote.origin.url'
      remote_name = key.split('.')[1]
      yield remote_name, url
    end
  end

  # Adds a new remote to the repo at +folder+.
  #
  # @param name [String] The remote name (e.g., 'upstream').
  # @param url [String] The remote URL.
  # @param folder [String] Path to the repo (defaults to Dir.pwd).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def add_remote(name, url, folder: Dir.pwd)
    Open3.capture3(*_git_command(folder), 'remote', 'add', name, url)
  end

  # Updates the URL of an existing remote in the repo at +folder+.
  #
  # @param name [String] The remote name (e.g., 'origin').
  # @param url [String] The new remote URL.
  # @param folder [String] Path to the repo (defaults to Dir.pwd).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def set_remote_url(name, url, folder: Dir.pwd)
    Open3.capture3(*_git_command(folder), 'remote', 'set-url', name, url)
  end

  # Fetches from all remotes and all tags in the repo at +folder+.
  #
  # @param folder [String] Path to the repo (defaults to Dir.pwd).
  # @param quiet [Boolean] Whether to suppress git output (defaults to true).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def fetch_all(folder: Dir.pwd, quiet: true)
    args = _git_command(folder) + ['fetch']
    args << '-q' if quiet
    args << '--all' << '--tags'
    Open3.capture3(*args)
  end

  # Returns true if +path+ contains a .git directory or file (worktree/submodule).
  # Mirrors is_git_repo in .shellrc.
  #
  # @param path [String, Pathname] Path to check.
  # @return [Boolean]
  def git_repo?(path)
    return false if nil_or_empty?(path)
    # .git can be a directory (normal clone) or a file (worktree / submodule).
    path = Pathname.new(path) unless path.is_a?(Pathname)
    path.join('.git').exist?
  end

  private

  # Builds the base git command array with the -C flag for the given folder.
  #
  # @param folder [String] Path to the repo.
  # @return [Array<String>] The git command prefix array.
  def _git_command(folder)
    ['git', '-C', folder]
  end
end
