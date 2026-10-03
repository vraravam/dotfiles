---
applyTo: "**/.gitconfig,**/custom.gitattributes,**/add-upstream-git-config.rb"
name: dotfiles-git-config
description: Use when editing ~/.config/git/config (.gitconfig), custom.gitattributes, git hooks under files/--XDG_CONFIG_HOME--/git/hooks/, scripts/add-upstream-git-config.rb, or any per-repo override script like upreb-<basename>.sh / push-<basename>.sh in ${PERSONAL_BIN_DIR}. Covers git alias shell-scripting conventions, the folder-context-aware override dispatch pattern, and native-hook vs wrapper-function lifecycle management.
---

# Git Configuration Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

## Scope

**This file applies to**: Git configuration files and scripts that interact with git repositories, including:
- `~/.config/git/config` - User-level git configuration (aliases, settings, hooks)
- `files/--HOME--/custom.gitattributes` - Custom git attributes
- `files/--XDG_CONFIG_HOME--/git/hooks/*` - Global git hooks (pre-push, pre-commit, etc.)
- `scripts/add-upstream-git-config.rb` - Repository upstream configuration
- Per-repository override scripts in `${PERSONAL_BIN_DIR}` (e.g., `upreb-<basename>.sh`, `push-<basename>.sh`)
- Autoload functions in `${XDG_CONFIG_HOME}/zsh/` that wrap git operations

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
| `recent-branch` / `oldest-branch` | reference branch | `git -C <path> recent-branch` |
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

## Per-Repository Customization Architecture

### Overview

This repository uses a **hybrid approach** for per-repository git customizations:

1. **Git native hooks** (for built-in commands: push, pull, commit, merge, etc.)
2. **Git alias overrides** (for custom commands: upreb, cc, etc.)
3. **Autoload scripts** (for complex shared logic)

### Why Hybrid?

**Problem**: Git built-in commands (push, pull) take precedence over aliases with the same name.
- When you run `git push`, git executes the built-in push command, NOT `alias.push`
- Custom aliases like `upreb` work fine (no built-in command to conflict with)

**Solution**:
- Use git's **native hook mechanism** for BEFORE logic (pre-push validation)
- Use **wrapper functions** for AFTER logic (post-push cleanup)
- Use **alias override dispatch** for custom commands (upreb/cc)

### Architecture Diagram

```
Built-in commands with lifecycle management:
  ./push-browser-profiles.sh (wrapper function)
  └─> with_cron_suspended _push
      ├─> suspend_cron (before)
      ├─> _push (operation)
      └─> recron (after)

Built-in commands with pre-validation only:
  git push
  └─> core.hooksPath → ~/.config/git/hooks/pre-push
      ├─> .git/hooks.local/pre-push (repo-specific, optional)
      └─> ${PERSONAL_BIN_DIR}/pre-push-<basename>.sh (per-repo validation)

Custom commands (upreb/cc):
  git upreb
  └─> alias.upreb
      ├─> ${PERSONAL_BIN_DIR}/upreb-<basename>.sh (full override)
      └─> ${XDG_CONFIG_HOME}/zsh/upreb (default implementation via _upreb)
```

---

## Git Native Hooks

### Global Hooks Directory

All repositories use global hooks installed via `core.hooksPath` in `.gitconfig`:

```ini
[core]
  hooksPath = ~/.config/git/hooks
```

Hook files are stored in `${DOTFILES_DIR}/files/--XDG_CONFIG_HOME--/git/hooks/` and symlinked by `install-dotfiles.rb`.

### Hook Execution Order

**IMPORTANT: Git only supports `pre-push`, NOT `post-push`**

Git natively supports these client-side hooks:
- `pre-push` - Runs before every `git push` (even when nothing to push)
- `pre-commit`, `post-commit`, `post-merge`, `post-checkout` - Various other operations

**Git does NOT have a `post-push` hook.** This is not a bug - it's intentional design.

**pre-push execution order**:
1. `.git/hooks.local/pre-push` - Repo-specific hook (optional, e.g., from Husky/lint-staged)
2. `${PERSONAL_BIN_DIR}/pre-push-<basename>.sh` - Per-repo customization

### Hook Installation

Hooks are installed automatically via `core.hooksPath` configuration in `.gitconfig`. When you clone a repository, the global hooks in `~/.config/git/hooks/` are immediately active for that repository.

