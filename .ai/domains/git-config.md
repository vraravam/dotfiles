---
applyTo: "**/.gitconfig,**/custom.gitattributes,**/add-upstream-git-config.rb"
name: dotfiles-git-config
description: Use when editing ~/.config/git/config (.gitconfig), git aliases, scripts/git-* external subcommands, custom.gitattributes, or scripts/add-upstream-git-config.rb. Covers git alias shell-scripting conventions, working-directory argument convention, alias vs external subcommand, shallow-clone aliases, no-op guards, and [delta]. For per-repo override scripts and git hooks see git-overrides.md.
---

# Git Configuration Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

## Topic Files (load on demand)

| File | Read when the task involves |
|------|-----------------------------|
| [`git-overrides.md`](./git-overrides.md) | Per-repo override scripts (`upreb-<basename>.*`, `push-<basename>.*`), the folder-context dispatch pattern, native git hooks, lifecycle management |

## Scope

**This file applies to**: Git configuration files and scripts that interact with git repositories, including:
- `~/.config/git/config` - User-level git configuration (aliases, settings, hooks)
- `files/--HOME--/custom.gitattributes` - Custom git attributes
- `files/--XDG_CONFIG_HOME--/git/hooks/*` - Global git hooks (pre-push, pre-commit, etc.)
- `scripts/add-upstream-git-config.rb` - Repository upstream configuration
- Per-repository override scripts in `${PERSONAL_BIN_DIR}` (e.g., `upreb-<basename>.rb`, `push-<basename>.rb`; `.sh` also accepted)
- `scripts/git-command.rb` + `scripts/utilities/git_commands.rb`/`git_overrides.rb`/`git_hooks.rb` - Ruby implementations of `push`/`pull`/`cc`/`upreb` and the global hooks
- Autoload functions in `${XDG_CONFIG_HOME}/zsh/` (`st`, `count`) that wrap git operations

**Related files**:
- [`shell-scripting.md`](./shell-scripting.md) - Shell scripting patterns used in git alias bodies
- [`ruby-scripting.md`](./ruby-scripting.md) - Ruby patterns for git-related scripts
- [`logging-conventions.md`](./logging-conventions.md) - Error collection for multi-repo operations

**Does NOT apply to**: Repository-specific `.git/config` files, `.gitignore` files (see `custom-gitignore-maintenance.md`), or git internals unrelated to user configuration.

## Shell Scripting Rules Inside Aliases

**All generic shell scripting rules from [`shell-scripting.md`](./shell-scripting.md) apply to git alias bodies.**

This includes:
- Variable quoting (always use `"${var}"`)
- Brace notation (always use `${var}`, never `$var`)
- Guarding positional parameters (use `${1:-}` or `${1:-.}`)
- Quote styles (single vs double quotes)
- All other shell conventions

**This file only documents git-specific patterns and exceptions.**

## Git-Specific: Working Directory Argument Convention

Every `!` alias that operates on a repository **must** accept an optional `<dir>`
as its first argument, defaulting to `'.'` if omitted. Use `git -C "${1:-.}"` for
every git call inside the alias body.

```ini
# Good -- accepts optional dir; defaults to current directory
my-alias = "!f() { git -C \"${1:-.}\" some-command; }; f"

# BAD -- hardcodes current directory; cannot be called with an explicit path
my-alias = !git some-command
```

This allows callers to pass the path directly (`git my-alias /path/to/repo`) as
an alternative to `git -C /path/to/repo my-alias`. Both forms are equivalent.

**Do NOT combine both forms.** `git -C <path1> my-alias <path2>` is undefined
behaviour -- the explicit arg wins and `-C <path1>` is silently ignored. Use one
or the other:

- `git -C <path> my-alias` -- git-native; preferred for interactive use and
  scripting that already has the path in a variable passed to `-C`.
- `git my-alias <path>` -- explicit arg; preferred for callers like `run-all.rb`
  that set cwd via `cd` and invoke the alias with no args (leaving `${1:-.}` to
  default to `.`), or when constructing a command string where `-C` is awkward.

### Exceptions -- aliases where `${1}` already has a fixed meaning

Do **not** add a `<dir>` argument when the first argument already has an
established meaning:

| Alias | First arg meaning | Use instead |
|---|---|---|
| `sci` | commit message | `git -C <path> sci "<msg>"` |
| `standup` | author name | `git -C <path> standup "<author>"` |
| `new` | branch name | `git -C <path> new <branch>` |
| `old` | remote name | `git -C <path> old <remote> <branch>` |
| `recent-branch` | `--oldest` flag or reference branch | `git -C <path> recent-branch [--oldest]` |
| `f` / `se` | search pattern | `git -C <path> f <pattern>` |
| `relative-path` | path argument | `git -C <path> relative-path` |

