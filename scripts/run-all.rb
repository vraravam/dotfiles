#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/run-all.rb
#
# Finds all git repositories within FOLDER (env var, defaults to current dir)
# filtered by FILTER (regex, defaults to empty = all) and a depth range
# MINDEPTH..MAXDEPTH, then runs the specified command in each repo's directory.
#
# Commands run in the context of each git repo root (the directory containing .git).
# Not limited to git commands — any shell command is accepted (ls, find, custom scripts, etc.).
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
require 'logging'

include Logging

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _find_git_repos(folder:, mindepth:, maxdepth:, filter:)
  seen = {}
  results = []

  find_cmd = [
    'find', folder,
    '-mindepth', mindepth.to_s,
    '-maxdepth', maxdepth.to_s,
    '-type', 'd',
    '-name', '.git'
  ]

  IO.popen(find_cmd, err: File::NULL) do |io|
    io.each_line do |line|
      dir = File.dirname(line.chomp)
      next if filter && !dir.match?(Regexp.new(filter))
      next if seen[dir]
      seen[dir] = true

      # Skip repos whose root directory is a symlink — they are duplicates of their real path.
      next if File.symlink?(dir)

      results << dir
    end
  end

  results
end

private :_find_git_repos

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

# run-all.rb takes all remaining ARGV as the command to execute (no flags).
# Print usage if called with no arguments.
if ARGV.empty? || ARGV.first == '-h' || ARGV.first == '--help'
  puts "Usage: [FOLDER=dir] [FILTER=regex] [MINDEPTH=n] [MAXDEPTH=n] #{File.basename(__FILE__).cyan} <command...>"
  puts ''
  puts '  Finds git repositories and runs the command in each repo directory.'.purple
  puts '  Commands can be git operations (status, pull) or any shell command (ls, find, etc.).'.purple
  puts ''
  puts '  ' + 'Environment variables (all optional):'.purple
  puts "  #{'FOLDER'.yellow}    Root directory to search (default: current dir)"
  puts "  #{'FILTER'.yellow}    Regex to filter repos by path (default: empty = all)"
  puts "  #{'MINDEPTH'.yellow}  Minimum search depth (default: 1)"
  puts "  #{'MAXDEPTH'.yellow}  Maximum search depth (default: 4)"
  puts ''
  puts '  ' + 'Examples:'.purple
  puts "  #{File.basename(__FILE__).cyan} git status                    # git command across all repos"
  puts "  #{File.basename(__FILE__).cyan} ls -la                        # non-git command in each repo"
  puts "  #{('FOLDER=dev MINDEPTH=2 ' + File.basename(__FILE__)).cyan} git status"
  puts "  #{('FILTER=oss ' + File.basename(__FILE__)).cyan} git upreb"
  exit 0
end

cmd_parts = ARGV.dup

folder = ENV.fetch('FOLDER', Dir.pwd)
filter = ENV.fetch('FILTER', nil)
filter = nil if filter&.empty?
mindepth = ENV.fetch('MINDEPTH', '1').to_i
maxdepth = ENV.fetch('MAXDEPTH', '4').to_i

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

increment_script_depth
start_time = print_script_start

section_header 'Running commands in git repositories'

puts "#{'Finding git repos starting in folder'.yellow} '#{folder.cyan}' " \
     "for a min depth of #{mindepth.to_s.cyan} and max depth of #{maxdepth.to_s.cyan}"
puts "#{'Filtering with:'.yellow} #{filter.cyan}" if filter

dir_array = _find_git_repos(folder: folder, mindepth: mindepth, maxdepth: maxdepth, filter: filter)
total = dir_array.length

failed_repos = []
successful_repos = []

dir_array.each_with_index do |dir, idx|
  info "[#{idx + 1} of #{total}] '#{cmd_parts.join(' ').yellow}' in '#{dir.cyan}'"

  # Invoke the user's shell to execute the command, mirroring the shell version's
  # `(cd dir && eval "$@")`. This gives access to shell functions, aliases, and
  # builtins defined in the user's shell config. The command string is passed to
  # the shell via -c, which is safe here because cmd_parts comes from ARGV (user
  # is running this script interactively and controls the command).
  shell = ENV['SHELL'] || '/bin/zsh'
  cmd_string = cmd_parts.join(' ')
  result = Dir.chdir(dir) { system(shell, '-c', cmd_string) }

  if result
    successful_repos << dir
  else
    failed_repos << dir
  end
end

print_operation_summary(total, successful_repos, failed_repos)
print_script_summary(start_time)

exit 1 unless failed_repos.empty?
