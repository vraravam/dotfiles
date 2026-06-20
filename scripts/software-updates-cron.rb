#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/software-updates-cron.rb
#
# Runs the periodic update steps in sequence. Intended to be invoked from cron
# every hour.
#
# Each step is guarded by a command-exists check so missing tools are silently
# skipped. Step failures are collected as warnings rather than aborting the
# entire run -- all steps execute regardless of earlier failures, and a single
# grouped macOS notification is sent at the end.
#
# Output behavior (when run via chronic in crontab):
# - Success: no output to log (chronic suppresses), writes ~/.software-updates-last-success
# - Failure: full output to log (chronic passes through when exit non-zero)
# - Check last success: cat ~/.software-updates-last-success
#
# Usage:
#   Standalone: software-updates-cron.rb
#   Module:     SoftwareUpdatesCron.run

require 'open3'
require 'rbconfig'
require 'shellwords'

require_relative 'run-all'
require_relative 'utilities/antidote'
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
    now = MacOS.current_timestamp
    duration = Logging.format_duration(Time.now.to_i - start_time)

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

    # Write success marker file for audit trail when run completes without errors/warnings
    if nil_or_empty?(step_errors) && nil_or_empty?(step_warnings)
      success_marker = EnvVars::HOME.join('.software-updates-last-success')
      # Append to file (creates if doesn't exist), each run on a new line
      success_marker.write("#{now} (took #{duration})\n", mode: 'a')
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

  def _restore_mtime_and_register_maintenance
    Logging.with_step('restore mtime and register maintenance', 'Restore mtime and register for maintenance'.yellow) do
      gitconfig = EnvVars::HOME.join('.gitconfig-oss.inc')
      folder = EnvVars::HOME.to_s
      maxdepth = 7

      RunAll.run(command: ['git', 'restore-mtime', '-c'], folder: folder, maxdepth: maxdepth)
      RunAll.run(command: ['git', 'maintenance', 'register', '--config-file', gitconfig.to_s], folder: folder, maxdepth: maxdepth)
      RunAll.run(command: ['git', 'maintenance', 'start'], folder: folder, maxdepth: maxdepth)
    end
  end
  private_class_method :_restore_mtime_and_register_maintenance

  def _run_all_updates
    # Brew update: use bundle check before full bundle to avoid reinstalling
    # already-installed formulae on every cron run.
    _perform_update('brews', 'brew') do
      # Update brew itself first to get latest formula definitions
      system('brew', 'update') || true
      # 'brew bundle check' exits 0 when everything is installed -- skip the full
      # bundle install in that case to avoid re-checking every formula every hour.
      system('brew', 'bundle', 'check', '-v') || system('brew', 'bundle', 'install', '-q')
    end
    _perform_update('mise plugins', 'mise') do
      # mise binary is upgraded using homebrew
      system('mise', 'plugins', 'update') && system('mise', 'upgrade', '--bump')
    end
    _perform_update('tldr database', 'tldr') { system('tldr', '--update') }
    _perform_update('git-ignore database', 'git-ignore-io') { system('git', 'ignore-io', '--update-list') }
    _perform_update('claude-code', 'claude') { system('claude', 'update') }

    Logging.with_step('antidote plugin update', "#{'Updating'.yellow} #{'antidote plugins'.purple} and regenerating plugin bundle") do
      Antidote.update_and_regenerate_bundle
    end

    Logging.with_step('bat cache update', "#{'Updating'.yellow} #{'bat'.purple} cache") do
      if PathUtils.command_exists?('bat')
        bat_config_dir, = Open3.capture3('bat', '--config-dir')
        bat_syntax_dir_pn = Pathname.new(bat_config_dir.strip).join('syntaxes')
        PathUtils.ensure_directories_exist(bat_syntax_dir_pn)

        system(
          'curl', '--retry', '3', '--retry-delay', '5', '-fsSL',
          'https://raw.githubusercontent.com/mattmc3/antidote/main/misc/zsh_plugins.sublime-syntax',
          '-o', bat_syntax_dir_pn.join('zsh_plugins.sublime-syntax').to_s
        )
        system('bat', 'cache', '--build')
      end
    end

    Logging.with_step('zen-browser-desktop tag cleanup', "#{"Remove 'twilight' tag from".yellow} #{'zen-browser-desktop'.purple} repo") do
      zen_desktop = EnvVars::PROJECTS_BASE_DIR.join('oss', 'zen-browser-desktop')
      if GitProcessor.repo?(zen_desktop)
        GitProcessor.new(dir: zen_desktop) do |git|
          if git.tag_exists?('twilight')
            git.delete_tag('twilight')
            Logging.success("Deleted #{'twilight'.purple} tag.")
          end
        end
      end
    end

    # TODO: Similar to ollama, need to update the models used by omlx via cli
    Logging.with_step('ollama models update', 'Pull ollama models'.yellow) do
      if PathUtils.command_exists?('ollama')
        # reference: https://insiderllm.com/guides/ollama-mac-setup-optimization/
        # reference: https://popularaitools.ai/blog/run-gemma-4-locally-opencode-2026
        # Note: This list is up-to-date as of 2026-06-06
        ollama_models = [
          # 'gemma4:e2b-mlx',      # reference: https://www.youtube.com/watch?v=BaAy1DodIcQ (Ollama + Claude code for local AI) - doesn't edit, only single file for suggestions
          'qwen2.5-coder:14b',   # Qwen 2.5 Coder 14B: strong coding model
          # 'rafw007/gemma4-e4b-claude-coder',      # reference: https://www.youtube.com/watch?v=BaAy1DodIcQ (Ollama + Claude code for local AI) - not sure if this runs via opencode, trying now
          # 'deepseek-coder-v2',
          # 'gpt-oss:20b',
          # 'qwen3.5:9b-q8_0',   # Qwen 3.5 9B (Q8): strong reasoning model
          # 'mdq100/qwen3.5-coder:35b',
          # 'gemma3:12b'         # Gemma 3 12B: free coding model
          # 'codestral:22b',     # TODO: Need to research
        ]
        ollama_models.each do |model|
          if system('ollama', 'pull', model)
            Logging.success "Pulled model: '#{model}'"
          else
            Logging.record_warning "Failed to pull model: '#{model}'"
          end
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
    _restore_mtime_and_register_maintenance

    Logging.with_step('setup dev env', 'Setup dev environment'.yellow) do
      GitWorkspace.setup_dev_environment(first_install: EnvVars.first_install?)
    end

    Logging.with_step('regenerate repo aliases', 'Regenerate repo aliases'.yellow) do
      GitWorkspace.regenerate_repo_aliases
    end

    Logging.with_step('capture preferences', 'Capture app preferences'.yellow) do
      capture_prefs_script = Pathname.new(__dir__).join('capture-prefs.rb')
      if system(RbConfig.ruby, capture_prefs_script.to_s, '-e')
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
    success = SoftwareUpdatesCron.run(start_time: start_time)

    # Single exit point: exit non-zero if there were errors or warnings.
    # Combined with chronic in crontab, this means:
    # - Success: chronic suppresses all output (empty log), but writes timestamp to marker file
    # - Failure: chronic outputs everything (populated log)
    exit(success ? 0 : 1)
  end
end
