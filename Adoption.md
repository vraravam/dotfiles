# Adoption Guide

This guide walks through the complete process of adopting this dotfiles system for your own use, from initial setup to ongoing maintenance.

> **⚡ Quick Start:** Already forked and customized? Jump to [§ 3.2 Bootstrap Command](#32-run-bootstrap-command) to copy-paste the installation command.

## 📋 Table of Contents

- [Overview](#overview)
- [Phase 1: Prepare Your Existing Machine](#phase-1-prepare-your-existing-machine)
- [Phase 2: Fork and Customize](#phase-2-fork-and-customize)
- [Phase 3: First-Time Setup](#phase-3-first-time-setup)
- [Phase 4: Ongoing Maintenance](#phase-4-ongoing-maintenance)
- [Phase 5: Keeping Up-to-Date](#phase-5-keeping-up-to-date)

---

## Overview

The adoption process has five phases:

1. **Prepare existing machine** — capture current state (apps, prefs, repos)
2. **Fork and customize** — adapt scripts to your setup
3. **First-time setup** — run on new/wiped machine
4. **Ongoing maintenance** — keep backups current
5. **Keeping up-to-date** — sync with upstream improvements

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

# Set required environment variable for all scripts
export PERSONAL_CONFIGS_DIR="${HOME}/personal/dev/configs"
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
# Generate catalog for all repos under ~/dev (or your PROJECTS_BASE_DIR)
# Replace ~/dev with your actual projects root if it differs
cd /tmp/dotfiles-master
./scripts/resurrect-repositories.rb -g -d ~/dev > "${PERSONAL_CONFIGS_DIR}/repositories-personal.yml"

# Optional: Generate additional catalogs for other project directories
# resurrect-repositories.rb -g -d ~/oss > "${PERSONAL_CONFIGS_DIR}/repositories-oss.yml"
# resurrect-repositories.rb -g -d ~/work > "${PERSONAL_CONFIGS_DIR}/repositories-work.yml"
```

**If you have repos in multiple root folders**, run once per folder with distinct filenames:

```zsh
resurrect-repositories.rb -g -d ~/dev > "${PERSONAL_CONFIGS_DIR}/repositories-personal.yml"
resurrect-repositories.rb -g -d ~/oss > "${PERSONAL_CONFIGS_DIR}/repositories-oss.yml"
resurrect-repositories.rb -g -d ~/work > "${PERSONAL_CONFIGS_DIR}/repositories-work.yml"
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
3. **Do NOT clone yet** — customizations must be done via GitHub web UI first

### 2.2 Required Customizations

**Edit via GitHub web UI** (not locally):

#### A. Update Bootstrap Command

In **[Adoption.md](Adoption.md)** (this file) — find Phase 3.2 and change the `curl` command:

```zsh
# BEFORE (points to vraravam):
export GH_USERNAME='vraravam' DOTFILES_BRANCH='master' ...

# AFTER (points to YOUR_USERNAME):
export GH_USERNAME='YOUR_USERNAME' DOTFILES_BRANCH='master' ...
```

#### B. Update Shell Defaults

In **[files/--HOME--/.shellrc](files/--HOME--/.shellrc)** — change these lines:

```zsh
# REQUIRED: Change to your GitHub username
export GH_USERNAME='YOUR_USERNAME'

# OPTIONAL: Leave as 'master' unless testing a branch
export DOTFILES_BRANCH='master'

# DO NOT CHANGE: Must stay as 'vraravam' (parent repo owner)
export UPSTREAM_GH_USERNAME='vraravam'

# OPTIONAL: Change to your Keybase username, or comment out if not using
export KEYBASE_USERNAME='YOUR_KEYBASE_USERNAME'
```

#### C. Update Ruby Fallback Defaults

In **[scripts/utilities/env_vars.rb](scripts/utilities/env_vars.rb)** — change these lines:

```ruby
# REQUIRED: Change fallback to your GitHub username
GH_USERNAME = ENV.fetch('GH_USERNAME', 'YOUR_USERNAME').freeze

# OPTIONAL: Leave as 'master'
DOTFILES_BRANCH = ENV.fetch('DOTFILES_BRANCH', 'master').freeze

# DO NOT CHANGE: Must stay as 'vraravam'
UPSTREAM_GH_USERNAME = ENV.fetch('UPSTREAM_GH_USERNAME', 'vraravam').freeze

# OPTIONAL: Change fallback to your Keybase username
KEYBASE_USERNAME = _normalize_optional_string(ENV.fetch('KEYBASE_USERNAME', 'YOUR_KEYBASE_USERNAME'))
```

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

#### C. Keybase (Optional)

If **NOT using Keybase**:

1. In **files/--HOME--/.shellrc** — comment out all `KEYBASE_*` lines:
   ```zsh
   # export KEYBASE_USERNAME='...'
   # export KEYBASE_HOME_REPO_NAME='...'
   # export KEYBASE_PROFILES_REPO_NAME='...'
   ```

2. In **scripts/utilities/env_vars.rb** — change fallbacks to empty strings:
   ```ruby
   KEYBASE_USERNAME = _normalize_optional_string(ENV.fetch('KEYBASE_USERNAME', ''))
   KEYBASE_HOME_REPO_NAME = _normalize_optional_string(ENV.fetch('KEYBASE_HOME_REPO_NAME', ''))
   KEYBASE_PROFILES_REPO_NAME = _normalize_optional_string(ENV.fetch('KEYBASE_PROFILES_REPO_NAME', ''))
   ```

The script will skip Keybase-dependent steps silently when these are empty.

### 2.4 Commit Customizations

After making all web UI edits:

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

**Before running the bootstrap command** (for the first time on a new machine), these steps are *recommended* so that the process doesn't error out midway.

On your target machine (fresh or wiped):

1. **If you use `mas` to install apps from the App Store**, login into the `App Store` application before running the script — `mas` cannot authenticate mid-run.
2. Open the `System Preferences` application.
   * Search for 'Full Disk Access' and add 'Terminal' — without this the script cannot read certain protected directories and will error out mid-run.
   * Search for 'File Vault' and turn it on — the script checks for FileVault and exits early if it is off, to avoid setting up a machine with an unencrypted disk.
3. Open the `System Preferences` application.
   * Search for 'Privacy & Security > Accessibility', and enable/approve for the Terminal app (and later for iTerm once its installed) — some macOS automation commands require Accessibility permission to control UI elements.

> Curious how the script works internally? See the [Technical Deep Dive](TechnicalDeepDive.md).

### 3.2 Run Bootstrap Command

```zsh
export GH_USERNAME='vraravam' DOTFILES_BRANCH='master' FIRST_INSTALL='true' CACHE_BUST_HEADERS='true' CURL_RETRY_OPTS='true' COLUMNS="${COLUMNS}"; curl -H "Cache-Control: no-cache, no-store, must-revalidate" -H "Pragma: no-cache" -H "Expires: 0" --retry 5 --retry-delay 10 --retry-max-time 120 --max-time 150 --connect-timeout 30 --retry-connrefused -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/scripts/fresh-install-of-osx.sh?$(date +%s)" | zsh 2>&1 | tee "${HOME}/Downloads/fresh-install-of-osx.log"; unset FIRST_INSTALL
```

Note: Change `vraravam` to your github username in the above command snippet. You can commit this change into your fork so that, for your own machine, you don't need to edit before copy-pasting every time.

**What it does:**

See [README § What the Script Does](README.md#what-the-script-does) for a complete overview. In summary:

1. Downloads and sources `.shellrc` (provides logging and utilities)
2. Installs Homebrew (or updates if already present)
3. Clones dotfiles repo to `${DOTFILES_DIR}` (typically `~/.config/dotfiles`)
4. Runs `install-dotfiles.rb` (symlinks config files)
5. Installs base Brewfile packages (full install continues in background)
6. Runs `post-brew-install.rb` (antidote, mise versions, etc.)
7. **Two-phase preference setup:**
   - Phase 1: `osx-defaults.sh -s` (seeds baseline defaults)
   - Phase 2: `capture-prefs.rb -i` (imports your UI-configured overrides)
8. Sets up cron jobs (falls back: existing → tracked → user action)
9. Resurrects tracked git repositories (from Phase 1.3 catalogs)
10. Prompts for password to set default shell to Homebrew zsh

**Optional shortcut for huge/slow repos:** if you added a `bundle` key for a repo in [Phase 1.3](#13-generate-repository-catalog), transfer the `.bundle` file to this machine (e.g. via AirDrop) to the same path referenced in the YAML. Step 9 above picks it up automatically -- no separate command needed, and no timing to get right: it imports from the bundle if present, otherwise falls back to a normal clone.

### 3.3 Post-Setup Manual Steps

After `fresh-install-of-osx.sh` completes:

#### A. Git Config Includes

Use **[templates/gitconfig-inc.template](templates/gitconfig-inc.template)** to create per-context git configs:

```zsh
# Example: personal and work contexts
cp templates/gitconfig-inc.template ~/.config/git/includes/personal.inc
cp templates/gitconfig-inc.template ~/.config/git/includes/work.inc

# Edit each file with appropriate name, email, signing key
# Then wire into ~/.gitconfig using includeIf
```

**Note:** Personal git config includes are consolidated in `~/.config/git/includes/` following XDG organization principles.

Example `~/.gitconfig` entry:

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
cp templates/ssh-config.template ~/.ssh/config
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
cd ~/.config/dotfiles

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

## Phase 4: Ongoing Maintenance

The backup strategy is **not a one-off activity**. Regular snapshots keep your setup recoverable.

### 4.1 Export Preferences

**When to run:**
- After installing/configuring a new app
- After changing system preferences
- Before major OS upgrade
- Monthly (can be automated via cron)

```zsh
# Export preferences (stages in git, does not commit)
capture-prefs.rb -e

# Review changes
cd "${HOME}"  # or your private configs repo
git status
git diff

# Commit and push
git add .
git commit -m "Preferences backup: $(date +'%Y-%m-%d %H:%M:%S')"
git push
```

### 4.2 Update Repository Catalogs

**When to run:**
- After cloning new repos
- After deleting repos
- Before wiping machine

```zsh
# Regenerate catalog
resurrect-repositories.rb -g -d ~/dev > "${PERSONAL_CONFIGS_DIR}/repositories-personal.yml"

# Review changes
cd "${PERSONAL_CONFIGS_DIR}"
git diff repositories-personal.yml

# Commit and push
git add repositories-personal.yml
git commit -m "Update repo catalog: $(date +'%Y-%m-%d %H:%M:%S')"
git push
```

### 4.3 Update Brewfile

**When to run:**
- After manually installing packages via `brew install`
- After removing packages

```zsh
# Review current Brewfile
cat ~/Brewfile

# Add/remove entries manually (preserves comments and formatting)
# DO NOT use 'brew bundle dump' again — it loses custom formatting

# Commit changes
cd "${DOTFILES_DIR}"
git add files/--HOME--/Brewfile
git commit -m "Brewfile: add <package>"
git push
```

### 4.4 Automated Maintenance via Cron

See [Extras.md — software-updates-cron.rb](Extras.md#software-updates-cronrb) for automated:
- Homebrew updates
- mise version updates
- Git repo updates
- Preference exports
- Repository catalog regeneration

### 4.5 Per-Repository Customizations

Add repository-specific behavior without modifying the core dotfiles. Two patterns are available depending on whether you're customizing built-in git commands or custom aliases.

#### 4.5.1 Built-In Git Commands (push, pull, commit, etc.)

**For BEFORE-only validation:** Use **git hooks** in `~/.config/git/hooks/`
**For lifecycle management (before + after):** Use **wrapper functions**

##### Pre-Validation Hooks

Create per-repository validation scripts in `${PERSONAL_BIN_DIR}` (default: `~/personal/dev/bin`).

**Pattern:** `pre-<command>-<repo-basename>.sh`

**Example: Pre-push validation**

```zsh
cat > ${PERSONAL_BIN_DIR}/pre-push-my-repo.sh << 'EOF'
#!/usr/bin/env zsh
set -euo pipefail
source "${HOME}/.shellrc"

# Validation only - no cleanup needed after push
if ! run_tests; then
  error "Tests failed - blocking push"
  exit 1
fi
EOF

chmod +x ${PERSONAL_BIN_DIR}/pre-push-my-repo.sh
```

**How it works:**
1. Global hook in `~/.config/git/hooks/pre-push` checks for per-repo script
2. If `${PERSONAL_BIN_DIR}/pre-push-<basename>.sh` exists and is executable, runs it
3. Non-zero exit blocks the git operation

**Available hooks:** `pre-push`, `pre-commit`, `post-commit`, `post-merge`, `pre-merge-commit` (see `man githooks`)

**IMPORTANT: Git has NO `post-push` hook!** This is intentional design, not a bug.

##### Wrapper Functions for Lifecycle Management

**Problem:** Git has no `post-push` hook, and EXIT traps in `pre-push` fire before git starts pushing.

**Solution:** Wrapper scripts that control the entire operation lifecycle.

**Example: Suspend cron during browser-profiles push**

```zsh
cat > ${PERSONAL_BIN_DIR}/push-browser-profiles.sh << 'EOF'
#!/usr/bin/env zsh
set -euo pipefail

_SCRIPT_NAME="${0:t}"
source "${ZDOTDIR}/.aliases"

# Load autoload script to get _push function
require_env_var XDG_CONFIG_HOME
load_file_if_exists "${XDG_CONFIG_HOME}/zsh/push"

main() {
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  trap '_decrement_script_depth' EXIT

  local script_start_time="${EPOCHSECONDS}"
  print_script_start

  # Suspend cron, run push, restore cron automatically
  with_cron_suspended _push "$@"

  print_script_summary "${script_start_time}"
}

main "$@"
EOF

chmod +x ${PERSONAL_BIN_DIR}/push-browser-profiles.sh
```

**Usage:**
```bash
cd ~/personal/vijay/browser-profiles
./push-browser-profiles.sh  # or add to PATH and call directly
```

**How `with_cron_suspended` works:**
1. Suspends cron (backs up current crontab)
2. Runs the wrapped function (`_push`)
3. Calls `recron` to restore crontab from tracked file
4. Cleans up backup file
5. Handles errors via EXIT trap - cron is always restored

**When to use wrapper functions vs hooks:**
- **Wrapper:** Need cleanup AFTER operation completes (push/pull with cron suspension)
- **Hook:** Need validation BEFORE operation starts (pre-push tests, pre-commit linting)

#### 4.5.2 Custom Git Aliases (upreb, cc, etc.)

Use **override scripts** in `${PERSONAL_BIN_DIR}` for custom aliases. These must source the corresponding autoload script to get the default implementation.

**Pattern:** `<alias>-<repo-basename>.sh`

**Example: Delete stale tag before upreb in zen-browser-desktop**

```zsh
cat > ${PERSONAL_BIN_DIR}/upreb-zen-browser-desktop.sh << 'EOF'
#!/usr/bin/env zsh
set -euo pipefail

_SCRIPT_NAME="${0:t}"
source "${ZDOTDIR}/.aliases"

# Load autoload script to get _upreb function
require_env_var XDG_CONFIG_HOME
load_file_if_exists "${XDG_CONFIG_HOME}/zsh/upreb"

main() {
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  trap '_decrement_script_depth' EXIT

  local script_start_time="${EPOCHSECONDS}"
  print_script_start

  # Custom pre-logic: delete stale tag
  if git rev-parse -q --verify refs/tags/twilight &>/dev/null; then
    git delete-tag twilight
  fi

  # Call common implementation
  _upreb

  print_script_summary "${script_start_time}"
}

main "$@"
EOF

chmod +x ${PERSONAL_BIN_DIR}/upreb-zen-browser-desktop.sh
```

**How it works:**
1. Git alias checks for override script: `${PERSONAL_BIN_DIR}/upreb-zen-browser-desktop.sh`
2. If exists and executable, sources it instead of running default implementation
3. Override script loads autoload function (`_upreb`) and adds custom logic around it

**Common use cases:**
- `upreb-<repo>.sh` - Custom fetch/rebase/push workflow
- `push-<repo>.sh` - Pre-push validation or cleanup
- `pull-<repo>.sh` - Post-pull actions (submodule update, build trigger)
- `cc-<repo>.sh` - Custom cache cleanup steps

**Template structure:**
1. Source `${ZDOTDIR}/.aliases` to get utility functions
2. Load corresponding autoload script (`load_file_if_exists "${XDG_CONFIG_HOME}/zsh/<alias>"`)
3. Implement `main()` with script infrastructure (depth tracking, timing, summaries)
4. Add custom pre-logic before calling `_<alias>` default implementation
5. Add custom post-logic after calling `_<alias>`

**Available for customization:**
- `upreb` - Update via fetch + rebase
- `push` - Push with custom pre/post logic
- `pull` - Pull with custom post-processing
- `cc` - Cache cleanup with repo-specific steps

**Testing:**
```zsh
# Direct invocation
cd ~/dev/oss/zen-browser-desktop
git upreb

# Via run-all.rb (multi-repo)
all upreb  # Each repo uses its override if it exists
```

---

## Phase 5: Keeping Up-to-Date

Sync with upstream improvements while preserving your customizations.

### 5.1 Recommended Branch Strategy

**Keep all customizations as a single commit on top of upstream.** This makes rebasing trivial.

**Note:** This applies to ongoing maintenance. If you completed Phase 2.4 or Phase 3.3D, you already have a single commit. This section is for when you've made additional changes over time.

```zsh
cd "${DOTFILES_DIR}"

# View your customization commit
git log --oneline upstream/master..HEAD
# Should show: 1 commit (or more if you've made changes since initial adoption)

# If you have multiple commits, squash them:
git rebase -i upstream/master
# Mark all but first as 'squash' or 'fixup'
```

### 5.2 Sync with Upstream

```zsh
cd "${DOTFILES_DIR}"

# Fetch latest changes
git fetch --all

# Rebase your customizations on top
git upreb  # alias for: git rebase upstream/master && git push --force-with-lease
```

**If there are conflicts:**

```zsh
# Review conflicts (typically in .shellrc, Brewfile, env_vars.rb)
git status

# Edit conflicted files
# Stage resolved files
git add <file>

# Continue rebase
git rebase --continue

# Force push (your fork is rebased)
git push --force-with-lease
```

### 5.3 Alternative: Cherry-Pick Your Changes

If you have many commits to catch up to and prefer a clean slate:

```zsh
cd "${DOTFILES_DIR}"

# Save your customization commit hash
latest_head="$(git rev-parse HEAD)"

# Hard reset to upstream
git reset --hard upstream/master

# Apply your customization commit
git cherry-pick "${latest_head}"

# Resolve conflicts if any
git status
# Edit conflicted files, then:
git add <file>
git cherry-pick --continue

# Force push
git push --force-with-lease
```

### 5.4 Review Diffs

Before pushing, verify your customizations are preserved:

```zsh
# Diff against your fork's remote (shows upstream changes you're adopting)
git diff @{u}

# Diff against upstream (shows only your customizations)
git diff upstream/master
```

**The second diff should show ONLY:**
- Your usernames in Adoption.md (bootstrap command), .shellrc, env_vars.rb
- Your custom Brewfile entries
- Your path adjustments

### 5.5 Post-Update Steps

After syncing with upstream:

1. **Run install-dotfiles.rb** to propagate symlink changes:
   ```zsh
   install-dotfiles.rb
   ```

2. **Check CHANGELOG.md** for version-specific instructions:
   ```zsh
   # Look for post-update steps for new versions
   less "${DOTFILES_DIR}/CHANGELOG.md"
   ```

3. **Restart Terminal** to reload configs:
   ```zsh
   # Quit Terminal/iTerm, then reopen
   ```

4. **Verify everything works**:
   ```zsh
   # Check shell functions load
   type is_shellrc_sourced

   # Check aliases load
   alias ll

   # Check git aliases work
   git st

   # Check mise versions load
   mise current
   ```

### 5.6 Testing Branch Changes

To test upstream changes on a branch before merging to your master:

```zsh
# In your fork (via GitHub web UI or locally):
# Change DOTFILES_BRANCH='master' to DOTFILES_BRANCH='test-branch'
# in Adoption.md (bootstrap command) and files/--HOME--/.shellrc

# Run bootstrap command with your test branch:
export GH_USERNAME='YOUR_USERNAME' DOTFILES_BRANCH='test-branch' ...
```

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

**Symptom:** Bootstrap fails with "GitHub username not set"

**Fix:** Edit `files/--HOME--/.shellrc` and `scripts/utilities/env_vars.rb` before running fresh-install (see [Phase 2.2](#22-required-customizations))

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