No additional installation step is required - just create your per-repo customization scripts in `${PERSONAL_BIN_DIR}` with the pattern `pre-<command>-<basename>.sh`, and the global hooks will automatically discover and execute them.

### Per-Repo Hook Scripts

**For operations requiring cleanup AFTER push completes**, use wrapper functions instead of hooks (see § Wrapper Functions for Lifecycle Management below).

Create simple scripts in `${PERSONAL_BIN_DIR}` with pattern: `pre-<command>-<basename>.sh` (follows git's standard hook naming convention).

**CRITICAL: EXIT traps in pre-push hooks do NOT work** because the trap fires when the hook script exits (before git starts the actual push operation). For suspend/resume patterns, use wrapper functions instead.

**Example: pre-push validation**

```zsh
# pre-push-my-repo.sh
#!/usr/bin/env zsh
set -euo pipefail
source "${HOME}/.shellrc"

# Validation only - no cleanup needed after push
if ! run_tests; then
  error "Tests failed - blocking push"
  exit 1
fi
```

**Benefits**:
- ✅ Works for all git operations that have native hooks
- ✅ Simple scripts - no autoload loading, no depth tracking, no script infrastructure
- ✅ Automatic installation on clone
- ✅ Chains with repo-specific hooks (Husky, lint-staged, etc.)

**Limitation**: Only available for operations git provides hooks for (pre-push, pre-commit, etc.)

---

## Wrapper Functions for Lifecycle Management

**Problem**: Git has NO `post-push` hook, and EXIT traps in `pre-push` fire before git starts pushing.

**Solution**: Wrapper functions that control the entire operation lifecycle (before → operation → after).

### Pattern: Suspend/Resume Around Git Operations

Use `with_cron_suspended` (defined in `.aliases`) to wrap operations that need cleanup after completion:

```zsh
# push-browser-profiles.sh
#!/usr/bin/env zsh
set -euo pipefail

_SCRIPT_NAME="${0:t}"
source "${ZDOTDIR}/.aliases"

# Load autoload script to get _push function
require_env_var XDG_CONFIG_HOME
load_file_if_exists "${XDG_CONFIG_HOME}/zsh/push"

main() {
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  trap '_decrement_script_depth' EXIT

  local script_start_time="${EPOCHSECONDS}"
  print_script_start

  # Suspend cron, run push, restore cron automatically
  with_cron_suspended _push "$@"

  print_script_summary "${script_start_time}"
}

main "$@"
```

**Usage**:
```bash
cd "${PERSONAL_PROFILES_DIR}"
./push-browser-profiles.sh  # or add to PATH and call directly
```

**How `with_cron_suspended` works**:
1. Suspends cron (backs up current crontab)
2. Runs the wrapped function (`_push`)
3. Calls `recron` to restore crontab from tracked file
4. Cleans up backup file
5. Handles errors via EXIT trap - cron is always restored

**Benefits**:
- ✅ Works regardless of whether push transfers data
- ✅ Handles errors - cron always restored
- ✅ No manual cleanup needed
- ✅ Reusable pattern for any operation needing lifecycle management

**When to use wrapper functions vs hooks**:
- **Wrapper**: Need cleanup AFTER operation completes (push, pull with cron suspension)
- **Hook**: Need validation BEFORE operation starts (pre-push tests, pre-commit linting)

---

## Folder-Context-Aware Override Pattern (Custom Commands)

Git aliases support folder-specific override scripts that allow customization of git commands on a per-repository basis. This enables workflows like `all upreb` where different repositories can have custom pre/post logic while sharing common implementation.

### How It Works

When a git alias runs, it checks for an override script at `${PERSONAL_BIN_DIR}/<alias>-<basename>.sh`:
- `<alias>` - The git alias name (e.g., `upreb`, `push`, `cc`)
- `<basename>` - The folder name of the current repository (e.g., `zen-browser-desktop`, `browser-profiles`)

If the override exists and is executable, the alias sources it instead of running the default implementation.

### Architecture

```
${PERSONAL_BIN_DIR}/
├── upreb-zen-browser-desktop.sh     # Custom upreb for zen-browser-desktop repo
├── push-browser-profiles.sh         # Custom push for browser-profiles repo
├── pull-service-center.sh           # Custom pull for service-center repo
└── cc-browser-profiles.sh           # Custom cc for browser-profiles repo
```

Each override script:
1. Sources `.aliases` to get access to shell utilities
2. Loads the corresponding autoload script to get the common `_<cmd>` implementation
3. Defines `main()` with custom pre/post logic
4. Calls `_<cmd>` for the common behavior

### Implementation Pattern

**Git alias with override support:**
```ini
upreb = "!f() { \
  dir=\"${1:-.}\"; \
  if [ -n \"${PERSONAL_BIN_DIR:-}\" ]; then \
    basename=\"$(basename \"$(cd \"${dir}\" && pwd)\")\"; \
    override=\"${PERSONAL_BIN_DIR}/upreb-${basename}.sh\"; \
    if [ -x \"${override}\" ]; then \
      (cd \"${dir}\" && . \"${override}\"); \
      return $?; \
    fi; \
  fi; \
  # ... default implementation ...; \
}; f"
```

**Override script example** (`upreb-zen-browser-desktop.sh`):
```zsh
#!/usr/bin/env zsh
set -euo pipefail

_SCRIPT_NAME="${0:t}"
source "${ZDOTDIR}/.aliases"

# Load autoload script to get _upreb function
require_env_var XDG_CONFIG_HOME
load_file_if_exists "${XDG_CONFIG_HOME}/zsh/upreb"

main() {
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  trap '_decrement_script_depth' EXIT

  local script_start_time="${EPOCHSECONDS}"
  print_script_start

  # Custom pre-logic: delete stale tag
  if git rev-parse -q --verify refs/tags/twilight &>/dev/null; then
    git delete-tag twilight
  fi

  # Call common implementation
  _upreb

  print_script_summary "${script_start_time}"
}

main "$@"
```

### Aliases with Override Support

The following git aliases support folder-specific overrides:

| Alias | Override Pattern | Common Implementation |
|-------|------------------|----------------------|
| `upreb` | `upreb-<basename>.sh` | `_upreb` in `${XDG_CONFIG_HOME}/zsh/upreb` |
| `push` | `push-<basename>.sh` | `_push` in `${XDG_CONFIG_HOME}/zsh/push` |
| `pull` | `pull-<basename>.sh` | `_pull` in `${XDG_CONFIG_HOME}/zsh/pull` |
| `cc` | `cc-<basename>.sh` | Default git alias implementation |

### Usage Examples

**Interactive use:**
```bash
cd ~/dev/oss/zen-browser-desktop
git upreb  # Uses upreb-zen-browser-desktop.sh if it exists

cd ~/dev/project
git upreb  # Uses default upreb implementation
```

**With `run-all.rb` (multi-repo):**
```bash
all upreb  # Each repo uses its override if it exists, otherwise default
```

**Direct invocation:**
```bash
git upreb ~/dev/oss/zen-browser-desktop  # Override based on basename
```

### When to Use Overrides

Create folder-specific override scripts when a repository needs:
- **Pre-operation cleanup** (delete stale tags, remove temp files)
- **Post-operation actions** (trigger builds, update submodules)
- **Custom validation** (check for specific branch names, verify tests pass)
- **Wrapper behavior** (suspend cron during push, restore mtime after pull)

### Relationship to Shell Autoload Functions

The shell autoload functions in `${XDG_CONFIG_HOME}/zsh/` also support overrides via `dispatch_or_fallback`, but they only activate when:
1. The function is called directly by name (e.g., `upreb` not `git upreb`)
2. From a context where the autoload function is loaded (interactive shell)

### `run-all.rb`'s Own Override Dispatch (covers git builtins too)

`git cc`/`git upreb` already resolve their own override via the alias-level dispatch
shown above, which works transparently through `all cc`/`all upreb` because
`run-all.rb` re-invokes a fresh `git cc`/`git upreb` in each repo directory (the
basename resolves correctly per-repo since the alias body derives it from the
current working directory).

That alias-level mechanism cannot cover git **builtins** (`push`, `pull`, etc.) --
git always resolves a builtin before consulting `[alias]`, so there is no way to
intercept `git push` via an alias of the same name. To close this gap, `run-all.rb`
(`scripts/run-all.rb`) has its own override-dispatch check, applied generically to
**every** command it runs (not just `git ...`) before invoking anything in a repo
directory:

- Derives an override name: `command[1]` when `command[0] == 'git'` (e.g. `push`,
  `cc`, `upreb`), otherwise `command[0]` (e.g. `ls`, `custom-script.sh`).
- Looks for `${PERSONAL_BIN_DIR}/<name>-<basename>.sh` for the repo currently being
  processed (`<basename>` = the repo directory's basename).
- If found and executable, execs that script directly (cwd = repo dir, remaining
  args forwarded) **instead of** the original command -- this is what makes a
  `with_cron_suspended`-wrapped override transparently apply to `push`/`pull`
  through `all push`/`all pull`, exactly as it already did for `cc`/`upreb`.
- If not found, falls back to the original `run-all.rb` behavior: `/bin/zsh -c
  "<command joined>"` in the repo directory.

**Cyclical-dispatch safety net**: before invoking a resolved override script,
`run-all.rb` sets `_RUN_ALL_OVERRIDE_SKIP=1` in that subprocess's environment
(mirroring `_GIT_OVERRIDE_SKIP`, which it also sets for `git ...` commands so the
alias's own redundant check doesn't re-fire). If `run-all.rb` is ever invoked
again from within that subprocess tree (e.g. a future override script mistakenly
calls `all <cmd>` again), the inner invocation sees the env var already set and
skips its own override-dispatch entirely -- bounding any accidental recursion to
one level instead of looping.

This makes the alias-level dispatch on `cc`/`upreb` effectively redundant for the
`run-all.rb`/`all` code path specifically (run-all.rb finds and execs the same
override script directly, without ever shelling out to `git cc`/`git upreb` at
all) -- but the alias-level dispatch is still required and still active for a
human running `git cc`/`git upreb` directly at the terminal, outside of
`run-all.rb`.

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

Used in: `pull-safe`, `upreb`

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
full explanation of what this one does and why it starts with a guard clause):
```ini
unshallow = "!f() { \
  dir=\"${1:-.}\"; \
  if [ \"$(git -C \"${dir}\" rev-parse --is-shallow-repository 2>/dev/null)\" != 'true' ] && \
    [ \"$(git -C \"${dir}\" config --get remote.origin.promisor 2>/dev/null)\" != 'true' ]; then \
    printf 'Already a full clone -- nothing to unshallow in %s\n' \"${dir}\"; \
    exit 0; \
  fi; \
  git -C \"${dir}\" fo && git -C \"${dir}\" backfill-blobs; \
}; f \"$@\""
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

**`git unshallow [<dir>]`** - Converts a shallow and/or partial (blobless) clone
into a full clone. Delegates to two smaller aliases rather than reimplementing
fetch/backfill logic itself:

```ini
unshallow = "!f() { \
  dir=\"${1:-.}\"; \
  if [ \"$(git -C \"${dir}\" rev-parse --is-shallow-repository 2>/dev/null)\" != 'true' ] && \
    [ \"$(git -C \"${dir}\" config --get remote.origin.promisor 2>/dev/null)\" != 'true' ]; then \
    printf 'Already a full clone -- nothing to unshallow in %s\n' \"${dir}\"; \
    exit 0; \
  fi; \
  git -C \"${dir}\" fo && git -C \"${dir}\" backfill-blobs; \
}; f \"$@\""
```

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
  else in this config (`pull-safe`, `upreb`, `pullsub`, cron, `antidote.rb`).
- **`git backfill-blobs`** -- backfills any missing blob objects for a partial
  (`--filter=blob:none`) clone, in up to 5 chunks (fewer for a repo with under
  5 commits), newest history first, each chunk wrapped in `with-retry`. No-op
  (self-guarded) if the repo isn't a partial clone or the installed git
  predates 2.44 (`git backfill`). See the alias's own comment in
  `${XDG_CONFIG_HOME}/git/config` for why chunking matters: `git backfill`
  groups every historical blob at a given path into one batch regardless of
  `--min-batch-size`, so a single path with many large historical versions
  (e.g. a binary committed directly) can otherwise produce one multi-GB,
  unsplittable transfer that a flaky connection can never complete.
- Routine freshness for an already-full repo is **not** this alias's job --
  callers that want that use `git fo` directly, or `git pull-safe`/`git upreb`
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
| `unshallow` | Repo is already a full, non-partial clone | `rev-parse --is-shallow-repository` + `config --get remote.origin.promisor` |
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

## `git pull-safe` and `git upreb` -- Dirty-Tree Guard for Cron

Aliases that rebase (or rebase + push) must check for a clean working tree
**before** doing any destructive work. `rebase.autoStash = true` is not
sufficient: it stashes, rebases, then tries to pop the stash -- if the stash
conflicts with the rebased commits, the repo is left in a broken mid-operation
state.

The correct pattern is an **early exit**: check first, do nothing if dirty.

**`git pull-safe`** -- fetch all remotes (via `fo`, for with-retry + promisor-
first ordering), rebase onto `@{u}` only if clean, falling back to a hard
reset onto `@{u}` if the histories have diverged with no common ancestor
(e.g. after a remote force-squash -- see `KeybaseMigration.md`) **and** the
repo has opted in with `git config --local pull.allowResetOnDivergedHistory
true`:

```ini
pull-safe = "!f() { \
  dir=\"${1:-.}\"; \
  git -C \"${dir}\" fo; \
  if ! git -C \"${dir}\" is-clean; then \
    printf 'Skipping rebase in %s: working tree has uncommitted changes. Pull manually.\n' \"${dir}\" >&2; \
    exit 1; \
  fi; \
  branch=$(git -C \"${dir}\" br); \
  if [ -z \"${branch}\" ]; then exit 1; fi; \
  if git -C \"${dir}\" merge-base \"${branch}\" '@{u}' >/dev/null 2>&1; then \
    git -C \"${dir}\" rebase '@{u}'; \
    exit $?; \
  fi; \
  allow_reset=$(git -C \"${dir}\" config --type=bool --default false pull.allowResetOnDivergedHistory); \
  if [ \"${allow_reset}\" != 'true' ]; then exit 1; fi; \
  git -C \"${dir}\" reset --hard '@{u}'; \
}; f \"$@\""
```

This is the **single, canonical** implementation of "pull that tolerates a
rewritten remote history" in this codebase -- both `pull`/`_pull` (the shell
autoload, only as its fallback after a bare `git pull` fails; see below for
why the *primary* interactive path stays on bare `git pull`) and
`GitProcessor#pull` (Ruby) call into this one alias rather than each carrying
their own copy of the fetch/clean-check/merge-base/rebase-or-reset logic. A
previous, Ruby-only duplicate of this exact logic (`GitProcessor#pull_or_reset`)
was removed once its logic moved here -- if you're tempted to add a diverged-
history-aware pull anywhere else, extend or call this alias instead of writing
a new implementation.

**Why `pull`/`_pull`'s primary path is still a bare `git pull`, not
`pull-safe`**: `pull-safe` is deliberately cron/automation-oriented -- it
**refuses** outright on a dirty tree rather than touching it. The interactive
`pull` command benefits from this repo's `[merge]/[rebase] autoStash = true`
(silently stash-pull-pop on a dirty tree), which is a real daily-use
convenience. Routing the common (clean, no-diverged-history) case through
`pull-safe` would silently regress that autostash behavior for every
interactive pull, not just diverged ones -- so `_pull` only reaches for
`pull-safe` as its fallback, after a bare `git pull` has already failed and
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

**`git compress [<dir>] [--expire=<when>] [<extra-reflog-flags>]`** -- combines
`rfc && cc` into a single named operation, since the two are almost always run
together (this section's own examples show `git rfc && git cc`). Mirrors how
`unshallow` combines `fo`+`backfill-blobs`: when two aliases are routinely
chained by every caller, add a third alias that does both rather than leaving
every call site (interactively, or in Ruby via multiple `run_alias` calls) to
chain them manually.

```ini
compress = "!f() { \
  case \"${1:-}\" in \
    -*|'') dir='.' ;; \
    *) dir=\"${1:-}\" ;; \
  esac; \
  git -C \"${dir}\" rfc && git -C \"${dir}\" cc \"$@\"; \
}; f \"$@\""
```

`rfc` only ever needs the `<dir>` argument (it has no flags of its own), so
`compress` extracts just that for the `rfc` call -- the full, unmodified `"$@"`
is still forwarded to `cc`, which already knows how to parse its own
`<dir>`/`--expire=<when>`/`<extra-reflog-flags>` combination (reusing `cc`'s
existing parsing rather than duplicating it a third time). `GitProcessor#compress`
(Ruby) calls this one alias instead of two separate `run_alias` calls.

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
