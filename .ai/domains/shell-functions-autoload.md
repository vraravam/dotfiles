---
applyTo: "**/*.sh*,**/.shellrc,**/.aliases,**/.envrc,**/.zsh*,**/files/--XDG_CONFIG_HOME--/zsh/*,**/scripts/**"
name: dotfiles-shell-functions-autoload
description: Use when writing zsh autoload functions or shell functions that act as first-class entry points in this dotfiles repo -- covers autoload script structure, local/unset usage, positional parameters, `:-` vs `-` expansion operators, array operations, parse_folder_and_switches, and the require_env_var guard.
---

# Shell Functions and Autoload Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules when authoring or editing shell functions, especially zsh autoload functions under `files/--XDG_CONFIG_HOME--/zsh/`.

**Related files**:
- [`shell-scripting.md`](./shell-scripting.md) - Core rules (utility functions, template, logging, quoting, `&&` safety) -- read this first
- [`shell-portability-cron.md`](./shell-portability-cron.md) - bash/direnv/cron portability
- [`zsh-startup.md`](./zsh-startup.md) - Startup performance

## Shell Functions as First-Class Entry Points

When a shell function (not a script file) acts as a command-line entry point
and nests calls to other functions or Ruby/shell scripts, it must follow the
same infrastructure pattern as top-level scripts:

```zsh
my_command() {
  local _SCRIPT_NAME='my_command'
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  # Shell functions cannot set EXIT traps -- they only fire on process exit, not
  # function return. The manual decrement at the end is the correct pattern for
  # functions. Scripts use 'trap _decrement_script_depth EXIT'.

  local start_time="${EPOCHSECONDS}"
  print_script_start

  # ... command logic, calling other scripts/functions ...

  print_script_summary "${start_time}"
  # Manual decrement -- EXIT trap does not fire on function return in shell functions.
  _decrement_script_depth
}
```

### Required elements

1. **`_SCRIPT_NAME`**: Set as a local variable to the function name. This is
   read by `print_script_start` and `print_script_summary` to prefix output.
   In a script file, this is set at script scope via `_SCRIPT_NAME="${0:t}"`;
   in a function, it must be set explicitly as a local.

2. **`start_time`**: Capture `${EPOCHSECONDS}` before calling `print_script_start`
   and pass it to `print_script_summary` at the end. This allows the summary to
   compute and display the total duration.

3. **Script depth tracking**: Increment `_DOTFILES_SCRIPT_DEPTH` at the start
   and manually call `_decrement_script_depth` at the end (after
   `print_script_summary`). Shell functions **cannot** use EXIT traps -- traps
   only fire on process exit, not function return. The manual decrement is the
   correct pattern for functions. Scripts use `trap _decrement_script_depth EXIT`.

4. **Deferred collection infrastructure**: Initialize `_current_section`,
   `_step_warnings`, and `_step_errors` so any nested calls that use
   `_record_warning` or `_record_error` have a valid context.

### When to apply this pattern

Use this pattern when:
- The function is invoked directly by the user from the command line (not just
  an internal helper)
- The function calls other scripts (Ruby or shell) that also use
  `print_script_start`/`print_script_summary`
- The function performs a multi-step workflow where timing and summary output
  are valuable

Do NOT use this pattern for:
- Simple wrapper functions that just delegate to a single command
- Internal helper functions not invoked directly by users
- Functions that complete instantly (no meaningful timing to display)

### Example: `bupc` function

The `bupc` function (in `.aliases`) upgrades nix packages, macOS defaults, and
Homebrew GUI casks via `nixup` (`darwin-rebuild switch`), then runs a couple of
`brew` cache/orphan cleanup commands. It follows
this pattern so that:
- `bupc` is recognized as the outermost script (via its own
  `_DOTFILES_SCRIPT_DEPTH` increment)
- Log output from anything triggered underneath -- e.g. the `antidote` nix
  package's `home.activation` postinstall hook in `nix/modules/packages.nix`,
  which fires during `darwin-rebuild switch` and calls into
  `Antidote.update_and_regenerate_bundle` -- inherits
  and correctly indents one level deeper, even though that method has no script
  infrastructure of its own (it is a plain utility method, not a top-level entry
  point; see script-depth-tracking.md)
- The final summary shows the total time for the entire `bupc` operation

## `local` and `unset` -- Correct Usage

### `unset` for `local` variables is always redundant

`local` variables are automatically cleaned up when the function returns. Never
call `unset` on a variable that was declared `local` in the same function:

