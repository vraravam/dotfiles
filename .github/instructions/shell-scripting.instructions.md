---
applyTo: "**/*.sh*,**/.shellrc,**/.aliases,**/.envrc,**/.zsh*,**/files/**,**/scripts/**"
---

# Shell Script Instructions

Apply these rules when writing or editing any shell script in this repository.

Syntax choices follow the decision-making priority defined in
`copilot-instructions.md` (startup speed + maintainability first; POSIX and
zsh built-ins where they do not conflict with those). Document the tradeoff in
a comment when they conflict.

## Script Skeleton

```zsh
#!/usr/bin/env zsh
# shellcheck shell=zsh
# file location: <describe where this file is symlinked/used>
#
# <One-line description of the script>
#
# Usage: <script-name> [options]

set -euo pipefail

# ---------------------------------------------------------------------------
# Re-source guard is inside .shellrc itself — safe to call unconditionally.
source "${HOME}/.shellrc"

# ---------------------------------------------------------------------------
# Constants / Config
_SCRIPT_NAME="${0:t}"

# ---------------------------------------------------------------------------
# Usage

usage() {
  print_usage "${_SCRIPT_NAME}" \
    "$(yellow '-f') <file>   Description of -f" \
    "$(yellow '-h')          Show this help"
}

# ---------------------------------------------------------------------------
# Private helpers

_helper_function() {
  # ...
}

# ---------------------------------------------------------------------------
# Main

main() {
  local flag=""

  while getopts ":fh" opt; do
    case "${opt}" in
      f) flag=true ;;
      h) usage; return 0 ;;
      :) warn "Option -${OPTARG} requires an argument."; usage; return 1 ;;
      ?) warn "Unknown option: -${OPTARG}"; usage; return 1 ;;
    esac
  done
  shift $(( OPTIND - 1 ))

  # ... main logic ...
}

main "$@"
```

### Script Name Convention

Use `_SCRIPT_NAME="${0:t}"` (underscore prefix, **not** `readonly`). The
underscore signals it is script-private (not exported). `readonly` is omitted
because the variable is never reassigned and the declaration overhead adds
no safety in practice.

Because `_SCRIPT_NAME` is declared at script scope (not `local`), it is
visible to any library function called from the script (e.g. `load_zsh_configs`
uses it for debug logging, `print_script_start` and `print_script_summary` read
it via dynamic scoping to prefix their output — no argument needed). Library
functions that want the calling script's name should reference
`${_SCRIPT_NAME:-<interactive>}` with a fallback — the variable is absent in
interactive sessions where no script is active.

### `print_usage` over `cat <<EOF`

Always use `print_usage` (defined in `.shellrc`) for usage output — not
`cat <<EOF`. `print_usage` accepts the script name as `$1` followed by
variadic color-formatted option lines:

```zsh
usage() {
  print_usage "${_SCRIPT_NAME}" \
    "$(yellow '-f') <file>   Description of -f" \
    "$(yellow '-h')          Show this help"
}
```

`usage()` must reference `${_SCRIPT_NAME}` directly — never accept the script
name as a parameter and never call `usage "${_SCRIPT_NAME}"` at the call site.
Call sites always invoke `usage` with no arguments:

```zsh
# BAD — passing _SCRIPT_NAME as an argument is redundant; usage() can read it directly
usage() { print_usage "${1}" ...; }
usage "${_SCRIPT_NAME}"

# Good — usage() references _SCRIPT_NAME directly; call sites pass no argument
usage() { print_usage "${_SCRIPT_NAME}" ...; }
usage
```

Exception: `*-common.sh` scripts use `${CALLER_SCRIPT:-${0:t}}` instead of
`${_SCRIPT_NAME}` so the wrapper script's name appears in usage output — see
§ **`exec`-Wrapper Scripts**.

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
  # Shell functions cannot set EXIT traps — they only fire on process exit, not
  # function return. The manual decrement at the end is the correct pattern for
  # functions. Scripts use 'trap _decrement_script_depth EXIT'.

  local start_time="${EPOCHSECONDS}"
  print_script_start

  # ... command logic, calling other scripts/functions ...

  print_script_summary "${start_time}"
  # Manual decrement — EXIT trap does not fire on function return in shell functions.
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
   `print_script_summary`). Shell functions **cannot** use EXIT traps — traps
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

The `bupc` function (in `.aliases`) upgrades Homebrew packages and calls
`post-brew-install.rb`. It follows this pattern so that:
- `bupc` is recognized as the outermost script
- `post-brew-install.rb` detects it is nested and suppresses its own output
- The final summary shows the total time for the entire `bupc` operation

## Intentional Omission of `set -euo pipefail`

All shell scripts use `set -euo pipefail` **except** when a script's logic
requires commands that legitimately return non-zero in normal operation. When
omitting it, add a comment at the top explaining why:

```zsh
# set -euo pipefail is intentionally omitted: many 'defaults write' and 'killall'
# calls return non-zero when a setting is unsupported on the current OS version,
# which is expected and must not abort the script.
```

Valid reasons to omit:
- Scripts that call `defaults write` / `killall` (macOS settings — non-zero is normal)
- Scripts that call `find` / `rm` where "no matches" is expected and non-fatal
- Cron scripts where `set -e` would abort on the first update tool failure,
  preventing all subsequent update steps from running (use an `ERR` trap instead)

## Option Parsing: `getopts` vs Long Flags

Use `getopts` for all short-option (`-f`, `-h`) parsing. `getopts` cannot
handle long flags (`--flag`). When long options are needed, use manual
`while/case` with `shift`:

```zsh
while [[ $# -gt 0 ]]; do
  case "${1}" in
    --port)
      port="${2:?--port requires an argument}"
      shift 2
      ;;
    -h | --help)
      usage
      return 0
      ;;
    *)
      error "Unknown option: ${1}"
      usage
      return 1
      ;;
  esac
done
```

The `${2:?message}` expansion aborts with the message if `$2` is unset or
empty — use it for required flag arguments.

## `local` and `unset` — Correct Usage

### `unset` for `local` variables is always redundant

