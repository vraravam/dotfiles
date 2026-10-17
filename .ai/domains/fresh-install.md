---
applyTo: "**/fresh-install-of-osx.sh,**/install-dotfiles.rb,**/osx-defaults.sh,**/setup-login-item.rb,**/capture-prefs.rb,**/resurrect-repositories.rb"
name: dotfiles-fresh-install
description: Use when editing scripts/fresh-install-of-osx.sh, scripts/install-dotfiles.rb, scripts/osx-defaults.sh, scripts/setup-login-item.rb, scripts/capture-prefs.rb, or scripts/resurrect-repositories.rb. Covers bootstrap idempotency for vanilla-OS vs pre-configured-machine modes, curl retry flags, crontab suspend/resume, and Brewfile truncation on FIRST_INSTALL.
---

# Fresh Install Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

These rules apply specifically to the bootstrap and installation scripts, as well as
scripts invoked during initial setup or backup/restore operations.

## Scope

**This file applies to**: Bootstrap, installation, and system setup scripts, including:
- `scripts/fresh-install-of-osx.sh` - Main bootstrap script (vanilla OS and pre-configured modes)
- `scripts/install-dotfiles.rb` - Symlink/copy manager for `files/` directory
- `scripts/osx-defaults.sh` - macOS system preferences
- `scripts/setup-login-item.rb` - Login item configuration
- `scripts/capture-prefs.rb` - Preferences export/import (run in-process by `PreferencesRestore`)
- `scripts/resurrect-repositories.rb` - Repository restoration from tracked state

**Related files**:
- [`shell-scripting.md`](./shell-scripting.md) - Shell patterns (curl flags, idempotency guards, error handling)
- [`ruby-scripting.md`](./ruby-scripting.md) - Ruby patterns (dual-mode scripts, error handling)
- [`custom-gitignore-maintenance.md`](./custom-gitignore-maintenance.md) - `install-dotfiles.rb` behavior details
- [`path-constants.md`](./path-constants.md) - Environment variables and path construction

**Does NOT apply to**: Regular maintenance scripts (software updates, cron jobs), user-initiated workflows (git operations, profile management), or scripts not involved in initial system setup.

## `fresh-install-of-osx.sh` -- Idempotency Contract

This script runs in **two modes**:
1. **Vanilla OS** (`FIRST_INSTALL=1`): a fresh macOS with nothing installed.
2. **Pre-configured machine**: an already-set-up machine running updates.

Every function and code path MUST work correctly in both modes.

### Section-Level Idempotency and Guards

Every section in `fresh-install-of-osx.sh` must be individually idempotent and
must have an appropriate guard that **pre-empts the entire section** when its
work is already done. This serves two purposes:

1. **Correctness** -- re-running on a pre-configured machine must not cause
   errors or undo existing state.
2. **Speed** -- on a pre-configured machine, sections that have nothing to do
   should be skipped immediately without executing any of the section's logic.

The guard should be the **first thing** inside the section, before any logging
or setup work. Typical guard patterns:

