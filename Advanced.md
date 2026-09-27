# Advanced Guide

This guide covers ongoing maintenance and long-term upkeep of your dotfiles fork,
once you've completed initial setup via **[Adoption.md](Adoption.md)**.

> **New to this system?** Start with [Adoption.md](Adoption.md) instead -- it covers
> preparing your machine, forking, and running the bootstrap command. Come back here
> once you're up and running and want to keep things current over time.

## 📋 Table of Contents

- [Phase 4: Ongoing Maintenance](#phase-4-ongoing-maintenance)
- [Phase 5: Keeping Up-to-Date](#phase-5-keeping-up-to-date)

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
capture-prefs.rb -e;

# Review changes (or your private configs repo instead of ${HOME})
git -C "${HOME}" status;
git -C "${HOME}" diff;

# Commit and push
git -C "${HOME}" add .;
git -C "${HOME}" commit -m "Preferences backup: $(date +'%Y-%m-%d %H:%M:%S')";
git -C "${HOME}" push;
```

### 4.2 Update Repository Catalogs

**When to run:**
- After cloning new repos
- After deleting repos
- Before wiping machine

```zsh
# Regenerate catalog
resurrect-repositories.rb -g -d "${PROJECTS_BASE_DIR}" > "${PERSONAL_CONFIGS_DIR}/repositories-personal.yml";

# Review changes
git -C "${PERSONAL_CONFIGS_DIR}" diff repositories-personal.yml;

# Commit and push
git -C "${PERSONAL_CONFIGS_DIR}" add repositories-personal.yml;
git -C "${PERSONAL_CONFIGS_DIR}" commit -m "Update repo catalog: $(date +'%Y-%m-%d %H:%M:%S')";
git -C "${PERSONAL_CONFIGS_DIR}" push;
```

### 4.3 Update Nix Packages / Homebrew Casks

**When to run:**
- After wanting a new CLI tool (add it to `nix/modules/packages.nix`) or GUI app (add
  it to `nix/darwin-configuration.nix`'s `homebrew.casks`)
- After removing one

```zsh
# Review current package/cask lists
"${EDITOR}" "${DOTFILES_DIR}/nix/modules/packages.nix";
"${EDITOR}" "${DOTFILES_DIR}/nix/darwin-configuration.nix";

# Add/remove entries manually, then apply immediately to verify:
nixup;

# Commit changes
git -C "${DOTFILES_DIR}" add nix/modules/packages.nix nix/darwin-configuration.nix;
git -C "${DOTFILES_DIR}" commit -m "nix: add <package/cask>";
git -C "${DOTFILES_DIR}" push;
```

### 4.4 Automated Maintenance via Cron

See [Extras.md — software-updates-cron.rb](Extras.md#software-updates-cronrb) for automated:
- Nix package + Homebrew cask updates (`darwin-rebuild switch`)
- mise version updates
- Git repo updates
- Preference exports
- Repository catalog regeneration

### 4.5 Per-Repository Customizations

Add repository-specific behavior without modifying the core dotfiles. Two patterns are available depending on whether you're customizing built-in git commands or custom aliases.

#### 4.5.1 Built-In Git Commands (push, pull, commit, etc.)

**For BEFORE-only validation:** Use **git hooks** in `${XDG_CONFIG_HOME}/git/hooks/`
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

chmod +x ${PERSONAL_BIN_DIR}/pre-push-my-repo.sh;
```

**How it works:**
1. Global hook in `${XDG_CONFIG_HOME}/git/hooks/pre-push` checks for per-repo script
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

chmod +x ${PERSONAL_BIN_DIR}/push-browser-profiles.sh;
```

**Usage:**
```bash
push-browser-profiles.sh "${PERSONAL_PROFILES_DIR}";  # or add to PATH and call directly
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

chmod +x ${PERSONAL_BIN_DIR}/upreb-zen-browser-desktop.sh;
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
git -C "${PROJECTS_BASE_DIR}/oss/zen-browser-desktop" upreb;

# Via run-all.rb (multi-repo)
all upreb;  # Each repo uses its override if it exists
```

---

## Phase 5: Keeping Up-to-Date

Sync with upstream improvements while preserving your customizations.

### 5.1 Recommended Branch Strategy

**Keep all customizations as a single commit on top of upstream.** This makes rebasing trivial.

**Note:** This applies to ongoing maintenance. If you completed Phase 2.4 or Phase 3.3D, you already have a single commit. This section is for when you've made additional changes over time.

```zsh
# View your customization commit
git -C "${DOTFILES_DIR}" log --oneline upstream/master..HEAD;
# Should show: 1 commit (or more if you've made changes since initial adoption)

# If you have multiple commits, squash them:
git -C "${DOTFILES_DIR}" rebase -i upstream/master;
# Mark all but first as 'squash' or 'fixup'
```

### 5.2 Sync with Upstream

```zsh
# Fetch latest changes
git -C "${DOTFILES_DIR}" fetch --all;

# Rebase your customizations on top
git -C "${DOTFILES_DIR}" upreb;  # alias for: git rebase upstream/master && git push --force-with-lease
```

**If there are conflicts:**

```zsh
# Review conflicts (typically in .shellrc, nix/darwin-configuration.nix, env_vars.rb)
git -C "${DOTFILES_DIR}" status;

# Edit conflicted files
# Stage resolved files
git -C "${DOTFILES_DIR}" add <file>;

# Continue rebase
git -C "${DOTFILES_DIR}" rebase --continue;

# Force push (your fork is rebased)
git -C "${DOTFILES_DIR}" push --force-with-lease;
```

### 5.3 Alternative: Cherry-Pick Your Changes

If you have many commits to catch up to and prefer a clean slate:

```zsh
# Save your customization commit hash
latest_head="$(git -C "${DOTFILES_DIR}" rev-parse HEAD)";

# Hard reset to upstream
git -C "${DOTFILES_DIR}" reset --hard upstream/master;

# Apply your customization commit
git -C "${DOTFILES_DIR}" cherry-pick "${latest_head}";

# Resolve conflicts if any
git -C "${DOTFILES_DIR}" status;
# Edit conflicted files, then:
git -C "${DOTFILES_DIR}" add <file>;
git -C "${DOTFILES_DIR}" cherry-pick --continue;

# Force push
git -C "${DOTFILES_DIR}" push --force-with-lease;
```

### 5.4 Review Diffs

Before pushing, verify your customizations are preserved:

```zsh
# Diff against your fork's remote (shows upstream changes you're adopting)
git -C "${DOTFILES_DIR}" diff @{u};

# Diff against upstream (shows only your customizations)
git -C "${DOTFILES_DIR}" diff upstream/master;
```

**The second diff should show ONLY:**
- Your GitHub username in the bootstrap command (Adoption.md § Phase 3.2)
- Your custom nix package/cask entries
- Your path adjustments

### 5.5 Post-Update Steps

After syncing with upstream:

1. **Run install-dotfiles.rb** to propagate symlink changes:
   ```zsh
   install-dotfiles.rb;
   ```

2. **Check CHANGELOG.md** for version-specific instructions:
   ```zsh
   # Look for post-update steps for new versions
   less "${DOTFILES_DIR}/CHANGELOG.md";
   ```

3. **Restart Terminal** to reload configs:
   ```zsh
   # Quit Terminal/iTerm, then reopen
   ```

4. **Verify everything works**:
   ```zsh
   # Check shell functions load
   type is_shellrc_sourced;

   # Check aliases load
   alias ll;

   # Check git aliases work
   git st;

   # Check mise versions load
   mise current;
   ```

### 5.6 Testing Branch Changes

To test upstream changes on a branch before merging to your master, just export
`DOTFILES_BRANCH` alongside `GH_USERNAME` in the bootstrap command itself -- no file
edits needed (mirrors how `GH_USERNAME` doesn't need pre-configuring either; see
`.shellrc`'s explanatory note near the top):

```zsh
export GH_USERNAME='YOUR_USERNAME' DOTFILES_BRANCH='test-branch' ...
```

**Re-running on an already-cloned machine**: `fresh-install-of-osx.sh` derives
`DOTFILES_BRANCH` automatically from `${DOTFILES_DIR}`'s currently checked-out branch
if not explicitly exported -- so once you `git checkout test-branch` locally in
`${DOTFILES_DIR}`, subsequent re-runs pick it up without needing to export anything.

---

## 📚 Additional Resources

- **[Adoption.md](Adoption.md)** -- Initial setup, forking, and the bootstrap command
- **[README.md](README.md)** -- Project overview and features
- **[Extras.md](Extras.md)** -- Detailed documentation for each utility script
- **[TechnicalDeepDive.md](TechnicalDeepDive.md)** -- Internal architecture and design decisions
- **[CHANGELOG.md](CHANGELOG.md)** -- Version history and upgrade notes

---
