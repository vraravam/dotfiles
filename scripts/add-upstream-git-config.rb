#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: $DOTFILES_DIR/scripts/add-upstream-git-config.rb
#
# Adds an 'upstream' remote to a forked git repository. For forked repos,
# constructs the upstream URL by substituting the cloned owner's username
# with the provided upstream owner. Supports SSH and HTTPS remote URL formats.
#
# Usage:
#   Standalone: add-upstream-git-config.rb -d <dir> -u <upstream-owner>
#   Module:     AddUpstreamGitConfig.run(dir: '/path/to/repo', upstream_owner: 'username')

require_relative 'utilities/git_processor'
require_relative 'utilities/logging'

# Adds an 'upstream' remote to a forked git repository.
# Returns true on success, false on error (errors are logged via Logging.record_error).
module AddUpstreamGitConfig
  extend self

  # Adds upstream remote to the specified repo directory.
  #
  # @param dir [String, Pathname] Target repo directory
  # @param upstream_owner [String] Upstream repo owner username
  # @return [Boolean] true if upstream was added or already exists, false on error
  def run(dir:, upstream_owner:)
    target_dir = dir.to_s
    Logging.debug "#{'Adding new upstream to:'.yellow} '#{target_dir.cyan}'"

    unless GitProcessor.repo?(target_dir)
      Logging.info "'#{target_dir.cyan}' is not a git repo -- skipping."
      return true
    end

    git = GitProcessor.new(dir: target_dir)

    # Check if an 'upstream' remote already exists.
    existing_upstream = git.remote_url(name: 'upstream')
    if existing_upstream
      Logging.info "Remote 'upstream' already exists for '#{target_dir.cyan}': '#{existing_upstream.cyan}' -- skipping."
      return true
    end

    # Get the origin URL and parse it to reconstruct the upstream URL.
    origin_url = git.remote_url
    unless origin_url
      Logging.record_error("Could not retrieve URL for remote 'origin' in '#{target_dir.cyan}'.")
      return false
    end

    new_repo_url, cloned_owner = _construct_upstream_url(origin_url, upstream_owner, target_dir)
    return false unless new_repo_url

    if cloned_owner == upstream_owner
      Logging.info "Origin owner ('#{cloned_owner.cyan}') and upstream owner are the same -- no change needed."
      return true
    end

    # Add the upstream remote.
    _stdout, stderr, status = git.add_remote('upstream', new_repo_url)
    unless status.success?
      Logging.record_error("Failed to add upstream remote '#{new_repo_url.cyan}'")
      Logging.debug "stderr: #{stderr}" unless nil_or_empty?(stderr)
      return false
    end

    # Fetch all remotes, unshallowing if needed.
    _stdout, stderr, status = git.fetch_all(quiet: true)
    unless status.success?
      Logging.record_error("Failed to fetch upstream remote '#{new_repo_url.cyan}' after adding it.")
      Logging.debug "stderr: #{stderr}" unless nil_or_empty?(stderr)
      return false
    end

    Logging.success "Successfully added and fetched upstream remote '#{new_repo_url.cyan}' to repo in '#{target_dir.cyan}'"
    true
  end

  # Constructs the upstream URL by parsing origin and substituting the owner.
  #
  # @param origin_url [String] The origin remote URL
  # @param upstream_owner [String] The upstream owner username
  # @param target_dir [String] Target directory (for error messages)
  # @return [Array<String, String>, Array<nil, nil>] [upstream_url, cloned_owner] or [nil, nil] on parse error
  def _construct_upstream_url(origin_url, upstream_owner, target_dir)
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
      Logging.record_error("Cannot parse origin remote URL format: '#{origin_url.cyan}'")
      return [nil, nil]
    end

    # Ensure .git suffix for consistency.
    new_repo_url += '.git' unless new_repo_url.end_with?('.git')

    [new_repo_url, cloned_owner]
  end

  private_class_method :_construct_upstream_url
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

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

  Logging.run_script(File.basename(__FILE__, '.rb')) do
    success = AddUpstreamGitConfig.run(dir: options[:dir], upstream_owner: options[:upstream_owner])
    exit(success ? 0 : 1)
  end
end
