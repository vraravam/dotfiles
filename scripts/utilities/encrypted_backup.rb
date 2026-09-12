#!/usr/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

# file location: ${DOTFILES_DIR}/scripts/utilities/encrypted_backup.rb
#
# Encrypted backup of a git repo's full history via 'git bundle' + 'gpg --symmetric',
# pushed as a single opaque blob to a plain public git remote (GitHub). Replaces
# git-remote-gcrypt -- see TechnicalDeepDive.md section 14 for the full rationale.
# This approach is genuinely password-based (no GPG keypair to back up separately),
# fully scriptable, and hides file names/tree structure inside the encrypted bundle
# (unlike git-crypt, which only encrypts blob contents).
#
# The encrypted blob is split into CHUNK_SIZE_BYTES-sized chunks (backup.gpg.000,
# backup.gpg.001, ...) before committing, reassembled before decrypting. This is not
# optional: GitHub hard-rejects any single pushed file over 100MB, and a full-history
# bundle of a real $HOME (scanned documents, PDFs, etc.) routinely exceeds that by
# several times over. Splitting is the only way to stay on a free, git-native, plain
# GitHub repo -- Git LFS was considered and rejected: its free tier (1GB storage + 1GB
# bandwidth/month, shared) would be exhausted in a push or two, since encrypted content
# never delta-compresses (every push is a wholly new blob, never an incremental diff).
#
# The passphrase is stored in the macOS Keychain, never inside either repo -- storing
# it in-repo would reintroduce the same chicken-and-egg problem git-remote-gcrypt had
# with GPG keypairs (you can't decrypt the thing that contains the only copy of the key
# needed to decrypt it).
#
# One-time-per-machine manual setup required before first use (does NOT sync via iCloud
# Keychain -- see KEYBASE_MIGRATION.md -- so this must be repeated on every new machine):
#   security add-generic-password -A -a "$USER" -s 'dotfiles-encrypted-backup' -w
#   (paste the passphrase from your password manager when prompted)
# scripts/setup-encrypted-backup.rb automates this interactively when possible.
#
# Method usage frequency, for anyone extending this module:
#   - export_and_push / clone_and_decrypt: ROUTINE -- called on every push (via the
#     push-<basename>.sh override scripts) and every fresh-install, respectively.
#   - prompt_and_store_passphrase: silently returns true if already configured (used as the
#     internal guard at the top of every method above), otherwise performs the
#     one-time-per-machine setup action described above. Called directly by
#     scripts/setup-encrypted-backup.rb as its main entry point.
#   - verify_current_blob_decryptable?: occasional/as-needed maintenance (not one-time, not
#     routine) -- called automatically by recreate-repository.rb's force mode whenever the
#     target directory is a wrapper repo (see that script's header comment).
#
# Why this logic lives here and NOT inside the shell 'clone_repo_into' function
# (files/--HOME--/.shellrc), even though clone_and_decrypt's final step calls that exact
# function (via GitProcessor.clone_repo_into) to do the actual bundle import:
#   1. Single responsibility: clone_repo_into is a generic "get git objects from source X
#      into directory Y" primitive reused by many unrelated callers (the dotfiles repo
#      clone itself, resurrect-repositories.rb's own unrelated plain-bundle-import feature
#      for large/flaky repos, etc.). Baking gpg/Keychain-specific logic into it would add a
#      narrow, security-sensitive concern to a function every other caller has nothing to
#      do with, and would need extra flags to distinguish "this bundle is encrypted" from
#      the plain bundle-import case resurrect-repositories.rb already uses.
#   2. Layer/language boundary: clone_repo_into is a shell function, deliberately kept
#      simple enough to run during vanilla-OS bootstrap before any Ruby gems are set up (it
#      clones the dotfiles repo itself, before Ruby utilities even exist on disk). Keychain
#      lookups, layered decrypt+'git bundle verify' checks, and structured error handling
#      are exactly the kind of logic this codebase's conventions push toward Ruby for (see
#      ruby-scripting.md) -- reimplementing that in shell would fight the language instead
#      of using it appropriately.
#   3. Composition over special-casing: EncryptedBackup treats clone_repo_into purely as a
#      building block (calling it twice -- once to fetch the wrapper repo over the network,
#      once to import the decrypted bundle) rather than reaching into or forking it. This
#      keeps clone_repo_into's bundle-import capability generic and reusable for both the
#      encrypted and plain (resurrect-repositories.rb) use cases, and keeps the
#      security-sensitive decrypt/passphrase code isolated in one small, auditable module
#      instead of buried inside an already-large, multi-purpose shell function.
#
# Usage:
#   Module: EncryptedBackup.export_and_push(repo_dir: EnvVars::HOME, encrypted_repo_name: EnvVars::ENCRYPTED_HOME_REPO_NAME)
#           EncryptedBackup.clone_and_decrypt(encrypted_repo_name: EnvVars::ENCRYPTED_HOME_REPO_NAME, target_dir: EnvVars::HOME)

