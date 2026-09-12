# Keybase to Encrypted-Backup Migration Guide

**Branch:** keybase-migration
**Mechanism:** `git bundle` + `gpg --symmetric` (see `TechnicalDeepDive.md` section 14 for the full design rationale, including why `git-remote-gcrypt`, Picocrypt, and git-crypt were each evaluated and rejected)

---

## Overview

This migration replaces Keybase with a self-built encrypted-backup mechanism implemented in `scripts/utilities/encrypted_backup.rb`.

### What Changed

**Removed:**
- Keybase.app (GUI dependency) and its Brewfile cask
- `scripts/utilities/keybase.rb` and every call site
- `keybase://` remote URLs
- `KEYBASE_*` environment variables

**Added:**
- `gnupg` (already a base Homebrew dependency)
- `scripts/utilities/encrypted_backup.rb` -- core module
- `scripts/setup-encrypted-backup.rb` -- idempotent readiness check (safe to run anytime; the Keychain entry it creates is effectively one-time-per-machine -- see "One-Time-Per-Machine Setup" below)
- `scripts/migrate-repo-to-encrypted-backup.rb` / `scripts/migrate-repos-to-encrypted-backup.rb` -- **ONE-TIME** migration tooling (run once per repo, when first moving off Keybase)
- `${PERSONAL_BIN_DIR}/push-<home-basename>.sh` / `push-browser-profiles.sh` -- transparent day-to-day refresh (routine, runs every push)

### How It Works

1. `home` (`~/`) and `browser-profiles` stay ordinary, unencrypted local git repos -- full native history, exactly as before. They do not need a live "origin" remote for this mechanism to work.
2. `git bundle create --all` produces a single-file, complete representation of the repo's history.
3. That bundle is encrypted with `gpg --batch --passphrase-fd 0 --symmetric`, using a passphrase read from the **macOS Keychain** (never stored inside either repo -- see "Why the Keychain, not a file" below).
4. The resulting encrypted blob (`backup.gpg`) is split into <100MB chunks (`backup.gpg.000`, `backup.gpg.001`, ...) -- GitHub hard-rejects any single pushed file over 100MB, and a full-history bundle of a real home directory (scanned documents, PDFs, etc.) can easily exceed that -- then all chunks are committed and pushed to a plain, ordinary **public** GitHub repo. Still no special git-remote-helper, just an ordinary `git push`.
5. To restore: clone the public repo over HTTPS (zero GitHub auth needed for a public repo), reassemble the chunks back into `backup.gpg`, decrypt it with the Keychain passphrase, then `git clone <decrypted-bundle>` to fully reconstitute the original repo with complete history.

