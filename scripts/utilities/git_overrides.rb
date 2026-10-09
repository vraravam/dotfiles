#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'
require 'rbconfig'

require_relative 'env_vars'

# Locates folder-specific override scripts for git commands and hooks.
#
# An override for command <cmd> in a repo whose directory is named <name> is the
# executable ${PERSONAL_BIN_DIR}/<cmd>-<name>.rb (preferred) or .sh. It replaces the
# default implementation of <cmd> for that one repo (e.g. to delete a stale tag first,
# or to suspend cron for the duration). This is the single Ruby source of truth for that
# naming convention; the shell side (dispatch_or_fallback in .aliases, and
# scripts/git-cc and scripts/git-upreb) mirrors it.
module GitOverrides
  extend self

  # Searched in order, so a Ruby override wins when both exist.
  EXTENSIONS = %w[rb sh].freeze

  # Env var set (to any non-empty value) on override subprocesses so that anything they
  # call -- the 'git cc'/'git upreb' commands, this module's own dispatcher -- skips override
  # detection instead of re-dispatching to the same override. This bounds the recursion
  # to one level.
  SKIP_ENV_VAR = '_GIT_OVERRIDE_SKIP'

  # @param command [String] Command or hook name (e.g. 'cc', 'upreb', 'pre-commit')
  # @param dir [String, Pathname] Repo directory; only its basename is used
  # @return [Pathname, nil] The executable override script, or nil if there is none
  def script_for(command, dir)
    name = File.basename(File.expand_path(dir.to_s))
    EXTENSIONS.each do |extension|
      candidate = EnvVars::PERSONAL_BIN_DIR.join("#{command}-#{name}.#{extension}")
      return candidate if candidate.file? && candidate.executable?
    end
    nil
  end

  # The argv that runs +script+. A Ruby override is run with the interpreter already running
  # this process (RbConfig.ruby) instead of through its '#!/usr/bin/env ruby' shebang: when
  # that resolves to a mise shim in a directory with no pinned Ruby, a shim launched from a
  # process that was itself started via the shim trips mise's recursion guard and aborts.
  #
  # @param script [Pathname, String] An override returned by script_for
  # @return [Array<String>]
  def command_for(script)
    script = script.to_s
    File.extname(script) == '.rb' ? [RbConfig.ruby, script] : [script]
  end

  # RUBYLIB for an override process: the shared utilities directory first, so a Ruby
  # override can 'require' them (e.g. 'git_commands') even when launched from cron, where
  # the shell never set it up.
  #
  # @return [String]
  def rubylib
    [EnvVars::DOTFILES_DIR.join('scripts', 'utilities').to_s, ENV.fetch('RUBYLIB', nil)].compact.join(File::PATH_SEPARATOR)
  end

  # @return [Boolean] true when override detection must be skipped (see SKIP_ENV_VAR)
  def skip?
    !ENV.fetch(SKIP_ENV_VAR, '').empty?
  end
end
