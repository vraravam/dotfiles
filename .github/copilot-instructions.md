# Dotfiles Repository — Copilot Instructions

## Absolute Rules

- **NEVER commit, amend, or create a PR** unless explicitly requested by the user. This includes `git commit`, `git commit --amend`, and `gh pr create`. Only the user decides when to record history.
- **NEVER push to any remote** (`git push`, `git push --force`, `git push --force-with-lease`, or any variant). This is unconditional — no exceptions, no user prompts. Only the user pushes.

This is a personal macOS dotfiles repository. The codebase contains zsh startup
files, shell utility scripts, Ruby scripts, and a macOS fresh-install bootstrap
script. All coding decisions documented here come from accumulated design
decisions across development sessions.

## Repository Layout

```
files/
  --HOME--/        -> symlinked to $HOME (contains .shellrc, .aliases, etc.)
  --ZDOTDIR--/     -> symlinked to $ZDOTDIR (contains .zshrc, .zshenv, .zlogin)
  --XDG_CONFIG_HOME--/zsh/  -> cached homebrew shellenv, antidote bundle, etc.
  --PERSONAL_PROFILES_DIR--/ -> .envrc for direnv
scripts/
  fresh-install-of-osx.sh   # Bootstrap installer — runs on vanilla OS AND pre-configured machine
  utilities/                # Shared Ruby utilities (logging.rb, string.rb, cli_parser.rb, hash_ext.rb, path_utils.rb)
  *.rb                      # Ruby scripts
  *.sh                      # Shell scripts
```

### `files/` Naming Convention — `--VAR--` Directories

Subdirectories under `files/` use the pattern `--ENV_VAR_NAME--`. `install-dotfiles.rb`
interpolates each directory name by resolving the env var it names (e.g. `--HOME--` →
`$HOME`, `--ZDOTDIR--` → `$ZDOTDIR`) and symlinks all files found inside into the
resolved directory. This means:

- Add a new dotfile under `files/--HOME--/` to have it symlinked into `$HOME`.
- Add a new config file under `files/--XDG_CONFIG_HOME--/zsh/` to have it placed in
  `$XDG_CONFIG_HOME/zsh/`.
- Plain subdirectory names without the `--VAR--` pattern are also valid — they resolve
  literally from `/` (e.g. `files/etc/` → `/etc/`). Prefer the `--VAR--` convention
  for any path that may differ between machines (e.g. home directory, XDG dirs), since
  hardcoded paths break portability.

Exception: files matching `custom.git*` (e.g. `custom.gitattributes`) are **copied**
rather than symlinked, because git does not handle symlinks well for its own core config.
Resolution when both the source and the destination exist as real files:
- `FIRST_INSTALL` set: pre-existing destination always wins — moved into dotfiles repo,
then copied back.
- Otherwise: the file with the **newer mtime** wins. On a tie, the dotfiles repo wins.
Prefer editing the `custom.git*` source file in the dotfiles repo. If you edit the
destination directly, ensure its mtime is newer before re-running `install-dotfiles.rb`.

The three primary script directories referenced throughout:
- `$DOTFILES_DIR`     = `${HOME}/.config/dotfiles`
- `$PERSONAL_BIN_DIR` = `${HOME}/personal/dev/bin`
- `$PERSONAL_CONFIGS_DIR` = `${HOME}/personal/dev/configs`

Except for adding/updating entries into the `CHANGELOG.md`, all actions need to be
performed in all relevant files in all the above 3 folders and their nested children.

---

## Decision-Making Philosophy

When suggesting or making any change to shell or zsh scripts, apply these
priorities in order. A higher priority always wins over a lower one; document
the tradeoff in a comment when they conflict.

1. **Startup speed** — never introduce a subshell fork (`$(...)`) or external
   process call in the startup hot path. Prefer zsh built-ins and cached values.
   A POSIX-compatible change that regresses startup time is not acceptable.

2. **Maintainability** — code must be understandable without deep zsh expertise.
   When a performance optimisation degrades readability, add a concise comment
   explaining what it does and why it is written that way.

3. **POSIX compatibility** — prefer POSIX syntax where it does not conflict with
   the above. This keeps scripts portable and safe in bash contexts (e.g.
   `.envrc` files evaluated by direnv). When POSIX syntax would require a
   subshell fork or harm readability, use zsh built-ins instead and document why.

4. **Zsh built-ins** — when POSIX syntax is insufficient or would require a
   subshell fork, use zsh built-in syntax (parameter expansions,
   `(( $+functions[...] ))`, `${(j::)arr}`, etc.) and document why the
   zsh-specific syntax was chosen.

Note:
- Priorities 3 and 4 only apply to zsh scripts. `.envrc` files are
  evaluated by direnv in a bash subshell and must use POSIX syntax exclusively.
- Similarly, git alias bodies use `sh` or `bash` and must use POSIX syntax.

## Four-Context Validation

Before suggesting or applying any shell construct, variable, or function, verify
it works correctly in **all four execution contexts**. A suggestion that fails in
any one of them is not acceptable.

| Context | Description |
|---|---|
| **Vanilla OS (pre-`.shellrc`)** | A fresh macOS before `fresh-install-of-osx.sh` has downloaded and sourced `.shellrc`; no utility functions, no Homebrew, no dotfiles symlinks. Only `/bin/zsh` builtins and hardcoded system paths are available. |
| **Bash / direnv subshell** | `.envrc` evaluated by direnv in bash; `.shellrc` is sourced but zsh-only syntax must not appear at the top level of `.shellrc`. Only POSIX constructs are safe. |
| **Zsh script / cron** | A `#!/usr/bin/env zsh` script run non-interactively; `.shellrc` may or may not be sourced depending on the script. `$0` is the script name, not `zsh`. |
| **Interactive zsh** | A normal terminal session; `.shellrc` and `.aliases` are fully loaded. |

Common failure patterns to check:

- **Shell detection**: use `[[ -n "${ZSH_VERSION-}" ]]` — works in all four contexts.
  `is_zsh` (once defined) delegates to this. Never use `[[ "${0}" =~ 'zsh' ]]` —
  `$0` is the script name in cron/scripts, not the interpreter name.
- **Utility functions** (`is_file`, `is_zero_string`, `has_sudo_credentials`, etc.):
  only available after `.shellrc` is sourced. Not safe in vanilla OS pre-bootstrap
  code or in bash contexts that have not sourced `.shellrc`.
- **Zsh-only syntax** (`(( $+functions[...] ))`, `${(j::)arr}`, `typeset -A`):
  causes a syntax error in bash. Must be guarded with `[[ -n "${ZSH_VERSION-}" ]]`
  anywhere `.shellrc` may be sourced from bash (e.g. `.envrc`).
- **`$0` for interpreter detection**: unreliable in scripts and cron — use
  `ZSH_VERSION` instead.

---

## Core Design Principles

### Idempotency — Fresh Install

`fresh-install-of-osx.sh` MUST work **both on a vanilla macOS** and a
**fully pre-configured machine** without errors. All logic must be idempotent.