```zsh
# Skip if tool already installed
if is_executable "brew"; then
  info "Homebrew already installed -- skipping."
else
  # ... install homebrew ...
fi

# Skip if dotfiles repo already cloned (is_git_repo checks both
# non-empty string AND presence of .git directory -- the else branch
# is NOT a simple negation of "directory exists").
if is_git_repo "${DOTFILES_DIR}"; then
  info "Dotfiles already cloned -- skipping."
else
  # ... clone dotfiles ...
fi

# Skip if already configured (check sentinel file / flag)
if is_file "${XDG_CONFIG_HOME}/git/config"; then
  info "Git config already present -- skipping."
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
`_curl_opts` is initialised before `_download_and_source_shellrc` is called --
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
| `--retry-connrefused` | -- | Retry on connection refused, not just transient errors |
| `-f` | -- | Fail on HTTP errors (prevents piping garbage to zsh) |
| `-s` | -- | Silent -- output is piped to zsh; a progress meter would interleave with script output and corrupt it |
| `-S` | -- | Show errors even under `-s` |
| `-L` | -- | Follow redirects (required for raw.githubusercontent.com) |

Do NOT add `--retry-all-errors` -- it causes the terminal app to close
unexpectedly (known issue, tracked in `.curlrc` comments).

The bootstrap command in `Adoption.md § Phase 3.2` is a one-liner run manually by
the user before `fresh-install` exists locally, so it must carry the full flags
inline -- it cannot use `_curl_opts`.



On a vanilla OS, the order of availability is:
1. `/bin/zsh` only -- no Homebrew, no dotfiles, no `.shellrc`
2. `.shellrc` downloaded via `curl` and sourced
3. Homebrew installed
4. dotfiles repo cloned → `.shellrc`/`.aliases` symlinked
5. `install-dotfiles.rb` creates symlinks
6. `brew bundle install` installs tools (each formula/cask handles its own post-install
   needs via Brewfile `postinstall:` hooks -- e.g. antidote's hook regenerates the plugin
   bundle; see "Antidote in Fresh Install" below)

Functions needed **before step 4** must live in `.shellrc`, not `.aliases`.
`.shellrc` is curl-downloaded and must stay lean -- only put functions in it
that are genuinely required before the dotfiles repo is cloned. See the
[`AGENTS.md`](../../AGENTS.md) § **Common Agent Mistakes** #6 for the
decision rule.

Functions needed **before step 3** (Homebrew install) cannot use brew-installed tools.

## `download_and_source_shellrc`

Logic:
1. On `FIRST_INSTALL`: always force download + re-source.
2. On pre-configured machine: skip downloading; source directly (the in-built
   guard will no-op if already sourced).

After the `curl` download, print an `info` log on success. After sourcing,
print a `success` message. If `info` is not yet defined (pre-source), use `echo`.

Add comment about retry behavior in error scenarios.

## `load_file_if_exists` / `recompile_zsh_script` Safety Before Homebrew Is Installed

`load_file_if_exists` calls `recompile_zsh_script` on its target file before
sourcing it (see `shell-portability-cron.md` § `source` vs `load_file_if_exists`).
This is safe to call anywhere in `fresh-install-of-osx.sh`, including points
where Homebrew has not been installed yet (e.g. the `load_zsh_configs` call that
`FreshInstallPostClone` makes right after install-dotfiles but before it installs
Homebrew):

- `recompile_zsh_script` only uses `autoload`/`zrecompile`, both zsh shell
  builtins with no dependency on Homebrew or any installed binary.
- `recompile_zsh_script` and `load_file_if_exists` always exit `0` regardless
  of whether recompilation happened (the `if` construct and the `|| true` /
  `|| warn` patterns guarantee this), so neither can trigger the script's
  `set -euo pipefail` + ERR trap.
- Verified empirically: sourcing a file via `load_file_if_exists` with its
  `.zwc` completely absent (the true vanilla-OS first-run state, before
  anything has ever been compiled) under `set -euo pipefail` with an active
  ERR trap does not fire the trap, and correctly writes a fresh `.zwc` from
  scratch.
- The very first `.shellrc` sourcing in `_download_and_source_shellrc` uses a
  plain `source "${HOME}/.shellrc"`, not `load_file_if_exists` -- it is
  unaffected by any of this regardless.

## `install_homebrew`

The logic for installing brew for first-time vs updating must not be duplicated.
Extract into a single conditional.

On a vanilla OS the shell starts the Homebrew installer **early and in the background**
(`_start_early_brew_install`, right after the Xcode Command Line Tools step and after the sudo
keep-alive is running): it needs only the CLT, sudo and the network, not the dotfiles repo. The
whole download (with the usual retry/cache-bust flags) and `NONINTERACTIVE=1 /bin/bash install.sh`
run in one disowned subshell with stdin from `/dev/null` and output to
`${TMPDIR:-/tmp}/dotfiles_brew_install.log`; its pid goes to `.../dotfiles_brew_install.pid`, and the
script exports `_DOTFILES_BREW_INSTALL_PID` and `_DOTFILES_BREW_INSTALL_LOG`. The subshell clears the
script's ERR/EXIT traps first, so it can never run the script's cleanup on its behalf. A re-run adopts
a still-running installer instead of starting a second one. If the script itself fails or is
interrupted, the installer is **deliberately left running** (killing it half-way leaves a broken
Homebrew); the EXIT trap prints a note with the pid and log. Opt out with `FRESH_INSTALL_NO_EARLY_BREW=1`.

`HomebrewInstall` (Ruby) is the other half: when brew is absent it waits for that pid (polling, a
log-tail line every 30s, bounded to 15 minutes, SIGTERM on timeout) **before** looking for
`bin/brew` (the file can exist while the installer is still running), verifies brew exists, and falls
back to downloading and running the installer itself when the early one is gone, failed or timed out.
Its own installer run is capped at 30 minutes overall and 10 minutes without output.

## Antidote in Fresh Install

`Antidote.update_and_regenerate_bundle` is invoked two ways, neither of which is
`fresh-install-of-osx.sh` itself:
- The `antidote` formula's `postinstall:` hook in the Brewfile (via the
  `update_antidote_and_regenerate_plugin_bundle` shell wrapper in `.aliases`) --
  fires whenever `brew bundle install` installs or upgrades antidote, which
  covers both a vanilla-OS first install and a pre-configured machine's re-run.
- `software-updates-cron.rb`'s periodic schedule, for day-to-day plugin updates
  outside of a fresh install.

It does NOT need to be called separately in `fresh-install-of-osx.sh` -- the
Brewfile hook already covers both first-install and pre-configured-machine modes.

When sourcing `antidote.zsh` inside fresh-install, use `load_file_if_exists` since
antidote may not be installed yet on a vanilla OS.

## `set -euo pipefail` and Third-Party Tools

Third-party scripts (e.g., `antidote.zsh`) may reference unset variables
(`BASH_VERSION`, etc.). Before sourcing such scripts, temporarily disable
`set -u`:

```zsh
set +u
source "${HOMEBREW_PREFIX}/opt/antidote/share/antidote/antidote.zsh"
set -u
```

Re-enable after the sourcing. Add comment explaining why:
`# antidote.zsh references BASH_VERSION which is unset in zsh under set -u`

