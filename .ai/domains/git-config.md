---
applyTo: "**/.gitconfig,**/custom.gitattributes,**/add-upstream-git-config.rb"
---

# Git Configuration Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

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
source "${HOME}/.aliases"

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
cd ~/personal/vijay/browser-profiles
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
source "${HOME}/.aliases"

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

When using `run-all.rb git upreb`:
- Executes `/bin/zsh -c "git upreb"` in each repo
- Invokes the **git alias** (not the shell function)
- Git alias override mechanism is the only way to customize behavior

This is why git aliases need their own override dispatch logic — they're the actual entry point in the `run-all.rb` workflow.

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
is-shallow = "!f() { git -C \"${1:-.}\" rev-parse --is-shallow-repository | /usr/bin/grep -q true; }; f"
```

Used in: `unshallow`

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

## `~/.gitconfig` Aliases

### Preferred Pattern: `!f() { ... }; f`

**All multi-step shell aliases should use the named function pattern:**

```ini
my-cmd = "!f() { git -C \"${1:-.}\" command \"$@\"; }; f"
```

**Benefits:**
- Clearer structure (no nested quotes)
- Easier to read multi-line logic
- Consistent with rest of codebase (17/22 aliases use this pattern)
- Simpler argument handling

**Example with multi-step logic:**
```ini
unshallow = "!f() { \
  dir=\"${1:-.}\"; \
  git -C \"${dir}\" remote | while IFS= read -r remote; do \
    git -C \"${dir}\" remote set-branches \"${remote}\" '*'; \
  done && \
  ( git -C \"${dir}\" is-shallow && git -C \"${dir}\" fetch --unshallow || true ); \
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
st = status --short --branch
```

## Shallow Clone Aliases

**`git unshallow [<dir>]`** - Converts a shallow repository to a full clone and configures it to fetch all branches:

```ini
unshallow = "!f() { \
  dir=\"${1:-.}\"; \
  git -C \"${dir}\" remote | while IFS= read -r remote; do \
    git -C \"${dir}\" remote set-branches \"${remote}\" '*'; \
  done && \
  ( git -C \"${dir}\" is-shallow && git -C \"${dir}\" fetch --unshallow || true ); \
}; f"
```

- Configures all remotes to fetch all branches (`remote set-branches <remote> '*'` for each remote)
- If shallow, runs `fetch --unshallow` to convert to a full clone
- **After running this, you must run `git fetch` or `git pull` to retrieve the complete history for all branches**
- No-op if repo is already a full clone
- Replaces the previous `fetch-unshallow` and `pull-unshallow` aliases

**Typical workflow:**
```bash
# Convert shallow clone to full clone
git unshallow

# Fetch complete history for all branches
git fetch

# Or use in one line
git unshallow && git fetch
```

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

**`git pull-safe`** -- fetch all remotes, rebase onto `@{u}` only if clean:

```ini
pull-safe = "!f() { git -C \"${1:-.}\" fetch; if git -C \"${1:-.}\" diff --quiet && git -C \"${1:-.}\" dc --quiet; then git -C \"${1:-.}\" rebase '@{u}'; else printf 'Skipping rebase in %s: working tree has uncommitted changes. Pull manually.\n' \"${1:-.}\" >&2; exit 1; fi; }; f"
```

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

## `[delta]` -- Diff Rendering

`delta` is configured under `[delta]` in `~/.gitconfig`. Key rules:

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
