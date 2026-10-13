---
applyTo: "**/*.sh*,**/.shellrc,**/.aliases,**/.envrc,**/.zsh*,**/files/--XDG_CONFIG_HOME--/zsh/*,**/scripts/**"
name: dotfiles-shell-portability-cron
description: Use when a shell script in this dotfiles repo must run under bash/direnv or cron, or deals with portability pitfalls -- bash compatibility gotchas in .shellrc, `.envrc` rules, cron scripts and cron suspension, `is_zsh` guards, NULL_GLOB globbing, cache invalidation, shebang choice, exec-wrapper scripts, and `notify`.
---

# Shell Portability, Cron and Caching Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules when a shell script must work outside an interactive zsh session (bash, direnv, cron) or maintains cached output.

**Related files**:
- [`shell-scripting.md`](./shell-scripting.md) - Core rules (utility functions, template, logging, quoting, `&&` safety) -- read this first
- [`shell-functions-autoload.md`](./shell-functions-autoload.md) - Function and autoload structure
- [`zsh-startup.md`](./zsh-startup.md) - Startup performance

## `source` vs `load_file_if_exists`
`.shellrc` has been downloaded and sourced. The rule is:

- **Before `.shellrc` is sourced** (e.g., early boot of `fresh-install` on a
  vanilla OS): use plain `source` with an explicit existence check, or accept
  that the file must be present.
- **After `.shellrc` is sourced**: always prefer `load_file_if_exists` over
  `source` for any file that may not exist on all machines or in all scenarios.

```zsh
# Early boot -- .shellrc not yet available, use source with guard
[[ -f "${HOME}/.shellrc" ]] && source "${HOME}/.shellrc"

# After .shellrc is sourced -- use load_file_if_exists
load_file_if_exists "${ZDOTDIR}/.some-optional-file"
```

**Note:** `load_file_if_exists` includes `|| warn` on the source command to catch
failures from external files (e.g., Homebrew completion scripts) without triggering
ERR traps. This is safe because external files may contain `&&` chains or other
constructs that return non-zero in normal operation.

