#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

require_relative 'command_utils'
require_relative 'core'
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
  include Core
  extend Core
  extend self

  # Searched in order, so a Ruby override wins when both exist.
  EXTENSIONS = %w[rb sh].freeze

  # Env var set (to any non-empty value) on override subprocesses so that anything they
  # call -- the 'git cc'/'git upreb' commands, this module's own dispatcher -- skips override
  # detection instead of re-dispatching to the same override. This bounds the recursion
  # to one level.
  SKIP_ENV_VAR = '_GIT_OVERRIDE_SKIP'

  # The env hash that sets SKIP_ENV_VAR, for passing as the leading argument of system/exec.
  SKIP_ENV = { SKIP_ENV_VAR => '1' }.freeze

  # @param command [String] Command or hook name (e.g. 'cc', 'upreb', 'pre-commit')
  # @param dir [String, Pathname] Repo directory; only its basename is used
  # @return [Pathname, nil] The executable override script, or nil if there is none
  def script_for(command, dir)
    name = File.basename(File.expand_path(dir.to_s))
    EXTENSIONS.each do |extension|
      candidate = CommandUtils.query('which', "#{command}-#{name}.#{extension}")
      unless nil_or_empty?(candidate)
        candidate_pn = Pathname(candidate)
        return candidate_pn if candidate_pn.file? && candidate_pn.executable?
      end
    end
    nil
  end

  # The argv that runs +script+. A Ruby override is run with the interpreter already running
  # this process (RbConfig.ruby) instead of through its '#!/usr/bin/env ruby' shebang: when
  # that resolves to a mise shim in a directory with no pinned Ruby, a shim launched from a
  # process that was itself started via the shim trips mise's recursion guard and aborts.
  #
  # The interpreter is started with --disable-gems: overrides only 'require' the shared
  # utilities (which need nothing outside the standard library), and loading RubyGems costs
  # ~70ms per launch. An override that does need a gem can 'require "rubygems"' itself first.
  #
  # @param script [Pathname, String] An override returned by script_for
  # @return [Array<String>]
  def command_for(script)
    script = script.to_s
    return [script] unless File.extname(script) == '.rb'

    # Lazily: under --disable-gems nothing has loaded 'rbconfig' yet and loading it costs ~30ms
    # (macOS system Ruby), which a caller that never launches a Ruby override should not pay.
    require 'rbconfig'
    [RbConfig.ruby, '--disable-gems', script]
  end

  # The full argv -- leading env hash included -- to run +script+ as an override subprocess,
  # in the form system/exec/CommandUtils.run_interactive accept. The env hash sets SKIP_ENV_VAR
  # (so the 'git cc'/'git upreb' commands and GitCommands do not re-dispatch to this same
  # override if it shells out to them) and RUBYLIB (so a Ruby override can 'require' the
  # shared utilities even under cron, where it is unset).
  #
  # @param script [Pathname, String] An override returned by script_for
  # @param args [Array<String>] Arguments for the override
  # @return [Array] [env, *command, *args]
  def argv_for(script, args)
    [SKIP_ENV.merge('RUBYLIB' => rubylib), *command_for(script), *args]
  end

  # RUBYLIB for an override process: the shared utilities directory first, so a Ruby
  # override can 'require' them (e.g. 'git_commands') even when launched from cron, where
  # the shell never set it up.
  #
  # @return [String]
  def rubylib
    [EnvVars::DOTFILES_DIR.join('scripts', 'utilities').to_s, EnvVars.rubylib].compact.join(File::PATH_SEPARATOR)
  end

  # @return [Boolean] true when override detection must be skipped (see SKIP_ENV_VAR); a
  #   blank value does not count as set
  def skip?
    EnvVars.set?(SKIP_ENV_VAR)
  end
end
