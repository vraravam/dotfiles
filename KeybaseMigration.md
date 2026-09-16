# Keybase and Encrypted-Backup Guide

**Mechanism:** `git bundle` + `gpg --symmetric`, exposed as a real git remote via a custom remote helper (see `TechnicalDeepDive.md` section 14 for the full design rationale, including why `git-remote-gcrypt`, Picocrypt, and git-crypt were each evaluated and rejected)

---

## Overview

This adds a second, independent encrypted-backup mechanism alongside Keybase, rather than replacing it. If a repo (`~` or `${PERSONAL_PROFILES_DIR}`) still has a `keybase://` `origin` remote, it is left completely untouched -- the encrypted backup is configured as a fully separate remote (named `origin2` when `origin` already exists, or `origin` itself when it doesn't), never fanned into `origin`'s own push URLs. Running both means two independent, addressable restore points, so you can choose which one to use when setting up a new machine, instead of committing to just one. Since the two remotes are kept fully separate (not fanned out from a single `push`), each is pushed to explicitly: `git push` (or `push`) reaches `origin` only; refreshing the encrypted backup is a separate `git push origin2`.

**The whole mechanism is a real git remote.** Plain `git push`/`git pull`/`git fetch` work against it directly -- no wrapper script, no manual bundle/encrypt/decrypt steps. This is implemented as `scripts/git-remote-encrypted-backup`, a custom git remote helper that git invokes automatically for any URL of the form `encrypted-backup::<repo-name>` (see `man gitremote-helpers`).

### What's New (relative to the original Keybase-only setup)

**Keybase is untouched -- nothing about it was removed.** `scripts/utilities/keybase.rb`
(identity/login-status derivation, repo create/delete/recreate), the Brewfile cask, and
the fresh-install login flow are all still there. Both mechanisms are opt-in per repo,
controlled purely by whether their repo-name env vars are exported in `.shellrc` --
comment out (or leave unset) a pair to disable that mechanism entirely:

```zsh
# Keybase (comment out to disable)
export KEYBASE_HOME_REPO_NAME='home';
export KEYBASE_PROFILES_REPO_NAME='profiles';

# Encrypted backup (comment out to disable)
export ENCRYPTED_HOME_REPO_NAME='home';
export ENCRYPTED_PROFILES_REPO_NAME='browser-profiles';
```

Both pairs are active by default. When both are enabled for the same repo, `fresh-install-of-osx.sh`
tries Keybase first (original mechanism, historical precedence) to perform the actual
clone, then adds the encrypted backup as an additional remote (`origin2`) -- or falls
back to cloning from the encrypted backup if Keybase isn't enabled/available. See
"Vanilla-OS Fresh Install" below for the full sequence.

**Added:**
- `gnupg` (already a base Homebrew dependency)
- `scripts/utilities/encrypted_backup.rb` -- core module (bundle/encrypt/chunk/push, decrypt/unbundle)
- `scripts/git-remote-encrypted-backup` -- the git remote helper itself; this is what makes plain git commands work
- `scripts/setup-encrypted-backup.rb` -- idempotent readiness check (safe to run anytime; the Keychain entry it creates is effectively one-time-per-machine -- see "One-Time-Per-Machine Setup" below)

### How It Works

1. `home` (`~/`) and `browser-profiles` stay ordinary, unencrypted local git repos -- full native history, exactly as before.
2. `git push` (to a remote configured with an `encrypted-backup::<name>` URL) triggers the remote helper, which runs `git bundle create --all` to produce a single-file, complete representation of the repo's history.
3. That bundle is encrypted with `gpg --batch --passphrase-fd 0 --symmetric`, using a passphrase read from the **macOS Keychain** (never stored inside either repo -- see "Why the Keychain, not a file" below).
4. The resulting encrypted blob (`backup.gpg`) is split into 45MB chunks (`backup.gpg.000`, `backup.gpg.001`, ...) -- GitHub hard-rejects any single pushed file over 100MB, and a full-history bundle of a real home directory (scanned documents, PDFs, etc.) can easily exceed that. 45MB (not just "under 100MB") also avoids GitHub's separate 50MB *recommended* threshold, which triggers a non-fatal but alarming-looking "GH001: Large files detected" warning on every push for anything between 50-100MB. All chunks are then committed and pushed to a plain, ordinary **public** GitHub repo (the "wrapper repo"). Still no special transport for *this* push -- just an ordinary `git push` to GitHub, invoked internally by the remote helper.
5. `git pull`/`git fetch` (against the same remote) triggers the reverse: the remote helper fetches the wrapper repo, reassembles the chunks, decrypts with the Keychain passphrase, and imports the resulting bundle's objects directly into your repo's object database (`git bundle unbundle`) -- git itself then handles the merge/rebase, exactly like fetching from any other remote.

**Why the Keychain, not a file:** the passphrase must never live inside `home` or `browser-profiles` themselves -- if it did, you'd need to already have decrypted the backup to get the passphrase needed to decrypt the backup. That's the exact chicken-and-egg problem this design exists to avoid (see `TechnicalDeepDive.md` section 14 for the longer version of this story, including why `git-remote-gcrypt`'s GPG-keypair-based approach fell into the same trap).

**Known limitation, shared with git-remote-gcrypt:** every push replaces the entire backup wholesale, so there's no server-side "reject non-fast-forward" check the way a real git server provides. Git's own pre-push fast-forward check (based on comparing your local branch against what the remote helper reports for `list for-push`) still applies -- fetch/pull before pushing, as always.

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
2. **Rotating the passphrase doesn't retroactively protect old backups.** If the wrapper repo's own git history retains prior commits of `backup.gpg.*`, each old commit stays decryptable with whatever passphrase was active when it was pushed. If you ever rotate the passphrase (e.g. after a suspected compromise), also squash the wrapper repo's own history so old, differently-encrypted chunks don't linger in reachable history: `recreate-repository.rb -f -d <wrapper-repo-dir>`. `recreate-repository.rb`'s built-in "verify file lists match" safety check is weaker protection here than for a typical multi-file repo (the wrapper repo's working tree only ever contains a handful of numbered `backup.gpg.NNN` chunk files), so its force mode automatically detects when `-d` points at a directory under `${XDG_CACHE_HOME}/encrypted-backups/` and runs the actually-relevant check first (`EncryptedBackup.verify_current_blob_decryptable?` -- reassembles the chunks, decrypts, and runs `git bundle verify` on the result), refusing to squash if it fails. This is automatic -- no special flag needed.
3. **`-A` on the Keychain entry is a real, accepted trade-off.** It's required for non-interactive cron/fresh-install use, but it means the passphrase is readable by any process running as your user, not gated behind a Touch ID/password prompt the way a normal Keychain item would be. If that's an unacceptable trade-off for your threat model, this mechanism is not a drop-in equivalent to Keybase's device-key model.
4. **Metadata exposure (repo existence, backup cadence) is unchanged from the accepted trade-offs already documented above and in `TechnicalDeepDive.md` section 14** -- not a new consideration, just restated here for completeness of the security picture.

**Bottom line:** for someone who chooses (and properly stores) a strong, random passphrase and accepts the metadata/revocation trade-offs, this mechanism provides strong confidentiality for the actual backed-up content. It is not a like-for-like replacement for Keybase's full security model -- particularly around metadata privacy and per-device key revocation -- and anyone with a stricter threat model should weigh that before relying on it for genuinely sensitive material.

---

## One-Time-Per-Machine Setup

**Note:** this section covers the encrypted-backup mechanism's setup only. Keybase's
own one-time setup is unchanged from before -- install the cask (automatic if
`KEYBASE_HOME_REPO_NAME`/`KEYBASE_PROFILES_REPO_NAME` are set), then log in (`keybase login`,
either manually or via the non-interactive prompt `fresh-install-of-osx.sh` attempts on
first install). No repo-creation step is needed for Keybase -- it auto-creates personal
repos on push.

### 1. Install gnupg (already in the base Brewfile section)

```bash
brew bundle install;
```

### 2. Ensure the Keychain passphrase is set

```bash
setup-encrypted-backup.rb;
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
the equivalent command yourself first, interactively, in a real terminal -- **this is the
command that actually creates the GPG passphrase entry in the macOS Keychain**:

```bash
security add-generic-password -A -a "${USER}" -s 'gpg-encrypted-backup' -w;
# paste the passphrase when prompted
```

`-A` allows any process to read the entry without a GUI prompt -- required for
non-interactive cron/fresh-install use.

**This is a genuinely per-machine step -- it does not sync via iCloud Keychain, even if iCloud Keychain is enabled and you're signed in on that machine.** Verified directly: `security add-generic-password -h` exposes no flag for `kSecAttrSynchronizable` (the attribute iCloud Keychain sync depends on) -- only account/service/password/access-control options exist. Items created this way go into the local, non-syncing keychain by default. **You must run this exact command again on every new machine**, including during vanilla-OS fresh-install (see below) -- there is no way to carry it over automatically, regardless of iCloud sign-in status.

### 3. Create the two plain GitHub repos (public, empty, one time)

Unlike Keybase (which auto-creates repos on push), a plain `git push` to GitHub requires the target repo to already exist:

```bash
gh repo create "${GH_USERNAME}/${ENCRYPTED_HOME_REPO_NAME:-home}" --public;
gh repo create "${GH_USERNAME}/${ENCRYPTED_PROFILES_REPO_NAME:-browser-profiles}" --public;
```

(Or create them manually at https://github.com/new -- public, no README/gitignore/license.)

### 4. Make `scripts/git-remote-encrypted-backup` available on `PATH`

It already is, if `${DOTFILES_DIR}/scripts` is on your `PATH` (the default `.zshrc` setup does this). Git finds it automatically by name (`git-remote-<scheme>` convention) -- no separate installation step.

---

## Adding Encrypted Backup to a Repo (One-Time, Per Repo)

This is now just plain git commands -- no custom script. The encrypted backup is always
its own separate remote, never fanned into `origin`'s push URLs (see Overview above):

```bash
# If the repo has no 'origin' yet, the encrypted backup can just be 'origin' itself:
git remote add origin encrypted-backup::home;
git push origin --all;

# If the repo already has an 'origin' (e.g. keybase://) you want to keep using too,
# add the encrypted backup as a second, separately-named remote instead:
git remote add origin2 encrypted-backup::home;
git push origin2 --all;
```

Either way, this never touches any *other* remote -- it only adds a new standalone remote
and then bundles/encrypts/pushes to the wrapper repo. `fresh-install-of-osx.sh` does this
automatically after cloning (see `_configure_encrypted_backup_remote`), naming it `origin2`
if `origin` already exists or `origin` itself if it doesn't.

**Verify the restore path works before trusting this** (test on a scratch directory, not your real `${HOME}`):

```bash
ruby -e "require 'encrypted_backup'; require 'env_vars'; EncryptedBackup.clone_and_decrypt(encrypted_repo_name: EnvVars::ENCRYPTED_HOME_REPO_NAME, target_dir: '/tmp/restore-test')";
```

---

## Day-to-Day Usage

**Nothing special -- just use `git push`/`git pull`/`git fetch` (or the `push`/`pull` shell functions, see `git-config.md` for why that distinction matters).** There is no wrapper script involved anymore: `git-remote-encrypted-backup` handles the encrypt/bundle/chunk/push and fetch/decrypt/unbundle transparently, the same way any other remote helper (`git-remote-https`, `git-remote-keybase`, etc.) would.

If both `origin` (e.g. `keybase://`) and `origin2` (`encrypted-backup::...`) are configured
(see Overview above), a plain `git push`/`git pull`/`git fetch` (or the `push`/`pull` shell
functions) only reaches `origin` -- refreshing the encrypted backup is a separate, explicit
`git push origin2`/`git pull origin2`, since the two are kept fully independent rather than
fanned out from a single push. `recreate-repository.rb`'s force-squash-and-push loops over
every configured remote and force-pushes each one individually -- for a `keybase://` remote
specifically, `Keybase.ensure_logged_in` is checked *before* any destructive local operation
(so a login failure is caught before history is squashed away with nowhere to push it), then
`Keybase.recreate_repo` explicitly deletes and recreates the repo (Keybase's own history/
pruning model means a plain force-push there doesn't fully discard old history the way it
does on a real git host, and Keybase does not reliably auto-recreate a repo on push the way
an explicit delete+create does), while every other remote (encrypted-backup, plain GitHub,
etc.) is just force-pushed directly.

**`browser-profiles` needs one exception:** that repo is periodically force-squashed by `recreate-repository.rb`, so an older local checkout and a freshly-squashed remote routinely share no common ancestor -- a plain `git pull` has no way to handle that (it just fails). Rather than a dedicated override script, this repo opts in to reset-instead-of-rebase behavior with a single per-repo git config flag:
```bash
git config --local pull.allowResetOnDivergedHistory true;
```
`pull` (the shell function, `files/--XDG_CONFIG_HOME--/zsh/pull`) checks this flag only if the normal `git pull` fails, and falls back to `GitProcessor#pull_or_reset`, which hard-resets instead of rebasing when it detects diverged history. `fresh-install-of-osx.sh` sets this flag automatically after cloning `browser-profiles`. `${HOME}` never sets it -- it's never squashed, so plain `pull` is sufficient there, and a failed pull is left as a failure (no silent data loss from an unexpected reset).

---

## Vanilla-OS Fresh Install

**Recommended:** set the Keychain passphrase yourself beforehand (see Adoption.md § 3.2) so fresh-install runs start to finish without pausing for input. **Fallback if you forget:** `setup-encrypted-backup.rb` still prompts for it interactively if missing, even when run via the documented bootstrap one-liner (`curl ... | zsh 2>&1 | tee ...`) -- that command pipes stdout through `tee`, which makes `$stdout.tty?` false for the whole script, but the passphrase prompt gates on `Core.tty_available?` (checks `/dev/tty` directly, not `$stdout`) instead, so it still fires correctly: `/dev/tty` refers to the real controlling terminal regardless of stdout/stderr redirection, and `security add-generic-password`'s own prompt (via `getpass(3)`) already talks to `/dev/tty` directly by design. Either way, fresh-install stays fully non-interactive once the passphrase is set (the common case on a re-run). **iCloud Keychain sign-in does not carry the passphrase over automatically** (see "does not sync via iCloud Keychain" note above); it must be set on every new machine, either proactively (recommended) or via this fallback prompt.

**Automated steps:**
1. Homebrew installs -- including `gnupg` always, and the `keybase` cask if `KEYBASE_HOME_REPO_NAME`/`KEYBASE_PROFILES_REPO_NAME` are set.
2. "Setup Keybase" -- if the Keybase env vars are set and the cask is installed, attempts a non-interactive `keybase login` on the true first-time bootstrap (silently syncs on later re-runs if already logged in).
3. "Setup encrypted backup" -- if the encrypted-backup env vars are set, `setup-encrypted-backup.rb` runs, prompting for the passphrase if missing (see above); otherwise silently confirms it's already set and continues.
4. `_clone_home_repo` / `_clone_profiles_repo` try Keybase first (if enabled), falling back to the encrypted backup (if enabled) -- whichever succeeds clones the repo (Keybase: a direct `keybase://` clone; encrypted backup: fetch the plain public wrapper repo over HTTPS, reassemble the `backup.gpg.*` chunks, decrypt with the Keychain passphrase, `git clone` the resulting bundle) -- full history restored either way.
5. Whichever mechanism(s) are enabled then get configured as remotes on the newly-cloned repo -- `origin` for whichever performed the clone, `origin2` for the other if also enabled -- so subsequent `git push`/`git push origin2` (etc.) work against them immediately, with no further setup.
6. SSH keys from the restored home repo become available for every subsequent git operation.

**Disaster recovery scenario:** laptop stolen/dead -> new laptop -> add the Keychain passphrase and/or log into Keybase (interactively if running fresh-install directly, or manually beforehand if using the piped one-liner) -> run `fresh-install-of-osx.sh` -> full recovery.

---

## Troubleshooting

### "No passphrase found in Keychain"

Run the `security add-generic-password` command from the one-time setup section above.

### "Failed to clone ... has the GitHub repo been created yet?"

The plain wrapper repo doesn't exist yet on GitHub. Create it (see step 3 of one-time-per-machine setup) before pushing or restoring.

### "Failed to decrypt ... check the Keychain passphrase is correct"

The Keychain entry has the wrong value, or was created for a different `${USER}`/service name. Re-run:
```bash
security delete-generic-password -a "${USER}" -s 'gpg-encrypted-backup' 2>/dev/null;
security add-generic-password -A -a "${USER}" -s 'gpg-encrypted-backup' -w;
```

---

## Questions

**Q: What if I forget the passphrase?**
A: The encrypted backup is unrecoverable. Store it in a password manager, not just the Keychain (the Keychain is itself lost if the machine is wiped without a working backup).

**Q: Can I rotate the passphrase?**
A: Update the Keychain entry, then push again for each repo -- the next push re-encrypts with whatever passphrase is currently in the Keychain. Old blobs remain decryptable with the old passphrase for as long as they're still reachable in the wrapper repo's own git history (see "Rotating the passphrase doesn't retroactively protect old backups" above) -- squash that history (`recreate-repository.rb -f -d <wrapper-repo-dir>`) if you need old blobs to stop being decryptable with a retired passphrase, e.g. after a suspected compromise.

**Q: Can different repos use different passphrases?**
A: Not with the current implementation -- one Keychain entry (`gpg-encrypted-backup`) is shared by both. Could be extended to per-repo Keychain services if ever needed.

**Q: What does GitHub see?**
A: Repo existence and the wrapper repo's own (trivial) commit history. File names, contents, and structure of the real backup are all inside the opaque encrypted chunks (split into 45MB pieces to stay safely under GitHub's 100MB hard file-size limit and its 50MB "large file" warning threshold -- the chunk boundaries reveal nothing about the real content).

---

## Further Reading

- `TechnicalDeepDive.md` section 14 -- full design rationale, including the rejected `git-remote-gcrypt`/Picocrypt/git-crypt alternatives and why each was ruled out
- `scripts/utilities/encrypted_backup.rb` -- core bundle/encrypt/decrypt implementation
- `scripts/git-remote-encrypted-backup` -- the git remote helper itself
- [gitremote-helpers documentation](https://git-scm.com/docs/gitremote-helpers) -- the protocol the remote helper implements
- [GnuPG documentation](https://www.gnupg.org/documentation/) -- `gpg --symmetric` details
- [git bundle documentation](https://git-scm.com/docs/git-bundle)