`local` variables are automatically cleaned up when the function returns. Never
call `unset` on a variable that was declared `local` in the same function:

```zsh
# BAD — unset is redundant; local vars auto-clean on function return
my_func() {
  local result
  result="$(some_cmd)"
  # ... use result ...
  unset result   # redundant
}

# Good — just let the function return
my_func() {
  local result
  result="$(some_cmd)"
  # ... use result ...
}
```

### Declare for-loop variables as `local`

For-loop variables are NOT automatically local in zsh — they leak into the
enclosing scope (the function, or the global environment if the loop is at
top level). Always declare them `local` before the loop:

```zsh
# BAD — 'item' leaks into the caller's scope after the loop exits
_my_func() {
  for item in "${arr[@]}"; do
    info "${item}"
  done
  unset item   # a band-aid, not the fix
}

# Good — declare local; no unset needed
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
a sourced file like `.zshrc`), `local` does nothing — the variable is global.
Remove `local` and rely on `unset` to clean up:

```zsh
# BAD — 'local' at top-level is a no-op; the variable is still global
local preferred_editors
preferred_editors=('vi')
# ... use it ...
unset preferred_editors   # this is the actual cleanup

# Good — no local, unset at the end is the correct cleanup
preferred_editors=('vi')
# ... use it ...
unset preferred_editors
```

### Two-step `local` + assignment is intentional — do NOT collapse

`local var="$(cmd)"` always returns 0 (the `local` builtin's exit code), which
masks the command's real exit code. Splitting into two lines preserves it:

```zsh
# BAD — local masks the exit code of cmd; set -e won't catch failures
local result="$(cmd)"

# Good — exit code of cmd is preserved; set -e will abort on failure
local result
result="$(cmd)"
```

This rule applies **only when the RHS contains a command substitution `$(...)`**.
Parameter expansions, string literals, and arithmetic have no exit code to mask,
so they may be combined with `local` on one line:

```zsh
local start_time="${1:-}"           # Good — parameter expansion, no exit code to lose
local folder="${1:-${PWD}}"         # Good — same reason
local name="${CALLER_SCRIPT:-${0:t}}"  # Good — same reason
```

Never collapse a two-step `local` + assignment back into a single line when
`$(...)` is involved, even though it may look redundant. The split is intentional.

## Quoting and Variable References

### Always Quote Variables

Always quote variables to prevent word-splitting and glob expansion when the
value is used in a context where it could contain spaces:

```zsh
# Good — quoted, safe if value contains spaces
cp "${src_file}" "${dest_dir}/"
is_file "${config_path}"
info "Processing ${filename}"

# BAD — unquoted, breaks if value contains spaces
cp $src_file $dest_dir/
is_file $config_path
info "Processing $filename"
```

### Single Quotes vs Double Quotes

Prefer **single quotes** for static strings that contain no variable references
or command substitutions. Use **double quotes** when the string contains a
variable reference or needs escape interpretation:

```zsh
# Good — single quotes for static strings
local sep='------'
grep -q 'pattern'
error 'File not found'

# Good — double quotes when expanding variables
local msg="Processing ${repo_name}"
source "${HOME}/.shellrc"
info "Done: ${count} files processed"

# BAD — double quotes on strings with no variable expansion (unnecessary)
local sep="------"
grep -q "pattern"   # fine if no special chars, but prefer single quotes
```

Exception: prefer **double quotes** over single quotes when the static string
contains single quotes that would otherwise require `$'...\n...'` escaping or
concatenation. Double quotes allow literal single quotes inside and support
literal newlines, making multiline strings significantly more readable:

```zsh
# BAD — $'...' with escaped single quotes is hard to read
user_action $'Restart \'Terminal\' and \'iTerm\':\n  \'ProtonVPN\' - may drop VPN.'

# Good — double quotes; single quotes are literal, newline is literal
user_action "Restart 'Terminal' and 'iTerm':
  'ProtonVPN' - may drop VPN."
```

### No Hardcoded User-Specific Paths

Never hardcode user-specific or machine-specific paths. Always use the exported
env vars defined in `.shellrc` instead. This applies to every file in the
repository — scripts, config files, and Brewfile Ruby expressions alike.

| Instead of | Use |
|---|---|
| `"${HOME}/dev"` literal repeated inline | `"${PROJECTS_BASE_DIR}"` |
| `"${HOME}/personal/dev/bin"` | `"${PERSONAL_BIN_DIR}"` |
| `"${HOME}/personal/dev/configs"` | `"${PERSONAL_CONFIGS_DIR}"` |
| `"${HOME}/.config/dotfiles"` | `"${DOTFILES_DIR}"` |
| `"${HOME}/.config"` | `"${XDG_CONFIG_HOME}"` |
| `"${HOME}/.cache"` | `"${XDG_CACHE_HOME}"` |
| `"${HOME}/.local/bin"` | `"${XDG_BIN_HOME}"` |
| `"${HOME}/.local/share"` | `"${XDG_DATA_HOME}"` |
| `"${HOME}/.local/state"` | `"${XDG_STATE_HOME}"` |
| `"${HOME}/.ssh"` | `"${SSH_CONFIGS_DIR}"` |
| `/opt/homebrew` or `/usr/local` | `"${HOMEBREW_PREFIX}"` |

`${HOME}` itself is always acceptable — it is a standard shell variable, not a
hardcoded path. The rule targets its *derived* paths that already have a named
env var.

Scan rule: when editing any script or config file, flag every occurrence of a
literal expanded path that matches one of the right-hand-side values above, and
replace it with the corresponding env var.

### `${var}` Brace Notation

Always use `${var}` brace notation (not bare `$var`) to unambiguously delimit
the variable name. This prevents accidental concatenation bugs and makes the
boundary of the variable name visually clear:

```zsh
# Good
echo "${HOME}/.config"
local path="${DOTFILES_DIR}/scripts"
info "Repo: ${repo_name}_backup"   # without braces, _backup would be part of name

# BAD
echo "$HOME/.config"
local path="$DOTFILES_DIR/scripts"
```

Exception: `$?`, `$#`, `$@`, `$*`, `$$`, `$!`, `$-` — the single-character
special parameters do not need braces.

