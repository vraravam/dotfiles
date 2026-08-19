---
applyTo: "**/*.sh*,**/.shellrc,**/.aliases,**/.envrc,**/.zsh*,**/files/--XDG_CONFIG_HOME--/zsh/*,**/scripts/**/*.{sh,rb}"
---

# Script Depth Tracking

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

`_DOTFILES_SCRIPT_DEPTH` is an environment variable used to track script nesting levels. It serves two critical purposes in the logging infrastructure.

## Scope

**This file applies to**: All scripts (shell and Ruby) that use the deferred error collection pattern and logging infrastructure, including:
- Scripts in `${DOTFILES_DIR}/scripts/` (both `.sh` and `.rb`)
- Scripts in `${PERSONAL_BIN_DIR}/` (both `.sh` and `.rb`)
- Autoload functions in `${XDG_CONFIG_HOME}/zsh/`
- Any script that calls `print_script_start`, `print_script_summary`, or uses `_record_warning`/`_record_error`

**Related files**:
- [`logging-conventions.md`](./logging-conventions.md) - Logging functions that use depth-based indentation
- [`ruby-scripting.md`](./ruby-scripting.md) - Ruby-specific implementation details
- [`shell-scripting.md`](./shell-scripting.md) - Shell-specific implementation details

**Does NOT apply to**: Simple utility functions that don't call logging infrastructure, one-off commands, or scripts without deferred error collection.

## Dual Purpose

`_DOTFILES_SCRIPT_DEPTH` serves two purposes:

1. **Nesting Suppression**: Only outermost scripts (depth ≤ 1) print start/summary banners
2. **Auto-Indentation**: ALL logging functions automatically indent based on depth

This creates visual hierarchy that matches the call stack and prevents nested subprocess output from cluttering the display.

## How It Works

### Shell Implementation

Every `main()` that uses the deferred-collection pattern (`_record_warning` / `_record_error` / `print_script_summary`) **must** increment the counter on entry and decrement it on exit:

```zsh
main() {
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  trap '_decrement_script_depth' EXIT   # chain into any existing EXIT trap
  ...
}
```

`_decrement_script_depth` is defined in `.shellrc`. When a script already sets its own EXIT trap later in `main()`, chain the decrement into that trap rather than setting a separate one (a later `trap ... EXIT` replaces any earlier one):

```zsh
# Scripts with an existing EXIT trap -- chain _decrement_script_depth at the end
trap 'restart_login_item_apps; resume_softwareupdate_schedule; _decrement_script_depth' EXIT

# Scripts whose EXIT trap calls a function -- add _decrement_script_depth inside
# that function rather than duplicating the trap string
_cleanup_recreate() {
  resume_cron
  _decrement_script_depth
}
trap _cleanup_recreate EXIT
```

`is_outermost_script` (`[[ ${_DOTFILES_SCRIPT_DEPTH:-0} -le 1 ]]`) is used by `print_script_start` and `print_script_summary` to suppress output from nested subprocess scripts.

### Ruby Implementation

Call `Logging.increment_script_depth` once before `print_script_start`. It increments `ENV['_DOTFILES_SCRIPT_DEPTH']` and registers an `at_exit` hook that decrements it on both clean and error exits (the exact mirror of the shell increment + EXIT trap pair):

```ruby
Logging.increment_script_depth
script_start_time = Logging.print_script_start

Logging.current_section = 'Checking dependencies'
Logging.record_warning "optional tool missing -- some features disabled"
Logging.record_error   "required env var FOO is not set"

# At end of script -- duration is printed internally
Logging.print_script_summary(script_start_time)
```

`print_script_start` and `print_script_summary` gate their output on `outermost_script?` (`depth <= 1`), so nested subprocess scripts stay silent and only the outermost script prints its banners and summary.

## Calling print_script_summary

**Rule**: Always pass `start_time` when available. Omit only in error handlers that lack access to the variable.

### Shell

```zsh
# Normal case - always pass start_time
main() {
  local start_time="${EPOCHSECONDS}"
  print_script_start
  # ... logic ...
  print_script_summary "${start_time}"  # REQUIRED
}

# Exception - error handler without access
_error_handler() {
  print_script_summary  # No start_time available - omit argument
}
```

### Ruby

```ruby
# Normal case - always pass start_time
start_time = print_script_start
# ... logic ...
print_script_summary(start_time)  # REQUIRED

# Exception - early return in nested method
def helper_method
  return false unless valid?  # Can't access outer start_time
  # If calling print_script_summary here, omit argument
end
```

