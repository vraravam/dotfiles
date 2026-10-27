---
applyTo: "**/.gitconfig,**/custom.gitattributes,**/add-upstream-git-config.rb,**/git/hooks/*,**/scripts/git-*,**/personal/dev/bin/*"
name: dotfiles-git-overrides
description: Use when creating or editing per-repo git override scripts (upreb-<basename>.rb/.sh, push-<basename>.*, pull-/cc-) in ${PERSONAL_BIN_DIR}, the GitOverrides dispatch, global git hooks under files/--XDG_CONFIG_HOME--/git/hooks/, or native-hook vs wrapper-function lifecycle management.
---

# Git Overrides and Hooks Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules when customising git commands or lifecycle hooks per repository.

**Related files**:
- [`git-config.md`](./git-config.md) - Aliases, external subcommands, `.gitattributes`, `[delta]` -- read this first
- [`shell-scripting.md`](./shell-scripting.md) - Shell patterns used in override scripts
- [`ruby-scripting.md`](./ruby-scripting.md) - Ruby patterns for Ruby override scripts

## Per-Repository Customization Architecture

### Overview

This repository uses a **hybrid approach** for per-repository git customizations:

1. **Git native hooks** (for built-in commands: push, pull, commit, merge, etc.)
2. **Git alias overrides** (for custom commands: upreb, cc, etc.)
3. **Ruby command implementations** (`scripts/git-command.rb` -> `GitCommands`, for shared logic)

### Why Hybrid?

**Problem**: Git built-in commands (push, pull) take precedence over aliases with the same name.
- When you run `git push`, git executes the built-in push command, NOT `alias.push`
- Custom aliases like `upreb` work fine (no built-in command to conflict with)

**Solution**:
- Use git's **native hook mechanism** for BEFORE logic (pre-push validation)
- Use **per-repo Ruby overrides** for AFTER logic (post-push cleanup)
- Use **alias override dispatch** for the git aliases (upreb/cc)

### Architecture Diagram

```
Built-in commands with lifecycle management:
  push (alias for scripts/git-command.rb push)
  └─> ${PERSONAL_BIN_DIR}/push-<basename>.rb (per-repo override)
      └─> Cron.with_cron_suspended { GitCommands.push }
          ├─> suspend_cron (before)
          ├─> GitCommands.push (operation)
          └─> recron (after)

Built-in commands with pre-validation only:
  git push
  └─> core.hooksPath → ~/.config/git/hooks/pre-push
      ├─> .git/hooks.local/pre-push (repo-specific, optional)
      └─> ${PERSONAL_BIN_DIR}/pre-push-<basename>.rb or .sh (per-repo validation)

Custom commands (upreb/cc):
  git upreb
  └─> alias.upreb
      ├─> ${PERSONAL_BIN_DIR}/upreb-<basename>.rb or .sh (full override)
      └─> default implementation (the alias body)
  upreb (alias for scripts/git-command.rb upreb)
  └─> ${PERSONAL_BIN_DIR}/upreb-<basename>.rb or .sh, else GitCommands.upreb
```

---

## Git Native Hooks

### Global Hooks Directory

All repositories use global hooks installed via `core.hooksPath` in `.gitconfig`:

```ini
[core]
  hooksPath = ~/.config/git/hooks
```

Hook files are stored in `${DOTFILES_DIR}/files/--XDG_CONFIG_HOME--/git/hooks/` and symlinked by `install-dotfiles.rb`. Each is a few-line Ruby script that `require_relative`s `scripts/utilities/git_hooks.rb` (`GitHooks.pre_commit`/`GitHooks.pre_push`) -- `require_relative` resolves from the hook's *real* location, so the symlinks keep working.

### Hook Execution Order

**IMPORTANT: Git only supports `pre-push`, NOT `post-push`**

Git natively supports these client-side hooks:
- `pre-push` - Runs before every `git push` (even when nothing to push)
- `pre-commit`, `post-commit`, `post-merge`, `post-checkout` - Various other operations

**Git does NOT have a `post-push` hook.** This is not a bug - it's intentional design.

**pre-push execution order**:
1. `.git/hooks.local/pre-push` - Repo-specific hook (optional, e.g., from Husky/lint-staged)
2. `${PERSONAL_BIN_DIR}/pre-push-<basename>.rb` (or `.sh`) - Per-repo customization

### Hook Installation

Hooks are installed automatically via `core.hooksPath` configuration in `.gitconfig`. When you clone a repository, the global hooks in `~/.config/git/hooks/` are immediately active for that repository.

No additional installation step is required - just create your per-repo customization scripts in `${PERSONAL_BIN_DIR}` with the pattern `pre-<command>-<basename>.rb` (or `.sh`), and the global hooks will automatically discover and execute them.