For these, `git -C <path> <alias>` is the only option.

### `cc` -- dir + flag coexistence

`cc` accepts both a dir and flags. Since flags always start with `-`, detect the
dir at the top of the function body by checking whether `${1}` starts with `-`:

```ini
cc = "!f() { case \"${1:-}\" in -*|'') dir='.' ;; *) dir=\"${1}\"; shift ;; esac; ...; }; f"
```

This preserves the existing `git cc --expire=now` calling convention while also
allowing `git cc /path/to/repo --expire=now`.

---

## Alias vs External Subcommand (`scripts/git-<name>`)

Git runs any executable named `git-<name>` found on `PATH` as `git <name>` (including
`git -C <dir> <name>`). An external command takes precedence over an alias of the same name.
Use this instead of a `!f() { ... }` alias once a command needs real control flow, comments or
testing -- as a file it needs no config-string escaping (`\"`, trailing `\`) and can be
formatted (`shfmt`), syntax-checked (`sh -n`/`dash -n`) and commented normally.

- **Alias** (in `git/config`): one- or two-line shortcuts (`br`, `st`, `pushf`).
- **External script** (`${DOTFILES_DIR}/scripts/git-<name>`, `#!/bin/sh`, POSIX, no `.shellrc`):
  `with-retry`, `fo`, `unshallow`, `maintain`,
  `migrate-reftable`, `cc`, `upreb`. `${DOTFILES_DIR}/scripts` is on `PATH` for
  interactive shells, `fresh-install-of-osx.sh` and the generated crontab.
- A script's default directory is `git rev-parse --show-toplevel` (git ran the former aliases
  from the work tree's top level; an external command runs from the caller's directory).
- Bootstrap: before the repo is cloned these commands are not on `PATH`; `clone_repo_into`
  tests `command -v git-with-retry` / `git-maintain` (plus the `siu` alias) and falls back to a
  plain clone / skips post-clone maintenance.
- `git <name> -h`/`--help` is intercepted by git (it looks for a man page) before reaching the script.

---

## Helper Predicates for DRY Principle

Git aliases can call other git aliases. Extract repeated patterns into helper predicates
to improve maintainability and reduce duplication.

### Lock-Free Status Helpers

Two helpers provide lock-free status checks safe for prompts and monitoring:

**`git st-nolock [<dir>]`** - Returns porcelain status without locks:
```ini
st-nolock = "!f() { git -C \"${1:-.}\" --no-optional-locks status --porcelain 2>/dev/null; }; f"
```

Used in: starship prompt (4 call sites)

**`git is-dirty [<dir>]`** - Returns 0 if working tree has uncommitted changes, 1 if clean:
```ini
is-dirty = "!f() { git -C \"${1:-.}\" st-nolock | /usr/bin/grep -q .; }; f"
```

Used in: starship prompt (4 `when` conditions)

**Why `--no-optional-locks`:**
- Prevents creating lock files (`index.lock`) during read-only operations
- Safe for prompts that run on every shell render
- Avoids interfering with ongoing git operations
- Never add to interactive aliases (`st`, `status`) - users benefit from seeing lock contention

**Why separate from `st` alias:**
- Interactive `git st` should NOT use `--no-optional-locks` (users need normal locking)
- Starship/monitoring contexts need explicit lock-free behavior
- Keeps concerns separated

### Other Helper Predicates

**`git is-clean [<dir>]`** - Returns 0 if no unstaged or staged changes:
```ini
is-clean = "!f() { git -C \"${1:-.}\" d --quiet && git -C \"${1:-.}\" dc --quiet; }; f"
```

Used in: `fo --rebase`, `upreb`

**`git is-shallow [<dir>]`** - Returns 0 if repo is shallow clone:
```ini
is-shallow = "!f() { output=$(git -C \"${1:-.}\" rev-parse --is-shallow-repository); [ \"${output}\" = \"true\" ]; }; f"
```

Used in: `unshallow`'s own no-op guard, `fo` (decides `fetch` vs `fetch --unshallow` per remote)

**`git all-refs [<dir>]`** - Lists all branches (local + remote-tracking):
```ini
all-refs = "!f() { git -C \"${1:-.}\" for-each-ref --format='%(refname)' refs/heads refs/remotes; }; f"
```

