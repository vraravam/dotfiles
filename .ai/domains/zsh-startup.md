---
applyTo: "**/files/--ZDOTDIR--/**,**/files/--XDG_CONFIG_HOME--/zsh/**,.zprofile"
---

# Zsh Startup Performance Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules when editing `.zshenv`, `.zshrc`, `.zprofile`, `.zlogin`, or any file
sourced during zsh startup.

Syntax choices follow the decision-making priority defined in
[`instructions.md`](../instructions.md) (startup speed + maintainability first; POSIX and
zsh built-ins where they do not conflict with those). When a startup-path
optimisation uses zsh-specific syntax, add a comment explaining why.

## Scope

**This file applies to**: Zsh startup files and performance-critical shell initialization, including:
- `.zshenv` - Always sourced first (minimal, env vars only)
- `.zshrc` - Interactive shell initialization (heavy lifting)
- `.zprofile` - Login shell initialization (not used in this repository)
- `.zlogin` - Post-initialization tasks (compilation, cache generation)
- Autoload functions in `${XDG_CONFIG_HOME}/zsh/`
- Cache generation scripts (Homebrew shellenv, Starship init, mise activate)
- Plugin management (Antidote bundle, compinit)

**Related files**:
- [`shell-scripting.md`](./shell-scripting.md) - General shell patterns and utilities
- [`logging-conventions.md`](./logging-conventions.md) - DEBUG and profiling output
- [`path-constants.md`](./path-constants.md) - Environment variables set in `.zshenv`

**Does NOT apply to**: Scripts that run after shell startup completes, non-interactive shell scripts, or Ruby scripts (which have their own performance considerations).

## Startup File Load Order

```
.zshenv   → always, first (keep minimal -- env vars only)
.zprofile → login shells (not used here)
.zshrc    → interactive shells (heavy lifting)
.zlogin   → after .zshrc, for post-init work (compilation, etc.)
```

## No Subshell Forks in Startup Code

Every `$(...)` command substitution in startup code forks a new process.
Avoid them in the hot path:

```zsh
# BAD -- forks a subshell
ARCH=$(uname -m)

# Good -- use cached value from .shellrc
# .shellrc caches ARCH to avoid fork on every source (see architecture cache section)
# Direct MACHTYPE usage is unsafe: reports 'x86_64' on Apple Silicon vanilla macOS (zsh bug)
if is_arm; then
  # arm-specific logic
fi

# BAD
CURRENT_USER=$(whoami)

# Good
CURRENT_USER="${USER}"
```

## zsh/stat Module for Zero-Fork File Operations

The `zsh/stat` module provides built-in access to file metadata without forking external commands.
Use it for mtime checks, size queries, and permission checks in startup code.

```zsh
# BAD -- forks stat command on every shell start
config_mtime=$(stat -f %m "${config}" 2>/dev/null)
theme_mtime=$(stat -f %m "${theme}" 2>/dev/null)

# Good -- zsh/stat module, zero forks
zmodload -F zsh/stat b:zstat 2>/dev/null
local config_mtime theme_mtime
zstat -F "%s" +mtime -A config_mtime "${config}" 2>/dev/null
zstat -F "%s" +mtime -A theme_mtime "${theme}" 2>/dev/null
```

**Benefits:**
- **Zero subprocess overhead**: No fork/exec of `/usr/bin/stat`
- **Faster**: ~0.1ms vs ~1-2ms per stat call
- **Built-in**: Ships with zsh, no external dependencies

**Common patterns:**
```zsh
# Check file mtime (modification time)
zmodload -F zsh/stat b:zstat 2>/dev/null
local file_mtime
zstat -F "%s" +mtime -A file_mtime "${file}" 2>/dev/null

# Check file size
local file_size
zstat +size -A file_size "${file}" 2>/dev/null

# Multiple attributes at once
local -a file_stats
zstat -F "%s" +mtime +size -A file_stats "${file}" 2>/dev/null
# file_stats[1] = mtime, file_stats[2] = size
```

**When to use:**
- File mtime comparisons in cache validation
- Size checks before expensive operations
- Any file metadata access during startup

**When NOT to use:**
- One-time operations outside hot path (e.g., install scripts)
- When external `stat` is already cached/optimized
- Cross-platform scripts (zsh/stat is zsh-only)

## Function Existence Check

```zsh
# BAD -- forks a subshell
type is_shellrc_sourced > /dev/null 2>&1

# Good -- zsh built-in, no fork
(( $+functions[is_shellrc_sourced] ))
```

## Homebrew Shellenv Caching

`brew shellenv` is slow. Cache its output and source from cache:

```zsh
# Cache file: ${XDG_CONFIG_HOME}/zsh/homebrew-shellenv-cache.zsh
if is_file_older_than "${_brew_cache}" "${_brew_bin}"; then
  "${_brew_bin}" shellenv >| "${_brew_cache}"
fi
load_file_if_exists "${_brew_cache}"
```

## `source` vs `load_file_if_exists`