## Positional Parameters

Always guard positional parameters with a default to avoid `unbound variable`
errors under `set -u`:

```zsh
local arg="${1:-}"   # Good
local arg="$1"       # BAD under set -u if $1 not provided
```

## Parameter Expansion Operators — `:-` vs `-`

The choice between `${VAR:-fallback}` and `${VAR-fallback}` is not arbitrary —
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
# Good — unset and set-but-empty are identical for a user flag
[[ -n "${DEBUG:-}" ]]
[[ -n "${ZSH_PROFILE:-}" ]]
[[ -n "${FIRST_INSTALL:-}" ]]
```

For a flag, `VAR=` (set but empty) and an unset `VAR` are the same thing — the
flag is not active. `:-` makes this intent explicit and avoids silent differences
between `unset VAR` and `VAR=`.

### Rule: use `-` for shell-provided or system-set variables

Variables set by the shell or by external tools — where an empty value is
meaningfully distinct from unset — use `-`:

```zsh
# Good — ZSH_VERSION is always non-empty when set; '-' is correct here
[[ -n "${ZSH_VERSION-}" ]]
[[ -n "${BASH_VERSION-}" ]]
```

`ZSH_VERSION` and `BASH_VERSION` are never set to empty by the shell; they are
either absent (wrong interpreter) or non-empty (correct interpreter). Using `:-`
here would be harmless in practice, but `-` is more precise about the semantics.

### Scan rule

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

## `&&` as Conditional — Safety Under `set -e` / ERR Trap

`A && B` where A returning false (exit 1) is a **normal, expected outcome** is
unsafe in any script that uses `set -e` or an ERR trap. When A returns 1, the
overall `&&` expression also returns 1 — that non-zero result triggers `set -e`
abort or fires the ERR trap, even though no actual error occurred.

The fix is always an explicit `if` statement, which never propagates a non-zero
exit code from the predicate to the enclosing scope.

```zsh
# BAD — is_file returning false (file absent) is normal; fires set -e / ERR trap
is_file "${optional_config}" && cp "${optional_config}" "${dest}"

# BAD — is_zero_string returns 1 for every non-empty string (the common case)
is_zero_string "${app_pref}" && continue

# BAD — is_non_empty_array returns 1 for empty array (the success/clean-run case)
is_non_empty_array failed_repos && exit 1

# BAD — is_non_zero_string returns 1 for empty string (e.g. a clean cron run)
is_non_zero_string "${outdated_flat}" && _msg+=". Needs manual update: ${outdated_flat}"

# Good — explicit if; predicate exit code never reaches the enclosing scope
if is_file "${optional_config}"; then cp "${optional_config}" "${dest}"; fi
if is_zero_string "${app_pref}"; then continue; fi
if is_non_empty_array failed_repos; then exit 1; fi
if is_non_zero_string "${outdated_flat}"; then _msg+=". Needs manual update: ${outdated_flat}"; fi
```

**Safe exception — `A && B || C` dispatch:**

`A && B || C` (run B on success, C on failure) is safe when C always returns 0.
The overall expression resolves to C's exit code, which is 0 — the ERR trap
never fires. This pattern is correct for intentional success/failure branching:

```zsh
# Good — C (_record_error / _record_warning) always returns 0; ERR trap never fires
update_all_repos && success 'Updated repos' || _record_error 'Failed to update repos'
git pull -r && success "Updated: ${folder}" || _record_warning "Failed: ${folder}"
```

**Scan rule:** when editing any script that uses `set -e` or an ERR trap, scan
every standalone `A && B` line and verify that A returning false is an *error*
(not a normal/expected case). If it is expected, convert to `if A; then B; fi`.

## Arithmetic Increment — Safety Under `set -e`

`(( var++ ))` uses post-increment: it evaluates to the *old* value of `var`.
When `var` is `0`, `(( 0 ))` is arithmetic false (exit code 1), which triggers
`set -e` abort or fires the ERR trap — silently killing the script at the first
iteration of any counter that starts at zero.

```zsh
# BAD — (( 0 )) on the first iteration; fires set -e and silently aborts
(( count++ ))

# Good — += 1 always evaluates to the new value (≥ 1); || true is a safety net
# for any edge case where the result could reach 0 (e.g. wrap-around)
(( count += 1 )) || true
```

The same applies to `(( var-- ))` when `var` reaches `1` (post-decrement
returns `1`, then evaluates to `0` on the next call). Use `(( var -= 1 )) || true`.

**Scan rule:** whenever adding or reviewing an arithmetic counter in a script
that uses `set -e`, replace bare `(( var++ ))` / `(( var-- ))` with
`(( var += 1 )) || true` / `(( var -= 1 )) || true`.


## `return` vs `exit` Inside `main()`

Always use `return` (never `exit`) inside `main()`. `exit` terminates the entire
shell process — if the script is ever sourced, it kills the calling shell. `return`
exits only the function; the script process then exits with that return code because
`main "$@"` is the last line.

```zsh
# BAD — exit inside main() terminates the calling shell if the script is sourced
main() {
  if is_zero_string "${folder}"; then
    warn 'Missing required argument'
    usage
    exit 1   # BAD
  fi
  ensure_keybase_logged_in || exit 1   # BAD
}

# Good — return propagates the exit code via 'main "$@"' at the bottom
main() {
  if is_zero_string "${folder}"; then
    warn 'Missing required argument'
    usage
    return 1
  fi
  ensure_keybase_logged_in || return 1
}

