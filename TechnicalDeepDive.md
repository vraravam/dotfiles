# Technical Deep Dive

This document is for adopters who want to understand **how and why** this repo is built the way it is. It covers the internal architecture, design decisions, and the reasoning behind patterns you will encounter when reading or modifying the scripts.

If you are setting up a new machine for the first time, start with [GettingStarted.md](GettingStarted.md) instead.

---

## Table of Contents

1. [Design Principles](#1-design-principles)
2. [Repository Layout](#2-repository-layout)
3. [Shell Architecture: `.shellrc` vs `.aliases`](#3-shell-architecture-shellrc-vs-aliases)
4. [Logging System](#4-logging-system)
5. [Exit Code Safety: `if` vs `&&`](#5-exit-code-safety-if-vs-)
6. [Deferred Error and Warning Collection](#6-deferred-error-and-warning-collection)
7. [Zsh Startup Optimisation](#7-zsh-startup-optimisation)
8. [Cron Safety Mechanisms](#8-cron-safety-mechanisms)
9. [`install-dotfiles.rb` Mechanics](#9-install-dotfilesrb-mechanics)
10. [Per-Project Script Overrides](#10-per-project-script-overrides)
11. [`capture-prefs.rb` Architecture](#11-capture-prefsrb-architecture)
12. [`osx-defaults.sh` and `capture-prefs.rb` — Two-Phase Preference Architecture](#12-osx-defaultssh-and-capture-prefsrb--two-phase-preference-architecture)

---

## 1. Design Principles

Every decision in this codebase is governed by four priorities, applied in order. A higher priority always wins over a lower one.

### 1.1 Startup speed

The shell must be usable immediately after opening a terminal. Every `$(...)` command substitution forks a new process — on a loaded system this can add tens of milliseconds each. The startup hot path (`.zshenv` → `.zshrc` → `.zlogin`) avoids all subshell forks. Zsh built-in parameter expansions (`${MACHTYPE%%-*}` instead of `$(uname -m)`, `${COLUMNS}` instead of `$(tput cols)`) are used throughout.

### 1.2 Maintainability

Performance optimisations that obscure intent are always commented. A reader with basic zsh knowledge should understand any section without needing to re-derive the intent.

### 1.3 POSIX compatibility

Where possible, syntax is kept POSIX-compatible so that scripts remain portable in bash contexts (`.envrc` files run in a bash subshell via direnv, git alias bodies use `sh`). When POSIX syntax would require a subshell fork or degrade readability, zsh built-ins are used with a comment explaining why.

### 1.4 Idempotency

`fresh-install-of-osx.rb` — the main bootstrap — must work correctly both on a **vanilla macOS** and on a **fully configured machine**. Every section has a guard at the very top that short-circuits the entire section when its work is already done. Re-running on a configured machine is therefore fast: only sections with outstanding work execute their logic.

The `FIRST_INSTALL` environment variable signals a vanilla OS run. Logic that only makes sense on a blank slate (e.g. downloading `.shellrc` via `curl` before the dotfiles repo exists) is guarded with `is_first_install` (a utility function in `.shellrc` that wraps `[[ -n "${FIRST_INSTALL:-}" ]]`). Two occurrences in `fresh-install-of-osx.rb` use the raw form directly because they run before `.shellrc` has been sourced.

---

## 2. Repository Layout

```
files/
  --HOME--/              symlinked into $HOME
  --ZDOTDIR--/           symlinked into $ZDOTDIR (defaults to $HOME)
  --XDG_CONFIG_HOME--/   symlinked into $XDG_CONFIG_HOME
  --PERSONAL_PROFILES_DIR--/  .envrc for direnv
scripts/
  fresh-install-of-osx.rb
  capture-prefs.rb
  osx-defaults.sh
  utilities/             shared Ruby modules (logging, string, cli_parser, …)
  data/                  plain-text data files read by scripts at runtime
```

### The `--VAR--` naming convention

Subdirectories under `files/` use the pattern `--ENV_VAR_NAME--`. The `install-dotfiles.rb` script resolves each directory name to the env var it names (`--HOME--` → `$HOME`, `--XDG_CONFIG_HOME--` → `$XDG_CONFIG_HOME`) and symlinks every file inside into the resolved directory.

To add a new dotfile, drop it under the appropriate `files/--VAR--/` directory. The script handles nested paths, conflict resolution, and the difference between symlinks and copies (see [§ 9](#9-install-dotfilesrb-mechanics)).

### The three directories

| Variable | Default path | Purpose |
|---|---|---|
| `$DOTFILES_DIR` | `~/.config/dotfiles` | This repo |
| `$PERSONAL_BIN_DIR` | `~/personal/dev/bin` | Private scripts and per-project overrides |
| `$PERSONAL_CONFIGS_DIR` | `~/personal/dev/configs` | Private config files (repo catalog YAML, exported prefs, etc.) |

`$PERSONAL_BIN_DIR` and `$PERSONAL_CONFIGS_DIR` live outside the dotfiles repo. They are never present on a vanilla OS before the dotfiles repo is cloned, so any function that only these scripts need belongs in `.aliases` — not `.shellrc`. They are kept separate intentionally: they hold private data (credentials, personal scripts, site-specific configs) that must never appear in a public repository. The only personal identifiers that belong in this repo are `GH_USERNAME` (a public GitHub username, inherently non-sensitive) and references to Keybase (which handles its own encryption for private data).

---

## 3. Shell Architecture: `.shellrc` vs `.aliases`

### Why the split exists

`.shellrc` is downloaded via `curl` early in `fresh-install-of-osx.rb`, **before** the dotfiles repo has been cloned and before `install-dotfiles.rb` has created symlinks. It must therefore stay lean — it holds only the functions that are genuinely needed in that pre-clone window.

`.aliases` is available only after the dotfiles repo is cloned and `install-dotfiles.rb` has run. Everything that does not need to exist before that point lives in `.aliases`.

### Decision rule

A function belongs in `.shellrc` if it is called during a vanilla-OS fresh-install **before `install-dotfiles.rb` runs**. Everything else belongs in `.aliases`.

There is a second constraint: `.envrc` files are evaluated by direnv in a **bash subshell**. They must source `.shellrc` (not `.aliases`) because `.aliases` contains zsh-only syntax (`:h`, `:A`, associative array subscripts, zsh-specific glob qualifiers) that bash cannot parse. Any function called from a `.envrc` file — even one that is not needed during the pre-clone window — must therefore live in `.shellrc`, with a comment explaining the bash-compat reason.

### Sourcing discipline

- Each script sources **only the tightest file** that provides what it needs.
- If a script needs only `.shellrc` functions, it sources `.shellrc`.
- If it needs `.aliases` functions, it sources `.aliases` — which already sources `.shellrc` internally.
- Never source both in the same script.

### Re-source guards

`.shellrc` defines a sentinel function `is_shellrc_sourced`. Other scripts source `.shellrc` unconditionally; the guard inside `.shellrc` itself prevents double-loading. The same applies to `.aliases` via `is_aliases_sourced`. Scripts add a comment — `# Re-source guard is inside .shellrc/.aliases itself — safe to call unconditionally.` — to make this explicit without repeating the guard logic.

---

## 4. Logging System

### Log levels

Six levels are defined in `.shellrc`, each with a distinct visual treatment:

| Level | Prefix/colour | When to use |
|---|---|---|
| `debug` | `**DEBUG**` (light purple) | Expected-absent optional tools, silently-skipped steps. Hidden by default; visible with `DEBUG=true`. |
| `info` | no prefix (plain) | Normal progress and idempotency guards ("already installed — skipping"). Suppressed when `DIRENV_IN_ENVRC` is set (direnv subshell). |
| `success` | `**SUCCESS**` (green) | An operation completed successfully. Suppressed when `DIRENV_IN_ENVRC` is set (direnv subshell). |
| `warn` | `**WARN**` (light red) | Argument-parse failures (followed by `usage` + `return 1`); non-fatal recoverable failures. |
| `error` | `**ERROR**` (red) | Unexpected mid-script failures. In shell: prints and fires a macOS notification via `osascript`. In Ruby: raises `RuntimeError`. |
| `user_action` | `➡️` (bold yellow) | Manual steps the user must perform after the script exits (restart an app, run a command). |

The key distinction between `warn` and `error`: `warn` is for expected failure modes (bad flag, recoverable skip). `error` triggers a macOS notification pop-up — using it for a typo in a flag argument would be annoying UX, so `warn` is always correct for argument-parse failures.

### Section headers and visual hierarchy

Two levels of section header provide a visual indent stack:

```
══════════════ ⏳ Top-level section ══════════════    ← section_header
  ──────── 🔷 Sub-step inside section ────────        ← section_header2
```

`section_header` uses `=` padding, `light_blue` colour, and no indent.
`section_header2` uses `-` padding, `cyan` colour, and 2-space indent.

The padding width is computed from `${COLUMNS:-80}` (the terminal width) minus the header text length, split evenly on both sides. The fallback to `80` is deliberate: cron jobs run with no terminal attached, so zsh sets `COLUMNS` to `0` — without the fallback, the arithmetic yields zero or negative lengths and `printf` produces no output.

### Color functions and tilde substitution

Color functions (`blue`, `red`, `cyan`, `yellow`, etc.) wrap their argument in ANSI escape codes and — importantly — apply `${1//${HOME}/~}` inline to replace absolute home paths with `~`. This substitution is a **no-fork** operation: it uses zsh parameter expansion, not a subshell call. Logging functions (`info`, `warn`, etc.) do not apply the substitution themselves; they rely on the color functions to do it.

This means: never call `replace_home_with_tilde` before passing a path to a color function — the substitution happens inside and calling it twice is redundant.

---

## 5. Exit Code Safety: `if` vs `&&`

### The problem

`A && B` means "run B only if A succeeds". Under `set -e` or an ERR trap, if A returns non-zero, the entire `&&` expression also returns non-zero — which triggers `set -e` abort or fires the ERR trap, **even if A returning false is a completely normal, expected outcome**.

For example:

```zsh
is_file "${optional_config}" && cp "${optional_config}" "${dest}"
```

`is_file` returns `1` when the file is absent. That is the common case (the file is optional). But the `&&` expression returns `1`, which under `set -e` aborts the script as if an error occurred.

### The fix

Always use an explicit `if` for predicates whose "false" branch is a normal outcome:

```zsh
if is_file "${optional_config}"; then
  cp "${optional_config}" "${dest}"
fi
```

An `if` statement never propagates a non-zero exit code from the condition to the enclosing scope.

### The safe exception

`A && B || C` is safe when `C` always returns 0. The overall expression resolves to `C`'s exit code (0), so the ERR trap never fires. This pattern is used intentionally for success/failure dispatch:

```zsh
git pull -r && success "Updated: ${folder}" || _record_warning "Failed: ${folder}"
```

`_record_warning` always returns 0, making this safe. Do not use this pattern if `C` can return non-zero.

### Scanning rule

When editing any script that uses `set -e` or an ERR trap, scan every standalone `A && B` line and verify that A returning false is a genuine error (not a normal case). If it is expected, convert to `if A; then B; fi`.

---

## 6. Deferred Error and Warning Collection

### Motivation

Scripts that process many items (e.g. iterating over 100+ repos, 100+ preference domains) should not fire a macOS notification for each individual failure. A single summary notification at the end is far less disruptive.

### The pattern

Every script that uses this pattern declares three locals and increments the nesting counter at the top of `main()`:

```zsh
main() {
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  trap '_decrement_script_depth' EXIT   # or chained into an existing EXIT trap
  ...
}
```

The helpers `_record_warning` and `_record_error` (defined in `.shellrc`) append to these arrays via **zsh dynamic scoping** — they write into the caller's `local` variables without needing them passed as arguments. They also emit an inline `warn`/`error` log line immediately so failures are visible in the log stream as they happen.

`print_script_summary` is called once at the end of `main()`. It prints all collected warnings then errors, and if any errors were collected it fires exactly one `_dotfiles_notify` with a consolidated message.

### Nesting depth counter and dual-purpose indentation

`_DOTFILES_SCRIPT_DEPTH` is an exported integer that tracks call depth across subprocess boundaries. It defaults to `0` when unset; each `main()` increments it on entry and decrements it on exit via an EXIT trap.

The depth counter serves **two purposes**:

1. **Banner suppression**: `is_outermost_script` (shell) and `outermost_script?` (Ruby) check `_DOTFILES_SCRIPT_DEPTH <= 1`. Both `print_script_start` and `print_script_summary` call this predicate and return early when depth > 1, ensuring only the outermost script prints its start/finish banners and final summary.

2. **Automatic indentation**: All logging functions (`info`, `warn`, `success`, `error`, `debug`, `user_action`) and section headers automatically prepend `2 * depth` spaces to their output, creating visual hierarchy that matches the call stack.

#### How depth-based indentation works

Every script starts at depth 0, increments to 1 in `main()`, and logs at depth 1:

```zsh
# Standalone script
main() {
  export _DOTFILES_SCRIPT_DEPTH=1  # 0 → 1
  info "Processing items..."         # Logs with 2-space indent
}
```

When a script calls another script as a subprocess, the child inherits the parent's depth and increments further:

```zsh
# Parent script at depth 1
info "Starting batch process..."    # 2-space indent

# Child subprocess
system('other-script.sh')           # Inherits depth=1, increments to 2
  # Child's info messages            # 4-space indent
  # Child's banners suppressed        # depth > 1

# Back to parent at depth 1
success "Batch complete"             # 2-space indent
```

This creates clear visual hierarchy:
- **Depth 0**: Script not yet started (no output)
- **Depth 1**: Standalone script or outermost script's main content (2-space indent)
- **Depth 2**: First-level subprocess (4-space indent, banners suppressed)
- **Depth 3+**: Deeper nesting (6+ space indent, banners suppressed)

#### No manual indentation needed

Call sites never manually prepend spaces to log messages. The depth counter handles all indentation automatically:

```zsh
# Before refactoring (manual indent)
info "  -> Processed ${count} items"

# After refactoring (auto-indent)
info "-> Processed ${count} items"  # Depth adds the indent
```

#### Bulleted lists: depth + 1

The `join_array` helper (shell) automatically indents list items one level deeper than the current depth, creating subordinate visual structure:

```zsh
# At depth 1 (2 spaces)
info "Failed items:"
join_array failed_items  # Items indented 4 spaces (depth + 1)
```

#### External tool output — intentionally not indented

External tools (`git`, `mise`, `sqlite3`) invoked via `system()` print directly to stdout/stderr at column 0. This is intentional — wrapping their output would add complexity (signal handling, streaming, exit code preservation) for minimal UX benefit. Tool output remains visually distinct from our structured logging.

#### Why subprocess scripts also decrement

All scripts with the counter are currently invoked as **subprocesses** (not sourced). Subprocess environments are copies — a child's increment does not affect the parent, and the parent's depth is unaffected when the child exits. The decrement therefore has no practical effect on correctness today.

The decrement is applied anyway as a defensive, symmetric pattern:
- If a script is ever converted from subprocess to sourced invocation, the decrement immediately becomes load-bearing without any further change.
- It establishes a consistent visual contract: every increment has a matching decrement, making audits straightforward.

#### Why `_decrement_script_depth` is a helper function, not inline arithmetic

The trap string must work both as a standalone trap (`trap '_decrement_script_depth' EXIT`) and chained into existing traps (`trap '...; _decrement_script_depth' EXIT`). Extracting it to a named helper keeps the arithmetic and underflow guard (`[[ depth -gt 0 ]]`) in one place and avoids repeating the logic across nine trap strings.

### Ruby equivalent

Ruby scripts call `Logging.increment_script_depth` once before `print_script_start`. It increments `ENV['_DOTFILES_SCRIPT_DEPTH']` and registers an `at_exit` hook that calls `Logging.decrement_script_depth` — the exact mirror of the shell's increment + EXIT trap pair.

```ruby
Logging.increment_script_depth
script_start_time = Logging.print_script_start
```

`at_exit` handlers in Ruby run on both clean exit and uncaught exceptions, mirroring the shell EXIT trap's behaviour on both normal and error exits.

### When to use `_record_error` vs `warn`

- **Argument-parse failures** (`?`/`:` getopts cases, missing required flags): always use `warn` + `usage` + `return 1`. These are interactive typos; a pop-up notification is inappropriate.
- **Runtime failures** (missing env vars, failed remote calls, unexpected file states): use `_record_error`. These are unexpected environment problems worth surfacing as a notification.

---

## 7. Zsh Startup Optimisation

### No subshell forks in the hot path

The startup sequence (`.zshenv` → `.zshrc` → `.zlogin`) is measured in milliseconds. Every `$(...)` call forks a new process. Common substitutions are replaced with zero-fork equivalents wherever possible:

| Naive (forks) | Fast (no fork) |
|---|---|
| `$(whoami)` | `${USER}` |
| `$(tput cols)` | `${COLUMNS}` |
| `type func > /dev/null` | `(( $+functions[func] ))` |

Architecture detection is a known exception: `${MACHTYPE%%-*}` is the ideal no-fork form, but `MACHTYPE` is unreliable on a vanilla macOS before Homebrew's zsh is active. `.shellrc` therefore uses `$(uname -m)` with a comment, accepting the fork cost at this one site in exchange for correctness across all environments.

### Homebrew shellenv caching

`brew shellenv` sets PATH, MANPATH, and a handful of other variables. It is slow (~100 ms). The output is cached to `$XDG_CONFIG_HOME/zsh/homebrew-shellenv-cache.zsh` and sourced from there on subsequent starts. The cache is regenerated only when the brew binary is newer than the cache file.

### ZWC compilation

Zsh can compile `.zsh` files to `.zwc` bytecode for faster loading. `.zlogin` triggers background compilation of all startup files and autoload directories after the interactive shell is ready. The `delete_caches` function removes all `.zwc` files; zsh regenerates them on the next startup.

### Antidote plugin manager

Antidote replaces oh-my-zsh as the plugin manager. Key properties:
- Static bundle: plugins are resolved once and written to a bundle file (`.zsh_plugins.zsh`) checked into the home git repo. The bundle is sourced at startup — no network call.
- `ANTIDOTE_HOME` is set to `~/Library/Caches/antidote` (macOS-specific cache location).
- The bundle is regenerated in a clean subshell (`zsh --no-rcs -c "antidote bundle < ..."`) to prevent ANSI escape codes from the interactive session leaking into the bundle file.
- Plugin option variables (e.g. `ZSH_AUTOSUGGEST_STRATEGY`) must be set **before** the bundle is sourced — plugins read them at load time.

### `compinit` caching

`compinit` (the completion system initialiser) runs a filesystem security scan (`compaudit`) that can add ~50 ms. On subsequent starts, `compinit -C` is passed to skip the scan — the dump file at `$XDG_CACHE_HOME/zcompdump` serves as evidence that the scan already ran.

### Startup profiling results

Running `ZSH_PROFILE=true zsh -i -c exit` reveals where time is actually spent during startup. The output is captured via `zprof` which instruments all function calls.

**Current measured breakdown (total ~50ms)**:

| Component | Time | % | Notes |
|---|---|---|
| Antidote plugin bundle | 42.2ms | 84% | Largest single cost; sources 6 plugins synchronously |
| `_zsh_highlight_bind_widgets` | 2.6ms | 5% | fast-syntax-highlighting widget setup |
| `antidote-setup` | 2.0ms | 4% | antidote initialization (not plugin loading) |
| Everything else | 3.2ms | 7% | Path setup, cache checks, utility functions |

**Key insights from profiling**:

1. **Plugin loading dominates**: The antidote bundle (line 204-210 in `.zshrc`) accounts for 84% of startup time. This is the cost of sourcing:
   - OMZ lib files: `functions.zsh` (284 lines), `completion.zsh` (78 lines), `key-bindings.zsh` (145 lines)
   - Synchronous plugins: `direnv`, `fast-syntax-highlighting` (384 lines), `zsh-autosuggestions`
   - Total: ~1000 lines of shell code parsed and executed before the first prompt

2. **Deferred plugins don't appear in profile**: The git plugin (431 lines), eza, iterm2, sudo, zbell, and history-substring-search are all loaded via `zsh-defer` — they fire after the first ZLE idle event, so they never block the prompt and don't appear in the `zprof` output at all.

3. **`.aliases` deferred successfully**: Also loaded via `zsh-defer` (963 lines), so it contributes zero time to the measured startup sequence.

4. **All cache strategies working correctly**:
   - `brew shellenv`: cached, only 0.62ms to source (anonymous function at line 103)
   - `git version`: cached, only 0.26ms to source (anonymous function at line 163)
   - `mise activate`: cached, only 1.54ms to source (anonymous function at line 221)
   - `starship init`: cached, only 1.50ms to source (anonymous function at line 258)

5. **No optimization opportunities remain**: The only significant cost is the plugin bundle, and that cost is unavoidable — those plugins must be loaded synchronously because they provide core shell functionality (completion, correction, key bindings, syntax highlighting, autosuggestions). The heavy plugins (git, eza, etc.) are already deferred.

**Conclusion**: Startup time of ~50ms is excellent for a fully-featured interactive shell with syntax highlighting, autosuggestions, comprehensive completions, and 15+ plugins. Further optimization would require removing functionality, which is not desirable.

---

## 8. Cron Safety Mechanisms

Scripts invoked from cron run in a minimal, non-interactive environment. Several things that work in a terminal silently fail or hang in cron.

### `load_zsh_configs` — only when genuinely needed

`load_zsh_configs` sources `.zshrc`, which sources `.zlogin`. `.zlogin` triggers background ZWC compilation jobs. Launching these from a cron job with no terminal attached is disruptive and wasteful.

**Rule:** call `load_zsh_configs` from a cron script only if the script uses variables or functions defined in `.zshrc` (e.g. `PROJECTS_BASE_DIR`, mise shims). Most cron scripts only need vars from `.shellrc`/`.aliases` — these are available after `load_file_if_exists "${HOME}/.aliases"` without calling `load_zsh_configs`.

### `sudo` — always guard with `has_sudo_credentials`

`sudo` prompts for a password when credentials are not cached. In a non-interactive cron context there is no terminal to type into — the process hangs indefinitely.

Any function callable from cron that uses `sudo` must call `has_sudo_credentials` (defined in `.shellrc`) first and return early with a `warn` if it fails:

```zsh
if ! has_sudo_credentials; then
  warn "sudo credentials not available — skipping."
  return 0
fi
sudo some-command
```

`has_sudo_credentials` encapsulates the `sudo -n true 2>/dev/null` check so call sites do not need to know the raw invocation.

### `is_running_in_tty` — gate interactive-only operations

`is_running_in_tty` returns `true` when stdin is a TTY (`[[ -t 0 ]]`) or `FORCE_COLOR` is set. In cron — no TTY, `FORCE_COLOR` unset — it returns `false`.

Operations that interact with the running desktop (killing apps, re-launching them via `open -a`) must be gated:

```zsh
if [[ "${operation}" == 'import' ]] || is_running_in_tty; then
  kill_login_item_apps
  trap 'restart_login_item_apps; cleanup' EXIT
else
  trap 'cleanup' EXIT
fi
```

In `capture-prefs.rb`: export from cron must not kill login-item apps — the user might be actively using them. Import always kills/restarts because the user explicitly triggered it.

### `COLUMNS` — always use `${COLUMNS:-80}`

Zsh sets `COLUMNS` to `0` when no terminal is attached. Any code that uses `COLUMNS` for arithmetic (header padding widths, display lengths) must use `${COLUMNS:-80}` to avoid zero-division or negative lengths.

### `info`/`success` suppression in direnv

`.shellrc` suppresses `info` and `success` output when `DIRENV_IN_ENVRC` is set — the variable direnv injects during `.envrc` evaluation. `DIRENV_DIR` is intentionally not used as the guard: it does not survive direnv's `strict_env` mode. `warn` and `error` always print. This means `.envrc` files need no special log-suppression logic.

---

## 9. `install-dotfiles.rb` Mechanics

### `--VAR--` resolution

Each subdirectory under `files/` named `--VAR--` is resolved by reading the environment variable named `VAR` and expanding it to an absolute path. Files inside are then symlinked into that resolved directory.

Plain subdirectory names without the `--VAR--` pattern are resolved literally from `/` (e.g. `files/etc/` → `/etc/`). The `--VAR--` form is preferred for any path that may differ between machines.

### Adopt-existing-file behaviour

If a real file (not a symlink) already exists at a symlink target, `install-dotfiles.rb` **moves the existing file into the repo** before creating the symlink. This "adopt" behaviour ensures existing configs are never silently discarded. The `--force` flag overrides this and deletes the existing file instead.

### Copy vs symlink for `custom.git*`

Files matching `custom.git*` (e.g. `custom.gitignore`, `custom.gitattributes`) are **copied** rather than symlinked. Git itself does not handle symlinks reliably for its own core config files. Conflict resolution when both the source (repo) and destination (home) exist as real files:

- `FIRST_INSTALL` set → destination always wins (moved into repo, then copied back).
- Otherwise → the file with the **newer mtime** wins. On a tie, the repo wins.

### SSH `Include` injection

After symlinking, `install-dotfiles.rb` ensures the line `Include "./global_config"` is present in `${HOME}/.ssh/config`. This is a post-symlink step — do not add it manually or duplicate the guard elsewhere.

---

## 10. Per-Project Script Overrides

### `dispatch_or_fallback`

Autoload functions (`cc`, `count`, `pull`, `push`, `st`, `upreb`) support per-project overrides. The public function is a thin wrapper:

```zsh
push() { dispatch_or_fallback push _push "$@"; }
```

When called, `dispatch_or_fallback` looks for `${PERSONAL_BIN_DIR}/<cmd>-<cwd-basename>.sh`. If the file exists and is executable, it is **sourced in the current shell** (so it inherits all functions and env vars). Otherwise the default `_push` implementation is called.

This means you can have a file `~/personal/dev/bin/push-my-project.sh` that overrides the push behaviour specifically when you are inside a directory named `my-project`, without touching the shared `push` function.

`status_all_repos` and `update_all_repos` intentionally do not use this pattern — they operate on a fixed set of repos and a cwd-based override would not be meaningful.

The same dispatch mechanism applies to `launch_me`, `debug_me`, and `build_me` — they look for `launch-<dir>.sh`, `debug-<dir>.sh`, and `build-<dir>.sh` respectively.

---

## 11. `capture-prefs.rb` Architecture

### Why XML plist (not binary, not JSON)

`defaults export` produces binary plist by default. `capture-prefs.rb` immediately converts to XML (`plutil -convert xml1`) for two reasons:

1. **Diffability**: XML plist is human-readable and produces meaningful git diffs. Binary plist diffs are useless.
2. **Round-trip fidelity**: `defaults import` reads XML plist natively. Converting via JSON is lossy — `<data>` blobs become base64 strings and `<date>` values become RFC 3339 strings that `defaults import` cannot round-trip. Some domains contain `<data>`-encoded values for legitimate portable keys (e.g. split-view frame strings).

### Three data files

| File | Purpose |
|---|---|
| `capture-prefs-allowed-list.txt` | Domains to export/import. One domain per line. |
| `capture-prefs-denied-list.txt` | Domains that must never be exported/imported (machine UUIDs, credentials, sync cursors, display geometry). Each entry has an inline comment explaining why. |
| `capture-prefs-excluded-keys.txt` | Individual keys within allowed domains that must be stripped before export/import. Format: `domain|key-or-glob-pattern`. The `*` domain applies patterns to every domain. |

### Key stripping: `_strip_excluded_keys`

After exporting a domain to XML, `_strip_excluded_keys` reads the top-level keys via `python3` (null-byte separated to handle keys with spaces), then for each key tests it against the patterns for that domain. Matched keys are deleted by `PlistBuddy`. Deletions are non-fatal — a missing key is silently skipped.

On import, stripping runs on a **temp copy** of the `.plist` file. The source file in the git repo is never modified during import.

The script-scoped `_excluded_by_domain` associative array is populated at startup (not per-domain) because zsh cannot pass associative arrays by value to functions.

### Cron export scoping

`capture-prefs.rb -e` (export) is called from `software-updates-cron.rb`. In this context:
- Killing login-item apps is wrong — the user may be actively using them.
- Re-launching them via `open -a` is worse — apps restart mid-session without the user's knowledge.

Kill/restart is therefore scoped to: always on import; interactive (TTY) export only. The `is_running_in_tty` check provides this gate. The EXIT trap in cron export only calls `resume_softwareupdate_schedule`.

---

## 12. `osx-defaults.sh` and `capture-prefs.rb` — Two-Phase Preference Architecture

macOS preferences are managed in two distinct, ordered phases. The order is load-bearing: phase 2 always wins over phase 1 by design. Both phases are invoked automatically by `fresh-install-of-osx.rb` in sequence.

### Phase 1 — `osx-defaults.sh -s` (baseline seed)

`osx-defaults.sh` writes a curated, partial baseline of `defaults write` calls. "Partial" is intentional — it only codifies settings where a known-good starting value is worth establishing on a fresh machine. It does not attempt to replicate every preference the user has ever configured.

The baseline is appropriate for:
- System settings the user has never changed via the UI (Dock behaviour, Finder display options, keyboard shortcuts).
- App settings that are purely scriptable and have no meaningful UI-side equivalent (disabling analytics, enabling developer menus).

The baseline is **not** appropriate for:
- Any setting the user configures through the app's UI over time. Writing those here means `osx-defaults.sh -s` would reset them to stale values on every fresh-install, defeating the purpose of phase 2.
- Ephemeral state (window coordinates, last-opened directory, migration sentinels, A/B experiment assignments). Apps manage these themselves.

### Phase 2 — `capture-prefs.rb -i` (UI-configured overrides)

`capture-prefs.rb -i` imports the `.plist` files previously exported from the user's old machine via `capture-prefs.rb -e`. Because this runs *after* phase 1, every imported value overwrites the corresponding baseline value. The user's deliberate, UI-configured choices always win.

### Why the order is load-bearing

```zsh
osx-defaults.sh -s    # phase 1 — write baseline
capture-prefs.rb -i   # phase 2 — overwrite with UI-configured values
```

Reversing the order causes `osx-defaults.sh` to overwrite the user's restored preferences with stale baseline values — exactly the wrong outcome. `fresh-install-of-osx.rb` encodes this order and must not be changed without understanding this constraint.

### Decision rule for new preference code

| Preference type | Where it goes |
|---|---|
| One-time baseline the user will not change via UI | `osx-defaults.sh` |
| Something the user configures through the app's UI | `capture-prefs-allowed-list.txt` — not `osx-defaults.sh` |
| Ephemeral state the app manages itself | `capture-prefs-excluded-keys.txt` or `-denied-list.txt` — nowhere else |

See [Extras.md — osx-defaults.sh](Extras.md#osx-defaultssh) for the adopter-facing summary.

---

## 13. Why `fresh-install-of-osx.rb` and `osx-defaults.sh` Remain Shell Scripts

While much of this codebase has migrated from shell to Ruby for maintainability and testability, two core scripts **will never be converted**: `fresh-install-of-osx.rb` and `osx-defaults.sh`. This is an intentional architectural decision based on practical constraints.

### `fresh-install-of-osx.rb` — Bootstrap Complexity

Converting `fresh-install-of-osx.rb` to Ruby would introduce unacceptable complexity in the bootstrap path:

1. **Vanilla OS constraint**: On a fresh macOS, only `/usr/bin/ruby` (system Ruby 2.6) is available. No gems, no `require_relative`, no `Pathname`. The bootstrap must work with *only* what the OS provides out of the box.

2. **Variable duplication**: Bootstrap variables (`DOTFILES_DIR`, `FIRST_INSTALL`, etc.) must exist in **two places**:
   - In shell form in `.shellrc` (sourced immediately after `curl` download on vanilla OS)
   - In Ruby form in `utilities/env_vars.rb` (loaded by Ruby scripts after dotfiles repo is cloned)
   
   This duplication is unavoidable because the bootstrap window runs before Ruby utilities exist. A Ruby-based fresh-install would have to *create* `env_vars.rb` during bootstrap, hardcoding paths into generated Ruby code — far more fragile than the current approach where shell variables are the source of truth and Ruby reads them via `ENV`.

3. **Xcode Command Line Tools dependency**: Git is not available on vanilla macOS — `/usr/bin/git` is just a stub that prompts for Xcode CLT installation. The current bootstrap uses `curl` to download a tarball (no git needed), then converts it to a proper git repo after Xcode CLT is installed. A Ruby bootstrap would have to replicate this entire dance, or force the user to install Xcode CLT manually before running anything.

4. **Shell integration**: The script sources `.shellrc` mid-execution to load utilities incrementally as they become available. Ruby scripts use `require_relative` which fails if the file doesn't exist yet — there's no equivalent to "source this if it exists, skip if not."

5. **Complexity explosion**: The current shell script is ~550 lines and handles all edge cases cleanly. A Ruby port would need:
   - Pre-flight checks for Ruby version (vanilla OS has 2.6, Homebrew installs 3.3+)
   - Fallback paths for every system command (some exist in `/usr/bin`, others only after Homebrew)
   - Manual `ENV` manipulation to replicate shell's automatic environment inheritance
   - Explicit process management for background jobs (brew bundle full install)
   
   The result would be longer, harder to debug, and more fragile than the shell version.

**Decision**: `fresh-install-of-osx.rb` stays as shell. The bootstrap path is inherently shell-native, and fighting that reality creates more problems than it solves.

### `osx-defaults.sh` — Copy-Paste Ergonomics

Converting `osx-defaults.sh` to Ruby would eliminate a key usability feature:

1. **Direct `defaults write` commands**: The current script is ~200 lines of bare `defaults write` commands with inline comments explaining what each one does. Users can copy-paste any line directly into their terminal to test it, tweak values, or apply a single setting without re-running the entire script.

2. **No abstraction layer**: Ruby would naturally introduce helper methods (`write_default(domain, key, value, type)`) for DRY. While cleaner, this makes individual commands non-portable — you can't copy a Ruby method call into a shell and have it work. The user would have to manually reconstruct the `defaults write` invocation from the method call.

3. **Transparency over elegance**: macOS `defaults` commands have complex syntax (`-dict`, `-dict-add`, `-array-add`, nested keys, type flags). The current script shows exactly what gets written, making it obvious what each line does. A Ruby abstraction would hide that detail behind method parameters, making it harder to understand what's actually being applied.

4. **Reference value**: The script doubles as a reference catalog of useful `defaults` commands. Users frequently grep it for "Dock" or "Finder" to find examples they can adapt. A Ruby implementation would obscure the actual commands behind abstractions.

**Decision**: `osx-defaults.sh` stays as shell. The ability to copy-paste individual commands is more valuable than the marginal maintainability gain from porting to Ruby.

### Implication for the Codebase

These two scripts anchor the shell ecosystem: `.shellrc` must remain because `fresh-install-of-osx.rb` sources it during bootstrap. Other scripts (`software-updates-cron.sh` evolved to Ruby, `setup-login-item.sh` evolved to Ruby) were converted because they don't have the same constraints. The decision to keep these two as shell is about respecting the constraints of the problem domain, not lack of effort or willingness to modernize.

---

Back to [README.md](README.md)
