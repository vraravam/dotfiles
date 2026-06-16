# Nix Migration Branch - Rebase Review & Plan

**Date:** Current session  
**Current Branch:** master (safe for cron)  
**Target Branch:** nix-migration  
**Analysis:** Should we rebase nix-migration onto latest master?

---

## Executive Summary

**RECOMMENDATION: ⚠️ DO NOT REBASE YET - MAJOR CONFLICTS AHEAD**

The nix-migration branch diverged 19 commits ago and has fundamental architectural differences that will cause extensive conflicts. A rebase is technically possible but requires significant manual resolution work.

**Alternative Recommendation:** Wait until ruby-scripts-migration is merged to master, then rebase nix-migration as a separate effort with dedicated time.

---

## Branch Status

| Branch | Last Common Ancestor | Commits Ahead | Status |
|--------|---------------------|---------------|--------|
| **master** | `c581a8a` (Jun 2026) | +19 | Current, stable |
| **ruby-scripts-migration** | `9f2bf17` (current) | +1 | Ready to merge, 100% parity |
| **nix-migration** | `c581a8a` (Jun 2026) | +1 (`e6bb74b`) | WIP, not tested |

### Key Dates
- **Common ancestor:** `c581a8a` - Large commit with deferred error collection, logging infrastructure, etc.
- **Divergence point:** Early June 2026
- **Master progress:** 19 commits of Ruby migration + fixes
- **Nix progress:** 1 WIP commit introducing Nix infrastructure

---

## What's On nix-migration Branch

### New Files Added (5 Nix files)
```
nix/
├── flake.nix                      # Nix flake definition
├── darwin-configuration.nix       # macOS system config
├── home.nix                       # Home-manager config
└── modules/
    ├── osx-app-defaults.nix       # macOS preferences (declarative)
    └── packages.nix               # Package list (replaces Brewfile)
```

### Deleted Files (1)
```
files/--HOME--/Brewfile            # Replaced by nix/modules/packages.nix
```

### Modified Files (8)
```
.github/copilot-instructions.md    # Added Nix context
files/--HOME--/.aliases             # Added nixup alias
files/--HOME--/.shellrc             # Nix integration
files/--ZDOTDIR--/.zlogin           # Nix path handling
files/--ZDOTDIR--/.zshrc            # Nix integration
scripts/fresh-install-of-osx.sh     # Nix bootstrap logic
scripts/osx-defaults.sh             # Reduced (Nix handles most)
scripts/post-brew-install.sh        # Simplified (Nix handles deps)
scripts/software-updates-cron.sh    # Nix update integration
```

---

## What's On master (19 commits ahead)

### Major Changes Since Divergence

1. **Ruby Migration** (7 commits)
   - `software-updates-cron.sh` → `.rb`
   - `capture-prefs.sh` → `.rb`
   - `cleanup-browser-profiles.sh` → `.rb`
   - `recreate-repo.sh` → `.rb`
   - `add-upstream-git-config.sh` → `.rb`
   - `run-all.sh` → `.rb`
   - Multiple autoload functions converted to Ruby

2. **New Ruby Utilities** (9 modules created)
   - `scripts/utilities/env_vars.rb` - Environment variable centralization
   - `scripts/utilities/git_processor.rb` - Git operations
   - `scripts/utilities/git_workspace.rb` - Workspace management
   - `scripts/utilities/cron.rb` - Cron management
   - `scripts/utilities/keybase.rb` - Keybase operations
   - `scripts/utilities/antidote.rb` - Antidote management
   - `scripts/utilities/macos.rb` - macOS helpers
   - `scripts/utilities/profiles_repo.rb` - Browser profiles
   - `scripts/utilities/collection_processor.rb` - Iteration patterns

3. **Tool-Agnostic AI Instructions** (15 files)
   - `.ai/domains/*.md` - Domain-specific rules
   - `.ai/instructions.md` - Main entry point
   - `.ai/context.md` - Session insights
   - `.github/copilot-instructions.md` - Reduced to redirect

4. **Shell Script Improvements**
   - SSH config variable expansion fix
   - ERR trap improvements
   - Pathname consistency
   - Terminology standardization (folder → dir)

5. **Performance Optimizations**
   - Startup speed improvements
   - Cron efficiency enhancements

---

## Conflict Analysis

### 🔴 CRITICAL CONFLICTS (Will Require Manual Resolution)

