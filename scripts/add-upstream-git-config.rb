#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/add-upstream-git-config.rb
#
# Adds an 'upstream' remote to a forked git repository. For forked repos,
# constructs the upstream URL by substituting the cloned owner's username
# with the provided upstream owner. Supports SSH and HTTPS remote URL formats.
#
# Usage:
#   Standalone: add-upstream-git-config.rb -d <dir> -u <upstream-owner>
#   Module:     AddUpstreamGitConfig.run(dir: '/path/to/repo', upstream_owner: 'username')

require_relative 'utilities/command_utils'
require_relative 'utilities/git_processor'
require_relative 'utilities/logging'

# Adds an 'upstream' remote to a forked git repository.
# Returns true on success, false on error (errors are logged via Logging.record_error).
module AddUpstreamGitConfig
  extend self
  extend Core

  # Adds upstream remote to the specified repo directory.
  #
  # @param dir [String, Pathname] Target repo directory
  # @param upstream_owner [String] Upstream repo owner username
  # @return [Boolean] true if upstream was added or already exists, false on error
  # :reek:UtilityFunction -- Module method pattern for dual-mode script (see ruby-scripting.md)
  # :reek:FeatureEnvy -- GitProcessor block pattern is intentional (see ruby-scripting.md GitProcessor Usage Patterns)
  def run(dir:, upstream_owner:)
    target_dir = dir.to_s
    target_dir_colored = target_dir.cyan
    Logging.debug "#{'Adding new upstream to:'.yellow} '#{target_dir_colored}'"

    unless GitProcessor.repo?(target_dir)
      Logging.info "'#{target_dir_colored}' is not a git repo -- skipping."
      return true
    end

    GitProcessor.new(dir: target_dir) do |git|
      # Check if an 'upstream' remote already exists.
      existing_upstream = git.remote_url(name: 'upstream')
      if existing_upstream
        Logging.info "Remote 'upstream' already exists for '#{target_dir_colored}': '#{existing_upstream.cyan}' -- skipping."
        return true
      end

      # Construct the upstream URL by parsing origin and substituting the owner.
      upstream_url, cloned_owner = git.construct_upstream_url(upstream_owner: upstream_owner)
      return false unless upstream_url

      if cloned_owner == upstream_owner
        Logging.info "Origin owner ('#{cloned_owner.cyan}') and upstream owner are the same -- no change needed."
        return true
      end

      upstream_url_colored = upstream_url.cyan
      # Add the upstream remote.
      # Flay detects similarity between these two check_status blocks (add_remote and fetch_all).
      # This is intentional - each operation has its own specific error message context.
      # Extracting would lose clarity about which operation failed.
      stdout, stderr, status = git.add_remote('upstream', upstream_url)
      return false unless CommandUtils.check_status(stdout, stderr, status) do |st, output_msg|
        Logging.record_error("Failed to add upstream remote '#{upstream_url_colored}' (status: #{st.exitstatus})#{output_msg}")
      end

      # Fetch all remotes, unshallowing if needed.
      stdout, stderr, status = git.fetch_all
      return false unless CommandUtils.check_status(stdout, stderr, status) do |st, output_msg|
        Logging.record_error("Failed to fetch upstream remote '#{upstream_url_colored}' after adding it (status: #{st.exitstatus})#{output_msg}")
      end

      Logging.success "Successfully added and fetched upstream remote '#{upstream_url_colored}' to repo in '#{target_dir_colored}'"
      true
    end
  end
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

  Logging.run_script do
    success = AddUpstreamGitConfig.run(dir: options[:dir], upstream_owner: options[:upstream_owner])
    exit(success ? 0 : 1)
  end
end
