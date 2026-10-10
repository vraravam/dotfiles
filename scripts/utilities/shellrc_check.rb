#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'fileutils'
require 'open3'

require_relative 'core'
require_relative 'env_vars'
require_relative 'logging'

# Guards the vanilla-OS bootstrap against a stale ~/.shellrc. On a first install .shellrc is
# downloaded with curl from raw.githubusercontent.com, whose cache can lag behind the repository
# for several minutes; a stale copy then breaks every later step. Right after the repository is
# cloned (and before install-dotfiles.rb moves the downloaded file into it) the two copies must
# be identical.
#
# fresh-install-of-osx.sh runs this by invoking scripts/call-utility.rb directly rather than the
# call_utility shell function: the function lives in the very .shellrc that may be stale.
module ShellrcCheck
  extend self

  # .shellrc's location inside the dotfiles repo, relative to ${DOTFILES_DIR}.
  REPO_SHELLRC_RELATIVE = File.join('files', '--HOME--', '.shellrc').freeze

  DIFF_CMD = Core::ROOT.join('usr', 'bin', 'diff').to_s.freeze

  # How many lines of the diff are shown.
  DIFF_LINES = 50

  # Public API method.
  #
  # Nothing to check (returns true) on a pre-configured machine, where ~/.shellrc is already a
  # symlink to the repo copy, or when the repository has not been cloned.
  #
  # @return [Boolean] false, after explaining what to do, when the two copies differ.
  def matches_repo?
    return true unless EnvVars.first_install?
    return true unless EnvVars::DOTFILES_DIR.directory?

    downloaded = EnvVars::HOME.join('.shellrc')
    repo_copy = EnvVars::DOTFILES_DIR.join(REPO_SHELLRC_RELATIVE)
    # An unreadable or missing file counts as a mismatch.
    return true if downloaded.file? && repo_copy.file? && FileUtils.compare_file(downloaded.to_s, repo_copy.to_s)

    _explain(downloaded, repo_copy)
    false
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  # Prints with Kernel#warn, not Logging: this runs before anything else is set up and must
  # always be visible.
  #
  # @param downloaded [Pathname]
  # @param repo_copy [Pathname]
  # @return [void]
  def _explain(downloaded, repo_copy)
    diff, = Open3.capture3(DIFF_CMD, '-u', downloaded.to_s, repo_copy.to_s)
    Kernel.warn <<~MESSAGE
      ERROR: [FIRST_INSTALL] The curl-downloaded ~/.shellrc differs from the repo version.
      This indicates GitHub's raw.githubusercontent.com cache is stale.

      Diff output:
      #{diff.lines.first(DIFF_LINES).join}
      Wait 5-10 minutes for the cache to refresh, then re-run this script.
      Alternatively, manually copy the repo version:
        cp '#{repo_copy}' '#{downloaded}'
        source '#{downloaded}'
        fresh-install-of-osx.sh
    MESSAGE
  end

  private_class_method :_explain
end