`load_file_if_exists` is defined in `.shellrc`. It is only usable **after**
`.shellrc` has been sourced. In `.zshrc`, `.zlogin`, and other zsh startup
files (which always run after `.shellrc` is available), always prefer
`load_file_if_exists` for optional files:

```zsh
# Good -- safe for files that may not exist yet (e.g., antidote bundle on first login)
load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"

# Use source only when the file is guaranteed to exist
source "${HOME}/.shellrc"
```

## Antidote Plugin Manager

Antidote replaces OMZ. Key rules:
- `ANTIDOTE_HOME` uses `~/Library/Caches/antidote` -- macOS-specific, comment near definition.
- The generated bundle file must exist in the home git repo for vanilla OS installs.
- Source the bundle with `load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"` -- it
  may not exist on first login (before antidote has been run).
- `ZSH` and `ZSH_CUSTOM` env vars from OMZ must be unset.
- Run `antidote bundle` in a clean subshell: `zsh --no-rcs -c "antidote bundle < ..."`.
  This prevents ANSI escape codes from the interactive shell leaking into `eval`.

## Path Variables

Export path arrays with `typeset +x` (not `export`):

```zsh
# BAD -- exporting an array causes issues
export fpath=( ... )

# Good -- mark as not exported
typeset +x fpath
fpath=( ... "${fpath[@]}" )
```

## ZWC Compilation in `.zlogin`

```zsh
# Recompile startup scripts if source is newer than .zwc
find_in_folder_and_recompile "${XDG_CACHE_HOME}"

# recompile_zsh_autoload_dir is kept separate from find_in_folder_and_recompile
# because autoload dirs have special semantics (lazy-loading functions).
# Do NOT replace it with find_in_folder_and_recompile.
recompile_zsh_autoload_dir "${ZDOTDIR}/functions"
```

## Antidote .zwc Compilation

