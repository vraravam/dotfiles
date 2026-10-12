---
applyTo: "**/*"
name: dotfiles-git-workflow
description: Use when about to stage, commit, branch, rebase, or amend in this dotfiles repo, or when verifying a branch is functionally complete before commit -- covers staging/commit/branch/rebase permission rules and the pre-commit functional completeness check.
---

# Git Workflow Rules

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

These rules govern any operation that changes git state. The default workflow is that the user reviews and stages changes manually.

**Related files**:
- [`changelog.md`](./changelog.md) - Changelog and commit-message rules
- [`../REBASE-AND-REFACTORING-METHODOLOGY.md`](./../REBASE-AND-REFACTORING-METHODOLOGY.md) - Long-running branch rebase methodology

## Git State Management Rules — Mandatory

**DO NOT modify Git state (staging area, commits, branches, remotes) without explicit permission from the user.**

**DEFAULT WORKFLOW: The user reviews and stages changes manually.**

After making edits:
1. ✅ Make the requested edits to files
2. ✅ Show `git status` or `git diff` to display what changed
3. ❌ **STOP** - Do NOT stage, commit, or modify git state
4. ✅ Let the user review changes and stage manually

### Staging Rules

**DO NOT stage, unstage, add, reset, or restore files without explicit permission.**

**Prohibited without permission:**
- `git add <file>` — stages a file
- `git add -A` — stages all changes
- `git add .` — stages all changes in current directory
- `git reset <file>` — unstages a file
- `git restore --staged <file>` — unstages a file
- `git restore <file>` — discards unstaged changes
- `git checkout -- <file>` — discards unstaged changes
- `git rm <file>` — stages a deletion
- `git stash` — stashes changes
- `git stash pop` — applies stashed changes
- Any other command that modifies the index/staging area

**Why this matters:**
- Users manually review all changes before staging
- Users may stage specific hunks or files for different commits
- Automatically staging destroys the user's deliberate staging intent
- Mixing unrelated changes into a single commit breaks atomic commit principles
- The staging area reflects the user's workflow decisions

**Correct workflow:**
1. Make edits to files as requested
2. Verify syntax (if applicable)
3. Show `git status` or `git diff` to display what changed
4. **STOP** - User will stage manually

**Exception:** When the user explicitly says "stage these files", "stage everything", "commit all changes", or similar clear intent to modify staging state, then staging commands are permitted.

### Commit Rules

**DO NOT create, amend, or modify commits without explicit permission.**

**Prohibited without permission:**
- `git commit` — creates a new commit
- `git commit -a` — stages and commits all tracked changes
- `git commit --amend` — modifies the last commit
- `git rebase` — rewrites commit history
- `git reset --soft/--mixed/--hard` — moves HEAD and potentially discards commits
- `git cherry-pick` — applies commits from other branches
- Any other command that creates or modifies commits

**Why this matters:**
- Commits are permanent snapshots in the repository history
- Commit messages must be authored by the user, not generated automatically
- Users may want to review staged changes before committing
- The timing of commits is part of the user's workflow

**Correct workflow:**
1. Make edits and stage files (with explicit permission)
2. Show `git diff --cached` to display what will be committed
3. Ask the user if they want to commit and what message to use
4. Only after explicit permission: run `git commit` with user-provided message

**Verifying an amend:** This check only applies once an amend has already been explicitly
authorized and performed -- it is a post-amend verification step, not something to run
speculatively beforehand. After running `git commit --amend`, diff the pre-amend commit
against the new one using the reflog: `git diff HEAD@{1} HEAD` (the reflog entry
immediately before an amend is always `HEAD@{1}`). This confirms the amend contains
exactly the intended staged changes -- nothing more, nothing less -- and is more reliable
than eyeballing `git status`/`git log` alone, since it directly compares the resulting
tree rather than the commit metadata. Prefer this over `git diff @{u}` (diff against the
upstream tracking branch): `@{u}` only equals "the state before the amend" when the local
branch and its upstream have not diverged. If the local branch has any unpushed commits,
or the remote has commits the local branch doesn't (e.g. `ahead 1, behind 1`),
`git diff @{u}` conflates that divergence with the amend's own effect, making it an
unreliable signal -- `git diff HEAD@{1} HEAD` is correct regardless of upstream state.
This check is narrow and mechanical: it only confirms the git *operation* did what was
asked (folded in exactly the staged changes). It does NOT verify that the *content* of
those changes is functionally correct -- e.g. that a conflict resolution preserved both
branches' logic. For that, see the separate checklist under Rebase Rules below.

**Exception:** When the user explicitly says "commit with message X", "create a commit", or similar clear intent, then `git commit` is permitted.

### Branch Management Rules

**DO NOT switch branches, create branches, or modify branch state without explicit permission.**

**Prohibited without permission:**
- `git checkout <branch>` — switches branches
- `git switch <branch>` — switches branches
- `git checkout -b <branch>` — creates and switches to new branch
- `git branch -d <branch>` — deletes a branch
- `git branch -D <branch>` — force-deletes a branch
- `git merge <branch>` — merges branches
- `git rebase <branch>` — rebases current branch
- Any other command that changes the current branch or branch state

**Why this matters:**
- Users may be working on a specific branch intentionally
- Switching branches can lose uncommitted work
- Creating branches should be a deliberate decision
- Branch operations affect the entire repository state

**Correct workflow:**
1. Work on the current branch the user has checked out
2. If a different branch is needed, inform the user and ask permission
3. Only after explicit permission: run branch commands

