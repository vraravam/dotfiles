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

$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'antidote'
require 'env_vars'
require 'git_workspace'
require 'logging'
require 'macos'
require 'open3'
require 'path_utils'
require 'profiles_repo'
require 'rbconfig'
require 'shellwords'

include Logging

# ---------------------------------------------------------------------------
# Step helpers
# ---------------------------------------------------------------------------

# Returns true if run-all.rb is available in PATH (memoized).
# Cached to avoid repeated `command -v` lookups across multiple helper calls.
def _run_all_available?
  @_run_all_available ||= PathUtils.command_exists?('run-all.rb')
end

# Runs the block guarded by a check for +check_cmd+. Records a warning on
# failure rather than aborting so all steps run regardless of earlier failures.
def _perform_update(title, check_cmd, &block)
  unless PathUtils.command_exists?(check_cmd)
    debug "Command not found: '#{check_cmd}'"
    return
  end

  section_header "#{'Updating'.yellow} #{title.purple}"

  if block.call
    success "Successfully updated: '#{title}'"
  else
    record_warning("Failed to update '#{title}'")
  end
end

# ---------------------------------------------------------------------------
# Home / OSS repo update helpers
# ---------------------------------------------------------------------------

def _update_home_repos
  return unless _run_all_available?

  section_header 'Update repos in home folder'.yellow

  env = { 'FOLDER' => EnvVars::HOME.to_s, 'FILTER' => '.bin|zsh|mise', 'MAXDEPTH' => '5' }
  unless system(env, 'run-all.rb', 'git', 'pull-safe')
    record_warning('Some home repos could not be auto-updated -- working tree may be dirty. Rebase manually.')
  end
end

def _upreb_oss_repos
  return unless _run_all_available?

  section_header 'Upreb repos in oss folder'.yellow

  oss_folder = EnvVars::PROJECTS_BASE_DIR.join('oss')
  return unless oss_folder.directory?

  env = { 'FOLDER' => oss_folder.to_s, 'MAXDEPTH' => '4' }
  unless system(env, 'run-all.rb', 'git', 'upreb')
    record_warning('Some oss repos could not be auto-updated -- working tree may be dirty. Run upreb manually.')
  end
end

def _restore_mtime_and_register_maintenance
  return unless _run_all_available?

  section_header 'Restore mtime and register for maintenance'.yellow

  gitconfig = EnvVars::HOME.join('.gitconfig-oss.inc')
  env = { 'FOLDER' => EnvVars::HOME.to_s, 'MAXDEPTH' => '7' }

  system(env, 'run-all.rb', 'git restore-mtime -c')
  system(env, 'run-all.rb', "git maintenance register --config-file #{gitconfig.to_s}")
  system(env, 'run-all.rb', 'git maintenance start')
end

private :_run_all_available?, :_perform_update, :_update_home_repos, :_upreb_oss_repos, :_restore_mtime_and_register_maintenance

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

increment_script_depth
start_time = print_script_start

# Brew update: use bundle check before full bundle to avoid reinstalling
# already-installed formulae on every cron run.
_perform_update('brews', 'brew') do
  # Update brew itself first to get latest formula definitions
  system('brew', 'update') || true
  # 'brew bundle check' exits 0 when everything is installed -- skip the full
  # bundle install in that case to avoid re-checking every formula every hour.
  system('brew', 'bundle', 'check') || system('brew', 'bundle')
end
_perform_update('mise plugins', 'mise') do
  # mise binary is upgraded using homebrew
  system('mise', 'plugins', 'update') && system('mise', 'upgrade', '--bump')
end
_perform_update('tldr database', 'tldr') { system('tldr', '--update') }
_perform_update('git-ignore database', 'git-ignore-io') { system('git', 'ignore-io', '--update-list') }
_perform_update('claude-code', 'claude') { system('claude', 'update') }

# Antidote plugin update
section_header "#{'Updating'.yellow} #{'antidote plugins'.purple} and regenerating plugin bundle"
Antidote.update_and_regenerate_bundle

# bat cache update
if PathUtils.command_exists?('bat')
  section_header "#{'Updating'.yellow} #{'bat'.purple} cache"

  bat_config_dir, = Open3.capture3('bat', '--config-dir')
  bat_syntax_dir_pn = Pathname.new(bat_config_dir.strip).join('syntaxes')
  bat_syntax_dir_pn.mkpath

  system(
    'curl', '--retry', '3', '--retry-delay', '5', '-fsSL',
    'https://raw.githubusercontent.com/mattmc3/antidote/main/misc/zsh_plugins.sublime-syntax',
    '-o', bat_syntax_dir_pn.join('zsh_plugins.sublime-syntax').to_s
  )
  system('bat', 'cache', '--build')
end