- `FIRST_INSTALL` env var is set only on a vanilla OS run.
- Check `FIRST_INSTALL` before operations that only make sense on a fresh machine.
- `.shellrc` is not available at the start of fresh-install on a vanilla OS;
  it is downloaded via `curl` and then sourced.
- `.aliases` is not available until the dotfiles repo is cloned. Functions
  needed before that clone must live in `.shellrc`, not `.aliases`.

**Every section must have a guard that pre-empts the whole section** when its
work is already complete. The guard is the first thing in the section — before
any logging or setup. This keeps re-runs on a pre-configured machine fast: only
sections with actual work to do execute their logic. See
`fresh-install.instructions.md` for guard patterns.

### `.shellrc` vs `.aliases` — Why Functions Are Split

`.shellrc` is downloaded via `curl` early in `fresh-install` on a vanilla OS,
**before** the dotfiles repo is cloned and before `install-dotfiles.rb` has run
to create symlinks. It must therefore remain **lean and small** — only the
functions genuinely needed during that early bootstrap window belong here.

`.aliases` is only available after the dotfiles repo is cloned and
`install-dotfiles.rb` has created the symlink from the repo into `$HOME`.
Everything that is not needed in the pre-clone window should live in `.aliases`,
not `.shellrc`.

Decision rule when placing a new function:
- **`.shellrc`** — required if the function is called during a vanilla OS
  fresh-install **before `install-dotfiles.rb` creates the `.aliases` symlink**.
  The precise boundary is `install-dotfiles.rb` in `main()` of
  `fresh-install-of-osx.sh`. Within a vanilla OS run, `$DOTFILES_DIR/scripts/`
  exists and is in PATH from the moment the dotfiles repo is cloned, but
  `~/.aliases` does not exist until `install-dotfiles.rb` finishes — so scripts
  in `$DOTFILES_DIR/scripts/` that are invoked in this window (between repo
  clone and `install-dotfiles.rb`) must also source `.shellrc`, not `.aliases`.
  Examples that belong here: `suspend_cron`, `resume_cron`, `clone_repo_into`,
  `keep_sudo_alive`, `set_ssh_folder_permissions`, `eval_shellenv`,
  `load_zsh_configs`, `print_usage`, `get_git_config_value`.
  Note: `add-upstream-git-config.sh` is invoked inside `_clone_dot_files_repo`
  (before `install-dotfiles.rb`), so any function it uses must be in `.shellrc`.
- **`.aliases`** — everything else; available once dotfiles are symlinked.
  This includes:
  - Functions only used by scripts in `$PERSONAL_BIN_DIR` or
    `$PERSONAL_CONFIGS_DIR` — those directories never exist on a vanilla OS
    before the dotfiles repo is cloned, so they are never in the boot path.
  - Functions used by scripts in `$DOTFILES_DIR/scripts/` that are only called
    **after** `install-dotfiles.rb` runs (e.g. `post-brew-install.sh`,
    `osx-defaults.sh`, `capture-prefs.sh`, `setup-login-item.sh`, `run-all.sh`,
    `software-updates-cron.sh`, `recreate-repo.sh`).
  - zsh autoload functions (the scripts under `$ZDOTDIR/functions/` and
    `$XDG_CONFIG_HOME/zsh/`) — these are only ever invoked in an interactive
    zsh session, well after all dotfiles are in place.
  The sourcing choice for all of the above is governed solely by the
  "source the tightest file" rule, not by the vanilla OS constraint.

Note on `.envrc` files: `.envrc` files are evaluated by direnv in a **bash**
subshell. They must source `.shellrc` (not `.aliases`) because `.aliases`
contains extensive zsh-only syntax (`(N.)` globs, `:h`, `:A`, `((@on))`,
`(($+...))` etc.) that is not bash-compatible. This is a **bash compatibility**
constraint, not a hotpath or startup-speed concern. Any function that is called
from a `.envrc` file and is not already in `.shellrc` for bootstrap reasons must
be kept in `.shellrc` for bash-compat reasons — add a comment on that function
explaining this (see `set_ssh_folder_permissions` for the pattern).

Avoid the temptation to put convenience functions in `.shellrc` just because
`.shellrc` is always loaded. Every extra function added to `.shellrc`
unnecessarily increases the payload of the initial `curl` download on a vanilla
OS and adds to shell startup time.

Guards that belong inside a single function/file must NOT be repeated across
multiple files. Example: the re-source guard for `.shellrc` is implemented
**inside** `.shellrc` itself (sentinel function `is_shellrc_sourced`). All
other scripts source `.shellrc` unconditionally and add a comment:
`# Re-source guard is inside .shellrc itself — safe to call unconditionally.`

The same pattern applies to `.aliases` with `is_aliases_sourced`.

Exception: `fresh-install-of-osx.sh` may have an explicit guard because it
runs before the sentinel function is available.

### Source the Tightest File

Each script must source only the tightest file that provides the needed
functions:
- If only `.shellrc` functions are needed, source `.shellrc`.
- If `.aliases` functions are needed (and `.aliases` sources `.shellrc`
  internally), source `.aliases`.
- Never source `.aliases` AND `.shellrc` in the same script — `.aliases`
  already sources `.shellrc`.

---

## Global State Variable Naming Conventions

Variables that form the shared-state backbone of `.shellrc` and the scripts
that source it follow a three-tier naming convention. The tier is determined
by how the variable is scoped and whether it is exported.

| Tier | Pattern | Examples | Declared with |
|------|---------|----------|---------------|
| Exported internal infrastructure | `_DOTFILES_*` ALL_CAPS | `_DOTFILES_CRON_BACKUP_FILE`, `_DOTFILES_SCRIPT_DEPTH` | `export VAR=…` |
| Non-exported global (lives in `.shellrc`, process-wide) | `_lowercase` with `_` prefix | `_script_start_times`, `_step_start_times` | `typeset -a VAR=()` |
| Dynamically-scoped "locals" (declared in `main()`, read by callees) | `_lowercase` with `_` prefix | `_step_warnings`, `_step_errors`, `_current_section` | `local -a VAR` or `local VAR` in `main()` |

The last two tiers share the same prefix to signal "internal/private". The
declaration context (`typeset -a` at file scope vs. `local` inside `main()`)
and surrounding comments distinguish them — no additional naming difference is
needed.

Rules:
- **Never use plain `ALL_CAPS` for internal infrastructure** — bare `ALL_CAPS`
  without the `_DOTFILES_` prefix looks like a user-visible exported variable
  and conflicts with conventional shell env var naming.
- **Never use `_DOTFILES_` for non-exported variables** — the `_DOTFILES_`
  prefix implies exported, process-wide state; using it for a `typeset -a`
  global or a `local` inside a function is misleading.
- **Exported internal vars must use `export`** — they are inherited by
  subprocess scripts (e.g. `_DOTFILES_SCRIPT_DEPTH`) and by ERR/EXIT trap
  handlers that run before `.shellrc` is re-sourced.

