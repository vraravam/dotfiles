#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/run-all.rb
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

      # Use Open3.capture3 to capture stderr for better error reporting, matching the
      # pattern in resurrect-repositories.rb. Dir.chdir with a block automatically
      # restores the original directory when the block exits, even if an exception is raised.
      Dir.chdir(dir) do
        _stdout, stderr, status = Open3.capture3(shell, '-c', cmd_string)

        unless status.success?
          # Command failures are warnings (non-fatal) -- record the failure with context
          # but continue processing remaining repos. Mirrors _report_git_failure pattern.
          message = "Command failed in '#{dir.cyan}' (status: #{status.exitstatus})"
          message += "\nSTDERR: #{stderr.strip}".red unless nil_or_empty?(stderr.strip)
          Logging.record_warning(message)
          has_failures = true
        end
      end

      # Always return true -- failures are recorded as warnings above, not as failed items.
      # This matches resurrect-repositories.rb pattern where _resurrect_each returns true
      # and handles its own warning logging via _report_git_failure.
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
  require_relative 'utilities/cli_parser'

  include Logging

  parser = CliParser.parse('<command...>') do |opts|
    opts.separator 'Finds git repositories and runs the command in each repo directory.'
    opts.separator 'Commands can be git operations (status, pull) or any shell command (ls, find, etc.).'
    opts.separator ''
    opts.separator 'Environment variables (all optional):'.purple
    opts.separator "  #{'FOLDER'.yellow}    Root directory to search (default: current dir)"
    opts.separator "  #{'FILTER'.yellow}    Regex to filter repos by path (default: empty = all)"
    opts.separator "  #{'MINDEPTH'.yellow}  Minimum search depth (default: 1)"
    opts.separator "  #{'MAXDEPTH'.yellow}  Maximum search depth (default: 4)"
    opts.separator ''
    opts.separator 'Examples:'.purple
    opts.separator "  #{File.basename(__FILE__).cyan} git status"
    opts.separator "  #{File.basename(__FILE__).cyan} ls -la"
    opts.separator "  #{'FOLDER=dev MINDEPTH=2'.yellow} #{File.basename(__FILE__).cyan} git status"
    opts.separator "  #{'FILTER=oss'.yellow} #{File.basename(__FILE__).cyan} git upreb"
  end

  parser.abort_with_usage('Missing required argument: <command...>') if nil_or_empty?(ARGV)

  Logging.run_script(File.basename(__FILE__, '.rb')) do
    success = RunAll.run(command: ARGV.dup)
    exit(success ? 0 : 1)
  end
end