# zen-browser-desktop tag cleanup
zen_desktop = EnvVars::PROJECTS_BASE_DIR.join('oss', 'zen-browser-desktop')
if GitProcessor.repo?(zen_desktop)
  section_header "#{"Remove 'twilight' tag from".yellow} #{'zen-browser-desktop'.purple} repo"
  GitProcessor.new(dir: zen_desktop) do |git|
    if git.tag_exists?('twilight')
      git.delete_tag('twilight')
      success("Deleted #{'twilight'.purple} tag.")
    end
  end
end

# TODO: Similar to ollama, need to update the models used by omlx via cli
if PathUtils.command_exists?('ollama')
  section_header 'Pull ollama models'.yellow
  # reference: https://insiderllm.com/guides/ollama-mac-setup-optimization/
  # reference: https://popularaitools.ai/blog/run-gemma-4-locally-opencode-2026
  # Note: This list is up-to-date as of 2026-06-06
  ollama_models = [
    # 'deepseek-coder-v2',
    # 'gpt-oss:20b',
    # 'qwen3.5:9b-q8_0', # Qwen 3.5 9B (Q8): strong reasoning model
    'qwen2.5-coder:14b', # Qwen 2.5 Coder 14B: strong coding model
    'gemma3:12b'        # Gemma 3 12B: free coding model
  # 'gemma4:26b',        # Gemma 4 26B: free coding model
  # 'codestral:22b',     # TODO: Need to research
  ]
  ollama_models.each do |model|
    if system('ollama', 'pull', model)
      success "Pulled model: '#{model}'"
    else
      record_warning "Failed to pull model: '#{model}'"
    end
  end
else
  debug 'ollama not found -- skipping model pulls'
end

success 'Finished independent updates.'

# Repo updates
if _run_all_available?
  _update_home_repos
  sleep 10  # Avoid GitHub rate-limiting between bursts of API calls.
  _upreb_oss_repos
  _restore_mtime_and_register_maintenance
end

section_header 'Setup dev environment'.yellow
GitWorkspace.setup_dev_environment(first_install: EnvVars.first_install?)

section_header 'Regenerate repo aliases'.yellow
GitWorkspace.regenerate_repo_aliases

section_header 'Capture app preferences'.yellow
capture_prefs_script = Pathname.new(__dir__).join('capture-prefs.rb')
if system(RbConfig.ruby, capture_prefs_script.to_s, '-e')
  success 'Finished capturing app preferences'
else
  record_error('Failed to capture app preferences')
end

section_header 'Prune old timestamped session backups from browser-profiles repo'.yellow
ProfilesRepo.prune_old_session_backups

section_header 'Check profiles repo size'.yellow
ProfilesRepo.check_size_limit

section_header 'Update home and profiles repos'.yellow
if !GitWorkspace.update_all_repos
  record_error('Failed to update home and profiles repos')
end

section_header 'Report status of all repos'.yellow
GitWorkspace.status_all_repos

section_header 'Updating all browser profile chrome folders if they are git repos'.yellow
ProfilesRepo.update_chrome_folders

section_header 'Checking if any greedy applications are outdated'.yellow
outdated_flat = MacOS.check_and_notify_outdated_apps

# ---------------------------------------------------------------------------
# Final summary and notification
# ---------------------------------------------------------------------------

now = MacOS.current_timestamp
duration = format_duration(Time.now.to_i - start_time)

success "Finished software updates at #{now.purple} in #{duration.light_blue}"

print_script_summary(start_time)

# Build a single grouped macOS notification.
notification_parts = []

# Access logging module's private step tracking variables
step_errors = Logging.instance_variable_get(:@step_errors) || []
step_warnings = Logging.instance_variable_get(:@step_warnings) || []

unless step_errors.empty?
  notification_parts << "#{step_errors.length} error(s): #{step_errors.join('; ')}"
end
unless step_warnings.empty?
  notification_parts << "#{step_warnings.length} warning(s): #{step_warnings.join('; ')}"
end

title_icon = (step_errors.empty? && step_warnings.empty?) ? '✅' : '⚠️'
msg = notification_parts.empty? ? '.' : " -- #{notification_parts.join(' | ')}"

if !outdated_flat.empty?
  title_icon = '⚠️'
  msg += ". Needs manual update: #{outdated_flat}"
end

MacOS.notify("Done at #{now} (took #{duration})#{msg}", "#{title_icon} Software Updates")

# Write success marker file for audit trail when run completes without errors/warnings
if step_errors.empty? && step_warnings.empty?
  success_marker = EnvVars::HOME.join('.software-updates-last-success')
  # Append to file (creates if doesn't exist), each run on a new line
  success_marker.write("#{now} (took #{duration})\n", mode: 'a')
end

# Single exit point: exit non-zero if there were errors or warnings.
# Combined with chronic in crontab, this means:
# - Success: chronic suppresses all output (empty log), but writes timestamp to marker file
# - Failure: chronic outputs everything (populated log)
exit(1) if step_errors.any? || step_warnings.any?
