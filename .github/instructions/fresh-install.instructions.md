---
applyTo: "**/fresh-install-of-osx.sh,**/install-dotfiles.rb,**/post-brew-install.sh"
---

# Fresh Install Instructions

These rules apply specifically to the bootstrap and installation scripts.

## `fresh-install-of-osx.sh` — Idempotency Contract

This script runs in **two modes**:
1. **Vanilla OS** (`FIRST_INSTALL=1`): a fresh macOS with nothing installed.
2. **Pre-configured machine**: an already-set-up machine running updates.

Every function and code path MUST work correctly in both modes.

### Section-Level Idempotency and Guards

Every section in `fresh-install-of-osx.sh` must be individually idempotent and
must have an appropriate guard that **pre-empts the entire section** when its
work is already done. This serves two purposes:

1. **Correctness** — re-running on a pre-configured machine must not cause
   errors or undo existing state.
2. **Speed** — on a pre-configured machine, sections that have nothing to do
   should be skipped immediately without executing any of the section's logic.

The guard should be the **first thing** inside the section, before any logging
or setup work. Typical guard patterns:

```zsh
# Skip if tool already installed
if is_executable "brew"; then
  info "Homebrew already installed — skipping."
else
  # ... install homebrew ...
fi

# Skip if dotfiles repo already cloned (is_git_repo checks both
# non-empty string AND presence of .git directory — the else branch
# is NOT a simple negation of "directory exists").
if is_git_repo "${DOTFILES_DIR}"; then
  info "Dotfiles already cloned — skipping."
else
  # ... clone dotfiles ...
fi

# Skip if already configured (check sentinel file / flag)
if is_file "${HOME}/.gitconfig"; then
  info "Git config already present — skipping."
else
  # ... configure git ...
fi
```

The log message for a skipped section must clearly state what was skipped and
why, so the output of a pre-configured run remains readable and auditable.

## `curl` Switches for Vanilla OS Downloads

All `curl` calls in `fresh-install` run before `~/.curlrc` is symlinked by
`install-dotfiles.rb`, so the `.curlrc` defaults are not in effect. Rather than
repeating the full flag set on every call site, a local array `_curl_opts` is
defined once near the top of `main` and expanded into each `curl` invocation:

```zsh
local -a _curl_opts
if [[ ! -f "${HOME}/.curlrc" ]]; then
  _curl_opts=(--retry 5 --retry-delay 10 --retry-max-time 120 \
              --max-time 150 --connect-timeout 30 --retry-connrefused)
fi

# Usage at each call site:
curl "${_curl_opts[@]}" -fsSL <url>
```

`local -a` initialises the variable as an empty array (not unset), so
`"${_curl_opts[@]}"` expands to nothing without triggering a
`parameter not set` error under `set -u` when `~/.curlrc` is already present.

The guard uses the raw `[[ -f ... ]]` test rather than `is_file` because
`_curl_opts` is initialised before `_download_and_source_shellrc` is called —
`.shellrc` (which defines `is_file`) has not been sourced yet at that point.

The array is empty when `~/.curlrc` already exists (pre-configured machine),
so the flags are only injected when they are genuinely needed. The constant
`-fsSL` flags remain inline at each call site since they are always required
regardless of `.curlrc` presence.

| Flag | Value | Reason |
|------|-------|--------|
| `--retry` | 5 | More attempts for slow/flaky connections |
| `--retry-delay` | 10s | Longer back-off between attempts |
| `--retry-max-time` | 120s | Cap total retry window; prevents infinite loops |
| `--max-time` | 150s | Total transfer time limit; prevents silent hangs on a stalled connection |
| `--connect-timeout` | 30s | Fail fast if the host is unreachable |
| `--retry-connrefused` | — | Retry on connection refused, not just transient errors |
| `-f` | — | Fail on HTTP errors (prevents piping garbage to zsh) |
| `-s` | — | Silent — output is piped to zsh; a progress meter would interleave with script output and corrupt it |
| `-S` | — | Show errors even under `-s` |
| `-L` | — | Follow redirects (required for raw.githubusercontent.com) |

Do NOT add `--retry-all-errors` — it causes the terminal app to close
unexpectedly (known issue, tracked in `.curlrc` comments).

The bootstrap command in `GettingStarted.md` is a one-liner run manually by
the user before `fresh-install` exists locally, so it must carry the full flags
inline — it cannot use `_curl_opts`.