### Per-Repo Hook Scripts

**For operations requiring cleanup AFTER push completes**, use a per-repo override instead of a hook (see § Per-Repo Overrides for Lifecycle Management below).

Create simple scripts in `${PERSONAL_BIN_DIR}` with pattern: `pre-<command>-<basename>.rb` or `.sh` (follows git's standard hook naming convention).

**CRITICAL: EXIT traps in pre-push hooks do NOT work** because the trap fires when the hook script exits (before git starts the actual push operation). For suspend/resume patterns, use a per-repo override instead.

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
- ✅ Simple scripts - no depth tracking, no script infrastructure
- ✅ Automatic installation on clone
- ✅ Chains with repo-specific hooks (Husky, lint-staged, etc.)

**Limitation**: Only available for operations git provides hooks for (pre-push, pre-commit, etc.)

---

## Per-Repo Overrides for Lifecycle Management

**Problem**: Git has NO `post-push` hook, and EXIT traps in `pre-push` fire before git starts pushing.

**Solution**: A per-repo override script that controls the entire operation lifecycle (before -> operation -> after).

### Pattern: Suspend/Resume Around Git Operations

Use `Cron.with_cron_suspended` (`scripts/utilities/cron.rb`) to wrap operations that need cleanup after completion:

```ruby
#!/usr/bin/env ruby
# ${PERSONAL_BIN_DIR}/push-browser-profiles.rb
# frozen_string_literal: true

require 'cron'
require 'git_commands'
require 'logging'

Logging.run_script do
  # Suspend cron, run the default push, restore cron automatically.
  # header: false because run_script already prints this script's own banner.
  Cron.with_cron_suspended { GitCommands.push(args: ARGV, header: false) }
end
```

**Usage**: type `push` inside the repo -- the `push` alias (`scripts/git-command.rb`) finds and runs the override.

**How `Cron.with_cron_suspended` works**:
1. Suspends cron (backs up current crontab)
2. Yields to the block (`GitCommands.push`)
3. Calls `recron` to restore crontab from tracked file
4. Cleans up backup file
5. Uses an `ensure` clause - cron is restored on an exception or an early `return` from the block too

**Benefits**:
- ✅ Works regardless of whether push transfers data
- ✅ Handles errors - cron always restored
- ✅ No manual cleanup needed
- ✅ Reusable pattern for any operation needing lifecycle management

**When to use an override vs hooks**:
- **Override**: Need cleanup AFTER operation completes (push, pull with cron suspension)
- **Hook**: Need validation BEFORE operation starts (pre-push tests, pre-commit linting)

---

## Folder-Context-Aware Override Pattern (Custom Commands)

Git aliases support folder-specific override scripts that allow customization of git commands on a per-repository basis. This enables workflows like `all upreb` where different repositories can have custom pre/post logic while sharing common implementation.

### How It Works

When one of these commands runs, it checks for an override script at `${PERSONAL_BIN_DIR}/<command>-<basename>.rb` (then `.sh`; a `.rb` file wins if both exist):
- `<command>` - `upreb`, `push`, `pull` or `cc`
- `<basename>` - The folder name of the current repository (e.g., `zen-browser-desktop`, `browser-profiles`)

If the override exists and is executable, it runs **instead of** the default implementation, with the repo as its working directory, only the `--switches` as arguments, `_GIT_OVERRIDE_SKIP=1` in its environment and `RUBYLIB` including `scripts/utilities/`.

Two entry points implement the same lookup, kept in step by convention:
- **Ruby**: `GitOverrides.script_for(command, dir)` (`scripts/utilities/git_overrides.rb`), used by `scripts/git-command.rb` (the `push`/`pull`/`upreb` shell aliases), `run-all.rb` and the git hooks
- **Shell**: `scripts/git-cc` and `scripts/git-upreb` (the `git cc`/`git upreb` commands) and `dispatch_or_fallback` (`.aliases`, for the `st`/`count` autoload functions)

### Architecture

```
${PERSONAL_BIN_DIR}/
├── upreb-zen-browser-desktop.rb     # Custom upreb for zen-browser-desktop repo
├── upreb-homebrew-brew.rb           # Custom upreb for homebrew-brew repo
├── pull-service-center.rb           # Custom pull for service-center repo
└── cc-browser-profiles.rb           # Custom cc for browser-profiles repo
```

Each override script:
1. `require`s the utility modules it needs (`git_commands`, `git_processor`, `cron`, `logging`)
2. Wraps its body in `Logging.run_script` (depth tracking, timing, summary)
3. Runs its custom pre/post logic
4. Calls `GitCommands.<command>(args: ARGV, header: false)` for the common behavior

### Implementation Pattern

**Git command with override support** (`scripts/git-cc` / `scripts/git-upreb`, plain `/bin/sh`):
```sh
dir="${1:-$(git rev-parse --show-toplevel 2>/dev/null || printf .)}"
if [ -n "${PERSONAL_BIN_DIR:-}" ] && [ -z "${_GIT_OVERRIDE_SKIP:-}" ]; then
  basename="$(basename "$(cd "${dir}" && pwd)")"
  for ext in rb sh; do
    override="${PERSONAL_BIN_DIR}/upreb-${basename}.${ext}"
    [ -x "${override}" ] || continue
    # ... run it (rb directly, sh via zsh) from inside ${dir} with _GIT_OVERRIDE_SKIP=1; return its status ...
  done
fi
# ... default implementation ...
```

**Override script example** (`upreb-zen-browser-desktop.rb`):
```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'git_commands'
require 'git_processor'
require 'logging'

Logging.run_script do
  git = GitProcessor.new(dir: Dir.pwd)

  # Custom pre-logic: delete stale tag (git-extras 'delete-tag' removes it locally AND remotely)
  git.run_alias('delete-tag', 'twilight') if git.tag_exists?('twilight')

  # Call common implementation
  GitCommands.upreb(args: ARGV, header: false)
end
```

A `.rb` override is launched with the running interpreter and `--disable-gems` (`[RbConfig.ruby, '--disable-gems', script]`, via `GitOverrides.command_for`) rather than through its `#!/usr/bin/env ruby` shebang (an override that needs a gem must `require 'rubygems'` itself): a mise shim started from a process that was itself started through the shim, in a directory with no pinned Ruby, trips mise's recursion guard and aborts.

### Commands with Override Support

| Command | Override Pattern | Common Implementation |
|---------|------------------|----------------------|
| `upreb` | `upreb-<basename>.rb`/`.sh` | `GitCommands.upreb` |
| `push` | `push-<basename>.rb`/`.sh` | `GitCommands.push` |
| `pull` | `pull-<basename>.rb`/`.sh` | `GitCommands.pull` |
| `cc` | `cc-<basename>.rb`/`.sh` | `GitCommands.cc` (wraps `git cc`); dispatched by `scripts/git-cc` itself -- the `cc` alias is plain `git cc`, with no Ruby wrapper |

### Usage Examples

**Interactive use:**
```bash
cd ~/dev/oss/zen-browser-desktop
git upreb  # Uses upreb-zen-browser-desktop.rb (or .sh) if it exists

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

The remaining shell autoload functions in `${XDG_CONFIG_HOME}/zsh/` (`st`, `count`) support overrides via `dispatch_or_fallback` (`.rb` first, then `.sh`), but they only activate when:
1. The function is called directly by name (e.g., `st` not `git st`)
2. From a context where the autoload function is loaded (interactive shell)

`push`, `pull` and `upreb` are no longer autoload functions: they are aliases for `scripts/git-command.rb`, which does its own lookup via `GitOverrides`. `cc` is an alias of plain `git cc`, whose external subcommand does its own lookup in shell.

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
- Looks for `${PERSONAL_BIN_DIR}/<name>-<basename>.rb` (then `.sh`) for the repo currently being
  processed (`<basename>` = the repo directory's basename).
- If found and executable, execs that script directly (cwd = repo dir, remaining
  args forwarded) **instead of** the original command -- this is what makes a
  `Cron.with_cron_suspended`-wrapped override transparently apply to `push`/`pull`
  through `all push`/`all pull`, exactly as it already did for `cc`/`upreb`.
- If not found, falls back to the original `run-all.rb` behavior: `/bin/zsh -c
  "<command joined>"` in the repo directory.

**Cyclical-dispatch safety net**: before invoking a resolved override script,
`run-all.rb` sets `_GIT_OVERRIDE_SKIP=1` (`GitOverrides::SKIP_ENV_VAR`, the single
variable shared by the git aliases, `GitCommands` and `run-all.rb`) in that
subprocess's environment. If `run-all.rb` is ever invoked again from within that
subprocess tree (e.g. a future override script mistakenly calls `all <cmd>` again),
the inner invocation sees the variable already set and skips its own
override-dispatch entirely -- bounding any accidental recursion to one level
instead of looping.

This makes the alias-level dispatch on `cc`/`upreb` effectively redundant for the
`run-all.rb`/`all` code path specifically (run-all.rb finds and execs the same
override script directly, without ever shelling out to `git cc`/`git upreb` at
all) -- but the alias-level dispatch is still required and still active for a
human running `git cc`/`git upreb` directly at the terminal, outside of
`run-all.rb`.

---