main "$@"
```

`exit` IS correct in:
- Trap handler functions (`_cleanup_and_exit`, ERR/EXIT traps) — these run outside
  the normal call stack and must terminate the process.
- Git `!` alias bodies — git runs them in a subprocess shell; `exit` propagates
  the code back to git.

**Scan rule:** when editing any script, flag every `exit` inside `main()` and
replace with `return`. Leave `exit` in trap handlers and git alias bodies.

Internal helpers not called by external scripts must be prefixed with `_`:

```zsh
_internal_helper() { ... }   # private
public_function() { ... }    # public (no prefix)
```

## `source` vs `load_file_if_exists`

`load_file_if_exists` is defined in `.shellrc` and is only available **after**
`.shellrc` has been downloaded and sourced. The rule is:

- **Before `.shellrc` is sourced** (e.g., early boot of `fresh-install` on a
  vanilla OS): use plain `source` with an explicit existence check, or accept
  that the file must be present.
- **After `.shellrc` is sourced**: always prefer `load_file_if_exists` over
  `source` for any file that may not exist on all machines or in all scenarios.
```zsh
# Early boot — .shellrc not yet available, use source with guard
[[ -f "${HOME}/.shellrc" ]] && source "${HOME}/.shellrc"

# After .shellrc is sourced — use load_file_if_exists
load_file_if_exists "${ZDOTDIR}/.some-optional-file"
```

## Array Operations

```zsh
# Declare associative arrays explicitly to avoid parameter-not-set errors
typeset -A my_assoc_array

# Check empty/non-empty
is_empty_array my_arr       # instead of [[ ${#my_arr[@]} -eq 0 ]]
is_non_empty_array my_arr   # instead of [[ ${#my_arr[@]} -gt 0 ]]

# Join — pass the array name (not elements); delimiter is hardcoded as '\n  - '
join_array my_arr
```

## Glob Patterns — NULL_GLOB

`setopt localoptions NULL_GLOB` scoped to a function body is the only permitted
way to enable NULL_GLOB. The scoping vehicle depends on whether the file can be
sourced by bash (see below).

- **Never use bare `setopt NULL_GLOB`** at script, function, or top-level scope —
  the change persists for the rest of the process and leaks into every caller.
- **Never use `unsetopt NULL_GLOB`** — if you find yourself needing to unset it,
  you set it globally in the first place, which is the mistake to fix.
- **Never use inline `(N)` glob qualifiers** — they are parsed by most editor
  syntax highlighters as function calls, breaking highlighting for the rest of
  the line.

### Anonymous function `()` vs named helper

The `()` anonymous-function syntax is zsh-only. Bash **cannot parse** it — not
even inside an `if is_zsh; then` block, because bash parses the entire `if` body
before evaluating the condition. A `()` anywhere in a file that bash will ever
`source` is a **parse-time** error, not a runtime one.

**Files that bash never sources** (pure zsh scripts, autoload functions,
`.zshrc`, `.zlogin`): use the anonymous `()` form.

**Files that bash may source** (`.shellrc`, which direnv loads in a bash
subshell): use a named helper function instead. `name()` syntax is valid in
both bash and zsh; `setopt localoptions` inside it is a runtime zsh-only call
that bash never reaches because the function is only invoked from zsh code.

```zsh
# BAD — NULL_GLOB leaks to the rest of the script / caller
setopt NULL_GLOB
rm -f "${dir}"/*.plist "${dir}"/*.defaults
unsetopt NULL_GLOB

# BAD — inline (N) qualifier breaks editor syntax highlighting
rm -f "${dir}"/*.plist(N) "${dir}"/*.defaults(N)

# BAD in .shellrc — () is zsh-only syntax; bash cannot parse this file at all,
# even if the block is guarded by 'if is_zsh' (bash parses before executing)
() {
  setopt localoptions NULL_GLOB
  rm -f "${dir}"/*.plist "${dir}"/*.defaults
}

# Good in pure zsh files (.zshrc, autoload scripts, zsh-only scripts) —
# () is valid; restored automatically when the anonymous function returns
() {
  setopt localoptions NULL_GLOB
  rm -f "${dir}"/*.plist "${dir}"/*.defaults
}

# Good in .shellrc (bash-parseable files) — named helper; bash can parse
# 'name() {}' syntax and never calls this function in a bash context
_remove_loose_files() {
  setopt localoptions NULL_GLOB
  rm -f "${dir}"/*.plist "${dir}"/*.defaults
}
_remove_loose_files
```

## Do not mandate named helpers everywhere

`()` anonymous functions are idiomatic and correct in pure zsh files. Named
functions defined inside another function in zsh persist in the global function
table after the outer function returns — they are **not** scoped. The `()` form
is truly scoped and disappears on return. Using named helpers everywhere would
introduce namespace pollution in files where `()` is perfectly safe.

Use named helpers **only** where bash parseability requires it (`.shellrc`,
`.aliases`, `.envrc`). The deciding question: can bash ever `source` this file?

When a named helper is required (bash-parseable file), always `unfunction` it
immediately after use to prevent global namespace pollution. This matters in
non-subshell call sites — direct interactive invocations and calls from other
functions running in the same process. `run-all.rb` sandboxes each repo call in
a `()` subshell so the leak is contained there, but the `unfunction` is still
required for correctness at other call sites:

```zsh
# Named helper required in .shellrc — bash cannot parse '() { ... }'
_do_the_thing() {
  setopt localoptions NULL_GLOB
  rm -f "${dir}"/*.tmp
}
_do_the_thing
# Unfunction immediately: named functions inside functions persist in the global
# table after the outer function returns, polluting the namespace at non-subshell
# call sites (direct interactive calls, calls from other functions in the same process).
unfunction _do_the_thing
```

## `is_zsh` guards are for parse-time zsh-only syntax only

Do not wrap a function definition in `if is_zsh; then` unless its body contains
syntax that bash **cannot parse** (e.g. `${(j.:.)array}`, `(( $+functions[...] ))`).
Runtime-only zsh constructs (`setopt`, `autoload`) inside functions that bash
never calls do not need a guard — bash defines the function but never invokes it,
so the runtime failure never occurs.

```zsh
# BAD — setopt is runtime-only; bash can parse this function definition fine.
# The is_zsh guard is redundant and misleads readers into thinking bash would
# fail to parse the body.
if is_zsh; then
  _my_helper() {
    setopt localoptions NULL_GLOB
    rm -f "${dir}"/*.plist
  }
fi

# Good — no guard needed; bash parses it, never calls it
_my_helper() {
  setopt localoptions NULL_GLOB
  rm -f "${dir}"/*.plist
}

# Good — guard IS needed: ${(j.:.)array} is zsh-only syntax that bash cannot
# parse at all, causing a syntax error when the file is loaded
if is_zsh; then
  export RUBYLIB="${(j.:.)rubylib_paths}"
fi
```

## `.envrc` Special Rules

`.envrc` files run in a **bash** subshell via direnv. They must:
- Use POSIX syntax only (no `(( $+functions[...] ))`, no `${(j::)arr}`)
- Source `.shellrc` unconditionally — do NOT guard with `type is_shellrc_sourced`
- Add comment: `# direnv runs this in a bash subshell — source unconditionally`
- Set `set -euo pipefail`, `set -E`, and an ERR trap after sourcing `.shellrc`:

```bash
set -euo pipefail
source "${HOME}/.shellrc"
# set -E ensures the ERR trap is inherited by functions called from this file.
# notify() (from .shellrc) triggers an osascript notification — no terminal needed.
set -E
trap 'notify "Error in ${BASH_SOURCE[0]##*/} (line ${LINENO})" "❌ direnv error"' ERR
```

`info` and `success` are automatically suppressed in direnv subshells because
`.shellrc` guards them with `is_non_zero_string "${DIRENV_IN_ENVRC:-}"`. `DIRENV_DIR`
is intentionally not used: it does not survive direnv's `strict_env` mode. `warn` and
`error` always print. This means `.envrc` files need no extra log suppression
logic — just use the standard logging functions as normal.

## Logging — Level Usage

Use the logging functions from `.shellrc` (`debug`, `info`, `success`, `warn`,
`error`, `user_action`). Never use bare `echo` except for `usage()` output and
code that runs before `.shellrc` is sourced.

| Level | Function | When to use |
|---|---|---|
| `debug` | `debug` | Expected-absent tools or optional steps that are silently skipped (e.g. "mise not in PATH — skipping"). Hidden by default; visible with `DEBUG=true`. |
| `info` | `info` | Normal progress messages and idempotency guards ("already installed — skipping"). Suppressed in direnv subshells. |
| `success` | `success` | An operation completed successfully (e.g. "Successfully sourced ~/.shellrc"). Suppressed in direnv subshells. |
| `warn` | `warn` | Argument-parsing failures (`?`/`:` getopts cases) followed by `usage; return 1`; non-fatal operation failures the script recovers from. |
| `error` | `error` | Unexpected mid-script operation failures that need attention and warrant a macOS notification. **Calls `_dotfiles_notify` — do NOT use for arg-parse failures in interactive scripts** (notification on every typo is bad UX). |
| `user_action` | `user_action` | Manual steps the user must perform after the script exits (restart an app, run a command, open a URL). Distinct from `warn` (unexpected problem) and `info` (purely informational). |

### Argument-parse failures — use `warn`, not `error`

```zsh
while getopts ":fh" opt; do
  case "${opt}" in
    f) flag=true ;;
    h) usage; return 0 ;;
    :) warn "Option -${OPTARG} requires an argument."; usage; return 1 ;;
    ?) warn "Unknown option: -${OPTARG}"; usage; return 1 ;;
  esac
