# Dotfiles Domain Context

## Overview
This file provides domain-specific context for the dotfiles repository, personal bin scripts, and configs. It complements the formal rules in [`domains/`](./domains/) with historical insights, optimization patterns, and practical debugging guidance.

## Instruction Files (The Source of Truth)
All detailed rules, patterns, and conventions are in `.ai/domains/`:
- `.ai/domains/character-encoding.md` (cross-language)
- `.ai/domains/comment-philosophy.md` (cross-language)
- `.ai/domains/edit-checklist.md` (cross-language)
- `.ai/domains/fresh-install.md`
- `.ai/domains/git-config.md`
- `.ai/domains/logging-conventions.md` (cross-language)
- `.ai/domains/path-constants.md` (cross-language)
- `.ai/domains/ruby-scripting.md`
- `.ai/domains/script-depth-tracking.md` (cross-language)
- `.ai/domains/shell-scripting.md`
- `.ai/domains/whitespace-rules.md` (cross-language)
- `.ai/domains/zsh-startup.md`

**DO NOT duplicate content from these files.** They are the authoritative source.

See `.ai/instructions.md` for the main entry point and `.ai/README.md` for the tool-agnostic convention.

## Decision-Making Philosophy
(From `copilot-instructions.md` - already loaded)

Priority order when making decisions:
1. **Startup speed** (for zsh startup paths)
2. **Maintainability** (readability, DRY, clear intent)
3. **POSIX compatibility** (when scripts run in bash/direnv)
4. **Zsh built-ins** (when they don't conflict with #1-3)

Higher priority always wins. Document tradeoffs in comments when they conflict.

## Repository Structure
```
~/.config/dotfiles/
├── files/
│   ├── --HOME--/              # Symlinked to ~/
│   │   ├── .shellrc           # Sourced by all shells
│   │   ├── .aliases           # Shell functions/aliases
│   │   └── Brewfile           # Homebrew packages
│   ├── --ZDOTDIR--/           # Zsh-specific (~/ZDOTDIR)
│   │   ├── .zshenv            # Always sourced first
│   │   ├── .zshrc             # Interactive shells
│   │   └── .zlogin            # After .zshrc (compilation)
│   └── --XDG_CONFIG_HOME--/zsh/  # Autoload functions
├── scripts/
│   ├── utilities/             # Shared Ruby modules
│   ├── fresh-install-of-osx.rb
│   └── install-dotfiles.rb
└── .ai/                        # AI assistant instructions
```

## Session-Specific Insights

### Recent Fixes (June 2026)

#### ERR Trap + `&&` Chain Interaction (June 2026)
**Problem**: Fresh-install failing on vanilla macOS during `.zshrc` sourcing with "Installation failed at line X" errors.

**Root cause**: Under `set -E`, ERR traps inherit to all functions. Standalone `A && B` expressions where A returns false (a normal outcome like "file doesn't exist" or "DEBUG not set") propagate exit code 1 to the enclosing scope, triggering the trap even though no error occurred.

**Solution**: Converted all standalone `&&` chains to explicit `if` blocks throughout `.shellrc`, `.aliases`, `.zshenv`, `.zshrc`, `.zlogin`:
- Logging functions: `success`, `info`, `warn`, `user_action`, `debug`
- Validation helpers: `join_array`, `is_file_older_than`, `is_non_empty_file`, `is_directory_empty`
- File operations: `load_file_if_exists` now uses `|| warn` to catch source failures
- Git operations: `clone_repo_into`, `set_ssh_folder_permissions`
- Re-source guards and DEBUG echo statements

**Impact**: Fresh-install now completes successfully on first run without false-positive errors.

**Key insight**: `if A; then B; fi` never propagates the predicate's exit code outside the conditional, so the trap never fires. Safe exception: `A && B || C` where C returns 0 (overall expression resolves to 0).

#### capture-prefs.rb Timestamp Check Abort (June 2026)
**Problem**: Fresh-install aborting silently after `osx-defaults.rb` with misleading "line 204" error. Script never reached "Recreate zsh completions" section or later steps (recron, resurrect_tracked_repos, mise/direnv setup).

**Root cause**: `capture-prefs.rb -i` checks if backup preferences predate `osx-defaults.rb` changes and aborts with `exit(1)` (treated as fatal error). On `FIRST_INSTALL`, any backup is better than none since fresh-install already ran `osx-defaults.rb -s` to baseline current prefs first.

**Debugging challenges**:
- ERR trap `$LINENO` reported wrong line number (204 = array declaration in `_ensure_directories_exist`, but actual failure was in `capture-prefs.rb` call at line 653)
- Success message "Successfully restored preferences" never printed (line 654), but warning from capture-prefs DID appear
- Three "Automatic checking for updates is turned on" messages from multiple `resume_softwareupdate_schedule` calls (osx-defaults EXIT trap, capture-prefs at_exit hook, and a third mysterious call before error)

**Solution**: Skip timestamp check on `FIRST_INSTALL` - added `&& !EnvVars.first_install?` condition to the abort logic in `capture-prefs.rb`. On pre-configured machines, `fresh-install-of-osx.rb` automatically refreshes the backup: runs `capture-prefs.rb -e` to export current preferences (stages files), then commits using `git sci` (amends if ahead of remote, creates new if not) to update the git commit timestamp. Import then succeeds because backup timestamp is now newer than `osx-defaults.rb`.

**Impact**: Fresh-install now completes preferences restoration on both vanilla OS (stale backups accepted) and pre-configured machines (backup automatically refreshed and committed before import).

**Key insights**:
- Ruby `at_exit` hooks that call `exit(1)` or raise exceptions cause parent shell to receive non-zero exit code, triggering ERR trap
- ERR trap `$LINENO` in string form (`trap 'handler "${LINENO}"' ERR`) captures the line where trap was SET, not where it FIRED, when used incorrectly
- Multiple `at_exit` hooks execute in LIFO order; all must complete successfully or the process exits non-zero
- `_abort_with_error` in Ruby scripts should be reserved for truly unrecoverable errors, not validation warnings that could be downgraded on FIRST_INSTALL
- Timestamp validation compares **git commit timestamps**, not file timestamps - must commit after export to update timestamp
- `git sci` automatically amends existing commit if ahead of remote (no commit spam on repeated runs)

#### cron.rb Exception Propagation (June 2026)
**Problem**: `restore_cron` raising exceptions when `crontab` command failed, causing fresh-install to abort via ERR trap.

**Root cause**: Ruby `raise` statements propagate to shell as non-zero exit codes when called via `ruby -e` from shell functions. The shell ERR trap catches this and aborts the entire fresh-install process.

**Solution**: Changed `restore_cron` to return `true`/`false` and log errors via `Logging.record_error` instead of raising. Updated callers (`resume_cron`, `recron`) to check return value before printing success message.

**Impact**: Crontab installation failures are now recoverable - errors are logged and tracked in the summary but don't abort fresh-install. User can run `recron` manually later.

**Key insight**: Ruby scripts called from shell (via `ruby -e` or subprocess) must return non-zero exit codes only for fatal errors. Recoverable failures should log warnings/errors and return false/success code, not raise exceptions.

#### clone_repo_into Delegation Pattern (June 2026)
**Problem**: Duplicate implementations - 79 lines in .shellrc, 98 lines in git_processor.rb.

**Solution**: Ruby delegates to shell version via `system('zsh', '-c', 'source ~/.shellrc && clone_repo_into ...')`.

**Why delegation, not consolidation**:
- **Bootstrap constraint**: fresh-install-of-osx.rb clones dotfiles repo BEFORE Ruby utilities exist
- **Vanilla OS**: Only /bin/zsh and curl available initially
- **Timing**: Function must be in .shellrc for curl-download during bootstrap
- **Single source of truth**: Shell version is canonical, Ruby is thin wrapper

**Shell enhancements applied** (lines 1252-1354 in .shellrc):
1. **Progressive trap cleanup**: `trap "rm -rf '${tmp_folder}' '${stderr_file}'" EXIT INT TERM`
   - Updates trap as resources are allocated
   - Clears trap after successful completion
   - Shell equivalent of Ruby's `ensure` block
2. **STDERR capture**: `git clone ... 2>"${stderr_file}"` then display on failure
   - Better debugging experience for network/auth failures
   - Only shows stderr when clone fails
3. **Existing .git removal**: `rm -rf "${target_folder}/.git"` before move
   - Prevents corrupt state from interrupted clones
   - Safety feature from Ruby version
4. **Duration tracking**: Uses `${EPOCHSECONDS}` (no subprocess fork)
   - Debug-only output, no overhead in normal operation

**Future port guidance**: When fresh-install is ported to Ruby, reimplement clone_repo_into fresh (don't copy stale Ruby implementation from git_processor.rb). Use current .shellrc version as reference.

**Pattern applies to**: Any function needed during bootstrap before dotfiles repo exists must stay in .shellrc, Ruby should delegate not duplicate.

### Recent Optimizations (June 2026)
Performance improvements in `.zshrc`:
- **Problem**: 28ms spent in helper functions during startup
- **Solution**: Replaced `is_directory` calls with glob qualifiers `(N/)` for path building
- **Trade-off**: Kept utility functions for non-glob checks (consistency over micro-optimization)
- **Results**:
  - `is_directory` calls: 8 → 1 (-87%) via glob qualifiers
  - Raw test switches eliminated (maintainability)
  - Internal time: 28ms → 26ms (-7%)

Key patterns that improved performance:
```zsh
# Before (function call overhead for each directory)
if is_directory "${dir}"; then path+=("${dir}"); fi

# After (glob qualifier filters at expansion time, no function call)
path+=("${dir}"(N/))

# For non-glob cases, still use utility functions
is_non_zero_string "${var}" && export VAR="${var}"  # NOT [[ -n "${var}" ]]
```
```

### Current Bottleneck Analysis
From `zprof` output:
- **81%** of startup: Antidote plugin bundle loading (21.65ms)
  - Already optimized with deferrals
  - Further gains require removing plugins
- **9%**: Syntax highlighting initialization (2.59ms)
- **5%**: Starship prompt (1.35ms) - cached, unavoidable
- **4%**: Mise activation (1.18ms) - cached, unavoidable

**Average total startup**: 78-87ms (variance due to system load)

### Historical Optimization Milestones

#### May 2026: Major Startup Overhaul (commit 72891ae)
**Achievement**: Shell startup reduced from ~200ms to **7ms** (97% improvement)

Key changes:
1. **Plugin manager swap**: oh-my-zsh → antidote (78b8cb4)
   - Static bundle generation (no runtime plugin resolution)
   - Result: 200ms → 9ms

2. **Caching strategy** (72891ae):
   - `brew shellenv`: Run once per brew upgrade, not every shell
   - Git version detection: Cache based on git binary mtime (~14ms saved)
   - Starship init: Cache based on starship binary mtime (~5-10ms saved)
   - Mise activate: Cache based on mise binary mtime (~5-10ms saved)

3. **NOUNSET handling**:
   - Plugins with bare `$3` crash under `set -u`
   - Solution: `set +u` before bundle, `set -u` after

4. **Architecture cache** (3.1.22 - Nov 2025):
   - Eliminated `uname -m` fork on every startup
   - Manual invalidation via `delete_caches` after OS upgrades
   - Result: 8.80ms → 0.06ms (147x speedup for this block)

5. **Compinit optimization**:
   - `-C` flag skips security audit when dump exists
   - `skip_global_compinit=1` prevents `/etc/zshrc` duplication

#### Performance Patterns That Work
From 3+ years of optimization:

**❌ Avoid**:
- Function calls in hot paths (especially directory checks)
- Subshell forks `$(...)` during startup
- Running external binaries multiple times per shell
- OMZ-style plugin loading (too dynamic)

**✅ Prefer**:
- Glob qualifiers: `(N/)` instead of `is_directory` checks (glob filtering is free)
- Utility functions: `is_non_zero_string` instead of `[[ -n "${var}" ]]` (consistency over micro-optimization)
- Memoization: Cache repeated checks/computations
- Static bundles: Pre-generate, source once
- Mtime-based invalidation: Cache until dependency changes

**Note**: Glob qualifiers `(N/)` provide both performance AND safety (no errors on
missing directories). Use them liberally in startup paths. Utility functions add
~0.1ms overhead but provide consistent error handling and are preferred over raw
test switches (`-f`, `-d`, `-n`, etc.) even in hot paths.

#### Shell→Ruby Migration Benefits (3.1.21-3.1.25)
Converted 5 shell scripts to Ruby (2025-2026):
- `software-updates-cron.sh` → `.rb`
- `capture-prefs.sh` → `.rb`
- Several autoload functions

Benefits realized:
- **Memoization**: 3 shell invocations → 1 per operation (~30ms/cron)
- **No subprocess overhead**: Direct module calls
- **Better error handling**: Native exceptions vs exit codes
- **Type safety**: Pathname objects, not string concatenation
- **Single language**: All plist/git/profile ops in Ruby

Trade-off: Still use shell for startup paths (zsh internals)

#### Antidote .zwc Crash (3.1.19 - Oct 2025)
**Problem**: `antidote.zsh.zwc` bytecode broke every shell startup
**Cause**: antidote uses `[[ ":${ZSH_EVAL_CONTEXT}:" == *:file:* ]]` to detect sourcing
  - `.zwc` sets context to `filecode`, not `file`
  - Pattern mismatch → CLI mode → `exit 1` → crash
**Solution**: Never compile `antidote.zsh` to `.zwc`
**Prevention**: `delete_caches` now purges any stale `antidote.zsh.zwc`

### Known Issues
1. Aliases sometimes fail to load after certain `.zshrc` changes
   - **Cause**: Syntax errors break initialization before `zsh-defer` runs
   - **Debug**: `zsh -n file.zsh` and check for nested expansion errors
2. Autoload functions not found
   - **Cause**: Glob pattern not matching symlinks correctly
   - **Fix**: Use `[[ "${file:e}" == "" ]]` check, not complex globs
3. Architecture cache stale after OS upgrade
   - **Symptom**: Wrong arch detection after major macOS update
   - **Fix**: Run `delete_caches` to regenerate

## Quick Debugging Commands

```zsh
# Check syntax
zsh -n ~/.zshrc

# Profile startup
ZSH_PROFILE=true zsh -i -c exit
zprof

# Debug load order
DEBUG=true zsh

# Check if function loaded
type function_name

# Check PATH/FPATH
echo ${PATH} | tr ':' '\n'
echo ${FPATH} | tr ':' '\n'
```

## Common Task Checklists

For complete edit workflows (syntax checks, formatting, whitespace verification, executable permissions), see [`domains/edit-checklist.md`](./domains/edit-checklist.md).

**Quick debugging commands:**
- Syntax check shell: `zsh -n file.zsh`
- Syntax check Ruby: `/usr/bin/ruby -c file.rb`
- Test new shell: `zsh -i -c "type some_alias"`
- Profile startup: `ZSH_PROFILE=true zsh -i -c exit` then `zprof`
- Benchmark startup: 20 iterations of `time zsh -i -c exit`

## Coding Patterns from Past Sessions

### Shell Scripting Hard-Won Lessons

1. **`&&` under `set -e` is dangerous**
   - `A && B` where A returning false is *expected* triggers ERR trap
   - **Fix**: Use explicit `if A; then B; fi`
   - **Exception**: `A && B || C` safe when C returns 0

2. **Arithmetic post-increment crashes**
   - `(( count++ ))` with count=0 → exit 1 → `set -e` abort
   - **Fix**: `(( count += 1 )) || true`

3. **For-loop variables leak**
   - Loop vars are NOT auto-local in zsh
   - **Fix**: `local item; for item in ...`

4. **Parameter expansion operators matter**
   - `${VAR:-fallback}`: unset OR empty → fallback
   - `${VAR-fallback}`: unset only → fallback
   - **Rule**: Use `:-` for user flags, `-` for shell vars

5. **Local + assignment masks exit codes**
   - `local result="$(cmd)"` always returns 0 (from `local`)
   - **Fix**: Split into two lines

6. **NULL_GLOB needs proper scoping**
   - Never use bare `setopt NULL_GLOB` (leaks)
   - **Fix**: `() { setopt localoptions NULL_GLOB; ... }` in pure zsh
   - **Fix**: Named function + `unfunction` in bash-parseable files

7. **Quoted paths everywhere**
   - Always `"${var}"`, never `$var` (except `$?` etc.)
   - **Exception**: After assignments like `file=${1:-.}`

8. **ERR trap LINENO capture**
   - `trap handler ERR` → `$LINENO` is handler's line
   - **Fix**: `trap 'handler "${LINENO}"' ERR` (string form)

9. **Progressive trap cleanup**
   - Set trap early, update as resources allocated, clear on success
   - **Pattern**: `trap "rm -rf '${tmp_folder}'" EXIT INT TERM`
   - Update: `trap "rm -rf '${tmp_folder}' '${stderr_file}'" EXIT INT TERM`
   - Clear: `trap - EXIT INT TERM` (after success, before function returns)
   - Handles normal exit, errors, and interrupts (Ctrl+C)
   - Shell equivalent of Ruby's `ensure` block

10. **STDERR capture for better debugging**
    - Pattern: `stderr_file="$(mktemp)"; cmd 2>"${stderr_file}"; status=$?`
    - Display stderr only on failure: `if [[ $status -ne 0 ]]; then cat "${stderr_file}"; fi`
    - Always use `2>/dev/null` when reading stderr file (in case it disappeared)
    - Add trap to clean up stderr file: `trap "rm -rf '${tmp}' '${stderr}'" EXIT`

### Ruby Scripting Patterns

1. **EnvVars module is source of truth**
   - All `ENV.fetch('LITERAL')` → centralize in `EnvVars`
   - **Pathname constants** for paths (expensive to construct)
   - **Methods** for dynamic values (re-evaluated each call)

2. **Memoization eliminates repeated work**
   - Command existence checks: `@_cmd_exists ||= command_exists?`
   - Boolean queries: `@_exporting ||= @op == 'export'`
   - **Don't memoize**: Dynamic state, single-use, cheap ops

3. **Pathname all the way**
   - Keep Pathname throughout code
   - Convert `.to_s` only at system call boundaries
   - Use `Pathname#join()`, not `File.join`

4. **Private method discipline**
   - Prefix with `_`, add `private :_method_name`
   - Signals internal-only API
   - **All** helper methods in scripts must be private

5. **Single exit point**
   - Never `exit()` mid-loop in processing scripts
   - Track failures, exit once at end
   - **Exception**: Help/usage, precondition validation

6. **GitProcessor patterns**
   - **Block form**: 2+ git operations in same scope
   - **Instance form**: Single operation, need return value
   - Always rescue `RuntimeError` for `relative_path`

7. **Shell delegation pattern**
   - Ruby utilities use `extend self`
   - Shell functions call via `ruby -e "Module.method"`
   - Single implementation, multiple entry points

8. **Logging auto-indents**
   - All methods use `log_indent` (depth * 2 spaces)
   - **Never** manually prepend spaces
   - External tool output intentionally unindented

### Cross-Language Conventions

1. **Unified color standard**
   - See [`domains/logging-conventions.md`](./domains/logging-conventions.md) for complete rules
   - Paths: cyan + quotes
   - Components/tools: yellow
   - Commands: cyan + quotes
   - Booleans: orange
   - Success counts: green, error counts: red, neutral: purple

2. **Deferred error collection**
   - Both shell and Ruby: `record_warning`, `record_error`
   - Prefix: `[script_name][section]`
   - Print summary at end via `print_script_summary`

3. **Script depth tracking**
   - Increment on entry, decrement on exit
   - Gates start/summary output (outermost only)
   - Auto-indents all logging output

4. **No hardcoded paths**
   - Shell: Use `${DOTFILES_DIR}` not `~/.config/dotfiles`
   - Ruby: Use `EnvVars::DOTFILES_DIR` not `Pathname.new(ENV['HOME']).join(...)`

5. **ASCII-only in code/comments**
   - See [`domains/character-encoding.md`](./domains/character-encoding.md) for complete rules
   - No em dashes, curly quotes, Unicode punctuation
   - **Exception**: User-facing output where typography matters

## Where to Find Information

| Topic | Location |
|-------|----------|
| ASCII-only requirements | domains/character-encoding.md |
| Cache patterns | domains/zsh-startup.md § Caching |
| Color standards | domains/logging-conventions.md |
| Comment guidelines | domains/comment-philosophy.md |
| Edit workflow | domains/edit-checklist.md |
| EnvVars module usage | domains/path-constants.md § Ruby |
| Fresh install rules | domains/fresh-install.md |
| Function call overhead | This file § Session-Specific Insights |
| Git alias patterns | domains/git-config.md |
| Glob qualifiers for performance | domains/shell-scripting.md § Glob Patterns |
| Logging conventions | domains/logging-conventions.md |
| Path constants | domains/path-constants.md |
| Ruby script template | domains/ruby-scripting.md § Script Template |
| Script depth tracking | domains/script-depth-tracking.md |
| Shell script template | domains/shell-scripting.md § Script Template |
| Whitespace rules | domains/whitespace-rules.md |

## Performance Optimization Workflow

When optimizing startup (see zsh-startup.md for full details):

1. **Profile**: `ZSH_PROFILE=true zsh -i -c exit` then `zprof`
2. **Identify**: Look for:
   - High call counts on simple functions
   - Function calls in loops
   - Subprocess forks `$(...)`
3. **Optimize**:
   - Use glob qualifiers `(N/)` for directory filtering (free at expansion time)
   - Keep utility functions for non-glob checks (consistency over micro-optimization)
   - Cache expensive commands
4. **Verify**: Profile again, benchmark with 20+ iterations
5. **Document**: Add optimization notes to this file

---

**Remember**: This skill is a navigation guide and session journal. Detailed rules live in the instruction files. Don't duplicate them here.
