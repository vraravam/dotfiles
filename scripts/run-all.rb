#!/usr/bin/env ruby
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

  # Public API method.
  #
  # @param command [Array<String>] Command parts to execute (e.g., ['git', 'status'])
  # @param folder [String, nil] Root directory to search (uses ENV['FOLDER'] or pwd if nil)
  # @param filter [String, nil] Regex to filter repos (uses ENV['FILTER'] if nil)
  # @param mindepth [Integer, nil] Minimum search depth (uses ENV['MINDEPTH'] if nil)
  # @param maxdepth [Integer, nil] Maximum search depth (uses ENV['MAXDEPTH'] if nil)
  # @return [Boolean] true on success (no command failures), false if any commands failed
  def run(command:, folder: nil, filter: nil, mindepth: nil, maxdepth: nil)
    if nil_or_empty?(command)
      Logging.error 'Missing required argument: command'
    end

    dir = folder || EnvVars.folder || Dir.pwd
    filter ||= EnvVars.filter
    mindepth ||= EnvVars.mindepth
    maxdepth ||= EnvVars.maxdepth

    Logging.info "#{'Finding git repos starting in dir'.yellow} '#{dir.to_s.cyan}' " \
                 "for a min depth of #{mindepth} and max depth of #{maxdepth}"
    Logging.info "#{'Filtering with:'.yellow} '#{filter.cyan}'" if filter

    dir_array = GitWorkspace.find_git_repos(
      dirs: dir,
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
    ) do |dir, idx, total|
      # Invoke the user's shell to execute the command, mirroring the shell version's
      # `(cd dir && eval "$@")`. This gives access to shell functions, aliases, and
      # builtins defined in the user's shell config. The command string is passed to
      # the shell via -c, which is safe here because command comes from ARGV (user
      # is running this script interactively and controls the command).
      shell = EnvVars::SHELL
      cmd_string = command.join(' ')

      # Use CommandUtils.run_interactive to execute the command, allowing stdout/stderr
      # to flow through to the terminal (so users see git log output, etc.). Dir.chdir
      # with a block automatically restores the original directory when the block exits,
      # even if an exception is raised.
      Dir.chdir(dir) do
        CommandUtils.run_interactive(shell, '-c', cmd_string) do
          Logging.record_warning("Command failed in '#{dir.cyan}' (status: #{$?.exitstatus})")
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
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  include Logging

  # Handle --help manually (can't use CliParser because all args are the command)
  if ARGV.empty? || ARGV.first == '-h' || ARGV.first == '--help'
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

  Logging.run_script(File.basename(__FILE__, '.rb')) do
    success = RunAll.run(command: ARGV.dup)
    exit(success ? 0 : 1)
  end
end