## `GIT_SSH_COMMAND`

Key rule: set at top of `main` when `FIRST_INSTALL` is true; unset immediately
after `install-dotfiles.rb` runs (which symlinks `${XDG_CONFIG_HOME}/git/config` into place).

It also turns on connection multiplexing (`ControlMaster=auto`, `ControlPersist=120`,
`ControlPath=/tmp/.dotfiles-ssh-cm-<uid>/%C`) because every git operation otherwise pays a ~2s ssh
handshake and each fresh repo does 3-5 of them. The control directory is created mode 700 and its
owner is checked (multiplexing is left off if that fails). `/tmp` rather than `$TMPDIR` because the
macOS `$TMPDIR` can push the socket path past the 104-byte limit, and not `~/.ssh` because that is
tracked by the home repo. The bootstrap's `Compression=no` overrides `Compression yes` from
`global_config`. After the first install the same effect comes from the `ControlMaster` block in
`files/--HOME--/.ssh/global_config` (see `ssh-config.md` for the `Match all` requirement).

## First Dotfiles Clone: Stall Protection

`git-with-retry` is not on `PATH` before the dotfiles repo exists, so the plain-clone fallback of
`clone_repo_into` (used for the very first clone) retries itself: 3 attempts with
`-c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30` (a stalled transfer aborts instead of hanging),
the temp folder wiped between attempts and a 5s pause. The success path is unchanged.

Every non-keybase clone (this inline fallback and the `git-with-retry` path) honors the optional
`GIT_CLONE_INACTIVITY_SECS` (default 25) and `GIT_CLONE_ATTEMPTS` (default 5; 3 inline), applied by
`_git_clone_guard`. They are transport-agnostic on purpose: https and ssh keep their native stall
settings (`http.lowSpeedLimit`, `ServerAlive*`). A bad value is warned about and ignored.

The human-facing catalog of every environment variable is `Extras.md` § Environment variables; when
adding or changing one, update that table, not a second list here.

## `keybase://` Clones