**Exception — module-level cross-function state**: `_SHARED_REPO_DIRS` (in
`.aliases`) is set *inside* a function and persists until explicitly `unset`.
It follows the `_` prefix convention but is neither a `typeset -a`
file-scope global nor a `local` — it is intentionally process-wide for the
duration of a single logical operation. This pattern is reserved for expensive
shared state (e.g. a `find` traversal result) that multiple sibling functions
need to consume. Always `unset` at the end of the owning function.

**Exception — file-scope constant arrays**: `_MACOS_LOGIN_ITEM_APPS` (in
`.aliases § 3n`) is a `typeset -a` constant declared at file scope. It uses
an uppercase name with `_` prefix — not `_DOTFILES_*` (which implies exported)
and not `_lowercase` (which signals a mutable global or dynamic local). Uppercase
with `_` prefix signals a read-only file-scope constant. It is never exported,
never modified, and never `unset`. This pattern is reserved for arrays that
represent a canonical list used by multiple sibling functions in the same file.

---

## Shell Scripting Rules

> Full rules and script skeleton are in
> `.github/instructions/shell-scripting.instructions.md`.
> The summary below covers the most critical points.

### Utility Functions Over Raw Test Conditions

**Never** use raw POSIX test switches (`-f`, `-z`, `-n`, `-d`, `-e`, `-x`,
`-L`, `-s`) directly in scripts. Always use the named utility functions defined
in `.shellrc`:

| Raw test | Utility function |
|----------|-----------------|
| `-f "$x"` | `is_file "$x"` |
| `-d "$x"` | `is_directory "$x"` |
| `-L "$x"` | `is_symbolic_link "$x"` |
| `-x "$x"` | `is_executable "$x"` |
| `-s "$x"` | `is_non_empty_file "$x"` |
| `-z "$x"` | `is_zero_string "$x"` |
| `-n "$x"` | `is_non_zero_string "$x"` |
| `[ -d "$x/.git" ]` | `is_git_repo "$x"` |
| `mkdir -p "$x"` | `ensure_dir_exists "$x"` |

Note: `is_git_repo` checks **two** conditions internally (non-empty string AND
`.git` directory present). Add a comment when calling it to note that the else
branch is not a simple negation.

Additional utility functions defined in `.shellrc` — use these rather than
inline equivalents:

| Function | Purpose |
|----------|---------|
| `is_directory_empty "$x"` | True if directory exists and contains no entries |
| `command_exists "$x"` | True if `$x` exists as a command, function, alias, or builtin (checks 4 hash tables) |
| `is_running_in_tty` | True if stdin is a TTY (`[[ -t 0 ]]`) or `FORCE_COLOR` is set (allows color output in CI/direnv) |
| `is_zsh` | True when running inside zsh (guards zsh-only code in files sourced by bash) |
| `is_macos` / `is_linux` | OS detection — use instead of `uname` subshell forks |
| `is_arm` | True on Apple Silicon — uses `$ARCH`, no subshell |
| `replace_home_with_tilde "$x"` | Substitutes `$HOME` with `~` in a string for display (inline, no fork) |

Exception: `.envrc` files are evaluated by direnv in a bash subshell; they
cannot use zsh utility functions. Use POSIX syntax in `.envrc` files.

Exception: `fresh-install-of-osx.sh` early-boot code that runs before
`.shellrc` is sourced must use raw tests with explanatory comments.

### Array Utility Functions

Use named utility functions instead of inline `${#arr[@]}` checks:
- `is_empty_array arr` instead of `[[ ${#arr[@]} -eq 0 ]]`
- `is_non_empty_array arr` instead of `[[ ${#arr[@]} -gt 0 ]]`
- `join_array arr_name` for joining array elements into a bulleted list (pass the array name, not elements)

### Logging — Never Use Bare `echo` in Scripts

Use the logging functions from `.shellrc` (`info`, `success`, `warn`, `error`,
`debug`, `section_header`, `section_header2`, `step_start`/`step_end`). Bare
`echo` is only acceptable for `usage` output and code that runs before
`.shellrc` is sourced.

Color functions apply `${1//${HOME}/~}` inline (no subshell fork). Logging
functions do NOT apply the substitution themselves — it happens inside the color
functions they call.

### Deferred Error/Warning Collection Pattern

Shell scripts that use `_record_error` / `_record_warning` + `print_script_summary`
must declare three locals, increment the depth counter, and register the decrement
trap at the top of `main()`:

```zsh
main() {
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  trap '_decrement_script_depth' EXIT   # chain into existing EXIT trap if one is set later
  ...
}
```

The decrement trap ensures `_DOTFILES_SCRIPT_DEPTH` is restored on both clean and
error exits. `is_outermost_script` (shell) / `outermost_script?` (Ruby) check
`depth <= 1`; `print_script_start` and `print_script_summary` call this predicate
and return early when depth > 1, so only the outermost script prints banners and
the final summary. See `TechnicalDeepDive.md` § 6 for the full rationale.

Each entry is prefixed with `[_SCRIPT_NAME][_current_section]` for traceability.
`print_script_summary` reads `_SCRIPT_NAME` via dynamic scoping — no argument needed.

The Ruby equivalent uses `Logging.record_warning`, `Logging.record_error`,
`Logging.current_section=`, and `Logging.print_script_summary(start_time)` — see
`ruby-scripting.instructions.md` § **Deferred error/warning collection**.
`print_script_summary` accepts an optional `start_time` (Unix epoch from
`print_script_start`) and calls `print_script_duration` internally — no separate
call needed. Omit the argument only on early-exit paths inside methods that
cannot access the top-level `start_time` local.

`print_script_summary` sends a macOS notification when `_step_errors` or
`_step_warnings` is non-empty (shell only — Ruby omits `osascript`). This makes
the choice of `_record_error` vs `warn` consequential:

#### Arg-parse failures — `warn` + `usage` + `return 1`

**Never** use `_record_error` / `print_script_summary` for argument-parsing
failures (bad flag, missing required flag/arg). Use `warn` + `usage` + `return 1`
directly. Sending a notification because the user mistyped a flag is poor UX.

```zsh
# getopts cases
:) warn "Option -${OPTARG} requires an argument."; usage "${_SCRIPT_NAME}"; return 1 ;;
?) warn "Unknown option: -${OPTARG}";              usage "${_SCRIPT_NAME}"; return 1 ;;

# Missing required positional/flag
if is_zero_string "${folder}"; then
  warn 'Missing required arguments/switches'
  usage "${_SCRIPT_NAME}"
  return 1
fi
```

#### Runtime preconditions — `_record_error` + `print_script_summary` + `return 1`

Use `_record_error` for failures that occur **after** arg-parsing succeeds:
missing env vars, missing files, failed remote lookups, etc. These represent
unexpected environment problems the user should be notified about.

```zsh
if is_zero_string "${PERSONAL_CONFIGS_DIR}"; then
  _record_error "Required env var '$(yellow 'PERSONAL_CONFIGS_DIR')' is not defined."
  print_script_summary
  return 1
fi
```