On a vanilla OS, the order of availability is:
1. `/bin/zsh` only — no Homebrew, no dotfiles, no `.shellrc`
2. `.shellrc` downloaded via `curl` and sourced
3. Homebrew installed
4. dotfiles repo cloned → `.shellrc`/`.aliases` symlinked
5. `install-dotfiles.rb` creates symlinks
6. `brew bundle install` installs tools
7. `post-brew-install.sh` runs (antidote, mise versions, etc.)

Functions needed **before step 4** must live in `.shellrc`, not `.aliases`.
`.shellrc` is curl-downloaded and must stay lean — only put functions in it
that are genuinely required before the dotfiles repo is cloned. See the
`.shellrc` vs `.aliases` split section in `copilot-instructions.md` for the
full rationale and decision rule.

Functions needed **before step 3** (Homebrew install) cannot use brew-installed tools.

## `download_and_source_shellrc`

Logic:
1. On `FIRST_INSTALL`: always force download + re-source.
2. On pre-configured machine: skip downloading; source directly (the in-built
   guard will no-op if already sourced).

After the `curl` download, print an `info` log on success. After sourcing,
print a `success` message. If `info` is not yet defined (pre-source), use `echo`.

Add comment about retry behavior in error scenarios.

## `install_homebrew`

The logic for installing brew for first-time vs updating must not be duplicated.
Extract into a single conditional.

## Antidote in Fresh Install

`update_antidote_and_regenerate_plugin_bundle` is called from `post-brew-install.sh`.
It does NOT need to be called separately in `fresh-install` for either mode —
`post-brew-install` handles both cases.

When sourcing `antidote.zsh` inside fresh-install, use `load_file_if_exists` since
antidote may not be installed yet on a vanilla OS.

## `set -euo pipefail` and Third-Party Tools

Third-party scripts (e.g., `antidote.zsh`) may reference unset variables
(`BASH_VERSION`, etc.). Before sourcing such scripts, temporarily disable
`set -u`:

```zsh
set +u
source "/opt/homebrew/opt/antidote/share/antidote/antidote.zsh"
set -u
```

Re-enable after the sourcing. Add comment explaining why:
`# antidote.zsh references BASH_VERSION which is unset in zsh under set -u`

## `GIT_SSH_COMMAND`

See `copilot-instructions.md` — Keybase / SSH section for full rationale.
Key rule: set at top of `main` when `FIRST_INSTALL` is true; unset immediately
after `install-dotfiles.rb` runs (which symlinks `~/.gitconfig` into place).

## Crontab During Fresh Install

Fresh install uses `suspend_cron` / `resume_cron` to avoid cron conflicts.
These functions are in `.shellrc` (not `.aliases`) so they are available before
the dotfiles repo is cloned.

The error trap must call `resume_cron` if `_DOTFILES_CRON_BACKUP_FILE` exists.

## Keybase Functions

See `copilot-instructions.md` — Keybase / SSH section. Summary: both functions
live in `.aliases`, not `.shellrc`. Do not move them to `.shellrc`.

## `install_mise_versions` Duration

The start time passed to `print_script_summary` must use epoch seconds
(`$EPOCHSECONDS` or `date +%s`) — not a formatted wall-clock string.
`print_script_summary` subtracts the start epoch from `$EPOCHSECONDS` at
call time to compute the duration; a pre-formatted string breaks that arithmetic.

## Brewfile Truncation on `FIRST_INSTALL`

On a vanilla OS run (`FIRST_INSTALL=1`), `brew bundle` is run only against the
**base section** of the Brewfile — lines up to (but not including) the first
line containing a `FIRST_INSTALL` guard. This keeps the initial install fast by
skipping optional heavy packages.

The Brewfile must have a sentinel comment line that contains the text
`FIRST_INSTALL` to mark the end of the base section. The script truncates at
that line using `sed`:

```zsh
brewfile_content="$(sed "/^[^#].*FIRST_INSTALL/q" "${HOMEBREW_BUNDLE_FILE}")"
brewfile_content="${brewfile_content%$'\n'*FIRST_INSTALL*}"  # strip the guard line itself
```

On a pre-configured machine (no `FIRST_INSTALL`), the full Brewfile is used.
Do not remove or rename the `FIRST_INSTALL` guard line in the Brewfile — it is
load-bearing for the vanilla OS install path.
