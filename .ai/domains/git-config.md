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
| `pull-unshallow` / `fetch-unshallow` | extra flags | `git -C <path> pull-unshallow` |
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

Used in: `pull-unshallow`, `fetch-unshallow`

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
pull-unshallow = "!f() { \
  git rev-parse --is-shallow-repository | /usr/bin/grep -q true && \
    git pull --unshallow \"$@\" || \
    git pull \"$@\"; \
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

- `git fetch-unshallow`: fetch and unshallow if repo is shallow. Guards against
  `--unshallow` on already-complete repos (which fails).
- `git pull-unshallow`: pull and unshallow in one step.

```ini
fetch-unshallow = !sh -c 'git -C "${1:-.}" rev-parse --is-shallow-repository | grep -q true && git -C "${1:-.}" fetch --unshallow || git -C "${1:-.}" fetch' -
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
