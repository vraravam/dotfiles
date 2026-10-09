#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# Reopened (not defined) here: GitProcessor itself requires this file before its own body,
# and only needs GitProcessor::URL_PATH_SEPARATOR, which is resolved at call time.
class GitProcessor
  # Parses and reconstructs git remote URLs with different owners.
  # Supports multiple formats:
  # - SCP-style SSH: git@host:owner/repo.git (most common)
  # - HTTPS: https://host/owner/repo.git
  # - git+ssh URL: git+ssh://git@host/owner/repo.git
  # - ssh:// URL: ssh://git@host/owner/repo.git
  class GitUrlParser
    attr_reader :host, :owner, :repo_path, :format, :protocol, :port

    # Parses a git remote URL.
    #
    # @param url [String] The git remote URL to parse
    # @raise [ArgumentError] If URL format is not recognized
    # :reek:DuplicateMethodCall -- Each case extracts different capture groups for different URL formats
    def initialize(url)
      case url
      when %r{\Agit@([^:]+):([^/]+)/(.+)\z}
        # SCP-style SSH URL format: git@host:owner/repo.git
        @format = :scp_ssh
        @host = Regexp.last_match(1)
        @owner = Regexp.last_match(2)
        @repo_path = _ensure_git_suffix(Regexp.last_match(3))
      when %r{\A(https?)://([^/]+)/([^/]+)/(.+)\z}
        # HTTPS URL format: https://host/owner/repo.git or http://host/owner/repo.git
        @format = :https
        @protocol = Regexp.last_match(1)
        @host = Regexp.last_match(2)
        @owner = Regexp.last_match(3)
        @repo_path = _ensure_git_suffix(Regexp.last_match(4))
        # Flay detects similarity between these two when clauses (git+ssh and ssh://).
        # This is intentional - both URL formats require the same field extraction pattern.
        # Extracting a helper would obscure the URL-format-to-field mapping.
      when %r{\Agit\+ssh://git@([^/:]+)(?::(\d+))?/([^/]+)/(.+)\z}
        # git+ssh URL format: git+ssh://git@host/owner/repo.git or git+ssh://git@host:port/owner/repo.git
        @format = :git_ssh
        @protocol = 'git+ssh'
        @host = Regexp.last_match(1)
        @port = Regexp.last_match(2)
        @owner = Regexp.last_match(3)
        @repo_path = _ensure_git_suffix(Regexp.last_match(4))
      when %r{\Assh://git@([^/:]+)(?::(\d+))?/([^/]+)/(.+)\z}
        # ssh:// URL format: ssh://git@host/owner/repo.git or ssh://git@host:port/owner/repo.git
        @format = :ssh_url
        @protocol = 'ssh'
        @host = Regexp.last_match(1)
        @port = Regexp.last_match(2)
        @owner = Regexp.last_match(3)
        @repo_path = _ensure_git_suffix(Regexp.last_match(4))
      else
        raise ArgumentError, "Cannot parse git URL format: '#{url}'"
      end
    end

    # Constructs a new URL with a different owner.
    #
    # @param new_owner [String] The new repository owner
    # @return [String] The reconstructed URL with .git suffix
    def with_owner(new_owner)
      sep = GitProcessor::URL_PATH_SEPARATOR
      case @format
      when :scp_ssh
        "git@#{@host}:#{new_owner}#{sep}#{@repo_path}"
      when :https
        "#{@protocol}:#{sep}#{sep}#{@host}#{sep}#{new_owner}#{sep}#{@repo_path}"
      when :git_ssh, :ssh_url
        port_part = @port ? ":#{@port}" : ''
        "#{@protocol}:#{sep}#{sep}git@#{@host}#{port_part}#{sep}#{new_owner}#{sep}#{@repo_path}"
      end
    end

    private

    # Ensures the repo path ends with .git suffix for consistency.
    # Matches the standard format used by GitHub, GitLab, Bitbucket, and Gitea.
    # Git accepts both forms, but .git is the official clone URL format.
    #
    # @param path [String] The repository path
    # @return [String] Path with .git suffix
    def _ensure_git_suffix(path)
      path.end_with?('.git') ? path : "#{path}.git"
    end
  end
end