Used in: `rfc`, `cc`

**`git has-upstream [<dir>]`** - Returns 0 if upstream remote exists:
```ini
has-upstream = "!f() { git -C \"${1:-.}\" remote | /usr/bin/grep -x upstream &>/dev/null; }; f"
```

Used in: `upreb`

---

## `~/.config/git/config` Aliases

### Preferred Pattern: `!f() { ... }; f`

**All multi-step shell aliases should use the named function pattern:**

```ini
my-cmd = "!f() { git -C \"${1:-.}\" command \"$@\"; }; f"
```

**Benefits:**
- Clearer structure (no nested quotes)
- Easier to read multi-line logic
- Consistent with the majority of multi-step aliases in this file (single-command aliases like `co = checkout` don't need it)
- Simpler argument handling

**Example with multi-step logic** (see § Shallow Clone Aliases below for the
full explanation of what `unshallow` does and why it starts with a guard clause --
it is long enough to live as `scripts/git-unshallow`; this is the shape of an alias
that fits in the config):
```ini
dlb = "!f() { \
  dir=\"${1:-.}\"; \
  git -C \"${dir}\" branch -vv | /usr/bin/grep ': gone]' | awk '{print $1}' | xargs -r git -C \"${dir}\" branch -D; \
}; f"
```

### Legacy Pattern: `!sh -c '...' -`

The `!sh -c '...' -` pattern is valid but **deprecated** in favor of `!f()`:

```ini
# Avoid (legacy style) -- harder to read, extra quoting complexity
my-alias = !sh -c 'git -C "${1:-.}" some-command' -
```

**When the legacy pattern was used:**
- Older Git versions (< 1.7.10) didn't support named functions well
- Historical convention before the codebase standardized

**Argument handling differences:**
- `!sh -c '...' -`: Trailing `-` sets `$0` to `-`, user args start at `$1`
- `!sh -c '...' --`: Trailing `--` sets `$0` to `--`, user args start at `$1`
- `!f() { ... }; f`: User args naturally start at `$1`, `$0` is the shell name

Both handle `"$@"` the same way for passing through extra arguments.

### Simple Aliases (No Shell)

Simpler single-command aliases can use `!git` or bare git subcommand directly:

```ini
co = checkout
```

## Shallow Clone Aliases

**`git unshallow [<dir>]`** (`scripts/git-unshallow`) - Converts a shallow and/or
partial (blobless) clone into a full clone. One command, two steps: `git fo` for
history, then an internal `backfill_blobs` function for blobs (there is no separate
`backfill-blobs` command):

- **No-op guard first**: if the repo is neither shallow (`is-shallow-repository`)
  nor a partial/blobless clone (`remote.origin.promisor`), there is nothing to
  convert -- returns immediately without even calling `fo`, rather than paying
  for a full multi-remote fetch cycle for zero benefit. This is the pattern to
  copy for any new alias whose purpose is "convert/fix X if needed" -- see
  § No-Op Guards below for the general principle.
- **`git fo`** -- fetches all remotes (promisor-first ordering), widens a
  shallow clone's default single-branch tracking to all branches, and (per
  remote) uses `fetch --unshallow` instead of a plain `fetch` when still
  shallow. This is the "routine sync" half -- also used standalone everywhere
  else in this config (`fo --rebase`, `upreb`, `pullsub`, cron, `antidote.rb`).
- **`backfill_blobs`** (function inside `git-unshallow`) -- backfills any missing blob
  objects for a partial (`--filter=blob:none`) clone, in up to 5 chunks (fewer for a
  repo with under 5 commits), newest history first, each chunk wrapped in
  `with-retry`. No-op (self-guarded) if the repo isn't a partial clone or the installed
  git predates 2.44 (`git backfill`). See the script's own comment for why chunking
  matters: `git backfill` groups every historical blob at a given path into one batch
  regardless of `--min-batch-size`, so a single path with many large historical
  versions (e.g. a binary committed directly) can otherwise produce one multi-GB,
  unsplittable transfer that a flaky connection can never complete.
- Routine freshness for an already-full repo is **not** this alias's job --
  callers that want that use `git fo` directly, or `git fo --rebase`/`git upreb`
  for the fetch-and-rebase workflows. `unshallow` answers "does this repo need
  converting", not "is this repo up to date".

**Typical workflow:**
```bash
# Convert shallow/partial clone to full clone (no-op if already full)
git unshallow
```

### `git st` -- Surfacing Missing Objects on a Partial Clone