**Why this matters**: Passing `start_time` allows `print_script_summary` to calculate and display the total execution duration. Without it, the summary shows no duration information.

## Purpose 1: Nesting Suppression

Only outermost scripts (depth ≤ 1) print start/summary banners. Nested subprocesses are silent to avoid clutter:

```sh
# Outermost script (depth 0 → 1)
./parent-script.sh
  [parent-script.sh] Starting...    # Banner printed
  Processing items...

  # Nested subprocess (depth 1 → 2)
  ./child-script.sh                 # NO banner printed
    Processing child items...

  Done with child
  [parent-script.sh] Success!       # Summary printed
```

This behavior is controlled by `is_outermost_script` (shell) or `outermost_script?` (Ruby), which checks if depth ≤ 1.

## Purpose 2: Auto-Indentation

All logging functions automatically indent based on depth (`2 * depth` spaces). This creates visual hierarchy that matches the call stack:

### Shell Example

```zsh
# Standalone script (depth 0 → 1)
main() {
  export _DOTFILES_SCRIPT_DEPTH=1
  info "Processing items..."  # 2-space indent (depth 1)
}

# Nested subprocess (depth 1 → 2)
info "Parent message"         # 2-space indent
system('child-script.sh')     # Child logs at 4-space indent (depth 2)
info "Back to parent"         # 2-space indent
```

All logging functions (`info`, `warn`, `success`, `error`, `debug`, `user_action`) and section headers call `$(_log_indent)` internally, which returns `2 * depth` spaces.

### Ruby Example

```ruby
# Standalone script (depth 0 → 1)
Logging.increment_script_depth  # depth now 1
info "Processing items..."      # 2-space indent (depth 1)

# Nested subprocess (depth 1 → 2)
info "Parent message"                 # 2-space indent
system('child-script.rb')             # Child logs at 4-space indent (depth 2)
info "Back to parent"                 # 2-space indent
```

All logging methods call `log_indent` internally, which returns `'  ' * depth`.

## Critical Rule: Never Manually Indent

**NEVER manually prepend spaces to log messages.** The depth counter handles all indentation automatically:

```sh
# BAD -- manual indent (old pattern, removed during refactoring)
info "  -> Processed ${count} items"

# Good -- auto-indent (current pattern)
info "-> Processed ${count} items"
```

The indent helpers (`$(_log_indent)` in shell, `log_indent` in Ruby) are internal utilities and should not be called directly from scripts.

## Bulleted Lists (Shell Only)

In shell scripts, `join_array` automatically indents list items one level deeper than the current depth, creating subordinate structure:

```zsh
# At depth 1 (2 spaces)
info "Failed items:"
join_array failed_items  # Items at depth 2 (4 spaces)
```

## External Tool Output

External tools (`git`, `mise`, `sqlite3`, `keybase`, etc.) invoked via `system()` or `Open3.capture3()` print at column 0. This is intentional -- wrapping their output would add complexity for minimal UX benefit. Tool output remains visually distinct from our structured logging.

**Examples of unindented tool output**:
- Shell: `system('git', '-C', repo, 'status')`
- Ruby: `system('mise', 'install')`, `Open3.capture3('git', 'log')`

## Why Decrement on Exit

The decrement ensures the counter returns to its pre-script value on exit. This is correct for:

1. **Sourced scripts**: The parent shell environment is restored
2. **Subprocess scripts**: The env is discarded on exit, but the decrement maintains correctness for any further logging in the EXIT trap itself

See `TechnicalDeepDive.md` § 6 for the full rationale on why the decrement is applied even for subprocess-only scripts.

## Conditional Output Based on Depth

Beyond banner suppression (depth ≤ 1), scripts can use `_DOTFILES_SCRIPT_DEPTH` to conditionally suppress other output when called from wrapper scripts.

### Pattern: Suppress section_header in Autoload Functions

Autoload functions that can be called directly OR from wrapper scripts should conditionally show `section_header`:

```zsh
_my_operation() {
  local folder
  local -a switches
  parse_folder_and_switches "$@"

  # Only show section_header when called directly (not from wrapper scripts).
  # Wrapper scripts use print_script_start for their own headers.
  if [[ "${_DOTFILES_SCRIPT_DEPTH:-0}" -le 0 ]]; then
    section_header "$(yellow 'Operation name') '$(cyan "${folder}")'"
  fi

  # ... operation logic ...
}
```

**Why this works:**
- **Direct invocation** (`git operation` or `my_operation`): depth is 0, header shows
- **Via wrapper script**: wrapper calls `print_script_start` (increments depth to 1), then calls autoload function, header is suppressed
- Eliminates duplicate headers without code duplication