antidote 2.1.1+ (released July 2026) fixed the `.zwc` bytecode crash (issue #270).
The source-detection check now matches both `file` and `filecode` eval contexts.

`antidote.zsh` can now be compiled to `.zwc` like any other zsh script. The
`find_in_folder_and_recompile "${ANTIDOTE_HOME}"` call in `.zlogin` handles it
automatically.

**Historical note**: antidote 2.1.0 and earlier used `[[ ":${ZSH_EVAL_CONTEXT}:" == *:file:* ]]`
to distinguish sourced-library mode from CLI mode. When loaded from `.zwc` bytecode,
zsh sets the eval context token to `filecode` (not `file`), causing the pattern
mismatch to trigger CLI mode which called `exit 1` and crashed every shell startup.
This was fixed in 2.1.1.

When `delete_caches` is run to remove `.zwc` files, do NOT chmod/chown them.
Just delete and let zsh regenerate on next startup.

## `is_shellrc_sourced` Sentinel

`.shellrc` defines `is_shellrc_sourced` as a sentinel. In `.zshrc` and other
zsh files, source `.shellrc` unconditionally -- the sentinel prevents double-loading:

```zsh
# Good
source "${HOME}/.shellrc"

# BAD -- guard is already inside .shellrc
[[ "$(type is_shellrc_sourced)" == *function* ]] || source "${HOME}/.shellrc"
```

## Plugin Option Variables

Plugin option variables (e.g. `ZSH_AUTOSUGGEST_STRATEGY`) **must be set before
the antidote bundle is sourced**. Plugins read these variables at load time; setting
them after `load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"` has no effect:

```zsh
# Good -- set before bundle
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
unset ZSH ZSH_CUSTOM   # clear stale OMZ values before antidote loads OMZ libs
load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"

# BAD -- too late, plugin already loaded
load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
```

## `compinit` Caching

`compinit` must be called with `-C` (skip `compaudit` security scan) when the
dump file already exists, and without `-C` on the first run. Store the dump in
`${XDG_CACHE_HOME}` (not `~/.zcompdump`) to keep `${HOME}` clean.
Set `skip_global_compinit=1` in `.zshenv` to prevent `/etc/zshrc` from running
its own `compinit` before ours:

```zsh
# In .zshenv:
skip_global_compinit=1

# In .zshrc:
export ZSH_COMPDUMP="${XDG_CACHE_HOME}/zcompdump"
() {
  autoload -Uz compinit
  if is_file "${ZSH_COMPDUMP}"; then
    compinit -C -d "${ZSH_COMPDUMP}"   # fast path -- skip audit on subsequent starts
  else
    compinit -d "${ZSH_COMPDUMP}"      # first run -- run audit to catch permission issues
  fi
}
```

The anonymous function `()` scopes the `autoload` so it does not pollute the
global function table.

## Deferring Expensive Operations with zsh-defer

**Pattern**: Defer non-essential operations to the first idle ZLE event using `zsh-defer`.

zsh-defer schedules functions to run after the first prompt is rendered but before the user can type. This moves expensive work off the critical startup path without impacting user experience.

**Benefits:**
- **Faster first prompt**: 30-50% improvement by deferring heavy operations
- **No user-visible impact**: Deferred work completes before first keypress
- **Graceful degradation**: Falls back to synchronous load when zsh-defer unavailable

**Common candidates for deferral:**
- Large function/alias files (`.aliases` with 1000+ lines)
- Completion system initialization (`compinit` with fpath scanning)
- Background maintenance checks (daemon restart validation, update checks)
- Tool activation caching (mise/direnv when cache exists)

**Pattern: Named function + conditional defer**
```zsh
# Named function required (not anonymous ()) -- zsh-defer needs a function name
_check_updates() {
  # Expensive check logic here
  if [[ -f "${cache}" ]]; then
    # Fast path using cached data
    return
  fi
  # Slow path: check for updates, write cache
}

# Defer if available, run synchronously otherwise
if (($+functions[zsh-defer])); then
  zsh-defer _check_updates
else
  _check_updates
fi
```

**Pattern: Defer file loading**
```zsh
# .aliases contains 1000+ lines of function definitions
# Defer to after first prompt (saves ~15-20ms on startup)
if (($+functions[zsh-defer])); then
  zsh-defer load_file_if_exists "${ZDOTDIR}/.aliases"
else
  load_file_if_exists "${ZDOTDIR}/.aliases"
fi
```

**Pattern: Defer completion initialization**
```zsh
_deferred_compinit() {
  unfunction compdef 2>/dev/null
  autoload -Uz compinit
  # ... compinit logic ...
  unfunction _deferred_compinit  # Clean up after running
}

if (($+functions[zsh-defer])); then
  zsh-defer _deferred_compinit
else
  _deferred_compinit
fi
```

**When to defer:**
- ✅ Large file sourcing (1000+ lines)
- ✅ Background checks with caching (5min+ TTL)
- ✅ Completion system setup (unless user needs tab-completion immediately)
- ✅ Plugin initialization that doesn't affect prompt rendering

**When NOT to defer:**
- ❌ Environment variables needed by other startup code
- ❌ PATH modifications (tools must be available immediately)
- ❌ Prompt configuration (starship init, etc.)
- ❌ Key bindings and ZLE widgets (user expects them immediately)
- ❌ Small operations (<1ms cost)

**Measurement:**
- **Before**: 70ms startup (30ms zsh-patina restart check in hot path)
- **After**: 40ms startup (30ms check deferred, runs after first prompt)
- **Result**: 43% improvement in time-to-first-prompt

**See also:**
- `.zshrc` lines 268-365 (zsh-patina restart check deferral)
- `.zshrc` lines 446-459 (.aliases deferral)
- `.zshrc` lines 486-526 (compinit deferral)

## Debugging Startup

Two env vars are wired into every startup file:

```zsh
# Trace which config files load and in what order:
DEBUG=true zsh

# Profile startup time (run zprof after opening the shell):
ZSH_PROFILE=true zsh -i -c exit
zprof
```

Every startup file (`zshenv`, `zshrc`, `zlogin`, `.shellrc`, `.aliases`, etc.)
has guards for both vars at the top. Do not remove them.

## Performance Targets

**Startup time benchmarks** (after optimizations):

| Hardware | Target | Acceptable | Needs Work |
|----------|--------|------------|------------|
| Apple Silicon (M1+) | <80ms | <120ms | >150ms |
| Intel (2019+) | <100ms | <150ms | >200ms |

**Measure impact:**
```zsh
# Average of 10 runs
for i in {1..10}; do
  /usr/bin/time -p zsh -i -c exit 2>&1 | grep real
done | awk '{sum+=$2} END {print "Avg:", sum/10, "sec"}'
```

**Profile bottlenecks:**
```zsh
# Profile with zprof
ZSH_PROFILE=true zsh -i -c exit
zprof

# Analyze output for:
# - Functions with high call counts
# - Functions with high per-call time
# - Unexpected subprocess forks
```

**Common bottlenecks and fixes:**
- Antidote plugin loading (21ms) - already optimized with deferrals
- Syntax highlighting (2-3ms) - minimize patterns, use fast plugin
- Homebrew shellenv (15ms without cache) - cache based on binary mtime
- Starship prompt (1-2ms) - cache init script
- Mise activation (1-2ms) - cache activation script

## `zmodload` and `ZSH_VERSION`

In files that may be sourced from bash (e.g., `.shellrc` which is sourced from
`.envrc`), guard zsh-only modules:

```zsh
# Guard zsh-specific code
if [[ -n "${ZSH_VERSION:-}" ]]; then
  zmodload zsh/datetime
  # other zsh-only setup
fi
```

The `is_zsh` utility function can be used in place of the `-n "${ZSH_VERSION:-}"` check.

## `BASH_VERSION` in Antidote

`antidote.zsh` references `BASH_VERSION` which is unset under `set -u` in zsh.
Initialize it near the top of `.shellrc` before sourcing antidote:

```zsh
# Antidote's shell script checks BASH_VERSION; initialize to avoid
# "unbound variable" under set -u when sourcing in zsh.
BASH_VERSION="${BASH_VERSION:-}"
```