`git st` (all three modes -- default, `-s`, `-m`) appends a report of any
objects still missing locally whenever the repo is a partial/blobless clone
(`remote.origin.promisor` = true), so it's visible at a glance -- without
remembering to run a separate command -- whether `git unshallow` still has
backfill work left to do:

```ini
if [ \"$(git -C \"${dir}\" config --get remote.origin.promisor 2>/dev/null)\" = 'true' ]; then \
  missing=$(git -C \"${dir}\" rev-list --objects --all --missing=print 2>/dev/null | grep '^?'); \
  if [ -n \"${missing}\" ]; then \
    count=$(printf '%s\n' \"${missing}\" | wc -l | xargs); \
    printf '\n%s object(s) missing locally (partial clone) -- run git unshallow to backfill:\n' \"${count}\"; \
    printf '%s\n' \"${missing}\"; \
  fi; \
fi; \
```

- **Guarded on `remote.origin.promisor`** first (same no-op-guard philosophy as
  `unshallow`/`siu` above) -- skipped entirely for the common case (a normal,
  non-partial clone), which could never have anything missing.
- **Silent when nothing is missing** -- `--missing=print` naturally produces no
  `?`-prefixed lines once everything is backfilled, so a fully-backfilled
  partial clone (post-`unshallow`) shows no extra output either; the report
  only appears while there's real, actionable missing content.
- **Cost**: ~0.2s even on a 7000-commit/11GB repo (measured) -- acceptable for
  `git st`'s human-triggered, interactive use (unlike `st-nolock`/`is-dirty`,
  which run on every prompt render and must stay lock-free and near-zero-cost;
  see § Lock-Free Status Helpers above -- this is exactly why the missing-
  objects report lives in `st`, not `st-nolock`).
- Prints the **raw** `?<sha>` lines from `--missing=print` (git's own format
  for this doesn't include the path for every entry -- cross-reference with
  `git rev-list --objects --all | grep <sha>` if you need to know which file a
  given missing object belongs to), rather than a summary-only count, so the
  exact objects are visible if you want to investigate before running
  `unshallow`.

## No-Op Guards -- "Stop Early If There's Nothing To Do"

