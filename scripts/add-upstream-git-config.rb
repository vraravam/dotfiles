#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/add-upstream-git-config.rb
#
# Adds an 'upstream' remote to a forked git repository. For forked repos,
# constructs the upstream URL by substituting the cloned owner's username
# with the provided upstream owner. Supports SSH and HTTPS remote URL formats.
#
# Usage: add-upstream-git-config.rb -d <dir> -u <upstream-owner>

$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'cli_parser'
require 'git_processor'
require 'logging'

include Logging

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

options = {}
parser = CliParser.parse('<options>') do |opts|
  opts.separator 'Adds an upstream remote to a forked git repo.'
  opts.separator ''
  opts.separator 'Options:'.purple
  opts.on('-d', '--dir DIR', 'Target repo dir (mandatory)') { |v| options[:dir] = v }
  opts.on('-u', '--upstream OWNER', 'Upstream repo owner (mandatory)') { |v| options[:upstream_owner] = v }
  opts.separator ''
  opts.separator "  eg: #{File.basename(__FILE__).cyan} -d ~/projects/my-fork -u original-author"
end

parser.abort_with_usage('Missing required options: -d <dir> and -u <upstream-owner>') if nil_or_empty?(options[:dir]) || nil_or_empty?(options[:upstream_owner])

target_dir = options[:dir]
upstream_owner = options[:upstream_owner]

increment_script_depth
start_time = print_script_start

debug "#{'Adding new upstream to:'.yellow} '#{target_dir.cyan}'"

unless GitProcessor.repo?(target_dir)
  info "'#{target_dir.cyan}' is not a git repo -- skipping."
  print_script_summary(start_time)
  exit 0
end

git = GitProcessor.new(dir: target_dir)

# Check if an 'upstream' remote already exists.
existing_upstream = git.remote_url(name: 'upstream')
if existing_upstream
  info "Remote 'upstream' already exists for '#{target_dir.cyan}': '#{existing_upstream.cyan}' -- skipping."
  print_script_summary(start_time)
  exit 0
end

# Get the origin URL and parse it to reconstruct the upstream URL.
origin_url = git.remote_url
unless origin_url
  record_error("Could not retrieve URL for remote 'origin' in '#{target_dir.cyan}'.")
  print_script_summary(start_time)
  exit 1
end

new_repo_url = nil
cloned_owner = nil

case origin_url
when /\Agit@([^:]+):([^\/]+)\/(.+)\z/
  # SSH format: git@host:owner/repo.git
  host = Regexp.last_match(1)
  cloned_owner = Regexp.last_match(2)
  repo_path = Regexp.last_match(3)
  new_repo_url = "git@#{host}:#{upstream_owner}/#{repo_path}"
when /\Ahttps?:\/\/([^\/]+)\/([^\/]+)\/(.+)\z/
  # HTTPS format: https://host/owner/repo.git
  protocol = origin_url.start_with?('https') ? 'https' : 'http'
  host = Regexp.last_match(1)
  cloned_owner = Regexp.last_match(2)
  repo_path = Regexp.last_match(3)
  new_repo_url = "#{protocol}://#{host}/#{upstream_owner}/#{repo_path}"
else
  record_error("Cannot parse origin remote URL format: '#{origin_url.cyan}'")
  print_script_summary(start_time)
  exit 1
end

# Ensure .git suffix for consistency.
new_repo_url += '.git' unless new_repo_url.end_with?('.git')

if cloned_owner == upstream_owner
  info "Origin owner ('#{cloned_owner.cyan}') and upstream owner are the same -- no change needed."
  print_script_summary(start_time)
  exit 0
end

# Add the upstream remote.
stdout, stderr, status = git.add_remote('upstream', new_repo_url)
unless status.success?
  record_error("Failed to add upstream remote '#{new_repo_url.cyan}'")
  debug "stderr: #{stderr}" unless nil_or_empty?(stderr)
  print_script_summary(start_time)
  exit 1
end

# Fetch all remotes, unshallowing if needed.
stdout, stderr, status = git.fetch_all(quiet: true)
unless status.success?
  record_error("Failed to fetch upstream remote '#{new_repo_url.cyan}' after adding it.")
  debug "stderr: #{stderr}" unless nil_or_empty?(stderr)
  print_script_summary(start_time)
  exit 1
end

success "Successfully added and fetched upstream remote '#{new_repo_url.cyan}' to repo in '#{target_dir.cyan}'"
print_script_summary(start_time)