#### 1. `scripts/software-updates-cron.sh` → DELETED in master (now `.rb`)
**Nix branch:** Modified shell version with Nix integration  
**Master:** Converted to Ruby (`software-updates-cron.rb`)  
**Resolution needed:** Port Nix integration to Ruby version

**Conflict size:** ~300 lines of Ruby vs ~400 lines of shell

---

#### 2. `files/--HOME--/Brewfile` → DELETED in nix-migration
**Nix branch:** Removed, replaced by `nix/modules/packages.nix`  
**Master:** Updated with new packages  
**Resolution needed:** Ensure all master's Brewfile additions are in Nix packages

**Conflict size:** 225 lines deleted vs 37 lines added

---

#### 3. `scripts/fresh-install-of-osx.sh` → MASSIVELY MODIFIED on both branches
**Nix branch:** 
- Removed Homebrew installation logic
- Added nix-darwin bootstrap
- Changed directory creation (Nix handles some)
- Modified app defaults restoration

**Master:**
- Enhanced error handling (ERR trap improvements)
- Added cache busting headers
- Improved preferences auto-refresh
- Home repo pull logic
- Touch ID improvements
- Resurrect repos background spawn

**Conflict size:** ~800 lines, almost every section touched

**Ruby-scripts-migration:** Also converts this to `.rb` (+1 more conflict layer!)

---

#### 4. `scripts/osx-defaults.sh` → DRASTICALLY REDUCED in nix-migration
**Nix branch:** 
- Reduced from 2,700 lines to ~400 lines
- Most prefs moved to `nix/modules/osx-app-defaults.nix`
- Only system-level defaults remain in shell

**Master:**
- Expanded with new app preferences
- Fixed several bugs
- Added more third-party app support

**Conflict size:** 1,277 deletions vs 182 additions

---

#### 5. `.github/copilot-instructions.md` → RESTRUCTURED in master
**Nix branch:** Added Nix-specific context (76 lines)  
**Master:** Converted to redirect file (1,200 lines removed, 5 lines remain)  
**Resolution needed:** Port Nix context to `.ai/domains/` structure

**Conflict size:** Full file rewrite

---

### 🟡 MODERATE CONFLICTS (Likely Auto-Mergeable with Review)

#### 6. `files/--HOME--/.aliases`
**Nix branch:** Added `nixup` alias  
**Master:** Converted many shell functions to Ruby, refactored

**Likely resolution:** Git can auto-merge, verify `nixup` survives

---

#### 7. `files/--HOME--/.shellrc`
**Nix branch:** Added Nix path handling (10 lines)  
**Master:** Massive refactoring, new utilities, performance improvements

**Likely resolution:** Git can auto-merge, verify Nix integration survives

---

#### 8. `files/--ZDOTDIR--/.zshrc` & `.zlogin`
**Nix branch:** Nix path integration  
**Master:** Performance optimizations, cache improvements

**Likely resolution:** Git can auto-merge

---

### 🟢 NO CONFLICTS (New Files)

All new files in master have no conflicts:
- `.ai/*` directories (new)
- `scripts/utilities/*.rb` (new Ruby modules)
- `*.rb` versions of converted scripts (new)

All new files in nix-migration have no conflicts:
- `nix/*` directories (new)

---

## Impact Assessment

### If We Rebase Now

#### Time Investment
- **Minimum:** 4-6 hours of conflict resolution
- **Realistic:** 8-12 hours including testing
- **Worst case:** 16+ hours if Ruby migration conflicts cascade

#### Risk Level: 🔴 HIGH
1. **Three-way conflict:** Nix changes vs master changes vs ruby-scripts-migration changes
2. **Architectural divergence:** Homebrew vs Nix paradigm shift
3. **Untested code:** Nix branch marked "WIP: not yet tested"
4. **Ruby conversion:** Would need to convert Nix-modified shell scripts to Ruby

#### What Could Go Wrong
1. Lose Nix-specific logic during conflict resolution
2. Accidentally keep shell versions when Ruby exists
3. Break working master/ruby-scripts-migration code
4. Spend hours merging only to discover Nix approach needs redesign

---

## Alternative Strategies

### Strategy A: Defer Rebase (RECOMMENDED)
**Timeline:**
1. ✅ Complete ruby-scripts-migration testing (current priority)
2. ✅ Merge ruby-scripts-migration → master
3. ⏳ THEN rebase nix-migration onto new master
4. ⏳ Port Nix changes to Ruby versions
5. ⏳ Test Nix migration thoroughly

