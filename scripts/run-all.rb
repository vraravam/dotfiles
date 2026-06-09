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
# Usage: [FOLDER=dir] [FILTER=regex] [MINDEPTH=n] [MAXDEPTH=n] run-all.rb <command...>
#
# Examples:
#   run-all.rb git status                    # git command across all repos
#   run-all.rb ls -la                        # non-git command in each repo
#   FOLDER=dev MINDEPTH=2 run-all.rb git status
#   FILTER=oss run-all.rb find . -name "*.rb"
#   FOLDER=/Users/me MAXDEPTH=5 run-all.rb git pull-safe

$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'cli_parser'
require 'collection_processor'
require 'env_vars'
require 'git_workspace'
require 'logging'

include Logging

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

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

if ARGV.empty?
  parser.abort_with_usage('Missing required argument: <command...>')
end

cmd_parts = ARGV.dup

folder = EnvVars.folder || Dir.pwd
filter = EnvVars.filter
mindepth = EnvVars.mindepth
maxdepth = EnvVars.maxdepth

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

increment_script_depth
start_time = print_script_start

section_header2 'Running commands in git repositories'

info "#{'Finding git repos starting in folder'.yellow} '#{folder.cyan}' " \
     "for a min depth of #{mindepth} and max depth of #{maxdepth}"
info "#{'Filtering with:'.yellow} '#{filter.cyan}'" if filter

dir_array = GitWorkspace.find_git_repos(
  folders: folder,
  mindepth: mindepth,
  maxdepth: maxdepth,
  filter: filter,
  skip_symlinks: true
)

info "Found #{dir_array.length.to_s.purple} repositories"
puts ''

results = CollectionProcessor.process_items(
  dir_array,
  operation_desc: "Running '#{cmd_parts.join(' ').purple}' #{'in'.yellow}"
) do |dir, idx, total|
  # Invoke the user's shell to execute the command, mirroring the shell version's
  # `(cd dir && eval "$@")`. This gives access to shell functions, aliases, and
  # builtins defined in the user's shell config. The command string is passed to
  # the shell via -c, which is safe here because cmd_parts comes from ARGV (user
  # is running this script interactively and controls the command).
  shell = EnvVars::SHELL
  cmd_string = cmd_parts.join(' ')
  Dir.chdir(dir) { system(shell, '-c', cmd_string) }
end

print_results_summary(results)
print_script_summary(start_time)

exit 1 unless results[:failed].empty?