done
```

`error` is intentionally avoided here: it calls `_dotfiles_notify` which fires a
macOS notification pop-up. Triggering a notification because the user typed a
bad flag is poor UX for any interactive script.

### Idempotency guard messages — use `info`, not `warn`

```zsh
if is_executable "brew"; then
  info "Homebrew already installed — skipping."
else
  # install ...
fi
```

These are expected, non-problematic states. `warn` implies something is wrong;
`info` correctly signals "nothing to do here".

### Expected-absent tools — use `debug`, not `warn`

```zsh
if ! command_exists mise; then
  debug "mise not in PATH — skipping mise config loading."
  return 0
fi
```

If a tool is known to be optionally present, its absence is not a warning.

### Action items for the user — use `user_action`, not `warn`

```zsh
user_action "Restart iTerm2 to apply the new font settings."
user_action "Run 'bupc' to update Homebrew packages."
```

These are follow-up instructions, not warnings about something that went wrong.

### Deferred warning collection — immediate vs summary-only

`_record_warning` both stores the warning AND prints it immediately. Use it for
warnings where immediate feedback is valuable (e.g., per-item failures in a loop).

For **aggregated summary messages** computed after processing multiple items
(e.g., "Failed to process N files" with a list), append directly to
`_step_warnings` to avoid duplicate output (immediate print + summary):

```zsh
# Immediate warning — print now AND in summary (typical case)
for item in "${items[@]}"; do
  if ! process_item "${item}"; then
    _record_warning "Failed to process ${item}"
  fi
done

# Summary-only warning — only in final summary (aggregated message)
if is_non_empty_array failed_files; then
  local msg="Failed to process ${#failed_files[@]} file(s):"
  msg+=$'\n'"$(join_array failed_files)"
  _step_warnings+=("[${_SCRIPT_NAME}][${_current_section}] ${msg}")
fi
```

The direct append pattern is the exception, not the rule. Use it only when:
- The message is computed/aggregated after processing multiple items
- Showing it immediately would be confusing or redundant
- The message is only meaningful in the context of the final summary

The pattern mirrors Ruby's `record_warning` (immediate) vs direct append to
`@step_warnings` (summary-only).

## Cron Scripts

Scripts invoked from cron start with a minimal environment.

### Sourcing `.aliases` and `load_zsh_configs`

After sourcing `.aliases`, call `load_zsh_configs` **only if the script uses
variables or functions that are defined in `.zshrc`** (e.g. `PROJECTS_BASE_DIR`,
mise shims, etc.). Do NOT call it unconditionally:

- `load_zsh_configs` sources `.zshrc`, which in turn sources `.zlogin`. `.zlogin`
  triggers background zwc compilation jobs that are disruptive when launched
  from cron with no terminal attached.
- Most cron scripts only need vars from `.shellrc`/`.aliases` (e.g.
  `PERSONAL_CONFIGS_DIR`, `DOTFILES_DIR`) — those are available after sourcing
  `.aliases` without calling `load_zsh_configs`.

```zsh
# Re-source guard is inside .aliases itself — safe to call unconditionally.
load_file_if_exists "${HOME}/.aliases"

