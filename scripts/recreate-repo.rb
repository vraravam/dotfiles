#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/recreate-repo.rb
#
# Recreates a git repo by optionally squashing all history into a single
# commit, then deleting and re-creating the remote Keybase repo and force-
# pushing. Useful for removing dangling/orphaned commits so fresh cloning
# is fast.
#
# Usage: recreate-repo.rb [-f] -d <repo-dir>

require_relative 'utilities/cli_parser'
require_relative 'utilities/cron'
require_relative 'utilities/env_vars'
require_relative 'utilities/git_processor'
require_relative 'utilities/keybase'
require_relative 'utilities/logging'
require_relative 'utilities/macos'

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
  opts.on('-d', '--dir DIR', 'Repo dir to process (mandatory)') { |v| options[:dir] = v }
  opts.on('-n', '--dry-run', 'Show what would be done without making changes') do
    options[:dry_run] = true
  end
  opts.separator ''
  opts.separator "  eg: #{File.basename(__FILE__).cyan} -f -d #{EnvVars::HOME}"
  opts.separator "  eg: #{File.basename(__FILE__).cyan} -d $PERSONAL_PROFILES_DIR"
  opts.separator "  eg: #{File.basename(__FILE__).cyan} -n -d ~/dev/my-repo  # dry-run"
end

parser.abort_with_usage('Missing required option: -d <dir>') if nil_or_empty?(options[:dir])

dir = options[:dir].chomp('/')
dir_pn = Pathname.new(dir)
force = options[:force]
dry_run = options[:dry_run]

increment_script_depth
start_time = print_script_start

info '🔍 DRY RUN MODE -- No changes will be made'.red if dry_run

# The profiles repo is always force-squashed.
profiles_repo_name = EnvVars::KEYBASE_PROFILES_REPO_NAME
force = true if profiles_repo_name && dir_pn.basename.to_s == profiles_repo_name

error "'#{dir.cyan}' is not a git repo. Please specify the root of a git repo." unless GitProcessor.repo?(dir)

section_header "#{'Processing dir:'.yellow} '#{dir.cyan}'"

# Create GitProcessor instance for this repo with dry_run mode.
# This single instance is reused throughout for all git operations.
git = GitProcessor.new(dir: dir_pn, dry_run: dry_run)

git_url = git.remote_url
user_name = git.config_value('user.name')
user_email = git.config_value('user.email')
branch = git.current_branch

info "#{'Squash commits (will lose history!):'.yellow} #{force.to_s.orange}"
info "#{'Dry run:'.yellow} #{dry_run.to_s.orange}"
info "#{'Repo url:'.yellow} '#{git_url.cyan}'"
info "#{'User name:'.yellow} '#{user_name.cyan}'"
info "#{'User email:'.yellow} '#{user_email.cyan}'"
info "#{'Branch:'.yellow} '#{branch.cyan}'"

error "One or more required git metadata values are missing for '#{dir.cyan}' -- see above" if [git_url, user_name, user_email, branch].any? { |v| nil_or_empty?(v) }

# Before destroying git history, ensure Keybase is reachable so we do not end
# up with a deleted local .git and no way to push.
exit 1 if Keybase.keybase_url?(git_url) && !Keybase.ensure_logged_in(dry_run: dry_run)

# Wrap the destructive operations in cron suspension so the cron job does not
# fire mid-operation. recron regenerates the crontab on the success path;
# resume_cron restores from the backup on any error path.
info 'Would suspend cron jobs' if dry_run

operation = lambda do
  if force
    if dry_run
      info "Would remove: '#{dir_pn.join('.git').to_s.cyan}'"
    else
      dir_pn.join('.git').rmtree
    end
    git.init
    git.add_remote('origin', git_url)
    git.config_set('user.name', user_name) unless nil_or_empty?(user_name)
    git.config_set('user.email', user_email) unless nil_or_empty?(user_email)
    git.delete_index_lock
    git.stage_all
    git.commit("Initial commit: #{MacOS.current_timestamp}", quiet: true)

    # Keybase repo recreation only happens when force-squashing commits, because
    # that's when we've destroyed local history. Without force, we're just
    # compressing and pushing existing commits - no remote recreation needed.
    if Keybase.keybase_url?(git_url)
      debug "#{'Recreating'.yellow} '#{git_url.cyan}'"
      Keybase.delete_repo(git.remote_repo_name, dry_run: dry_run)
      Keybase.create_repo(git.remote_repo_name, dry_run: dry_run)
    end
  end

  # Retry the commit in case it failed above, then compress.
  if dry_run
    info 'Would stage all files and amend commit'
  else
    git.delete_index_lock
    git.stage_all
    git.run_alias('amq')
  end

  if dry_run
    info 'Would compress (reflog + gc)'
  else
    debug "#{'Compressing'.yellow} '#{dir.cyan}'"
    git.run_alias('rfc')
    git.run_alias('cc')
  end

  git.push(remote: 'origin', branch: branch, force: true, progress: true)
end

if dry_run
  operation.call
  info 'Would resume cron jobs'
else
  Cron.with_cron_suspended(&operation)
end

print_script_summary(start_time)