require 'open3'
require 'pathname'
require 'tmpdir'

require_relative 'command_utils'
require_relative 'core'
require_relative 'env_vars'
require_relative 'git_processor'
require_relative 'logging'

module EncryptedBackup
  extend self
  include Core # For instance methods (in blocks)
  extend Core  # For module methods

  KEYCHAIN_SERVICE = 'dotfiles-encrypted-backup'
  BLOB_FILENAME = 'backup.gpg'
  # GitHub's hard per-file push limit is 100MB. Leaves a comfortable margin below that
  # (rather than cutting it as close as possible) to tolerate any filesystem/encoding
  # overhead, since going even one byte over 100MB fails the push outright.
  CHUNK_SIZE_BYTES = 90 * 1024 * 1024

  # ---------------------------------------------------------------------------
  # Query methods (read-only state inspection)
  # ---------------------------------------------------------------------------

  # Reads the backup passphrase from the macOS Keychain. Memoized -- the keychain
  # entry does not change during a single script execution.
  #
  # @return [String, nil] the passphrase, or nil if not found
  def passphrase
    return @_passphrase if defined?(@_passphrase)

    value = CommandUtils.query('security', 'find-generic-password', '-a', EnvVars::USER, '-s', KEYCHAIN_SERVICE, '-w')
    @_passphrase = nil_or_empty?(value) ? nil : value
  end

  # @return [Boolean] true if a passphrase is configured in the Keychain
  def passphrase_configured?
    !nil_or_empty?(passphrase)
  end

  # Returns the local wrapper-repo directory for encrypted_repo_name (the local clone
  # holding just the single encrypted blob -- see BLOB_FILENAME). Public so that
  # recreate-repository.rb's auto-detection of wrapper-repo directories (see that script's
  # header comment) can recognize this same path convention without duplicating it.
  #
  # @param encrypted_repo_name [String]
  # @return [Pathname]
  def wrapper_repo_dir(encrypted_repo_name)
    EnvVars::XDG_CACHE_HOME.join('encrypted-backups', encrypted_repo_name)
  end

  # Verifies the currently-pushed blob for encrypted_repo_name can still be decrypted
  # with the current Keychain passphrase, AND that what comes out is an intact git bundle
  # (not just "gpg didn't error"). Called automatically by recreate-repository.rb's force
  # mode whenever the target directory is a wrapper repo (see that script's header comment)
  # as a pre-check before squashing the wrapper repo's own history: that operation
  # force-pushes over the wrapper repo's history, so if the current blob is corrupted or
  # stale, squashing would destroy the only remaining copy of the last known-good backup
  # with no way back.
  #
  # Two layers deliberately: a wrong/rotated passphrase and a corrupted-but-still-decrypts
  # bundle are different failure modes -- 'git bundle verify' catches the second case that
  # gpg's own exit status alone would miss.
  #
  # @param encrypted_repo_name [String]
  # @return [Boolean] true if the current blob decrypts and verifies successfully
  def verify_current_blob_decryptable?(encrypted_repo_name:)
    return false unless prompt_and_store_passphrase

    wrapper_dir = wrapper_repo_dir(encrypted_repo_name)

    Dir.mktmpdir('encrypted-backup-verify-') do |tmp_dir|
      tmp_dir_pn = Pathname.new(tmp_dir)
      encrypted_file = tmp_dir_pn.join(BLOB_FILENAME)
      bundle_file = tmp_dir_pn.join('repo.bundle')

      unless _join_chunks(wrapper_dir, encrypted_file)
        Logging.record_error "No '#{BLOB_FILENAME}.*' chunks found in '#{wrapper_dir.cyan}' -- nothing to verify"
        return false
      end

      unless _decrypt(encrypted_file, bundle_file)
        Logging.record_error "Current '#{encrypted_file.cyan}' failed to decrypt with the configured " \
                             'passphrase -- refusing to proceed (would risk losing the last known-good backup)'
        return false
      end

      _stdout, stderr, status = Open3.capture3('git', 'bundle', 'verify', bundle_file.to_s)
      unless status.success?
        Logging.record_error "Decrypted bundle for '#{encrypted_repo_name}' failed 'git bundle verify' -- " \
                             "the backup may be corrupted. Stderr: #{stderr}"
        return false
      end
    end

    Logging.success "Current encrypted backup for '#{encrypted_repo_name}' verified decryptable and valid"
    true
  end

  # ---------------------------------------------------------------------------
  # Mutation methods (modify state)
  # ---------------------------------------------------------------------------

  # Ensures a passphrase is available, prompting interactively if possible. Returns true
  # immediately (silently) if already configured -- this doubles as the internal guard used
  # by export_and_push/clone_and_decrypt/verify_current_blob_decryptable?, in addition to
  # being scripts/setup-encrypted-backup.rb's main entry point, so both the routine call
  # sites and the dedicated setup script share identical "prompt if possible" behavior.
  #
  # When not already configured, interactively prompts (via 'security add-generic-password's
  # own masked, double-entry confirmation prompt) to store a new passphrase in the Keychain.
  # Deliberately does NOT capture the passphrase in Ruby first and pass it via '-w <value>'
  # -- that would expose it in this process's argv (visible to other processes via 'ps' for
  # the call's duration). Letting 'security' prompt directly means the passphrase never
  # touches Ruby process memory or command-line arguments at all.
  #
  # Only attempts the prompt when running in a TTY -- there is no way to prompt in a
  # non-interactive context (cron, etc.), so this logs setup instructions and returns false
  # there instead.
  #
  # @return [Boolean] true if a passphrase is already configured or was successfully stored
  def prompt_and_store_passphrase
    if passphrase_configured?
      Logging.debug "Encrypted-backup passphrase already configured for service '#{KEYCHAIN_SERVICE}'"
      return true
    end

    unless running_in_tty?
      Logging.user_action 'No encrypted-backup passphrase found in the macOS Keychain.'
      Logging.user_action 'Generate/choose a strong passphrase and store it in your password manager, then run:'
      Logging.user_action "  security add-generic-password -A -a \"#{EnvVars::USER}\" -s '#{KEYCHAIN_SERVICE}' -w"
      Logging.user_action '(-A allows any application to read it without a GUI prompt, required for non-interactive cron/fresh-install use)'
      Logging.record_error "No passphrase found in Keychain for service '#{KEYCHAIN_SERVICE}' -- see instructions above"
      return false
    end

    Logging.info 'No encrypted-backup passphrase found in the macOS Keychain.'
    Logging.info 'You will be prompted to enter (and confirm) one now -- store it in your password manager too.'

    unless system('security', 'add-generic-password', '-A', '-a', EnvVars::USER, '-s', KEYCHAIN_SERVICE, '-w')
      Logging.record_error 'Failed to store passphrase in Keychain (mismatch, empty input, or cancelled)'
      return false
    end

    # Invalidate the memoized lookup (may have cached 'not found' from an earlier check
    # this same run) so the next passphrase call re-reads the newly stored value.
    remove_instance_variable(:@_passphrase) if defined?(@_passphrase)

    Logging.success 'Passphrase stored in Keychain'
    true
  end

  # Bundles the full history of repo_dir, encrypts it with the Keychain passphrase, and
  # pushes the resulting single-file blob to the local wrapper clone of encrypted_repo_name's
  # plain public GitHub remote.
  #
  # @param repo_dir [Pathname] Path to the live, unencrypted local repo (e.g. EnvVars::HOME).
  # @param encrypted_repo_name [String] Name of the plain GitHub repo holding the blob.
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [Boolean] true on success or dry_run, false on failure
  def export_and_push(repo_dir:, encrypted_repo_name:, dry_run: false)
    return false unless prompt_and_store_passphrase

    unless GitProcessor.repo?(repo_dir)
      Logging.record_error "'#{repo_dir.cyan}' is not a git repo -- cannot export"
      return false
    end

    if dry_run
      Logging.info "Would bundle+encrypt '#{repo_dir.cyan}' and push to '#{encrypted_repo_name.cyan}'"
      return true
    end

    Dir.mktmpdir('encrypted-backup-') do |tmp_dir|
      tmp_dir_pn = Pathname.new(tmp_dir)
      bundle_file = tmp_dir_pn.join('repo.bundle')
      encrypted_file = tmp_dir_pn.join(BLOB_FILENAME)

      unless GitProcessor.new(dir: repo_dir).bundle_create(file: bundle_file)
        Logging.record_error "Failed to create git bundle for '#{repo_dir.cyan}'"
        return false
      end

      unless _encrypt(bundle_file, encrypted_file)
        Logging.record_error "Failed to encrypt bundle for '#{repo_dir.cyan}'"
        return false
      end

      wrapper_dir = wrapper_repo_dir(encrypted_repo_name)
      return false unless _ensure_wrapper_repo(wrapper_dir, encrypted_repo_name)

      unless _split_into_chunks(encrypted_file, wrapper_dir)
        Logging.record_error "Failed to split encrypted blob into <100MB chunks for '#{repo_dir.cyan}'"
        return false
      end

      return false unless _commit_and_push_wrapper(wrapper_dir)
    end

    Logging.success "Encrypted backup of '#{repo_dir.cyan}' pushed to '#{encrypted_repo_name.cyan}'"
    true
  end

  # Clones encrypted_repo_name's plain GitHub remote, decrypts its blob with the Keychain
  # passphrase, and imports the resulting bundle into target_dir (full git history restored)
  # via GitProcessor.clone_repo_into.
  #
  # @param encrypted_repo_name [String]
  # @param target_dir [Pathname]
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [Boolean] true on success or dry_run, false on failure
  def clone_and_decrypt(encrypted_repo_name:, target_dir:, dry_run: false)
    return false unless prompt_and_store_passphrase

    if dry_run
      Logging.info "Would clone '#{encrypted_repo_name.cyan}', decrypt, and import into '#{target_dir.cyan}'"
      return true
    end

    wrapper_dir = wrapper_repo_dir(encrypted_repo_name)
    return false unless _ensure_wrapper_repo(wrapper_dir, encrypted_repo_name, pull_latest: true)

    Dir.mktmpdir('encrypted-backup-') do |tmp_dir|
      tmp_dir_pn = Pathname.new(tmp_dir)
      encrypted_file = tmp_dir_pn.join(BLOB_FILENAME)
      bundle_file = tmp_dir_pn.join('repo.bundle')

      unless _join_chunks(wrapper_dir, encrypted_file)
        Logging.record_error "No '#{BLOB_FILENAME}.*' chunks found in '#{wrapper_dir.cyan}' -- has an encrypted backup ever been pushed for '#{encrypted_repo_name}'?"
        return false
      end

      unless _decrypt(encrypted_file, bundle_file)
        Logging.record_error "Failed to decrypt '#{encrypted_file.cyan}' -- check the Keychain passphrase is correct"
        return false
      end

      return GitProcessor.clone_repo_into('', target_dir, bundle: bundle_file)
    end
  end

  # Fetches the latest encrypted backup for encrypted_repo_name and rebases repo_dir's
  # current branch onto the corresponding branch from that backup. This is the
  # already-exists-as-a-repo counterpart to clone_and_decrypt (which only handles a
  # fresh/non-existent target) -- it covers the sequential "commit+push on machine1,
  # pull+rebase+continue-working on machine2" workflow that Keybase supported
  # transparently (its encrypted repo was the live remote itself). Here, repo_dir has
  # no real remote to fetch from, so the decrypted bundle is added as a *temporary*
  # git remote purely so 'git fetch'/'git rebase' behave exactly like a normal
  # remote-tracking pull -- the temporary remote is always removed again afterward,
  # regardless of success or failure, since it points at a temp file that is deleted
  # when this method returns.
  #
  # @param encrypted_repo_name [String]
  # @param repo_dir [Pathname] The already-existing live repo to rebase (e.g. EnvVars::HOME).
  # @param allow_reset_on_diverged_history [Boolean] When true, falls back to a hard reset
  #   instead of a rebase if repo_dir's history and the backup's history share no common
  #   ancestor (e.g. a squash-prone repo like browser-profiles, periodically force-squashed
  #   by recreate-repository.rb -- after a squash there is no meaningful base to rebase onto,
  #   only a full resync). Defaults to false: for a repo that is never squashed (e.g. HOME),
  #   diverged history is unexpected and should fail loudly rather than silently discard
  #   local commits.
  # @param dry_run [Boolean] When true, logs the operation instead of executing.
  # @return [Boolean] true on success or dry_run, false on failure
  def fetch_and_rebase(encrypted_repo_name:, repo_dir:, allow_reset_on_diverged_history: false, dry_run: false)
    return false unless prompt_and_store_passphrase

    unless GitProcessor.repo?(repo_dir)
      Logging.record_error "'#{repo_dir.cyan}' is not a git repo -- cannot fetch/rebase"
      return false
    end

    git = GitProcessor.new(dir: repo_dir, dry_run: dry_run)
    _stdout, _stderr, clean_status = git.run_alias('is-clean', read_only: true)
    unless clean_status.success?
      Logging.record_error "'#{repo_dir.cyan}' has uncommitted changes -- commit or stash before pulling"
      return false
    end

    if dry_run
      Logging.info "Would fetch latest encrypted backup for '#{encrypted_repo_name.cyan}' and rebase '#{repo_dir.cyan}' onto it"
      return true
    end

    wrapper_dir = wrapper_repo_dir(encrypted_repo_name)
    return false unless _ensure_wrapper_repo(wrapper_dir, encrypted_repo_name, pull_latest: true)

    Dir.mktmpdir('encrypted-backup-') do |tmp_dir|
      tmp_dir_pn = Pathname.new(tmp_dir)
      encrypted_file = tmp_dir_pn.join(BLOB_FILENAME)
      bundle_file = tmp_dir_pn.join('repo.bundle')

      unless _join_chunks(wrapper_dir, encrypted_file)
        Logging.record_error "No '#{BLOB_FILENAME}.*' chunks found in '#{wrapper_dir.cyan}' -- has an encrypted backup ever been pushed for '#{encrypted_repo_name}'?"
        return false
      end

      unless _decrypt(encrypted_file, bundle_file)
        Logging.record_error "Failed to decrypt '#{encrypted_file.cyan}' -- check the Keychain passphrase is correct"
        return false
      end

      return _rebase_onto_bundle(git, bundle_file, allow_reset_on_diverged_history: allow_reset_on_diverged_history)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Adds bundle_file as a temporary remote in git's repo, fetches it, then either rebases
  # or hard-resets the current branch onto the fetched branch depending on
  # allow_reset_on_diverged_history and whether the two histories share a common ancestor.
  # The temporary remote is always removed afterward regardless of outcome -- it must
  # never be left configured, since it points at a temp file that is deleted as soon as
  # the caller's Dir.mktmpdir block exits.
  #
  # @param git [GitProcessor] Already constructed for the live repo being synced.
  # @param bundle_file [Pathname] Decrypted bundle to fetch from.
  # @param allow_reset_on_diverged_history [Boolean] See fetch_and_rebase's doc.
  # @return [Boolean] true if fetch and rebase/reset both succeeded
  def _rebase_onto_bundle(git, bundle_file, allow_reset_on_diverged_history: false)
    remote_name = 'encrypted-backup-sync'
    branch = git.current_branch
    if nil_or_empty?(branch)
      Logging.record_error "Could not determine current branch in '#{git.dir.cyan}'"
      return false
    end

    _stdout, stderr, add_status = git.add_remote(remote_name, bundle_file.to_s)
    unless add_status.success?
      Logging.record_error "Failed to add temporary remote for encrypted backup: #{stderr}"
      return false
    end

    begin
      _stdout, stderr, fetch_status = git.fetch(remote_name)
      unless fetch_status.success?
        Logging.record_error "Failed to fetch from encrypted backup: #{stderr}"
        return false
      end

      backup_ref = "#{remote_name}/#{branch}"

      unless git.common_ancestor?(branch, backup_ref)
        unless allow_reset_on_diverged_history
          Logging.record_error "'#{branch}' and the encrypted backup have no common ancestor (unexpected -- " \
                               'was history rewritten on one side?) -- refusing to rebase blindly'
          return false
        end

        Logging.warn "'#{branch}' and the encrypted backup have no common ancestor (expected after a " \
                     "force-squash) -- resetting '#{branch}' to the backup instead of rebasing"
        _stdout, stderr, reset_status = git.reset_hard(backup_ref)
        unless reset_status.success?
          Logging.record_error "Failed to reset '#{branch}' to the encrypted backup: #{stderr}"
          return false
        end

        Logging.success "Reset '#{branch}' to the latest encrypted backup for '#{git.dir.cyan}'"
        return true
      end

      _stdout, stderr, rebase_status = git.rebase(backup_ref)
      unless rebase_status.success?
        Logging.record_error "Failed to rebase '#{branch}' onto the encrypted backup -- resolve manually " \
                             "(git rebase --abort to cancel): #{stderr}"
        return false
      end

      Logging.success "Rebased '#{branch}' onto the latest encrypted backup for '#{git.dir.cyan}'"
      true
    ensure
      git.remove_remote(remote_name)
    end
  end

  # Ensures a local clone of encrypted_repo_name's plain GitHub remote exists at wrapper_dir,
  # cloning it if missing. When pull_latest is true and the clone already exists, pulls the
  # latest blob first (tolerates failure -- e.g. nothing pushed yet on a brand new repo).
  def _ensure_wrapper_repo(wrapper_dir, encrypted_repo_name, pull_latest: false)
    remote_url = "https://github.com/#{EnvVars::GH_USERNAME}/#{encrypted_repo_name}.git"

    if GitProcessor.repo?(wrapper_dir)
      GitProcessor.new(dir: wrapper_dir).pull if pull_latest
      return true
    end

    unless GitProcessor.clone_repo_into(remote_url, wrapper_dir)
      Logging.record_error "Failed to clone '#{remote_url}' -- has the GitHub repo '#{encrypted_repo_name}' " \
                           'been created yet? Create it (public, empty) at https://github.com/new before running this.'
      return false
    end
    true
  end

  def _commit_and_push_wrapper(wrapper_dir)
    git = GitProcessor.new(dir: wrapper_dir)
    git.add('.')
    unless git.smart_commit
      Logging.record_error "Failed to commit encrypted blob in '#{wrapper_dir.cyan}'"
      return false
    end

    _stdout, stderr, status = git.push(branch: git.current_branch)
    unless status.success?
      Logging.record_error "Failed to push encrypted blob from '#{wrapper_dir.cyan}': #{stderr}"
      return false
    end
    true
  end

  def _encrypt(input_file, output_file)
    _stdout, _stderr, status = Open3.capture3(
      'gpg', '--batch', '--yes', '--passphrase-fd', '0', '--symmetric',
      '--output', output_file.to_s, input_file.to_s,
      stdin_data: passphrase
    )
    status.success?
  end

  def _decrypt(input_file, output_file)
    _stdout, _stderr, status = Open3.capture3(
      'gpg', '--batch', '--yes', '--passphrase-fd', '0', '--decrypt',
      '--output', output_file.to_s, input_file.to_s,
      stdin_data: passphrase
    )
    status.success?
  end

  # Splits input_file into CHUNK_SIZE_BYTES-sized chunks inside output_dir, named
  # "#{BLOB_FILENAME}.000", "#{BLOB_FILENAME}.001", etc. (numeric, zero-padded to 3
  # digits -- supports up to 1000 chunks, far more than any realistic backup needs).
  # Removes any pre-existing chunks in output_dir first: a previous, larger encrypted
  # file may have produced more chunks than this run needs, and a stale extra chunk
  # would otherwise linger and corrupt the next _join_chunks.
  #
  # @param input_file [Pathname]
  # @param output_dir [Pathname]
  # @return [Boolean] true on success
  def _split_into_chunks(input_file, output_dir)
    _remove_existing_chunks(output_dir)

    _stdout, _stderr, status = Open3.capture3(
      'split', '-d', '-a', '3', '-b', CHUNK_SIZE_BYTES.to_s,
      input_file.to_s, output_dir.join("#{BLOB_FILENAME}.").to_s
    )
    status.success?
  end

  # Reassembles the chunk files in input_dir (see _split_into_chunks) into a single
  # output_file, in numeric order. Returns false if no chunks are found.
  #
  # @param input_dir [Pathname]
  # @param output_file [Pathname]
  # @return [Boolean] true on success
  def _join_chunks(input_dir, output_file)
    chunks = _chunk_files(input_dir)
    return false if chunks.empty?

    File.open(output_file, 'wb') do |out|
      chunks.each { |chunk| IO.copy_stream(chunk.to_s, out) }
    end
    true
  end

  # Returns BLOB_FILENAME's chunk files in dir, sorted in numeric order (a plain
  # lexicographic sort is sufficient since _split_into_chunks always zero-pads to a
  # fixed 3-digit width).
  #
  # @param dir [Pathname]
  # @return [Array<Pathname>]
  def _chunk_files(dir)
    Dir.glob(dir.join("#{BLOB_FILENAME}.[0-9][0-9][0-9]").to_s).map { |f| Pathname.new(f) }.sort
  end

  # Removes any existing chunk files in dir -- cleanup before _split_into_chunks writes
  # a fresh set (see that method's doc for why stale extras must not be left behind).
  # Also removes a plain, un-suffixed BLOB_FILENAME if present -- a wrapper repo created
  # before chunking was introduced has exactly this file sitting in it, and it must not
  # be left behind: it alone already exceeds GitHub's 100MB limit, so any push including
  # it would fail regardless of the new chunks being correctly sized.
  #
  # @param dir [Pathname]
  # @return [void]
  def _remove_existing_chunks(dir)
    _chunk_files(dir).each(&:delete)

    legacy_blob = dir.join(BLOB_FILENAME)
    legacy_blob.delete if legacy_blob.file?
  end

  private_class_method :_ensure_wrapper_repo, :_rebase_onto_bundle, :_split_into_chunks,
                       :_join_chunks, :_chunk_files, :_remove_existing_chunks,
                       :_commit_and_push_wrapper, :_encrypt, :_decrypt
end