#### `-h` / `--help` path — `return 0` directly

Never call `print_script_summary` on the help path. With empty error/warning
arrays it would print a spurious success summary.

```zsh
h) usage "${_SCRIPT_NAME}"; return 0 ;;
```

### `set -euo pipefail`

All shell scripts use `set -euo pipefail`. Guard positional parameters with
`${1:-}`. Use `grep -q ... || true` in pipelines to avoid SIGPIPE under
`set -o pipefail`.

**Arithmetic increment under `set -e`**: never use bare `(( var++ ))` — post-increment
evaluates to the *old* value, so `(( 0 ))` on the first iteration (when `var` starts
at zero) is arithmetic false (exit 1) and silently aborts the script. Always use
`(( var += 1 )) || true`. See `shell-scripting.instructions.md`
§ **Arithmetic Increment — Safety Under `set -e`** for the full rule and scan rule.

### Quoting and Variable References

- **Never hardcode user-specific paths**: always use the exported env vars from
  `.shellrc` instead of literal expanded paths. This applies to every file —
  scripts, config files, and Brewfile Ruby expressions alike.

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
  env var. Full table and scan rule in `shell-scripting.instructions.md`
  § **No Hardcoded User-Specific Paths**.

- **Always quote variables**: use `"${var}"` in any context where the value
  could contain spaces. Unquoted variables break on filenames with spaces.
- **Single quotes for static strings**: use `'literal'` when there is no
  variable expansion. Use double quotes only when expanding variables or
  needing escape sequences.
  Exception: prefer double quotes when the string contains single quotes that
  would otherwise require `$'...\n...'` escaping or concatenation — double
  quotes allow literal single quotes inside and support literal newlines,
  making multiline strings significantly more readable (see
  `shell-scripting.instructions.md` § Single Quotes vs Double Quotes).
- **Always use `${var}` brace notation**: never bare `$var`. Braces
  unambiguously delimit the variable name and prevent accidental
  concatenation bugs (e.g. `"${name}_suffix"` vs `"$name_suffix"` which
  looks up `$name_suffix`).
- Exception: single-character special params (`$?`, `$#`, `$@`, `$$`, etc.)
  do not need braces.

### Key Structural Rules

- Use `getopts` for all option parsing (not manual `$1/$2` checking).
- Entry point must be a `main()` function; library scripts (`*-common.sh`) must
  NOT have a `main` call.
- Internal helpers: prefix with `_`.
- `source` vs `load_file_if_exists`: use `load_file_if_exists` after `.shellrc`
  is sourced; use raw `[[ -f ]]` + `source` before `.shellrc` is available.

### No Aliases in Non-Interactive Scripts

Zsh disables alias expansion in non-interactive shells (scripts, cron jobs,
`zsh -c`, `zsh -lsc`). **Never call an alias by name inside a script** — use
the underlying command or function it expands to. Also replace any
`command_exists <alias>` guard with a check against the real executable:

```zsh
# BAD — aliases not expanded in non-interactive shells
home pull
oss upreb
if command_exists bcg; then
  bcg | grep ...

# Good — direct equivalents
FOLDER="${HOME}" FILTER='.bin|.dotfiles|zsh|mise' MAXDEPTH=5 run-all.sh git pull
FOLDER="${PROJECTS_BASE_DIR}/oss" MAXDEPTH=4 run-all.sh git upreb
if command_exists brew; then
  # 'bcg' alias (brew outdated --greedy) is not expanded in non-interactive shells.
  brew outdated --greedy | grep ...
```

Add a comment at each call site noting why the alias is not used.

---

## Ruby Scripting Rules

> Full rules and script skeleton are in
> `.github/instructions/ruby-scripting.instructions.md`.
> The summary below covers the most critical points.

### Ruby Version Compatibility

`install-dotfiles.rb` and `utilities/` scripts run under the **system Ruby
(2.6)** during a vanilla OS fresh-install. All Ruby code must be compatible
with Ruby 2.6. Do NOT use homebrew-managed Ruby for `$DOTFILES_DIR` scripts.

### Key Rules

- Use `map`/`select`/`reduce` (not `collect`/`filter`/`inject`).
- Use `Array()` to guard potential nil values before iteration.
- Use `nil_or_empty?` — do NOT replace with `.empty?` (unsafe on nil).
- Use `File::SEPARATOR` (not hardcoded `/`).
- Do not `require` transitively — push requires down to direct users.
- Do NOT use `Kernel.warn` — use `Logging.warn` instead.
- Use `CliParser` from `cli_parser.rb` for all CLI option parsing.

---

## Zsh Startup Performance Rules

> Full rules are in `.github/instructions/zsh-startup.instructions.md`.
> The summary below covers the most critical points.

- Avoid `$(...)` in the startup hot path — prefer zsh parameter expansion.
- Use `(( $+functions[funcname] ))` (not `type`) for function existence checks
  in zsh. Exception: `.envrc` and bash contexts must use `type`.
- Cache `brew shellenv` output to a file; source from cache.
- Pre-compile startup scripts to `.zwc` in `.zlogin`. Use `delete_caches` to
  remove `.zwc` files — do NOT chmod/chown them.
- **Antidote**: `ANTIDOTE_HOME` uses `~/Library/Caches`; bundle file checked
  into home git repo; source with `load_file_if_exists`; run `antidote bundle`
  in `zsh --no-rcs -c "..."` to avoid ANSI leaks; guard `--unshallow`.
- Path arrays (`fpath`, `path`, etc.) use `typeset +x` — not `export`.
- **`load_zsh_configs` uses `${ZDOTDIR}`**: safe to use because the function is
  defined inside `.shellrc`, which initialises `ZDOTDIR` unconditionally at its
  own line 38 (`export ZDOTDIR="${ZDOTDIR:-"${HOME}"}"`) before the function
  definition. `ZDOTDIR` is therefore always set correctly by the time
  `load_zsh_configs` can be called — even in cron or fresh-install subshell
  contexts where `.zshenv` has not been sourced.
- **`load_zsh_configs` not always needed in cron**: only call when the script
  needs `.zshrc`-defined vars/functions (e.g. `PROJECTS_BASE_DIR`, mise shims).
  Calling it unconditionally in cron sources `.zlogin`, which triggers background
  zwc compilation jobs that are disruptive with no terminal attached.
- **`sudo` in cron — always guard with `has_sudo_credentials`**: any function
  callable from cron that uses `sudo` must call `has_sudo_credentials` (defined
  in `.shellrc` § 1e) first; without cached credentials `sudo` hangs
  indefinitely in a non-interactive context. Use `warn` and return early if the
  check fails.
- **`is_running_in_tty` gates interactive-only operations**: `is_running_in_tty`
  returns `false` in cron (no TTY, `FORCE_COLOR` not set). Gate kill/restart
  of login-item apps (and any other interactive-only side-effects) on
  `[[ "${operation}" == 'import' ]] || is_running_in_tty` — cron export must
  not kill running apps or re-launch them via `open -a`.
