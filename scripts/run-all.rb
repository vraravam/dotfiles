#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/run-all.rb
#
# Finds all git repositories within FOLDER (env var, defaults to current dir)
# filtered by FILTER (regex, defaults to empty = all) and a depth range
# MINDEPTH..MAXDEPTH, then runs the specified command in each repo's directory.
#
# Commands run in the context of each git repo root (the directory containing .git).
# Not limited to git commands -- any shell command is accepted (ls, find, custom scripts, etc.).
#
# Usage:
#   Standalone: [FOLDER=dir] [FILTER=regex] [MINDEPTH=n] [MAXDEPTH=n] run-all.rb <command...>
#   Module:     RunAll.run(command: ['git', 'status'], folder: nil, filter: nil, mindepth: nil, maxdepth: nil)
#
# Examples:
#   run-all.rb git status                    # git command across all repos
#   run-all.rb ls -la                        # non-git command in each repo
#   FOLDER=dev MINDEPTH=2 run-all.rb git status
#   FILTER=oss run-all.rb find . -name "*.rb"
#   FOLDER=/Users/me MAXDEPTH=5 run-all.rb git pull-safe

require 'open3'

require_relative 'utilities/collection_processor'
require_relative 'utilities/command_utils'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_workspace'
require_relative 'utilities/logging'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module RunAll
  extend self

  # Env var set on override script subprocesses (mirrors '_GIT_OVERRIDE_SKIP', the
  # equivalent guard already used by the 'cc'/'upreb' git aliases). If an override
  # script -- or anything it calls -- ends up invoking run-all.rb again for the same
  # repo, the inner invocation sees this already set and skips its own
  # override-dispatch, falling back to running the literal command instead of
  # re-dispatching to the same override script. This bounds the recursion to one
  # level even if a future override script is accidentally written to call back
  # into 'all'/'run-all.rb'.
  OVERRIDE_SKIP_ENV_VAR = '_RUN_ALL_OVERRIDE_SKIP'

  # Public API method.
  #
  # @param command [Array<String>] Command parts to execute (e.g., ['git', 'status'])
  # @param folder [String, nil] Root directory to search (uses ENV['FOLDER'] or pwd if nil)
  # @param filter [String, nil] Regex to filter repos (uses ENV['FILTER'] if nil)
  # @param mindepth [Integer, nil] Minimum search depth (uses ENV['MINDEPTH'] if nil)
  # @param maxdepth [Integer, nil] Maximum search depth (uses ENV['MAXDEPTH'] if nil)
  # @return [Boolean] true on success (no command failures), false if any commands failed
  def run(command:, folder: nil, filter: nil, mindepth: nil, maxdepth: nil)
    Logging.error 'Missing required argument: command' if nil_or_empty?(command)

    start_dir = folder || EnvVars.folder || Dir.pwd
    filter ||= EnvVars.filter
    mindepth ||= EnvVars.mindepth
    maxdepth ||= EnvVars.maxdepth

    Logging.info "#{'Finding git repos starting in dir'.yellow} '#{start_dir.cyan}' " \
                 "for a min depth of #{mindepth} and max depth of #{maxdepth}"
    Logging.info "#{'Filtering with:'.yellow} '#{filter.cyan}'" if filter

    dir_array = GitWorkspace.find_git_repos(
      dirs: start_dir,
      mindepth: mindepth,
      maxdepth: maxdepth,
      filter: filter,
      skip_symlinks: true
    )

    Logging.info "Found #{dir_array.length.to_s.purple} repositories"
    puts ''

    # Track whether any commands failed during this run (for exit code).
    # Don't rely on step_warnings.any? which accumulates across multiple script invocations
    # if run-all.rb is called in a loop from another script.
    has_failures = false

    results = CollectionProcessor.process_items(
      dir_array,
      operation_desc: "Running '#{command.join(' ').cyan}' #{'in'.yellow}"
    ) do |dir, _idx, _total|
      # Resolves to a folder-specific override script (e.g. cc-browser-profiles.sh)
      # when one exists for this repo, otherwise falls back to the user's shell
      # running the command as-is. See _resolve_exec_command for details.
      exec_command = _resolve_exec_command(command: command, dir: dir)

      # Use CommandUtils.run_interactive to execute the command, allowing stdout/stderr
      # to flow through to the terminal (so users see git log output, etc.). Dir.chdir
      # with a block automatically restores the original directory when the block exits,
      # even if an exception is raised.
      Dir.chdir(dir) do
        CommandUtils.run_interactive(*exec_command) do
          Logging.record_warning("Command failed in '#{dir.cyan}' (status: #{$CHILD_STATUS&.exitstatus || 'unknown'})")
          has_failures = true
        end
      end

      # Always return true -- failures are recorded as warnings above, not as failed items.
      # This matches resurrect-repositories.rb pattern where _resurrect_each returns true
      # and handles its own warning logging inline.
      true
    end

    Logging.print_results_summary(results)

    !has_failures
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Resolves the actual command to exec for a given repo directory.
  #
  # If a folder-specific override script exists at
  # ${PERSONAL_BIN_DIR}/<name>-<basename>.sh (where <name> is the git subcommand
  # for 'git ...' commands, or the command's own name otherwise, and <basename>
  # is the repo directory's basename), this returns an exec array that runs the
  # override script directly instead of the original command.
  #
  # This is what makes folder-specific overrides (e.g. suspending cron for the
  # duration of a commit/push/pull) transparent for every command run-all.rb
  # executes across a loop of repos -- including git builtins like push/pull
  # that can never be intercepted via a git alias (git always resolves builtins
  # before consulting [alias]).
  #
  # @param command [Array<String>] The command as passed to run-all.rb (e.g. ['git', 'cc'])
  # @param dir [String] The repo directory this command is about to run in
  # @return [Array] exec-style array suitable for CommandUtils.run_interactive(*array)
  def _resolve_exec_command(command:, dir:)
    # Invoke the user's shell to execute the command, mirroring the shell version's
    # `(cd dir && eval "$@")`. This gives access to shell functions, aliases, and
    # builtins defined in the user's shell config. The command string is passed to
    # the shell via -c, which is safe here because command comes from ARGV (user
    # is running this script interactively and controls the command).
    shell = EnvVars::SHELL
    default_exec = [shell, '-c', command.join(' ')]

    # Already inside a dispatched override's subprocess tree -- do not re-dispatch.
    return default_exec unless nil_or_empty?(ENV.fetch(OVERRIDE_SKIP_ENV_VAR, nil))

    override = _override_script_for(command: command, dir: dir)
    return default_exec if override.nil?

    Logging.info "Delegating to override '#{override.to_s.cyan}' for '#{dir.to_s.cyan}'"

    is_git = command[0] == 'git'
    extra_args = is_git ? command[2..-1] : command[1..-1]

    env = { OVERRIDE_SKIP_ENV_VAR => '1' }
    # Also skip the git alias's own (redundant but harmless) override check, in
    # case the override script shells out to 'git cc'/'git upreb' without having
    # set this itself -- matches the existing '_cc'/'_upreb' convention.
    env['_GIT_OVERRIDE_SKIP'] = '1' if is_git

    [env, override.to_s, *Array(extra_args)]
  end

  private_class_method :_resolve_exec_command

  # Finds the folder-specific override script for a command, if one exists.
  #
  # @param command [Array<String>] The command as passed to run-all.rb
  # @param dir [String] The repo directory the command is about to run in
  # @return [Pathname, nil] Path to the override script, or nil if none exists/executable
  def _override_script_for(command:, dir:)
    return nil if nil_or_empty?(command)

    override_name = command[0] == 'git' && command.size > 1 ? command[1] : command[0]
    return nil if nil_or_empty?(override_name)

    candidate = EnvVars::PERSONAL_BIN_DIR.join("#{override_name}-#{File.basename(dir)}.sh")
    return nil unless candidate.file? && File.executable?(candidate)

    candidate
  end

  private_class_method :_override_script_for
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  include Logging

  # Handle --help manually (can't use CliParser because all args are the command)
  if nil_or_empty?(ARGV) || ARGV.first == '-h' || ARGV.first == '--help'
    puts "#{'Usage'.red}: #{File.basename(__FILE__).cyan} #{'<command...>'.yellow}"
    puts ''
    puts 'Finds git repositories and runs the command in each repo directory.'
    puts 'Commands can be git operations (status, pull) or any shell command (ls, find, etc.).'
    puts ''
    puts 'Environment variables (all optional):'.purple
    puts "  #{'FOLDER'.yellow}    Root directory to search (default: current dir)"
    puts "  #{'FILTER'.yellow}    Regex to filter repos by path (default: empty = all)"
    puts "  #{'MINDEPTH'.yellow}  Minimum search depth (default: 1)"
    puts "  #{'MAXDEPTH'.yellow}  Maximum search depth (default: 4)"
    puts ''
    puts 'Examples:'.purple
    puts "  #{File.basename(__FILE__).cyan} git status"
    puts "  #{File.basename(__FILE__).cyan} git log --oneline -5"
    puts "  #{File.basename(__FILE__).cyan} ls -la"
    puts "  #{'FOLDER=dev MINDEPTH=2'.yellow} #{File.basename(__FILE__).cyan} git status"
    puts "  #{'FILTER=oss'.yellow} #{File.basename(__FILE__).cyan} git upreb"
    exit 0
  end

  Logging.run_script do
    success = RunAll.run(command: ARGV.dup)
    exit(success ? 0 : 1)
  end
end
