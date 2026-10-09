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

### 4.3 Update Brewfile

**When to run:**
- After manually installing packages via `brew install`
- After removing packages

```zsh
# Review current Brewfile
cat "${HOMEBREW_BUNDLE_FILE}";

# Add/remove entries manually (preserves comments and formatting)
# DO NOT use 'brew bundle dump' again — it loses custom formatting

# Commit changes
git -C "${DOTFILES_DIR}" add files/--HOME--/Brewfile;
git -C "${DOTFILES_DIR}" commit -m "Brewfile: add <package>";
git -C "${DOTFILES_DIR}" push;
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
2. If `${PERSONAL_BIN_DIR}/pre-push-<basename>.rb` (or `.sh`) exists and is executable, runs it
3. Non-zero exit blocks the git operation

**Available hooks:** `pre-push`, `pre-commit`, `post-commit`, `post-merge`, `pre-merge-commit` (see `man githooks`)

**IMPORTANT: Git has NO `post-push` hook!** This is intentional design, not a bug.

##### Wrapper Functions for Lifecycle Management

**Problem:** Git has no `post-push` hook, and EXIT traps in `pre-push` fire before git starts pushing.

**Solution:** Wrapper scripts that control the entire operation lifecycle.

**Example: Suspend cron during browser-profiles push**

```zsh
cat > ${PERSONAL_BIN_DIR}/push-browser-profiles.rb << 'EOF'
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cron'
require 'git_commands'
require 'logging'

Logging.run_script do
  # Suspend cron, run the default push, restore cron -- even if the push raises or returns early.
  # header: false because run_script already prints this script's own banner.
  Cron.with_cron_suspended { GitCommands.push(args: ARGV, header: false) }
end
EOF

chmod +x ${PERSONAL_BIN_DIR}/push-browser-profiles.rb;
```

`${PERSONAL_BIN_DIR}` is on `RUBYLIB` (and `RUBYLIB` is set for override scripts launched by `push`/`pull`/`cc`/`upreb`/`run-all.rb`), so `require 'cron'` and `require 'git_commands'` resolve to `scripts/utilities/`.

**Usage:** just type `push` inside the `browser-profiles` directory -- the override is found automatically.

**How `Cron.with_cron_suspended` works:**
1. Suspends cron (backs up current crontab)
2. Yields to the block (the default `push`)
3. Calls `recron` to restore crontab from the tracked file
4. Cleans up the backup file
5. Uses an `ensure` clause, so cron is restored even on an exception or an early `return` inside the block

**When to use wrapper functions vs hooks:**
- **Wrapper:** Need cleanup AFTER operation completes (push/pull with cron suspension)
- **Hook:** Need validation BEFORE operation starts (pre-push tests, pre-commit linting)

#### 4.5.2 Custom Git Aliases (upreb, cc, etc.)

Use **override scripts** in `${PERSONAL_BIN_DIR}` to customise `push`, `pull`, `cc` and `upreb` for a single repo. An override replaces the default implementation; it can call the default back through `GitCommands`.

**Pattern:** `<command>-<repo-basename>.rb` (a `.sh` file is also accepted; a `.rb` file wins if both exist)

**Example: Delete stale tag before upreb in zen-browser-desktop**

```zsh
cat > ${PERSONAL_BIN_DIR}/upreb-zen-browser-desktop.rb << 'EOF'
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'git_commands'
require 'git_processor'
require 'logging'

Logging.run_script do
  git = GitProcessor.new(dir: Dir.pwd)

  # Custom pre-logic: delete stale tag
  git.run_alias('delete-tag', 'twilight') if git.tag_exists?('twilight')

  # Call the default implementation
  GitCommands.upreb(args: ARGV, header: false)
end
EOF

chmod +x ${PERSONAL_BIN_DIR}/upreb-zen-browser-desktop.rb;
```

**How it works:**
1. `push`, `pull`, `cc` and `upreb` are aliases for `scripts/git-command.rb`, which looks for `${PERSONAL_BIN_DIR}/<command>-<repo-basename>.rb` (then `.sh`)
2. If one exists and is executable, it runs *instead of* the default, with the repo as its working directory and only the `--switches` as arguments
3. The override calls `GitCommands.<command>` for the default behaviour and adds its own logic around it
4. `_GIT_OVERRIDE_SKIP=1` is set for the override, so anything it calls (the `git cc`/`git upreb` aliases, `GitCommands`) skips override detection instead of recursing

**Common use cases:**
- `upreb-<repo>.rb` - Custom fetch/rebase/push workflow
- `push-<repo>.rb` - Pre-push validation or cleanup
- `pull-<repo>.rb` - Post-pull actions (submodule update, build trigger)
- `cc-<repo>.rb` - Custom cache cleanup steps

**Template structure:**
1. `require` the utility modules you need (`git_commands`, `git_processor`, `cron`, `logging`)
2. Wrap the body in `Logging.run_script` (depth tracking, timing, summary)
3. Add custom pre-logic before calling `GitCommands.<command>(args: ARGV, header: false)`
4. Add custom post-logic after it

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
# Review conflicts (typically in .shellrc, Brewfile, env_vars.rb)
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
- Your custom Brewfile entries
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