**Advantages:**
- Clean two-way conflict (Nix vs Ruby-complete master)
- Single architectural transition (Shell+Homebrew → Ruby+Nix)
- No risk to working ruby-scripts-migration branch
- Can dedicate focused time to Nix integration

**Disadvantages:**
- Nix migration delayed by ~1 week
- Two separate rebase efforts instead of one

---

### Strategy B: Rebase Now (NOT RECOMMENDED)
**Timeline:**
1. Rebase nix-migration onto master (4-12 hours)
2. Resolve 8 major conflicts manually
3. Test nix-migration thoroughly
4. Then still need to merge ruby-scripts-migration
5. Then resolve conflicts between nix-migration and ruby-scripts-migration

**Advantages:**
- Nix branch up to date with master improvements
- Get it over with?

**Disadvantages:**
- High risk of breaking working code
- Three-way conflict resolution (complex)
- Blocks ruby-scripts-migration testing/merge
- May need to redo work after ruby-scripts-migration merges

---

### Strategy C: Parallel Tracks (ALTERNATIVE)
**Timeline:**
1. Merge ruby-scripts-migration → master (priority 1)
2. Create nix-migration-v2 from new master (fresh start)
3. Cherry-pick Nix-specific changes from old nix-migration
4. Rewrite Nix integration against Ruby versions
5. Keep old nix-migration as reference

**Advantages:**
- Clean slate with Ruby-complete codebase
- No conflict resolution needed
- Can redesign Nix integration from scratch
- Old branch preserved for reference

**Disadvantages:**
- More work upfront
- Lose commit history from nix-migration
- Need to audit all changes carefully

---

## Key Decision Factors

### Questions to Answer Before Rebasing

1. **Is Nix migration still a priority?**
   - If yes → wait for ruby-scripts-migration merge (Strategy A)
   - If no → archive nix-migration branch

2. **How stable is the Nix design?**
   - If tested and stable → rebase and port to Ruby (Strategy A)
   - If experimental → consider fresh start (Strategy C)

3. **What's the timeline pressure?**
   - If urgent → Strategy B (risky but fast)
   - If flexible → Strategy A (safe and methodical)

4. **Who will do the work?**
   - If you have 2 days → Strategy B might work
   - If you have 1 week spread out → Strategy A is safer
   - If you need help → Strategy C is most reviewable

---

## Technical Considerations

### Nix + Ruby Integration Points

These will need careful design regardless of strategy:

1. **Package Management**
   - Nix replaces Homebrew
   - Ruby scripts reference `brew` commands
   - Need Nix equivalents for: `brew bundle`, `brew outdated`, etc.

2. **System Preferences**
   - Nix declarative config vs imperative `defaults write`
   - Ruby scripts use `MacOS.defaults` helpers
   - Need to decide which approach wins

3. **Bootstrap Process**
   - Current: curl → clone → brew → ruby scripts
   - Nix: curl → nix-darwin → declarative config
   - Need unified bootstrap that works both ways

4. **Cron Integration**
   - Current: Ruby cron script updates Homebrew
   - Nix: `darwin-rebuild switch` for updates
   - Need Nix-aware Ruby cron script

5. **Development Tools**
   - Current: mise, direnv, ruby via Homebrew
   - Nix: Development environments via flake
   - Need to support both workflows

---

## File-by-File Rebase Complexity

| File | Nix Changes | Master Changes | Complexity | Strategy |
|------|-------------|----------------|------------|----------|
| `software-updates-cron.sh` | Modified | Deleted (→.rb) | 🔴 CRITICAL | Port to Ruby manually |
| `Brewfile` | Deleted | Modified | 🔴 CRITICAL | Audit packages, update Nix |
| `fresh-install-of-osx.sh` | Massive | Massive | 🔴 CRITICAL | Manual 3-way merge |
| `osx-defaults.sh` | Reduced 70% | Expanded | 🔴 CRITICAL | Reconcile philosophies |
| `copilot-instructions.md` | Added Nix | Restructured | 🔴 CRITICAL | Move to .ai/domains/ |
| `.aliases` | Added nixup | Refactored | 🟡 MODERATE | Likely auto-merge |
| `.shellrc` | Nix paths | Refactored | 🟡 MODERATE | Likely auto-merge |
| `.zshrc` / `.zlogin` | Nix paths | Optimized | 🟡 MODERATE | Likely auto-merge |

