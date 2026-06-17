# Feature Parity Checklist: Branch Rebase from Master

**Purpose:** Ensure no functionality is lost when rebasing a feature branch from an updated master/main branch.

**When to use:** After rebasing any long-running feature branch onto master, especially when the rebase involved conflict resolution or significant divergence.

---

## Pre-Rebase Preparation

Before starting the rebase, document:

1. **Branch purpose**: What feature/refactoring does this branch implement?
2. **Key files changed**: List all modified/added/deleted files
3. **Critical functionality**: What must still work after rebase?
4. **Known conflicts**: Which files are likely to conflict with master?

---

## Post-Rebase Verification Checklist

### 1. Code Quality ✅

- [ ] **No syntax errors**: All scripts parse cleanly in their target interpreters
  ```bash
  # Shell scripts
  find . -name "*.sh" -o -name "*.zsh" | xargs -I {} zsh -n {}
  
  # Ruby scripts
  find . -name "*.rb" | xargs -I {} ruby -c {}
  ```

- [ ] **No duplicate code**: Same logic not implemented in multiple places
  ```bash
  # Look for duplicate function names
  rg "^def |^function " --no-filename | sort | uniq -d
  ```

- [ ] **Module separation preserved**: Extracted modules remain separate (not inlined back)
- [ ] **No anti-patterns introduced**: Check for `$LOAD_PATH` hacks, hardcoded paths, etc.
- [ ] **Consistent naming**: Variables/functions follow established conventions

### 2. Functionality ✅

- [ ] **All features present**: Compare feature list before/after rebase
- [ ] **External tool calls intact**: Commands that invoke system tools unchanged
- [ ] **Environment variables accessible**: All required env vars still available
- [ ] **Error handling preserved**: Traps, rescue blocks, cleanup hooks still present
- [ ] **Idempotency maintained**: Guards that skip already-completed work still present
- [ ] **User interactions preserved**: Prompts, confirmations, output messages unchanged

### 3. Documentation ✅

- [ ] **File references updated**: All docs point to correct file paths
- [ ] **Renamed files tracked**: If files were renamed, all references updated
- [ ] **Examples still valid**: Code examples in docs match actual implementation
- [ ] **Inline comments accurate**: Comments describe current behavior (not stale)
- [ ] **README consistency**: Main docs reflect current state of both branches

### 4. Conflict Resolution Quality ✅

When conflicts occurred during rebase:

- [ ] **Both sides' improvements kept**: Merged best of both implementations
- [ ] **No silent feature loss**: Didn't blindly accept one side and lose the other's work
- [ ] **Conflict markers removed**: No `<<<<<<<`, `=======`, `>>>>>>>` left in code
- [ ] **Logical consistency**: Merged code makes sense (no Frankenstein functions)
- [ ] **Test both code paths**: If both branches added conditional logic, both paths work

### 5. Dependencies & Imports ✅

- [ ] **Require/import statements correct**: All dependencies still loadable
- [ ] **Module paths valid**: Relative paths didn't break with file moves
- [ ] **No circular dependencies**: Rebase didn't introduce import loops
- [ ] **External gems/packages present**: Third-party deps still available

### 6. Configuration Files ✅

- [ ] **Config references updated**: Scripts point to correct config file locations
- [ ] **Template files current**: If templates exist, they match new structure
- [ ] **Environment files synced**: `.envrc`, `.env` files have required variables
- [ ] **Gitignore/attributes current**: Ignore rules cover new file types/locations

---

## Testing Strategy

### Automated Checks

1. **Syntax validation**: Run all scripts through their interpreters with `-c`/`-n`
2. **Static analysis**: Run linters (shellcheck, rubocop) on modified files
3. **Grep for issues**: Search for common problems:
   ```bash
   # Shell: Check for unquoted variables
   rg '\$[A-Z_]+[^"{]' --type sh
   
   # Ruby: Check for require without relative/gem
   rg '^require [^_]' --type ruby
   
   # Both: Check for hardcoded paths
   rg '/(usr|bin|etc|opt)/' --type sh --type ruby
   ```

### Manual Verification

1. **Dry run**: Execute scripts with dry-run flags (if available)
2. **Review diff**: `git diff master..HEAD` - scan for unexpected changes
3. **Check history**: `git log master..HEAD --oneline` - verify commit messages
4. **Compare file lists**: Ensure no accidental deletions
   ```bash
   # Files only in master (deleted in branch?)
   git diff --name-only --diff-filter=D master..HEAD
   
   # Files only in branch (added)
   git diff --name-only --diff-filter=A master..HEAD
   ```

### Integration Testing

- [ ] **Test on target environment**: Run scripts on the intended OS/setup
- [ ] **Test idempotency**: Run twice, second run should skip completed work
- [ ] **Test error paths**: Trigger failures, verify cleanup runs
- [ ] **Test with real data**: Use actual config files, repos, etc. (not mocks)

---

## Common Pitfalls

### ❌ Don't Do This

1. **Blindly accepting master's version**: Just because master is newer doesn't mean it's right for this branch
2. **Blindly accepting branch's version**: Branch may be stale and missing master's improvements
3. **Deleting conflicted sections**: Both sides might be necessary
4. **Ignoring test failures**: "I'll fix it later" = technical debt
5. **Skipping documentation updates**: Stale docs are worse than no docs

### ✅ Do This Instead

1. **Read both versions**: Understand what each side was trying to achieve
2. **Merge intelligently**: Take best parts of both, remove duplication
3. **Test each fix**: Don't accumulate multiple unverified changes
4. **Update docs immediately**: While context is fresh in your mind
5. **Ask for clarification**: If unsure which version is correct

---

## Sign-Off Template

After completing verification, document your findings:

```markdown
## Rebase Verification: [Branch Name]

**Date:** YYYY-MM-DD
**Rebased from:** master @ commit [hash]
**Rebased onto:** master @ commit [hash]
**Conflicts resolved:** [count]

### Feature Parity: ✅ / ⚠️ / ❌

- [ ] All features from branch preserved
- [ ] All improvements from master incorporated
- [ ] No functionality lost in conflict resolution
- [ ] Documentation updated for renamed/moved files

### Code Quality: ✅ / ⚠️ / ❌

- [ ] No syntax errors
- [ ] No duplicate code
- [ ] Module separation maintained
- [ ] Consistent naming/style

### Testing Status: ✅ / ⚠️ / ❌

- [ ] Syntax checks pass
- [ ] Static analysis clean
- [ ] Manual dry-run successful
- [ ] Integration tests pass

### Issues Found: [count]

1. [Description of issue] - Status: [Fixed/TODO/Acceptable]
2. ...

### Recommendation: READY / NEEDS WORK / BLOCKED

[Brief explanation of decision]
```

---

## Reference: Rebase Quality Rules

From `.ai/instructions.md` § Git State Management Rules:

1. **No functional loss**: All functionality from both branches must be preserved
2. **No duplication**: Avoid duplicate implementations of the same logic
3. **No loss in modularity**: Keep extracted modules separate; don't inline them back
4. **No degradation in maintainability**: Code should be clearer after rebase, not harder to understand
5. **Documentation must be updated**: All references to renamed/moved files must be updated in docs, configs, and scripts

---

## Related Documents

- `.ai/instructions.md` - Full git workflow rules
- `.ai/REBASE-AND-REFACTORING-METHODOLOGY.md` - Workflow for maintaining feature branches
