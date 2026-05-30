---
applyTo: "**/.gitconfig,**/custom.gitattributes,**/add-upstream-git-config.sh"
---

# Git Configuration Instructions

## Shell Scripting Rules Inside Aliases

These rules mirror the shell scripting rules in `shell-scripting.instructions.md`
and apply to every `!sh -c` or `!f()` alias body.

### Always Quote Variables

Always quote variable expansions to prevent word-splitting on values that could
contain spaces:

```ini
# BAD — unquoted, breaks on paths with spaces
my-alias = !sh -c 'git -C $1 command' -

# Good — quoted
my-alias = !sh -c 'git -C "${1:-.}" command' -
```

### Brace Notation

Always use `${var}` brace notation — never bare `$var` (except single-character
special params `$?`, `$#`, `$@`, `$$`, etc.):

```ini
# BAD
my-alias = "!f() { echo $branch; }; f"

# Good
my-alias = "!f() { echo \"${branch}\"; }; f"
```

### Guard Positional Parameters with Defaults

Under `set -u` (or any strict mode), bare `$1` fails when no argument is given.
Always provide a default with `${1:-}` (empty default) or a meaningful fallback:

```ini
# BAD — fails if no argument supplied
my-alias = !sh -c 'git checkout $1' -

# Good — empty default, safe when no arg
my-alias = !sh -c 'git checkout "${1:-}"' -

# Good — meaningful fallback (current dir)
my-alias = !sh -c 'git -C "${1:-.}" status' -
```

### Single vs Double Quotes

Use single quotes for static strings with no variable expansion inside the alias
value. Use double quotes only when the string contains variable references:

```ini
# Good — static string, single quotes
my-alias = !sh -c 'printf "no args\n"' -

# Good — variable expansion, double quotes required
my-alias = "!f() { printf '%s\n' \"${1:-}\"; }; f"
```

---

## `~/.gitconfig` Aliases

Aliases that use shell commands must use `!sh -c '...' -` to properly handle
the `-C <dir>` flag:

```ini
# BAD — does not honour -C
my-alias = !git some-command

# Good — honours -C via $1 defaulting to current dir
my-alias = !sh -c 'git -C "${1:-.}" some-command' -
```

For aliases that accept additional arguments, pass them through with `"$@"`:

```ini
pull-unshallow = !sh -c 'cd "${1:-.}" && shift && git fetch --unshallow "$@" && git pull "$@"' -
```

### `--` Trailer and `$0` vs `$1`

The trailing `-` after the shell string sets `$0` (the script name) to `-`.
Positional arguments from the git invocation then start at `$1`. This is the
correct convention for `!sh -c '...' -` aliases:

```ini
# $1 = first user-supplied arg (or "." if no arg given)
my-alias = !sh -c 'git -C "${1:-.}" command' -
```

Do NOT use `$0` for user arguments — `$0` is always `-` (the script name
passed as the trailing argument to `sh -c`).

### `!f()` Named Function Pattern

For multi-step logic, use a named function rather than a bare inline
expression. This improves readability and avoids quoting complexity:

```ini
my-cmd = "!f() { git -C \"${1:-.}\" command \"$@\"; }; f"
```

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

## `git sci` (Smart Commit — Non-Interactive)

`git sci "<message>"` is fully non-interactive. It takes a commit message as
its argument and decides whether to create a new commit or amend the last one:

- Aborts if nothing is staged (`git diff --cached --quiet`).
- Amends (`git amq`) if already ahead of remote and not diverged.
- Creates a new commit (`git ci "<message>"`) otherwise.

Use `git diff --cached --quiet` to check for staged changes — not
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

## `git size`

`git size` is human-triggered (not in the startup hot path), so subshell
invocations are acceptable. Quote all command substitutions to handle paths
containing spaces:

```ini
size = !printf '==> Size of repository at %s: %s\n' "$(git rev-parse --show-toplevel)" "$(du -sh "$(git rev-parse --show-toplevel)/.git" | cut -f1)"
```

## `git cc` and `git rfc` — Reflog Expiry Without Stash Loss

`git reflog expire --all` covers `refs/stash` and will discard stashes.
**Never use `--all`** in `reflog expire`. Instead, enumerate refs explicitly
using `git for-each-ref`:

```ini
# BAD — discards stashes
rfc = reflog expire --expire=now --all

# Good — preserves refs/stash; excludes refs/tags (tags have no reflogs in any
# repo — git only maintains reflogs for HEAD and branches — passing them always
# produces "reflog could not be found" errors)
rfc = "!f() { refs=$(git for-each-ref --format='%(refname)' refs/heads refs/remotes); [ -n \"${refs}\" ] && git reflog expire --expire=now --expire-unreachable=now --stale-fix ${refs}; }; f"
```

The same rule applies inside `git cc` — the `reflog expire` step must use
`git for-each-ref` enumeration of `refs/heads` and `refs/remotes` only. `refs/tags`
must be excluded — tags have no reflogs in any repo (git only maintains reflogs for
`HEAD` and branches), and passing them to `git reflog expire` always produces
"reflog could not be found" errors for every tag.

## `.gitattributes`

`install-dotfiles.rb` copies `custom.gitattributes` to `.gitattributes` in the
appropriate directory. Resolution when both files exist as real files: on `FIRST_INSTALL`
the destination wins; otherwise the newer mtime wins (repo source wins on a tie).
Prefer editing `custom.gitattributes` in the repo; if you edit `.gitattributes` directly,
ensure its mtime is newer before re-running `install-dotfiles.rb`.

Binary file types must be marked binary:

```gitattributes
*.defaults  binary
*.zwc       binary
```
