---
applyTo: "**/*.sh*,**/.shellrc,**/.aliases,**/.envrc,**/.zsh*,**/files/--XDG_CONFIG_HOME--/zsh/*,**/scripts/**"
---

# Shell Script Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules when writing or editing any shell script in this repository.

Syntax choices follow the decision-making priority defined in
[`instructions.md`](../instructions.md) (startup speed + maintainability first; POSIX and
zsh built-ins where they do not conflict with those). Document the tradeoff in
a comment when they conflict.

## Scope

**This file applies to**: All shell scripts, zsh configuration, and shell functions in the repository, including:
- Executable scripts in `${DOTFILES_DIR}/scripts/*.sh` (e.g., `fresh-install-of-osx.sh`, `osx-defaults.sh`)
- Executable scripts in `${PERSONAL_BIN_DIR}/*.sh` (personal automation scripts)
- Shell configuration files (`.shellrc`, `.aliases`, `.envrc`, `.zshenv`, `.zshrc`, `.zlogin`)
- Autoload functions in `${XDG_CONFIG_HOME}/zsh/`
- Git alias bodies in `.gitconfig` (shell command strings)
- Shell scripts invoked via subprocess from Ruby (e.g., `system('zsh', '-c', '...')`)

**Related files**:
- [`logging-conventions.md`](./logging-conventions.md) - Cross-language logging and color standards
- [`script-depth-tracking.md`](./script-depth-tracking.md) - Nesting depth tracking in shell
- [`path-constants.md`](./path-constants.md) - Environment variable usage and quoting
- [`zsh-startup.md`](./zsh-startup.md) - Zsh-specific startup optimizations
- [`edit-checklist.md`](./edit-checklist.md) - Post-edit verification workflow

**Does NOT apply to**: Ruby scripts (see `ruby-scripting.md`), external shell scripts from third-party tools, or shell commands in documentation examples.

## Quick Reference