```zsh
# BAD -- unset is redundant; local vars auto-clean on function return
my_func() {
  local result
  result="$(some_cmd)"
  # ... use result ...
  unset result   # redundant
}

# Good -- just let the function return
my_func() {
  local result
  result="$(some_cmd)"
  # ... use result ...
}
```

### Declare for-loop variables as `local`

For-loop variables are NOT automatically local in zsh -- they leak into the
enclosing scope (the function, or the global environment if the loop is at
top level). Always declare them `local` before the loop:

```zsh
# BAD -- 'item' leaks into the caller's scope after the loop exits
_my_func() {
  for item in "${arr[@]}"; do
    info "${item}"
  done
  unset item   # a band-aid, not the fix
}

# Good -- declare local; no unset needed
_my_func() {
  local item
  for item in "${arr[@]}"; do
    info "${item}"
  done
}
```

Multiple loop variables can be declared together: `local dir cfg`.

### `local` at the top level of a script is a no-op

`local` is only meaningful inside a function. At script top level (or inside
a sourced file like `.zshrc`), `local` does nothing -- the variable is global.
Remove `local` and rely on `unset` to clean up:

```zsh
# BAD -- 'local' at top-level is a no-op; the variable is still global
local preferred_editors
preferred_editors=('vi')
# ... use it ...
unset preferred_editors   # this is the actual cleanup

# Good -- no local, unset at the end is the correct cleanup
preferred_editors=('vi')
# ... use it ...
unset preferred_editors
```

### Two-step `local` + assignment is intentional -- do NOT collapse

