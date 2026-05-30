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

Never collapse a two-step `local` + assignment back into a single line, even
though it may look redundant. The split is intentional.

## Quoting and Variable References

### Always Quote Variables

Always quote variables to prevent word-splitting and glob expansion when the
value is used in a context where it could contain spaces:

```zsh
# Good — quoted, safe if value contains spaces
cp "${src_file}" "${dest_dir}/"
[[ -f "${config_path}" ]]
info "Processing ${filename}"

# BAD — unquoted, breaks if value contains spaces
cp $src_file $dest_dir/
[[ -f $config_path ]]
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

## Pipelines with `grep`

`grep -q` in a pipeline under `set -o pipefail` causes SIGPIPE:

```zsh
# BAD
some_command | grep -q "pattern"

# Good
some_command | grep -q "pattern" || true
# Or better, capture output first
output=$(some_command)
is_non_zero_string "${output}" && echo "${output}" | grep -q "pattern"
```

## Function Visibility

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

# Join
result=$(join_array ", " "${my_arr[@]}")
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
`.shellrc` guards them with `is_non_zero_string "${DIRENV_DIR:-}"`. `warn` and
`error` always print. This means `.envrc` files need no extra log suppression
logic — just use the standard logging functions as normal.

## Cron Scripts

Scripts invoked from cron start with a minimal environment. After sourcing
`.aliases`, call `load_zsh_configs` explicitly to bring all zsh configs into
scope:

```zsh
# Re-source guard is inside .aliases itself — safe to call unconditionally.
load_file_if_exists "${HOME}/.aliases"
# This script is invoked from cron, which starts a minimal environment.
# load_zsh_configs must be called explicitly to bring all zsh configs into scope.
load_zsh_configs
```

Because cron runs without `set -e` in most cases (a single failing step should
not abort all subsequent steps), use an `ERR` trap with `error` for failure
notification instead. `error` from `.shellrc` calls `notify` internally, which
triggers a macOS notification visible to the user even without a terminal:

```zsh
# Do not exit immediately — each update step runs independently.
# error() calls notify() which triggers an osascript notification on failure.
trap 'error "Script failed. Check the log for details."' ERR
```

Note: cron scripts must also never call aliases by name — see
**No Aliases in Non-Interactive Scripts** below.

## No Aliases in Non-Interactive Scripts

Zsh **disables alias expansion** in non-interactive shells (scripts, cron jobs,
`zsh -c`, `zsh -lsc`). Aliases defined in `.aliases` are never expanded when a
script is parsed, even if `.aliases` has been sourced. `command_exists` will
find the alias in `$+aliases[...]`, but invoking it as a command will fail with
"command not found".

**Rule:** never call an alias by name inside a script. Always use the underlying
command or function it expands to.

```zsh
# BAD — 'home', 'oss', 'bcg' are aliases; they expand in interactive shells
# but fail silently (command not found) in scripts and cron jobs.
home pull
oss upreb
bcg | grep ...

# Good — use the direct equivalent
FOLDER="${HOME}" FILTER='.bin|.dotfiles|zsh|mise' MAXDEPTH=5 run-all.sh git pull
FOLDER="${PROJECTS_BASE_DIR}/oss" MAXDEPTH=4 run-all.sh git upreb
brew outdated --greedy | grep ...
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
# ZSH_VERSION guard ensures the zsh-only '(( $+functions[...] ))' syntax is never
# evaluated by non-zsh runtimes (e.g. direnv's sandbox).
[[ -n "${ZSH_VERSION-}" ]] && (($+functions[compdef])) && compdef my_cmd || true
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
[[ -n "${ZSH_VERSION-}" ]] && (($+functions[compdef])) && compdef my_cmd || true
```

Two guards are required:
1. `[[ -n "${ZSH_VERSION-}" ]]` — POSIX string test guards against non-zsh
   runtimes (e.g. direnv's bash subshell) where the next expression would be
   a syntax error.
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

## Formatting After Every Edit

After every edit to a shell script, reformat with `shfmt`:

```zsh
shfmt -w <file>
```

**Check `.shfmtignore` first.** If the file is listed there, do NOT run `shfmt`
on it — skip formatting entirely for that file. Running `shfmt` on an excluded
file will corrupt intentional one-liners (see below).

**shfmt has no inline per-line or per-block ignore directive.** Whole files can
be excluded via `.shfmtignore`, but only for two valid reasons:

1. The file contains zsh-only syntax that shfmt cannot parse (e.g. `${^array}`,
   `for key value in "${(@kv)assoc}"`).
2. The file hits a shfmt bug where one-liners inside loop or compound bodies are
   forcibly expanded into an unreadable (and often misaligned) multi-line form
   with no way to suppress it. Example — shfmt transforms this intentional
   one-liner:
   ```zsh
   while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
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