| Task | Pattern | Section Link |
|------|---------|--------------|
| Source .shellrc | `source "${HOME}/.shellrc"` | [§ Mandatory: Source .shellrc](#mandatory-source-shellrc-for-utility-functions) |
| Positional param with default | `dir="${1:-.}"` | [§ Positional Parameters](#positional-parameters) |
| Check file exists | `is_file "${path}"` | [§ Prefer Utility Functions](#prefer-utility-functions-over-raw-shell-tests) |
| Check directory exists | `is_directory "${path}"` | [§ Prefer Utility Functions](#prefer-utility-functions-over-raw-shell-tests) |
| Avoid subshell fork | `${PWD:t}` not `$(basename "$PWD")` | [§ Zsh Parameter Expansion](#zsh-parameter-expansion-for-basename) |
| For loop variable | `local item; for item in ...` | [§ `local` and `unset`](#local-and-unset----correct-usage) |
| Safe conditional | `if A; then B; fi` not `A && B` | [§ `&&` as Conditional](#-as-conditional----safety-under-set--e--err-trap) |
| Logging | `info`, `success`, `warn`, `error`, `debug` | [§ Logging](#logging) |
| Git operations | `git -C "${dir}"` | [§ git-config.md](./git-config.md) |
| Script depth tracking | `export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))` | [§ Script Depth Tracking](./script-depth-tracking.md) |

## File Naming Convention

**All shell scripts use kebab-case (hyphens), matching Unix CLI tool conventions.**

| Type | Pattern | Examples | Rationale |
|------|---------|----------|-----------|
| **Executable scripts** | kebab-case | `fresh-install-of-osx.sh`, `osx-defaults.sh` | Standard Unix convention; easier to type on command line |
| **Common libraries** | kebab-case | `db-dump-common.sh`, `upreb-homebrew-common.sh` | Consistency with main scripts that source them |
| **Single-word scripts** | no separator | N/A - most shell scripts are multi-word descriptive names | No separator needed if single word |

**Why kebab-case for shell:**
- Matches Unix ecosystem conventions (`git-log`, `npm-install`, `docker-compose`)
- Easier to type on command line (no Shift key for underscores)
- Consistent with Ruby executable scripts (see ruby-scripting.md § File Naming Convention)

**Applies to:**
- `${DOTFILES_DIR}/scripts/*.sh` - All shell scripts use kebab-case
- `${PERSONAL_BIN_DIR}/*.sh` - All shell scripts use kebab-case
- Autoload functions in `${XDG_CONFIG_HOME}/zsh/` - Single-word names (no separator)

**Autoload function naming**: Zsh autoload functions in `${XDG_CONFIG_HOME}/zsh/` use single-word names by design (e.g., `upreb`, `status`, `push`). This is not a "no separator needed" exception—it's a deliberate convention for autoloaded commands that matches shell built-in naming patterns (`cd`, `ls`, `git`, `grep`).

## Function Naming Convention

**All shell functions use snake_case (underscores), following Unix and Ruby conventions.**

```zsh
# Good -- public functions use snake_case
current_timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
clone_repo_into() { ... }
is_file() { ... }

# Good -- private/internal functions use snake_case with leading underscore
_log_indent() { ... }
_colorize() { ... }
_strip_ansi() { ... }

# BAD -- kebab-case is for file names, not function names
current-timestamp() { ... }   # Wrong
clone-repo-into() { ... }     # Wrong
```

**Why snake_case for functions:**
- Matches Ruby method naming (consistency across shell/Ruby boundary)
- Standard Unix shell convention (most bash/zsh codebases use snake_case)
- Easier to type than kebab-case (no need to type hyphens in function names)
- Functions often wrap Ruby methods with identical names: `status_all_repos()` → `GitWorkspace.status_all_repos`

**Private function prefix:**
- Internal helpers must be prefixed with `_` (see § Internal Helpers below)
- Public functions (called by users or other scripts) have no prefix

**Cross-reference:**
- File naming: § File Naming Convention (above)
- Private helpers: § Internal Helpers -- `_` Prefix Convention (below)

## Mandatory: Source .shellrc for Utility Functions

**All shell scripts MUST source `${HOME}/.shellrc` to access utility functions.**

```zsh
# At the top of every script, after set -euo pipefail
# Re-source guard is inside .shellrc itself -- safe to call unconditionally.
source "${HOME}/.shellrc"
```

**Why this is mandatory:**
- `.shellrc` provides essential utility functions used throughout scripts:
  - Logging: `info`, `success`, `warn`, `error`, `debug`, `user_action`
  - Validation: `is_file`, `is_directory`, `is_non_zero_string`, `nil_or_empty`
  - Git operations: `clone_repo_into`, `migrate_git_repo_to_reftable`
  - Script infrastructure: `print_script_start`, `print_script_summary`, `print_usage`
  - Cron management: `suspend_cron`, `resume_cron`, `with_cron_suspended`
  - Path utilities: `ensure_dir_exists`, `load_file_if_exists`
  - Logging helpers: `section_header`, `current_timestamp`
- Ensures consistent behavior across all scripts
- Scripts without `.shellrc` sourced cannot use any utility functions
- The re-source guard inside `.shellrc` prevents duplicate loading overhead

**Exceptions:**
- `.shellrc` itself (cannot source itself)
- Scripts that run BEFORE `.shellrc` exists (bootstrap phase in `fresh-install-of-osx.sh`)
- Git hooks that deliberately avoid dependencies (rare - most should still source it)

**Pattern for git hooks:**
Even simple git hooks should source `.shellrc` if they use any utility functions:

```zsh
#!/usr/bin/env zsh
# Global pre-push hook

set -euo pipefail

# Source .shellrc for utility functions (is_file, suspend_cron, etc.)
source "${HOME}/.shellrc"

# Now you can use utility functions
if is_file "${script}"; then
  "${script}" "$@"
fi
```

**Verification:**
If a script uses functions like `info`, `warn`, `is_file`, `ensure_dir_exists`, etc., but does NOT source `.shellrc`, it will fail with "command not found" errors.

## Prefer Utility Functions Over Raw Shell Tests

**Always use `.shellrc` utility functions instead of raw shell test operators.**

This improves:
- **Readability**: `is_file "${path}"` vs `[[ -f "${path}" ]]`
- **Consistency**: Single implementation across all scripts
- **Maintainability**: Bug fixes in one place benefit all callers
- **Safety**: Utility functions handle edge cases (empty strings, special characters)

### Common Substitutions

| Instead of | Use | Notes |
|------------|-----|-------|
| `[[ -f "${file}" ]]` | `is_file "${file}"` | File existence check |
| `[[ -d "${dir}" ]]` | `is_directory "${dir}"` | Directory existence check (excludes root `/`) |
| `[[ -x "${file}" ]]` | `is_executable "${file}"` | Executable file check |
| `[[ -f "${file}" && -x "${file}" ]]` | `is_executable "${file}"` | Combines both checks |
| `[[ -n "${var}" ]]` | `is_non_zero_string "${var}"` | Non-empty string check |
| `[[ -z "${var}" ]]` | `nil_or_empty "${var}"` | Nil or empty check (handles nil safely) |
| `[[ "${path}" == "/" ]]` | `is_root_dir "${path}"` | Check if path is root directory |
| `$(basename "$(pwd)")` | `${PWD:t}` | Get directory basename (no subshell fork) |
| `$(basename "${path}")` | `${path:t}` | Get path basename (no subshell fork) |

**Note**: `is_directory` returns false for root (`/`) to prevent accidental operations on the filesystem root. Ruby equivalent: `PathUtils.valid_directory?` (see `scripts/utilities/path_utils.rb`).

**Note**: `is_root_dir` is used to check if a directory path is root before write operations. Use bash-compatible `${path%/*}` to get parent directory (not `${path:h}` which is zsh-only). Pattern: `is_root_dir "${path%/*}"`. Ruby equivalent: `PathUtils.root_dir?`.

### Examples

```zsh
# BAD -- raw shell tests
if [[ -f "${config}" && -x "${config}" ]]; then
  "${config}"
fi

if [[ -d "${PERSONAL_BIN_DIR}" ]]; then
  basename="$(basename "$(pwd)")"
  script="${PERSONAL_BIN_DIR}/${basename}.sh"
  if [[ -x "${script}" ]]; then
    "${script}"
  fi
fi

# Good -- utility functions + zsh parameter expansion
if is_executable "${config}"; then
  "${config}"
fi

if is_directory "${PERSONAL_BIN_DIR}"; then
  basename="${PWD:t}"
  script="${PERSONAL_BIN_DIR}/${basename}.sh"
  if is_executable "${script}"; then
    "${script}"
  fi
fi

# Good -- root directory protection before write operations
# Use ${var%/*} for bash compatibility (direnv sources .shellrc in bash)
if is_root_dir "${target_path%/*}"; then
  error "Refusing to operate on path in root: '${target_path}'"
fi
rm -f "${target_path}"
```

### Bash vs Zsh Parameter Expansion

**.shellrc must use bash-compatible syntax** because direnv sources it in a bash subshell.

| Operation | Zsh-only | Bash-compatible | Notes |
|-----------|----------|-----------------|-------|
| Get parent directory | `${path:h}` | `${path%/*}` | Use `%/*` in .shellrc |
| Get basename | `${path:t}` | `${path##*/}` | Use zsh `:t` where possible (faster) |

**Rule**: In .shellrc and .aliases, use `${var%/*}` for parent directory extraction to support direnv's bash subprocess. In pure zsh files (.zshrc, .zlogin, autoload functions), `${var:h}` is preferred.

### Zsh Parameter Expansion for Basename

**Prefer `${PWD:t}` and `${path:t}` over `$(basename ...)` to avoid subshell forks.**

The `:t` modifier extracts the tail (basename) of a path without creating subprocesses:

```zsh
# BAD -- two subshell forks
basename="$(basename "$(pwd)")"
filename="$(basename "${full_path}")"

# Good -- zsh parameter expansion (no subshell, faster)
basename="${PWD:t}"
filename="${full_path:t}"
```

**Why this matters:**
- **Performance**: Every `$(...)` forks a new process (expensive)
- **Simplicity**: Fewer moving parts, less error-prone
- **Consistency**: Idiomatic zsh pattern

This applies to all zsh code: scripts, hooks, functions, startup files, interactive use.

### Zsh Parameter Expansion Modifiers Reference

**Zsh provides built-in modifiers that eliminate subprocess forks for common path operations.**

Use these modifiers for zero-cost path manipulation (no fork, no external process):

| Modifier | Operation | Example | Bash Alternative |
|----------|-----------|---------|------------------|
| `:t` | Basename (tail) | `${path:t}` | `${path##*/}` |
| `:h` | Dirname (head) | `${path:h}` | `${path%/*}` |
| `:r` | Remove extension | `${file:r}` | `${file%.*}` |
| `:e` | Extension only | `${file:e}` | `${file##*.}` |
| `:a` | Absolute path | `${path:a}` | `$(realpath "$path")` |
| `:A` | Absolute + resolve symlinks | `${path:A}` | `$(readlink -f "$path")` |
| `:u` | Uppercase | `${var:u}` | `${var^^}` (bash 4+) |
| `:l` | Lowercase | `${var:l}` | `${var,,}` (bash 4+) |

**Examples:**

```zsh
# Path manipulation (zero cost)
full_path="/usr/local/bin/ruby"
basename="${full_path:t}"           # "ruby" (not $(basename "$full_path"))
dirname="${full_path:h}"            # "/usr/local/bin" (not $(dirname "$full_path"))
without_ext="${full_path:r}"        # "/usr/local/bin/ruby" (no change, no extension)

file="script.sh"
name_only="${file:r}"               # "script" (not ${file%.sh})
extension="${file:e}"               # "sh" (not ${file##*.})

# Absolute paths (replaces realpath/readlink subprocess)
relative="../../scripts/file.sh"
absolute="${relative:a}"            # "/Users/vijay/.config/dotfiles/scripts/file.sh"
resolved="${relative:A}"            # Same but follows symlinks

# Case conversion (zero cost)
upper="${var:u}"                    # "HELLO" (not $(echo "$var" | tr '[:lower:]' '[:upper:]'))
lower="${var:l}"                    # "hello" (not $(echo "$var" | tr '[:upper:]' '[:lower:]'))

# Script name extraction (common pattern)
_SCRIPT_NAME="${0:t}"               # Basename of current script (not $(basename "$0"))
script_dir="${0:a:h}"               # Absolute dir of current script (not $(cd "$(dirname "$0")" && pwd))
```

**Combining modifiers:**

```zsh
# Chain modifiers with multiple colons
script_path="/path/to/script.rb"
script_name="${script_path:t:r}"    # "script" (basename + remove extension)

# Get absolute directory of current script
script_dir="${0:a:h}"               # :a (absolute) then :h (dirname)

# Get absolute path to sibling file
sibling="${0:a:h}/config.yml"       # No subprocess needed
```

**When to use each:**

| Use Case | Modifier | Replaces |
|----------|----------|----------|
| Get script name | `${0:t}` | `$(basename "$0")` |
| Get script directory | `${0:a:h}` | `$(cd "$(dirname "$0")" && pwd)` |
| Remove file extension | `${file:r}` | `${file%.ext}` or `$(basename "$file" .ext)` |
| Get file extension | `${file:e}` | `${file##*.}` |
| Resolve to absolute path | `${path:a}` | `$(realpath "$path")` |
| Follow symlinks | `${path:A}` | `$(readlink -f "$path")` |

**Bash compatibility notes:**

- `:t` and `:h` modifiers are zsh-only
- Use `${var##*/}` (basename) and `${var%/*}` (dirname) in bash-compatible code
- `.shellrc` must use bash syntax (direnv sources it in bash subprocess)
- Pure zsh files (.zshrc, .zlogin, autoload functions) can use `:t` and `:h` freely

**Performance impact:**

```zsh
# BAD -- 3 subprocess forks
script_dir="$(cd "$(dirname "$0")" && pwd)"
basename="$(basename "$script_dir")"
name_only="$(basename "${file}" .rb)"

# Good -- zero forks
script_dir="${0:a:h}"
basename="${script_dir:t}"
name_only="${file:t:r}"
```

Each `$(...)` fork costs ~1-2ms. In hot paths (startup, loops), this compounds quickly.

**See also:**
- § Bash vs Zsh Parameter Expansion (line 220) - Compatibility table
- zsh-startup.md § No Subshell Forks - Hot path optimization patterns
- `man zshexpn` - Complete zsh parameter expansion documentation

### When Raw Tests Are Acceptable

Raw shell tests ARE acceptable when:
- **Before `.shellrc` is sourced** (bootstrap phase in `fresh-install-of-osx.sh`)
- **Performance-critical hot paths** where function call overhead matters (rare)
- **Inside utility function implementations** in `.shellrc` itself

In all other cases, prefer utility functions for consistency and maintainability.

## Script Template

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
# Re-source guard is inside .shellrc itself -- safe to call unconditionally.
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
it via dynamic scoping to prefix their output -- no argument needed). Library
functions that want the calling script's name should reference
`${_SCRIPT_NAME:-<interactive>}` with a fallback -- the variable is absent in
interactive sessions where no script is active.

### `print_usage` over `cat <<EOF`

Always use `print_usage` (defined in `.shellrc`) for usage output -- not
`cat <<EOF`. `print_usage` accepts the script name as `$1` followed by
variadic color-formatted option lines:

```zsh
usage() {
  print_usage "${_SCRIPT_NAME}" \
    "$(yellow '-f') <file>   Description of -f" \
    "$(yellow '-h')          Show this help"
}
```

`usage()` must reference `${_SCRIPT_NAME}` directly -- never accept the script
name as a parameter and never call `usage "${_SCRIPT_NAME}"` at the call site.
Call sites always invoke `usage` with no arguments:

```zsh
# BAD -- passing _SCRIPT_NAME as an argument is redundant; usage() can read it directly
usage() { print_usage "${1}" ...; }
usage "${_SCRIPT_NAME}"

# Good -- usage() references _SCRIPT_NAME directly; call sites pass no argument
usage() { print_usage "${_SCRIPT_NAME}" ...; }
usage
```

Exception: `*-common.sh` scripts use `${CALLER_SCRIPT:-${0:t}}` instead of
`${_SCRIPT_NAME}` so the wrapper script's name appears in usage output -- see
§ **`exec`-Wrapper Scripts**.

## Logging

Use the logging functions from `.shellrc` (`debug`, `info`, `success`, `warn`,
`error`, `user_action`). Never use bare `echo` except for `usage()` output and
code that runs before `.shellrc` is sourced.

See [`logging-conventions.md`](./logging-conventions.md) for complete rules on:
- Message prefixes (`[script][section]`) for RCA
- Deferred error/warning collection
- Color standards

| Level | Function | When to use |
|---|---|---|
| `debug` | `debug` | Expected-absent tools or optional steps that are silently skipped (e.g. "mise not in PATH -- skipping"). Hidden by default; visible with `DEBUG=true`. |
| `info` | `info` | Normal progress messages and idempotency guards ("already installed -- skipping"). Suppressed in direnv subshells. |
| `success` | `success` | An operation completed successfully (e.g. "Successfully sourced ~/.shellrc"). Suppressed in direnv subshells. |
| `warn` | `warn` | Argument-parsing failures (`?`/`:` getopts cases) followed by `usage; return 1`; non-fatal operation failures the script recovers from. |
| `error` | `error` | Unexpected mid-script operation failures that need attention and warrant a macOS notification. **Calls `_dotfiles_notify` -- do NOT use for arg-parse failures in interactive scripts** (notification on every typo is bad UX). |
| `user_action` | `user_action` | Manual steps the user must perform after the script exits (restart an app, run a command, open a URL). Distinct from `warn` (unexpected problem) and `info` (purely informational). |

### Argument-parse failures -- use `warn`, not `error`

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

### Idempotency guard messages -- use `info`, not `warn`

```zsh
if is_executable "brew"; then
  info "Homebrew already installed -- skipping."
else
  # install ...
fi
```

These are expected, non-problematic states. `warn` implies something is wrong;
`info` correctly signals "nothing to do here".

### Expected-absent tools -- use `debug`, not `warn`

```zsh
if ! command_exists mise; then
  debug "mise not in PATH -- skipping mise config loading."
  return 0
fi
```

If a tool is known to be optionally present, its absence is not a warning.

### Action items for the user -- use `user_action`, not `warn`

```zsh
user_action "Restart iTerm2 to apply the new font settings."
user_action "Run 'bupc' to update Homebrew packages."
```

These are follow-up instructions, not warnings about something that went wrong.

### Deferred Error/Warning Collection

`_record_warning` both stores the warning AND prints it immediately. Use it for
warnings where immediate feedback is valuable (e.g., per-item failures in a loop).

For **aggregated summary messages** computed after processing multiple items
(e.g., "Failed to process N files" with a list), append directly to
`_step_warnings` to avoid duplicate output (immediate print + summary):

```zsh
# Immediate warning -- print now AND in summary (typical case)
for item in "${items[@]}"; do
  if ! process_item "${item}"; then
    _record_warning "Failed to process ${item}"
  fi
done

# Summary-only warning -- only in final summary (aggregated message)
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

## Script Depth Tracking

See [`script-depth-tracking.md`](./script-depth-tracking.md) for complete details on `_DOTFILES_SCRIPT_DEPTH`.

**Quick summary for shell**:
- Increment on entry: `export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))`
- Decrement on exit: `trap '_decrement_script_depth' EXIT`
- Dual purpose: nesting suppression (outermost only prints banners) + auto-indentation (2 spaces per depth)
- Never manually indent log messages
- Bulleted lists: `join_array` auto-indents one level deeper
- External tool output intentionally unindented

## Path Constants

See [`path-constants.md`](./path-constants.md) for complete rules on environment variables, path construction, and avoiding hardcoded paths.

**Quick summary for shell**:
- Always use `${VAR}` with braces (not bare `$VAR`)
- Always quote: `"${DOTFILES_DIR}/scripts"`
- Never hardcode derived paths: use `${XDG_CONFIG_HOME}` not `"${HOME}/.config"`
- Available constants: `${DOTFILES_DIR}`, `${PERSONAL_BIN_DIR}`, `${XDG_CONFIG_HOME}`, etc.

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
echo "${HOME}/.config"
local path="${DOTFILES_DIR}/scripts"
```

Exception: `$?`, `$#`, `$@`, `$*`, `$$`, `$!`, `$-` -- the single-character
special parameters do not need braces.

## Option Parsing -- `getopts` vs Long Flags

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
empty -- use it for required flag arguments.

## Quoting and Variable References

### Always Quote Variables

Always quote variables to prevent word-splitting and glob expansion when the
value is used in a context where it could contain spaces:

```zsh
# Good -- quoted, safe if value contains spaces
cp "${src_file}" "${dest_dir}/"
is_file "${config_path}"
info "Processing ${filename}"

# BAD -- unquoted, breaks if value contains spaces
cp $src_file $dest_dir/
is_file $config_path
info "Processing $filename"
```

### Single Quotes vs Double Quotes

Prefer **single quotes** for static strings that contain no variable references
or command substitutions. Use **double quotes** when the string contains a
variable reference or needs escape interpretation:

```zsh
# Good -- single quotes for static strings
local sep='------'
grep -q 'pattern'
error 'File not found'

# Good -- double quotes when expanding variables
local msg="Processing ${repo_name}"
source "${HOME}/.shellrc"
info "Done: ${count} files processed"

# BAD -- double quotes on strings with no variable expansion (unnecessary)
local sep="------"
grep -q "pattern"   # fine if no special chars, but prefer single quotes
```

Exception: prefer **double quotes** over single quotes when the static string
contains single quotes that would otherwise require `$'...\n...'` escaping or
concatenation. Double quotes allow literal single quotes inside and support
literal newlines, making multiline strings significantly more readable:

```zsh
# BAD -- $'...' with escaped single quotes is hard to read
user_action $'Restart \'Terminal\' and \'iTerm\':\n  \'ProtonVPN\' - may drop VPN.'

# Good -- double quotes; single quotes are literal, newline is literal
user_action "Restart 'Terminal' and 'iTerm':
  'ProtonVPN' - may drop VPN."
```

## Exit Points -- `return` vs `exit` in `main()`

Always use `return` (never `exit`) inside `main()`. `exit` terminates the entire
shell process -- if the script is ever sourced, it kills the calling shell. `return`
exits only the function; the script process then exits with that return code because
`main "$@"` is the last line.

```zsh
# BAD -- exit inside main() terminates the calling shell if the script is sourced
main() {
  if is_zero_string "${folder}"; then
    warn 'Missing required argument'
    usage
    exit 1   # BAD
  fi
  ensure_keybase_logged_in || exit 1   # BAD
}

# Good -- return propagates the exit code via 'main "$@"' at the bottom
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
- Trap handler functions (`_cleanup_and_exit`, ERR/EXIT traps) -- these run outside
  the normal call stack and must terminate the process.
- Git `!` alias bodies -- git runs them in a subprocess shell; `exit` propagates
  the code back to git.

**Scan rule:** when editing any script, flag every `exit` inside `main()` and
replace with `return`. Leave `exit` in trap handlers and git alias bodies.

## Internal Helpers -- `_` Prefix Convention

**All internal/private helper functions must be prefixed with `_` to signal they are script-internal and not part of the public API.**

```zsh
# BAD -- helper not prefixed with underscore
read_config_file() {
  # ...
}

process_item() {
  # ...
}

# main execution
items=(...)
for item in "${items[@]}"; do
  process_item "${item}"
done

# Good -- helpers prefixed with underscore
_read_config_file() {
  # ...
}

_process_item() {
  # ...
}

# main execution
items=(...)
for item in "${items[@]}"; do
  _process_item "${item}"
done

# Public functions exported for use by other scripts
public_function() { ... }    # no prefix - part of public API
```

**Rules:**
- **All** helper functions that are not the main entry point or intended for external use must be prefixed with `_`
- Main execution code (option parsing, main logic) comes after helper definitions
- Functions in `.shellrc` and `.aliases` that are intended to be called by users or other scripts should NOT have underscore prefix
- Functions in `.shellrc` and `.aliases` that are only called internally (like `_log_indent`, `_colorize`, `_strip_ansi`) MUST have underscore prefix

**Applies to:**
- Helper functions in standalone scripts (anything in `${DOTFILES_DIR}/scripts/*.sh`)
- Helper functions in `${PERSONAL_BIN_DIR}/*.sh`
- Internal implementation functions in `.shellrc` and `.aliases`

**Exception:** Autoload functions in `${XDG_CONFIG_HOME}/zsh/` follow a dual-function pattern where the public wrapper (no underscore) calls a private implementation (with underscore):

```zsh
# Autoload function pattern
_status_all_repos() {
  # Implementation
  _call_ruby_git_workspace status_all_repos
}

status_all_repos() {
  dispatch_or_fallback status_all_repos _status_all_repos "$@"
}
```

This pattern allows `dispatch_or_fallback` to choose between Ruby module mode (fast, when available) and shell fallback mode (when Ruby unavailable).

## Deleting Functions -- Mandatory Codebase Scan

**Before deleting ANY function as "unused", perform a comprehensive codebase scan to verify no call sites exist.**

A function is NOT unused until verified by:
1. **Grep all shell files**: `grep -rn "function_name" files/ scripts/`
2. **Grep all Ruby files**: `grep -rn "function_name" scripts/` (Ruby may call shell functions via `system()`)
3. **Check git history**: `git log --all -S"function_name()" --oneline` (verify not recently added elsewhere)
4. **Check all branches**: `git grep "function_name" $(git branch -a | grep -v HEAD)`

**Why simple search isn't enough**:
- Functions may be called from autoload scripts or other repositories
- Call sites may use aliases or wrapper functions
- Functions may be called from code in other branches being developed
- Ruby scripts may call shell functions via `system()`, `Open3.capture3()`, etc.

**Safe deletion checklist**:
```bash
# 1. Search all shell files for function name
grep -rn "function_name" files/ scripts/

# 2. Search all Ruby files (may call via system/Open3)
grep -rn "function_name" scripts/

# 3. Check if recently added in other branches
git log --all --since="6 months ago" -S"function_name()" --oneline

# 4. Search across all branches (not just current)
for branch in $(git branch -a | grep -v HEAD); do
  echo "=== $branch ==="
  git grep "function_name" $branch -- '*.sh' '*.zsh' '*.rb' || true
done

# 5. Syntax check all files after deletion
find files -name "*.zsh" -o -name "*.sh" | xargs -n1 zsh -n
find scripts -name "*.rb" -exec ruby -c {} \;
```

**Only delete when ALL checks pass**: No matches in current branch, no matches in other branches, no recent additions in git history.

**Cross-reference**: See identical rule in [`ruby-scripting.md`](./ruby-scripting.md) § Deleting Methods/Functions for Ruby-specific guidance.

## Unified Color Standard (Shell + Ruby)

**See [`logging-conventions.md`](./logging-conventions.md) for the complete unified color standard.**

That file documents:
- Color classification rules (paths, commands, components, booleans, counts, etc.)
- Application guidelines
- Language-specific syntax (shell vs Ruby)
- Deferred error/warning collection
- Script depth tracking
- Message prefixes

The rules apply equally to shell and Ruby scripts for consistency across the codebase.

## Comment Philosophy

See [`comment-philosophy.md`](./comment-philosophy.md) for complete rules,
rationale, and examples, including comment format conventions.

## Character Encoding and Punctuation

See [`character-encoding.md`](./character-encoding.md) for complete rules on ASCII-only requirements, Unicode restrictions, and allowed exceptions.

## Formatting After Every Edit

After every edit to a shell script, follow the complete workflow in [`edit-checklist.md`](./edit-checklist.md).

Quick summary for shell scripts:
1. Verify decision-making philosophy
2. Scan for unsafe `&&` patterns (see [§ `&&` as Conditional](#-as-conditional----safety-under-set--e--err-trap))
3. Syntax check: `zsh -n <file>`
4. Format: `shfmt -w <file>` (check `.shfmtignore` first)
5. Remove consecutive empty lines: `awk 'NF {blank=0; print} !NF {if (!blank) print; blank=1}' <file>`
6. Verify whitespace rules (see [`whitespace-rules.md`](./whitespace-rules.md))
7. Ensure executable permission: `chmod +x <file>`

### Consecutive Empty Lines

**Shell scripts must not have consecutive empty lines (2+ blank lines in a row).**

```zsh
# BAD -- two blank lines between functions

function_one() {
  # ...
}

function_two() {
  # ...
}

# Good -- single blank line between functions

function_one() {
  # ...
}

function_two() {
  # ...
}
```

**Remove consecutive empty lines:**
```bash
# Collapse 2+ consecutive blank lines into 1
awk 'NF {blank=0; print} !NF {if (!blank) print; blank=1}' <file> > <file>.tmp && mv <file>.tmp <file>
```

**Verification:**
```bash
# Check for consecutive empty lines (3+ newlines = 2+ blank lines)
grep -Pzo '\n\n\n' <file> && echo "Has consecutive empty lines" || echo "OK"
```

**Exception:** `CHANGELOG.md` may have consecutive empty lines for visual separation between version sections.

This rule applies to all shell scripts in the repository.

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
- Scripts that call `defaults write` / `killall` (macOS settings -- non-zero is normal)
- Scripts that call `find` / `rm` where "no matches" is expected and non-fatal
- Cron scripts where `set -e` would abort on the first update tool failure,
  preventing all subsequent update steps from running (use an `ERR` trap instead)

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

Always guard positional parameters with a default to avoid `unbound variable`
errors under `set -u`:

```zsh
local arg="${1:-}"   # Good
local arg="$1"       # BAD under set -u if $1 not provided
```

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

## `&&` as Conditional -- Safety Under `set -e` / ERR Trap

`A && B` where A returning false (exit 1) is a **normal, expected outcome** is
unsafe in any script that uses `set -e` or an ERR trap. When A returns 1, the
overall `&&` expression also returns 1 -- that non-zero result triggers `set -e`
abort or fires the ERR trap, even though no actual error occurred.

The fix is always an explicit `if` statement, which never propagates a non-zero
exit code from the predicate to the enclosing scope.

### Why `set -e` Triggers on `&&` False

Bash/zsh's `set -e` (exit on error) considers ANY non-zero exit code an "error" unless explicitly handled. The `&&` operator returns the right-hand side's exit code if the left succeeds, OR the left-hand side's exit code if it fails.

When the left side returns non-zero (false condition), the entire `&&` expression returns non-zero. Since it's not in an explicit conditional context (`if`), `set -e` sees "command returned 1" and triggers.

**Example**:
```zsh
set -e
is_file "${optional}"  # Returns 1 (false) - file doesn't exist
# set -e sees: "Last command exited 1" → abort script

# With &&
is_file "${optional}" && process  # Left side returns 1
# set -e sees: "&& expression exited 1" → abort script

# With if
if is_file "${optional}"; then process; fi
# set -e sees: "if statement (success=0 even if condition false)" → continue
```

The `if` statement itself always exits 0 (it executed successfully), so `set -e` never triggers regardless of the condition's result.

```zsh
# BAD -- is_file returning false (file absent) is normal; fires set -e / ERR trap
is_file "${optional_config}" && cp "${optional_config}" "${dest}"

# BAD -- is_zero_string returns 1 for every non-empty string (the common case)
is_zero_string "${app_pref}" && continue

# BAD -- is_non_empty_array returns 1 for empty array (the success/clean-run case)
is_non_empty_array failed_repos && exit 1

# BAD -- is_non_zero_string returns 1 for empty string (e.g. a clean cron run)
is_non_zero_string "${outdated_flat}" && _msg+=". Needs manual update: ${outdated_flat}"

# BAD -- early return guard where condition returning false is normal
_should_suppress_log && return 0
is_empty_array arr && return

# BAD -- conditional operation where false is normal
[[ -n "${DEBUG:-}" ]] && echo "loading ${0}"

# Good -- explicit if; predicate exit code never reaches the enclosing scope
if is_file "${optional_config}"; then cp "${optional_config}" "${dest}"; fi
if is_zero_string "${app_pref}"; then continue; fi
if is_non_empty_array failed_repos; then exit 1; fi
if is_non_zero_string "${outdated_flat}"; then _msg+=". Needs manual update: ${outdated_flat}"; fi
if _should_suppress_log; then return 0; fi
if is_empty_array arr; then return; fi
if [[ -n "${DEBUG:-}" ]]; then echo "loading ${0}"; fi
```

**Common patterns that need conversion:**

1. **Early return guards** -- functions that return early based on a condition:
   ```zsh
   # BAD
   _should_suppress_log && return 0

   # Good
   if _should_suppress_log; then return 0; fi
   ```

2. **Re-source guards** -- checking if a file has already been sourced:
   ```zsh
   # BAD
   [[ -n "${ZSH_VERSION-}" ]] && (($+functions[is_shellrc_sourced])) && return

   # Good
   if [[ -n "${ZSH_VERSION-}" ]] && (($+functions[is_shellrc_sourced])); then
     return
   fi
   ```

3. **Conditional DEBUG output** -- debug statements that only print when DEBUG is set:
   ```zsh
   # BAD
   [[ -n "${DEBUG:-}" ]] && echo "loading ${0}"

   # Good
   if [[ -n "${DEBUG:-}" ]]; then echo "loading ${0}"; fi
   ```

4. **Validation function chains** -- functions whose return value is a validation result:
   ```zsh
   # BAD -- both is_file and && [[ -s ]] can return false normally
   is_non_empty_file() {
     is_file "${1:-}" && [[ -s "${1:-}" ]]
   }

   # Good -- explicit if/return with clear success/failure branches
   is_non_empty_file() {
     if is_file "${1:-}" && [[ -s "${1:-}" ]]; then
       return 0
     else
       return 1
     fi
   }
   ```

**Safe exception -- `A && B || C` dispatch:**

`A && B || C` (run B on success, C on failure) is safe when C always returns 0.
The overall expression resolves to C's exit code, which is 0 -- the ERR trap
never fires. This pattern is correct for intentional success/failure branching:

```zsh
# Good -- C (_record_error / _record_warning) always returns 0; ERR trap never fires
update_all_repos && success 'Updated repos' || _record_error 'Failed to update repos'
git pull -r && success "Updated: ${folder}" || _record_warning "Failed: ${folder}"

# Can also be written as explicit if/else for clarity
if update_all_repos; then
  success 'Updated repos'
else
  _record_error 'Failed to update repos'
fi
```

**Scan rule:** when editing any script that uses `set -e` or an ERR trap, scan
every standalone `A && B` line and verify that A returning false is an *error*
(not a normal/expected case). If it is expected, convert to `if A; then B; fi`.

## Arithmetic Increment -- Safety Under `set -e`

`(( var++ ))` uses post-increment: it evaluates to the *old* value of `var`.
When `var` is `0`, `(( 0 ))` is arithmetic false (exit code 1), which triggers
`set -e` abort or fires the ERR trap -- silently killing the script at the first
iteration of any counter that starts at zero.

```zsh
# BAD -- (( 0 )) on the first iteration; fires set -e and silently aborts
(( count++ ))

# Good -- += 1 always evaluates to the new value (≥ 1); || true is a safety net
# for any edge case where the result could reach 0 (e.g. wrap-around)
(( count += 1 )) || true
```

The same applies to `(( var-- ))` when `var` reaches `1` (post-decrement
returns `1`, then evaluates to `0` on the next call). Use `(( var -= 1 )) || true`.

**Scan rule:** whenever adding or reviewing an arithmetic counter in a script
that uses `set -e`, replace bare `(( var++ ))` / `(( var-- ))` with
`(( var += 1 )) || true` / `(( var -= 1 )) || true`.

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
recompiles when the source is newer than the existing `.zwc`. `recompile_zsh_script`
guards its `autoload -Uz zrecompile` call behind `is_zsh` since `.shellrc` (where
both functions live) must remain bash-parseable for direnv's bash subshell.

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
# Resolves symlinks before comparison to ensure edits/upgrades to symlink targets
# are detected (e.g., Homebrew binaries, dotfiles symlinked from the repo).
# Uses the shell's built-in -nt (newer-than) test which compares modification times.
# Common pattern: if is_file_older_than "$cache" "$source"; then regenerate_cache; fi
#
# Arguments:
#   $1 - target file path (typically a cache file)
#   $2 - source file path (typically a binary or config file)
#
# Returns:
#   0 (true) if target is missing or source is newer (regeneration needed)
#   1 (false) if target exists and is newer than or same age as source (cache valid)
is_file_older_than() {
  # Return true (needs regeneration) if either argument is missing/empty
  [[ -z "${1:-}" || -z "${2:-}" ]] && return 0
  local target="${1:A}"
  local source="${2:A}"
  [[ ! -f "${target}" || "${source}" -nt "${target}" ]]
}
```

**Usage**:
- First argument: the cache file (what you're checking)
- Second argument: the source file (what it depends on)
- Returns true when cache needs regeneration
- Automatically resolves symlinks so Homebrew binary upgrades are detected
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
| `path+=...` / `fpath+=...` (zsh's `$PATH`/`$FPATH`-tied special arrays) | Bash has no such tying -- `path`/`fpath` are just ordinary, unrelated variables there. `path+="/foo"` silently creates/appends to a scalar named `path`, never touching `$PATH` at all | `append_to_path_if_dir_exists`: bash branch manipulates `$PATH` directly with an idempotent `case` dedup check. `append_to_fpath_if_dir_exists` is a documented **intentional no-op** under bash -- bash has no `$FPATH`/function-autoloading concept at all, so there is nothing meaningful to fall back to |
| `$EPOCHSECONDS` / `strftime` (zsh's `zsh/datetime` module) | Both are simply undefined under bash -- `${EPOCHSECONDS}` expands to an empty string (no error), and bare `strftime` is "command not found" (but only surfaces if stderr isn't redirected) | `_epoch_seconds <varname>` (zsh: `$EPOCHSECONDS`, zero-fork; bash: forks `date +%s`) and `_strftime <varname> <format> <epoch>` (zsh: `strftime -s`; bash: BSD `date -j -f '%s'`, since this codebase is macOS-only) |

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

The fix used in `.shellrc`'s `_log_indent`: replace `[[ ! -v "arr[key]" ]]` with
`[[ -z "${arr[key]:-}" ]]` (emptiness check instead of existence check). This
is not a universal drop-in replacement -- it changes behavior for keys whose
legitimate value IS an empty string (they will be needlessly recomputed every
call instead of using the cached empty value) -- but for `_log_indent`'s cache
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

### ERR Trap -- `$LINENO` String Form vs Function Form

When the ERR trap body calls a **function** (`trap my_handler ERR`), `$LINENO`
inside `my_handler` is the line *within the handler*, not the failing command's
line. To capture the failing line, use a **string trap** and pass `$LINENO` as
an argument before the function call -- the string is evaluated in the failing
command's scope:

```zsh
# BAD -- $LINENO inside _cleanup_and_exit is the handler's own line, not the failing line
trap _cleanup_and_exit ERR

# Good -- $LINENO expands in the failing command's scope before _cleanup_and_exit is called
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
fires in the scope of the failing helper function -- `$LINENO` in the string
trap correctly reports that helper's line.

**Debugging misleading line numbers:** ERR trap line numbers can be misleading when:
1. **Subprocess failures**: A Ruby/Python script called from shell exits non-zero, triggering
   the trap at the script invocation line, not the actual failure inside the subprocess
2. **Function call failures**: A function deep in the call stack fails, but `$LINENO` reports
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

## Cron Suspension -- `with_cron_suspended`

For scripts that must not run concurrently with the cron job, use the
`with_cron_suspended` wrapper (defined in `.aliases`). It suspends cron,
runs the given function, then restores cron -- including on error via an
internal `EXIT` trap:

```zsh
main() {
  with_cron_suspended _main_impl "$@"
}
```

Do not call `suspend_cron` / `resume_cron` directly in scripts that have a
single entry point -- use `with_cron_suspended` instead. Use the low-level
functions only when the suspend/resume scope spans multiple code paths (e.g.
`fresh-install-of-osx.sh` where the scope is the entire `main()`).

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

Every file under `files/--XDG_CONFIG_HOME--/zsh/` is a zsh autoload script.
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
  script portably even if `$PATH` does not include the directory.
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

## Common Mistakes (Code Review Findings)

Based on code review patterns and debugging sessions, here are the most common mistakes to avoid:

1. **Using `&&` with `set -e` where false is expected** → Use explicit `if` statements
   ```zsh
   # BAD - triggers set -e when file doesn't exist (expected case)
   is_file "${optional}" && process
   # Good
   if is_file "${optional}"; then process; fi
   ```

2. **Post-increment in arithmetic under `set -e`** → Returns 1 when value is 0
   ```zsh
   # BAD - (( 0 )) on first iteration triggers set -e
   (( count++ ))
   # Good
   (( count += 1 )) || true
   ```

3. **For-loop variables leaking** → Not auto-local in zsh
   ```zsh
   # BAD - 'item' leaks into caller's scope
   for item in "${arr[@]}"; do
     info "${item}"
   done
   # Good - declare local first
   local item
   for item in "${arr[@]}"; do
     info "${item}"
   done
   ```

4. **Using `:-` vs `-` incorrectly** → Different semantics for unset vs empty
   ```zsh
   # BAD - inconsistent with user flag convention
   [[ -n "${DEBUG-}" ]]
   # Good - use :- for user flags (unset OR empty → fallback)
   [[ -n "${DEBUG:-}" ]]
   ```

5. **Local + assignment masks exit codes** → Split into two lines
   ```zsh
   # BAD - local returns 0 even if cmd fails
   local result="$(cmd)"
   # Good - preserve cmd's exit code
   local result
   result="$(cmd)"
   ```

6. **Bare `setopt NULL_GLOB`** → Leaks to caller
   ```zsh
   # BAD - persists for rest of process
   setopt NULL_GLOB
   rm -f *.txt
   unsetopt NULL_GLOB
   # Good - scoped to anonymous function
   () {
     setopt localoptions NULL_GLOB
     rm -f *.txt
   }
   ```

7. **Not quoting variables** → Breaks with spaces
   ```zsh
   # BAD
   cp $src_file $dest_dir/
   # Good
   cp "${src_file}" "${dest_dir}/"
   ```

8. **Using `exit` in `main()`** → Kills calling shell if sourced
   ```zsh
   # BAD
   main() {
     exit 1  # kills shell if script is sourced
   }
   # Good
   main() {
     return 1  # exits function only
   }
   ```

9. **ERR trap with function handler loses `$LINENO`** → Use string form
   ```zsh
   # BAD - $LINENO is handler's line, not failing line
   trap _cleanup_and_exit ERR
   # Good - capture $LINENO in string before function call
   trap '_cleanup_and_exit "${LINENO}"' ERR
   ```

10. **Using aliases in non-interactive scripts** → Not available in cron/background jobs
    ```zsh
    # BAD - 'bcg' alias requires .aliases to be loaded
    bcg | grep ...
    # Good - use underlying command
    brew outdated --greedy | grep ...
    ```
