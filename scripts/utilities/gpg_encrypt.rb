#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require_relative 'core'

# Helpers for the 'gpg-encrypt::<url>' pseudo-URL scheme used by the external
# 'git-remote-gpg-encrypt' tool (installed via the 'vraravam/tap' Homebrew tap -- see
# files/--HOME--/Brewfile). Mirrors Keybase (scripts/utilities/keybase.rb) as the other
# backup-mechanism module -- see KeybaseMigration.md for how the two coexist.
#
# Unlike Keybase, there is no login/session state to manage here -- the tool itself
# (git-gpg-encrypt-setup/git-gpg-encrypt-restore) is invoked directly as a shell command
# (from fresh-install-of-osx.sh and the shell clone_repo_into function it delegates to),
# so this module currently owns only the URL scheme itself.
module GpgEncrypt
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # URL scheme prefix recognized by clone_repo_into (both GitProcessor.clone_repo_into
  # and the shell function it delegates to) as a special-case that delegates to
  # 'git gpg-encrypt-restore' instead of a plain 'git clone'.
  PROTOCOL = 'gpg-encrypt::'

  # Builds the 'gpg-encrypt::<url>' pseudo-URL for the given plain clone URL.
  #
  # @param plain_url [String] Plain clone URL of the underlying (encrypted) git repo.
  # @return [String]
  # :reek:UtilityFunction -- Stateless URL builder
  def url(plain_url)
    "#{PROTOCOL}#{plain_url}"
  end
end
