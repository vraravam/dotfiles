---
name: dotfiles-rebase-methodology
description: Use when rebasing a long-running branch onto master, backporting general-purpose improvements from a WIP branch back to master, converting a branch chain (e.g. shell-to-Ruby conversions), catching up a branch chain from its parent, or verifying no functionality was lost after a rebase/merge/squash. Covers forward-rebase mechanics, reverse-comparison technique, feature-parity verification (see FEATURE-PARITY-CHECKLIST.md), and duplication removal.
---

# Rebase and Refactoring Methodology

**Purpose:** General-purpose patterns for rebasing feature branches and large refactorings
**Scope:** Language-agnostic strategies applicable to any major code reorganization
**Source:** Lessons learned from Ruby migration (June 2026) and Nix migration analysis

---

## Table of Contents

1. [Rebase Workflow](#rebase-workflow)
2. [Reverse Comparison Technique](#reverse-comparison-technique)
3. [Feature Parity Verification](#feature-parity-verification)
4. [Duplication Removal](#duplication-removal)
5. [Forward Rebase: Catching Up a Branch Chain from Its Parent](#forward-rebase-catching-up-a-branch-chain-from-its-parent)
6. [Rebasing All Branches: Scope, Order and Handoff](#rebasing-all-branches-scope-order-and-handoff)
7. [Backporting: Bringing Branch Improvements Back to Master](#backporting-bringing-branch-improvements-back-to-master)
8. [Lessons Learned](#lessons-learned)

**See also:** [FEATURE-PARITY-CHECKLIST.md](FEATURE-PARITY-CHECKLIST.md) - Comprehensive post-rebase verification checklist

---

## Rebase Workflow

**Purpose:** Keep feature branch current with main branch's fixes and enhancements

**When to use:**
- Main branch receives bug fixes
- Main branch adds new features
- Main branch updates dependencies
- Before final merge (ensure branch is current)

### Process

#### 1. Reload Branch States

```bash
git fetch --all
git checkout feature-branch
git log --oneline main..HEAD        # See what's unique to this branch
git log --oneline HEAD..main        # See what main has that we don't
```

**Why:** Understand the divergence before starting rebase. Helps estimate conflict resolution time.

---

#### 2. Keep Single Commit on Feature Branch

**RULE:** Feature branches should maintain all changes in a single commit on top of main.

```bash
# If multiple commits exist, squash them before rebase:
git log --oneline main..HEAD    # Check commit count
git reset --soft main            # Move HEAD to main, keep all changes staged
git commit -m "WIP: [feature description] (TODO: testing + CHANGELOG)"

# OR after rebase, if new commits were added:
git rebase -i main              # Mark all but first as 'squash' or 'fixup'
```

**Why:**
- ✅ Clean git history for review (one diff to evaluate)
- ✅ Atomic merge (all changes together or none)
- ✅ Easy to revert if needed (single commit)
- ✅ Simplifies conflict resolution during rebase
- ✅ Clear "before/after" comparison with main

**When to squash:**
- Before initial rebase (consolidate work-in-progress commits)
- After rebase if verification/documentation commits were added
- Before final merge to main

**Commit message content:** The message should describe the branch's actual
content/feature -- it does not need to mention that a rebase or squash
occurred. Rebasing onto an updated main and squashing back down to one commit
is routine git history maintenance, not something worth documenting in the
message itself.

---

#### 3. Execute Rebase

```bash
git rebase main
# Resolve conflicts as they arise
```

**Standard conflict resolution:**
- Read conflict markers carefully
- Test locally after each resolution
- `git rebase --continue` after staging fixes
- `git rebase --abort` if you need to start over

**If `main`'s tip commit was itself amended/rewritten** (not just fast-forwarded with new commits on top -- e.g. `git commit --amend` folded additional changes into a commit the branch was already based on), a plain `git rebase main` replays the branch's commits against the OLD, now-superseded version of that commit and conflicts on every hunk `main`'s amend also touched, even when the branch's own content is completely unaffected by the amend. Use `--onto` to skip replaying the superseded commit entirely:

```bash
# <old-base> is the commit the branch was ACTUALLY based on before main's amend
# (often still resolvable via: git merge-base <branch> <old-main-ref-or-reflog-entry>)
git rebase --onto main <old-base> <branch>
```

This replays only the branch's own commits directly onto the new `main`, without ever touching the superseded intermediate commit -- for branches that don't independently touch the exact lines `main`'s amend changed, this usually eliminates conflicts entirely rather than just resolving them.

---

#### 3a. MANDATORY: Verify No Functionality Is Lost -- Every Branch, Every Time

**Applies whether the rebase reported conflicts or not.** A clean, conflict-free rebase is NOT proof that nothing was lost -- it only proves git could mechanically apply every hunk; it says nothing about whether the *result* still contains everything both sides intended. "It rebased without conflicts" and "nothing was lost" are two different claims, and only the second one matters.

After every rebase (plain or `--onto`), before considering it done, for **every** branch being brought up to date with a new `main`/`master` (not just one flagship branch):

1. **Inherited files must be unaffected.** For any file the branch does NOT independently modify, it must come out byte-identical to `main`:
   ```bash
   git diff main..<branch> -- <file-the-branch-does-not-own>
   # Empty output required -- any diff here means something was lost or altered unexpectedly
   ```

2. **No leftover conflict markers anywhere in the tree** (a manually-resolved conflict can leave a stray marker behind if a hunk was missed):
   ```bash
   grep -rn '^<<<<<<<\|^=======$\|^>>>>>>>' . 2>/dev/null | grep -v '/\.git/'
   ```

3. **Re-run syntax checks on every file the rebase touched** -- conflict resolution can silently break syntax even when git reports a clean, automatic merge:
   ```bash
   zsh -n <each-changed-.sh-or-.zsh-file>
   /usr/bin/ruby -c <each-changed-.rb-file>
   ```

4. **Re-check for reintroduced duplication** if the branch independently added something `main`'s new commits also added (e.g. both sides added a similarly-named helper method/constant for the same purpose). This is the single most common way a "clean" rebase silently loses correctness -- git's automatic merge happily keeps BOTH copies when they don't textually conflict. Grep for the specific symbol/method names touched by `main`'s changes across the branch's own changed files; see [Duplication Removal](#duplication-removal) for resolution patterns once found.

5. **For a chain of branches** (one branch built on top of another -- see [Forward Rebase](#forward-rebase-catching-up-a-branch-chain-from-its-parent)), re-verify the chain relationship still holds after rebasing both:
   ```bash
   git merge-base --is-ancestor parent child && echo "parent is still an ancestor of child: OK"
   ```

---

#### 4. Conflict Resolution Strategy

**General patterns:**

| Scenario | Strategy | Rationale |
|----------|----------|-----------|
| File deleted in branch, modified in main | Skip main's changes | Branch's deletion is intentional (replacement, removal) |
| File modified in both | Merge manually | Both changes likely valuable |
| New file in main | Accept (no conflict) | Branch should have new features |
| File renamed/moved | Update references | Ensure paths point to new locations |

**For refactoring branches (e.g., shell→Ruby, JS→TS):**

| Scenario | Strategy | Rationale |
|----------|----------|-----------|
| Old impl deleted, new impl exists | Skip old impl changes | New impl is source of truth |
| Config files modified in both | Merge carefully | Both may have independent updates |
| Documentation modified in both | Merge carefully | Both may reference different implementations |

---

#### 5. Reverse Comparison (CRITICAL STEP!)

**This is the most important technique for preventing regressions.**

After rebase completes, compare in REVERSE direction to catch missed changes:

```bash
# General pattern: compare main..branch (not branch..main)
git diff main..feature-branch -- <paths>

# Check specific directories
git diff main..feature-branch -- scripts/
git diff main..feature-branch -- src/
git diff main..feature-branch -- lib/

# For refactoring: verify old → new conversions
for old_file in src/*.old_ext; do
  new_file="${old_file%.old_ext}.new_ext"
  if [[ -f "${new_file}" ]]; then
    echo "Comparing ${old_file} (main) with ${new_file} (branch)"
    # Manual review: does new version have all old version features?
  fi
done
```

**Why reverse comparison matters:**

- **Forward comparison** (branch..main): Shows what main has that branch doesn't
- **Reverse comparison** (main..branch): Shows what branch has that main doesn't
- **Git's rebase** resolves conflicts in forward direction (main → branch)
- **Easy to accidentally drop changes** during conflict resolution
- **Reverse comparison ensures** no main functionality was lost

**What to look for:**

- ✅ Functions/methods present in old version but missing in new
- ✅ Configuration keys removed unintentionally
- ✅ Error handling dropped during refactoring
- ✅ Edge cases handled in old but not new
- ✅ Documentation updates in main not reflected in branch

---

#### 6. Feature Parity Verification

**Create systematic comparison document listing:**

- [ ] All command-line arguments supported
- [ ] All idempotency guards present
- [ ] All error handling equivalent or better
- [ ] All user interactions preserved
- [ ] All external tool calls identical behavior
- [ ] All environment variables accessible
- [ ] All configuration options supported

**Document format:**

```markdown
## Feature: [Name]

### Old Implementation (main)
- Location: src/old_file.ext:123
- Behavior: [description]
- Edge cases: [list]

### New Implementation (branch)
- Location: src/new_file.ext:456
- Behavior: [description]
- Status: ✅ Equivalent | ❌ Missing | ✨ Enhanced

### Differences
- [intentional improvements]
- [missing features to backport]
```

**Results should include:**
- ✅ 100% feature coverage verified
- ✅ All differences categorized (missing vs intentional)
- ✅ Clear action items for gaps
- ✅ Documented intentional improvements

**Lessons:**
- Don't assume "it looks right" - systematically verify
- Document analysis (others can review and validate)
- Categorize differences (missing vs enhancement vs intentional)

---

#### 7. Eliminate Duplication (After Rebase)

**CRITICAL STEP** - After all conflicts resolved, before final commit:

Review both old and new implementations and eliminate duplication.

**Common duplication patterns after rebase:**

### Pattern A: Old implementation reimplements new logic

**Problem:** Conflict resolution merged both versions

```python
# Old implementation (kept from main)
def process_data(data):
    # 100 lines of complex logic
    ...

# New implementation (from branch)
class DataProcessor:
    def process(self, data):
        # Same 100 lines but improved
        ...
```

**Fix:** Keep new, remove old (or make old delegate to new)

```python
# Option 1: Remove old entirely (if new is drop-in replacement)

# Option 2: Make old delegate to new (if old is public API)
def process_data(data):
    """Legacy wrapper - use DataProcessor.process() directly."""
    return DataProcessor().process(data)
```

---

### Pattern B: New implementation exists but old still used

**Problem:** Code still calls old API after new implementation merged

```bash
# scripts/run_task.sh still exists and is called
run_task.sh --flag value

# But scripts/run_task.py was created in branch
python run_task.py --flag value
```

**Fix:** Update all call sites, remove old implementation

```bash
# Update callers to use new implementation
python run_task.py --flag value

# Delete old implementation
rm scripts/run_task.sh
```

---

### Pattern C: Circular dependencies (old→new→old)

**Problem:** Old calls new which calls old again

```ruby
# old_util.sh (shell)
def shell_function() {
  ruby -e "require 'new_util'; NewUtil.method"
}

# new_util.rb (Ruby)
def self.method
  system('zsh', '-c', 'shell_function')  # Calls back to shell!
end
```

**Fix:** Eliminate circular call, extract shared logic

```ruby
# new_util.rb
def self.method
  # Direct implementation, no shell call
end

# old_util.sh (if still needed)
def shell_function() {
  ruby -e "require 'new_util'; NewUtil.method"  # One-way delegation
}
```

---

### Duplication Removal Tools

**Find long functions that might be duplicated:**

```bash
# Shell: functions > 20 lines
rg -U "^[a-z_]+\(\) \{" --after-context=20 | rg "^}" | wc -l

# Ruby: methods > 20 lines
rg -U "^\s*def " --after-context=20 | rg "^\s*end" | wc -l

# Python: functions > 20 lines
rg -U "^def " --after-context=20 | rg "^$" | wc -l
```

**Find shell/new-language pairs (potential duplication):**

```bash
# Find files with same basename but different extensions
find scripts -name "*.sh" | while read sh; do
  base="${sh%.sh}"
  for ext in rb py js ts; do
    [[ -f "${base}.${ext}" ]] && echo "Pair: ${sh} + ${base}.${ext}"
  done
done
```

**Find circular references (grep for old names in new files):**

```bash
# Are new Ruby files calling old shell scripts?
rg "system.*\.sh" scripts/*.rb

# Are old shell scripts calling new Ruby scripts?
rg "ruby.*\.rb" scripts/*.sh
```

---

#### 8. Syntax and Format Checks

After all changes complete, verify correctness:

```bash
# Shell scripts
find . -name "*.sh" -exec zsh -n {} \;

# Ruby scripts
find . -name "*.rb" -exec ruby -c {} \;

# Python scripts
find . -name "*.py" -exec python3 -m py_compile {} \;

# Format (language-specific)
rufo scripts/*.rb                         # Ruby
black scripts/*.py                        # Python
prettier --write src/**/*.ts              # TypeScript
```

---

#### 9. Force Push (The User's Step -- Never the Agent's)

A rebase rewrites history, so every rebased branch that already exists on the
remote needs a force-push. **The agent never pushes** (see `.ai/instructions.md`
§ Git State Management Rules): after verifying, it tells the user which
branches changed and the exact command, and the user pushes.

```bash
# Run by the user, once per rebased branch (parents before children):
git push origin <branch> --force-with-lease

# --force-with-lease is safer than --force:
# - Aborts if remote has changes you don't have locally
# - Prevents accidentally overwriting teammate's work
```

**Ready to hand off when:**
- The rebase succeeded and the verification in 3a/5/8 passed
- Every branch in a chain has been rebased *locally* first -- see
  [Rebasing All Branches](#rebasing-all-branches-scope-order-and-handoff) for why

**Not ready (do not hand off) when:**
- Branch is shared with others (coordinate first)
- Unsure if rebase succeeded (verify first)
- CI is running (wait for it to finish)

---

## Reverse Comparison Technique

**See also:** [§ 3a. MANDATORY: Verify No Functionality Is Lost](#3a-mandatory-verify-no-functionality-is-lost----every-branch-every-time) for the concrete, mechanical checklist (byte-identical inherited files, conflict-marker grep, syntax checks, duplication re-check, chain-ancestor check) to run after every rebase, regardless of whether this deeper technique is also needed.

### Why It Matters

**Forward comparison** (what main has): Standard conflict resolution
**Reverse comparison** (what branch has): Regression prevention

**Git's rebase resolves conflicts forward** (main → branch). Easy to:
- ❌ Accept main's version and drop branch's intentional changes
- ❌ Merge both but forget to remove duplication
- ❌ Port changes incompletely
- ❌ Miss edge cases that were fixed in branch

**Reverse comparison catches:**
- ✅ 100% of missed changes
- ✅ Duplicate implementations
- ✅ Incomplete ports
- ✅ Accidentally dropped features

### When To Use

- **After every rebase** (mandatory)
- **After merging conflict-heavy files** (extra verification)
- **Before final testing** (last sanity check)
- **Before force-pushing** (confirm nothing lost)

### Process

1. **Compare full diff in reverse direction**
   ```bash
   git diff main..feature-branch > /tmp/reverse.diff
   # Read entire diff looking for unexpected differences
   ```

2. **Check specific file categories**
   ```bash
   # Source code
   git diff main..feature-branch -- src/ lib/ scripts/

   # Configuration
   git diff main..feature-branch -- config/ .*.yml *.json

   # Documentation
   git diff main..feature-branch -- docs/ *.md
   ```

3. **For refactorings: old→new file pairs**
   ```bash
   # Does new have everything old had?
   # Manual review required - checklist approach
   ```

4. **Verify syntax of changed files**
   ```bash
   git diff main..feature-branch --name-only | \
     xargs -I {} <language-specific-syntax-check> {}
   ```

5. **Document findings**
   - Create `REBASE-VERIFICATION.md`
   - List all differences found
   - Mark each: ✅ Correct | ❌ Regression | ⚠️ Needs review

---

## Feature Parity Verification

### Purpose

Ensure refactored code has 100% feature coverage of original.

### When To Use

- Large refactorings (language migrations, rewrites)
- After reverse comparison identifies differences
- Before marking feature branch "ready for merge"
- When original code is being deleted

### Comparison Dimensions

#### 1. Functional Equivalence

| Aspect | Check |
|--------|-------|
| CLI arguments | All flags/options supported |
| Return codes | Same exit codes for same conditions |
| Output format | Identical (or documented as improved) |
| Side effects | Same files created/modified/deleted |
| Error messages | Equivalent detail and clarity |

#### 2. Non-Functional Equivalence

| Aspect | Check |
|--------|-------|
| Performance | Not significantly slower |
| Memory usage | Not significantly higher |
| Dependencies | No new required tools |
| Compatibility | Works on same platforms |
| Security | No new vulnerabilities |

#### 3. Edge Cases

- Empty input handling
- Large input handling
- Invalid input handling
- Missing dependencies (graceful degradation)
- Network failures (retry logic)
- Filesystem issues (permissions, disk full)

#### 4. Documentation

- Usage examples still valid
- Error message docs updated
- Configuration docs updated
- Migration guide provided (if breaking changes)

### Document Template

```markdown
## Feature Parity Analysis: [Component Name]

### Overview
- **Old:** [path/file.ext]
- **New:** [path/file.ext]
- **Status:** [✅ Complete | 🚧 In Progress | ❌ Missing Features]

### Command-Line Interface

| Flag | Old | New | Status | Notes |
|------|-----|-----|--------|-------|
| `-f` | ✅ | ✅ | ✅ | Identical behavior |
| `-v` | ✅ | ❌ | ❌ | TODO: Implement verbose mode |
| `-h` | ✅ | ✅ | ✨ | Improved help formatting |

### Functionality Checklist

- [ ] Feature A
  - [x] Happy path
  - [x] Edge case 1
  - [ ] Edge case 2 (missing)
- [x] Feature B
- [ ] Feature C (intentionally removed - see rationale below)

### Differences

#### Missing Features
- **Verbose mode (`-v`)**: Not yet implemented. Action: Create issue #123

#### Intentional Changes
- **Feature C removed**: Deprecated in v2.0, no longer needed. Docs updated.

#### Improvements
- **Help formatting**: Uses color, more readable. Backwards compatible.

### Testing Status

- [x] Unit tests pass
- [x] Integration tests pass
- [ ] Manual testing on vanilla OS (pending)
- [ ] Performance benchmarking (pending)

### Sign-Off

- **Author:** [name] (feature-branch)
- **Reviewer:** [name] (reverse comparison)
- **Date:** YYYY-MM-DD
- **Status:** Ready for merge | Blocked on [list issues]
```

---

## Duplication Removal

### Why It's Critical

**Conflict resolution often merges both versions**, creating:
- ❌ Two implementations of same logic
- ❌ Maintenance burden (fix bugs twice)
- ❌ Confusion (which to call?)
- ❌ Performance overhead (duplicate work)

**This must be fixed before merge.**

### Duplication Patterns

See "7. Eliminate Duplication" in Rebase Workflow above for:
- Pattern A: Old reimplements new logic
- Pattern B: New exists but old still used
- Pattern C: Circular dependencies

### Detection Tools

```bash
# Find files with same base name (potential duplication)
find . -type f | sed 's/\.[^.]*$//' | sort | uniq -d

# Find similar functions (fuzzy matching)
# This requires custom tooling per language
# Example: Ruby method signatures
rg "^\s*def \w+" --no-filename | sort | uniq -d

# Find TODO comments left during conflict resolution
rg "TODO|FIXME|XXX" --type-add 'code:*.{sh,rb,py,js}' --type=code
```

### Resolution Strategy

1. **Identify duplicate implementations**
2. **Choose canonical version** (usually: new > old)
3. **Update all call sites** to use canonical version
4. **Remove duplicate** (or make it thin wrapper if public API)
5. **Test** (ensure nothing broke)
6. **Document** (why canonical was chosen)

---

## Forward Rebase: Catching Up a Branch Chain from Its Parent

**Purpose:** Bring a branch up to date with its **parent branch** (not
necessarily `master`) when this repo is using a chain of branches for a large
incremental conversion -- e.g., one branch per file being converted from
shell to Ruby, each branch built directly on top of the previous one in the
chain, and only the final branch eventually merges to `master`.

**Terminology used below:**
- **Target branch** -- the branch you're bringing up to date (e.g., `osx-defaults-ruby`)
- **Parent branch** -- the branch it's built on top of (e.g., `fresh-install-ruby`) -- may or may not be `master`

### Process

1. **Reload parent branch context**
   ```bash
   git -C "${DOTFILES_DIR}" log --oneline <parent-branch> | head -10
   ```
   Review the last ~10 commits on the parent branch before starting, so you
   know what's new.

2. **Rebase and resolve conflicts**
   ```bash
   git -C "${DOTFILES_DIR}" checkout <target-branch>
   git -C "${DOTFILES_DIR}" rebase <parent-branch>
   # resolve conflicts as they arise
   ```

3. **Look for simplification opportunities, not just conflict resolution**
   Even if the rebase reports no conflicts (or the branch appears already
   rebased), separately review the last ~20 commits on the parent branch
   cumulatively for:
   - New utility methods/classes the target branch's conversion could reuse
     instead of duplicating functionality
   - Simplifications now possible in the target branch because of what the
     parent branch added since it last caught up

4. **Verify functional equivalence of the conversion itself**
   For the specific file(s) being converted in the target branch, confirm the
   conversion (e.g., shell -> Ruby) is functionally correct: nothing was added
   that wasn't in the original, and nothing was silently dropped. Use
   [Feature Parity Verification](#feature-parity-verification), the
   [Reverse Comparison Technique](#reverse-comparison-technique), and the
   [mandatory no-loss-of-functionality checklist](#3a-mandatory-verify-no-functionality-is-lost----every-branch-every-time) above.

5. **Verify compliance and static analysis**
   New/changed code must conform to `.ai/domains/`. Run the project's
   syntax/lint checks (`ruby -c`, `rubocop`, `zsh -n`, `shfmt` as applicable --
   see `.ai/domains/edit-checklist.md`) and fix anything the rebase introduced
   or exposed.

6. **Strip file-extension-conversion noise from documentation/comments**
   Undo any documentation or comment changes that exist *only* to describe the
   `.sh` -> `.rb` (or equivalent) extension/format change itself. Keep all
   *other* documentation updates (genuine functional/behavioral changes).
   **Why:** this keeps the diff focused on functional changes plus the docs
   that describe that functionality -- not noise about which file extension
   something currently lives under, which is a transient WIP-branch detail
   until the whole chain merges.

7. **Leave CHANGELOG.md untouched**
   Don't edit `CHANGELOG.md` on a WIP conversion branch -- it should reflect
   real commit history once things land on `master`, not the in-progress
   state of a conversion chain.

8. **Do not stage or commit**
   Make the changes but do not `git add`/`git commit`/amend anything -- the
   user reviews, stages, and amends the branch's single WIP commit manually
   (see `.ai/instructions.md` § Git State Management Rules).

9. **Flag the pending rename for the user's commit message**
   Since staging/committing is the user's job, surface this as a note in your
   summary rather than doing it yourself: the WIP commit message should
   mention that the `.sh` -> `.rb` file extension change still needs to happen
   before this chain merges into `master`.

---

## Rebasing All Branches: Scope, Order and Handoff

**Purpose:** What "rebase all branches" means in this repo, in what order the
work happens, and where the agent's job ends and the user's begins. The
per-branch mechanics are in [Rebase Workflow](#rebase-workflow) and
[Forward Rebase](#forward-rebase-catching-up-a-branch-chain-from-its-parent);
this section covers everything around them.

### 1. Scope

- "All branches" means **every local branch except `master`**, after
  `git fetch --all --prune` (reload from the remote first, since the user may
  have pushed or amended since the last session):
  ```bash
  git -C "${DOTFILES_DIR}" fetch --all --prune
  git -C "${DOTFILES_DIR}" branch --format='%(refname:short)' | grep -v '^master$'
  ```
- That includes standalone single-commit branches (experiments, analysis,
  test branches) as well as members of a conversion chain. Branches already on
  top of the target are reported as such, not silently skipped.
- Before touching anything, record each branch's current tip
  (`git rev-parse <branch>`) and its ahead/behind counts against `master`. The
  old tips are needed for `--onto` below and for proving nothing was lost.

### 2. Order of work across tasks

When a request combines a change on `master` with rebasing and a follow-up
task, the sequence is fixed and each handoff waits for the user:

1. Make the change on `master` (working tree only -- see Git State Management).
2. **Stop and wait** for the user to review, stage, commit and push `master`.
3. Only then rebase the other branches onto the new `master`.
4. **Stop and wait** for the user to force-push the rebased branches.
5. Only then start the next task (for example cutting a new branch from
   `master`). If the user says to hold a task, leave it entirely untouched
   until released -- do not create its branch or edit its files.

### 3. Order within one rebase pass

1. Independent branches (those whose parent is `master`) can go in any order.
2. In a chain, **parent before child**. The child is moved with `--onto`,
   using the parent's *old* tip, because the parent's commit was rewritten and
   a plain `git rebase <parent>` would replay the stale parent commit too:
   ```bash
   git -C "${DOTFILES_DIR}" rebase --onto <rebased-parent> <parent-OLD-tip> <child>
   git -C "${DOTFILES_DIR}" merge-base --is-ancestor <rebased-parent> <child> && echo "chain intact"
   ```
3. The same applies whenever the user amends a parent after the fact: the child
   is stale again and must be moved `--onto` the amended parent (old tip = the
   SHA the child was last based on).
4. If `master`'s own tip is amended (including by the agent -- see section 6),
   every branch is rebased again with `--onto master <old-master-tip>`.
5. `git range-diff <old-tip>...<new-tip>` (or comparing patch-ids) is a quick
   proof that a branch's own commit survived unchanged (`=` for every commit).

### 4. Push handoff

- The agent never pushes or force-pushes. It reports which branches changed
  and gives the user the `--force-with-lease` commands, parents first.
- **Rebase the entire chain locally before the user pushes anything.** Pushing
  a child branch before its parent's final commit exists, or pushing the same
  branch twice, triggers one CI run per pushed commit -- the earlier run is
  then a red/obsolete run against a commit that no longer exists on the branch.
- Leave the working tree on the branch that was checked out when the session
  started (normally `master`) and clean. Any fix the agent was asked to make on
  a WIP branch stays unstaged there for the user to review and amend; say so
  explicitly, with the branch name.

### 5. Resolving conflicts and overlaps

- **Principle: feature parity -- no more, no less, and no duplication.** A conflict is resolved so
  the result has exactly the behavior of both sides, no feature dropped and none
  invented. This is checked with the equivalence methods above, not by eye. The
  principle covers conflict resolution *and* the de-duplication below.
- **Backports land in essence, not literally.** Functionality a branch added
  may since have been reimplemented on `master` or on the parent branch under a
  different name or shape. Build on what the parent already provides: switch the
  branch's callers to the existing implementation and delete the branch's own
  copy instead of keeping two. Search by behavior, not just by name (curl retry
  flags, sudo keep-alive, step counters, notification text, brew wrappers, ...).
- **Adopting the backported version must not change behavior.** The same
  "no more, no less" parity applies when a branch's own copy is replaced by the
  implementation that landed on `master` or the parent: the branch's callers
  must end up behaving exactly as before. Do not take the opportunity to add
  features, defaults, logging or error handling the branch never had, and do not
  drop any the branch did have. Where the backported version differs in
  behavior (different return value, stricter or looser failure handling,
  different output, new side effects), either adapt the call site so the branch
  behaves as before or, if the difference is clearly an improvement, record it
  in the summary as an intentional change for the user to approve.
- **Parity and no duplication hold together.** Neither may be traded for the
  other: after adopting the backported implementation the branch must still
  have exactly one implementation of that behavior (its own copy deleted, every
  caller switched, nothing left behind as an unused or parallel version), and it
  must behave exactly as before. A rebase is not finished while either "less than
  before" or "two copies of the same thing" remains -- verify both explicitly
  (a grep for the removed helper's name and for its behavior, plus the
  equivalence checks above).
- **Tie-breakers when two implementations compete:** prefer whichever is more
  maintainable, faster, correct (bug-free) and better performing, in that
  spirit; if equal, keep the one already on the parent. State the choice in the
  summary so the user can overrule it.

### 6. Conventions must hold on every branch

A clean rebase says nothing about whether the branch's code follows the rules
`master` has since adopted. For each rebased branch (not only the one that
conflicted):

1. Review the branch's own diff against the current `.ai/domains/` rules:
   file naming and headers, syntax (Ruby 2.6 compatibility), formatting
   (`rufo`/`shfmt`), idiomatic constructs (utility helpers instead of raw
   `system`, `Core`/`EnvVars` instead of raw `ENV`/hardcoded paths), logging and
   colorization standards, ASCII-only code, comment philosophy, dual-mode
   structure.
2. Run the syntax checks and the **full spec suite** on each rebased branch,
   without disturbing the user's checkout (for example from a temporary
   `git archive <branch>` export). The UTF-8 file-read spec and similar
   repo-wide specs fail CI on branch-only code that `master` never contained.
3. Report violations per branch. Fixes go on the branch's working tree,
   unstaged, per Forward Rebase steps 7-8 -- the user amends.
4. **If the rule being violated is not written down, it must be added to `master`
   first** -- the `.ai` files are the single source of truth, and branches
   receive them only by rebasing onto `master`. Add the rule to the relevant
   `.ai/domains/*.md` and **amend it into `master`'s tip commit** rather than
   creating a new commit. Leave that commit's message and its `CHANGELOG.md`
   section as they are: they do not mention these documentation additions.
   Then rebase every branch again (section 3, item 4).

## Backporting: Bringing Branch Improvements Back to Master

**Purpose:** While a large incremental conversion (e.g., shell -> Ruby, file
by file) is still in progress across a chain of WIP branches, periodically
pull *generally useful* improvements out of those branches and land them on
`master` directly -- without merging the incomplete conversion work itself.

**Why this matters:** WIP branches accumulate real improvements (comment
fixes, small code changes, formatting, minor refactors) alongside their core
conversion work. `master` shouldn't have to wait for an entire conversion
chain to finish before benefiting from those side improvements.

### Process

1. **Enumerate non-default branches**
   ```bash
   git -C "${DOTFILES_DIR}" branch --format='%(refname:short)' | grep -v '^master$'
   ```

2. **For each branch, get a cumulative diff against master**
   ```bash
   git -C "${DOTFILES_DIR}" diff master..<branch> -- <path>
   ```

3. **Classify each change: backport-eligible or not**
   - **Exclude**: the core conversion of the branch's target file itself (e.g.,
     the actual shell -> Ruby rewrite) -- that's WIP and isn't ready for
     `master` until its own branch is ready to merge.
   - **Include**: anything else that stands on its own and improves
     maintainability if landed on `master` now -- comment fixes, small code
     changes, formatting, generalizable utility improvements, documentation
     corrections.
   - **Never include**: code that would be unused/dead on `master` (i.e., only
     makes sense in the context of the branch's not-yet-merged conversion).

4. **Apply the backport-eligible changes**
   Make the edits directly (don't just list them) so they're ready for review.

5. **Do not stage or commit**
   Same rule as forward rebase: the user manually reviews, stages, and amends
   a single commit on top of `master`. The source WIP branch's own commit is
   not touched -- only the working-tree changes destined for `master` matter here.

6. **Every branch is fair game, regardless of WIP status**
   Don't skip a branch just because it's incomplete/experimental -- its
   backport-eligible subset of changes can still land on `master` now.

---

## Lessons Learned

### What Worked Well

#### Two-Way Sync Strategy

**Keep both branches functional throughout refactoring**

Maintaining both original (main) and refactored (branch) versions in parallel:
- ✅ Main remains production-ready and receives bug fixes
- ✅ Refactored branch evolves without pressure to be "done"
- ✅ Incremental migration (one component at a time)
- ✅ Testing both versions side-by-side
- ✅ Confidence in final merge (both versions proven)

**Key insight:** This is similar to feature flags in production. Both implementations coexist until new version proves equivalent.

---

#### Reverse Comparison Technique

**Caught 100% of potential regressions**

Forward comparison (old → new) checks "does new have what old has?"
Reverse comparison (new → old) checks "did we drop anything?"

**Results from Ruby migration:**
- ✅ Zero missed changes
- ✅ Identified 2 missing features
- ✅ Verified all idempotency guards present
- ✅ Confirmed all error handling equivalent

**This technique should be mandatory for all future refactoring projects.**

---

#### Feature Parity Analysis

**Prevented regressions through systematic comparison**

Created comprehensive comparison documents:
- Feature-by-feature checklist
- Visual summary table
- Specific action items for gaps

**Results:**
- ✅ 100% feature coverage verified
- ✅ All differences categorized (missing vs intentional)
- ✅ Clear action items for gaps
- ✅ Documented intentional improvements

**Lessons:**
- Don't assume "it looks right" - systematically verify
- Document analysis (others can review and validate)
- Categorize differences (missing vs enhancement vs intentional)

---

### What Was Challenging

#### Three-Way Conflict Scenarios

**Multiple parallel refactorings complicate rebase**

**Problem:**
- Main has implementation A
- feature-branch-1 has implementation B (refactored A)
- feature-branch-2 has implementation C (modified A differently)
- Rebasing any two creates conflicts with the third

**Decision:**
- Merge feature-branch-1 → main first
- THEN rebase feature-branch-2 onto updated main
- Avoid three-way conflicts

**Lessons:**
- One major refactoring at a time
- Don't try to merge multiple architectural changes simultaneously
- Sequence matters (finish one, then start next)

---

#### Duplication Removal After Conflicts

**Conflict resolution often merges both versions**

**Problem:**
- Git's conflict resolution keeps both implementations
- Rebase succeeds, but code now has two versions of same logic
- Easy to miss during review (both work independently)

**Solution:**
- Mandatory duplication removal step (step 10 in workflow)
- Systematic search for duplicate implementations
- Tools to detect common patterns
- Manual review of all conflict resolutions

**Added to workflow:**
- Step 10: Remove duplication after conflict resolution
- Detection tools (find pairs, grep for bounces)
- Resolution patterns (choose canonical, remove dup)

**Lessons:**
- Conflict resolution is NOT the final step
- Duplication removal must be systematic, not ad-hoc
- Test after removing duplicates (ensure nothing broke)

---

#### Feature Parity Pressure

**Pressure to declare "done" before truly equivalent**

**Problem:**
- Refactoring takes longer than expected
- Pressure to merge before 100% complete
- Easy to rationalize "close enough"

**Solution:**
- Document missing features explicitly
- Create action items for gaps
- Block merge on critical features only
- Accept enhancements as "better than equivalent"

**Lessons:**
- "Almost done" is a trap - be honest about gaps
- Enhancements are good (better than original counts as parity)
- Block on critical, defer on nice-to-have
- Document decisions (don't leave gaps undocumented)

---

## Summary

### Mandatory Steps

1. ✅ **Single commit** on feature branch (squash before/after rebase)
2. ✅ **Reverse comparison** after every rebase
3. ✅ **Feature parity analysis** for major refactorings
4. ✅ **Duplication removal** after conflict resolution
5. ✅ **Syntax checks** before force-push
6. ✅ **Documentation** of decisions and gaps
7. ✅ **Scope/order/handoff** per [Rebasing All Branches](#rebasing-all-branches-scope-order-and-handoff): every non-`master` branch, parent before child with `--onto`, whole chain rebased before any push, agent never pushes
8. ✅ **Conventions and full spec suite** verified on every rebased branch; missing rules amended into `master`'s tip (message and CHANGELOG unchanged)

### Optional But Recommended

- Two-way sync strategy (parallel development)
- Systematic comparison documents
- Detection tools for common issues
- Sign-off checklist before merge

### Red Flags

- ❌ Multiple commits on feature branch (should be squashed)
- ❌ "Looks right" without verification
- ❌ Conflicts resolved but duplicates not removed
- ❌ Gaps rationalized as "close enough"
- ❌ Three-way merges attempted simultaneously
- ❌ Force-push without reverse comparison
- ❌ The agent pushing, or starting the next task before the user has reviewed/pushed
- ❌ Pushing a child branch before its parent's final commit exists (duplicate, red CI runs)
- ❌ A plain `git rebase <parent>` after the parent's commit was rewritten (replays the stale commit)

---

## Related Documentation

- **Feature Parity Checklist**: `.ai/FEATURE-PARITY-CHECKLIST.md` - Post-rebase verification checklist (use after every rebase)
- **Context**: `.ai/context.md` - Navigation aid and operational reference

---

**Last Updated:** October 10, 2026
**Status:** Living document (update as new patterns emerge)