# Call load_zsh_configs only when the script needs .zshrc-defined vars/functions
# (e.g. PROJECTS_BASE_DIR, mise shims). Omit if only .shellrc/.aliases vars needed.
# WARNING: load_zsh_configs sources .zlogin which triggers background compilation
# jobs — do not call from cron unless the .zshrc-defined vars are genuinely required.
load_zsh_configs
```

### ERR Trap Instead of `set -e`

Because cron runs without `set -e` in most cases (a single failing step should
not abort all subsequent steps), use an `ERR` trap with `error` for failure
notification instead. `error` from `.shellrc` calls `notify` internally, which
triggers a macOS notification visible to the user even without a terminal:

```zsh
# Do not exit immediately — each update step runs independently.
# error() calls notify() which triggers an osascript notification on failure.
trap 'error "Script failed. Check the log for details."' ERR
```

### ERR Trap — `$LINENO` String Form vs Function Form

When the ERR trap body calls a **function** (`trap my_handler ERR`), `$LINENO`
inside `my_handler` is the line *within the handler*, not the failing command's
line. To capture the failing line, use a **string trap** and pass `$LINENO` as
an argument before the function call — the string is evaluated in the failing
command's scope:

```zsh
# BAD — $LINENO inside _cleanup_and_exit is the handler's own line, not the failing line
trap _cleanup_and_exit ERR

# Good — $LINENO expands in the failing command's scope before _cleanup_and_exit is called
trap '_cleanup_and_exit "${LINENO}"' ERR

# _cleanup_and_exit then accepts it as $1:
_cleanup_and_exit() {
  local failed_line="${1:-}"
  local message='Operation failed.'
  if [[ -n "${failed_line}" ]]; then
    message="Operation failed at line ${failed_line}."
  fi
  error "${message}"
}
```

This rule applies whether `set -E` is active or not. With `set -E`, the trap
fires in the scope of the failing helper function — `$LINENO` in the string
trap correctly reports that helper's line.

### `sudo` in Cron — Always Guard with `has_sudo_credentials`

Any function callable from cron that uses `sudo` must call `has_sudo_credentials`
(defined in `.shellrc` § 1e) first. Without cached credentials, `sudo` hangs
waiting for a password in a non-interactive context. Use `warn` and return
early if the check fails:

```zsh
_my_func() {
  if ! has_sudo_credentials; then
    warn "_my_func: sudo credentials not available — skipping."
    return 0
  fi
  sudo some-command
}
```

### `is_running_in_tty` — Gate Interactive-Only Operations

`is_running_in_tty` returns `false` in cron (no TTY attached, `FORCE_COLOR`
not set). Use it to gate operations that should only run interactively:

```zsh
# Kill/restart apps only on import or when running interactively.
# Cron export must not kill apps mid-session or re-launch them via 'open -a'.
if [[ "${operation}" == 'import' ]] || is_running_in_tty; then
  kill_login_item_apps
  trap 'restart_login_item_apps; cleanup' EXIT
else
  trap 'cleanup' EXIT
fi
```

### `COLUMNS` in Cron

Zsh sets `COLUMNS` to `0` when no terminal is attached. Any code that uses
`COLUMNS` for length calculations must fall back to a sensible default:

```zsh
local viewport_length=${COLUMNS:-80}
```

This applies to `_section_header_impl` and `print_chars_for_length` in
`.shellrc` (already done). Apply the same pattern in any new code that
reads `COLUMNS` outside the startup hot path.

Note: cron scripts must also never call aliases by name — see
**No Aliases in Non-Interactive Scripts** below.

## No Aliases in Non-Interactive Scripts

Unlike bash, zsh's `ALIASES` option is **on by default** in all shells including
non-interactive scripts. Alias expansion itself is not the problem.

The real risk is that aliases defined in `.aliases` are only available **if
`.aliases` has been sourced** in the current process. Scripts run outside a
normal interactive shell (cron jobs, fresh-install subshells, background jobs
via `&|`) may not have sourced `.aliases`. `command_exists` finds the alias in
`$+aliases[...]` when it is defined, but if `.aliases` was never loaded the
alias simply does not exist and invoking it fails with "command not found".

**Rule:** never call an alias by name inside a script. Always use the underlying
command or function it expands to. This removes the dependency on `.aliases`
being loaded and makes the actual command explicit.

```zsh
# BAD — 'home', 'oss', 'bcg' are aliases; if .aliases is not loaded in this
# process (e.g. a cron job, a background &| job, or fresh-install), they are
# undefined and fail with "command not found".
home pull
oss upreb
bcg | grep ...

# Good — use the direct equivalent; no dependency on .aliases being loaded
FOLDER="${HOME}" FILTER='.bin|.dotfiles|zsh|mise' MAXDEPTH=5 run-all.rb git pull
FOLDER="${PROJECTS_BASE_DIR}/oss" MAXDEPTH=4 run-all.rb git upreb
brew outdated --greedy | grep ...
```

When replacing an alias guard (`command_exists <alias>`) also replace it with
a check against the real executable:

```zsh
# BAD — checks for the alias, not the binary; returns false when .aliases is unloaded
if command_exists bcg; then

# Good — checks for the real binary; works regardless of whether .aliases is loaded
if command_exists brew; then
```

Add a comment at the call site explaining the substitution so the next reader
understands why the alias is not used:

```zsh
# 'bcg' alias (brew outdated --greedy) requires .aliases to be loaded; use the
# underlying command directly to avoid that dependency.
brew outdated --greedy | ...
```

When replacing an alias guard (`command_exists <alias>`) also replace it with
a check against the real executable:

```zsh
# BAD — checks for the alias, not the binary
if command_exists bcg; then