**Note:** `load_file_if_exists` also calls `recompile_zsh_script` on the target
file before sourcing it, keeping its `.zwc` bytecode cache in sync in every
context that uses it -- not just interactive shells covered by `.zlogin`'s bulk
recompile pass (cron jobs, scripts, direnv's bash subshell all benefit too).
Overhead is negligible: a couple of stat calls (no fork), and it only actually
recompiles when the source is newer than the existing `.zwc` (its fast path returns after
a couple of raw `-f`/`-nt` tests, ~17us per call). `recompile_zsh_script`
guards its `autoload -Uz zrecompile` call behind `is_zsh` since `.shellrc` (where
both functions live) must remain bash-parseable for direnv's bash subshell.

## Cache Invalidation Pattern

When implementing mtime-based cache invalidation (comparing a cache file against
its source), use the `is_file_older_than` helper instead of repeating the
`[[ ! -f ... || ... -nt ... ]]` pattern.

```zsh
# Good -- semantic helper encapsulates the cache staleness check
if is_file_older_than "${cache}" "${source}"; then
  generate_cache
fi
load_file_if_exists "${cache}"

# BAD -- repeated boilerplate, easy to get the logic backwards
if ! is_file "${cache}" || [[ "${source}" -nt "${cache}" ]]; then
  generate_cache
fi
load_file_if_exists "${cache}"
```

### `is_file_older_than` -- Cache Staleness Helper

**Definition** (from `.shellrc`):
```zsh
# Returns true if target file ($1) is missing or older than source file ($2).
# Symlinks are followed by -f and -nt themselves, so edits/upgrades to symlink targets
# are detected (e.g., Homebrew binaries, dotfiles symlinked from the repo).
# Uses the shell's built-in -nt (newer-than) test which compares modification times.
# Common pattern: if is_file_older_than "${cache}" "${source}"; then regenerate_cache; fi
#
# Arguments:
#   $1 - target file path (typically a cache file)
#   $2 - source file path (typically a binary or config file)
#
# Returns:
#   0 (true) if target is missing or source is newer (regeneration needed)
#   1 (false) if target exists and is newer than or same age as source (cache valid)
is_file_older_than() {
  # A single [[ ]]: true if either argument is missing/empty, the target is not a regular
  # file, or the source is newer.
  [[ -z "${1:-}" || -z "${2:-}" || ! -f "${1}" || "${2}" -nt "${1}" ]]
}
```

**Usage**:
- First argument: the cache file (what you're checking)
- Second argument: the source file (what it depends on)
- Returns true when cache needs regeneration
- Symlinks are followed by the `-f`/`-nt` tests themselves, so Homebrew binary upgrades are detected
- Safe with empty/unset parameters (returns true = regenerate)

**Common use cases**:
```zsh
# Binary-based cache (e.g., brew shellenv, starship init, mise activate)
if is_file_older_than "${cache}" "${binary}"; then
  "${binary}" --generate-cache > "${cache}"
fi

# Config-based cache (e.g., antidote bundle)
if is_file_older_than "${bundle}" "${plugins_txt}"; then
  antidote bundle < "${plugins_txt}" > "${bundle}"
fi

# Directory-based cache (e.g., keg-only paths)
# Inverted logic: cache is valid when NOT older than directory
if ! is_file_older_than "${cache}" "${homebrew_opt_dir}"; then
  load_file_if_exists "${cache}"
  return
fi
```

**Why use the helper**:
1. **Semantic clarity**: Name describes intent ("is cache stale?")
2. **DRY principle**: Single implementation of the staleness check
3. **Symlink safety**: Resolves symlinks automatically (Homebrew binaries are symlinks)
4. **Defensive**: Handles empty/unset parameters gracefully (safe default: regenerate)
5. **Maintainability**: Changes to cache logic apply everywhere
6. **Readability**: `is_file_older_than` reads like English

**When NOT to use**:
- One-off comparisons that don't follow the cache pattern
- When you need custom staleness logic (e.g., multiple source files)

## Glob Patterns -- NULL_GLOB

`setopt localoptions NULL_GLOB` scoped to a function body is the only permitted
way to enable NULL_GLOB. The scoping vehicle depends on whether the file can be
sourced by bash (see below).

- **Never use bare `setopt NULL_GLOB`** at script, function, or top-level scope --
  the change persists for the rest of the process and leaks into every caller.
- **Never use `unsetopt NULL_GLOB`** -- if you find yourself needing to unset it,
  you set it globally in the first place, which is the mistake to fix.
- **Never use inline `(N)` glob qualifiers** -- they are parsed by most editor
  syntax highlighters as function calls, breaking highlighting for the rest of
  the line.

### Anonymous function `()` vs named helper

The `()` anonymous-function syntax is zsh-only. Bash **cannot parse** it -- not
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
# BAD -- NULL_GLOB leaks to the rest of the script / caller
setopt NULL_GLOB
rm -f "${dir}"/*.plist "${dir}"/*.defaults
unsetopt NULL_GLOB

# BAD -- inline (N) qualifier breaks editor syntax highlighting
rm -f "${dir}"/*.plist(N) "${dir}"/*.defaults(N)

# BAD in .shellrc -- () is zsh-only syntax; bash cannot parse this file at all,
# even if the block is guarded by 'if is_zsh' (bash parses before executing)
() {
  setopt localoptions NULL_GLOB
  rm -f "${dir}"/*.plist "${dir}"/*.defaults
}

# Good in pure zsh files (.zshrc, autoload scripts, zsh-only scripts) --
# () is valid; restored automatically when the anonymous function returns
() {
  setopt localoptions NULL_GLOB
  rm -f "${dir}"/*.plist "${dir}"/*.defaults
}

# Good in .shellrc (bash-parseable files) -- named helper; bash can parse
# 'name() {}' syntax and never calls this function in a bash context
_remove_loose_files() {
  setopt localoptions NULL_GLOB
  rm -f "${dir}"/*.plist "${dir}"/*.defaults
}
_remove_loose_files
```

## `is_zsh` guards are for parse-time zsh-only syntax only

Do not wrap a function definition in `if is_zsh; then` unless its body contains
syntax that bash **cannot parse**. Runtime-only zsh constructs (`setopt`,
`autoload`, `${(j.:.)array}`, `(( $+functions[...] ))`, `${+var}`, `${(P)var}`,
negative array indices) inside functions that bash never calls do not need a
guard -- bash defines the function but never invokes it, so the runtime failure
never occurs. See § Bash Compatibility Gotchas Discovered in `.shellrc` below
for the full catalog of constructs, split by parse-time vs runtime-only, plus
a third category that is far more dangerous than either: constructs that parse
AND run under bash but silently produce the *wrong result* with no error at all.

```zsh
# BAD -- setopt is runtime-only; bash can parse this function definition fine.
# The is_zsh guard is redundant and misleads readers into thinking bash would
# fail to parse the body.
if is_zsh; then
  _my_helper() {
    setopt localoptions NULL_GLOB
    rm -f "${dir}"/*.plist
  }
fi

# Good -- no guard needed; bash parses it, never calls it
_my_helper() {
  setopt localoptions NULL_GLOB
  rm -f "${dir}"/*.plist
}

# BAD -- ${(j.:.)array} is NOT a parse-time failure (confirmed empirically:
# 'bash -n' accepts this fine) -- it only fails with 'bad substitution' if
# actually *evaluated*. A guard is still correct here, but for the runtime
# reason, not a parse-time one.
if is_zsh; then
  export RUBYLIB="${(j.:.)rubylib_paths}"
fi

# Good -- guard IS needed for a genuine parse-time reason: '-v "arr[key]"'
# breaks bash's own '[[ ]]' conditional-expression parser, not just its
# runtime evaluator. Confirmed empirically: even wrapping it in
# 'if is_zsh; then ... fi', or moving it into a separate function that bash
# never calls, does not help -- bash must still tokenize a function's body to
# find its closing brace when *defining* it, so a parse-time error inside an
# unreached branch still breaks sourcing the whole file. The only fix is to
# avoid the construct in files bash may source at all (see the '-v' entry in
# § Bash Compatibility Gotchas below for the actual portable replacement used
# in this codebase).
if is_zsh; then
  if [[ ! -v "_SOME_ARRAY[${key}]" ]]; then
    echo "not cached"
  fi
fi
```

## Bash Compatibility Gotchas Discovered in `.shellrc`

`.shellrc` must remain not just bash-*parseable* but bash-*functionally
correct*, since direnv sources it in a bash subshell (see `path-constants.md`
and the `.envrc` rules below) and scripts are free to `source ~/.shellrc`
directly from bash. A systematic audit of every zsh-specific construct in
`.shellrc` surfaced three distinct failure classes, ordered from most to least
dangerous:

### Class 1: Silently wrong, no error at all (most dangerous)

These constructs neither fail to parse nor throw a runtime error under bash --
they just quietly compute the wrong answer, which is why they went unnoticed
for a long time. **Always add an explicit regression test comparing output
across both shells when touching code in this class.**

| Construct | Bash behavior | Fix used in `.shellrc` |
|---|---|---|
| `${var:A}` (zsh absolute-path resolution) | Bash parses `:A` as substring-offset arithmetic; an undefined identifier like `A` evaluates to `0` in arithmetic context, so `${var:A}` == `${var:0}` == the original string, completely unresolved -- no symlink following, no absolute-path conversion, no error | `_resolve_absolute_path <varname> <path>` helper: zsh branch uses `${path:A}` directly (zero-fork); bash branch is a `readlink`-loop + `cd ... && pwd -P` (no dependency on GNU `readlink -f`/`realpath`, neither of which macOS ships by default) |
| `path+=...` / `fpath+=...` (zsh's `${PATH}`/`${FPATH}`-tied special arrays) | Bash has no such tying -- `path`/`fpath` are just ordinary, unrelated variables there. `path+="/foo"` silently creates/appends to a scalar named `path`, never touching `${PATH}` at all | `append_to_path_if_dir_exists`: bash branch manipulates `${PATH}` directly with an idempotent `case` dedup check. `append_to_fpath_if_dir_exists` is a documented **intentional no-op** under bash -- bash has no `${FPATH}`/function-autoloading concept at all, so there is nothing meaningful to fall back to |
| `${EPOCHSECONDS}` / `strftime` (zsh's `zsh/datetime` module) | Both are simply undefined under bash -- `${EPOCHSECONDS}` expands to an empty string (no error), and bare `strftime` is "command not found" (but only surfaces if stderr isn't redirected) | `_epoch_seconds <varname>` (zsh: `${EPOCHSECONDS}`, zero-fork; bash: forks `date +%s`) and `_strftime <varname> <format> <epoch>` (zsh: `strftime -s`; bash: BSD `date -j -f '%s'`, since this codebase is macOS-only) |

### Class 2: Parses under bash, fails only at runtime (safe to guard with `is_zsh`)

These constructs are real bash tokens that bash's parser accepts without
complaint -- the failure only happens if the branch is actually *executed*.
A plain `if is_zsh; then ... fi` (or `... else <bash fallback> fi`) is the
correct and sufficient fix.

| Construct | Runtime failure under bash | Confirmed via |
|---|---|---|
| `${+var}` / `${+arr[key]}` (zsh "is-set" flag) | `bad substitution` | `bash -c '(( ! ${+arr[0]} ))'` |
| `${(P)1}` / `${(@P)name}` (indirect parameter/array-by-name expansion) | `bad substitution` | `bash -c 'echo ${#${(P)1}[@]}'` called with an array name |
| `${(j:...:)array}` / `${(j.:.)array}` (array join) | `bad substitution` | `bash -c 'x="${(j:; :)arr}"'` |
| `arr[-1]` (negative array index) | `bad array subscript` | bash added negative indices in 4.3+; macOS's default `/bin/bash` is 3.2 |
| `${(@)arr[1,-2]}` (zsh array slice) | `bad substitution` | same reasoning as negative indices above |
| `typeset -A` / `typeset -gT` (associative arrays / scalar-array ties) | `typeset: -A: invalid option` | bash 3.2 predates both (added in bash 4.0/4.2 respectively); no guaranteed Homebrew bash in `PATH` either |

### Class 3: Fails to parse under bash -- breaks the entire file (most obviously dangerous, but not fixable with `is_zsh`)

Only one construct in `.shellrc` fell into this class, but it's the one that
matters most to recognize, because the usual `is_zsh` guard **does not help**:

| Construct | Why `is_zsh` doesn't help |
|---|---|
| `[[ -v "arr[key]" ]]` (associative-array key-existence test) | Confirmed empirically (see § `is_zsh` guards are for parse-time zsh-only syntax only above): bash's own `[[ ]]` parser rejects this token sequence at *definition* time, before any runtime guard is ever consulted. Even isolating it into a helper function that is only ever called from an `is_zsh`-guarded call site still breaks sourcing, because bash must fully tokenize a function's body (to find its closing brace) the moment it *defines* the function, not when it's called |

The fix used in `.shellrc`'s `_set_log_indent`: replace `[[ ! -v "arr[key]" ]]` with
`[[ -z "${arr[key]:-}" ]]` (emptiness check instead of existence check). This
is not a universal drop-in replacement -- it changes behavior for keys whose
legitimate value IS an empty string (they will be needlessly recomputed every
call instead of using the cached empty value) -- but for `_set_log_indent`'s cache
specifically, an empty string is only ever the depth-1 value, where
recomputation is a single trivial `printf` call, so the correctness/performance
tradeoff is negligible.

**General principle when auditing zsh-only syntax for bash compatibility**:
1. Check with `bash -n <file>` first -- Class 3 constructs abort the *entire
   file*, so fix these before anything else.
2. For everything that parses, actually **execute** the code path under bash
   (not just `bash -n`) -- Class 1 constructs produce no diagnostic of any
   kind, so a clean `bash -n` and even a clean run with no visible errors does
   not mean the output is correct. Compare actual output between `zsh -c` and
   `bash -c` invocations of the same function call.
3. Only Class 2 constructs are safe to fix with a bare `if is_zsh; then ... fi`
   guard around the existing zsh code, optionally with an `else` bash fallback.

## `.envrc` Special Rules

`.envrc` files run in a **bash** subshell via direnv. They must:
- Use POSIX syntax only (no `(( $+functions[...] ))`, no `${(j::)arr}`)
- Source `.shellrc` unconditionally -- do NOT guard with `type is_shellrc_sourced`
- Add comment: `# direnv runs this in a bash subshell -- source unconditionally`
- Set `set -euo pipefail`, `set -E`, and an ERR trap after sourcing `.shellrc`:

```bash
set -euo pipefail

source "${HOME}/.shellrc"

# set -E ensures the ERR trap is inherited by functions called from this file.
# notify() (from .shellrc) triggers a macOS notification (terminal-notifier or osascript fallback).
set -E
trap 'notify "Error in ${BASH_SOURCE[0]##*/} (line ${LINENO})" "❌ direnv error"' ERR
```

`info`, `success`, `print_script_start`, and `print_script_duration` are automatically
suppressed in direnv subshells because `.shellrc` guards them with
`is_non_zero_string "${DIRENV_IN_ENVRC:-}"`. `DIRENV_DIR` is intentionally not used:
it does not survive direnv's `strict_env` mode. `warn` and `error` always print.
This means `.envrc` files need no extra log suppression logic -- just use the
standard logging functions as normal.

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
  `PERSONAL_CONFIGS_DIR`, `DOTFILES_DIR`) -- those are available after sourcing
  `.aliases` without calling `load_zsh_configs`.

```zsh
# Re-source guard is inside .aliases itself -- safe to call unconditionally.
load_file_if_exists "${ZDOTDIR}/.aliases"

# Call load_zsh_configs only when the script needs .zshrc-defined vars/functions
# (e.g. PROJECTS_BASE_DIR, mise shims). Omit if only .shellrc/.aliases vars needed.
# WARNING: load_zsh_configs sources .zlogin which triggers background compilation
# jobs -- do not call from cron unless the .zshrc-defined vars are genuinely required.
load_zsh_configs
```

### ERR Trap Instead of `set -e`

Because cron runs without `set -e` in most cases (a single failing step should
not abort all subsequent steps), use an `ERR` trap with `error` for failure
notification instead. `error` from `.shellrc` calls `notify` internally, which
triggers a macOS notification visible to the user even without a terminal:

```zsh
# Do not exit immediately -- each update step runs independently.
# error() calls notify() which triggers a macOS notification (terminal-notifier or osascript).
trap 'error "Script failed. Check the log for details."' ERR
```

### ERR Trap -- `${LINENO}` String Form vs Function Form

When the ERR trap body calls a **function** (`trap my_handler ERR`), `${LINENO}`
inside `my_handler` is the line *within the handler*, not the failing command's
line. To capture the failing line, use a **string trap** and pass `${LINENO}` as
an argument before the function call -- the string is evaluated in the failing
command's scope:

```zsh
# BAD -- ${LINENO} inside _cleanup_and_exit is the handler's own line, not the failing line
trap _cleanup_and_exit ERR

# Good -- ${LINENO} expands in the failing command's scope before _cleanup_and_exit is called
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
fires in the scope of the failing helper function -- `${LINENO}` in the string
trap correctly reports that helper's line.

**Debugging misleading line numbers:** ERR trap line numbers can be misleading when:
1. **Subprocess failures**: A Ruby/Python script called from shell exits non-zero, triggering
   the trap at the script invocation line, not the actual failure inside the subprocess
2. **Function call failures**: A function deep in the call stack fails, but `${LINENO}` reports
   the line where the outermost function was called
3. **At-exit hook failures**: Ruby `at_exit` hooks that raise or call `exit(1)` cause the
   parent shell to receive non-zero exit code after the script body completes successfully

**Diagnostic techniques:**
- Add `info "Reached checkpoint X"` messages before suspected failure points
- Check if success messages after the reported line never appear in output
- Look for subprocess output (warnings, errors) that indicates where the real failure occurred
- Remember: reported line may be where the *trap was set*, not where it *fired*

### `sudo` in Cron -- Always Guard with `has_sudo_credentials`

Any function callable from cron that uses `sudo` must call `has_sudo_credentials`
(defined in `.shellrc` § 1e) first. Without cached credentials, `sudo` hangs
waiting for a password in a non-interactive context. Use `warn` and return
early if the check fails:

```zsh
_my_func() {
  if ! has_sudo_credentials; then
    warn "_my_func: sudo credentials not available -- skipping."
    return 0
  fi
  sudo some-command
}
```

### `is_running_in_tty` -- Gate Interactive-Only Operations

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

This applies to `section_header` and `print_chars_for_length` in
`.shellrc` (already done). Apply the same pattern in any new code that
reads `COLUMNS` outside the startup hot path.

Note: cron scripts must also never call aliases by name -- see
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
# BAD -- 'home', 'oss', 'bcg' are aliases; if .aliases is not loaded in this
# process (e.g. a cron job, a background &| job, or fresh-install), they are
# undefined and fail with "command not found".
home pull
oss upreb
bcg | grep ...

# Good -- use the direct equivalent; no dependency on .aliases being loaded
FOLDER="${HOME}" FILTER='.bin|.dotfiles|zsh|mise' MAXDEPTH=5 run-all.rb git pull
FOLDER="${PROJECTS_BASE_DIR}/oss" MAXDEPTH=4 run-all.rb git upreb
brew outdated --greedy | grep ...
```

When replacing an alias guard (`command_exists <alias>`) also replace it with
a check against the real executable:

```zsh
# BAD -- checks for the alias, not the binary; returns false when .aliases is unloaded
if command_exists bcg; then

# Good -- checks for the real binary; works regardless of whether .aliases is loaded
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
# BAD -- checks for the alias, not the binary
if command_exists bcg; then

# Good -- checks for the real binary
if command_exists brew; then
```

Add a comment at the call site explaining the substitution so the next reader
understands why the alias is not used:

```zsh
# 'bcg' alias (brew outdated --greedy) is not expanded in non-interactive shells (cron).
brew outdated --greedy | ...
```

## `notify` -- macOS User Notifications

`notify` (defined in `.shellrc`) sends a macOS notification via `osascript`.
Use it in scripts that run without a terminal (cron jobs, direnv) to surface
failures to the user:

```zsh
notify "message text" "Title"   # both args; title defaults to "Dotfiles"
notify "Backup completed"        # title defaults to "Dotfiles"
```

`error` from `.shellrc` calls `notify` automatically -- prefer `error` over
calling `notify` directly when reporting failures.

## Cron Suspension -- `Cron.with_cron_suspended`

For scripts that must not run concurrently with the cron job, use
`Cron.with_cron_suspended` (`scripts/utilities/cron.rb`) -- Ruby only; there is no
shell equivalent. It suspends cron, yields to the block, then restores cron --
including on an exception or an early `return`, via an `ensure` clause:

```ruby
Cron.with_cron_suspended { run_main_logic }
```

A script that needs this should be a Ruby script (or a Ruby override of a git
command -- see `git-overrides.md` § Per-Repo Overrides for Lifecycle Management). In
shell, use the low-level `suspend_cron` / `resume_cron` functions only when the
suspend/resume scope spans multiple code paths (e.g. `fresh-install-of-osx.sh`
where the scope is the entire `main()`); `.shellrc` keeps pure-shell fallbacks of
these so they work before the dotfiles repo is cloned.

## Shebang Choice

- **zsh scripts** (use `.shellrc`, zsh builtins): `#!/usr/bin/env zsh` -- zsh may live in
  Homebrew rather than `/bin`, so it must be found via `PATH`.
- **Ruby scripts**: `#!/usr/bin/env ruby`; hot entry points that never need a gem use `#!/usr/bin/env -S ruby --disable-gems` (see `ruby-scripting.md` § RubyGems -- Off on Hot Entry Points).
- **Plain POSIX `sh` scripts** that must run anywhere with no repo/shell setup (`wait-editor`,
  the `scripts/git-<name>` git subcommands): `#!/bin/sh`, NOT `#!/usr/bin/env sh`. `/bin/sh` is a
  fixed, guaranteed path on macOS and Linux, so `env` adds an extra exec and a `PATH` lookup for
  nothing -- and under cron's minimal `PATH`, or a `PATH` shadowed by mise/Homebrew, it can only
  make resolution less predictable. Keep such scripts strictly POSIX (no arrays, `[[ ]]`, `local`
  or `${var:t}`): on macOS `/bin/sh` is bash 3.2 in POSIX mode, on Debian/Ubuntu it is `dash`.
  Verify with `sh -n` and `dash -n`.

## `exec`-Wrapper Scripts

Thin dispatcher scripts that exist only to pass fixed arguments to a common
script use `exec` to replace the current process -- no `main()`, no
`set -euo pipefail` (irrelevant before `exec`), no return path:

```zsh
#!/usr/bin/env zsh
# vim:filetype=zsh syntax=zsh ...
#
# Wrapper: passes --project foo to db-dump-common.sh.

CALLER_SCRIPT="${0:t}" exec "${0:a:h}/db-dump-common.sh" --project foo "$@"
```

- `${0:a:h}` -- absolute path of this script's directory; finds the common
  script portably even if `${PATH}` does not include the directory.
- `CALLER_SCRIPT="${0:t}"` -- passes the wrapper's own filename into the common
  script's environment so `usage()` displays the correct name.
- `exec` -- replaces the wrapper process entirely; no fork, no return path.

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