**Why the Keychain, not a file:** the passphrase must never live inside `home` or `browser-profiles` themselves -- if it did, you'd need to already have decrypted the backup to get the passphrase needed to decrypt the backup. That's the exact chicken-and-egg problem this design exists to avoid (see `TechnicalDeepDive.md` section 14 for the longer version of this story, including why `git-remote-gcrypt`'s GPG-keypair-based approach fell into the same trap).

**What's visible vs. encrypted on GitHub:**

| Item | Visibility |
|---|---|
| Repo exists | Public (same trade-off Keybase avoided, now accepted) |
| Commit history of the wrapper repo (backup frequency/dates) | Public |
| File names, directory structure of the real content | Hidden -- it's inside the opaque encrypted bundle |
| File contents | Hidden |
| Commit messages of the real content | Hidden |

---

## Is This as Secure as Keybase?

**Short answer: comparable for content confidentiality given a strong passphrase, but not equivalent overall.** Several concrete differences, not just a vague "trust trade-off":

| Dimension | Keybase | This mechanism |
|---|---|---|
| Content confidentiality | Strong (per-device asymmetric keys) | Strong, **if and only if** the passphrase has high entropy (see below) |
| Metadata privacy | Full -- repo existence, structure, everything hidden from non-collaborators | Partial -- repo existence and the wrapper repo's own commit history/dates are public |
| Key-derivation strength | N/A (full-entropy device keys, not password-derived) | Weaker than a modern memory-hard KDF -- GPG's symmetric mode uses an iterated+salted S2K (string-to-key) function, not Argon2id/scrypt. It resists brute-forcing less per unit of attacker compute than a memory-hard KDF would, for the same passphrase strength |
| Revocation | Per-device -- compromise one device, revoke just that device's key, everything else stays secure | None -- one shared passphrase for everything. A compromised passphrase means rotating it and re-encrypting all future backups; anything already pushed under the old passphrase stays decryptable with it forever if retained in git history |
| Passphrase exposure surface | Provisioned per-device via Keybase's own protocol, not stored in a general-purpose OS secret store | Stored in the macOS Keychain with `-A` (any process can read it, no GUI prompt) -- a deliberate trade-off for scriptability, but it does mean any process running as your user can read it non-interactively |

**What this means practically:**

1. **The passphrase is now the entire security boundary.** Use a long, high-entropy, randomly-generated passphrase (not a memorized word or phrase) -- e.g. `openssl rand -base64 32` -- and store it in a password manager, not just the Keychain. A weak passphrase is a much bigger practical risk here than with Keybase, where the private key material has full cryptographic entropy regardless of what the user "remembers."
2. **Rotating the passphrase doesn't retroactively protect old backups.** If the wrapper repo's own git history retains prior commits of `backup.gpg.*`, each old commit stays decryptable with whatever passphrase was active when it was pushed. If you ever rotate the passphrase (e.g. after a suspected compromise), also squash the wrapper repo's own history so old, differently-encrypted chunks don't linger in reachable history: `recreate-repository.rb -f -d <wrapper-repo-dir>`. `recreate-repository.rb`'s built-in "verify file lists match" safety check (`GitProcessor#ls_tree` uses `git ls-tree --name-only` -- paths only, never content) is weaker protection here than for a typical multi-file repo: the wrapper repo's working tree only ever contains a handful of numbered `backup.gpg.NNN` chunk files (see "How It Works" above), so that check can catch a chunk going missing/a stray extra file appearing, or even the chunk *count* changing (a differently-sized backup produces a different number of chunks) -- but it provides no protection against force-pushing *stale or corrupted* chunks whose paths and count are unchanged but content is wrong, which is the more relevant risk for this specific repo. For that reason, `recreate-repository.rb`'s force mode automatically detects when `-d` points at a directory under `${XDG_CACHE_HOME}/encrypted-backups/` and runs the actually-relevant check first (`EncryptedBackup.verify_current_blob_decryptable?` -- reassembles the chunks, decrypts, and runs `git bundle verify` on the result), refusing to squash if it fails. This is automatic -- no special flag needed, so the ordinary `recreate-repository.rb -f -d <dir>` habit stays safe for wrapper repos too.
3. **`-A` on the Keychain entry is a real, accepted trade-off.** It's required for non-interactive cron/fresh-install use, but it means the passphrase is readable by any process running as your user, not gated behind a Touch ID/password prompt the way a normal Keychain item would be. If that's an unacceptable trade-off for your threat model, this mechanism is not a drop-in equivalent to Keybase's device-key model.
4. **Metadata exposure (repo existence, backup cadence) is unchanged from the accepted trade-offs already documented above and in `TechnicalDeepDive.md` section 14** -- not a new consideration, just restated here for completeness of the security picture.

**Bottom line:** for someone who chooses (and properly stores) a strong, random passphrase and accepts the metadata/revocation trade-offs, this mechanism provides strong confidentiality for the actual backed-up content. It is not a like-for-like replacement for Keybase's full security model -- particularly around metadata privacy and per-device key revocation -- and anyone with a stricter threat model should weigh that before relying on it for genuinely sensitive material.

---

## One-Time-Per-Machine Setup

### 1. Install gnupg (already in the base Brewfile section)

```bash
brew bundle install
```

### 2. Ensure the Keychain passphrase is set

```bash
setup-encrypted-backup.rb
```

This is idempotent and safe to run anytime (it's also called automatically by
`fresh-install-of-osx.sh`). If the passphrase is missing and this is running
interactively, it prompts you for one via `security add-generic-password`'s own masked,
double-entry confirmation prompt (see `EncryptedBackup.prompt_and_store_passphrase`) --
generate a strong passphrase and save it in your password manager when prompted. The
passphrase itself never touches this script or Ruby process memory/argv -- `security`
handles the prompt and storage directly.

If running non-interactively (cron, a piped `curl | zsh` bootstrap, etc.), there's no way
to prompt, so `setup-encrypted-backup.rb` just logs instructions instead. In that case, run
the equivalent command yourself first, interactively, in a real terminal:

```bash
security add-generic-password -A -a "$USER" -s 'dotfiles-encrypted-backup' -w
# paste the passphrase when prompted
```

`-A` allows any process to read the entry without a GUI prompt -- required for
non-interactive cron/fresh-install use.

**This is a genuinely per-machine step -- it does not sync via iCloud Keychain, even if iCloud Keychain is enabled and you're signed in on that machine.** Verified directly: `security add-generic-password -h` exposes no flag for `kSecAttrSynchronizable` (the attribute iCloud Keychain sync depends on) -- only account/service/password/access-control options exist. Items created this way go into the local, non-syncing keychain by default. **You must run this exact command again on every new machine**, including during vanilla-OS fresh-install (see below) -- there is no way to carry it over automatically, regardless of iCloud sign-in status.

### 3. Create the two plain GitHub repos (public, empty, one time)

Unlike Keybase (which auto-creates repos on push), a plain `git push` to GitHub requires the target repo to already exist:

```bash
gh repo create "${GH_USERNAME}/${ENCRYPTED_HOME_REPO_NAME:-home}" --public
gh repo create "${GH_USERNAME}/${ENCRYPTED_PROFILES_REPO_NAME:-browser-profiles}" --public
```

(Or create them manually at https://github.com/new -- public, no README/gitignore/license.)

---

## Migrating Existing Repos (One-Time, Per Repo)

Run this once per repository, when first moving it off Keybase. Nothing left to migrate for
that repo afterward -- day-to-day pushes go through the `push-<basename>.sh` override
scripts instead (see "Day-to-Day Usage" below). Re-running is harmless (it just re-bundles,
re-encrypts, and re-pushes), but there's nothing more to gain from doing so once a repo has
already been migrated.

```bash
# Both repos at once (recommended)
migrate-repos-to-encrypted-backup.rb

# Or one at a time
migrate-repo-to-encrypted-backup.rb --repo "${HOME}" --encrypted-repo-name "${ENCRYPTED_HOME_REPO_NAME:-home}"
migrate-repo-to-encrypted-backup.rb --repo "${PERSONAL_PROFILES_DIR}" --encrypted-repo-name "${ENCRYPTED_PROFILES_REPO_NAME:-browser-profiles}"
```

This does **not** touch either repo's existing remotes -- it only bundles, encrypts, and pushes to the separate wrapper repo. If `origin` still points at a dead `keybase://` URL, the script will warn (not modify anything); remove it manually if you want:

```bash
git -C "${HOME}" remote remove origin
```

**Verify the restore path works before trusting this** (test on a scratch directory, not your real `$HOME`):

```bash
ruby -e "require 'encrypted_backup'; require 'env_vars'; EncryptedBackup.clone_and_decrypt(encrypted_repo_name: EnvVars::ENCRYPTED_HOME_REPO_NAME, target_dir: '/tmp/restore-test')"
```

---

## Day-to-Day Usage

Nothing changes. Run `push` and `pull` (the shell functions, not `git push`/`git pull` -- see `git-config.md` for why the distinction matters) in `~` or `${PERSONAL_PROFILES_DIR}` as you always have -- including the sequential push-on-machine1, pull/rebase-on-machine2 workflow Keybase supported. The per-repo override scripts (`push-<home-basename>.sh`/`pull-<home-basename>.sh` -- basename of `$HOME`, typically `$USER` -- and `push-browser-profiles.sh`/`pull-browser-profiles.sh`) automatically refresh/consume the encrypted backup. See `EncryptedBackup.fetch_and_rebase` (`scripts/utilities/encrypted_backup.rb`) for how `pull` fetches the latest encrypted blob and rebases the current branch onto it, even though the live repo has no real `origin` to fetch from directly. The existing cron schedule that already runs `push-browser-profiles.sh` keeps that backup current without any extra action.

**`pull` on `browser-profiles` may reset instead of rebase.** That repo is periodically force-squashed by `recreate-repository.rb`, so an older local checkout and a freshly-squashed backup routinely share no common ancestor -- a plain rebase would be meaningless there. `pull-browser-profiles.sh` passes `allow_reset_on_diverged_history: true`, so `fetch_and_rebase` detects the missing common ancestor and hard-resets the branch to the backup instead (local commit history in that repo is never meant to survive a squash anyway). `pull-<home-basename>.sh` leaves this at its default `false` -- `$HOME` is never force-squashed, so diverged history there is unexpected and fails loudly rather than silently discarding local commits.

---

## Vanilla-OS Fresh Install

**Prerequisite:** the Keychain passphrase must already be set, or be settable interactively, before `fresh-install-of-osx.sh` reaches the "Clone encrypted-backup repos" step. **Important caveat on the documented bootstrap one-liner** (`curl ... | zsh 2>&1 | tee ...`, see Adoption.md Phase 3.2): because that command pipes stdout through `tee`, `$stdout.tty?` is false for the whole script and everything it calls, so `setup-encrypted-backup.rb`'s interactive prompt does **not** trigger there even though a human is watching the terminal live -- it falls back to logging instructions only. The interactive prompt only actually fires when `fresh-install-of-osx.sh` is run directly in a terminal without piping through `tee`/anything else. For the documented one-liner specifically, either run `security add-generic-password -A -a "$USER" -s 'dotfiles-encrypted-backup' -w` yourself first (before running the one-liner), or re-run `setup-encrypted-backup.rb` directly afterward (in a real interactive shell, no piping) followed by `_clone_home_repo`/`_clone_profiles_repo` (or just re-run `fresh-install-of-osx.sh` again -- it's idempotent). **iCloud Keychain sign-in does not carry this over automatically** either way (see "does not sync via iCloud Keychain" note above); it must be re-entered by hand on every new machine.

**Automated steps:**
1. Homebrew installs, including `gnupg`.
2. `setup-encrypted-backup.rb` runs -- if the passphrase is missing and this is genuinely interactive (see caveat above), prompts for one; otherwise warns and continues (does not block the rest of fresh-install).
3. `_clone_home_repo` / `_clone_profiles_repo` clone the plain public wrapper repos over HTTPS (zero GitHub auth), reassemble the `backup.gpg.*` chunks and decrypt them with the Keychain passphrase, and `git clone` the resulting bundle into `$HOME` / `$PERSONAL_PROFILES_DIR` -- full history restored.
4. SSH keys from the restored home repo become available for every subsequent git operation.

**Disaster recovery scenario:** laptop stolen/dead -> new laptop -> add the Keychain passphrase (interactively if running fresh-install directly, or manually beforehand if using the piped one-liner) -> run `fresh-install-of-osx.sh` -> full recovery.

---

## Troubleshooting

### "No passphrase found in Keychain"

Run the `security add-generic-password` command from the one-time setup section above.

### "Failed to clone ... has the GitHub repo been created yet?"

The plain wrapper repo doesn't exist yet on GitHub. Create it (see step 3 of one-time-per-machine setup) before migrating or restoring.

### "Failed to decrypt ... check the Keychain passphrase is correct"

The Keychain entry has the wrong value, or was created for a different `$USER`/service name. Re-run:
```bash
security delete-generic-password -a "$USER" -s 'dotfiles-encrypted-backup' 2>/dev/null
security add-generic-password -A -a "$USER" -s 'dotfiles-encrypted-backup' -w
```

---

## Questions

**Q: What if I forget the passphrase?**
A: The encrypted backup is unrecoverable. Store it in a password manager, not just the Keychain (the Keychain is itself lost if the machine is wiped without a working backup).

**Q: Can I rotate the passphrase?**
A: Update the Keychain entry, then run the migration script again for each repo -- the next `export_and_push` re-encrypts with whatever passphrase is currently in the Keychain. Old blobs remain decryptable with the old passphrase for as long as they're still reachable in the wrapper repo's own git history (see "Rotating the passphrase doesn't retroactively protect old backups" above) -- squash that history (`recreate-repository.rb -f -d <wrapper-repo-dir>`) if you need old blobs to stop being decryptable with a retired passphrase, e.g. after a suspected compromise.

**Q: Can different repos use different passphrases?**
A: Not with the current implementation -- one Keychain entry (`dotfiles-encrypted-backup`) is shared by both. Could be extended to per-repo Keychain services if ever needed.

**Q: What does GitHub see?**
A: Repo existence and the wrapper repo's own (trivial) commit history. File names, contents, and structure of the real backup are all inside the opaque encrypted chunks (split into <100MB pieces purely to satisfy GitHub's file-size limit -- the chunk boundaries reveal nothing about the real content).

---

## Further Reading

- `TechnicalDeepDive.md` section 14 -- full design rationale, including the rejected `git-remote-gcrypt`/Picocrypt/git-crypt alternatives and why each was ruled out
- `scripts/utilities/encrypted_backup.rb` -- implementation
- [GnuPG documentation](https://www.gnupg.org/documentation/) -- `gpg --symmetric` details
- [git bundle documentation](https://git-scm.com/docs/git-bundle)
