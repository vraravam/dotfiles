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
5. [Lessons Learned](#lessons-learned)

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
cd "${HOME}" && rufo scripts/*.rb        # Ruby
black scripts/*.py                       # Python
prettier --write src/**/*.ts             # TypeScript
```

---

#### 9. Force Push (After Verification)

```bash
# Force push rebased branch (rewrites history)
git push origin feature-branch --force-with-lease

# --force-with-lease is safer than --force:
# - Aborts if remote has changes you don't have locally
# - Prevents accidentally overwriting teammate's work
```

**When to force push:**
- After successful rebase
- After amending commit messages
- After squashing commits

**When NOT to force push:**
- Branch is shared with others (coordinate first)
- Unsure if rebase succeeded (verify first)
- CI is running (wait for it to finish)

---

## Reverse Comparison Technique

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

---

## Related Documentation

- **Feature Parity Checklist**: `.ai/FEATURE-PARITY-CHECKLIST.md` - Post-rebase verification checklist (use after every rebase)
- **Context**: `.ai/context.md` - Historical insights and patterns

---

**Last Updated:** June 16, 2026  
**Source:** Lessons learned from Ruby migration project  
**Status:** Living document (update as new patterns emerge)