Aliases whose purpose is conditional ("convert X if needed", "update submodules
if any exist") should check that condition **first** and return immediately
when it doesn't hold, rather than running their full body and relying on the
underlying git commands to discover there's nothing to do. This avoids paying
for expensive setup (a multi-remote fetch, a `with-retry` wrapper, a subprocess
fork) when the answer was knowable up front from a cheap, local check.

Three examples currently in `${XDG_CONFIG_HOME}/git/config`:

| Alias | Guard condition | Cheap check used |
|---|---|---|
| `unshallow` | Repo is already a full, non-partial clone | `is-shallow` + `config --get remote.origin.promisor` |
| `siu` | Repo has no submodules | `[ -f "${dir}/.gitmodules" ]` |
| `migrate-reftable` | Repo is already reftable format | `rev-parse --show-ref-format` |

`maintain` is a partial exception: there is no single deterministic boolean for
"nothing to maintain" (a repo always has *some* loose objects/reflog entries a
`gc` could touch), so it uses a **time-based** throttle instead (skip if a
`.git/dotfiles-last-maintain` stamp file is newer than 3h), mirroring the
`Core.due_for_periodic_update` pattern already used for mise-plugin/ollama-model
update throttling in `software-updates-cron.rb`. Always support a `--force`
(or equivalent) override on a time-throttled alias so the "run this now
regardless, I'm diagnosing a real problem" use case is never silently
swallowed -- this matters especially for a repair/diagnostic tool like
`maintain` ("like brew doctor").

**When adding a new no-op guard to an alias that can receive arguments**:
remember the "bare `f` doesn't forward args" gotcha below -- a guard that reads
`$1`/`$2` (e.g. a `--force` flag) silently never sees them unless the alias
ends in `f \"$@\"`, not bare `f`.

### Gotcha: Bare `f` vs `f "$@"` -- Argument Forwarding

Every `!f() { ... }; f` alias is invoked by git as `sh -c '<value>' <argv0>
<arg1> <arg2> ...`. Ending the value with bare `f` (no arguments) calls the
function with **zero** arguments -- POSIX shell functions do not automatically
inherit the outer script's positional parameters; `"$@"` must be forwarded
explicitly:

```ini
# BAD -- $1/$2/... inside f() are ALWAYS empty, regardless of what the caller
# passed to the alias, because f is invoked with no arguments
my-alias = "!f() { dir=\"${1:-.}\"; ...; }; f"

# Good -- forwards the real arguments into f()
my-alias = "!f() { dir=\"${1:-.}\"; ...; }; f \"$@\""
```

This is harmless for most existing aliases in this file because every current
call site invokes them via `git -C "${dir}" <alias>` (no trailing args) --
`-C` already changes the process's cwd before the alias runs, so `${1:-.}`
correctly defaults to `.` without needing argument forwarding at all. It only
becomes a real bug the moment an alias needs to read an actual argument (a
flag like `maintain`'s `--force`, or a second positional) -- verify this is
fixed (`f \"$@\"`) for any alias you add or modify that reads `$1`/`$2` beyond
a plain `${1:-.}` dir default. Not all aliases in this file have been swept for
this yet -- when touching one, check and fix it if it now depends on argument
forwarding that bare `f` cannot provide.

## `git sci` (Smart Commit -- Non-Interactive)

`git sci "<message>"` is fully non-interactive. It takes a commit message as
its argument and decides whether to create a new commit or amend the last one:

- Aborts if nothing is staged (`git diff --cached --quiet`).
- Amends (`git amq`) if already ahead of remote and not diverged.
- Creates a new commit (`git ci "<message>"`) otherwise.

Use `git diff --cached --quiet` to check for staged changes -- not
`git status --porcelain | grep "to unstage"`. The latter is locale-dependent
and breaks for non-English git installations.

```ini
sci = "!sh -c '\
  if git diff --cached --quiet; then \
    printf \"Nothing staged: aborting\n\"; \
  elif git status | grep -q \"is ahead of\" && ! git status | grep -q \"have diverged\"; then \
    printf \"Amending existing commit\n\"; \
    git amq; \
  else \
    printf \"Creating new commit\n\"; \
    git ci \"${1:-}\"; \
  fi' -"
```

Both paths are non-interactive: `git amq` = `commit --amend --no-edit --quiet`;
`git ci "<msg>"` = `commit -m "<msg>"`.

## `git fo --rebase` and `git upreb` -- Dirty-Tree Guard for Cron

Aliases that rebase (or rebase + push) must check for a clean working tree
**before** doing any destructive work. `rebase.autoStash = true` is not
sufficient: it stashes, rebases, then tries to pop the stash -- if the stash
conflicts with the rebased commits, the repo is left in a broken mid-operation
state.

The correct pattern is an **early exit**: check first, do nothing if dirty.

**`git fo --rebase [<dir>]`** (`scripts/git-fo`) -- fetch all remotes (the normal `fo`
fetch: with-retry + promisor-first ordering), then rebase onto `@{u}` only if clean,
falling back to a hard reset onto `@{u}` if the histories have diverged with no common
ancestor (e.g. after a remote force-squash -- see `KeybaseMigration.md`) **and** the
repo has opted in with `git config --local pull.allowResetOnDivergedHistory true`.
Without `--rebase`, `fo` only fetches. A dirty tree or an un-opted-in diverged history
makes it exit non-zero, which `run-all.rb` surfaces as a per-repo warning. There is no
separate `pull-safe` command: it was folded into `fo` since it was `fo` plus this tail.

This is the **single, canonical** implementation of "pull that tolerates a
rewritten remote history" in this codebase -- both `GitCommands.pull` (the
`pull` command, only as its fallback after a bare `git pull` fails; see below for
why the *primary* interactive path stays on bare `git pull`) and
`GitProcessor#pull` (Ruby) call `git fo --rebase` rather than each carrying
their own copy of the fetch/clean-check/merge-base/rebase-or-reset logic. A
previous, Ruby-only duplicate of this exact logic (`GitProcessor#pull_or_reset`)
was removed once its logic moved here -- if you're tempted to add a diverged-
history-aware pull anywhere else, extend or call this instead of writing
a new implementation.

**Why `GitCommands.pull`'s primary path is still a bare `git pull`, not
`fo --rebase`**: `fo --rebase` is deliberately cron/automation-oriented -- it
**refuses** outright on a dirty tree rather than touching it. The interactive
`pull` command benefits from this repo's `[merge]/[rebase] autoStash = true`
(silently stash-pull-pop on a dirty tree), which is a real daily-use
convenience. Routing the common (clean, no-diverged-history) case through
`fo --rebase` would silently regress that autostash behavior for every
interactive pull, not just diverged ones -- so `GitCommands.pull` only reaches for
`fo --rebase` as its fallback, after a bare `git pull` has already failed and
`pull.allowResetOnDivergedHistory` is set locally.

**`git upreb`** -- abort before touching anything if dirty (a mid-workflow
failure after fetch+rebase but before push would leave the repo in a worse
state than doing nothing):

```ini
upreb = "!f() { if git diff --quiet && git diff --cached --quiet; then <full workflow>; else printf 'Skipping upreb: working tree has uncommitted changes. Run manually.\n' >&2; exit 1; fi; }; f"
```

Rules:
- Use `git diff --quiet && git diff --cached --quiet` to check both unstaged
  and staged changes. Never use `git status --porcelain` for this -- it is
  locale-dependent.
- Exit non-zero on dirty so callers (e.g. `run-all.rb`) surface a warning.
- Print to **stderr** (`>&2`) so the message appears in cron logs without
  polluting stdout that callers might parse.
- In cron scripts that call these via `run-all.rb`, use `_record_warning`
  (not `_record_error`) for the outer failure -- a dirty skip is an expected
  state in a personal repo, not a script failure.

## `git size`

`git size` is human-triggered (not in the startup hot path), so subshell
invocations are acceptable. Quote all command substitutions to handle paths
containing spaces:

```ini
size = !printf '==> Size of repository at %s: %s\n' "$(git rev-parse --show-toplevel)" "$(/usr/bin/du -sh "$(git rev-parse --show-toplevel)/.git" | cut -f1)"
```

## `git cc` and `git rfc` -- Reflog Expiry Without Stash Loss

`git reflog expire --all` covers `refs/stash` and will discard stashes.
**Never use `--all`** in `reflog expire`. Instead, enumerate refs explicitly
using `git for-each-ref`:

```ini
# BAD -- discards stashes
rfc = reflog expire --expire=now --all

# Good -- preserves refs/stash; excludes refs/tags (tags have no reflogs in any
# repo -- git only maintains reflogs for HEAD and branches -- passing them always
# produces "reflog could not be found" errors)
rfc = "!f() { refs=$(git for-each-ref --format='%(refname)' refs/heads refs/remotes); [ -n \"${refs}\" ] && git reflog expire --expire=now --expire-unreachable=now --stale-fix ${refs}; }; f"
```

The same rule applies inside `git cc` -- the `reflog expire` step must use
`git for-each-ref` enumeration of `refs/heads` and `refs/remotes` only. `refs/tags`
must be excluded -- tags have no reflogs in any repo (git only maintains reflogs for
`HEAD` and branches), and passing them to `git reflog expire` always produces
"reflog could not be found" errors for every tag.

**There is no `compress` alias.** `git cc --expire=now` already expires the whole reflog
immediately and then does the full prune/repack/gc cleanup, i.e. exactly what
`rfc && cc` would do. `GitProcessor#compress` (Ruby) runs `git cc --expire=now`. Use
`rfc` on its own only when you want the reflog expiry without the repack.

## `[delta]` -- Diff Rendering

`delta` is configured under `[delta]` in `~/.config/git/config`. Key rules:

- **`minus-style` / `plus-style`**: use `"syntax <bg-color>"` (not `"red"` /
  `"green"`). Foreground-only colors lose syntax highlighting on whole-line
  diffs; `syntax <bg>` preserves it.
- **`minus-emph-style` background**: must be visually brighter than the
  `minus-style` background to remain distinct. If you adjust `minus-style`'s
  background, adjust `minus-emph-style`'s background proportionally.
- **`line-fill-method = ansi`**: extends the diff background color to the full
  terminal width. The default (`spaces`) only colors actual characters, leaving
  the rest of the line with the terminal's default background -- which looks
  inconsistent on wide terminals.
- Do not revert `minus-style` / `plus-style` back to bare `"red"` / `"green"` --
  those were the original values and they dropped syntax highlighting.

---

## `.gitattributes`

`install-dotfiles.rb` copies `custom.gitattributes` to `.gitattributes` in the
appropriate directory. Resolution when both files exist as real files: on `FIRST_INSTALL`
the destination wins; otherwise the newer mtime wins (repo source wins on a tie).
Prefer editing `custom.gitattributes` in the repo; if you edit `.gitattributes` directly,
ensure its mtime is newer before re-running `install-dotfiles.rb`.

Binary file types must be marked binary:

```gitattributes
*.zwc  binary
```

XML plist files (`*.plist`) exported by `capture-prefs.rb` are text -- no
`binary` attribute needed. Do not add `*.plist binary` or `*.defaults binary`.
