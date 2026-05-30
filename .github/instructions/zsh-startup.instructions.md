---
applyTo: "**/files/--ZDOTDIR--/**,**/files/--XDG_CONFIG_HOME--/zsh/**"
---

# Zsh Startup Performance Instructions

Apply these rules when editing `.zshenv`, `.zshrc`, `.zlogin`, or any file
sourced during zsh startup.

Syntax choices follow the decision-making priority defined in
`copilot-instructions.md` (startup speed + maintainability first; POSIX and
zsh built-ins where they do not conflict with those). When a startup-path
optimisation uses zsh-specific syntax, add a comment explaining why.

## Startup File Load Order

```
.zshenv   → always, first (keep minimal — env vars only)
.zprofile → login shells (not used here)
.zshrc    → interactive shells (heavy lifting)
.zlogin   → after .zshrc, for post-init work (compilation, etc.)
```

## No Subshell Forks in Startup Code

Every `$(...)` command substitution in startup code forks a new process.
Avoid them in the hot path:

```zsh
# BAD — forks a subshell
ARCH=$(uname -m)

# Good — zsh built-in parameter expansion
ARCH="${MACHTYPE%%-*}"   # Note: returns 'arm' not 'arm64' on Apple Silicon
# TODO: verify MACHTYPE gives correct arch string on all targets

# BAD
CURRENT_USER=$(whoami)

# Good
CURRENT_USER="${USER}"
```

## Function Existence Check

```zsh
# BAD — forks a subshell
type is_shellrc_sourced > /dev/null 2>&1

# Good — zsh built-in, no fork
(( $+functions[is_shellrc_sourced] ))
```

## Homebrew Shellenv Caching

`brew shellenv` is slow. Cache its output and source from cache:

```zsh
# Cache file: ${XDG_CONFIG_HOME}/zsh/homebrew-shellenv-cache.zsh
if [[ ! -f "${_brew_cache}" || "${_brew_bin}" -nt "${_brew_cache}" ]]; then
  "${_brew_bin}" shellenv >| "${_brew_cache}"
fi
source "${_brew_cache}"
```

## `source` vs `load_file_if_exists`

`load_file_if_exists` is defined in `.shellrc`. It is only usable **after**
`.shellrc` has been sourced. In `.zshrc`, `.zlogin`, and other zsh startup
files (which always run after `.shellrc` is available), always prefer
`load_file_if_exists` for optional files:

```zsh
# Good — safe for files that may not exist yet (e.g., antidote bundle on first login)
load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"

# Use source only when the file is guaranteed to exist
source "${HOME}/.shellrc"
```

## Antidote Plugin Manager

Antidote replaces OMZ. Key rules:
- `ANTIDOTE_HOME` uses `~/Library/Caches/antidote` — macOS-specific, comment near definition.
- The generated bundle file must exist in the home git repo for vanilla OS installs.
- Source the bundle with `load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"` — it
  may not exist on first login (before antidote has been run).
- `ZSH` and `ZSH_CUSTOM` env vars from OMZ must be unset.
- Run `antidote bundle` in a clean subshell: `zsh --no-rcs -c "antidote bundle < ..."`.
  This prevents ANSI escape codes from the interactive shell leaking into `eval`.

## Path Variables

Export path arrays with `typeset +x` (not `export`):

```zsh
# BAD — exporting an array causes issues
export fpath=( ... )

# Good — mark as not exported
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

When `delete_caches` is run to remove `.zwc` files, do NOT chmod/chown them.
Just delete and let zsh regenerate on next startup.

## `is_shellrc_sourced` Sentinel

`.shellrc` defines `is_shellrc_sourced` as a sentinel. In `.zshrc` and other
zsh files, source `.shellrc` unconditionally — the sentinel prevents double-loading:

```zsh
# Good
source "${HOME}/.shellrc"

# BAD — guard is already inside .shellrc
[[ "$(type is_shellrc_sourced)" == *function* ]] || source "${HOME}/.shellrc"
```

## Plugin Option Variables

Plugin option variables (e.g. `ZSH_AUTOSUGGEST_STRATEGY`) **must be set before
the antidote bundle is sourced**. Plugins read these variables at load time; setting
them after `load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"` has no effect:

```zsh
# Good — set before bundle
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
unset ZSH ZSH_CUSTOM   # clear stale OMZ values before antidote loads OMZ libs
load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"

# BAD — too late, plugin already loaded
load_file_if_exists "${ZDOTDIR}/.zsh_plugins.zsh"
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)
```

## `compinit` Caching

`compinit` must be called with `-C` (skip `compaudit` security scan) when the
dump file already exists, and without `-C` on the first run. Store the dump in
`$XDG_CACHE_HOME` (not `~/.zcompdump`) to keep `$HOME` clean.
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
    compinit -C -d "${ZSH_COMPDUMP}"   # fast path — skip audit on subsequent starts
  else
    compinit -d "${ZSH_COMPDUMP}"      # first run — run audit to catch permission issues
  fi
}
```

The anonymous function `()` scopes the `autoload` so it does not pollute the
global function table.

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
