#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/software-updates-cron.rb
#
# Runs the periodic update steps in sequence. Intended to be invoked from cron
# every hour.
#
# Each step is guarded by a command-exists check so missing tools are silently
# skipped. Step failures are collected as warnings rather than aborting the
# entire run -- all steps execute regardless of earlier failures, and a single
# grouped macOS notification is sent at the end.
#
# Output behavior (when run from crontab with conditional logging):
# - All runs: output captured to temp file during execution
# - Success (exit 0): temp file discarded, writes ~/.software-updates-run-log timestamp
# - Failure (exit non-zero): temp file appended to ~/software-updates-cron.log
# - Check run history: cat ~/.software-updates-run-log
# - Check errors: tail ~/software-updates-cron.log
#
# Usage:
#   Standalone: software-updates-cron.rb
#   Module:     SoftwareUpdatesCron.run

require 'fileutils'
require 'rbconfig'
require 'shellwords'

require_relative 'run-all'
require_relative 'utilities/antidote'
require_relative 'utilities/command_utils'
require_relative 'utilities/core'
require_relative 'utilities/enumerable_ext'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/git_workspace'
require_relative 'utilities/logging'
require_relative 'utilities/macos'
require_relative 'utilities/path_utils'
require_relative 'utilities/profiles_repo'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module SoftwareUpdatesCron
  extend self

  # Public API method for post-update summary and notification.
  #
  # @param start_time [Integer] Unix epoch timestamp from when updates started
  # @return [Boolean] true on success (no errors/warnings), false if any errors or warnings occurred
  def run(start_time:)
    outdated_flat = _run_all_updates
    now = Core.current_timestamp
    duration = Logging.format_duration(Core.duration_since(start_time))

    Logging.success "Finished software updates at #{now.purple} in #{duration.light_blue}"

    # Build a single grouped macOS notification.
    notification_parts = []

    # Access logging module's private step tracking variables
    step_errors = Logging.instance_variable_get(:@step_errors) || []
    step_warnings = Logging.instance_variable_get(:@step_warnings) || []

    unless nil_or_empty?(step_errors)
      notification_parts << "#{step_errors.length} error(s): #{step_errors.join('; ')}"
    end
    unless nil_or_empty?(step_warnings)
      notification_parts << "#{step_warnings.length} warning(s): #{step_warnings.join('; ')}"
    end

    title_icon = (nil_or_empty?(step_errors) && nil_or_empty?(step_warnings)) ? '✅' : '⚠️'
    msg = nil_or_empty?(notification_parts) ? '.' : " -- #{notification_parts.join(' | ')}"

    unless nil_or_empty?(outdated_flat)
      title_icon = '⚠️'
      msg += ". Needs manual update: #{outdated_flat}"
    end

    MacOS.notify("Done at #{now} (took #{duration})#{msg}", "#{title_icon} Software Updates")

    # Write end marker for audit trail when run completes without errors/warnings
    if nil_or_empty?(step_errors) && nil_or_empty?(step_warnings)
      run_log = EnvVars::HOME.join('.software-updates-run-log')
      # Append completion marker (start marker was written before run began)
      run_log.write("COMPLETED: #{now} (took #{duration})\n", mode: 'a')
    end

    # Return false if there were any errors or warnings
    nil_or_empty?(step_errors) && nil_or_empty?(step_warnings)
  end

  # Runs the block guarded by a check for +check_cmd+. Records a warning on
  # failure rather than aborting so all steps run regardless of earlier failures.
  def _perform_update(title, check_cmd, &block)
    Logging.with_step("update #{title}", "#{'Updating'.yellow} #{title.purple}") do
      unless PathUtils.command_exists?(check_cmd)
        Logging.debug "Command not found: '#{check_cmd}'"
        return
      end

      if block.call
        Logging.success "Successfully updated: '#{title}'"
      else
        Logging.record_warning("Failed to update '#{title}'")
      end
    end
  end

  private_class_method :_perform_update

  def _update_home_repos
    Logging.with_step('Update repos in home folder') do
      unless RunAll.run(
        command: ['git', 'pull-safe'],
        folder: EnvVars::HOME.to_s,
        filter: '.bin|zsh|mise',
        maxdepth: 5
      )
        Logging.record_warning('Some home repos could not be auto-updated -- working tree may be dirty. Rebase manually.')
      end
    end
  end

  private_class_method :_update_home_repos

  def _upreb_oss_repos
    Logging.with_step('Upreb repos in oss folder') do
      oss_folder = EnvVars::PROJECTS_BASE_DIR.join('oss')
      return unless oss_folder.directory?

      unless RunAll.run(
        command: ['git', 'upreb'],
        folder: oss_folder.to_s,
        maxdepth: 4
      )
        Logging.record_warning('Some oss repos could not be auto-updated -- working tree may be dirty. Run upreb manually.')
      end
    end
  end

  private_class_method :_upreb_oss_repos

  def _run_all_updates
    # Brew update: use bundle check before full bundle to avoid reinstalling
    # already-installed formulae on every cron run.
    _perform_update('brews', 'brew') do
      # Update brew itself first to get latest formula definitions
      # Redirect stdout to suppress progress output in cron context
      CommandUtils.run_silent('brew', 'update', err: :err) || true
      # 'brew bundle check' exits 0 when everything is installed -- skip the full
      # bundle install in that case to avoid re-checking every formula every hour.
      # Keep check output visible for debugging missing packages.
      system('brew', 'bundle', 'check', '-v') || system('brew', 'bundle', 'install', '-q')
    end
    _perform_update('mise plugins', 'mise') do
      # mise binary is upgraded using homebrew
      # Plugin registry updates moved to 6-hour schedule (balance between freshness and rate limiting).
      # Check timestamp cache to avoid unnecessary API calls (GitHub rate limiting).
      plugin_update_interval = 6 * 3600  # 6 hours in seconds
      last_plugin_update_file = EnvVars::XDG_CACHE_HOME.join('mise-plugins-last-update')

      # Update plugins (every 6 hours) - check timestamp to avoid rate limiting
      # Redirect stdout to suppress 'all tools are installed' messages
      unless last_plugin_update_file.file? && Core.elapsed?(File.mtime(last_plugin_update_file).to_i, plugin_update_interval)
        CommandUtils.run_silent('mise', 'plugins', 'update', err: :err)
        FileUtils.touch(last_plugin_update_file)
      else
        hours_since = Core.duration_since(File.mtime(last_plugin_update_file).to_i) / 3600
        Logging.debug "mise plugins were updated #{hours_since} hour(s) ago -- skipping (interval: #{plugin_update_interval / 3600} hours)"
      end

      # Always run tool upgrades (hourly is appropriate for version updates)
      CommandUtils.run_silent('mise', 'upgrade', '--bump', err: :err)
    end
    _perform_update('tldr database', 'tldr') { CommandUtils.run_silent('tldr', '--update', err: :err) }
    _perform_update('git-ignore database', 'git-ignore-io') { system('git', 'ignore-io', '--update-list') }
    _perform_update('claude-code', 'claude') { system('claude', 'update') }

    Logging.with_step('antidote plugin update', "#{'Updating'.yellow} #{'antidote plugins'.purple} and regenerating plugin bundle") do
      Antidote.update_and_regenerate_bundle
    end

    Logging.with_step('bat cache update', "#{'Updating'.yellow} #{'bat'.purple} cache") do
      if PathUtils.command_exists?('bat')
        bat_config_dir = CommandUtils.query('bat', '--config-dir')
        bat_syntax_dir_pn = Pathname.new(bat_config_dir).join('syntaxes')
        PathUtils.ensure_directories_exist(bat_syntax_dir_pn)

        system(
          'curl', '--retry', '3', '--retry-delay', '5', '-fsSL',
          'https://raw.githubusercontent.com/mattmc3/antidote/main/misc/zsh_plugins.sublime-syntax',
          '-o', bat_syntax_dir_pn.join('zsh_plugins.sublime-syntax').to_s
        )
        # Redirect stdout to suppress 'Writing theme/syntax set' messages
        CommandUtils.run_silent('bat', 'cache', '--build', err: :err)
      end
    end

    Logging.with_step('zen-browser-desktop tag cleanup', "#{"Remove 'twilight' tag from".yellow} #{'zen-browser-desktop'.purple} repo") do
      zen_desktop = EnvVars::PROJECTS_BASE_DIR.join('oss', 'zen-browser-desktop')
      GitProcessor.new(dir: zen_desktop) do |git|
        if git.tag_exists?('twilight')
          git.delete_tag('twilight')
          Logging.success("Deleted #{'twilight'.purple} tag.")
        end
      end
    end

    # TODO: Similar to ollama, need to update the models used by omlx via cli
    Logging.with_step('ollama models update', 'Pull ollama models'.yellow) do
      if PathUtils.command_exists?('ollama')
        # Pull models at most once per 24 hours (configurable interval).
        # ollama pull downloads models even if already up to date (no --check flag),
        # so timestamp-based caching prevents unnecessary large transfers.
        model_update_interval = 24 * 3600  # seconds
        last_update_file = EnvVars::XDG_CACHE_HOME.join('ollama-last-update')

        if last_update_file.file?
          hours_since = Core.duration_since(File.mtime(last_update_file).to_i) / 3600
          unless Core.elapsed?(File.mtime(last_update_file).to_i, model_update_interval)
            Logging.debug "Ollama models were updated #{hours_since} hour(s) ago -- skipping (interval: #{model_update_interval / 3600} hours)"
            next
          end
        end

        # reference: https://insiderllm.com/guides/ollama-mac-setup-optimization/
        # reference: https://popularaitools.ai/blog/run-gemma-4-locally-opencode-2026
        # Note: This list is up-to-date as of 2026-06-06
        # 'qwen3.6:27b',         # reference: gChat from work (AIFSD chat room): strong coding model
        # 'gemma4:e2b-mlx',      # reference: https://www.youtube.com/watch?v=BaAy1DodIcQ (Ollama + Claude code for local AI) - doesn't edit, only single file for suggestions
        # 'qwen2.5-coder:14b'   # Qwen 2.5 Coder 14B: strong coding model
        # 'rafw007/gemma4-e4b-claude-coder',      # reference: https://www.youtube.com/watch?v=BaAy1DodIcQ (Ollama + Claude code for local AI) - not sure if this runs via opencode, trying now
        # 'deepseek-coder-v2',
        # 'gpt-oss:20b',
        # 'qwen3.5:9b-q8_0',   # Qwen 3.5 9B (Q8): strong reasoning model
        # 'mdq100/qwen3.5-coder:35b',
        # 'gemma3:12b'         # Gemma 3 12B: free coding model
        # 'codestral:22b',     # TODO: Need to research
        # Fetch the list of currently downloaded models dynamically via 'ollama list'.
        # This replaces the hardcoded list to automatically keep all local models up to date.
        # Output format: "NAME             ID              SIZE      MODIFIED"
        # We extract the NAME column (first field) and skip the header row.
        # CommandUtils.query returns stripped stdout; failure is not expected for 'ollama list'
        # when ollama binary exists (already checked via command_exists?).
        stdout = CommandUtils.query('ollama', 'list')
        # Parse model names from output (skip header, extract first column)
        # filter_map polyfill in enumerable_ext.rb provides optimized single-pass implementation for Ruby 2.6
        ollama_models = Array(stdout.lines[1..-1]).filter_map { |line| line.split.first }

        if ollama_models.empty?
          Logging.info 'No ollama models found locally -- skipping updates'
        else
          Logging.info "Found #{ollama_models.size} ollama model(s) to update: #{ollama_models.join(', ')}"
          ollama_models.each do |model|
            # Redirect stdout/stderr to suppress progress bars and ANSI escape sequences in cron context
            if CommandUtils.run_silent('ollama', 'pull', model)
              Logging.success "Successfully pulled model: '#{model.cyan}'"
            else
              Logging.record_warning "Failed to pull model: '#{model.cyan}'"
            end
          end
          # Touch timestamp file to mark successful update
          FileUtils.touch(last_update_file)
        end
      else
        Logging.debug 'ollama not found -- skipping model pulls'
      end
    end

    Logging.success 'Finished independent updates.'

    # Repo updates
    _update_home_repos
    sleep 10  # Avoid GitHub rate-limiting between bursts of API calls.
    _upreb_oss_repos
    # git maintain (restore-mtime + maintenance register/start) now runs once per repo at clone time
    # via clone_repo_into() in .shellrc and GitProcessor.clone_repo_into(). No need to repeat hourly -
    # these are idempotent operations that only need to run once. Removed from cron to save thousands
    # of git forks/hour.

    Logging.with_step('setup dev env', 'Setup dev environment'.yellow) do
      GitWorkspace.setup_dev_environment(first_install: EnvVars.first_install?)
    end

    Logging.with_step('regenerate repo aliases', 'Regenerate repo aliases'.yellow) do
      GitWorkspace.regenerate_repo_aliases
    end

    Logging.with_step('capture preferences', 'Capture app preferences'.yellow) do
      capture_prefs_script = Pathname.new(__dir__).join('capture-prefs.rb')
      # Set COLUMNS for terminal width detection (cron has no TTY, defaults to 80)
      env = { 'COLUMNS' => EnvVars.columns.to_s }
      if system(env, RbConfig.ruby, capture_prefs_script.to_s, '-e')
        Logging.success 'Finished capturing app preferences'
      else
        Logging.record_error('Failed to capture app preferences')
      end
    end

    Logging.with_step('prune session backups', 'Prune old timestamped session backups from browser-profiles repo'.yellow) do
      ProfilesRepo.prune_old_session_backups
    end

    Logging.with_step('check profiles repo size') do
      ProfilesRepo.check_size_limit
    end

    Logging.with_step('update home and profiles repos') do
      unless GitWorkspace.update_all_repos
        Logging.record_error('Failed to update home and profiles repos')
      end
    end

    Logging.with_step('report status of all repos') do
      GitWorkspace.status_all_repos
    end

    Logging.with_step('update browser-profiles nested chrome repos', 'Updating all browser profile chrome folders if they are git repos'.yellow) do
      ProfilesRepo.update_chrome_folders
    end

    Logging.with_step('check outdated greedy brew apps', 'Checking if any greedy applications are outdated'.yellow) do
      MacOS.check_and_notify_outdated_apps
    end
  end

  private_class_method :_run_all_updates
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  include Logging

  Logging.run_script do |start_time|
    # Write start marker before beginning work (shows cron is running)
    run_log = EnvVars::HOME.join('.software-updates-run-log')
    start_timestamp = Core.current_timestamp
    run_log.write("STARTED: #{start_timestamp}\n", mode: 'a')

    success = SoftwareUpdatesCron.run(start_time: start_time)

    # Write failure marker if run had errors/warnings
    unless success
      end_timestamp = Core.current_timestamp
      duration = Logging.format_duration(Core.duration_since(start_time))
      run_log.write("FAILED: #{end_timestamp} (took #{duration})\n", mode: 'a')
    end

    # Single exit point: exit non-zero if there were errors or warnings.
    # The exit code doesn't affect mail generation (MAILTO="" disables it),
    # but it's still useful for scripting contexts that check exit codes.
    exit(success ? 0 : 1)
  end
end