# Good — checks for the real binary
if command_exists brew; then
```

Add a comment at the call site explaining the substitution so the next reader
understands why the alias is not used:

```zsh
# 'bcg' alias (brew outdated --greedy) is not expanded in non-interactive shells (cron).
brew outdated --greedy | ...
```

## `notify` — macOS User Notifications

`notify` (defined in `.shellrc`) sends a macOS notification via `osascript`.
Use it in scripts that run without a terminal (cron jobs, direnv) to surface
failures to the user:

```zsh
notify "message text" "Title"   # both args; title defaults to "Dotfiles"
notify "Backup completed"        # title defaults to "Dotfiles"
```

`error` from `.shellrc` calls `notify` automatically — prefer `error` over
calling `notify` directly when reporting failures.

## Cron Suspension — `with_cron_suspended`

For scripts that must not run concurrently with the cron job, use the
`with_cron_suspended` wrapper (defined in `.aliases`). It suspends cron,
runs the given function, then restores cron — including on error via an
internal `EXIT` trap:

```zsh
main() {
  with_cron_suspended _main_impl "$@"
}
```

Do not call `suspend_cron` / `resume_cron` directly in scripts that have a
single entry point — use `with_cron_suspended` instead. Use the low-level
functions only when the suspend/resume scope spans multiple code paths (e.g.
`fresh-install-of-osx.sh` where the scope is the entire `main()`).

## `parse_folder_and_switches` Convention

Autoload scripts that accept an optional leading folder argument followed by
git-style `--flags` use `parse_folder_and_switches` (defined in `.aliases`).
The function writes into `folder` and `switches` in the **caller's scope** —
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

Every file under `files/--XDG_CONFIG_HOME--/zsh/` is a zsh autoload script.
The structure is fixed — all four components must be present in every file:

```zsh
#!/usr/bin/env zsh
# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# <Description of what this command does>
# ...usage/examples...

# Re-source guard is inside .shellrc itself — safe to call unconditionally.
source "${HOME}/.shellrc"

_my_cmd() {
  local folder
  local -a switches
  parse_folder_and_switches "$@"
  # ... implementation ...
}

my_cmd() { dispatch_or_fallback my_cmd _my_cmd "$@"; }

# Run only when executed directly, not when sourced (e.g. to import the function
# into another script).
[[ "${zsh_eval_context}" == *file* ]] || my_cmd "$@"
# is_zsh returns false in bash (ZSH_VERSION unset), short-circuiting the zsh-only
# '(( $+functions[...] ))' syntax so it is never evaluated by non-zsh runtimes.
is_zsh && (($+functions[compdef])) && compdef my_cmd || true
```

### `zsh_eval_context` Self-Invocation Guard

`[[ "${zsh_eval_context}" == *file* ]] || my_cmd "$@"` prevents the function
from running when the file is `source`d by another script. When `*file*` is
present in `zsh_eval_context`, the file is being sourced — skip execution.
When absent, the file is being run directly — execute.

Use `*file*` (not `*:file*`) — the separator before `file` differs by context:
- Sourced from a script: `toplevel:shfunc:file` → colon-separated, matches both
- Sourced in `zsh -c`: `cmdarg file` → space-separated, only `*file*` matches

### `compdef` Registration Guard

```zsh
is_zsh && (($+functions[compdef])) && compdef my_cmd || true
```

Two guards are required:
1. `is_zsh` — returns false in bash (where `ZSH_VERSION` is unset), short-
   circuiting the zsh-only arithmetic expression that follows. `is_zsh` is
   available here because autoload scripts always source `.shellrc` at the top.
2. `(($+functions[compdef]))` — zsh built-in check; `compdef` is only available
   after `compinit` has run. Autoload scripts may be sourced before `compinit`
   (e.g. during `fresh-install`), so this guard prevents a "command not found"
   error.

The trailing `|| true` is required because `(($+functions[compdef]))` exits 1
when `compdef` is not defined (arithmetic 0 = false = exit 1 in zsh). Without
`|| true`, sourcing an autoload script from a script that has an ERR trap (e.g.
a cron job) would fire the trap every time `compdef` is not available.

## `exec`-Wrapper Scripts

Thin dispatcher scripts that exist only to pass fixed arguments to a common
script use `exec` to replace the current process — no `main()`, no
`set -euo pipefail` (irrelevant before `exec`), no return path:

```zsh
#!/usr/bin/env zsh
# vim:filetype=zsh syntax=zsh ...
#
# Wrapper: passes --project foo to db-dump-common.sh.

CALLER_SCRIPT="${0:t}" exec "${0:a:h}/db-dump-common.sh" --project foo "$@"
```

- `${0:a:h}` — absolute path of this script's directory; finds the common
  script portably even if `$PATH` does not include the directory.
- `CALLER_SCRIPT="${0:t}"` — passes the wrapper's own filename into the common
  script's environment so `usage()` displays the correct name.
- `exec` — replaces the wrapper process entirely; no fork, no return path.

### `CALLER_SCRIPT` in Common Scripts

Common scripts (`*-common.sh`) that are invoked via `exec`-wrappers must read
`CALLER_SCRIPT` for their usage output, falling back to `${0:t}` on direct
invocation:

```zsh
usage() {
  local script_name="${CALLER_SCRIPT:-${0:t}}"
  print_usage "${script_name}" ...
}
```

## `require_env_var` Guard

Before sourcing a common script that depends on a specific env var, validate
the var is set using `require_env_var` (defined in `.aliases`). This aborts
with a clear message rather than producing cryptic errors inside the common
script:

```zsh
# Re-source guard is inside .aliases itself — safe to call unconditionally.
load_file_if_exists "${HOME}/.aliases"
require_env_var PERSONAL_BIN_DIR
load_file_if_exists "${PERSONAL_BIN_DIR}/upreb-homebrew-common.sh"
```

## Comment Format

```zsh
################################################################################
# file-header.sh
# Purpose: ...
################################################################################

# ---------------------------------------------------------------------------
# Section Name

# Individual function comments use plain #
function_name() {
  # Implementation detail comment
}
```

## `_DOTFILES_SCRIPT_DEPTH` — Increment and Decrement

Every `main()` that uses the deferred-collection pattern (`_record_warning` /
`_record_error` / `print_script_summary`) **must** both increment the counter
on entry and decrement it on exit:

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

`_decrement_script_depth` is defined in `.shellrc`. When a script already sets
its own EXIT trap later in `main()`, chain the decrement into that trap rather
than setting a separate one — a later `trap ... EXIT` replaces any earlier one:

```zsh
# Scripts with an existing EXIT trap — chain _decrement_script_depth at the end
trap 'restart_login_item_apps; resume_softwareupdate_schedule; _decrement_script_depth' EXIT

