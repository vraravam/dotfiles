#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'open3'
require 'tempfile'

require_relative 'core'
require_relative 'git_overrides'
require_relative 'pathname_ext'
require_relative 'string_ext'

# Logic for the global git hooks installed via core.hooksPath (see
# files/--XDG_CONFIG_HOME--/git/hooks/). Each hook file is a few lines that require this
# module and exit with the boolean it returns.
#
# Hooks run on every commit/push in every repository, so this file deliberately avoids
# requiring the heavier logging/env machinery -- it only needs colors, paths and the
# override lookup.
module GitHooks
  extend self

  SYSTEM_RUBY = '/usr/bin/ruby'
  ZSH = '/bin/zsh'
  SHELL_EXTENSIONS = %w[.sh .zsh .bash].freeze

  # pre-commit: syntax-checks staged Ruby (against system Ruby 2.6, the oldest supported)
  # and shell files, runs RuboCop on the Ruby ones if it is installed, then runs the
  # repo-specific hooks. Skip all of it with 'git commit --no-verify'.
  #
  # @param args [Array<String>] Arguments git passed to the hook (forwarded to local hooks)
  # @return [Boolean] false aborts the commit
  def pre_commit(args = [])
    staged = _staged_files
    return true if staged.empty?

    ruby_files, failures = _syntax_check(staged)
    unless failures.empty?
      puts "\n#{'❌ Syntax validation failed:'.red}"
      failures.each { |failure| puts "  #{failure}" }
      puts "\nFix syntax errors and try again, or use #{'git commit --no-verify'.yellow} to skip validation."
      return false
    end

    return false unless _rubocop(ruby_files)

    _run_local_hooks('pre-commit', args)
  end

  # pre-push: runs the repo-specific hooks. Git feeds the refs being pushed on stdin; it
  # is captured once and replayed to every local hook, since a single pipe could only
  # ever be consumed by the first one.
  #
  # @param args [Array<String>] Arguments git passed to the hook (remote name and URL)
  # @return [Boolean] false aborts the push
  def pre_push(args = [])
    stdin_data = $stdin.tty? ? '' : $stdin.read
    _run_local_hooks('pre-push', args, stdin_data: stdin_data)
  end

  # Names of staged (added/copied/modified) files, NUL-delimited so that names with spaces
  # or non-ASCII characters (which git otherwise quotes/escapes) arrive intact.
  #
  # @return [Array<String>]
  def _staged_files
    output, = Open3.capture2('git', 'diff', '--cached', '--name-only', '-z', '--diff-filter=ACM')
    output.split("\0").reject(&:empty?)
  end

  private_class_method :_staged_files

  # Syntax-checks each staged Ruby and shell file.
  #
  # @param staged [Array<String>]
  # @return [Array(Array<String>, Array<String>)] Ruby files that parsed cleanly (for
  #   RuboCop), and one message per file that failed
  def _syntax_check(staged)
    ruby_files = []
    failures = []
    staged.each do |file|
      next unless File.file?(file) # deleted in the working tree

      extension = File.extname(file)
      if extension == '.rb'
        if system(SYSTEM_RUBY, '-c', file, out: File::NULL, err: File::NULL)
          ruby_files << file
        else
          failures << "Ruby syntax error in #{file}"
        end
      elsif SHELL_EXTENSIONS.include?(extension) && !system(ZSH, '-n', file, err: File::NULL)
        failures << "Shell syntax error in #{file}"
      end
    end
    [ruby_files, failures]
  end

  private_class_method :_syntax_check

  # Runs RuboCop (if installed) on the given Ruby files.
  #
  # @param files [Array<String>]
  # @return [Boolean] false if RuboCop reported offenses
  def _rubocop(files)
    return true if files.empty? || !_rubocop_installed?

    puts "\n#{'🔍 Running RuboCop on staged Ruby files...'.blue}"
    # simple format keeps the output compact in hook context
    unless system('rubocop', '--format', 'simple', *files, err: :out)
      puts "\n#{'❌ RuboCop found issues in staged files.'.red}"
      puts "Fix issues and try again, or use #{'git commit --no-verify'.yellow} to skip validation."
      puts "Run #{'rubocop -a'.cyan} to auto-fix safe issues."
      return false
    end

    puts '✓ RuboCop checks passed'.green
    true
  end

  private_class_method :_rubocop

  # @return [Boolean] whether a 'rubocop' executable is on PATH
  def _rubocop_installed?
    ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, 'rubocop')) }
  end

  private_class_method :_rubocop_installed?

  # Runs the repo-specific hooks, in order, stopping at the first failure:
  #   1. .git/hooks.local/<name> in the repository
  #   2. ${PERSONAL_BIN_DIR}/<name>-<repo-dir>.rb or .sh (see GitOverrides)
  #
  # @param name [String] Hook name ('pre-commit' or 'pre-push')
  # @param args [Array<String>] Forwarded to each hook
  # @param stdin_data [String] Replayed on each hook's stdin
  # @return [Boolean] false if a hook failed
  def _run_local_hooks(name, args, stdin_data: '')
    hooks = [File.join('.git', 'hooks.local', name), GitOverrides.script_for(name, Dir.pwd)&.to_s]
    hooks.compact.select { |hook| File.file?(hook) && File.executable?(hook) }.all? do |hook|
      Tempfile.create('git-hook-stdin') do |stdin_file|
        stdin_file.write(stdin_data)
        stdin_file.flush
        system(*GitOverrides.command_for(hook), *args, in: stdin_file.path)
      end
    end
  end

  private_class_method :_run_local_hooks
end
