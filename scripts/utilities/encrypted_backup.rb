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
# bundle of a real ${HOME} (scanned documents, PDFs, etc.) routinely exceeds that by
# several times over. Splitting is the only way to stay on a free, git-native, plain
# GitHub repo -- Git LFS was considered and rejected: its free tier (1GB storage + 1GB
# bandwidth/month, shared) would be exhausted in a push or two, since encrypted content
# never delta-compresses (every push is a wholly new blob, never an incremental diff).
# Chunk size is kept under GitHub's 50MB *recommended* threshold too (not just the
# 100MB hard limit) -- files between 50-100MB still push successfully, but GitHub's
# pre-receive hook prints a "GH001: Large files detected... this is larger than
# GitHub's recommended maximum file size of 50.00 MB" warning on every single push,
# which reads exactly like a failure even though it isn't one (confirmed in real usage).
#
# The passphrase is stored in the macOS Keychain, never inside either repo -- storing
# it in-repo would reintroduce the same chicken-and-egg problem git-remote-gcrypt had
# with GPG keypairs (you can't decrypt the thing that contains the only copy of the key
# needed to decrypt it).
#
# One-time-per-machine manual setup required before first use (does NOT sync via iCloud
# Keychain -- see KeybaseMigration.md -- so this must be repeated on every new machine):
#   security add-generic-password -A -a "${USER}" -s 'gpg-encrypted-backup' -w
#   (paste the passphrase from your password manager when prompted)
# scripts/setup-encrypted-backup.rb automates this interactively when possible.
#
# Method usage frequency, for anyone extending this module:
#   - bundle_and_push / fetch_and_list_bundle_refs: ROUTINE -- called by
#     scripts/git-remote-encrypted-backup (a custom git remote helper -- see that file)
#     on every 'git push'/'git pull'/'git fetch' against a remote named e.g.
#     'encrypted-backup::home'. This is now the ONLY routine push path -- no shell
#     wrapper script involved at all (push-<basename>.sh was deleted). Coexists with a
#     real 'origin' (e.g. keybase://) on the same repo via git's native fan-out push
#     (multiple push URLs on one remote) -- this is an additional remote, not a
#     replacement. See KeybaseMigration.md.
#   - clone_and_decrypt: fresh-install-of-osx.sh's bootstrap path (target_dir doesn't
#     exist as a repo yet, and isn't empty either) -- see that method's doc. Also usable
#     standalone as a disaster-recovery/restore-test utility.
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
#   Module: EncryptedBackup.clone_and_decrypt(encrypted_repo_name: EnvVars::ENCRYPTED_HOME_REPO_NAME, target_dir: EnvVars::HOME)
#   Git remote helper (scripts/git-remote-encrypted-backup): EncryptedBackup.bundle_and_push(git_dir:, encrypted_repo_name:, quiet:)
#                                                             EncryptedBackup.fetch_and_list_bundle_refs(git_dir:, encrypted_repo_name:, quiet:)

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

  KEYCHAIN_SERVICE = 'gpg-encrypted-backup'
  BLOB_FILENAME = 'backup.gpg'
  # GitHub's hard per-file push limit is 100MB, but files between 50MB-100MB also
  # trigger a "GH001: Large files detected... this is larger than GitHub's recommended
  # maximum file size of 50.00 MB" warning on every single push (confirmed in real
  # usage) -- non-fatal, but reads exactly like a failure. Staying under 50MB avoids
  # the warning entirely; staying under 100MB avoids the actual hard rejection. Leaves
  # a comfortable ~10% margin below the 50MB threshold (rather than cutting it as close
  # as possible) to tolerate any filesystem/encoding overhead.
  CHUNK_SIZE_BYTES = 45 * 1024 * 1024

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
  # by clone_and_decrypt/bundle_and_push/fetch_and_list_bundle_refs/verify_current_blob_decryptable?,
  # in addition to being scripts/setup-encrypted-backup.rb's main entry point, so both the
  # routine call sites and the dedicated setup script share identical "prompt if possible" behavior.
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

    # Uses tty_available? (checks '/dev/tty' directly), not running_in_tty? (checks
    # $stdout.tty?) -- the documented fresh-install-of-osx.sh bootstrap one-liner pipes
    # stdout through 'tee' (see Adoption.md Phase 3.2), which makes $stdout.tty? false
    # even though a human is watching the terminal live and could answer a prompt.
    # '/dev/tty' still refers to that same terminal regardless of the pipe, and
    # 'security add-generic-password's own interactive prompt (via getpass(3)) already
    # talks to /dev/tty directly by design -- so gating on tty_available? here (instead
    # of running_in_tty?) makes the prompt actually fire for that one-liner too, while
    # still correctly staying silent for genuinely non-interactive contexts (cron,
    # launchd) that have no controlling terminal at all.
    unless tty_available?
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

  # Clones encrypted_repo_name's plain GitHub remote, decrypts its blob with the Keychain
  # passphrase, and imports the resulting bundle into target_dir (full git history restored)
  # via GitProcessor.clone_repo_into.
  #
  # Still the bootstrap mechanism for fresh-install-of-osx.sh (target_dir does not exist
  # as a git repo yet, and -- for ${HOME} specifically -- is not even empty, ruling out a
  # plain 'git clone'). Day-to-day push/pull no longer uses this at all: once a repo has
  # the 'encrypted-backup' remote configured (see scripts/git-remote-encrypted-backup),
  # plain 'git push'/'git pull'/'git fetch' handle it natively. Also useful standalone as
  # a disaster-recovery/restore-test utility (see KeybaseMigration.md) -- e.g.
  # EncryptedBackup.clone_and_decrypt(encrypted_repo_name: 'home', target_dir: '/tmp/restore-test')
  # to verify a backup actually restores, without touching the real target_dir.
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

  # Bundles ALL refs directly from git_dir and pushes the result to the wrapper repo --
  # called by the git-remote-helper's 'push' command (see
  # scripts/git-remote-encrypted-backup), for callers that only have a GIT_DIR and no
  # guaranteed working tree to '-C' into. Uses '--git-dir' throughout instead of
  # GitProcessor's cwd-based '-C' invocation for that reason.
  #
  # @param git_dir [Pathname, String] The '.git' directory to bundle from (GIT_DIR).
  # @param encrypted_repo_name [String]
  # @param quiet [Boolean] Suppresses 'git bundle create's progress meter when true
  #   (threaded through from the remote helper's 'option verbosity'/'option progress' --
  #   see scripts/git-remote-encrypted-backup). Streamed live either way (see note below)
  #   -- this only controls how much git itself chooses to report, not whether it streams.
  # @return [Boolean] true on success, false on failure
  def bundle_and_push(git_dir:, encrypted_repo_name:, quiet: false)
    return false unless prompt_and_store_passphrase

    Dir.mktmpdir('encrypted-backup-') do |tmp_dir|
      tmp_dir_pn = Pathname.new(tmp_dir)
      bundle_file = tmp_dir_pn.join('repo.bundle')
      encrypted_file = tmp_dir_pn.join(BLOB_FILENAME)

      # Streamed (not Open3.capture3) so a large repo's multi-minute bundling shows live
      # progress instead of appearing to hang until the entire command completes. Safe to
      # stream from inside the remote helper: both call sites (_reply_list/_reply_push in
      # scripts/git-remote-encrypted-backup) already wrap this call in
      # _with_stdout_redirected_to_stderr, an fd-level redirect that also covers whatever
      # a child process writes to its inherited stdout -- see that file's header comment.
      # '--quiet'/'--progress' are passed explicitly (never left to git's own tty
      # auto-detection) since the remote-helper's stderr may not present as a real tty
      # even when a human is watching it live -- auto-detection silently produced no
      # output at all in exactly that situation.
      # '--quiet'/'--progress' must precede <file> -- 'git bundle create's own usage is
      # '[-q | --quiet | --progress] [--version=<version>] <file> <git-rev-list-args>';
      # placing it after <file> (alongside '--all') causes git to misparse it as a
      # rev-list arg instead of a bundle-create option ("unrecognized argument"),
      # confirmed empirically.
      bundle_create_args = ['git', '--git-dir', git_dir.to_s, 'bundle', 'create', quiet ? '--quiet' : '--progress', bundle_file.to_s, '--all']
      unless CommandUtils.run_interactive(*bundle_create_args)
        Logging.record_error "Failed to create git bundle from '#{git_dir}' -- see output above"
        return false
      end

      unless _encrypt(bundle_file, encrypted_file)
        Logging.record_error "Failed to encrypt bundle from '#{git_dir}'"
        return false
      end

      wrapper_dir = wrapper_repo_dir(encrypted_repo_name)
      return false unless _ensure_wrapper_repo(wrapper_dir, encrypted_repo_name)

      unless _split_into_chunks(encrypted_file, wrapper_dir)
        Logging.record_error "Failed to split encrypted blob into <100MB chunks for '#{git_dir}'"
        return false
      end

      return false unless _commit_and_push_wrapper(wrapper_dir)
    end

    Logging.success "Encrypted backup pushed to '#{encrypted_repo_name.cyan}' from '#{git_dir}'"
    true
  end

  # Fetches the latest encrypted backup for encrypted_repo_name, decrypts it, imports its
  # objects into git_dir's object database (via 'git bundle unbundle' -- objects only, no
  # refs touched, per 'git help bundle'), and returns the ref list the bundle contains.
  # This is the git-remote-helper's combined 'list'+'fetch' primitive (see
  # scripts/git-remote-encrypted-backup): a remote helper with the 'fetch' capability
  # (as opposed to 'import') is only responsible for populating the object database --
  # git itself updates remote-tracking refs afterward, based on the ref list returned
  # here combined with the now-present objects. Always imports everything eagerly (no
  # partial/incremental fetch) since decryption is all-or-nothing by design.
  #
  # A missing/undecryptable backup (nothing pushed yet, wrong passphrase, corrupted
  # blob) is reported to the caller as an empty ref list, not a hard failure -- from the
  # remote-helper's perspective this is indistinguishable from "the remote exists but has
  # no refs yet" (e.g. a brand new repo before its first push), which is a normal,
  # expected state, not an error. The underlying reason is still logged via
  # Logging.record_error for diagnostics.
  #
  # @param git_dir [Pathname, String] The '.git' directory to import objects into (GIT_DIR).
  # @param encrypted_repo_name [String]
  # @param quiet [Boolean] Suppresses 'git bundle unbundle's progress meter when true --
  #   see bundle_and_push's matching parameter doc for the full rationale.
  # @return [Array<Array(String, String)>] array of [sha1, refname] pairs (empty if
  #   nothing has been pushed yet, or the current blob could not be decrypted)
  def fetch_and_list_bundle_refs(git_dir:, encrypted_repo_name:, quiet: false)
    return [] unless prompt_and_store_passphrase

    wrapper_dir = wrapper_repo_dir(encrypted_repo_name)
    return [] unless _ensure_wrapper_repo(wrapper_dir, encrypted_repo_name, pull_latest: true)

    Dir.mktmpdir('encrypted-backup-') do |tmp_dir|
      tmp_dir_pn = Pathname.new(tmp_dir)
      encrypted_file = tmp_dir_pn.join(BLOB_FILENAME)
      bundle_file = tmp_dir_pn.join('repo.bundle')

      unless _join_chunks(wrapper_dir, encrypted_file)
        Logging.record_error "No '#{BLOB_FILENAME}.*' chunks found in '#{wrapper_dir.cyan}' -- nothing pushed yet for '#{encrypted_repo_name}'"
        return []
      end

      unless _decrypt(encrypted_file, bundle_file)
        Logging.record_error "Failed to decrypt '#{encrypted_file.cyan}' -- check the Keychain passphrase is correct"
        return []
      end

      # 'list-heads' output must be parsed (not just checked for success), and is always
      # small/fast (a plain list of sha1/refname pairs) -- no progress-meter concern, so
      # this one stays captured rather than streamed.
      heads_out, heads_stderr, heads_status = Open3.capture3('git', 'bundle', 'list-heads', bundle_file.to_s)
      unless heads_status.success?
        Logging.record_error "Failed to list heads in decrypted bundle for '#{encrypted_repo_name}': #{heads_stderr}"
        return []
      end

      # Streamed for the same reason as bundle_and_push's 'bundle create' above -- a large
      # repo's object import can take minutes. 'git bundle unbundle' has no '--quiet' flag
      # (only '--progress' to force it on), so quiet mode is simply "don't force progress",
      # not "explicitly suppress" -- there is nothing more to suppress by default. Streaming
      # also surfaces 'unbundle's own stdout (it always prints the same sha1/refname pairs
      # 'list-heads' already returned, confirmed empirically) -- harmless duplication, not a
      # bug: this method is only ever called from the remote helper's _reply_list, which
      # wraps the whole call in _with_stdout_redirected_to_stderr, so it lands on stderr
      # alongside the progress meter, not on the actual wire-protocol stdout stream.
      # '--progress' must precede <file> here too -- see bundle_create_args's comment
      # above for why (same 'git bundle' argument-parsing behavior).
      unbundle_args = ['git', '--git-dir', git_dir.to_s, 'bundle', 'unbundle']
      unbundle_args << '--progress' unless quiet
      unbundle_args << bundle_file.to_s
      unless CommandUtils.run_interactive(*unbundle_args)
        Logging.record_error "Failed to unbundle encrypted backup into '#{git_dir}' -- see output above"
        return []
      end

      return heads_out.each_line.filter_map do |line|
        sha1, ref = line.strip.split(' ', 2)
        [sha1, ref] unless nil_or_empty?(sha1) || nil_or_empty?(ref)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Ensures a local clone of encrypted_repo_name's plain GitHub remote exists at wrapper_dir,
  # cloning it if missing. When pull_latest is true and the clone already exists, pulls the
  # latest blob first (tolerates failure -- e.g. nothing pushed yet on a brand new repo).
  #
  # Always resets an existing wrapper repo to HEAD first if its working tree is dirty --
  # this repo's working tree is a managed artifact (only ever written by
  # _split_into_chunks/_commit_and_push_wrapper's commit-then-push sequence), never
  # something a human or any other code path legitimately edits directly, so uncommitted
  # changes here can only be leftover cruft from an earlier bundle_and_push call that got
  # interrupted between _split_into_chunks removing the OLD (fully-committed, known-good)
  # chunks and _commit_and_push_wrapper committing the NEW set -- e.g. killed by an outer
  # with-retry timeout, network loss, terminal closed, laptop slept, etc. Left as-is, a
  # subsequent join+decrypt would silently reassemble whatever partial mix of old/new
  # chunks happens to be sitting on disk (neither a complete old nor a complete new
  # backup) and fail with a *misleading* "check the Keychain passphrase is correct" --
  # the real problem has nothing to do with the passphrase. Resetting first guarantees
  # every read always sees the last fully-committed (and already-pushed) good state.
  def _ensure_wrapper_repo(wrapper_dir, encrypted_repo_name, pull_latest: false)
    if GitProcessor.repo?(wrapper_dir)
      git = GitProcessor.new(dir: wrapper_dir)
      _stdout, _stderr, clean_status = git.run_alias('is-clean', read_only: true)
      unless clean_status.success?
        Logging.warn "'#{wrapper_dir.cyan}' has uncommitted changes -- this can only be leftover " \
                     'debris from an earlier interrupted push; resetting to the last committed ' \
                     '(and already-pushed) state before reading'
        git.reset_hard('HEAD')
      end
      _ensure_remote_fetch_refspec(git, wrapper_dir) if pull_latest
      git.pull if pull_latest
      return true
    end

    gh_username = _gh_username
    return false if nil_or_empty?(gh_username)

    remote_url = "https://github.com/#{gh_username}/#{encrypted_repo_name}.git"
    # skip_maintenance: true -- this wrapper repo holds nothing but a handful of small
    # chunk files, wholesale-replaced on every push; it gains nothing from
    # migrate-reftable/unshallow/maintain/siu. Skipping is not just a wasted-cost
    # optimization: that chain's own duration (unshallow alone runs a nested with-retry
    # fetch) can exceed the timeout of the *outer* with-retry wrapping this entire call
    # from scripts/git-remote-encrypted-backup -- observed in practice as a false-positive
    # stall-kill (SIGKILL) of the whole remote-helper process well after this clone had
    # already succeeded, because the outer with-retry's progress-path is the real target
    # repo's OWN '.git/objects' (e.g. browser-profiles'), which sees no growth while this
    # wrapper repo's own maintenance runs.
    unless GitProcessor.clone_repo_into(remote_url, wrapper_dir, skip_maintenance: true)
      Logging.record_error "Failed to clone '#{remote_url}' -- has the GitHub repo '#{encrypted_repo_name}' " \
                           'been created yet? Create it (public, empty) at https://github.com/new before running this.'
      return false
    end
    true
  end

  # Self-heals two classes of wrapper-repo drift discovered in the wild, both of which
  # break the 'git pull' that _ensure_wrapper_repo runs right after calling this:
  #
  # 1. Missing/narrow fetch refspec: a repo can end up with remote.origin.fetch
  #    completely absent or scoped to only one branch name, instead of the wildcard
  #    '+refs/heads/*:refs/remotes/origin/*' that 'git remote set-branches origin *'
  #    sets. Without it, 'git pull' fails with "fatal: upstream branch 'refs/heads/
  #    <name>' not stored as a remote-tracking branch" even though fetching the ref
  #    itself succeeds (confirmed in the wild: 'git pull --all' in a repo using the
  #    encrypted-backup remote surfaced exactly this, tracing back to this wrapper repo).
  #
  # 2. Remote default branch renamed (e.g. via GitHub's web UI "rename branch" feature --
  #    hit in the wild for both the 'home' and 'browser-profiles' wrapper repos within
  #    the same session, 'main' -> 'master'): the local branch keeps its old name and
  #    upstream config, so 'git pull' fails with "Your configuration specifies to merge
  #    with the ref 'refs/heads/<old>' from the remote, but no such ref was fetched."
  #    Detected by comparing the local branch name against the remote's actual HEAD
  #    symref (which 'git remote set-head origin -a' always refreshes to the true
  #    current value); repaired by renaming the local branch and re-pointing its
  #    upstream to match -- exactly mirroring GitHub's own suggested recovery commands
  #    ('git branch -m <old> <new>; git branch -u origin/<new> <new>').
  #
  # Both fixes are cheap, idempotent, and safe to run unconditionally before every
  # pull_latest: true call -- 'set-branches'/'set-head' are local-only aside from a
  # single ref lookup, far cheaper than the fetch 'git pull' performs immediately after.
  #
  # @param git [GitProcessor] already constructed for wrapper_dir
  # @param wrapper_dir [Pathname] only used for log messages
  # @return [void]
  def _ensure_remote_fetch_refspec(git, wrapper_dir)
    git.run_alias('remote', 'set-branches', 'origin', '*')

    git.run_alias('remote', 'set-head', 'origin', '-a')
    remote_head, _stderr, status = git.run_alias('symbolic-ref', 'refs/remotes/origin/HEAD', read_only: true)
    return unless status.success?

    remote_branch = remote_head.strip.sub(%r{\Arefs/remotes/origin/}, '')
    return if nil_or_empty?(remote_branch)

    local_branch = git.current_branch
    return if nil_or_empty?(local_branch) || local_branch == remote_branch

    Logging.warn "'#{wrapper_dir.cyan}' local branch '#{local_branch.cyan}' is stale -- remote's " \
                 "default branch is now '#{remote_branch.cyan}' (renamed on GitHub); repairing local tracking"
    git.run_alias('branch', '-m', local_branch, remote_branch)
    git.run_alias('branch', '-u', "origin/#{remote_branch}", remote_branch)
  end

  # Derives the GitHub username that owns the encrypted-backup wrapper repos (e.g. 'home',
  # 'browser-profiles') from DOTFILES_DIR's own 'origin' remote -- mirrors
  # _resolve_gh_username() in fresh-install-of-osx.sh. There is no stored GH_USERNAME
  # constant (see env_vars.rb): a fork's already-cloned dotfiles repo is the only thing
  # that reliably identifies which GitHub account owns the wrapper repos too, since both
  # are expected to live under the same account.
  def _gh_username
    @_gh_username ||= begin
      url = GitProcessor.new(dir: EnvVars::DOTFILES_DIR).remote_url
      if nil_or_empty?(url)
        Logging.record_error "Could not determine GitHub username -- '#{EnvVars::DOTFILES_DIR.cyan}' has no 'origin' remote"
        nil
      else
        GitProcessor::GitUrlParser.new(url).owner
      end
    rescue ArgumentError => e
      Logging.record_error "Could not determine GitHub username: #{e.message}"
      nil
    end
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
  #
  # Splits into a scratch temp directory FIRST and only swaps it into output_dir (removing
  # the old chunks there and moving the new ones in) once the new set is fully written and
  # confirmed non-empty. This is deliberately NOT "remove old chunks, then split directly
  # into output_dir": that ordering leaves output_dir's old (fully-committed, known-good)
  # chunks destroyed for the entire duration of 'split' with no complete replacement yet
  # present -- if the process is interrupted anywhere in that window (an outer with-retry
  # timeout, network loss, terminal closed, laptop slept), _commit_and_push_wrapper never
  # runs, and the wrapper repo's working tree is left holding neither the old nor a
  # complete new backup: exactly the state _ensure_wrapper_repo's dirty-tree reset guards
  # against on the read side, but better prevented at the source. Splitting into a scratch
  # dir first shrinks the unsafe window down to the brief rename loop below, and the old
  # chunks are only ever touched once a verified-complete new set already exists.
  #
  # @param input_file [Pathname]
  # @param output_dir [Pathname]
  # @return [Boolean] true on success
  def _split_into_chunks(input_file, output_dir)
    Dir.mktmpdir('encrypted-backup-split-') do |scratch_dir|
      scratch_dir_pn = Pathname.new(scratch_dir)

      _stdout, _stderr, status = Open3.capture3(
        'split', '-d', '-a', '3', '-b', CHUNK_SIZE_BYTES.to_s,
        input_file.to_s, scratch_dir_pn.join("#{BLOB_FILENAME}.").to_s
      )
      return false unless status.success?

      new_chunks = _chunk_files(scratch_dir_pn)
      return false if new_chunks.empty?

      _remove_existing_chunks(output_dir)
      new_chunks.each { |chunk| chunk.rename(output_dir.join(chunk.basename)) }
    end
    true
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

  # Removes any existing chunk files in dir -- called by _split_into_chunks right before
  # swapping in a verified-complete new set (see that method's doc for why stale extras
  # must not be left behind, and why this happens only after the new set is ready, not
  # before splitting). Also removes a plain, un-suffixed BLOB_FILENAME if present -- a
  # wrapper repo created before chunking was introduced has exactly this file sitting in
  # it, and it must not be left behind: it alone already exceeds GitHub's 100MB limit, so
  # any push including it would fail regardless of the new chunks being correctly sized.
  #
  # @param dir [Pathname]
  # @return [void]
  def _remove_existing_chunks(dir)
    _chunk_files(dir).each(&:delete)

    legacy_blob = dir.join(BLOB_FILENAME)
    legacy_blob.delete if legacy_blob.file?
  end

  private_class_method :_ensure_wrapper_repo, :_ensure_remote_fetch_refspec, :_split_into_chunks,
                       :_join_chunks, :_chunk_files, :_remove_existing_chunks,
                       :_commit_and_push_wrapper, :_encrypt, :_decrypt
end
