#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'
require 'ostruct'
require 'pathname'
require 'shellwords'

require_relative 'core'
require_relative 'env_vars'
require_relative 'logging'
require_relative 'path_utils'

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
  include Core  # For instance methods
  extend Core   # For class methods

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
    nil_or_empty?(out) ? nil : out
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
    return nil if nil_or_empty?(url)
    url.sub(/\/\z/, '').split('/').last
  end

  # Returns the current branch name, or nil if HEAD is detached or the repo is empty.
  #
  # @return [String, nil]
  def current_branch
    out, = _execute('branch', '--show-current')
    out = out.strip
    nil_or_empty?(out) ? nil : out
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
      next if nil_or_empty?(line.strip)
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

  # Stages a specific file or directory (equivalent to `git add <path>`).
  #
  # @param path [String, Pathname] Path to stage (relative to repo root).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def add(path)
    _execute('add', path.to_s)
  end

  # Returns the last commit timestamp for a file or directory.
  # Returns nil if the file has no commits or doesn't exist in git history.
  #
  # @param path [String, Pathname] Path to check (relative to repo root).
  # @return [Integer, nil] Unix timestamp of last commit, or nil if no commits.
  def log_timestamp(path)
    out, _err, status = _execute('log', '--format=%ct', '-n1', '--', path.to_s)
    return nil unless status.success?
    out = out.strip
    nil_or_empty?(out) ? nil : out.to_i
  end

  # Returns true if a tag exists in the repository.
  #
  # @param name [String] Tag name to check.
  # @return [Boolean] true if tag exists, false otherwise.
  def tag_exists?(name)
    _out, _err, status = _execute('rev-parse', '-q', '--verify', "refs/tags/#{name}")
    status.success?
  end

  # Deletes a tag from the repository (local only, does not affect remote).
  #
  # @param name [String] Tag name to delete.
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def delete_tag(name)
    _execute('tag', '-d', name)
  end

  # Pulls changes from upstream with optional rebase.
  #
  # @param rebase [Boolean] Whether to rebase instead of merge (defaults to false).
  # @param quiet [Boolean] Whether to suppress git output (defaults to false).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def pull(rebase: false, quiet: false)
    args = ['pull']
    args << '-r' if rebase
    args << '-q' if quiet
    _execute(*args)
  end

  # Removes a file from the index (staging area) without deleting it from the working directory.
  # Equivalent to `git rm --cached <path>`.
  #
  # @param path [String, Pathname] Path to remove from index.
  # @param quiet [Boolean] Whether to suppress git output (defaults to false).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def rm_cached(path, quiet: false)
    args = ['rm', '--cached']
    args << '-q' if quiet
    args << '--' << path.to_s
    _execute(*args)
  end

  # Restores working tree files.
  # Equivalent to `git restore <pathspec>`.
  #
  # @param pathspec [String] Path or pathspec to restore (e.g., '.' for all files).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def restore(pathspec)
    _execute('restore', pathspec)
  end

  # Reports the working tree status.
  # Equivalent to `git status <switches>`.
  #
  # @param switches [Array<String>] Additional arguments to pass to git status.
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def status(*switches)
    _execute('status', *switches)
  end

  # Lists tracked files matching the given pathspec patterns.
  # Uses 'git ls-files' to query the git index.
  #
  # @param patterns [Array<String>] Pathspec patterns to match (e.g., '*.rb', 'src/**/*.js').
  #   If no patterns given, returns all tracked files.
  # @return [Array<String>] Array of tracked file paths (relative to repo root).
  def ls_files(*patterns)
    args = ['ls-files']
    args += ['--'] + patterns unless nil_or_empty?(patterns)
    stdout, = _execute(*args)
    stdout.split("\n")
  end

  # Normalizes a path to be relative to the repository root.
  # Uses the 'git relative-path' alias. Raises error if path is outside repo or cannot be resolved.
  #
  # @param path [String, Pathname, nil] Path to normalize (defaults to @dir via GIT_PREFIX when nil).
  # @return [String] Path relative to repository root (with './' prefix for non-root), or '.' for repo root.
  # @raise [RuntimeError] If path is outside repo or cannot be resolved.
  def relative_path(path = nil)
    if path.nil?
      # No argument: let git alias use GIT_PREFIX to determine current directory relative to repo root
      stdout, stderr, status = _execute('relative-path')
    else
      # Explicit path: pass it to the alias for normalization
      stdout, stderr, status = _execute('relative-path', path.to_s)
    end

    unless status.success?
      error_msg = stderr.strip
      error_msg = 'Failed to compute relative path' if nil_or_empty?(error_msg)
      raise error_msg
    end

    stdout.strip
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

  # Smart commit: amends if ahead of remote and not diverged, otherwise creates new commit.
  # Equivalent to `git sci "<message>"` alias.
  # Aborts if nothing is staged.
  #
  # @param message [String] The commit message.
  # @return [Boolean] true if commit succeeded, false if nothing staged or commit failed.
  def smart_commit(message)
    _out, _err, status = run_alias('sci', message)
    status.success?
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
      Logging.debug "#{'Pushing'.yellow} from '#{@dir.to_s.cyan}' to #{url.cyan}"
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
      Logging.success "Pushed from '#{@dir.to_s.cyan}' to #{url.cyan}"
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
    return false if nil_or_empty?(path)
    # .git can be a directory (normal clone) or a file (worktree / submodule).
    path = Pathname.new(path) unless path.is_a?(Pathname)
    path.join('.git').exist?
  end

  # Clones a git repo into a target directory, handling the non-empty target case.
  # On FIRST_INSTALL (vanilla OS), uses --depth=1 for a shallow clone to save time
  # and bandwidth; repos can be unshallowed later via fetch-unshallow/pull-unshallow.
  #
  # **DELEGATES TO SHELL VERSION**: This Ruby method is a thin wrapper around the
  # shell function clone_repo_into() in .shellrc. The shell version is required
  # for bootstrap (runs before dotfiles repo is cloned), so it cannot be removed.
  # This delegation eliminates duplicate implementations and ensures both paths
  # use identical logic.
  #
  # **FUTURE PORT NOTE**: When porting fresh-install to Ruby in the future, this
  # method should be reimplemented fresh in Ruby (not copied from this stale branch).
  # The current dual implementation exists only because fresh-install.sh still needs
  # the shell version for bootstrap. A future pure-Ruby fresh-install can implement
  # this natively without the shell dependency.
  #
  # @param url [String] Git repository URL to clone.
  # @param dest [String, Pathname] Target directory for the clone.
  # @param branch [String, nil] Optional branch to clone (defaults to remote's HEAD).
  # @return [Boolean] true on success, false on failure.
  def self.clone_repo_into(url, dest, branch: nil)
    dest = Pathname.new(dest) unless dest.is_a?(Pathname)

    # Build the shell command
    # clone_repo_into accepts: url (arg 1), dest (arg 2), branch (optional arg 3)
    cmd = "source #{EnvVars::HOME.join('.shellrc').to_s} && clone_repo_into"
    cmd += " #{Shellwords.escape(url)}"
    cmd += " #{Shellwords.escape(dest.to_s)}"
    cmd += " #{Shellwords.escape(branch)}" if branch && !nil_or_empty?(branch)

    # Execute via zsh with shell function
    # The shell function handles all the logic: temp folders, traps, error handling,
    # HEAD fix, reftable migration, submodule updates, etc.
    system('zsh', '-c', cmd)
  end

  # Migrates the repository to reftable format if it's still using the legacy
  # files format. Requires git 2.45+ (git refs migrate command).
  # On older git (system git on vanilla macOS), silently skips migration.
  #
  # @param folder [String, Pathname, nil] Repository directory (required)
  # @return [Boolean] false if folder is nil or empty, true/void otherwise
  def self.migrate_to_reftable(folder: nil)
    return false if nil_or_empty?(folder)

    folder = Pathname.new(folder) unless folder.is_a?(Pathname)

    return unless repo?(folder)

    # git rev-parse --show-ref-format was added in git 2.45; fall back to 'files'
    # on older git so the guard below correctly detects a non-reftable repo.
    ref_format, = Open3.capture3('git', '-C', folder.to_s, 'rev-parse', '--show-ref-format', err: File::NULL)
    ref_format = ref_format.strip
    ref_format = 'files' if nil_or_empty?(ref_format)
    return if ref_format == 'reftable'

    # 'git refs migrate' requires git 2.45+. On older git (vanilla macOS system
    # git) this returns non-zero; skip silently -- fresh-install calls this again
    # after Homebrew's modern git is on PATH.
    _out, _err, status = Open3.capture3('git', '-C', folder.to_s, 'refs', 'migrate', '--ref-format=reftable', err: File::NULL)
    unless status.success?
      Logging.debug "git refs migrate unavailable (requires git 2.45+) -- skipping reftable migration for '#{folder.to_s.cyan}'"
      return
    end

    # 'git refs migrate' writes all refs to the reftable directory and should
    # clear loose refs, but may leave behind empty files in the legacy
    # .git/refs/{heads,tags,remotes}/ trees. Remove them so they cannot shadow
    # the canonical reftable entries. Use Pathname#rmtree to recursively remove
    # directories with nested refs (e.g. refs/heads/feature/mybranch).
    git_dir = folder.join('.git')
    refs_heads = git_dir.join('refs', 'heads')
    refs_tags = git_dir.join('refs', 'tags')
    refs_remotes = git_dir.join('refs', 'remotes')

    [refs_heads, refs_tags, refs_remotes].each do |refs_subdir|
      next unless refs_subdir.directory?
      refs_subdir.children.each do |entry|
        if entry.directory?
          entry.rmtree
        elsif entry.file?
          entry.delete
        end
      end
    end

    Logging.success "Migrated '#{folder.to_s.cyan}' to reftable format"
  end

  # Corrects the HEAD file after a reftable clone-via-mv operation.
  # When cloning via temp folder + .git move, the HEAD file retains a '.invalid'
  # placeholder since the move bypasses git's normal post-clone finalization.
  # Shell prompts read .git/HEAD directly, so this fixes it by writing the real ref.
  #
  # @return [void]
  def fix_head_file
    real_ref = symbolic_ref
    return unless real_ref
    @dir.join('.git', 'HEAD').write("ref: #{real_ref}\n")
  end

  # Returns the count of commits in the given revision range.
  # Equivalent to `git rev-list <range> --count`.
  #
  # @param range [String] The revision range (e.g., 'HEAD..FETCH_HEAD').
  # @return [Integer] The commit count, or 0 on failure.
  def rev_list_count(range)
    out, _err, status = _execute('rev-list', range, '--count', err: File::NULL)
    status.success? ? out.strip.to_i : 0
  end

  private

  # Returns the symbolic reference for the given ref name.
  # Equivalent to `git symbolic-ref <name>`.
  # Used by fix_head_file to resolve HEAD reference.
  #
  # @param name [String] The symbolic ref to resolve (default: 'HEAD').
  # @return [String, nil] The resolved ref name, or nil if not a symbolic ref.
  def symbolic_ref(name = 'HEAD')
    out, _err, status = _execute('symbolic-ref', name, err: File::NULL)
    return nil unless status.success?
    out.strip
  end

  # Builds the base git command array with the -C flag (memoized).
  #
  # @return [Array<String>] The git command prefix array.
  def _git_command
    @_git_command ||= ['git', '-C', @dir.to_s]
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
