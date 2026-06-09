#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/recreate-repo.rb
#
# Recreates a git repo by optionally squashing all history into a single
# commit, then deleting and re-creating the remote Keybase repo and force-
# pushing. Useful for removing dangling/orphaned commits so fresh cloning
# is fast.
#
# Usage: recreate-repo.rb [-f] -d <repo-folder>

$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'cli_parser'
require 'cron'
require 'env_vars'
require 'git_helpers'
require 'keybase'
require 'logging'
require 'macos'

include Logging

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

options = { force: false, dry_run: false }
parser = CliParser.parse('<options>') do |opts|
  opts.separator 'Recreates a git repo, optionally squashing all history, and force-pushes to the remote.'
  opts.separator ''
  opts.separator 'Options:'.purple
  opts.on('-f', '--force', 'Squash all commits into one (profiles repo is always forced)') do
    options[:force] = true
  end
  opts.on('-d', '--dir DIR', 'Repo folder to process (mandatory)') { |v| options[:folder] = v }
  opts.on('-n', '--dry-run', 'Show what would be done without making changes') do
    options[:dry_run] = true
  end
  opts.separator ''
  opts.separator "  eg: #{File.basename(__FILE__).cyan} -f -d #{EnvVars::HOME}"
  opts.separator "  eg: #{File.basename(__FILE__).cyan} -d $PERSONAL_PROFILES_DIR"
  opts.separator "  eg: #{File.basename(__FILE__).cyan} -n -d ~/dev/my-repo  # dry-run"
end

if nil_or_empty?(options[:folder])
  parser.abort_with_usage('Missing required option: -d <folder>')
end

folder = options[:folder].chomp('/')
folder_pn = Pathname.new(folder)
force = options[:force]
dry_run = options[:dry_run]

increment_script_depth
start_time = print_script_start

if dry_run
  info '🔍 DRY RUN MODE -- No changes will be made'.red
end

# The profiles repo is always force-squashed.
profiles_repo_name = EnvVars::KEYBASE_PROFILES_REPO_NAME
force = true if profiles_repo_name && folder_pn.basename.to_s == profiles_repo_name

unless GitHelpers.git_repo?(folder)
  error "'#{folder}' is not a git repo. Please specify the root of a git repo. Aborting."
end

section_header "#{'Processing folder:'.yellow} '#{folder.cyan}'"

git_url = GitHelpers.remote_url(folder: folder)
user_name = GitHelpers.config_value('user.name', folder: folder)
user_email = GitHelpers.config_value('user.email', folder: folder)
branch = GitHelpers.current_branch(folder: folder)

info "#{'Squash commits (will lose history!):'.yellow} #{force.to_s.orange}"
info "#{'Dry run:'.yellow} #{dry_run.to_s.orange}"
info "#{'Repo url:'.yellow} '#{git_url.cyan}'"
info "#{'User name:'.yellow} '#{user_name.cyan}'"
info "#{'User email:'.yellow} '#{user_email.cyan}'"
info "#{'Branch:'.yellow} '#{branch.cyan}'"

if [git_url, user_name, user_email, branch].any? { |v| nil_or_empty?(v) }
  error "One or more required git metadata values are missing for '#{folder.cyan}' -- see above"
end

# Before destroying git history, ensure Keybase is reachable so we do not end
# up with a deleted local .git and no way to push.
if Keybase.keybase_url?(git_url)
  if dry_run
    info 'Would check: Keybase login status'
  else
    exit 1 unless Keybase.ensure_logged_in
  end
end

# Wrap the destructive operations in cron suspension so the cron job does not
# fire mid-operation. recron regenerates the crontab on the success path;
# resume_cron restores from the backup on any error path.
info 'Would suspend cron jobs' if dry_run

operation = lambda do
  if force
    require 'fileutils'
    if dry_run
      info "Would remove: '#{folder_pn.join('.git').to_s.cyan}'"
      info "Would run: git -C '#{folder.cyan}' init --ref-format=reftable ."
      info "Would run: git -C '#{folder.cyan}' remote add origin '#{git_url.cyan}'"
      info "Would run: git -C '#{folder.cyan}' config user.name '#{user_name}'" unless nil_or_empty?(user_name)
      info "Would run: git -C '#{folder.cyan}' config user.email '#{user_email}'" unless nil_or_empty?(user_email)
      info "Would delete: '#{folder_pn.join('.git', 'index.lock').to_s.cyan}' (if exists)"
      info "Would run: git -C '#{folder.cyan}' add -A ."
      info "Would run: git -C '#{folder.cyan}' commit -qm 'Initial commit: <timestamp>'"
    else
      FileUtils.rm_rf(folder_pn.join('.git'))
      system('git', '-C', folder, 'init', '--ref-format=reftable', '.')
      system('git', '-C', folder, 'remote', 'add', 'origin', git_url)
      system('git', '-C', folder, 'config', 'user.name', user_name) unless nil_or_empty?(user_name)
      system('git', '-C', folder, 'config', 'user.email', user_email) unless nil_or_empty?(user_email)
      folder_pn.join('.git', 'index.lock').delete rescue nil
      system('git', '-C', folder, 'add', '-A', '.')
      timestamp = MacOS.current_timestamp
      system('git', '-C', folder, 'commit', '-qm', "Initial commit: #{timestamp}")
    end

    # Keybase repo recreation only happens when force-squashing commits, because
    # that's when we've destroyed local history. Without force, we're just
    # compressing and pushing existing commits - no remote recreation needed.
    if Keybase.keybase_url?(git_url)
      debug "#{'Recreating'.yellow} '#{git_url.cyan}'"
      repo_name = git_url.sub(/\/\z/, '').split('/').last
      if dry_run
        info "Would delete keybase repo: '#{repo_name.yellow}'"
        info "Would create keybase repo: '#{repo_name.yellow}'"
      else
        Keybase.delete_repo(repo_name) ||
          record_warning("Failed to delete keybase repo '#{repo_name}' (it might not exist)")
        error "Failed to create keybase repo '#{repo_name}'" unless Keybase.create_repo(repo_name)
      end
    end
  end

  # Retry the commit in case it failed above, then compress.
  if dry_run
    debug 'Would stage all files and amend commit'
  else
    folder_pn.join('.git', 'index.lock').delete rescue nil
    system('git', '-C', folder, 'add', '-A', '.')
    system('git', '-C', folder, 'amq')
  end

  if dry_run
    debug 'Would compress (reflog + gc)'
  else
    debug "#{'Compressing'.yellow} '#{folder.cyan}'"
    system('git', '-C', folder, 'rfc')
    system('git', '-C', folder, 'cc')
  end

  if dry_run
    debug 'Would push to remote'
  else
    debug "#{'Pushing'.yellow} from '#{folder.cyan}' to '#{git_url.cyan}'"
    system('git', '-C', folder, 'push', '--progress', '-fu', 'origin', branch)
    folder_pn.join('.git', 'index.lock').delete rescue nil
    success "Git repo in '#{folder.cyan}' recreated and pushed to '#{git_url.cyan}'"
  end
end

if dry_run
  operation.call
  info 'Would resume cron jobs'
else
  Cron.with_cron_suspended(&operation)
end

print_script_summary(start_time)