- **`COLUMNS` fallback in cron**: zsh sets `COLUMNS` to `0` with no terminal.
  Always use `${COLUMNS:-80}` in any code that computes a display width.
- **ERR trap — string form required to capture `$LINENO`**: `trap my_handler ERR`
  evaluates `$LINENO` inside the handler (wrong line). Use a string trap to
  capture it in the failing command's scope: `trap 'my_handler "${LINENO}"' ERR`.
  Full rule in `shell-scripting.instructions.md` § **ERR Trap — `$LINENO` String Form vs Function Form**.
- **`NULL_GLOB` must always be scoped**: never use bare `setopt NULL_GLOB` /
  `unsetopt NULL_GLOB` at script or function scope — changes leak to all
  subsequent code. Always use `setopt localoptions NULL_GLOB` inside a scoped
  block. In pure zsh files (`.zshrc`, autoload scripts), use the anonymous
  function `()`. In files bash may source (`.shellrc`), use a named helper
  function instead — `()` is a **parse-time** error in bash even inside an
  `if is_zsh` guard. Never use inline `(N)` glob qualifiers — they break editor
  syntax highlighting. Full rules in `shell-scripting.instructions.md`
  § **Glob Patterns — NULL_GLOB**.
- **Do not mandate named helpers everywhere**: `()` anonymous functions are
  idiomatic and correct in pure zsh files. Named functions defined inside
  another function in zsh persist in the global table after the outer function
  returns — they are not scoped. The `()` form is truly scoped. Use named
  helpers **only** where bash parseability requires it (`.shellrc`, `.aliases`,
  `.envrc`). The deciding question: can bash ever `source` this file?
  When a named helper is required, always `unfunction` it immediately after use
  — `run-all.sh` sandboxes each repo call in a `()` subshell so the leak is
  contained there, but the `unfunction` is still required for correctness at
  non-subshell call sites (direct interactive invocations, calls from other
  functions in the same process). Full rule in `shell-scripting.instructions.md`
  § **Do not mandate named helpers everywhere**.
- **`is_zsh` guards are for parse-time zsh-only syntax only**: do not wrap a
  function definition in `if is_zsh` unless its body contains syntax bash
  cannot parse (e.g. `${(j.:.)array}`, `(( $+functions[...] ))`). Runtime-only
  zsh constructs (`setopt`, `autoload`) inside functions that bash never calls
  do not need a guard — bash defines the function but never invokes it.

---

## Git Configuration Rules

> Full rules are in `.github/instructions/git-config.instructions.md`.

### Aliases in `~/.gitconfig`

- Aliases that use shell features must use `!sh -c '...' -` or `!git` prefix.
- For multi-step logic, use `!f()` named function pattern: `"!f() { ...; }; f"`.
- Every `!` alias that operates on a repository must accept an optional `<dir>` as its first argument (default `'.'`), using `git -C "${1:-.}"` for every internal git call. This is an alternative to `git -C <path> <alias>` — both forms are equivalent. **Do NOT combine both**: `git -C <path1> alias <path2>` is undefined — the explicit arg wins and `-C <path1>` is silently ignored. Exceptions where `${1}` has a fixed meaning: `sci` (message), `standup` (author), `new`/`old`/`recent-branch`/`oldest-branch` (branch/ref), `pull-unshallow`/`fetch-unshallow` (flags), `f`/`se` (pattern), `relative-path` (own convention) — use `git -C <path> <alias>` only for these.
- The trailing `-` sets `$0`; user args start at `$1`. Never use `$0` for user args.
- `git sci`: smart commit, **non-interactive** — takes a message arg; amends (`git amq`) if ahead of remote and not diverged, otherwise creates a new commit (`git ci`). Aborts if nothing staged. Use `git diff --cached --quiet` (not locale-dependent `grep "to unstage"`).
- `git pull-safe` / `git upreb`: **always guard with a dirty-tree check** before any rebase or push. `rebase.autoStash = true` is not sufficient — it stashes then tries to pop after rebase, which can conflict and leave the repo in a broken mid-operation state. Use `git diff --quiet && git diff --cached --quiet`; if dirty, print to stderr and exit non-zero. Callers in cron scripts must use `_record_warning` (not `_record_error`) — a dirty skip is an expected state, not a failure.
- `git cc` / `git rfc`: **never use `--all`** in `reflog expire` — it discards stashes. Always enumerate refs explicitly with `git for-each-ref refs/heads refs/remotes` only. `refs/tags` must be excluded — tags have no reflogs in any repo (git only maintains reflogs for `HEAD` and branches), and passing them to `git reflog expire` always produces "reflog could not be found" errors for every tag.
- `fetch.fsckObjects = false` enforced in antidote bundle repo git configs
  (ohmyzsh, fast-syntax-highlighting) — `fetch` only, not `receive`/`transfer`.
- **`[delta]`**: use `"syntax <bg-color>"` for `minus-style`/`plus-style` (not bare `"red"`/`"green"`) to preserve syntax highlighting on whole-line diffs. Set `line-fill-method = ansi` to extend diff background to full terminal width. `minus-emph-style` background must be visually brighter than `minus-style` background.

---

## Crontab / Cron Handling

Cron functions are split across two files:

1. **`.shellrc`** — `suspend_cron` and `resume_cron`: needed before the dotfiles
   repo is cloned (used in `fresh-install` for vanilla OS).
2. **`.aliases`** — `_create_crontab`, `recron`, and higher-level cron helpers:
   only needed after dotfiles are installed.

Comments in both files must explain this split for future maintainers.

Exit/error traps in scripts that call `suspend_cron` must call `resume_cron`
(via trap) if `_DOTFILES_CRON_BACKUP_FILE` is present.

Scripts with a single entry point must use the `with_cron_suspended` wrapper
(defined in `.aliases`) rather than calling `suspend_cron`/`resume_cron`
directly — it handles the EXIT trap and error recovery internally:

```zsh
main() {
  with_cron_suspended _main_impl "$@"
}
```

Use the low-level `suspend_cron`/`resume_cron` only when the suspend/resume
scope spans multiple code paths (e.g. `fresh-install-of-osx.sh` where the
scope is the entire `main()`).

Scripts that involve cron operations (e.g., `cc-browser-profiles.sh`) should
source `.aliases` (not `.shellrc`) since the cron functions they need are
defined in `.aliases`.

---

## Starship Prompt Rules

- Git state (rebase/cherry-pick/merge) must be shown in the `custom.git_state`
  section in red.
- `custom.git_state` works for both reftable and classic `.git/HEAD` formats.
- No leading space before the chevron when `custom.git_state` has no output
  (use `when` condition to suppress the module when inactive).
- `ignore_timeout = true` in custom commands that may be slow.

---

## Code Comments

Comments in code files must be written for **future reference**, not as a
narrative of the current change. A reader should be able to understand _why_
a decision was made — not reconstruct what commit introduced it.