`clone_repo_into` guards a `keybase://` clone like any other transport: `git with-retry` with
**inactivity tracking on the clone folder**, not a fixed wall clock. Measured with keybase 6.6.3 on a
real repository, `.git/objects` grows steadily while `git-remote-keybase` transfers (137MB at 4s,
1.04GB at 20s), so a slow but steady clone is not killed on every attempt the way the old fixed 60s
limit did. The allowance is `KEYBASE_CLONE_INACTIVITY_SECS` (default 120s; 600s with 2 attempts on a
`FIRST_INSTALL`, where KBFS is still syncing team/device keys and a first clone can sit without visible
progress for minutes). A first install used to run completely unguarded (a hang blocked it forever); it
is still unguarded only while `git-with-retry` is not on `PATH` yet, or with `KEYBASE_CLONE_UNWRAPPED=1`
(the old single attempt). `_keybase_clone_guard` picks these values.

Before cloning there are two best-effort checks, neither fatal: the containing KBFS folder listing
(`keybase fs ls /keybase/private/<user>`, ~1s -- a KBFS path that `keybase fs` resolves itself, not a file
on disk, so it works although KBFS is mounted elsewhere) and `_wait_for_keybase_git_backend`, a
`git ls-remote` through the helper (~2.5s), retried every 5s up to `KEYBASE_READY_ATTEMPTS` (default 12)
times. The second is the one that matters: the failure seen on a fresh device is
`git-remote-keybase error: (1) Server: block does not exist` while the daemon is logged in and the folder
already lists. `keybase://` URLs never involve ssh, so none of the ssh config (multiplexing, host keys,
compression) applies to them.

## Command Line Tools

`_install_xcode_command_line_tools` does not run `softwareupdate --list` (5s) when `xcode-select -p`
already succeeds. When the tools are missing it creates the `.in-progress` marker file first (the CLT
only show up in `--list` while it exists), runs `--list` through `_run_with_timeout` (vanilla macOS has
no `timeout`/`gtimeout`: background + poll + kill, bounded to 120s), parses the "Command Line Tools"
label (`_parse_clt_label`) and installs only that: `sudo softwareupdate -i "<label>"`. If no label is
found, the list times out or the install fails it falls back to the old `softwareupdate -ia --force`
(every recommended update) with a warning. Both step headers are always printed so the
`[Step N of 14]` numbering matches the Ruby total.

## Crontab During Fresh Install

Fresh install uses `suspend_cron` / `resume_cron` to avoid cron conflicts.
These functions are in `.shellrc` (not `.aliases`) so they are available before
the dotfiles repo is cloned.

The error trap must call `resume_cron` if `_DOTFILES_CRON_BACKUP_FILE` exists.

The script backs up the live crontab (`crontab -l`) and then clears it (`crontab -r`). The backup is
**never overwritten with an empty one**: a run that crashed after `crontab -r` would otherwise lose
the only copy on the next start (a message says when an older backup is kept; a non-empty live
crontab still replaces it). The EXIT trap restores a leftover non-empty backup when cron is empty,
then removes the file, so even a bare `exit 1` does not lose the schedule.

The hourly schedule is installed by the Ruby `Setup cron jobs` step, which runs **after the tracked
repositories are resurrected** (not before): an hourly `software-updates-cron` firing during the long
clone phase, or while the background Brewfile install is still running, would fight them for the
network and for Homebrew. If the full Brewfile install is still running when cron is installed, the
run logs a note that the first hourly run may overlap it.

### `recron` Fallback Logic

`recron` (called during fresh-install to set up cron jobs) uses a fallback strategy
to preserve existing schedules while supporting vanilla OS installs:

1. **Capture existing crontab**: Run `crontab -l` (by now the shell has already run `crontab -r`,
   so on a fresh-install run this is empty)
2. **Fallback to tracked file**: If no existing crontab, use `${PERSONAL_CONFIGS_DIR}/crontab.txt`
   (ignored when empty)
3. **Fallback to the shell's backup**: If that is missing or empty too, use the content of
   `_DOTFILES_CRON_BACKUP_FILE`, i.e. the user's original schedule
4. **User action if all are empty**: Print user_action instructing user to create `crontab.txt`
5. **Load non-empty schedule**: Install whichever source is non-empty, then `Cron.retire_backup`:
   the backup is removed only after the install succeeded, and only if it matches what was
   installed; a differing original is renamed `<name>.replaced`, so `resume_cron` can never put the
   old schedule back over the new one

**Rationale:**
- Preserves user's custom cron jobs (don't overwrite with defaults)
- Supports vanilla OS via tracked `crontab.txt` in home repo
- Doesn't impose default schedule if user has neither

