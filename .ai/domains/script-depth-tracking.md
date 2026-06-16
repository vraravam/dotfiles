---
applyTo: "all cross-language scripts that use deferred error collection"
---

# Script Depth Tracking

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

`_DOTFILES_SCRIPT_DEPTH` is an environment variable used to track script nesting levels. It serves two critical purposes in the logging infrastructure.

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

## Summary

| Aspect | Shell | Ruby |
|--------|-------|------|
| Increment | `export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))` | `Logging.increment_script_depth` |
| Decrement | `trap '_decrement_script_depth' EXIT` | Automatic via `at_exit` hook |
| Check if outermost | `is_outermost_script` | `outermost_script?` |
| Indent calculation | `$(_log_indent)` returns `2 * depth` spaces | `log_indent` returns `'  ' * depth` |
| Used by | All logging functions + section headers | All logging methods + section headers |
