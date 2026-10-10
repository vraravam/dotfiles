#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/utilities/generate_bootstrap_repositories_yaml.rb
#
# Generates the YAML config consumed by 'resurrect-repositories.rb -r' to clone/update
# the home and browser-profiles repos during fresh-install-of-osx.sh's bootstrap flow.
# For each repo, the primary vs fallback remote is chosen programmatically from
# whichever KEYBASE_*_REPO_NAME/ENCRYPTED_*_REPO_URL env vars are configured -- Keybase
# takes precedence as the primary remote when both are set (historical precedence, see
# KeybaseMigration.md); the fallback is recorded under 'other_remotes', which
# resurrect-repositories.rb also tries as an alternate clone source if the primary fails.
# A repo with neither env var configured is omitted entirely (mirrors the "skip cloning
# ... since neither env var has been set" behavior this script replaces).
#
# Only fresh-install-of-osx.sh needs it, so it is a plain module, called there through
# call-utility.rb (there is no standalone CLI):
#   call_utility --truthy GenerateBootstrapRepositoriesYaml.run --output_file=<file>
# Ruby callers: GenerateBootstrapRepositoriesYaml.run(output_file: '...')

require 'yaml'

require_relative 'env_vars'
require_relative 'gpg_encrypt'
require_relative 'keybase'
require_relative 'logging'

# Generates the bootstrap repositories YAML config.
module GenerateBootstrapRepositoriesYaml
  extend self

  # Public API method.
  #
  # @param output_file [String, Pathname] Path to write the generated YAML config to.
  # @return [Boolean] true on success, false if neither repo has a backup mechanism
  #   configured (nothing to generate).
  def run(output_file:)
    ok = false
    Logging.run_script('generate_bootstrap_repositories_yaml', 'Generating the bootstrap repositories config') do
      ok = _write(output_file)
    end
    ok
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  # @param output_file [String, Pathname]
  # @return [Boolean]
  def _write(output_file)
    entries = [_home_entry, _profiles_entry].compact

    if entries.empty?
      Logging.record_error('No backup mechanism configured for the home or profiles repo -- nothing to generate.')
      return false
    end

    File.write(output_file.to_s, entries.to_yaml)
    Logging.success("Generated #{entries.length.to_s.purple} repo entries to '#{output_file.to_s.cyan}'")
    true
  end

  private_class_method :_write

  # Builds the home repo entry. 'post_checkout' resets ssh/gnupg permissions
  # immediately once files are checked out -- git checkout does not preserve the
  # strict modes either needs, and clone_repo_into's own reftable-migrate/unshallow/
  # maintain/siu chain (and, back in resurrect-repositories.rb, any second-remote
  # fetch) could need SSH auth using a key this checkout just wrote with the wrong
  # (too-open) permissions -- see clone_repo_into's own comment in .shellrc. 'post_clone'
  # (which runs later) patches /etc/hosts from the personal config backup if present,
  # and pulls latest changes into the working tree (unlike every other
  # resurrect-repositories.rb-managed repo, $HOME's checked-out files are used live by
  # the rest of this bootstrap run, so a fetch-only update is not enough). Branch
  # tracking itself needs no explicit step here -- clone_repo_into already guarantees
  # it unconditionally for every repo it touches (see its own comment).
  #
  # @return [Hash, nil]
  def _home_entry
    hosts_backup = EnvVars::PERSONAL_CONFIGS_DIR.join('etc.hosts')

    _backup_entry(
      folder: EnvVars::HOME,
      keybase_repo_name: EnvVars::KEYBASE_HOME_REPO_NAME,
      encrypted_repo_url: EnvVars::ENCRYPTED_HOME_REPO_URL,
      post_checkout: %w[
        set_ssh_folder_permissions
        set_gnupg_folder_permissions
      ],
      post_clone: [
        "if [ -f '#{hosts_backup}' ]; then sudo cp '#{hosts_backup}' /etc/hosts; fi",
        'git fo --rebase',
      ]
    )
  end

  private_class_method :_home_entry

  # Builds the browser-profiles repo entry. Unlike home, this repo is periodically
  # force-squashed by recreate-repository.rb, so it is deliberately not pulled here --
  # 'pull.allowResetOnDivergedHistory' instead lets the 'pull' autoload function handle
  # the resulting diverged history safely if/when the user pulls it manually.
  #
  # @return [Hash, nil]
  def _profiles_entry
    _backup_entry(
      folder: EnvVars::PERSONAL_PROFILES_DIR,
      keybase_repo_name: EnvVars::KEYBASE_PROFILES_REPO_NAME,
      encrypted_repo_url: EnvVars::ENCRYPTED_PROFILES_REPO_URL,
      post_clone: [
        'git config --local pull.allowResetOnDivergedHistory true',
      ]
    )
  end

  private_class_method :_profiles_entry

  # Builds a single repository entry hash matching resurrect-repositories.rb's YAML
  # schema. Returns nil if neither backup mechanism is configured for this repo.
  #
  # @param folder [Pathname] Target folder for this repo.
  # @param keybase_repo_name [String, nil] KEYBASE_*_REPO_NAME value, or nil if disabled.
  # @param encrypted_repo_url [String, nil] ENCRYPTED_*_REPO_URL value, or nil if disabled.
  # @param post_checkout [Array<String>] Optional post-checkout shell commands (run
  #   in-process inside clone_repo_into -- no 'source .shellrc &&' prefix needed, unlike
  #   post_clone below).
  # @param post_clone [Array<String>] Optional post-clone shell commands.
  # @return [Hash, nil]
  def _backup_entry(folder:, keybase_repo_name:, encrypted_repo_url:, post_checkout: [], post_clone: [])
    return nil unless keybase_repo_name || encrypted_repo_url

    if keybase_repo_name
      remote = Keybase.repo_url(keybase_repo_name)
      other_remotes = encrypted_repo_url ? { 'origin2' => GpgEncrypt.url(encrypted_repo_url) } : {}
    else
      remote = GpgEncrypt.url(encrypted_repo_url)
      other_remotes = {}
    end

    {
      'folder' => folder.to_s,
      'active' => true,
      'remote' => remote,
      'other_remotes' => other_remotes.empty? ? nil : other_remotes,
      'post_checkout' => post_checkout.empty? ? nil : post_checkout,
      'post_clone' => post_clone.empty? ? nil : post_clone
    }.compact
  end

  private_class_method :_backup_entry
end