**Error handling:** `restore_cron` (called by `recron`) logs errors via `Logging.record_error`
and returns false instead of raising. This prevents crontab installation failures from
aborting the entire fresh-install process. The error is recorded in the summary but
execution continues.

**Manual template generation:**
If you need a starting template, run:
```zsh
create_crontab ${PERSONAL_CONFIGS_DIR}/crontab.txt
```

This creates the default schedule (software-updates-cron hourly). Edit as needed,
commit to home repo, and run `recron` to install.

## Keybase Functions

Summary: both functions
live in `.aliases`, not `.shellrc`. Do not move them to `.shellrc`.

## `install_mise_versions` Duration

The start time passed to `print_script_summary` must use epoch seconds
(`${EPOCHSECONDS}` or `date +%s`) -- not a formatted wall-clock string.
`print_script_summary` subtracts the start epoch from `${EPOCHSECONDS}` at
call time to compute the duration; a pre-formatted string breaks that arithmetic.

## Brewfile Truncation on `FIRST_INSTALL`

The Brewfile install lives in Ruby (`BrewBundle` in `scripts/utilities/brew_bundle.rb`, built on the
pure command wrappers in `Brew`; the base section, the retry and the background install live in `BrewBundle`, while `bupc` and cron use the argument-less `Brew.sync_bundle`). `FreshInstallPostClone` calls it once the dotfiles repository is
cloned and install-dotfiles has linked `~/Brewfile`:

```ruby
BrewBundle.run
```

On a vanilla OS run (`FIRST_INSTALL=1`), `brew bundle` is run only against the **base section** of the
Brewfile -- the lines above the sentinel. This keeps the initial install fast by skipping optional
heavy packages; the whole Brewfile is then installed in a detached background job (with
`FIRST_INSTALL` emptied in the child; its output goes to `~/Downloads/brew-bundle-full-install.log`).
On a pre-configured machine (no `FIRST_INSTALL`) the whole Brewfile is used, and the install is skipped
when `brew bundle check` already passes. A failure makes `BrewBundle.run` return false after recording its own warning, and the script carries on.

On a first install `BrewBundle` installs the base content without the preceding `Brew.bundle_check`, which skips the full-file `brew bundle check -v`: it
always fails on a vanilla OS and costs ~2s while evaluating the Brewfile DSL once more. A failed
`brew bundle install` (typically a flaky cask download) is retried once after 5 seconds. `brew bundle`
itself is deliberately not given a timeout: its `-q` output gives no progress to judge a stall by, and
killing a long cask install does more harm than waiting.

The detached full-Brewfile job is tracked (`BrewBundle.full_install_state`, `report_full_install`):
a non-zero exit is recorded as a warning naming the log, and while it is still running the closing
user action and the notification say so -- the run never reports everything as installed while casks
are still installing.

The Brewfile must have exactly one sentinel **comment** line that starts with `# FIRST_INSTALL:` to mark
the end of the base section. `BrewBundle.base_brewfile_content` returns everything above it (nil when the
sentinel is missing, in which case `BrewBundle` warns and installs the whole file as the base section).

The sentinel is a comment, so the match must not exclude comment lines. (An earlier `sed` pattern,
`/^[^#].*FIRST_INSTALL/q`, did exactly that: it never matched, so the whole Brewfile was installed as the
"base section" and the split was a silent no-op.) `spec/brewfile_spec.rb` fails if the sentinel is
missing, duplicated, or no longer splits the file, and checks `BrewBundle.base_brewfile_content` against the
real Brewfile. Do not remove or rename the sentinel line -- it is load-bearing for the vanilla OS
install path.

## The Post-Clone Part of `fresh-install-of-osx.sh` Is One Ruby Process