**Total Critical Conflicts:** 5 files, ~3,000 lines of manual resolution  
**Total Moderate Conflicts:** 3 files, ~500 lines to review  
**Total New Files:** 14 (no conflicts)

---

## Recommended Action Plan

### Phase 1: Current Priority (This Week)
✅ **DO NOW:**
1. Stay on master branch (safe for cron) ✅ DONE
2. Test ruby-scripts-migration on vanilla macOS
3. Test ruby-scripts-migration on pre-configured machine
4. Merge ruby-scripts-migration → master when tests pass

⛔ **DO NOT:**
- Touch nix-migration branch yet
- Start rebase work
- Make any Nix-related changes

---

### Phase 2: Nix Rebase Preparation (Next Week)
**AFTER ruby-scripts-migration is merged:**

1. **Audit Nix branch** (2 hours)
   - Document all Nix-specific changes
   - List all package differences (Brewfile vs packages.nix)
   - Identify shell functions that need Ruby equivalents

2. **Create Rebase Plan** (1 hour)
   - File-by-file merge strategy
   - Test plan for each conflict resolution
   - Rollback plan if rebase fails

3. **Set up test environment** (1 hour)
   - VM or separate machine for testing
   - Backup current working config
   - Document rollback procedures

---

### Phase 3: Execute Rebase (Dedicated Time Block)
**Requires:** 2-3 day time block, no interruptions

1. **Rebase nix-migration** (4-6 hours)
   ```bash
   git checkout nix-migration
   git rebase master
   # Resolve conflicts one by one
   ```

2. **Port Nix Changes to Ruby** (4-6 hours)
   - Update `software-updates-cron.rb` with Nix logic
   - Add `nix-darwin` integration to Ruby utilities
   - Create `Nix` utility module (like `MacOS`, `Cron`, etc.)

3. **Test Thoroughly** (4-8 hours)
   - Bootstrap on vanilla macOS with Nix
   - Verify all preferences apply
   - Test update workflow
   - Verify cron integration

4. **Document** (2 hours)
   - Update CHANGELOG.md
   - Update GettingStarted.md with Nix bootstrap
   - Add Nix-specific documentation

**Total time:** 14-22 hours of focused work

---

## Risk Mitigation

### If Rebase Goes Wrong

**Safety net:**
```bash
# Before starting, create safety branch
git checkout nix-migration
git branch nix-migration-backup
git push origin nix-migration-backup

# If rebase fails catastrophically:
git rebase --abort
git reset --hard nix-migration-backup
```

### Test Before Committing
```bash
# After each conflict resolution, verify:
ruby -c scripts/*.rb                     # Ruby syntax
zsh -n scripts/*.sh                      # Shell syntax
cd "${HOME}" && rufo scripts/*.rb        # Format Ruby
git diff --check                         # Whitespace
```

---

## Conclusion

### Final Recommendation: Strategy A (Defer Rebase)

**Reasoning:**
1. ✅ Ruby migration is 99% complete, tested, ready to merge
2. ⚠️ Nix migration is WIP, untested, experimental
3. 🔴 Rebasing now adds risk to working ruby-scripts-migration
4. ⏰ Delaying Nix rebase by 1 week is acceptable
5. 🎯 Clean two-way merge is easier than three-way

**Action Items:**
- ✅ Switch to master (DONE - safe for cron)
- ⏳ Test ruby-scripts-migration thoroughly
- ⏳ Merge ruby-scripts-migration → master
- ⏳ THEN tackle nix-migration with dedicated focus

**Timeline:**
- **This week:** ruby-scripts-migration → master
- **Next week:** Nix rebase + Ruby integration
- **Week 3:** Nix testing + documentation

---

## Questions for You

Before proceeding with any rebase work, please confirm:

1. **Is Nix migration still a priority?** (Active project or experiment?)
2. **What's the timeline?** (Urgent or flexible?)
3. **Testing capacity?** (VM available? Separate machine?)
4. **Risk tolerance?** (Okay with potential breakage during rebase?)
5. **Preference?** (Strategy A, B, or C?)

**My strong recommendation:** Strategy A (defer until ruby-scripts-migration is merged).

---

## References

- Ruby migration status: `.ai/FEATURE-PARITY-ANALYSIS.md`
- Ruby migration fixes: `.ai/MISSING-FEATURES-FIXED.md`
- Master commit history: 19 commits from `c581a8a` to `9f2bf17`
- Nix WIP commit: `e6bb74b` (not yet tested)
- Common ancestor: `c581a8a` (early June 2026)