`local var="$(cmd)"` always returns 0 (the `local` builtin's exit code), which
masks the command's real exit code. Splitting into two lines preserves it:

```zsh
# BAD -- local masks the exit code of cmd; set -e won't catch failures
local result="$(cmd)"

# Good -- exit code of cmd is preserved; set -e will abort on failure
local result
result="$(cmd)"
```

This rule applies **only when the RHS contains a command substitution `$(...)`**.
Parameter expansions, string literals, and arithmetic have no exit code to mask,
so they may be combined with `local` on one line:

```zsh
local start_time="${1:-}"           # Good -- parameter expansion, no exit code to lose
local folder="${1:-${PWD}}"         # Good -- same reason
local name="${CALLER_SCRIPT:-${0:t}}"  # Good -- same reason
```

Never collapse a two-step `local` + assignment back into a single line when
`$(...)` is involved, even though it may look redundant. The split is intentional.

## Positional Parameters

**Every function that uses a positional parameter (`$1`, `$2`, ...) must guard
it -- either with a default it can safely proceed with, or with a fail-fast
check if the function cannot proceed without it. A bare, unguarded `${1}` /
`$1` is always a bug: it has neither a default nor a fail-fast message.**

### Optional: has a sensible default, function can proceed without it

```zsh
local arg="${1:-}"          # Good -- empty is a valid, handled state
local dir="${1:-${PWD}}"    # Good -- explicit fallback value
```

### Required: function cannot proceed without it -- fail fast

Use `${1:?message}` to abort immediately with a clear message if unset or empty:

```zsh
local folder="${1:?my_func: folder argument required}"
```

Or, when the failure needs to go through this repo's own logging/return-code
conventions rather than a raw shell abort (e.g. inside a function that must
`return 1` instead of killing the whole script -- see [`shell-scripting.md`](./shell-scripting.md) § Exit Points),
guard explicitly:

```zsh
local folder="${1:-}"
if nil_or_empty "${folder}"; then
  warn "my_func: folder argument required"
  return 1
fi
```

**Choosing between the two required-guard forms:** `${1:?message}` is
simplest and correct for most internal/private helper functions (`_`-prefixed)
where an immediate abort is acceptable. Prefer the explicit `nil_or_empty` +
`warn` + `return 1` form for user-facing entry-point functions (where `warn`'s
consistent logging format and a clean `return` -- not an abrupt `${1:?}` abort
message -- matter for UX), or where the calling script needs to keep running
other work after this one function fails.

### Two related gaps that look guarded but are not

**`getopts`-parsed flags are never automatically required.** `getopts` only
parses whatever flags are present -- it does not know or enforce that a given
flag is mandatory. If a flag is required, check it explicitly after the loop
(see also [`shell-scripting.md`](./shell-scripting.md) § Option Parsing):

```zsh
while getopts ":d:" opt; do
  case "${opt}" in
    d) dir="${OPTARG}" ;;
  esac
done
if nil_or_empty "${dir:-}"; then
  warn "my_func: -d <dir> is required"
  usage
  return 1
fi
```

**`shift`/`shift N` silently no-ops past the end instead of failing.** In zsh,
`shift N` when `$# < N` prints `shift: shift count must be <= $#` to stderr but
does **not** abort or change `$#` -- the function continues executing with
stale positional parameters instead of failing fast. Guard the count before
shifting whenever it isn't already guaranteed present:

```zsh
# BAD -- if called with zero args, shift silently fails to consume anything
_my_func() {
  local fn="${1:-}"
  shift
  # ...
}

# Good -- verify enough args are present before shifting
_my_func() {
  if (($# < 1)); then
    warn "_my_func: fn argument required"
    return 1
  fi
  local fn="${1}"
  shift
  # ...
}
```

**Scan rule:** when editing any function, check every `$1`/`$2`/.../`shift`
reference against this section. A parameter that's genuinely optional gets
`:-`; a parameter the function cannot function without gets `:?` or an
explicit `nil_or_empty` check; every `shift`/`shift N` is preceded by a `$#`
check if the count being shifted isn't already guaranteed present.

## Parameter Expansion Operators -- `:-` vs `-`

The choice between `${VAR:-fallback}` and `${VAR-fallback}` is not arbitrary --
it signals intent about whether an **empty** value should be treated the same as
**unset**:

| Operator | Substitutes fallback when... |
|---|---|
| `${VAR:-fallback}` | VAR is **unset** OR **set-but-empty** |
| `${VAR-fallback}` | VAR is **unset** only |

### Rule: use `:-` for user-controlled boolean feature flags

All user-controlled boolean env vars (`DEBUG`, `ZSH_PROFILE`, `FIRST_INSTALL`,
and any similar flag) must use `:-`:

```zsh
# Good -- unset and set-but-empty are identical for a user flag
[[ -n "${DEBUG:-}" ]]
[[ -n "${ZSH_PROFILE:-}" ]]
[[ -n "${FIRST_INSTALL:-}" ]]
```

For a flag, `VAR=` (set but empty) and an unset `VAR` are the same thing -- the
flag is not active. `:-` makes this intent explicit and avoids silent differences
between `unset VAR` and `VAR=`.

### Rule: use `-` for shell-provided or system-set variables

Variables set by the shell or by external tools -- where an empty value is
meaningfully distinct from unset -- use `-`:

```zsh
# Good -- ZSH_VERSION is always non-empty when set; '-' is correct here
[[ -n "${ZSH_VERSION-}" ]]
[[ -n "${BASH_VERSION-}" ]]
```

`ZSH_VERSION` and `BASH_VERSION` are never set to empty by the shell; they are
either absent (wrong interpreter) or non-empty (correct interpreter). Using `:-`
here would be harmless in practice, but `-` is more precise about the semantics.

### Scan rule

Shell files only. SSH config files (`files/--HOME--/.ssh/*`, `templates/ssh-config.template`) are not
shell: ssh rejects `${VAR:-}`, so never add or "correct" default-value expansions there
(`ssh-config.md` overrides this rule).

When reviewing any shell file, flag every `${VAR-}` or `${VAR-""}` where `VAR`
is a user-controlled boolean feature flag and change it to `${VAR:-}` /
`${VAR:-""}`. Only leave `-` when the variable is shell-provided (e.g.
`ZSH_VERSION`, `BASH_VERSION`) or when set-but-empty is genuinely distinct from
unset for that variable.

## Pipelines with `grep`

`grep -q` in a pipeline under `set -o pipefail` causes SIGPIPE:

```zsh
# BAD
some_command | grep -q "pattern"

# Good
some_command | grep -q "pattern" || true
# Or better, capture output first
output=$(some_command)
if is_non_zero_string "${output}"; then echo "${output}" | grep -q "pattern"; fi
```

## Array Operations

```zsh
# Declare associative arrays explicitly to avoid parameter-not-set errors
typeset -A my_assoc_array

# Check empty/non-empty
is_empty_array my_arr       # instead of [[ ${#my_arr[@]} -eq 0 ]]
is_non_empty_array my_arr   # instead of [[ ${#my_arr[@]} -gt 0 ]]

# Join -- pass the array name (not elements); delimiter is hardcoded as '\n  - '
join_array my_arr
```

## `parse_folder_and_switches` Convention

Autoload scripts that accept an optional leading folder argument followed by
git-style `--flags` use `parse_folder_and_switches` (defined in `.aliases`).
The function writes into `folder` and `switches` in the **caller's scope** --
both locals must be declared before the call:

```zsh
_my_cmd() {
  local folder
  local -a switches
  parse_folder_and_switches "$@"
  # folder = first non-flag arg, or pwd if none
  # switches = all --flag args
  git -C "${folder}" some-command "${switches[@]}"
}
```

Rules:
- `folder` receives the first bare (non-`--`) argument, defaulting to `$(pwd)`.
- `switches` receives all `--flag` arguments in order.
- Only use this when the command naturally accepts both a directory and flags.
  If the command takes only a directory (no flags), use `local folder="${1:-$(pwd)}"` directly.

## Autoload Script Structure

Every file under `files/--XDG_CONFIG_HOME--/zsh/` (except `plugins.txt`) is a zsh autoload script.
The structure is fixed -- all four components must be present in every file:

```zsh
#!/usr/bin/env zsh
# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# <Description of what this command does>
# ...usage/examples...

# Re-source guard is inside .shellrc itself -- safe to call unconditionally.
source "${HOME}/.shellrc"

_my_cmd() {
  local folder
  local -a switches
  parse_folder_and_switches "$@"
  # ... implementation ...
}

my_cmd() { dispatch_or_fallback my_cmd _my_cmd "$@"; }

# Run only when executed directly, not when sourced (e.g. to import the function
# into another script). Pattern matches both 'file' (regular sourcing) and
# 'filecode' (.zwc bytecode).
[[ ":${ZSH_EVAL_CONTEXT}:" == *:file(|code):* ]] || my_cmd "$@"
# is_zsh returns false in bash (ZSH_VERSION unset), short-circuiting the zsh-only
# '(( $+functions[...] ))' syntax so it is never evaluated by non-zsh runtimes.
is_zsh && (($+functions[compdef])) && compdef my_cmd || true
```

### `ZSH_EVAL_CONTEXT` Self-Invocation Guard

`[[ ":${ZSH_EVAL_CONTEXT}:" == *:file(|code):* ]] || my_cmd "$@"` prevents the
function from running when the file is `source`d by another script.

**Pattern explanation:**
- Use **uppercase** `ZSH_EVAL_CONTEXT` (scalar string version), not lowercase `zsh_eval_context` (array version)
- `:${ZSH_EVAL_CONTEXT}:` wraps the variable in colons to match colon-separated tokens
- `*:file(|code):*` matches both `:file:` (regular sourcing) and `:filecode:` (.zwc bytecode)
- The `(|code)` pattern means "optionally followed by 'code'"

**Behavior:**
- When sourced: context contains `:file:` or `:filecode:` → pattern matches → skip execution
- When run directly: context is `toplevel` or `cmdarg` → pattern doesn't match → execute

**Why the colon wrappers:**
- `toplevel:shfunc:file` → `:toplevel:shfunc:file:` ensures `:file:` matches (not partial match of `filecode`)
- `cmdarg filecode` → `:cmdarg filecode:` would NOT match `:file:` (correct - bytecode loaded differently)

**Why `file(|code)` pattern:**
- `.zwc` bytecode changes eval context token from `file` to `filecode`
- Pattern must match both to work correctly with compiled autoload functions
- Mirrors antidote 2.1.1's fix for the same issue

### `compdef` Registration Guard

```zsh
is_zsh && (($+functions[compdef])) && compdef my_cmd || true
```

Two guards are required:
1. `is_zsh` -- returns false in bash (where `ZSH_VERSION` is unset), short-
   circuiting the zsh-only arithmetic expression that follows. `is_zsh` is
   available here because autoload scripts always source `.shellrc` at the top.
2. `(($+functions[compdef]))` -- zsh built-in check; `compdef` is only available
   after `compinit` has run. Autoload scripts may be sourced before `compinit`
   (e.g. during `fresh-install`), so this guard prevents a "command not found"
   error.

The trailing `|| true` is required because `(($+functions[compdef]))` exits 1
when `compdef` is not defined (arithmetic 0 = false = exit 1 in zsh). Without
`|| true`, sourcing an autoload script from a script that has an ERR trap (e.g.
a cron job) would fire the trap every time `compdef` is not available.

## `require_env_var` Guard

Before sourcing a common script that depends on a specific env var, validate
the var is set using `require_env_var` (defined in `.aliases`). This aborts
with a clear message rather than producing cryptic errors inside the common
script:

```zsh
# Re-source guard is inside .aliases itself -- safe to call unconditionally.
load_file_if_exists "${ZDOTDIR}/.aliases"
  require_env_var PERSONAL_BIN_DIR
  load_file_if_exists "${PERSONAL_BIN_DIR}/upreb-homebrew-common.sh"
```