See [TechnicalDeepDive.md § 13](../../TechnicalDeepDive.md#13-why-fresh-install-of-osxsh-and-osx-defaultssh-remain-shell-scripts) for the rationale and the table of which step is which module (kept there only, to avoid two copies).

The script stays shell up to and including the dotfiles clone: that part must run on a vanilla macOS
with nothing but the OS, before Ruby utilities or the repository exist. Right after the clone,
`_run_post_clone_steps` runs everything else as one Ruby process:

```zsh
COLUMNS="${COLUMNS}" "${DOTFILES_DIR}/scripts/call-utility.rb" --truthy FreshInstallPostClone.run \
  "--steps_done=${steps_done}" "--start_time=${script_start_time}"
```

- It runs `call-utility.rb` by path, **not** through the `call_utility` shell function: that function
  lives in the `~/.shellrc` that `ShellrcCheck`, the module's first step, verifies.
- The shell passes the number of steps it already numbered (the module continues `[Step N of TOTAL]`
  from there), the epoch the whole run started at (closing duration line) and `COLUMNS` (not exported).
  Everything else travels as exported environment variables (`FIRST_INSTALL`, the cron backup file,
  `_DOTFILES_SCRIPT_DEPTH`, `_DOTFILES_ISSUES_FILE`, ...).
- The module is a child process, never `exec`ed, so the shell's EXIT trap still runs. The module prints
  the closing summary, the manual-step reminders and the one notification, and restores cron when it
  fails; the shell then just exits with its status (and restores cron itself only if the backup file
  is still there, i.e. the Ruby process died before it could).
- Nothing runs in the shell after the hand-off, so the shell-only chores of the old flow became
  changes to the Ruby process's `ENV` (`MacOS.load_brew_shellenv`, `ENV.delete('GIT_SSH_COMMAND')`,
  `PathUtils.append_to_path`). Steps that need zsh functions (`recompile_zsh_script`,
  `load_zsh_configs`, `delete_caches`, `compinit`) run through `zsh -c "source ~/.shellrc; ..."`.

Adding a step: put the logic in a module under `scripts/utilities/` with a spec (the existing ones --
`HomebrewInstall`, `BrewBundle`, `Keybase.bootstrap_login`, `GpgEncrypt.bootstrap_setup`,
`BootstrapRepos`, `PreferencesRestore`, `DefaultShell` -- are the pattern), call it from
`FreshInstallPostClone._install`, wrap it in `_step` if it is numbered (and bump `POST_CLONE_STEPS`),
let the module record its own failures with `Logging.record_warning`/`record_error`, and `raise Aborted`
only for a failure that must stop the run. A module that genuinely needs to know about a vanilla install
(`BrewBundle`, `PreferencesRestore`) defaults `first_install:` to `EnvVars.first_install?`.

## Background Work During A First Install

Four things run detached so the long, independent steps overlap. The foreground run joins or reports
on each of them, and nothing here is fire-and-forget:

| Background job | Started by | Needs | Joined / reported by | Log | Opt-out |
|---|---|---|---|---|---|
| Homebrew installer | `_start_early_brew_install` (shell, after the CLT step) | CLT, sudo, network | `HomebrewInstall` waits for `_DOTFILES_BREW_INSTALL_PID`, then verifies brew | `${TMPDIR:-/tmp}/dotfiles_brew_install.log` | `FRESH_INSTALL_NO_EARLY_BREW=1` |
| `osx-defaults.sh -s` baseline | `PreferencesRestore.start_baseline_in_background` (right after install-dotfiles) | the repo and sudo; not brew, not the home repo | `PreferencesRestore.run` joins it (30 min bound) before the import; failure recorded as an error | `~/Downloads/osx-defaults-baseline.log` | `FRESH_INSTALL_SERIAL_DEFAULTS=1` |
| Full Brewfile install | `BrewBundle` after the base section | the base install | `BrewBundle.report_full_install` at wrap-up | `~/Downloads/brew-bundle-full-install.log` | -- |
| Background `unshallow` batch | `ResurrectRepositories` after the last catalogue | the repos | not joined (see below) | `~/Downloads/unshallow-batch.log` | `FRESH_INSTALL_SKIP_BACKGROUND_UNSHALLOW=1` |

`BackgroundJob` (`scripts/utilities/background_job.rb`) is the shared helper for starting such a child
(stdout/stderr appended to a log, stdin closed so it can never compete for the terminal) and for
polling, waiting with a bound and reading the log tail. It requires nothing beyond `pathname`, because
`call-utility.rb` runs under `--disable-gems`.

The baseline runs concurrently with Homebrew and the clones, so `osx-defaults.sh -s` must never prompt
on the TTY (every `ask` is answered from its `-s` defaults; without cached sudo credentials the
sudo-only steps are skipped, counted and reported as one warning) and returns a meaningful exit status.
It is only started in the background when `sudo -n true` works, so it never competes for a password
prompt; otherwise it runs inline as before.

