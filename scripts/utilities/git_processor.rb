#!/usr/bin/env ruby
# encoding: utf-8
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
# :reek:RepeatedConditional -- Defensive checks (@dry_run, repo?, quiet, status.success?) guard each operation independently
class GitProcessor
  include Core  # For instance methods
  extend Core   # For class methods

  attr_reader :dir

  # Class-level cache for repo? checks. Whether a directory is a git repo doesn't
  # change during script execution, so we memoize at the class level.
  @repo_cache = {}

  # Commands that benefit from streaming output (push/pull/fetch progress bars)
  STREAMING_COMMANDS = %w[push pull fetch].freeze

  # Flags that indicate quiet mode (suppress streaming output)
  QUIET_FLAGS = %w[-q --quiet].freeze

  # URL path separator. URLs always use '/' per RFC 3986, regardless of OS.
  # This is distinct from File::SEPARATOR which is OS-specific ('/' on Unix, '\' on Windows).
  URL_PATH_SEPARATOR = '/'

  class << self
    attr_accessor :repo_cache
  end

  # Class method for checking if any path is a git repo.
  # Mirrors is_git_repo in .shellrc.
  # Result is cached at the class level since repo status doesn't change during
  # script execution.
  #
  # @param path [String, Pathname] Path to check.
  # @return [Boolean]

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # Class method for checking if any path is a git repo.
  # Mirrors is_git_repo in .shellrc.
  #
  # Caches results in a class-level hash for performance (directory tree traversal
  # benefits from O(1) lookups). Cache persists for script lifetime. This is safe
  # because the class method is used for validation checks where each path is
  # typically checked once. If you create/remove repos during execution and need
  # fresh checks, use the instance method or clear repo_cache manually.
  #
  # @param path [String, Pathname] Path to check.
  # @return [Boolean]
  def self.repo?(path)
    return false if nil_or_empty?(path)

    # Normalize to absolute path for cache key (handles relative paths, symlinks)
    path = Pathname.new(path) unless path.is_a?(Pathname)

    # .git can be a directory (normal clone) or a file (worktree / submodule).
    repo_cache[path.expand_path.to_s] ||= path.join('.git').exist?
  end

  # Clones a git repo into a temp folder, moves the .git dir into the target location,
  # and does an initial checkout there. Works around git's refusal to clone into a
  # non-empty directory (e.g. HOME). If the target is already a git repo, runs fetch
  # to pull updates. New clones always use --depth=1 --filter=blob:none --single-branch
  # for fast initial clone. All repos (new and existing) are converted to full clones
  # asynchronously via background 'git unshallow' job after the main operation completes.
  # Always updates submodules afterwards.
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
    cmd = "source #{EnvVars::HOME.join('.shellrc')} && clone_repo_into"
    cmd += " #{Shellwords.escape(url)}"
    cmd += " #{Shellwords.escape(dest.to_s)}"
    cmd += " #{Shellwords.escape(branch)}" if branch && !nil_or_empty?(branch)

    # Execute via zsh with shell function
    # The shell function handles all the logic: temp folders, traps, error handling,
    # HEAD fix, reftable migration, submodule updates, etc.
    CommandUtils.run_interactive('zsh', '-c', cmd)
  end

  # Migrates the repository to reftable format if it's still using the legacy
  # files format. Requires git 2.45+ (git refs migrate command).
  # On older git (system git on vanilla macOS), silently skips migration.
  #
  # @param folder [String, Pathname, nil] Repository directory (required)
  # @return [Boolean] false if folder is nil or empty, true/void otherwise
  def self.migrate_to_reftable(folder: nil)
    return false if nil_or_empty?(folder)

    new(dir: folder).migrate_refs_to_reftable
  end

  # ---------------------------------------------------------------------------
  # Constructor
  # ---------------------------------------------------------------------------

  # @param dir [String, Pathname] Repository directory
  # @param dry_run [Boolean] When true, log operations instead of executing
  def initialize(dir:, dry_run: false)
    @dir = dir.is_a?(Pathname) ? dir : Pathname.new(dir)
    @dry_run = dry_run
    yield self if block_given?
  end

  # ---------------------------------------------------------------------------
  # Query methods (read-only state inspection)
  # ---------------------------------------------------------------------------

  # Returns true if this path is a git repository.
  # Checks for .git directory or file (worktree/submodule).
  # Not memoized because repo state can change during instance lifetime (init, recreate, etc.).
  #
  # @return [Boolean]
  def repo?
    @dir.join('.git').exist?
  end

  # Returns the value of a git config key, or nil if absent.
  # Mirrors get_git_config_value in .shellrc.
  #
  # @param key [String] Git config key, e.g. 'remote.origin.url'.
  # @return [String, nil]
  def config_value(key)
    @_config_values ||= {}
    @_config_values[key] ||= begin
      out, = _execute('config', '--get', key)
      nil_or_empty?(out) ? nil : out.strip
    end
  end

  # Returns the URL for the specified remote, or nil.
  #
  # @param name [String] Remote name (defaults to 'origin').
  # @return [String, nil]
  def remote_url(name: 'origin')
    @_remote_urls ||= {}
    @_remote_urls[name] ||= config_value("remote.#{name}.url")
  end

  # Extracts the repository name from a remote URL.
  # Strips trailing slash and returns the last path segment.
  # Works with any URL format (SSH, HTTPS, git+ssh, keybase, etc.) via simple string manipulation.
  #
  # Examples:
  #   keybase://private/user/dotfiles/ -> dotfiles
  #   git@github.com:user/repo.git -> repo.git
  #   https://github.com/user/repo -> repo
  #   ssh://git@host/user/my-repo.git -> my-repo.git
  #
  # @param name [String] Remote name (defaults to 'origin').
  # @return [String, nil] Repository name, or nil if remote doesn't exist.
  def remote_repo_name(name: 'origin')
    @_remote_repo_names ||= {}
    return @_remote_repo_names[name] if @_remote_repo_names.key?(name)

    url = remote_url(name: name)
    @_remote_repo_names[name] = nil_or_empty?(url) ? nil : url.sub(/#{Regexp.escape(URL_PATH_SEPARATOR)}\z/, '').split(URL_PATH_SEPARATOR).last
  end

  # Constructs an upstream remote URL by parsing the origin URL and substituting the owner.
  # Delegates to GitUrlParser for URL parsing and reconstruction.
  #
  # @param upstream_owner [String] The upstream repository owner username.
  # @return [Array<String, String>, Array<nil, nil>] [upstream_url, cloned_owner] or [nil, nil] on error.
  #   Errors are logged via Logging.record_error.
  def construct_upstream_url(upstream_owner:)
    origin_url = remote_url
    unless origin_url
      Logging.record_error("Could not retrieve URL for remote 'origin' in '#{@dir.cyan}'")
      return [nil, nil]
    end

    begin
      parser = GitUrlParser.new(origin_url)
      [parser.with_owner(upstream_owner), parser.owner]
    rescue ArgumentError => e
      Logging.record_error(e.message.sub('git URL', 'origin remote URL').sub(origin_url, origin_url.cyan))
      [nil, nil]
    end
  end

  # Returns the current branch name, or nil if HEAD is detached or the repo is empty.
  #
  # @return [String, nil]
  def current_branch
    @current_branch ||= begin
      out, = _execute('branch', '--show-current')
      nil_or_empty?(out) ? nil : out.strip
    end
  end

  # Returns true if the repository is a shallow clone (limited history depth).
  # Shallow clones are created with --depth flag and can be converted to full
  # clones via 'git unshallow' (which includes fetch operation).
  #
  # @return [Boolean] true if shallow clone, false if full clone
  def shallow?
    @shallow ||= begin
      out, = _execute('rev-parse', '--is-shallow-repository')
      nil_or_empty?(out) ? false : out.strip == 'true'
    end
  end

  # Returns the repository's reference storage format ('files' or 'reftable').
  # Legacy repos use 'files' format (.git/refs/* hierarchy), modern repos use
  # 'reftable' (single packed file). Git 2.45+ defaults to reftable for new
  # repos when init.defaultRefFormat=reftable is set.
  #
  # @return [String] 'files' or 'reftable'
  def ref_format
    @ref_format ||= begin
      out, = _execute('rev-parse', '--show-ref-format')
      format = nil_or_empty?(out) ? 'files' : out.strip
      nil_or_empty?(format) ? 'files' : format
    end
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
      next if nil_or_empty?(line)

      key, url = line.strip.split(' ', 2) # key is like 'remote.origin.url'
      remote_name = key.split('.')[1]
      yield remote_name, url
    end
  end

  # Returns true if a tag exists in the repository.
  #
  # @param name [String] Tag name to check.
  # @return [Boolean] true if tag exists, false otherwise.
  def tag_exists?(name)
    _stdout, _stderr, status = _execute('rev-parse', '-q', '--verify', "refs/tags/#{name}")
    status.success?
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
    stdout, _stderr, status = _execute(*args)
    status.success? ? stdout.split("\n").sort : []
  end

  # Lists files in a ref (branch/tag/commit/remote ref) using ls-tree.
  # Works for both local refs (HEAD, master) and remote refs (origin/main).
  # Does not require fetching - reads from locally cached refs.
  #
  # Returns sorted list for consistent comparison operations.
  # Git naturally outputs in sorted order, but we call .sort explicitly for guaranteed consistency.
  #
  # @param ref [String] Any git ref (e.g., 'HEAD', 'master', 'origin/main')
  # @return [Array<String>] Sorted list of file paths, or empty array on failure
  def ls_tree(ref)
    stdout, _stderr, status = _execute('ls-tree', '-r', '--name-only', ref)
    status.success? ? stdout.split("\n").sort : []
  end

  # Returns the total number of commits in the repository across all branches.
  # Uses 'git rev-list --all --count' which counts all reachable commits.
  #
  # Works correctly for:
  # - Brand new repos without any commits (returns 0)
  # - Repos without remotes (counts local commits only)
  # - Repos after git.recreate() (returns 0 for fresh .git directory)
  # - Existing repos with commit history (returns total count)
  #
  # @return [Integer] Total commit count (0 for brand new repos, >0 for repos with history).
  def commit_count
    stdout, = _execute('rev-list', '--all', '--count')
    nil_or_empty?(stdout) ? 0 : stdout.strip.to_i
  end

  # ---------------------------------------------------------------------------
  # Mutation methods (modify state)
  # ---------------------------------------------------------------------------

  # Sets a git config value.
  #
  # @param key [String] Git config key, e.g. 'user.name'.
  # @param value [String] The value to set.
  # @param local [Boolean] When true (default), sets --local scope.
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def config_set(key, value, local: true)
    return _mock_status_response(false) unless repo?

    args = ['config']
    args << '--local' if local
    args << key << value
    _execute(*args)
  end

  # Adds a new remote.
  #
  # @param name [String] The remote name (e.g., 'upstream').
  # @param url [String] The remote URL.
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def add_remote(name, url)
    return _mock_status_response(false) unless repo?

    _execute('remote', 'add', name, url)
  end

  # Updates the URL of an existing remote.
  #
  # @param name [String] The remote name (e.g., 'origin').
  # @param url [String] The new remote URL.
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def set_remote_url(name, url)
    return _mock_status_response(false) unless repo?

    _execute('remote', 'set-url', name, url)
  end

  # Fetches from all remotes and all tags.
  #
  # @param quiet [Boolean] Whether to suppress git output (defaults to true).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def fetch_all(quiet: true)
    return _mock_status_response(false) unless repo?

    args = ['fetch']
    args << '-q' if quiet
    args << '--all' << '-t' << '-p'
    _execute(*args)
  end

  # Initializes a new git repository in the directory.
  #
  # @param ref_format [String] The ref-format to use (defaults to 'reftable').
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def init(ref_format: 'reftable', initial_branch: nil)
    args = ['init', "--ref-format=#{ref_format}"]
    args << "--initial-branch=#{initial_branch}" unless nil_or_empty?(initial_branch)
    _execute(*args, '.')
  end

  # Verifies that all required git metadata is present before recreation.
  # Logs the values and raises an error if any are missing.
  #
  # @param force [Boolean] Whether this is a force recreation (for logging)
  # @return [Hash] Hash with keys: :git_url, :user_name, :user_email, :branch
  # @raise [RuntimeError] If any required metadata is missing
  def verify_pre_recreation(force:)
    git_url = remote_url
    user_name = config_value('user.name')
    user_email = config_value('user.email')
    branch = current_branch

    Logging.info "#{'Squash commits (will lose history!):'.yellow} #{force.to_s.orange}"
    Logging.info "#{'Dry run:'.yellow} #{@dry_run.to_s.orange}"
    Logging.info "#{'Repo url:'.yellow} '#{git_url.cyan}'"
    Logging.info "#{'User name:'.yellow} '#{user_name.cyan}'"
    Logging.info "#{'User email:'.yellow} '#{user_email.cyan}'"
    Logging.info "#{'Branch:'.yellow} '#{branch.cyan}'"

    Logging.error "One or more required git metadata values are missing for '#{@dir.cyan}' -- see above" if [git_url, user_name, user_email, branch].any? { |v| nil_or_empty?(v) }
  end

  # Recreates the local git repository with verification against remote.
  # Captures remote file list before recreation, recreates repo, stages/commits all files,
  # then verifies the new local matches the old remote before allowing remote deletion.
  #
  # This is the safe force-recreate workflow that prevents data loss.
  #
  # @return [Boolean] true if recreation and verification succeeded, false otherwise.
  def verify_and_recreate_local_repo
    # Capture current branch BEFORE destroying .git
    branch_name = current_branch
    return false if nil_or_empty?(branch_name)

    # Fetch from remote to ensure we have latest remote-tracking branches
    # (needed to capture remote file list before destroying .git)
    Logging.info 'Fetching from remote to capture file list...'
    _stdout, stderr, fetch_status = fetch_all(quiet: false)
    unless fetch_status.success?
      Logging.record_error 'Failed to fetch from remote before recreation'
      Logging.record_error "Stderr: #{stderr}" unless nil_or_empty?(stderr)
      return false
    end

    # Capture remote file list BEFORE destroying local .git
    # (recreate removes .git which loses remote tracking refs)
    remote_ref = "origin/#{branch_name}"
    remote_files = ls_tree(remote_ref)

    if nil_or_empty?(remote_files)
      Logging.record_error "Failed to get file list from remote branch '#{remote_ref.cyan}' or remote is empty"
      Logging.user_action "Ensure remote branch '#{remote_ref}' exists and has been pushed"
      return false
    end

    # Recreate repo (automatically restores config and branch name)
    return false unless _recreate

    # Stage and commit all files in local repo
    Logging.info 'Staging all files in working directory...'
    _stdout, _stderr, stage_status = stage_all
    unless stage_status.success?
      Logging.record_error 'Failed to stage files after recreation'
      return false
    end

    # Check what was actually staged (might be nothing due to gitignore)
    staged_files = ls_files
    if staged_files.empty?
      Logging.record_error 'No files staged after git add -A (check .gitignore rules in repo root)'
      Logging.user_action 'Review .gitignore and ensure files you want tracked are not excluded'
      return false
    end

    Logging.info "Staged #{staged_files.size.to_s.purple} files for commit"

    # Create initial commit with --no-verify to skip pre-commit hooks
    # (pre-commit runs RuboCop which may fail on personal scripts that don't follow dotfiles standards)
    prefix = commit_count.zero? ? 'Initial' : 'Incremental'
    message = "#{prefix} commit: #{Core.current_timestamp}"
    _stdout, stderr, commit_status = commit(message, no_verify: true)
    unless commit_status.success?
      Logging.record_error 'Failed to create commit after recreation'
      Logging.record_error "Stderr: #{stderr}" unless nil_or_empty?(stderr)
      return false
    end

    # Verify commit has files (commit succeeded but might be empty)
    if commit_count.zero?
      Logging.record_error 'No commits created after staging and committing'
      return false
    end

    # Verify file lists match
    _verify_file_lists_match(remote_files)
  end

  # Stages all changes (equivalent to `git add -A .`).
  # Automatically removes stale index.lock before staging to prevent failures.
  #
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def stage_all
    if @dry_run
      Logging.info 'Would stage all files after removing stale lock file if it exists'
    else
      return _mock_status_response(false) unless repo?

      delete_index_lock
      _execute('add', '-A', '.')
    end
  end

  # Stages a specific file or directory (equivalent to `git add <path>`).
  #
  # @param path [String, Pathname] Path to stage (relative to repo root).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def add(path)
    return _mock_status_response(false) unless repo?

    _execute('add', path.to_s)
  end

  # Deletes a tag from the repository (local only, does not affect remote).
  #
  # @param name [String] Tag name to delete.
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def delete_tag(name)
    return _mock_status_response(false) unless repo?

    _execute('tag', '-d', name)
  end

  # Pulls changes from upstream with optional rebase.
  #
  # @param rebase [Boolean] Whether to rebase instead of merge (defaults to false).
  # @param quiet [Boolean] Whether to suppress git output (defaults to false).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def pull(rebase: false, quiet: false)
    return _mock_status_response(false) unless repo?

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
    return _mock_status_response(false) unless repo?

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
    return _mock_status_response(false) unless repo?

    _execute('restore', pathspec)
  end

  # Creates a commit with the given message.
  #
  # @param message [String] Commit message.
  # @param quiet [Boolean] Whether to suppress git output (defaults to false).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def commit(message, quiet: false, no_verify: false)
    return _mock_status_response(false) unless repo?

    args = ['commit']
    args << '-q' if quiet
    args << '-n' if no_verify
    args << '-m' << message
    _execute(*args)
  end

  # Smart commit: amends if ahead of remote and not diverged, otherwise creates new commit.
  # Equivalent to `git sci "<message>"` alias.
  # Aborts if nothing is staged.
  #
  # When called without a message, auto-generates one based on repository state:
  # - "Initial commit: <timestamp>" if no commits exist (commit_count == 0)
  # - "Incremental commit: <timestamp>" otherwise (commit_count > 0)
  #
  # @param message [String, nil] Optional commit message. If nil, auto-generates based on repo state.
  # @return [Boolean] true if commit succeeded, false if nothing staged or commit failed.
  def smart_commit(message = nil)
    return false unless repo?

    # Auto-generate message if not provided
    if nil_or_empty?(message)
      prefix = commit_count.zero? ? 'Initial' : 'Incremental'
      message = "#{prefix} commit: #{Core.current_timestamp}"
    end

    stdout, stderr, status = run_alias('sci', message)
    unless status.success?
      Logging.record_error 'smart_commit failed (sci alias returned non-zero)'
      Logging.record_error "Stdout: #{stdout}" unless nil_or_empty?(stdout)
      Logging.record_error "Stderr: #{stderr}" unless nil_or_empty?(stderr)
    end
    status.success?
  end

  # Pushes to a remote and sets up upstream tracking.
  #
  # @param remote [String] Remote name (defaults to 'origin').
  # @param branch [String] Branch name to push.
  # @param force [Boolean] Whether to force push (defaults to false).
  # @param force_with_lease [Boolean] Whether to use --force-with-lease (defaults to false).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  def push(branch:, remote: 'origin', force: false, force_with_lease: false)
    if @dry_run
      Logging.info 'Would push to remote'
      Logging.info "Would set upstream tracking: #{remote}/#{branch}"
      return _mock_status_response(true)
    end

    return _mock_status_response(false) unless repo?

    url = remote_url(name: remote)
    Logging.debug "#{'Pushing'.yellow} from '#{@dir.cyan}' to #{url.cyan}"

    args = ['push']
    if force_with_lease
      args << '--force-with-lease'
    elsif force
      args << '-f'
    end
    args << remote << branch

    _execute(*args) do
      # Clean up stale index.lock after push operations (common with force push)
      delete_index_lock

      # Set upstream tracking after successful push
      _stdout, _stderr, status = _execute('branch', '-u', "#{remote}/#{branch}")
      if status.success?
        Logging.debug "Set upstream tracking: #{remote}/#{branch}"
      else
        Logging.warn "Failed to set upstream tracking for '#{branch}'"
      end

      Logging.success "Pushed from '#{@dir.cyan}' to #{url.cyan}"
    end
  end

  # Compresses the repository by expiring reflog and running gc.
  # Runs 'git rfc' (reflog expire) and 'git cc' (gc --aggressive) aliases.
  #
  # @return [Boolean] true on success, false on failure.
  def compress
    if @dry_run
      Logging.info 'Would compress (reflog + gc)'
      return true
    end

    return false unless repo?

    Logging.debug "#{'Compressing'.yellow} '#{@dir.cyan}'"
    run_alias('rfc')
    run_alias('cc')
    true
  end

  # Builds the commit graph for the repository to optimize git operations.
  # Commit graphs speed up operations like git log, git merge-base, and git status.
  # Use --reachable to include all commits reachable from any ref (branches, tags).
  #
  # @return [Boolean] true on success, false on failure
  def build_commit_graph
    if @dry_run
      Logging.info 'Would build commit graph'
      return true
    end

    return false unless repo?

    Logging.debug "#{'Building commit graph'.yellow} for '#{@dir.cyan}'"
    _stdout, _stderr, status = _execute('commit-graph', 'write', '--reachable', '--changed-paths')
    status.success?
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
      Logging.info "Would delete: '#{@dir.join('.git', 'index.lock').cyan}' (if it exists)"
    else
      begin
        @dir.join('.git', 'index.lock').delete
      rescue StandardError
        nil
      end
    end
  end

  # Migrates repository from legacy files format to reftable format.
  # Reftable is the modern reference storage format (git 2.45+) that replaces
  # the traditional .git/refs/* file hierarchy with a single packed file,
  # improving performance and atomic operations.
  #
  # No-op if already reftable or if git version doesn't support migration.
  # Requires git 2.45+ with 'git refs migrate' command.
  #
  # @return [Boolean] true if migration succeeded or already reftable, false if failed or unavailable
  def migrate_refs_to_reftable
    # Not a repo - skip migration
    return false unless repo?

    # Check if already reftable
    return true if ref_format == 'reftable'

    # Attempt migration
    _stdout, _stderr, status = _execute('refs', 'migrate', '--ref-format=reftable')
    unless status.success?
      Logging.debug "git refs migrate unavailable (requires git 2.45+, status: #{status.exitstatus}) -- skipping reftable migration for '#{@dir.cyan}'"
      return false
    end

    # Clean up legacy loose refs after successful migration
    _cleanup_legacy_refs

    Logging.success "Migrated '#{@dir.cyan}' to reftable format"
    true
  end

  # ---------------------------------------------------------------------------
  # Inner classes
  # ---------------------------------------------------------------------------

  # Parses and reconstructs git remote URLs with different owners.
  # Supports multiple formats:
  # - SCP-style SSH: git@host:owner/repo.git (most common)
  # - HTTPS: https://host/owner/repo.git
  # - git+ssh URL: git+ssh://git@host/owner/repo.git
  # - ssh:// URL: ssh://git@host/owner/repo.git
  class GitUrlParser
    attr_reader :host, :owner, :repo_path, :format, :protocol, :port

    # Parses a git remote URL.
    #
    # @param url [String] The git remote URL to parse
    # @raise [ArgumentError] If URL format is not recognized
    # :reek:DuplicateMethodCall -- Each case extracts different capture groups for different URL formats
    def initialize(url)
      case url
      when %r{\Agit@([^:]+):([^/]+)/(.+)\z}
        # SCP-style SSH URL format: git@host:owner/repo.git
        @format = :scp_ssh
        @host = Regexp.last_match(1)
        @owner = Regexp.last_match(2)
        @repo_path = _ensure_git_suffix(Regexp.last_match(3))
      when %r{\A(https?)://([^/]+)/([^/]+)/(.+)\z}
        # HTTPS URL format: https://host/owner/repo.git or http://host/owner/repo.git
        @format = :https
        @protocol = Regexp.last_match(1)
        @host = Regexp.last_match(2)
        @owner = Regexp.last_match(3)
        @repo_path = _ensure_git_suffix(Regexp.last_match(4))
      # Flay detects similarity between these two when clauses (git+ssh and ssh://).
      # This is intentional - both URL formats require the same field extraction pattern.
      # Extracting a helper would obscure the URL-format-to-field mapping.
      when %r{\Agit\+ssh://git@([^/:]+)(?::(\d+))?/([^/]+)/(.+)\z}
        # git+ssh URL format: git+ssh://git@host/owner/repo.git or git+ssh://git@host:port/owner/repo.git
        @format = :git_ssh
        @protocol = 'git+ssh'
        @host = Regexp.last_match(1)
        @port = Regexp.last_match(2)
        @owner = Regexp.last_match(3)
        @repo_path = _ensure_git_suffix(Regexp.last_match(4))
      when %r{\Assh://git@([^/:]+)(?::(\d+))?/([^/]+)/(.+)\z}
        # ssh:// URL format: ssh://git@host/owner/repo.git or ssh://git@host:port/owner/repo.git
        @format = :ssh_url
        @protocol = 'ssh'
        @host = Regexp.last_match(1)
        @port = Regexp.last_match(2)
        @owner = Regexp.last_match(3)
        @repo_path = _ensure_git_suffix(Regexp.last_match(4))
      else
        raise ArgumentError, "Cannot parse git URL format: '#{url}'"
      end
    end

    # Constructs a new URL with a different owner.
    #
    # @param new_owner [String] The new repository owner
    # @return [String] The reconstructed URL with .git suffix
    def with_owner(new_owner)
      sep = GitProcessor::URL_PATH_SEPARATOR
      case @format
      when :scp_ssh
        "git@#{@host}:#{new_owner}#{sep}#{@repo_path}"
      when :https
        "#{@protocol}:#{sep}#{sep}#{@host}#{sep}#{new_owner}#{sep}#{@repo_path}"
      when :git_ssh, :ssh_url
        port_part = @port ? ":#{@port}" : ''
        "#{@protocol}:#{sep}#{sep}git@#{@host}#{port_part}#{sep}#{new_owner}#{sep}#{@repo_path}"
      end
    end

    private

    # Ensures the repo path ends with .git suffix for consistency.
    # Matches the standard format used by GitHub, GitLab, Bitbucket, and Gitea.
    # Git accepts both forms, but .git is the official clone URL format.
    #
    # @param path [String] The repository path
    # @return [String] Path with .git suffix
    def _ensure_git_suffix(path)
      path.end_with?('.git') ? path : "#{path}.git"
    end
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  private

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
  # Decides whether to stream output or capture it based on the command:
  # - Streams (system): push, pull, fetch (unless -q/--quiet flag present)
  # - Captures: all other commands
  #
  # @param args [Array<String>] Git subcommand and arguments (e.g., 'status', '--short').
  # @yield Optional block executed after command completes (useful for cleanup/logging).
  # @return [Array<(String, String, Process::Status)>] stdout, stderr, and status object.
  #   In dry-run mode, returns empty strings and a mock successful status.
  def _execute(*args)
    cmd = _git_command + args

    if @dry_run
      Logging.info "Would run: #{cmd.join(' ').cyan}"
      yield if block_given?
      # Return mock success response with same format as captured output
      return _mock_status_response(true)
    end

    # Determine if we should stream output (for push/pull/fetch without quiet flag)
    if _should_stream_output?(args)
      # Stream output directly to terminal
      success = CommandUtils.run_interactive(*cmd)
      yield if block_given? && success
      # Return format compatible with captured output
      _mock_status_response(success)
    else
      # Capture output
      result = Open3.capture3(*cmd)
      yield if block_given?
      result
    end
  end

  # Determines if a git command should stream output or capture it.
  # Commands like push/pull/fetch benefit from real-time progress output,
  # but only when quiet mode is not requested.
  #
  # @param args [Array<String>] Git subcommand and arguments.
  # @return [Boolean] true if output should be streamed, false if captured.
  def _should_stream_output?(args)
    return false if nil_or_empty?(args)

    # Check if command is one that benefits from streaming
    return false if nil_or_empty?(args & STREAMING_COMMANDS)

    # Don't stream if quiet flag is present
    nil_or_empty?(args & QUIET_FLAGS)
  end

  # Creates a mock status response with the same format as captured command output.
  # Used for dry-run and streaming operations to maintain consistent return format.
  #
  # @param success [Boolean] Whether the operation succeeded.
  # @return [Array<(String, String, OpenStruct)>] Empty stdout/stderr and status object.
  def _mock_status_response(success)
    ['', '', OpenStruct.new(success?: success, exitstatus: success ? 0 : 1)]
  end

  # :reek:FeatureEnvy -- Standard filesystem traversal pattern (checks entry type before deletion)
  def _cleanup_legacy_refs
    git_dir = @dir.join('.git')
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
  end

  # Verifies that new local repo file list matches the pre-captured remote file list.
  # Logs detailed diagnostics if they don't match.
  #
  # @param remote_files [Array<String>] Pre-captured remote file list (before recreate)
  # @return [Boolean] true if lists match, false otherwise
  def _verify_file_lists_match(remote_files)
    Logging.info 'Verifying file lists match between new local and old remote...'

    if @dry_run
      Logging.info "Would compare #{'HEAD'.cyan} vs pre-captured remote file list"
      return true
    end

    # Get local files list from new repo (HEAD - just committed)
    local_files = ls_tree('HEAD')

    # Compare the lists
    if local_files == remote_files
      Logging.success "✅ File lists match (#{local_files.size.to_s.purple} files) - safe to delete remote"
      return true
    end

    # Lists don't match - compute differences and show detailed diagnostic output
    _log_file_list_mismatch(local_files, remote_files)
    Logging.record_error '❌ File lists DO NOT match between new local and old remote!'
    false
  end

  # Logs diagnostic output for file list mismatches.
  #
  # @param local_files [Array<String>] Files in new local repo
  # @param remote_files [Array<String>] Files in old remote
  # @return [void]
  def _log_file_list_mismatch(local_files, remote_files)
    local_only = local_files - remote_files
    remote_only = remote_files - local_files

    Logging.warn 'Aborting without deleting remote repo - local has been recreated but remote is preserved'

    _print_file_diff('Files only in new local', local_only, '+')
    _print_file_diff('Files only in old remote', remote_only, '-')
  end

  # Prints file diff diagnostics for verification failures.
  #
  # @param label [String] Description of the file set
  # @param files [Array<String>] List of files
  # @param prefix [String] Prefix character ('+' or '-')
  # @return [void]
  def _print_file_diff(label, files, prefix)
    return unless files.any?

    files_size = files.size
    Logging.warn "#{label} (#{files_size.to_s.red}):"
    files.first(10).each { |f| Logging.warn "  #{prefix} #{f.cyan}" }
    Logging.warn "  ... and #{files_size - 10} more" if files_size > 10
  end

  # Recreates the local git repository by removing .git and reinitializing.
  # Preserves working tree files, only destroys git history.
  # Automatically restores origin remote, user.name, and user.email from current repo state.
  #
  # WARNING: This method does NOT verify against remote. For force-squash operations
  # where you're destroying history, use verify_and_recreate_local_repo instead
  # to prevent data loss.
  #
  # This method is currently private. If made public in the future, it should only be used when:
  # - Converting ref format without changing history
  # - Operating on local-only repos (no remote)
  # - You have verified file lists match through other means
  #
  # @param ref_format [String] The ref-format to use (defaults to 'reftable').
  # @param remote_name [String] Remote name to restore (defaults to 'origin').
  # @return [Boolean] true on success, false on failure.
  def _recreate(ref_format: 'reftable', remote_name: 'origin')
    git_path = @dir.join('.git')

    # Capture current state before destroying .git
    branch_name = current_branch
    remote_url = remote_url(name: remote_name)
    user_name = config_value('user.name')
    user_email = config_value('user.email')

    if @dry_run
      Logging.info "Would remove: '#{git_path.cyan}'"
    else
      return false unless repo?

      # .git can be a directory (normal clone) or a file (worktree/submodule pointer).
      # rmtree handles both: removes directory tree or deletes the file.
      git_path.rmtree
    end

    _stdout, _stderr, status = init(ref_format: ref_format, initial_branch: branch_name)
    return false unless status.success?

    # Restore remote and config from captured state
    add_remote(remote_name, remote_url) unless nil_or_empty?(remote_url)
    config_set('user.name', user_name) unless nil_or_empty?(user_name)
    config_set('user.email', user_email) unless nil_or_empty?(user_email)

    true
  end

  private :_recreate, :_should_stream_output?, :_mock_status_response, :_cleanup_legacy_refs, :_verify_file_lists_match, :_log_file_list_mismatch, :_print_file_diff
end
