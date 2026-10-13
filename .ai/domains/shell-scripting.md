---
applyTo: "**/*.sh*,**/.shellrc,**/.aliases,**/.envrc,**/.zsh*,**/files/--XDG_CONFIG_HOME--/zsh/*,**/scripts/**"
name: dotfiles-shell-scripting
description: Use when creating or editing any shell script in this dotfiles repo -- .sh, .zsh, .bash files, .shellrc, .aliases, .envrc, zsh autoload functions under files/--XDG_CONFIG_HOME--/zsh/, or git alias shell bodies in .gitconfig. This is the CORE shell file; read it first. Covers utility functions (is_file, is_directory, nil_or_empty), quoting/brace notation, set -e/&& safety, script depth tracking, logging levels, and the standard script template. Topic files cover autoload/function structure and bash/cron portability.
---

# Shell Script Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules when writing or editing any shell script in this repository.

Syntax choices follow the decision-making priority defined in
[`instructions.md`](../instructions.md) (startup speed + maintainability first; POSIX and
zsh built-ins where they do not conflict with those). Document the tradeoff in
a comment when they conflict.

## Topic Files (load on demand)

This file holds the rules every shell edit needs. Read the sibling file when the task touches its topic:

| File | Read when the task involves |
|------|-----------------------------|
| [`shell-functions-autoload.md`](./shell-functions-autoload.md) | Shell functions as entry points, autoload function structure, `local`/`unset`, positional parameters, parameter-expansion operators, `require_env_var` |
| [`shell-portability-cron.md`](./shell-portability-cron.md) | bash/direnv compatibility, `.envrc`, cron scripts and suspension, `is_zsh` guards, globs, cache invalidation, shebangs, `exec` wrappers, `notify` |

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
| Positional param with default | `dir="${1:-.}"` | [§ Positional Parameters](./shell-functions-autoload.md#positional-parameters) |
| Required positional param | `dir="${1:?func: dir required}"` | [§ Positional Parameters](./shell-functions-autoload.md#positional-parameters) |
| Check file exists | `is_file "${path}"` | [§ Prefer Utility Functions](#prefer-utility-functions-over-raw-shell-tests) |
| Check directory exists | `is_directory "${path}"` | [§ Prefer Utility Functions](#prefer-utility-functions-over-raw-shell-tests) |
| Avoid subshell fork | `${PWD:t}` not `$(basename "$PWD")` | [§ Zsh Parameter Expansion](#zsh-parameter-expansion-for-basename) |
| For loop variable | `local item; for item in ...` | [§ `local` and `unset`](./shell-functions-autoload.md#local-and-unset----correct-usage) |
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

**Autoload function naming**: Zsh autoload functions in `${XDG_CONFIG_HOME}/zsh/` use single-word names by design (e.g., `st`, `count`). This is not a "no separator needed" exception—it's a deliberate convention for autoloaded commands that matches shell built-in naming patterns (`cd`, `ls`, `git`, `grep`).

## Function Naming Convention

**All shell functions use snake_case (underscores), following Unix and Ruby conventions.**

```zsh
# Good -- public functions use snake_case
current_timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
clone_repo_into() { ... }
is_file() { ... }

# Good -- private/internal functions use snake_case with leading underscore
_set_log_indent() { ... }
_colorize() { ... }
_strip_ansi_into() { ... }

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
  - Cron management: `suspend_cron`, `resume_cron`, `restore_cron` (`with_cron_suspended` is Ruby-only: `Cron.with_cron_suspended { ... }`)
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

**Note**: `is_root_dir` is true only for `/` itself. To refuse write/delete operations on a path that is `/` or a direct child of `/` (e.g. `/foo`), use `_is_direct_child_of_root "${path}"` -- it handles the case where `${path%/*}` is empty (`/foo`), which `is_root_dir "${path%/*}"` would miss, and is bash-compatible (unlike `${path:h}`). Ruby equivalent: `PathUtils.root_dir?`.

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
if _is_direct_child_of_root "${target_path}"; then
  error "Refusing to operate on path in root: '${target_path}'"
  return 1
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
absolute="${relative:a}"            # "${HOME}/.config/dotfiles/scripts/file.sh"
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
[`shell-portability-cron.md`](./shell-portability-cron.md) § **`exec`-Wrapper Scripts**.

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
  local failed_file
  for failed_file in "${failed_files[@]}"; do
    msg+=$'\n'"  - '${failed_file}'"
  done
  _step_warnings+=("[${_SCRIPT_NAME}][${_current_section}] ${msg}")
fi
```

The direct append pattern is the exception, not the rule. Use it only when:
- The message is computed/aggregated after processing multiple items
- Showing it immediately would be confusing or redundant
- The message is only meaningful in the context of the final summary

The pattern mirrors Ruby's `record_warning` (immediate) vs direct append to
`Logging.step_warnings` (summary-only).

## Script Depth Tracking

See [`script-depth-tracking.md`](./script-depth-tracking.md) for complete details on `_DOTFILES_SCRIPT_DEPTH`.

**Quick summary for shell**:
- Increment on entry: `export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))`
- Decrement on exit: `trap '_decrement_script_depth' EXIT`
- Dual purpose: nesting suppression (outermost only prints banners) + auto-indentation (2 spaces per depth)
- Never manually indent log messages
- Bulleted lists: build one `  - '<item>'` line per item explicitly (Ruby has `Logging.join_array`)
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

`getopts` itself never enforces a flag as mandatory -- it just parses whatever
is present. If a `getopts`-parsed flag is required, add an explicit
`nil_or_empty` check after the loop; see [`shell-functions-autoload.md`](./shell-functions-autoload.md) § Positional Parameters for the
full pattern.

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
- Functions in `.shellrc` and `.aliases` that are only called internally (like `_set_log_indent`, `_colorize`, `_strip_ansi_into`) MUST have underscore prefix

**Applies to:**
- Helper functions in standalone scripts (anything in `${DOTFILES_DIR}/scripts/*.sh`)
- Helper functions in `${PERSONAL_BIN_DIR}/*.sh`
- Internal implementation functions in `.shellrc` and `.aliases`

**Exception:** Autoload functions in `${XDG_CONFIG_HOME}/zsh/` (`st`, `count`) follow a dual-function pattern where the public wrapper (no underscore) calls a private implementation (with underscore):

```zsh
# Autoload function pattern
_st() {
  # Implementation
  git -C "${folder}" status "${switches[@]}"
}

st() {
  dispatch_or_fallback st _st "$@"
}
```

This pattern allows `dispatch_or_fallback` to run a per-repo override script (`.rb` or `.sh`) when one exists, and the default implementation otherwise. Commands that are not typed constantly and benefit from Ruby (`push`, `pull`, `cc`, `upreb`, `status_all_repos`, `update_all_repos`) are not autoload functions: they are aliases (`git-command.rb <cmd>`, `call-utility.rb <Module.method>`) defined in `.aliases`.

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
  echo "=== ${branch} ==="
  git grep "function_name" "${branch}" -- '*.sh' '*.zsh' '*.rb' || true
done

# 5. Syntax check all files after deletion
find files -name "*.zsh" -o -name "*.sh" | xargs -n1 zsh -n
find scripts -name "*.rb" -exec ruby -c {} \;
```

**Only delete when ALL checks pass**: No matches in current branch, no matches in other branches, no recent additions in git history.

**Cross-reference**: See identical rule in [`ruby-infrastructure.md`](./ruby-infrastructure.md) § Deleting Methods/Functions for Ruby-specific guidance.

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

9. **ERR trap with function handler loses `${LINENO}`** → Use string form
   ```zsh
   # BAD - ${LINENO} is handler's line, not failing line
   trap _cleanup_and_exit ERR
   # Good - capture ${LINENO} in string before function call
   trap '_cleanup_and_exit "${LINENO}"' ERR
   ```

10. **Using aliases in non-interactive scripts** → Not available in cron/background jobs
    ```zsh
    # BAD - 'bcg' alias requires .aliases to be loaded
    bcg | grep ...
    # Good - use underlying command
    brew outdated --greedy | grep ...
    ```

11. **Unguarded positional parameters / `shift` without a `$#` check** → No default and no fail-fast message (see [`shell-functions-autoload.md`](./shell-functions-autoload.md) § Positional Parameters)
    ```zsh
    # BAD - bare $1, no default and no fail-fast message
    local dir="${1}"
    # BAD - shift silently no-ops if $# < 1 instead of failing
    shift
    # Good - required param fails fast; shift only after count is verified
    local dir="${1:?my_func: dir argument required}"
    if (($# < 1)); then warn "my_func: fn argument required"; return 1; fi
    shift
    ```