`PreferencesRestore.finish_pending` joins the baseline and closes the bracket when a run stops before
the preferences step, and `FreshInstallPostClone._wrap_up_background_work` reports on the Brewfile job
from the run's `ensure`, so the summary and the notification are truthful on every exit path.

Deliberately **not** backgrounded: `resurrect-repositories.rb` processes repositories strictly one at a
time, in this process, in path order. A parallel worker pool was built and removed -- replayed or
interleaved per-repository output was too hard to follow when something failed. (`capture-prefs.rb`
does use threads for its independent per-domain exports and imports, but the workers never log: results
are replayed in order from the main thread.)

## `FIRST_INSTALL`: Clones Stay Shallow

On a first install `clone_repo_into` does **not** unshallow, run `git maintain` or `git siu` for the
repositories it clones -- only the reftable migration runs. The one exception is `${DOTFILES_DIR}`,
which keeps the full chain (the reftable-race comment in `_post_clone_maintenance` explains why). A
repository cloned in this run is also not fetched a second time (the clone is fresh) unless it has
other remotes that would otherwise never be fetched. Once every catalogue is resurrected, ONE detached
low-priority batch (`nice -n 19`, own session, the equivalent of the user's `all unshallow`, i.e.
`run-all.rb git unshallow` with `FOLDER=${HOME} MAXDEPTH=7`) completes them all; run-all itself stays
sequential inside it. The closing message says repos were cloned shallow and that this job is fetching
their history -- not that the install already did.

## `osx-defaults.sh` On Re-Runs

The script used to repeat destructive or noisy work on every run. Now:

- **Machine names** (`_set_computer_names`): ComputerName, HostName, LocalHostName and the NetBIOS name
  embed a timestamp, so a re-run used to rename the machine every time. They are set only when the
  current `scutil --get` values do not already match the expected pattern; an existing timestamp is
  reused and a fresh one is generated only when naming for the first time.
- **Once per macOS version**: the LaunchServices rebuild (`lsregister -kill -r ...`) and the Spotlight
  re-index (`mdutil -Eda`, `-ai off`) are guarded by stamps `${XDG_CACHE_HOME}/osx-defaults-lsregister-stamp`
  and `osx-defaults-spotlight-stamp` holding the macOS version. `OSX_DEFAULTS_FORCE=1` ignores them. The
  Spotlight stamp is written only if `mdutil -Eda` succeeded. (Stamp file names must contain `stamp`:
  `delete_caches` keeps such files.)
- **Batched scalar writes**: runs of scalar `defaults write` calls (bool, int, string, floats that are
  exact in single precision) go through `_dw` and are flushed per domain with ONE
  `defaults import <domain> -` (a merge: existing keys survive, types match `defaults write`).
  `_dw <domain> <key> <type-flag> <value>` takes the same arguments as `defaults write`, so every line
  is still copy-pasteable (prefix `defaults write` instead). NSGlobalDomain, `-currentHost`, sudo and
  `/Library` domains, arrays, dicts and `-dict-add`/`-array-add` are never batched -- they flush the
  pending batch and run as plain `defaults write`, preserving order; a failed import replays that
  domain's writes one by one. **Never** use `defaults write <dom> '{ ... }'` (replaces the whole domain)
  or edit the plist directly (bypasses `cfprefsd`). `OSX_DEFAULTS_NO_BATCH=1` turns `_dw` back into
  plain writes.
- **Proving a change is safe**: `OSX_DEFAULTS_DRY_RUN=1` maps every `defaults` call onto scratch plists
  and records the other commands without touching any real preference. Run it for the old and the new
  script and diff the per-domain dumps -- empty for every batched domain is the acceptance test.
- **Bracket contract**: when `DOTFILES_APPS_BRACKETED` is non-empty (the Ruby step brackets the baseline
  and the preferences import once) the script makes no kill/restart/suspend/resume/`reload_macos_prefs`
  call; unset, it behaves exactly as before. `spec/osx_defaults_spec.rb` exercises all of this with
  shims and a file-write sandbox -- specs must never touch real preferences.