Rules:
- Explain **why**, not what the code does (the code already shows the what).
- Document non-obvious constraints, tradeoffs, or design decisions that would
  otherwise force a future reader to re-derive them (e.g. "antidote.zsh
  references BASH_VERSION which is unset in zsh under `set -u`").
- Never phrase a comment as a changelog entry ("Added X to fix Y" or
  "Changed to use Z in this commit"). That context belongs in the git commit
  message, not in the source file.
- Avoid temporal language (`now`, `currently`, `as of this change`) — comments
  must remain accurate across future edits without needing updates themselves.
- Do NOT add a comment purely to satisfy the instruction to comment; only add
  one when it genuinely helps a future reader.

---

## EditorConfig / Formatting

- Indentation: **2 spaces** for all file types.
- Always trim trailing whitespace (except markdown).
- Always end files with a final newline.
- Trim consecutive blank lines (except markdown).
- `max_line_length` is **off** for all file types.

### Shell Formatting

Run `shfmt -w <file>` after every edit to a shell script. See
`shell-scripting.instructions.md` for the full rules on `.shfmtignore` and
the two valid reasons for excluding a file.

**Check `.shfmtignore` before running `shfmt`.** If the file is listed there,
do NOT run `shfmt` on it — skip formatting entirely. Running `shfmt` on an
excluded file corrupts intentional one-liners (e.g. `while true; do ...; done`
expanded into misaligned multi-line form with no way to suppress it inline).

### Ruby Formatting

Run `cd "${HOME}" && rufo <file>` after every edit to a Ruby script. Run from
`$HOME` (not `$DOTFILES_DIR`) — `$DOTFILES_DIR` is pinned to system Ruby 2.6
which cannot run rufo.

---

## `RUBYLIB` / `$LOAD_PATH`

`.shellrc` sets `RUBYLIB` to include `$DOTFILES_DIR/scripts/utilities` and other
utility directories. This allows Ruby scripts to `require 'logging'` (etc.)
without `require_relative`.

On a vanilla OS during `fresh-install`, `RUBYLIB` may not be set yet. The
`install-dotfiles.rb` script (which runs early) must not depend on `RUBYLIB`
pointing to the utilities directory — it manually prepends the utilities path
to `$LOAD_PATH` via `$LOAD_PATH.unshift` at the top of the file, before any
`require` calls.

---

## `install-dotfiles.rb` Behaviour

### Adopt-Existing-File

If a real file (not a symlink) already exists at a symlink target, `install-dotfiles.rb`
**moves the existing file into the repo** (making it the new dotfiles source) before
creating the symlink. This "adopt" behaviour means existing configs are never silently
lost. The `--force` flag overrides this and deletes the existing file instead.

### SSH `Include` Line

After symlinking, `install-dotfiles.rb` ensures the line
`Include "${SSH_CONFIGS_DIR}/global_config"` is present in `${SSH_CONFIGS_DIR}/config`. This
is a post-symlink SSH setup step — do not add it manually or add a duplicate guard
elsewhere.

---

## Keybase / SSH

`ensure_keybase_logged_in` and `build_keybase_repo_url` are defined in
`.aliases` (not `.shellrc`). They are only needed by scripts in `$HOME` and
`$PERSONAL_PROFILES_DIR` — never before the dotfiles repo is cloned. Keeping
them in `.aliases` is correct; moving them to `.shellrc` is not needed.

`GIT_SSH_COMMAND` env var for SSH key selection is set at the top of
`fresh-install` when `FIRST_INSTALL` is true, because `~/.gitconfig` (and thus
`core.sshCommand`) does not exist yet. It must be **unset immediately after
`install-dotfiles.rb` runs**, since that script symlinks `~/.gitconfig` into
place — from that point on `core.sshCommand` is active and `GIT_SSH_COMMAND`
would silently override it for the remainder of the run.

---

## `dispatch_or_fallback` — Per-Project Script Overrides

Autoload functions (`push`, `pull`, `cc`, `upreb`, etc.) support per-project
overrides via `dispatch_or_fallback` (defined in `.shellrc`):

```zsh
push() { dispatch_or_fallback push _push "$@"; }
```

When called, `dispatch_or_fallback` looks for
`${PERSONAL_BIN_DIR}/<cmd>-<cwd-basename>.sh`. If the file exists and is
executable, it is sourced (running in the current shell). Otherwise the default
`_<cmd>` function is called. Scripts in `$PERSONAL_BIN_DIR` follow the naming
convention `<cmd>-<project-dir-name>.sh`.

Similarly, `launch_me`, `debug_me`, and `build_me` look for
`${PERSONAL_BIN_DIR}/launch-${PWD##*/}.sh`, `debug-${PWD##*/}.sh`, and
`build-${PWD##*/}.sh` respectively.

---

## `_SHARED_REPO_DIRS` Convention

`resurrect_tracked_repos` (in `.aliases`) populates `_SHARED_REPO_DIRS` — a
module-level array — after running its expensive `find` traversal. Functions
called in the same logical operation (`install_mise_versions`,
`allow_all_direnv_configs`) check for this array before running their own
traversal, avoiding duplicating the `find` cost. The array is `unset` at the
end of `resurrect_tracked_repos` so it does not persist across independent
invocations.

When adding new functions that need to traverse all repo dirs, check for
`_SHARED_REPO_DIRS` first:

```zsh
if (( ${+_SHARED_REPO_DIRS} )) && is_non_empty_array _SHARED_REPO_DIRS; then
  all_dirs=("${_SHARED_REPO_DIRS[@]}")
else
  # ... run find traversal ...
fi
```

---

## `capture-prefs.sh` — Allowed and Denied Lists

`capture-prefs.sh` exports/imports macOS `defaults` domains using two data
files in `scripts/data/`:

- **`capture-prefs-allowed-list.txt`** — domains that are safe to
  export/import across machines.
- **`capture-prefs-denied-list.txt`** — domains that must never be
  exported/imported. `find_and_append_prefs` (in `.aliases`) warns if you try
  to add a denied domain to the allowed list.

### Denial criteria

A domain belongs on the denied list if it contains any of:

1. **Machine identity / hardware UUIDs** — device-specific identifiers,
   AirTag beacon UUIDs, Apple Push Service tokens, MDM enrollment tokens.
   Importing these onto a different machine corrupts the receiving system's
   identity with the Apple infrastructure.

2. **Account-bound credentials** — Apple ID DSIDs, iMessage/FaceTime
   per-device key material, iCloud sync identities. These are hardware- and
   account-specific; they cannot be reused on another machine or account.

3. **Ephemeral CloudKit / daemon sync state** — per-device CloudKit sync
   cursors, biome sync watermarks, routing state. Importing these confuses
   daemons into treating the new machine as a continuation of the old one,
   causing silent sync failures.

4. **Display / session geometry** — window frame coordinates keyed to
   specific monitor configurations, Space topology with per-monitor display
   UUIDs. These have zero portability value and macOS overwrites them on first
   boot anyway.

5. **OS version stamps and setup-wizard state** — build version strings,
   `SetupAssistant` dismissal flags. macOS ignores or overwrites these; they
   carry no portable value.

### Export format — XML plist, not binary, not JSON

`capture-prefs.sh` exports each domain as an **XML plist** (text), not binary
plist and not JSON. The conversion happens immediately after `defaults export`
via `plutil -convert xml1 <file>` (in-place, no temp file needed).

**Why XML plist over binary plist:**
- Human-readable and fully diffable in git — binary plist diffs are useless.

**Why XML plist over JSON:**
- `defaults import` reads XML plist natively — no conversion step needed on
  import.
- Plist types that have no JSON equivalent (`<date>`, `<data>`, nested
  `<dict>`/`<array>`) are preserved exactly. JSON conversion via `plutil`
  is lossy for `<data>` blobs and `<date>` values, producing base64 strings
  and RFC 3339 strings respectively that `defaults import` cannot round-trip.
- Some allowed domains contain `<data>` blobs for legitimate portable keys
  (e.g. `NSSplitView` frame strings encoded as NSData). These survive
  XML round-trips intact; they do not survive JSON round-trips.

**Portability rules are unchanged** — the allowed/denied list mechanism applies
regardless of file format. A domain on the denied list is skipped whether the
format is binary, XML, or JSON.

**File extension:** `.plist` (not `.defaults`) — signals the format to editors
(syntax highlighting, validation) and to `plutil`.

Do not change the export format to binary or JSON. If a future macOS version
changes the behaviour of `plutil -convert xml1`, verify the round-trip with
`defaults import` before adopting any alternative format.

### Rules when modifying the lists

- **Adding to the allowed list**: verify the domain contains only
  user-configurable preferences (no UUIDs, no credentials, no sync cursors).
  When in doubt, check what keys the domain stores with `defaults read <domain>`
  on a live machine.
- **Adding to the denied list**: document the specific key(s) that make it
  unsafe inline in `capture-prefs-denied-list.txt`, following the comment style
  of the existing entries. Do not add a domain without a comment explaining why.
- **Never copy denied-list reasoning into individual code comments** — the
  canonical explanation lives in the data files themselves.

### Periodic recheck (at most once per session, not more than once per day)

Apps update frequently and may add new keys that violate portability rules.
Proactively recheck all three data files when working in this area:

1. **`capture-prefs-allowed-list.txt`** — run `defaults read <domain>` on any
   domain you touch and verify no new non-portable keys have appeared at the
   domain level (UUIDs, credentials, sync cursors). If a domain has become
   unsafe, move it to the denied list.

2. **`capture-prefs-denied-list.txt`** — scan for any domain that was denied
   for a reason that may no longer apply (e.g. a key that was account-bound but
   has been removed in a newer app version). If safe, move it to the allowed
   list.

Do not recheck all 390+ domains in a single session — focus on domains
relevant to the work at hand. The goal is incremental hygiene, not a full
audit on every change.

---

## `osx-defaults.sh` and `capture-prefs.sh` — Two-Phase Preference Architecture

macOS preferences are managed in two distinct, ordered phases. The order is
load-bearing: phase 2 always wins over phase 1 by design.

### Phase 1 — `osx-defaults.sh -s` (baseline seed)

`osx-defaults.sh` writes a curated baseline of `defaults write` calls covering
macOS system settings and third-party app settings. It is intentionally a
**partial baseline** — it does not attempt to capture every possible preference,
only those where a known-good starting value is worth codifying.

Rules for what belongs in `osx-defaults.sh`:
- Settings the user has never changed via the UI, but should have a specific
  starting value on a fresh machine.
- Settings that are purely scriptable and have no meaningful UI-side override
  (e.g. disabling analytics, enabling developer menu).
- Settings are written as `ask 'Y'` blocks so the user can skip any section
  during a manual run.

Rules for what does NOT belong in `osx-defaults.sh`:
- Settings the user adjusts via the app's UI after initial setup — those belong
  in `capture-prefs.sh`'s allowed list, not here. Writing them here would mean
  `osx-defaults.sh -s` resets them to stale values on every fresh-install.
- Ephemeral state (window positions, last-opened directory, migration sentinels,
  A/B experiment shards) — apps manage these themselves; never codify them.

### Phase 2 — `capture-prefs.sh -i` (UI-configured overrides)

After the baseline is seeded, `capture-prefs.sh -i` imports the preferences
that were captured from the previous machine via `capture-prefs.sh -e`. These
are the settings the user actually configured through each app's UI over time.

Because import runs **after** `osx-defaults.sh`, every UI-configured value
overwrites the corresponding baseline value. The user's deliberate choices
always win.

### Ordering constraint — enforced in `fresh-install-of-osx.sh`

`fresh-install-of-osx.sh` calls these two in strict order:

```zsh
osx-defaults.sh -s      # phase 1 — seed baseline
capture-prefs.sh -i     # phase 2 — restore UI-configured overrides on top
```

**Never reverse this order.** Running `capture-prefs.sh -i` first and then
`osx-defaults.sh` would wipe out the user's UI-configured values wherever
`osx-defaults.sh` writes the same key.

### Decision rule when adding new preference code

When a new preference needs to be managed, apply this rule:

1. **Is it a one-time baseline default the user will never change via UI?**
   → Add it to `osx-defaults.sh`.
2. **Is it something the user configures through the app's UI?**
   → Add its domain to `capture-prefs-allowed-list.txt`. Do not write it in `osx-defaults.sh`.
3. **Is it an ephemeral value the app manages itself?**
   → Add its domain to `capture-prefs-denied-list.txt`. Write it nowhere.

---

## CHANGELOG

CHANGELOG section headers use **semantic versioning** (`major.minor.patch`).
The version to use depends on whether a new commit is being created or an
existing unpushed commit is being amended/extended.

### Determining the version number

Run these two commands from `$DOTFILES_DIR`:

```zsh
git describe --tags --abbrev=0   # most recent tag, e.g. "3.1"
git log @{u}..HEAD --oneline     # empty = nothing unpushed; non-empty = unpushed commit(s)
```

**If `git log @{u}..HEAD` is non-empty** (unpushed commits exist):
The current CHANGELOG entry is still in progress — the work will be folded into
the same commit. Do **not** increment the patch segment. Use the same version
already at the top of `CHANGELOG.md`.

**If `git log @{u}..HEAD` is empty** (HEAD is in sync with remote):
A new commit will be created. Increment the **patch** (3rd) segment of the most
recent tag. If the tag has only two segments (e.g. `3.1`), treat it as `3.1.0`
and increment to `3.1.1`.

Examples:
- Tag `3.1`, nothing unpushed, new work → CHANGELOG header `### 3.1.1`
- Tag `3.1.1`, nothing unpushed, new work → CHANGELOG header `### 3.1.2`
- Tag `3.1`, unpushed commit exists → keep existing header (e.g. `### 3.1.1`)

- Add the new entry at the **top** of `CHANGELOG.md`, above all existing entries.
- Use `### <version>` as the section heading (e.g. `### 3.1.1`).
- Only include changes made within `$DOTFILES_DIR`. Changes to `$PERSONAL_BIN_DIR`
  and `$PERSONAL_CONFIGS_DIR` are subject to the same editing/formatting rules but
  are not documented in this CHANGELOG.

### Sub-sections for top-level goals

Each version entry uses `####` sub-sections to group changes by the high-level
goal they serve. This keeps the entry scannable and makes it easy to understand
what was attempted before looking at individual bullets.

Structure:

```markdown
### <version>

#### <Goal 1 — short noun phrase describing the intent>

* *[file-or-component]* Change description — what and why.

#### <Goal 2>

* *[file-or-component]* ...

#### Adopting these changes

* Steps the user must run to pick up the changes.
```

Rules for sub-sections:
- Use a short noun phrase that describes the **intent** of the group, not the
  files changed (e.g. `Harden capture-prefs.sh`, not `capture-prefs.sh changes`).
- Order sub-sections by impact: behavioral/runtime first, infrastructure next,
  documentation last. `Adopting these changes` is always the final sub-section
  when adoption steps are needed.
- A sub-section may contain a single bullet — don't artificially merge unrelated
  changes just to reduce sub-sections.
- Within each sub-section, bullets follow the same ordering rule:
  1. **Behavioral/runtime changes** — bug fixes, new functions, changed outputs,
     script logic changes (anything that affects what runs or what the user sees)
  2. **Infrastructure changes** — refactors, shared helpers, structural changes
     that enable behavioral changes but are not directly visible
  3. **Documentation** — instruction files, README, CHANGELOG itself
- Each bullet should be scoped with `*[file or component]*` and describe the
  change succinctly — what was done and why, not how.
- Keep each bullet concise — one sentence where possible.
- **Link instruction-file bullets to the named section they reference.** When a
  bullet describes adding or changing a named section in an instructions file,
  embed a markdown link to that section using a repo-root-relative path. Only
  apply this to bullets whose subject is an instructions file (`.instructions.md`,
  `copilot-instructions.md`) — not to code-file bullets (`.shellrc`,
  `fresh-install-of-osx.sh`, etc.), where a file name is sufficient. The link
  text should use the `§ Section Name` convention. GitHub anchor rules: lowercase
  the heading text, strip backticks (keep content), remove all characters except
  letters, numbers, hyphens, underscores, and spaces, then replace spaces with
  hyphens. Em-dashes (—) are stripped and leave two adjacent spaces that each
  become a hyphen (double-hyphen). `$` signs are stripped.

  Example:
  ```markdown
  * *[shell-scripting.instructions.md]* Added
    [§ ERR Trap — `$LINENO` String Form vs Function Form](.github/instructions/shell-scripting.instructions.md#err-trap---lineno-string-form-vs-function-form).
  ```

### Commit Message Style

- Write commit messages in the **past tense** (e.g. "Replaced X with Y", "Fixed
  bug in Z") — not imperative mood ("Replace X", "Fix Z").
- The message should describe what changed, not what to do.
- Keep messages **succinct**: use the `####` sub-section goal headings from the
  current CHANGELOG entry as the commit message, joined with semicolons. These
  headings already capture the intent of every change made in the session.
  Omit the `Adopting these changes` sub-section — it is not a code change.

  Example:
  ```
  Hardened capture-prefs.sh; expanded osx-defaults.sh; extracted shared macOS
  prefs helpers; fixed cron-safety issues; added technical deep-dive docs
  ```

  Use `git next-version` to confirm the version before finalising the CHANGELOG
  entry, then use the sub-section headings from that entry as the commit message.

---

## Documentation Update Routine

Run this routine **proactively at the end of every session** and **at least
once per day** when multiple sessions occur. Do not wait to be asked.

### Trigger conditions

Run the routine whenever any of the following occurred during the session:

- A new design decision was made or an existing one was revised
- A bug was discovered and fixed (especially if the fix reveals a general rule)
- A new pattern, constraint, or naming convention was established
- A new script or function was added or significantly changed
- An existing rule in any instructions file was found to be incorrect or incomplete
- A new adopter-facing workflow step was introduced

### Routing: what goes where

Apply each piece of pertinent information to the **tightest** file that owns
it. Never duplicate the same rule across files — put it in one place and
cross-reference from broader files where needed.

| Type of information | Primary file | Cross-reference if significant |
|---|---|---|
| Shell scripting rule, pattern, or pitfall | `shell-scripting.instructions.md` | Here (summary bullets) |
| Zsh startup optimisation or startup-path constraint | `zsh-startup.instructions.md` | Here (summary bullets) |
| Git config alias pattern or delta/diff rule | `git-config.instructions.md` | Here (summary bullets) |
| Ruby scripting pattern or convention | `ruby-scripting.instructions.md` | — |
| Fresh-install idempotency guard or bootstrap constraint | `fresh-install.instructions.md` | Here if affects general readers |
| Naming convention, global state variable, or sourcing rule | Here (primary) | `TechnicalDeepDive.md` § 2 or § 3 if architectural |
| Architectural explanation (why a design exists) | `TechnicalDeepDive.md` | Link from adopter docs if user-visible |
| New or changed script behaviour | `Extras.md` | Link to `TechnicalDeepDive.md` for internals |
| Adopter workflow change (fork, upgrade, import/export steps) | `README.md` | `GettingStarted.md` if affects first-run |
| Bug fix or behavioural change with adoption steps | `CHANGELOG.md` under current version | — |
| Inaccuracy found in any doc | Fix in-place in the affected file | Fix all files that carry the same error |

### Process

1. Scan the full session for decisions, fixes, and patterns not yet reflected
   in any doc.
2. For each item, identify the tightest owning file from the routing table above.
3. Draft the addition in the style of the surrounding content in that file
   (see § **Code Comments**: explain *why*, not what; no temporal language; no
   changelog phrasing).
4. Apply the edit. If a broader file needs a cross-reference or summary bullet,
   add that too.
5. **Cross-reference analysis — mandatory after every doc update**: after
   editing any documentation file (especially `TechnicalDeepDive.md`), scan
   all adopter-facing docs (`Extras.md`, `GettingStarted.md`, `README.md`,
   `copilot-instructions.md`) for places that describe the same concept without
   a link to the updated section. Add or update links so that every relevant
   mention in adopter docs points to the canonical deep-dive section. Conversely,
   if a new section was added to an adopter doc, check whether `TechnicalDeepDive.md`
   has a matching deep-dive section that should be linked from it.
6. If the item belongs in `CHANGELOG.md`, add it under the current `### x.y.z`
   version using the `####` sub-section format. Determine the version using the
   rules in § **CHANGELOG** above.
7. After all updates, verify no file now contains a stale or contradicted
   version of the same rule.

### What does NOT belong in documentation

- Changelog-style phrasing in code comments ("Added X to fix Y").
- Temporal language ("currently", "as of this session", "now uses").
- Implementation details that are already self-evident from reading the code.
- Redundant duplication of a rule already present in the tightest file.