**Exception:** When the user explicitly says "switch to branch X", "checkout branch X", or similar clear intent, then branch commands are permitted.

### Rebase Rules

**When rebasing branches, ensure code quality is maintained or improved.**

After completing any rebase (whether manual conflict resolution or automated):

1. **No functional loss**: All functionality from both branches must be preserved
2. **No duplication**: Avoid duplicate implementations of the same logic
3. **No loss in modularity**: Keep extracted modules separate; don't inline them back
4. **No degradation in maintainability**: Code should be clearer after rebase, not harder to understand
5. **Documentation must be updated**: All references to renamed/moved files must be updated in docs, configs, and scripts

**Conflict resolution guidelines:**
- When both branches add the same file with different implementations:
  - Choose the more modular/maintainable version
  - If both have unique improvements, merge the best of both
- When both branches modify the same file:
  - Preserve all new functionality from both sides
  - Remove any duplicated code introduced by the merge
  - Ensure naming and structure remain consistent
- When file references change (e.g., `.sh` → `.rb`):
  - Update all references to use the newest file name
  - Verify documentation, configs, and scripts are all updated

**Verification after rebase:**
- Check for duplicate functions/methods (same logic in multiple places)
- Verify all file references point to correct files
- Ensure no functionality was lost in conflict resolution
- Run syntax checks on all modified files

**See also:** [FEATURE-PARITY-CHECKLIST.md](../FEATURE-PARITY-CHECKLIST.md) for comprehensive post-rebase verification workflow. This checklist verifies *content* correctness (no lost functionality, no duplication); it is separate from the mechanical `git diff HEAD@{1} HEAD` amend-verification check above, which only confirms a `git commit --amend` folded in exactly the intended staged changes.

**For this repo's branch-chain conversion workflows specifically**, see
[REBASE-AND-REFACTORING-METHODOLOGY.md](../REBASE-AND-REFACTORING-METHODOLOGY.md):
- § Forward Rebase: Catching Up a Branch Chain from Its Parent -- when a branch
  needs to catch up with its parent branch (not necessarily `master`)
- § Backporting: Bringing Branch Improvements Back to Master -- when
  general-purpose improvements on a WIP branch should land on `master` now,
  without merging that branch's incomplete conversion work
- § Rebasing All Branches: Scope, Order and Handoff -- what "rebase all
  branches" covers, the order of work (master change, user review and push,
  rebase, user force-push, next task), parent-before-child `--onto`, and why the
  agent never pushes

### Pre-Commit Verification — Functional Completeness Check

**Before creating or amending any commit, verify functional completeness of the changed code.**

This applies to:
- New branches with conversion work (shell → Ruby, refactoring, etc.)
- Branches being rebased or merged
- Any commit that modifies executable scripts or modules

**Required verification steps:**

1. **Syntax check all modified files**
   ```bash
   # Ruby files
   find scripts -name "*.rb" -type f -exec /usr/bin/ruby -c {} \;

   # Shell files
   find scripts -name "*.sh" -type f -exec zsh -n {} \;
   ```

2. **Verify all dependencies exist**
   ```ruby
   # Check all require_relative statements resolve to existing files
   ruby -e "
   Dir['scripts/**/*.rb'].each do |script|
     File.readlines(script).each do |line|
       if line =~ /^require_relative ['\"](.*)['\"]$/
         required = \$1
         path = required.start_with?('utilities/') ? \"scripts/#{required}.rb\" : \"scripts/#{required}.rb\"
         unless File.exist?(path)
           puts \"❌ MISSING: #{script} requires #{required}\"
         end
       end
     end
   end
   "
   ```

3. **Verify method calls match definitions**
   - Extract all module method calls: `Module.method_name`
   - Verify each method exists in the target module
   - Check class vs instance method usage (don't call instance methods as class methods)

4. **Test script invocation**
   ```bash
   # Verify main scripts run without errors (at least --help)
   /usr/bin/ruby scripts/script-name.rb --help
   ```

5. **Check cross-script references**
   - Verify any `system(RUBY_BIN, script.to_s, ...)` calls reference existing scripts
   - Verify dual-mode modules (module + `if __FILE__ == $PROGRAM_NAME`) are correctly structured

**Why this matters:**
- Prevents broken commits that fail at runtime
- Catches method signature mismatches (class vs instance)
- Ensures all dependencies are tracked in the branch
- Reduces debugging time after merge/rebase

**When to run:**
- Before `git commit` or `git commit --amend` on WIP branches
- After completing a rebase or merge
- When switching between branches with different conversion states

**Checklist for WIP conversion branches:**
```bash
# Example: nix-migration branch
cd ${HOME}/.config/dotfiles
git checkout nix-migration

# 1. Syntax check all Ruby files
for file in $(find scripts -name "*.rb" -type f); do
  /usr/bin/ruby -c "${file}" || echo "❌ FAILED: ${file}"
done

# 2. Check dependencies
ruby -e "..." # (see step 2 above)

# 3. Verify method calls (manual or scripted)
# 4. Test main script
/usr/bin/ruby scripts/fresh-install-of-osx.rb --help

# 5. Verify external script references exist
grep -E "system.*\.rb|RUBY_BIN.*\.rb" scripts/fresh-install-of-osx.rb
# Check that each referenced script exists
```

**Exception:** This verification is not required for documentation-only changes (`.md` files, comments).