- Still run on every run (guard before changing): the `killall` of Safari/Mail/Chrome/..., rewriting
  the iTerm Keyboard Map keys and the Firefox/Zen `user.js`.

## Hand-Off of Recorded Issues Between the Shell and Ruby

`fresh-install-of-osx.sh` records its own warnings/errors in the `_step_warnings` / `_step_errors` arrays
(only the steps before the clone are left in the shell), while `FreshInstallPostClone` owns the closing
summary and notification of the whole run. Neither process can see the other's in-memory state, and a
step can also start further Ruby processes whose issues live in yet another process (for example the
`post_clone` commands `ResurrectRepositories` runs, such as `git fo --rebase`). **A file is the simplest
channel across those process boundaries**; a script that is Ruby end to end in one process needs none of it
(it reads `Logging.step_warnings`/`step_errors` directly). Most steps need no channel at all because they
run in-process: `PreferencesRestore` calls `CapturePrefs.run` directly (it restores system state in an
`ensure`, not `at_exit`), while `osx-defaults.sh` stays a shell subprocess.

- `main()` exports `_DOTFILES_ISSUES_FILE` (`${TMPDIR}/dotfiles_fresh_install_issues`) and empties the file.
- Every `Logging.record_warning`/`record_error` in a process that has the variable set appends one
  `<warning|error><TAB><entry>` line the moment it is recorded (`EnvVars.issues_file`, memoized, is nil when
  the variable is unset, so nothing else is affected).
- Before the hand-off, `_hand_over_shell_issues` appends what the shell recorded to the same file.
- `FreshInstallPostClone` calls `Logging.adopt_issues_file`: it loads what the shell wrote into its own
  collections, empties the file and becomes the owner, whose own issues stay in memory only (so they are not
  counted twice). Its children keep appending. At the end `Logging.merge_issues_file` merges what the
  children wrote, before the summary prints, and deletes the file.
- Consequence for module design: a module called from the install flow records its own failures
  (`Logging.record_*`) and the caller does not add a second, generic warning for the same problem.

## Preferences Step: Baseline, Then Export Or Import (Never Both)

`PreferencesRestore.run` does one bracket around two operations: suspend the software-update schedule
and stop the login-item apps once, run `osx-defaults.sh -s` (the baseline) and the `capture-prefs.rb`
work, then one `reload_macos_prefs`, restart the apps and resume the schedule once (in an `ensure`).
`DOTFILES_APPS_BRACKETED=1` in the children's environment tells `osx-defaults.sh` and
`CapturePrefs.run(manage_apps: false)` not to bracket on their own; a standalone `capture-prefs.rb`
run still does. Specs must never run `reload_macos_prefs` or touch the real home repo.

`capture-prefs.rb` no longer has a "backup predates `osx-defaults.sh`" timestamp check: the baseline
always runs first, and the backup is an overlay on top of it.

- **First install**: import the backup from the home repo (nothing to refresh).
- **Pre-configured machine**: either refresh the backup from the machine (export all domains and commit
  with `git sci`, which amends rather than piling up commits) **or** import it -- never both. Importing
  right after a successful export would only write back what was just exported. To avoid exporting over
  a newer backup pulled in from another machine, each successful export records
  `${XDG_CACHE_HOME}/capture-prefs-export-stamp` (written only after the commit succeeded). If the last
  home-repo commit touching `defaults/` is newer than that stamp, the backup is imported and left
  alone. A machine with no stamp yet exports as before, so the first run after upgrading can still
  overwrite a pulled backup once.
- **Parallelism**: the per-domain export and import run on up to `CAPTURE_PREFS_JOBS` threads (default
  6; `1` = serial). Workers never log; results are collected and replayed in the allowed-list order
  from the main thread, and an exception in a worker is re-raised there. Measured on 377 real
  domains: serial 5.3s, 6 jobs 1.5s, output identical.
- `Plist.export_domain` writes `defaults export <domain> -` straight to the file (no `plutil` pass), and
  excluded keys are stripped from the in-memory XML before `defaults import <domain> -`.

**Debugging note:** a fatal error in `capture-prefs.rb` is reported through `Logging` and surfaces as a
recorded error in the closing summary; look for that message rather than the line number of the shell
ERR trap, which reports where the trap string was defined, not where the failure occurred.
