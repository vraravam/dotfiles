#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pathname'

require_relative 'command_utils'
require_relative 'core'
require_relative 'env_vars'
require_relative 'git_overrides'
require_relative 'git_processor'
require_relative 'logging'

# Folder-aware 'push', 'pull', 'cc' and 'upreb' commands (typed as aliases of
# scripts/git-command.rb). Each takes an optional folder (default: the current directory)
# plus '--switches' that are forwarded to the underlying git command, and wraps it with a
# section header, a "is this a git repo" guard and -- where the network can hang --
# 'git with-retry' protection.
#
# A repo can replace any of the four with its own override script (see GitOverrides). A
# Ruby override calls the default implementation back through the module methods here,
# typically wrapped in a block such as Cron.with_cron_suspended:
#
#   Cron.with_cron_suspended { GitCommands.cc(args: ARGV, header: false) }
#
# All methods return true: like the shell functions they replace, a failing underlying git
# command is surfaced as a recorded warning (see Logging.print_script_summary) rather than
# a failing exit status, so chained invocations ('push; pull') keep going.
module GitCommands
  extend self

  COMMANDS = %w[push pull cc upreb].freeze

  # Retry parameters for 'git with-retry' (timeout secs, max attempts): the fetch/pull
  # parameters match 'git fo' (scripts/git-fo); push uses a wall-clock timeout (see _push).
  WITH_RETRY_TIMEOUT_SECS = '60'
  WITH_RETRY_ATTEMPTS = '3'

  # Runs +command+ for the folder named in +args+: its override script if the repo has one
  # (replacing this process, so the override keeps its own script banner/summary), else
  # the default implementation.
  #
  # @param command [String] One of COMMANDS
  # @param args [Array<String>] Optional folder plus '--switches'
  # @return [Boolean] true (see the module comment on why failures are warnings, not a status)
  def run(command:, args: [])
    raise ArgumentError, "Unknown command '#{command}' (expected one of #{COMMANDS.join(', ')})" unless COMMANDS.include?(command)

    folder, switches = parse_args(args)
    override = GitOverrides.skip? ? nil : GitOverrides.script_for(command, folder)
    exec_override(override, folder, switches) if override

    # No Logging.run_script here: a bare 'push'/'pull'/'cc'/'upreb' prints just its section
    # header (as the shell functions it replaced did), not a script start/finish banner.
    # Overrides are separate processes and bring their own banner via run_script.
    public_send(command, args: args, header: true)
    true
  end

  # Splits raw arguments into the target folder (the first argument that is not a
  # '--switch', defaulting to the current directory) and the '--switches'.
  #
  # @param args [Array<String>]
  # @return [Array(String, Array<String>)]
  # :reek:UtilityFunction -- Stateless argument parser
  def parse_args(args)
    switches, positional = args.partition { |arg| arg.start_with?('--') }
    [positional.reject(&:empty?).first || Dir.pwd, switches]
  end

  # Pushes the repo, with hang protection. A push does not grow the local .git/objects as
  # it progresses (it only reads them), so there is no on-disk signal for with-retry to
  # watch: it falls back to a plain wall-clock timeout ('-' progress path). Deliberately
  # the bare builtin 'git push' wrapped here -- git always resolves builtins before
  # aliases, so this is the only place that can add retry protection to it.
  #
  # @param args [Array<String>] Optional folder plus '--switches'
  # @param header [Boolean] Print a section header first
  # @return [Boolean] true
  def push(args: [], header: true)
    folder, switches = parse_args(args)
    return true unless _ready?(folder, 'Pushing', 'pushing of', header)

    _with_retry(folder, '-', 'push', *switches) || Logging.record_warning("Failed to push '#{folder.cyan}'")
    true
  end

  # Pulls the repo, with hang protection. If the pull still fails and the repo has opted in
  # with 'git config --local pull.allowResetOnDivergedHistory true' (e.g. a repo that is
  # periodically force-squashed), falls back to 'git fo --rebase', which resets onto the
  # upstream when the histories share no common ancestor. Everywhere else a failed pull is
  # reported and left alone: retrying the same pull cannot fix diverged history.
  #
  # Deliberately not 'fo --rebase' for the common case: it refuses on a dirty tree, whereas
  # this interactive path benefits from the repo's own autoStash setting.
  #
  # @param args [Array<String>] Optional folder plus '--switches'
  # @param header [Boolean] Print a section header first
  # @return [Boolean] true
  def pull(args: [], header: true)
    folder, switches = parse_args(args)
    return true unless _ready?(folder, 'Pulling', 'pulling of', header)
    return true if _with_retry(folder, Pathname.new(folder).join('.git', 'objects').to_s, 'pull', *switches)

    return true unless GitProcessor.new(dir: folder).config_bool('pull.allowResetOnDivergedHistory')

    Logging.info "Pull failed -- '#{folder.cyan}' has 'pull.allowResetOnDivergedHistory' set; checking for diverged history"
    Logging.record_warning("Failed to reconcile '#{folder.cyan}' -- see errors above") unless _git(folder, 'fo', '--rebase')
    true
  end

  # Compresses the repo and reclaims disk space via the 'git cc' alias (prune, repack,
  # gc). Switches such as --expire=<when> are forwarded to 'git reflog expire'.
  #
  # @param args [Array<String>] Optional folder plus '--switches'
  # @param header [Boolean] Print a section header first
  # @return [Boolean] true
  def cc(args: [], header: true)
    folder, switches = parse_args(args)
    return true unless _ready?(folder, 'Compressing', 'finding size of the', header)

    _git(folder, 'cc', *switches) || Logging.record_warning("'#{'git cc'.cyan}' failed in '#{folder.cyan}'")
    true
  end

  # Rebases every local branch onto its upstream and pushes it (via the 'git upreb'
  # alias), finishing on the branch that was checked out. A branch whose local and remote
  # histories diverged symmetrically with no content difference (remote was force-pushed
  # or rebased) is safely rebased onto its upstream.
  #
  # @param args [Array<String>] Optional folder
  # @param header [Boolean] Print a section header first
  # @return [Boolean] true
  def upreb(args: [], header: true)
    folder, = parse_args(args)
    Logging.section_header("#{'Upreb-ing'.yellow} '#{folder.cyan}'") if header

    current = branches = nil
    GitProcessor.new(dir: folder) do |git|
      current = git.current_branch
      branches = git.local_branches
    end
    Logging.info "current branch: #{current.to_s.yellow}"
    # The checked-out branch goes last so the repo ends up where it started.
    ordered = branches.reject { |branch| branch == current } + [current].compact

    ordered.each do |branch|
      Logging.debug "processing: #{branch.yellow}"
      _git(folder, 'switch', branch, skip_override: false)
      _git(folder, 'upreb')
      _rebase_if_symmetric_divergence(folder, branch)
    end
    true
  end

  private

  # Replaces this process with the override script, run from inside the folder with
  # override detection switched off for anything it calls, and with RUBYLIB pointing at
  # the shared utilities so a Ruby override can 'require' them even under cron.
  #
  # @param override [Pathname]
  # @param folder [String]
  # @param args [Array<String>] The '--switches' only: the override runs with the folder as
  #   its working directory, so passing the folder along as well would resolve it twice
  #   (a relative path would then point inside itself)
  # @return [void] never returns
  def exec_override(override, folder, args)
    Logging.info "Delegating to override '#{override.cyan}' for '#{folder.cyan}'"
    env = { GitOverrides::SKIP_ENV_VAR => '1', 'RUBYLIB' => GitOverrides.rubylib }
    Dir.chdir(folder) { exec(env, *GitOverrides.command_for(override), *args) }
  end

  # Common preamble: optional header, then the git-repo guard.
  #
  # @return [Boolean] false if +folder+ is not a git repo (a warning has been logged)
  def _ready?(folder, verb, skip_phrase, header)
    Logging.section_header("#{verb.yellow} '#{folder.cyan}'") if header
    return true if GitProcessor.repo?(folder)

    Logging.warn "Skipping #{skip_phrase} the repo since '#{folder.cyan}' doesn't exist or is not a git repo"
    false
  end

  # Runs 'git -C folder <args>' with override detection skipped, so a 'git cc'/'git
  # upreb' alias reached from here does not dispatch back to the override that called us.
  #
  # @return [Boolean] whether git exited 0
  def _git(folder, *args, skip_override: true)
    env = skip_override ? { GitOverrides::SKIP_ENV_VAR => '1' } : {}
    CommandUtils.run_interactive(env, 'git', '-C', folder, *args)
  end

  # Runs 'git -C folder <args>' under 'git with-retry' (see the alias for the semantics of
  # the progress path), with override detection skipped.
  #
  # @return [Boolean] whether it eventually succeeded
  def _with_retry(folder, progress_path, *args)
    retry_prefix = ['git', 'with-retry', WITH_RETRY_TIMEOUT_SECS, WITH_RETRY_ATTEMPTS, File::NULL, progress_path]
    CommandUtils.run_interactive({ GitOverrides::SKIP_ENV_VAR => '1' }, *retry_prefix, 'git', '-C', folder, *args)
  end

  # After 'git upreb', a branch that is still both ahead of and behind its upstream by the
  # same number of commits with no content difference has only diverged cosmetically (the
  # remote was force-pushed or rebased). Rebasing onto the upstream is then lossless.
  def _rebase_if_symmetric_divergence(folder, branch)
    git = GitProcessor.new(dir: folder)
    incoming = git.commit_count(range: 'HEAD..@{u}')
    outgoing = git.commit_count(range: '@{u}..HEAD')
    return unless incoming.positive? && incoming == outgoing
    return unless git.same_content_as?('@{u}')

    Logging.info "Symmetric diverge with no content diff -- rebasing #{branch.yellow} onto @{u}"
    _git(folder, 'rebase', '@{u}', skip_override: false)
  end
end