**Example wrapper script pattern:**
```zsh
#!/usr/bin/env zsh
set -euo pipefail

_SCRIPT_NAME="${0:t}"
source "${ZDOTDIR}/.aliases"
require_env_var XDG_CONFIG_HOME
load_file_if_exists "${XDG_CONFIG_HOME}/zsh/my_operation"

main() {
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  trap '_decrement_script_depth' EXIT

  local script_start_time="${EPOCHSECONDS}"
  print_script_start                # Shows wrapper's banner, sets depth=1

  with_cron_suspended _my_operation "$@"  # Autoload skips section_header

  print_script_summary "${script_start_time}"
}

main "$@"
```

**Output comparison:**
```bash
# Direct invocation - shows section_header
$ git operation /path/to/repo
Operation name '/path/to/repo'
... operation output ...

# Via wrapper - no duplicate header
$ operation-wrapper.sh /path/to/repo
[operation-wrapper.sh] Starting...
... operation output (no section_header) ...
[operation-wrapper.sh] Summary: completed in 2s
```

### Pattern: Skip Git Alias Override Detection in Autoload Functions

Autoload functions that call git aliases with override detection MUST set `_GIT_OVERRIDE_SKIP=1` to prevent double-execution.

**Problem:** When a wrapper script uses `dispatch_or_fallback`, the following sequence occurs:

1. User types `cc` → `dispatch_or_fallback` finds `cc-browser-profiles.sh` → executes wrapper
2. Wrapper increments depth, calls `with_cron_suspended _cc`
3. `_cc` calls `git -C "${folder}" cc` (the git alias)
4. Git alias detects override script exists → calls `cc-browser-profiles.sh` AGAIN
5. Second invocation increments depth again, prints duplicate output

**Solution:** Set `_GIT_OVERRIDE_SKIP=1` before calling git aliases from autoload functions:

```zsh
_cc() {
  local folder
  local -a switches
  parse_folder_and_switches "$@"

  # Only show section_header when called directly (not from wrapper scripts).
  if [[ "${_DOTFILES_SCRIPT_DEPTH:-0}" -le 0 ]]; then
    section_header "$(yellow 'Compressing') '$(cyan "${folder}")'"
  fi

  if ! is_git_repo "${folder}"; then
    warn "Skipping repo '${folder}' -- not a git repo"
  else
    # Skip git alias override detection to prevent double-execution when called
    # from wrapper scripts (dispatch_or_fallback already found the override).
    _GIT_OVERRIDE_SKIP=1 git -C "${folder}" cc "${switches[@]}" || true
  fi
}
```

**Why this works:**
- Git aliases check `[ -z "${_GIT_OVERRIDE_SKIP:-}" ]` before running override detection
- When set, git alias bypasses override check and runs the actual git commands
- Prevents wrapper script from being called twice

**Applies to all git aliases with override detection:**
- `cc` (compress/clean)
- `push` (git push)
- `pull` (git pull)
- `upreb` (update+rebase)

**Files affected:**
- `files/--XDG_CONFIG_HOME--/zsh/cc` (line 36)
- `files/--XDG_CONFIG_HOME--/zsh/push` (line 22)
- `files/--XDG_CONFIG_HOME--/zsh/pull` (line 18)
- `files/--XDG_CONFIG_HOME--/zsh/upreb` (lines 30, 42)

**Pattern in upreb:**
`upreb` autoload function calls both `git upreb` and `git push` in a loop, so both need `_GIT_OVERRIDE_SKIP=1`:

```zsh
for branch in "${local_branches[@]}"; do
  git -C "${dir}" switch "${branch}"
  _GIT_OVERRIDE_SKIP=1 git -C "${dir}" upreb || true
  # ... symmetric diverge check ...
  _GIT_OVERRIDE_SKIP=1 git -C "${dir}" push || true
done
```

## Summary

| Aspect | Shell | Ruby |
|--------|-------|------|
| Increment | `export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))` | `Logging.increment_script_depth` |
| Decrement | `trap '_decrement_script_depth' EXIT` | Automatic via `at_exit` hook |
| Check if outermost | `is_outermost_script` | `outermost_script?` |
| Check if direct call | `[[ "${_DOTFILES_SCRIPT_DEPTH:-0}" -le 0 ]]` | `ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i <= 0` |
| Indent calculation | `$(_log_indent)` returns `2 * depth` spaces | `log_indent` returns `'  ' * depth` |
| Used by | All logging functions + section headers | All logging methods + section headers |