# Scripts whose EXIT trap calls a function — add _decrement_script_depth inside
# that function rather than duplicating the trap string
_cleanup_recreate() {
  resume_cron
  _decrement_script_depth
}
trap _cleanup_recreate EXIT
```

`is_outermost_script` (`[[ ${_DOTFILES_SCRIPT_DEPTH:-0} -le 1 ]]`) is used by
`print_script_start` and `print_script_summary` to suppress output from nested
subprocess scripts. The decrement ensures the counter returns to its pre-script
value on exit, which is correct for sourced scripts (subprocess scripts discard
their env on exit regardless). See `TechnicalDeepDive.md` § 6 for the full
rationale on why the decrement is applied even for subprocess-only scripts.

## Edit Checklist — Run After Every Change

After every edit to a shell script, follow these steps **in order**:

### Step 1 — Verify Decision-Making Philosophy

Verify every new or changed line upholds the four priorities defined in
`copilot-instructions.md` § **Decision-Making Philosophy** (startup speed →
maintainability → POSIX compatibility → zsh built-ins). A higher priority
always wins; document the tradeoff in a comment when they conflict. If it
is unclear which priority applies, ask the user before proceeding.

Only continue once every changed line satisfies the highest applicable priority.

### Step 2 — Scan for unsafe `&&` patterns

Scan every standalone `A && B` line in the edited file. If the script uses
`set -e` or an ERR trap, verify that A returning false is an *error*, not a
normal/expected outcome. Fix any unsafe patterns before proceeding
(see **`&&` as Conditional — Safety Under `set -e` / ERR Trap** above).

Only continue to formatting once all unsafe patterns are resolved.

### Step 3 — Reformat with `shfmt`

**Check `.shfmtignore` first.** If the file is listed there, do NOT run `shfmt`
on it — skip formatting entirely for that file. Running `shfmt` on an excluded
file will corrupt intentional one-liners (see below).

Run `shfmt`:

```zsh
shfmt -w <file>
```

**shfmt has no inline per-line or per-block ignore directive.** Whole files can
be excluded via `.shfmtignore`, but only for two valid reasons:

1. The file contains zsh-only syntax that shfmt cannot parse (e.g. `${^array}`,
   `for key value in "${(@kv)assoc}"`).
2. The file hits a shfmt bug where one-liners inside loop or compound bodies are
   forcibly expanded into an unreadable (and often misaligned) multi-line form
   with no way to suppress it. Example — shfmt transforms this intentional
   one-liner:
   ```zsh
   while true; do has_sudo_credentials; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
   ```
   into this broken padded expansion:
   ```zsh
   while true; do
                  sudo -n true
                                sleep 60
                                          kill -0 "$$" || exit
   done                                                          2>/dev/null &
   ```
   The one-liner form is correct and must be preserved. Adding the file to
   `.shfmtignore` is the only reliable fix.

Do not add files to `.shfmtignore` for any other reason.

### Step 4 — Verify All Whitespace Rules

After formatting, the file **MUST pass all three whitespace checks**. This applies
to all text files **except Markdown files** (`.md`), which are exempt from Check 2
only (trailing blank lines).

#### Check 1: File Ends with Newline
```zsh
# Verify file ends with exactly one newline
tail -c 1 <file> | od -An -tx1 | grep -q '0a' || echo "FAIL: Missing final newline"
```

#### Check 2: No Trailing Blank Lines
```zsh
# Verify no blank lines at end of file
tail -n 1 <file> | grep -q '^$' && echo "FAIL: Has trailing blank lines"
```

**Fix:**
```zsh
# Remove trailing blank lines while preserving final newline
sed -i '' -e :a -e '/^\s*$/d;N;ba' <file>
```

#### Check 3: No Trailing Whitespace on Any Line
```zsh
# Verify no lines end with spaces or tabs
grep -n '[[:space:]]$' <file> && echo "FAIL: Lines above have trailing whitespace"
```

**Fix:**
```zsh
# Remove trailing whitespace from all lines
sed -i '' 's/[[:space:]]*$//' <file>
```

#### All-in-One Verification
```zsh
if tail -c 1 <file> | od -An -tx1 | grep -q '0a' && \
   ! tail -n 1 <file> | grep -q '^$' && \
   ! grep -q '[[:space:]]$' <file>; then
  echo "✅ All whitespace checks pass"
else
  echo "❌ Whitespace violations found"
fi
```

**When using the Edit tool:**
- Ensure `newString` ends with exactly one newline
- No blank lines after the last content line
- No trailing spaces/tabs on any line

**Why this matters:**
- Consistent file endings across the repository
- Cleaner diffs (no spurious blank line changes)
- Matches the output of `shfmt`, `rufo`, and linters
- Reduces visual noise in version control
- POSIX compliance

**Exceptions:**
- **Markdown files (`.md`)** are exempt from Check 2 only (trailing blank lines may be intentional for formatting). Checks 1 and 3 still apply.
- **Cryptographic files (`.key`, `.pem`)** must not be modified — they are generated by external tooling and any modification breaks their integrity.

### Step 5 — Ensure Executable Permission

After editing shell scripts, ensure they have executable permission. This is especially important if your editing method rewrites the file (which can lose the executable bit).

**Check if executable:**
```zsh
[[ -x path/to/script.sh ]] && echo "✅ Executable" || echo "❌ Not executable"
```

**Restore executable permission:**
```zsh
chmod +x path/to/script.sh
```

**Applies to:**
- All scripts in `$DOTFILES_DIR/scripts/` (`.sh`, `.zsh`)
- All scripts in `$PERSONAL_BIN_DIR/` (`.sh`, `.zsh`, `.bash`)
- Autoload functions in `$XDG_CONFIG_HOME/zsh/` (`.zsh` files)

**Why:** Scripts must be executable to run. Without this permission, they fail with "Permission denied" errors.
