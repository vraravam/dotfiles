# Adoption Guide

This guide walks through adopting this dotfiles system for your own use: preparing
your machine, forking, and running the bootstrap command. This is the **basic**
path -- it's all you need to get a fully working setup.

> **⚡ Quick Start:** Already forked and customized? Jump to [§ 3.2 Bootstrap Command](#32-run-bootstrap-command) to copy-paste the installation command.

> **Already up and running?** See **[Advanced.md](Advanced.md)** for ongoing
> maintenance (keeping backups current, per-repo git customizations) and staying
> in sync with upstream improvements.

## 📋 Table of Contents

- [Overview](#overview)
- [Phase 1: Prepare Your Existing Machine](#phase-1-prepare-your-existing-machine)
- [Phase 2: Fork and Customize](#phase-2-fork-and-customize)
- [Phase 3: First-Time Setup](#phase-3-first-time-setup)

---

## Overview

The basic adoption process has three phases:

1. **Prepare existing machine** — capture current state (apps, prefs, repos)
2. **Fork and customize** — adapt scripts to your setup
3. **First-time setup** — run on new/wiped machine

Once you're up and running, see **[Advanced.md](Advanced.md)** for ongoing
maintenance and keeping your fork in sync with upstream.

### Two Adoption Scenarios

- **Fresh machine** (vanilla macOS) → Skip Phase 1, start at Phase 2
- **Existing pre-configured machine** → Start at Phase 1 to capture current state

---

## Phase 1: Prepare Your Existing Machine

**Skip this phase if:** You're starting on a fresh/wiped machine with nothing to capture.

**Purpose:** Capture the state of your current machine so `fresh-install-of-osx.sh` can restore it faithfully on the new one.

**Important:** At this stage, you haven't installed the dotfiles yet. Download the entire repository as a zip to get all scripts and dependencies.

### 1.0 Download Scripts

Download the repository as a zip file to get all scripts:

```zsh
# Download and extract repository
cd /tmp
curl -fsSL https://github.com/vraravam/dotfiles/archive/refs/heads/master.zip -o dotfiles.zip
unzip -q dotfiles.zip
cd dotfiles-master

# Set required environment variables for all scripts
export PERSONAL_CONFIGS_DIR="${HOME}/personal/dev/configs"
export PROJECTS_BASE_DIR="${HOME}/dev"
mkdir -p "${PERSONAL_CONFIGS_DIR}"
```

Now you have all scripts available in `/tmp/dotfiles-master/scripts/`.

**Note:** GitHub's zip archives preserve executable permissions, so scripts are immediately runnable.

### 1.1 Export Homebrew Package List

If you already use Homebrew, dump your installed packages to avoid starting from scratch:

```zsh
brew bundle dump --force --file="${HOME}/Brewfile"
```

**Important:** This is a **one-time** command. If you regenerate later, any custom comments/formatting will be lost. After the first dump, maintain the Brewfile manually.

### 1.2 Export Application Preferences

Run `capture-prefs.rb` to export preferences:

```zsh
cd /tmp/dotfiles-master
./scripts/capture-prefs.rb -e

# Files are exported to ${PERSONAL_CONFIGS_DIR}/defaults/
# Verify they're there:
ls -la "${PERSONAL_CONFIGS_DIR}/defaults/"
```

**What gets exported:**
- System preferences (Finder, Dock, Mission Control, etc.) as `.plist` and `.defaults` files
- Application preferences (iTerm, VS Code, etc.)
- Files are exported to `${PERSONAL_CONFIGS_DIR}/defaults/` (ready to be committed to your home git repo)
- Filters out machine-specific IDs, display geometry, ephemeral state

**Note**: The `find_and_append_prefs` function is not available at this stage (it requires `.shellrc` to be installed). To add new app preferences, manually edit the downloaded `capture-prefs-allowed-list.txt` file before running the export.

### 1.3 Generate Repository Catalog

Generate YAML catalogs of all git repos you want to restore:

```zsh
# Generate catalog for all repos under ${PROJECTS_BASE_DIR} (default: ~/dev)
cd /tmp/dotfiles-master
./scripts/resurrect-repositories.rb -g -d "${PROJECTS_BASE_DIR}" > "${PERSONAL_CONFIGS_DIR}/repositories-personal.yml"

# Optional: Generate additional catalogs for other project directories
# ./scripts/resurrect-repositories.rb -g -d "${PROJECTS_BASE_DIR}/oss" > "${PERSONAL_CONFIGS_DIR}/repositories-oss.yml"
# ./scripts/resurrect-repositories.rb -g -d "${PROJECTS_BASE_DIR}/work" > "${PERSONAL_CONFIGS_DIR}/repositories-work.yml"
```

**If you have repos in multiple root folders**, run once per folder with distinct filenames:

```zsh
cd /tmp/dotfiles-master
./scripts/resurrect-repositories.rb -g -d "${PROJECTS_BASE_DIR}" > "${PERSONAL_CONFIGS_DIR}/repositories-personal.yml"
./scripts/resurrect-repositories.rb -g -d "${PROJECTS_BASE_DIR}/oss" > "${PERSONAL_CONFIGS_DIR}/repositories-oss.yml"
./scripts/resurrect-repositories.rb -g -d "${PROJECTS_BASE_DIR}/work" > "${PERSONAL_CONFIGS_DIR}/repositories-work.yml"
```

**After generation:**
1. Review the YAML files
2. Set `active: true` only for repos you want resurrected on a fresh machine
3. Add `post_clone` commands if specific repos need them (e.g., `npm install`)

**Optional: bundle export for huge/slow repos.** If a repo is very large (deep history, gigabytes of objects), you can bypass a slow/unreliable network clone on the new machine by adding a `bundle` key to its entry in the YAML (see [Extras.md § Bundle support](Extras.md#bundle-support)):

```yaml
- folder: "${PROJECTS_BASE_DIR}/oss/<repo-name>"
  remote: git@github.com:you/<repo-name>
  bundle: "${HOME}/Downloads/<repo-name>.bundle"
  active: true
```

Then export it (from this old machine's healthy clone):

```zsh
resurrect-repositories.rb -b "${PERSONAL_CONFIGS_DIR}/repositories-oss.yml"
```

Transfer the resulting `.bundle` file to the new machine yourself (AirDrop, USB drive, etc.) to the same path referenced in `bundle` above — it is not committed to the dotfiles repo (only the YAML's `bundle` key/path is). Timing doesn't matter: if it isn't there yet when [Phase 3.2](#32-run-bootstrap-command)'s resurrect step runs, that repo just falls back to a normal network clone.

### 1.4 Commit and Push

Store your captured state in a git repository at `${HOME}`. These files contain personal preferences and repo locations — never commit to a public repository.

```zsh
cd "${HOME}"
git add Brewfile personal/dev/configs/
git commit -m "Backup: $(date +'%Y-%m-%d %H:%M:%S')"
git push
```

**Cleanup:**
```zsh
# Remove downloaded scripts
rm -rf /tmp/dotfiles-master /tmp/dotfiles.zip
```

---

## Phase 2: Fork and Customize

### 2.1 Fork the Repository

1. Go to https://github.com/vraravam/dotfiles
2. Click "Fork" button

That's it for forking. See § 2.2 for the one thing you'll need to provide
when you run Phase 3.2, and § 2.3 for genuinely optional file customizations.

### 2.2 What You Actually Need to Provide

There is no GitHub web UI edit, no file to change, and no squash-commit dance
required before you can run Phase 3.2. There is exactly one thing you supply,
and you supply it **in the command itself** when you run it (see
[Phase 3.2](#32-run-bootstrap-command)), the same way you'd pass a parameter
to any other installer:

- **`GH_USERNAME`** -- your own GitHub username, in place of `vraravam` in the
  `export GH_USERNAME='vraravam' ...` line. This is unavoidable: the command
  has to know which fork to clone before anything exists locally to derive it
  from. On a **new/vanilla machine there is nothing cloned yet, so you provide
  it there too** -- same as the very first time, every time you set up a
  different machine. The one thing you never need to do is provide it again
  on a machine that's already set up: re-running it there derives the value
  automatically from that machine's own local clone's `origin` remote.
- **Encrypted backups** (`gpg` + `git bundle`) -- optional, and not required in
  advance either; if you want it, see [§ 2.3.C](#c-encrypted-backup-optional)
  below for the one-time GitHub repo creation and Keychain passphrase setup.

If you'd rather not retype your username every time you copy-paste the
command, commit the substitution into your own fork's copy of this file once
(see [Phase 3.2](#32-run-bootstrap-command)) -- but that's a convenience, not
a requirement.

### 2.3 Optional Customizations

#### A. Path Structure

In **[files/--HOME--/.shellrc](files/--HOME--/.shellrc)** — adjust to match your preferred folder layout:

```zsh
# Root folder for all git repos
export PROJECTS_BASE_DIR="${HOME}/dev"

# Personal scripts and executables
export PERSONAL_BIN_DIR="${HOME}/personal/dev/bin"

# Private config files and repo catalogs
export PERSONAL_CONFIGS_DIR="${HOME}/personal/dev/configs"

# Browser profile backups
export PERSONAL_PROFILES_DIR="${HOME}/personal/${USER}/browser-profiles"
```

**If you change `PROJECTS_BASE_DIR`**, also update **[files/--HOME--/custom.gitignore](files/--HOME--/custom.gitignore)**:
- Update `/dev/` entry in "HOME DIRECTORY TOP-LEVEL FOLDERS" section
- Update all `/dev/**/` entries in "DEV WORKSPACE" section

#### B. Brewfile

Review **[files/--HOME--/Brewfile](files/--HOME--/Brewfile)** and remove unwanted packages.

**If you exported from an existing machine (Phase 1.1):**

1. Locate the `FIRST_INSTALL` guard comment in the fork's Brewfile (currently around line 63, but may shift)
2. Keep everything BEFORE that line (base packages needed for vanilla OS)
3. Replace everything AFTER that line with your exported Brewfile contents
4. This merges your packages with the minimal base set needed for bootstrap

**If starting fresh (no existing machine):**
- Review the entire Brewfile and remove any packages you don't want

#### C. Encrypted Backup (Optional)

The encrypted-backup mechanism (`gpg` + `git bundle`, see [TechnicalDeepDive.md § 14](TechnicalDeepDive.md#14-adding-an-encrypted-backup-gpg--git-bundle-alongside-keybase)) backs up `~` and `${PERSONAL_PROFILES_DIR}` to encrypted blobs in plain public GitHub repos, **alongside Keybase, not instead of it** -- if a repo still has a live `keybase://` `origin`, it keeps being pushed to normally on every push, in addition to this. **Before relying on this for sensitive data**, read [KEYBASE_MIGRATION.md § Is This as Secure as Keybase?](KEYBASE_MIGRATION.md#is-this-as-secure-as-keybase) -- it's a genuine, honest comparison, not a "yes, don't worry" reassurance. In short: strong given a high-entropy passphrase, but not a like-for-like replacement (weaker metadata privacy, no per-device key revocation).

**If using it:**

1. Adjust the repo names if desired in **files/--HOME--/.shellrc** (defaults shown):
   ```zsh
   export ENCRYPTED_HOME_REPO_NAME='home'
   export ENCRYPTED_PROFILES_REPO_NAME='browser-profiles'
   ```
2. Create the two plain, public, empty GitHub repos (one time):
   ```bash
   gh repo create "${GH_USERNAME}/${ENCRYPTED_HOME_REPO_NAME}" --public
   gh repo create "${GH_USERNAME}/${ENCRYPTED_PROFILES_REPO_NAME}" --public
   ```
3. Ensure the Keychain passphrase is set (one-time-per-machine -- see below):
   ```bash
   setup-encrypted-backup.rb
   ```
   This is idempotent and safe to run anytime. If the passphrase is missing and this is
   running interactively, it prompts you for one via `security add-generic-password`'s own
   masked, double-entry confirmation prompt -- generate a strong value and save it in your
   password manager when prompted (never commit it anywhere). The passphrase never touches
   this script or Ruby process memory/argv -- `security` handles the prompt and storage
   directly. **The [§ 3.2 bootstrap command](#32-run-bootstrap-command) pipes `curl` straight
   into `zsh` and has no terminal to prompt you with**, so if you're using this feature, set
   the passphrase yourself beforehand -- see the note right before that command.

   **This does not sync via iCloud Keychain, even if iCloud Keychain is enabled and you're signed in.** `security add-generic-password` has no flag for the `kSecAttrSynchronizable` attribute that iCloud Keychain sync depends on (confirmed via `security add-generic-password -h` -- only account/service/password/access-control options are exposed), so this item is local-only by design. **You must repeat the one-time Keychain setup (or re-run `setup-encrypted-backup.rb` interactively) on every new machine** -- there is no way to carry it over automatically.

**If NOT using it:** do nothing extra. `fresh-install-of-osx.sh` checks for the Keychain passphrase, and the clone/backup steps log an error and continue (non-fatal to the rest of fresh-install) if it's absent -- no env vars need to be commented out.

#### D. CI Badges (Optional)

The badges at the top of **[README.md](README.md)** (Lint, RSpec, codecov,
Bundler Audit) hardcode `vraravam/dotfiles` in their URLs -- they show the
CI status of the **original** repo until you update them to point at your
own fork:

- **Lint / RSpec / Bundler Audit**: replace `vraravam` with your GitHub
  username in each `https://github.com/vraravam/dotfiles/actions/workflows/...`
  URL. These work immediately -- no account/token setup needed, since they
  just link to your fork's own GitHub Actions runs.
- **codecov**: also replace `vraravam` with your username in the
  `https://codecov.io/gh/vraravam/dotfiles/...` URLs, then sign in to
  [codecov.io](https://codecov.io) with your GitHub account, add your fork,
  and add the resulting token as a repository secret named `CODECOV_TOKEN`
  (Settings → Secrets and variables → Actions). Until you do this, the
  coverage upload step in `rspec.yml` fails silently (`fail_ci_if_error:
  false`) and the badge shows "unknown" -- the test run itself is unaffected.

If you don't care about the badges reflecting your own fork's status, skip
this entirely -- nothing else in the setup depends on it.

### 2.4 Commit Customizations (If You Made Any)

If you made any of the **optional** edits in § 2.3 above, commit them via the
GitHub web UI (or locally, then push) before proceeding to Phase 3.
If you didn't change anything, skip straight to [Phase 3](#phase-3-first-time-setup).

1. **Option A (Recommended): Squash into single commit**
   - GitHub web UI: Create pull request from your fork's master to itself
   - Use "Squash and merge" option
   - Commit message: `"Initial customization for YOUR_USERNAME"`
   - Delete the temporary branch after merge

2. **Option B: Leave as multiple commits**
   - Just commit each change via GitHub web UI
   - Multiple commits remain in history

**Why squash?**
- **Easier rebasing**: When pulling upstream updates, a single customization commit has fewer conflicts than scattered edits
- **Cleaner history**: Your fork's changes are one logical unit (your customizations)
- **Simpler cherry-picking**: If you need to re-apply customizations, one commit is easier to manage

**When NOT to squash:**
- You want to preserve granular edit history
- You're comfortable resolving multi-commit rebase conflicts

**After squashing, verify via GitHub web UI:**
- Go to your fork's commits page: `https://github.com/YOUR_USERNAME/dotfiles/commits/master`
- Should see one customization commit on top of upstream commits

---

## Phase 3: First-Time Setup

### 3.1 Pre-Flight Checklist

**Before running the bootstrap command** (for the first time on a new machine), do these on your target machine (fresh or wiped). Two of them are **hard requirements** -- the script will error out or abort without them -- the rest are conditional or soft recommendations.

**Required (the script will fail without these):**

1. Open the `System Preferences` application.
   * Search for 'Full Disk Access' and add 'Terminal' — **required**: without this the script cannot read certain protected directories and **will error out mid-run**.
   * Search for 'File Vault' and turn it on — **required**: the script explicitly **checks for FileVault and exits early** if it is off, to avoid setting up a machine with an unencrypted disk.

**Conditional (only if it applies to you):**

2. **If you use `mas` to install apps from the App Store**, login into the `App Store` application before running the script — `mas` cannot authenticate mid-run.

**Recommended (won't block the script, but some steps work better with it):**

3. Open the `System Preferences` application.
   * Search for 'Privacy & Security > Accessibility', and enable/approve for the Terminal app (and later for iTerm once its installed) — some macOS automation commands require Accessibility permission to control UI elements. If skipped, the script continues; you'll be reminded to review this manually in Phase 3.2's post-setup summary.

> Curious how the script works internally? See the [Technical Deep Dive](TechnicalDeepDive.md).

### 3.2 Run Bootstrap Command

**If you're using the optional encrypted-backup feature ([§ 2.3 C](#c-encrypted-backup-optional)):**
set the Keychain passphrase now, in this terminal, before running the command below. The
bootstrap command pipes `curl` straight into `zsh`, so it has no terminal to prompt you with
once it's running -- this is the only chance to do it interactively ahead of time:
```bash
security add-generic-password -A -a "$USER" -s 'dotfiles-encrypted-backup' -w
```
(paste a strong passphrase from your password manager when prompted; skip this if you're not
using the encrypted-backup feature -- `fresh-install-of-osx.sh` logs a non-fatal error and
continues without it either way).

```zsh
export GH_USERNAME='vraravam' DOTFILES_BRANCH='keybase-migration' FIRST_INSTALL='true' CACHE_BUST_HEADERS='true' CURL_RETRY_OPTS='true' COLUMNS="${COLUMNS}"; curl -H "Cache-Control: no-cache, no-store, must-revalidate" -H "Pragma: no-cache" -H "Expires: 0" --retry 5 --retry-delay 10 --retry-max-time 120 --max-time 150 --connect-timeout 30 --retry-connrefused -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/scripts/fresh-install-of-osx.sh?$(date +%s)" | zsh 2>&1 | tee "${HOME}/Downloads/fresh-install-of-osx.log"; unset FIRST_INSTALL
```

Note: This command is ready to copy-paste-run as-is on `vraravam`'s own machines.
If you forked this repo, replace `vraravam` with your own GitHub username and
commit that change into your fork, so it's likewise ready to copy-paste-run
for you every time, without editing first.

**What it does:**

In summary:

1. Downloads and sources `.shellrc` (provides logging and utilities)
2. Installs Homebrew (or updates if already present)
3. Clones dotfiles repo to `${DOTFILES_DIR}` (typically `~/.config/dotfiles`)
4. Runs `install-dotfiles.rb` (symlinks config files)
5. Installs base Brewfile packages (full install continues in background) -- each
   formula/cask handles its own post-install needs via Brewfile `postinstall:` hooks
   (e.g. antidote's hook regenerates the plugin bundle)
6. **Two-phase preference setup:**
   - Phase 1: `osx-defaults.sh -s` (seeds baseline defaults)
   - Phase 2: `capture-prefs.rb -i` (imports your UI-configured overrides)
7. Sets up cron jobs (falls back: existing → tracked → user action)
8. Resurrects tracked git repositories (from Phase 1.3 catalogs)
9. Prompts for password to set default shell to Homebrew zsh

**Optional shortcut for huge/slow repos:** if you added a `bundle` key for a repo in [Phase 1.3](#13-generate-repository-catalog), transfer the `.bundle` file to this machine (e.g. via AirDrop) to the same path referenced in the YAML. Step 8 above picks it up automatically -- no separate command needed, and no timing to get right: it imports from the bundle if present, otherwise falls back to a normal clone.

### 3.3 Post-Setup Manual Steps

After `fresh-install-of-osx.sh` completes:

#### A. Git Config Includes

Use **[templates/gitconfig-inc.template](templates/gitconfig-inc.template)** to create per-context git configs:

```zsh
# Example: personal and work contexts
cp "${DOTFILES_DIR}/templates/gitconfig-inc.template" "${XDG_CONFIG_HOME}/git/includes/personal.inc"
cp "${DOTFILES_DIR}/templates/gitconfig-inc.template" "${XDG_CONFIG_HOME}/git/includes/work.inc"

# Edit each file with appropriate name, email, signing key
# Then wire into ${XDG_CONFIG_HOME}/git/config using includeIf
```

**Note:** Personal git config includes are consolidated in `${XDG_CONFIG_HOME}/git/includes/` following XDG organization principles.

Example `${XDG_CONFIG_HOME}/git/config` entry:

```ini
[includeIf "gitdir:~/dev/personal/"]
  path = ~/.config/git/includes/personal.inc

[includeIf "gitdir:~/dev/work/"]
  path = ~/.config/git/includes/work.inc
```

See [git conditional includes documentation](https://git-scm.com/docs/git-config#_conditional_includes) for full syntax.

#### B. SSH Config

**Timing**: Do this after fresh-install completes (SSH directory and permissions will be set up by the script).

Use **[templates/ssh-config.template](templates/ssh-config.template)** to create `~/.ssh/config`:

```zsh
cp "${DOTFILES_DIR}/templates/ssh-config.template" ~/.ssh/config
# Edit with your key paths and host aliases
```

**Note:** `install-dotfiles.rb` automatically inserts `Include "./global_config"` — do not add manually.

#### C. System Preferences (Optional)

- Displays → Set scaling/resolution
- Full Disk Access → Add iTerm, zoom.us
- Camera/Microphone → Add browsers (Brave, Firefox, Zen), zoom.us
- Default web browser → Set preference
- iCloud → Login and enable Desktop sync

#### D. Squash Customization Commits (Recommended)

**Timing**: After `fresh-install-of-osx.sh` completes successfully and you've verified everything works.

**Why now?** Your fork is now cloned to `${DOTFILES_DIR}` (~/.config/dotfiles), making it easy to squash locally.

```zsh
cd "${DOTFILES_DIR}"

# Check current history
git log --oneline -20

# Count how many customization commits you made (e.g., 5)
# Squash them into one commit:
git reset --soft HEAD~5  # Adjust number to match your commits
git commit -m "Initial customization for YOUR_USERNAME"

# Force push to your fork (this rewrites history)
git push --force-with-lease origin master
```

**Benefits:**
- Easier rebasing when pulling upstream updates
- Cleaner history (one logical customization commit)
- Simpler conflict resolution

**Alternative:** If you already squashed via GitHub web UI (Phase 2.4 Option A), skip this step.

#### E. Restart Terminal

Quit and restart Terminal/iTerm to load all new configs.

---

## Ongoing Maintenance and Staying Up-to-Date

Once you're up and running, see **[Advanced.md](Advanced.md)** for:

- Exporting preferences and updating repository catalogs over time
- Maintaining the Brewfile and automating tasks via cron
- Per-repository git customizations (hooks, wrapper functions, alias overrides)
- Syncing your fork with upstream improvements

---

## 🆘 Troubleshooting

### Script Fails Mid-Run

The script is **idempotent** — re-run the same command. It will skip completed steps and resume where it failed.

### Homebrew Installation Hangs

- Check internet connection
- Try setting `HTTP_PROXY` / `HTTPS_PROXY` if behind corporate firewall
- Run `brew doctor` after installation completes

### Preferences Not Importing

- Check that `osx-defaults.sh -s` ran first (baseline seed)
- Verify backup repo is cloned and has `.plist`/`.defaults` files
- Check `capture-prefs.rb -i` output for specific errors
- Ensure backup is not stale (check timestamp warning)

### Cron Jobs Not Created

- Check `recron` function output during fresh-install
- Verify crontab template exists: `cat "${PERSONAL_CONFIGS_DIR}/crontab.txt"`
- Manually create: `create_crontab "${PERSONAL_CONFIGS_DIR}/crontab.txt"`
- Install: `recron`

### Git Repos Not Resurrecting

- Verify catalog files exist: `ls "${PERSONAL_CONFIGS_DIR}"/repositories-*.yml`
- Check that repos have `active: true` in YAML
- Review `resurrect-repositories.rb -r` output for errors
- Manually clone missing repos

### Missing GH_USERNAME

**Symptom:** Bootstrap fails with `GH_USERNAME is not set and could not be derived from ...`

**Fix:** This happens whenever `${DOTFILES_DIR}` doesn't exist locally yet --
the very first run on any given machine, vanilla or not. Export it in the
bootstrap command itself: `export GH_USERNAME='your-username' ...` (see
[Phase 3.2](#32-run-bootstrap-command)). Once that machine has cloned the repo,
every later run on **that same machine** derives `GH_USERNAME` automatically
from its local clone's git remote -- but a different/new machine starts from
scratch again and needs it exported, same as this one did.

### Wrong DOTFILES_DIR

**Symptom:** Scripts can't find files, require_relative fails

**Fix:** Either:
1. Use default location `~/.config/dotfiles` (recommended)
2. Set `DOTFILES_DIR` in bootstrap command AND update `.shellrc` before running

### Custom Paths Not Respected

**Symptom:** Scripts create directories in default locations instead of custom paths

**Fix:** Customize path variables in `.shellrc` after forking but BEFORE running the bootstrap scripts (see [Phase 2.3](#23-optional-customizations))

---

## 📚 Additional Resources

- **[Advanced.md](Advanced.md)** — Ongoing maintenance and staying up-to-date with upstream
- **[README.md](README.md)** — Project overview and features
- **[Extras.md](Extras.md)** — Detailed documentation for each utility script
- **[TechnicalDeepDive.md](TechnicalDeepDive.md)** — Internal architecture and design decisions
- **[CHANGELOG.md](CHANGELOG.md)** — Version history and upgrade notes
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — Guidelines for contributing code

---

## 🙏 Questions?

- Open a GitHub Discussion for general questions
- Open a GitHub Issue for bugs or feature requests
- See CONTRIBUTING.md for how to report issues effectively
