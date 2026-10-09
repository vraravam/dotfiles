#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/git-command.rb
#
# Runs one of the folder-aware git commands (push, pull, cc, upreb) -- see
# utilities/git_commands.rb for what each does. If the target repo has an override script
# (${PERSONAL_BIN_DIR}/<command>-<repo-dir>.rb or .sh) it runs that instead.
#
# Typed as plain 'push', 'pull', 'cc' and 'upreb' via aliases in ${ZDOTDIR}/.aliases.
#
# Usage:
#   Standalone: git-command.rb <push|pull|cc|upreb> [<folder>] [--switch ...]
#   Module:     GitCommands.run(command: 'push', args: ['/path/to/repo', '--force-with-lease'])
#
# Examples:
#   git-command.rb push                          # current directory
#   git-command.rb pull ~/dev/oss/some-repo
#   git-command.rb cc --expire=now

require_relative 'utilities/git_commands'

if __FILE__ == $PROGRAM_NAME
  command = ARGV.shift

  unless GitCommands::COMMANDS.include?(command)
    warn "Usage: #{File.basename($PROGRAM_NAME)} <#{GitCommands::COMMANDS.join('|')}> [<folder>] [--switch ...]"
    exit(%w[-h --help].include?(command) ? 0 : 1)
  end

  exit(GitCommands.run(command: command, args: ARGV) ? 0 : 1)
end
