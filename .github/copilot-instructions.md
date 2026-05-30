# Dotfiles Repository — Copilot Instructions

## Absolute Rules

- **NEVER push to any remote** (`git push`, `git push --force`, `git push --force-with-lease`, or any variant). This is unconditional — no exceptions, no user prompts. Only the user pushes.

This is a personal macOS dotfiles repository. The codebase contains zsh startup
files, shell utility scripts, Ruby scripts, and a macOS fresh-install bootstrap
script. All coding decisions documented here come from accumulated design
decisions across development sessions.

## Repository Layout

```
files/
  --HOME--/        -> symlinked to $HOME (contains .shellrc, .aliases, etc.)
  --ZDOTDIR--/     -> symlinked to $ZDOTDIR (contains .zshrc, .zshenv, .zlogin)
  --XDG_CONFIG_HOME--/zsh/  -> cached homebrew shellenv, antidote bundle, etc.
  --PERSONAL_PROFILES_DIR--/ -> .envrc for direnv
scripts/
  fresh-install-of-osx.sh   # Bootstrap installer — runs on vanilla OS AND pre-configured machine
  utilities/                # Shared Ruby utilities (logging.rb, string.rb, cli_parser.rb, hash_ext.rb, path_utils.rb)
  *.rb                      # Ruby scripts
  *.sh                      # Shell scripts
```

### `files/` Naming Convention — `--VAR--` Directories

Subdirectories under `files/` use the pattern `--ENV_VAR_NAME--`. `install-dotfiles.rb`
interpolates each directory name by resolving the env var it names (e.g. `--HOME--` →
`$HOME`, `--ZDOTDIR--` → `$ZDOTDIR`) and symlinks all files found inside into the
resolved directory. This means:

- Add a new dotfile under `files/--HOME--/` to have it symlinked into `$HOME`.
- Add a new config file under `files/--XDG_CONFIG_HOME--/zsh/` to have it placed in
  `$XDG_CONFIG_HOME/zsh/`.
- Plain subdirectory names without the `--VAR--` pattern are also valid — they resolve
  literally from `/` (e.g. `files/etc/` → `/etc/`). Prefer the `--VAR--` convention
  for any path that may differ between machines (e.g. home directory, XDG dirs), since
  hardcoded paths break portability.

Exception: files matching `custom.git*` (e.g. `custom.gitattributes`) are **copied**
rather than symlinked, because git does not handle symlinks well for its own core config.
Resolution when both the source and the destination exist as real files:
- `FIRST_INSTALL` set: pre-existing destination always wins — moved into dotfiles repo,
then copied back.
- Otherwise: the file with the **newer mtime** wins. On a tie, the dotfiles repo wins.
Prefer editing the `custom.git*` source file in the dotfiles repo. If you edit the
destination directly, ensure its mtime is newer before re-running `install-dotfiles.rb`.

The three primary script directories referenced throughout:
- `$DOTFILES_DIR`     = `${HOME}/.config/dotfiles`
- `$PERSONAL_BIN_DIR` = `${HOME}/personal/dev/bin`
- `$PERSONAL_CONFIGS_DIR` = `${HOME}/personal/dev/configs`

Except for adding/updating entries into the `CHANGELOG.md`, all actions need to be
performed in all relevant files in all the above 3 folders and their nested children.

---

## Decision-Making Philosophy

When suggesting or making any change to shell or zsh scripts, apply these
priorities in order. A higher priority always wins over a lower one; document
the tradeoff in a comment when they conflict.

1. **Startup speed** — never introduce a subshell fork (`$(...)`) or external
   process call in the startup hot path. Prefer zsh built-ins and cached values.
   A POSIX-compatible change that regresses startup time is not acceptable.

2. **Maintainability** — code must be understandable without deep zsh expertise.
   When a performance optimisation degrades readability, add a concise comment
   explaining what it does and why it is written that way.

3. **POSIX compatibility** — prefer POSIX syntax where it does not conflict with
   the above. This keeps scripts portable and safe in bash contexts (e.g.
   `.envrc` files evaluated by direnv). When POSIX syntax would require a
   subshell fork or harm readability, use zsh built-ins instead and document why.

4. **Zsh built-ins** — when POSIX syntax is insufficient or would require a
   subshell fork, use zsh built-in syntax (parameter expansions,
   `(( $+functions[...] ))`, `${(j::)arr}`, etc.) and document why the
   zsh-specific syntax was chosen.

Note: 
1. Priorities 3 and 4 only apply to zsh scripts. `.envrc` files are
evaluated by direnv in a bash subshell and must use POSIX syntax exclusively.
2. Similarly, the git aliases section might use sh or bash and should be
POSIX syntax exclusively.

---

## Core Design Principles

### Idempotency — Fresh Install

`fresh-install-of-osx.sh` MUST work **both on a vanilla macOS** and a
**fully pre-configured machine** without errors. All logic must be idempotent.

- `FIRST_INSTALL` env var is set only on a vanilla OS run.
- Check `FIRST_INSTALL` before operations that only make sense on a fresh machine.
- `.shellrc` is not available at the start of fresh-install on a vanilla OS;
  it is downloaded via `curl` and then sourced.
- `.aliases` is not available until the dotfiles repo is cloned. Functions
  needed before that clone must live in `.shellrc`, not `.aliases`.

**Every section must have a guard that pre-empts the whole section** when its
work is already complete. The guard is the first thing in the section — before
any logging or setup. This keeps re-runs on a pre-configured machine fast: only
sections with actual work to do execute their logic. See
`fresh-install.instructions.md` for guard patterns.

### `.shellrc` vs `.aliases` — Why Functions Are Split

`.shellrc` is downloaded via `curl` early in `fresh-install` on a vanilla OS,
**before** the dotfiles repo is cloned and before `install-dotfiles.rb` has run
to create symlinks. It must therefore remain **lean and small** — only the
functions genuinely needed during that early bootstrap window belong here.

`.aliases` is only available after the dotfiles repo is cloned and
`install-dotfiles.rb` has created the symlink from the repo into `$HOME`.
Everything that is not needed in the pre-clone window should live in `.aliases`,
not `.shellrc`.

Decision rule when placing a new function:
- **`.shellrc`** — required if the function is called during a vanilla OS
  fresh-install **before `install-dotfiles.rb` creates the `.aliases` symlink**.
  The precise boundary is `install-dotfiles.rb` in `main()` of
  `fresh-install-of-osx.sh`. Within a vanilla OS run, `$DOTFILES_DIR/scripts/`
  exists and is in PATH from the moment the dotfiles repo is cloned, but
  `~/.aliases` does not exist until `install-dotfiles.rb` finishes — so scripts
  in `$DOTFILES_DIR/scripts/` that are invoked in this window (between repo
  clone and `install-dotfiles.rb`) must also source `.shellrc`, not `.aliases`.
  Examples that belong here: `suspend_cron`, `resume_cron`, `clone_repo_into`,
  `keep_sudo_alive`, `set_ssh_folder_permissions`, `eval_shellenv`,
  `load_zsh_configs`, `print_usage`, `get_git_config_value`.
  Note: `add-upstream-git-config.sh` is invoked inside `_clone_dot_files_repo`
  (before `install-dotfiles.rb`), so any function it uses must be in `.shellrc`.
- **`.aliases`** — everything else; available once dotfiles are symlinked.
  This includes:
  - Functions only used by scripts in `$PERSONAL_BIN_DIR` or
    `$PERSONAL_CONFIGS_DIR` — those directories never exist on a vanilla OS
    before the dotfiles repo is cloned, so they are never in the boot path.
  - Functions used by scripts in `$DOTFILES_DIR/scripts/` that are only called
    **after** `install-dotfiles.rb` runs (e.g. `post-brew-install.sh`,
    `osx-defaults.sh`, `capture-prefs.sh`, `setup-login-item.sh`, `run-all.sh`,
    `software-updates-cron.sh`, `recreate-repo.sh`).
  - zsh autoload functions (the scripts under `$ZDOTDIR/functions/` and
    `$XDG_CONFIG_HOME/zsh/`) — these are only ever invoked in an interactive
    zsh session, well after all dotfiles are in place.
  The sourcing choice for all of the above is governed solely by the
  "source the tightest file" rule, not by the vanilla OS constraint.

Note on `.envrc` files: `.envrc` files are evaluated by direnv in a **bash**
subshell. They must source `.shellrc` (not `.aliases`) because `.aliases`
contains extensive zsh-only syntax (`(N.)` globs, `:h`, `:A`, `((@on))`,
`(($+...))` etc.) that is not bash-compatible. This is a **bash compatibility**
constraint, not a hotpath or startup-speed concern. Any function that is called
from a `.envrc` file and is not already in `.shellrc` for bootstrap reasons must
be kept in `.shellrc` for bash-compat reasons — add a comment on that function
explaining this (see `set_ssh_folder_permissions` for the pattern).

Avoid the temptation to put convenience functions in `.shellrc` just because
`.shellrc` is always loaded. Every extra function added to `.shellrc`
unnecessarily increases the payload of the initial `curl` download on a vanilla
OS and adds to shell startup time.



Guards that belong inside a single function/file must NOT be repeated across
multiple files. Example: the re-source guard for `.shellrc` is implemented
**inside** `.shellrc` itself (sentinel function `is_shellrc_sourced`). All
other scripts source `.shellrc` unconditionally and add a comment:
`# Re-source guard is inside .shellrc itself — safe to call unconditionally.`

The same pattern applies to `.aliases` with `is_aliases_sourced`.

Exception: `fresh-install-of-osx.sh` may have an explicit guard because it
runs before the sentinel function is available.

### Source the Tightest File

Each script must source only the tightest file that provides the needed
functions:
- If only `.shellrc` functions are needed, source `.shellrc`.
- If `.aliases` functions are needed (and `.aliases` sources `.shellrc`
  internally), source `.aliases`.
- Never source `.aliases` AND `.shellrc` in the same script — `.aliases`
  already sources `.shellrc`.

---

## Shell Scripting Rules

> Full rules and script skeleton are in
> `.github/instructions/shell-scripting.instructions.md`.
> The summary below covers the most critical points.

### Utility Functions Over Raw Test Conditions

**Never** use raw POSIX test switches (`-f`, `-z`, `-n`, `-d`, `-e`, `-x`,
`-L`, `-s`) directly in scripts. Always use the named utility functions defined
in `.shellrc`:

| Raw test | Utility function |
|----------|-----------------|
| `-f "$x"` | `is_file "$x"` |
| `-d "$x"` | `is_directory "$x"` |
| `-L "$x"` | `is_symbolic_link "$x"` |
| `-x "$x"` | `is_executable "$x"` |
| `-s "$x"` | `is_non_empty_file "$x"` |
| `-z "$x"` | `is_zero_string "$x"` |
| `-n "$x"` | `is_non_zero_string "$x"` |
| `[ -d "$x/.git" ]` | `is_git_repo "$x"` |
| `mkdir -p "$x"` | `ensure_dir_exists "$x"` |

Note: `is_git_repo` checks **two** conditions internally (non-empty string AND
`.git` directory present). Add a comment when calling it to note that the else
branch is not a simple negation.

Additional utility functions defined in `.shellrc` — use these rather than
inline equivalents:

| Function | Purpose |
|----------|---------|
| `is_directory_empty "$x"` | True if directory exists and contains no entries |
| `command_exists "$x"` | True if `$x` exists as a command, function, alias, or builtin (checks 4 hash tables) |
| `is_running_in_tty` | True if stdout is a TTY or `FORCE_COLOR` is set (allows color output in CI/direnv) |
| `is_zsh` | True when running inside zsh (guards zsh-only code in files sourced by bash) |
| `is_macos` / `is_linux` | OS detection — use instead of `uname` subshell forks |
| `is_arm` | True on Apple Silicon — uses `$ARCH`, no subshell |
| `replace_home_with_tilde "$x"` | Substitutes `$HOME` with `~` in a string for display (inline, no fork) |

Exception: `.envrc` files are evaluated by direnv in a bash subshell; they
cannot use zsh utility functions. Use POSIX syntax in `.envrc` files.

Exception: `fresh-install-of-osx.sh` early-boot code that runs before
`.shellrc` is sourced must use raw tests with explanatory comments.

### Array Utility Functions

Use named utility functions instead of inline `${#arr[@]}` checks:
- `is_empty_array arr` instead of `[[ ${#arr[@]} -eq 0 ]]`
- `is_non_empty_array arr` instead of `[[ ${#arr[@]} -gt 0 ]]`
- `join_array separator arr` for joining array elements

### Logging — Never Use Bare `echo` in Scripts

Use the logging functions from `.shellrc` (`info`, `success`, `warn`, `error`,
`debug`, `section_header`, `section_header2`, `step_start`/`step_end`). Bare
`echo` is only acceptable for `usage` output and code that runs before
`.shellrc` is sourced.

Color functions apply `${1//${HOME}/~}` inline (no subshell fork). Logging
functions do NOT apply the substitution themselves — it happens inside the color
functions they call.

### `set -euo pipefail`

All shell scripts use `set -euo pipefail`. Guard positional parameters with
`${1:-}`. Use `grep -q ... || true` in pipelines to avoid SIGPIPE under
`set -o pipefail`.

### Quoting and Variable References

- **Always quote variables**: use `"${var}"` in any context where the value
  could contain spaces. Unquoted variables break on filenames with spaces.
- **Single quotes for static strings**: use `'literal'` when there is no
  variable expansion. Use double quotes only when expanding variables or
  needing escape sequences.
- **Always use `${var}` brace notation**: never bare `$var`. Braces
  unambiguously delimit the variable name and prevent accidental
  concatenation bugs (e.g. `"${name}_suffix"` vs `"$name_suffix"` which
  looks up `$name_suffix`).
- Exception: single-character special params (`$?`, `$#`, `$@`, `$$`, etc.)
  do not need braces.

### Key Structural Rules

- Use `getopts` for all option parsing (not manual `$1/$2` checking).
- Entry point must be a `main()` function; library scripts (`*-common.sh`) must
  NOT have a `main` call.
- Internal helpers: prefix with `_`.
- `source` vs `load_file_if_exists`: use `load_file_if_exists` after `.shellrc`
  is sourced; use raw `[[ -f ]]` + `source` before `.shellrc` is available.

### No Aliases in Non-Interactive Scripts

Zsh disables alias expansion in non-interactive shells (scripts, cron jobs,
`zsh -c`, `zsh -lsc`). **Never call an alias by name inside a script** — use
the underlying command or function it expands to. Also replace any
`command_exists <alias>` guard with a check against the real executable:

```zsh
# BAD — aliases not expanded in non-interactive shells
home pull
oss upreb
if command_exists bcg; then
  bcg | grep ...

# Good — direct equivalents
FOLDER="${HOME}" FILTER='.bin|.dotfiles|zsh|mise' MAXDEPTH=5 run-all.sh git pull
FOLDER="${PROJECTS_BASE_DIR}/oss" MAXDEPTH=4 run-all.sh git upreb
if command_exists brew; then
  # 'bcg' alias (brew outdated --greedy) is not expanded in non-interactive shells.
  brew outdated --greedy | grep ...
```

Add a comment at each call site noting why the alias is not used.

---

## Ruby Scripting Rules

> Full rules and script skeleton are in
> `.github/instructions/ruby-scripting.instructions.md`.
> The summary below covers the most critical points.

### Ruby Version Compatibility

`install-dotfiles.rb` and `utilities/` scripts run under the **system Ruby
(2.6)** during a vanilla OS fresh-install. All Ruby code must be compatible
with Ruby 2.6. Do NOT use homebrew-managed Ruby for `$DOTFILES_DIR` scripts.

### Key Rules

- Use `map`/`select`/`reduce` (not `collect`/`filter`/`inject`).
- Use `Array()` to guard potential nil values before iteration.
- Use `nil_or_empty?` — do NOT replace with `.empty?` (unsafe on nil).
- Use `File::SEPARATOR` (not hardcoded `/`).
- Do not `require` transitively — push requires down to direct users.
- Do NOT use `Kernel.warn` — use `Logging.warn` instead.
- Use `CliParser` from `cli_parser.rb` for all CLI option parsing.

---

## Zsh Startup Performance Rules

> Full rules are in `.github/instructions/zsh-startup.instructions.md`.
> The summary below covers the most critical points.

- Avoid `$(...)` in the startup hot path — prefer zsh parameter expansion.
- Use `(( $+functions[funcname] ))` (not `type`) for function existence checks
  in zsh. Exception: `.envrc` and bash contexts must use `type`.
- Cache `brew shellenv` output to a file; source from cache.
- Pre-compile startup scripts to `.zwc` in `.zlogin`. Use `delete_caches` to
  remove `.zwc` files — do NOT chmod/chown them.
- **Antidote**: `ANTIDOTE_HOME` uses `~/Library/Caches`; bundle file checked
  into home git repo; source with `load_file_if_exists`; run `antidote bundle`
  in `zsh --no-rcs -c "..."` to avoid ANSI leaks; guard `--unshallow`.
- Path arrays (`fpath`, `path`, etc.) use `typeset +x` — not `export`.

---

## Git Configuration Rules

> Full rules are in `.github/instructions/git-config.instructions.md`.

### Aliases in `~/.gitconfig`

- Aliases that use shell features must use `!sh -c '...' -` or `!git` prefix.
- For `-C <dir>` support: `!sh -c 'git -C "${1:-.}" ...' -`.
- The trailing `-` sets `$0`; user args start at `$1`. Never use `$0` for user args.
- For multi-step logic, use `!f()` named function pattern: `"!f() { ...; }; f"`.
- `git sci`: smart commit, **non-interactive** — takes a message arg; amends (`git amq`) if ahead of remote and not diverged, otherwise creates a new commit (`git ci`). Aborts if nothing staged. Use `git diff --cached --quiet` (not locale-dependent `grep "to unstage"`).
- `git cc` / `git rfc`: **never use `--all`** in `reflog expire` — it discards stashes. Always enumerate refs explicitly with `git for-each-ref refs/heads refs/remotes` only. `refs/tags` must be excluded — tags have no reflogs in any repo (git only maintains reflogs for `HEAD` and branches), and passing them to `git reflog expire` always produces "reflog could not be found" errors for every tag.
- `fetch.fsckObjects = false` enforced in antidote bundle repo git configs
  (ohmyzsh, fast-syntax-highlighting) — `fetch` only, not `receive`/`transfer`.

---

## Crontab / Cron Handling

Cron functions are split across two files:

1. **`.shellrc`** — `suspend_cron` and `resume_cron`: needed before the dotfiles
   repo is cloned (used in `fresh-install` for vanilla OS).
2. **`.aliases`** — `_create_crontab`, `recron`, and higher-level cron helpers:
   only needed after dotfiles are installed.

Comments in both files must explain this split for future maintainers.

Exit/error traps in scripts that call `suspend_cron` must call `resume_cron`
(via trap) if `CRON_BACKUP_FILE` is present.

Scripts that involve cron operations (e.g., `cc-browser-profiles.sh`) should
source `.aliases` (not `.shellrc`) since the cron functions they need are
defined in `.aliases`.

---

## Starship Prompt Rules

- Git state (rebase/cherry-pick/merge) must be shown in the `custom.git_state`
  section in red.
- `custom.git_state` works for both reftable and classic `.git/HEAD` formats.
- No leading space before the chevron when `custom.git_state` has no output
  (use `when` condition to suppress the module when inactive).
- `ignore_timeout = true` in custom commands that may be slow.

---

## Code Comments

Comments in code files must be written for **future reference**, not as a
narrative of the current change. A reader should be able to understand _why_
a decision was made — not reconstruct what commit introduced it.

Rules:
- Explain **why**, not what the code does (the code already shows the what).
- Document non-obvious constraints, tradeoffs, or design decisions that would
  otherwise force a future reader to re-derive them (e.g. "antidote.zsh
  references BASH_VERSION which is unset in zsh under `set -u`").
- Never phrase a comment as a changelog entry ("Added X to fix Y" or
  "Changed to use Z in this commit"). That context belongs in the git commit
  message, not in the source file.
- Avoid temporal language (`now`, `currently`, `as of this change`) — comments
  must remain accurate across future edits without needing updates themselves.
- Do NOT add a comment purely to satisfy the instruction to comment; only add
  one when it genuinely helps a future reader.

---

## EditorConfig / Formatting

- Indentation: **2 spaces** for all file types.
- Always trim trailing whitespace (except markdown).
- Always end files with a final newline.
- Trim consecutive blank lines (except markdown).
- `max_line_length` is **off** for all file types.

### Shell Formatting

Run `shfmt -w <file>` after every edit to a shell script. See
`shell-scripting.instructions.md` for the full rules on `.shfmtignore` and
the two valid reasons for excluding a file.

**Check `.shfmtignore` before running `shfmt`.** If the file is listed there,
do NOT run `shfmt` on it — skip formatting entirely. Running `shfmt` on an
excluded file corrupts intentional one-liners (e.g. `while true; do ...; done`
expanded into misaligned multi-line form with no way to suppress it inline).

### Ruby Formatting

Run `cd "${HOME}" && rufo <file>` after every edit to a Ruby script. Run from
`$HOME` (not `$DOTFILES_DIR`) — `$DOTFILES_DIR` is pinned to system Ruby 2.6
which cannot run rufo.

---

## `RUBYLIB` / `$LOAD_PATH`

`.shellrc` sets `RUBYLIB` to include `$DOTFILES_DIR/scripts/utilities` and other
utility directories. This allows Ruby scripts to `require 'logging'` (etc.)
without `require_relative`.

On a vanilla OS during `fresh-install`, `RUBYLIB` may not be set yet. The
`install-dotfiles.rb` script (which runs early) must not depend on `RUBYLIB`
pointing to the utilities directory — it manually prepends the utilities path
to `$LOAD_PATH` via `$LOAD_PATH.unshift` at the top of the file, before any
`require` calls.

---

## `install-dotfiles.rb` Behaviour

### Adopt-Existing-File

If a real file (not a symlink) already exists at a symlink target, `install-dotfiles.rb`
**moves the existing file into the repo** (making it the new dotfiles source) before
creating the symlink. This "adopt" behaviour means existing configs are never silently
lost. The `--force` flag overrides this and deletes the existing file instead.

### SSH `Include` Line

After symlinking, `install-dotfiles.rb` ensures the line
`Include "${SSH_CONFIGS_DIR}/global_config"` is present in `~/.ssh/config`. This
is a post-symlink SSH setup step — do not add it manually or add a duplicate guard
elsewhere.

---

## Keybase / SSH

`ensure_keybase_logged_in` and `build_keybase_repo_url` are defined in
`.aliases` (not `.shellrc`). They are only needed by scripts in `$HOME` and
`$PERSONAL_PROFILES_DIR` — never before the dotfiles repo is cloned. Keeping
them in `.aliases` is correct; moving them to `.shellrc` is not needed.

`GIT_SSH_COMMAND` env var for SSH key selection is set at the top of
`fresh-install` when `FIRST_INSTALL` is true, because `~/.gitconfig` (and thus
`core.sshCommand`) does not exist yet. It must be **unset immediately after
`install-dotfiles.rb` runs**, since that script symlinks `~/.gitconfig` into
place — from that point on `core.sshCommand` is active and `GIT_SSH_COMMAND`
would silently override it for the remainder of the run.

---

## `dispatch_or_fallback` — Per-Project Script Overrides

Autoload functions (`push`, `pull`, `cc`, `upreb`, etc.) support per-project
overrides via `dispatch_or_fallback` (defined in `.shellrc`):

```zsh
push() { dispatch_or_fallback push _push "$@"; }
```

When called, `dispatch_or_fallback` looks for
`${PERSONAL_BIN_DIR}/<cmd>-<cwd-basename>.sh`. If the file exists and is
executable, it is sourced (running in the current shell). Otherwise the default
`_<cmd>` function is called. Scripts in `$PERSONAL_BIN_DIR` follow the naming
convention `<cmd>-<project-dir-name>.sh`.

Similarly, `launch_me`, `debug_me`, and `build_me` look for
`${PERSONAL_BIN_DIR}/launch-${PWD##*/}.sh`, `debug-${PWD##*/}.sh`, and
`build-${PWD##*/}.sh` respectively.

---

## `_SHARED_REPO_DIRS` Convention

`resurrect_tracked_repos` (in `.aliases`) populates `_SHARED_REPO_DIRS` — a
module-level array — after running its expensive `find` traversal. Functions
called in the same logical operation (`install_mise_versions`,
`allow_all_direnv_configs`) check for this array before running their own
traversal, avoiding duplicating the `find` cost. The array is `unset` at the
end of `resurrect_tracked_repos` so it does not persist across independent
invocations.

When adding new functions that need to traverse all repo dirs, check for
`_SHARED_REPO_DIRS` first:

```zsh
if (( ${+_SHARED_REPO_DIRS} )) && is_non_empty_array _SHARED_REPO_DIRS; then
  all_dirs=("${_SHARED_REPO_DIRS[@]}")
else
  # ... run find traversal ...
fi
```

---

## CHANGELOG

Each new CHANGELOG entry must use the output of `git describe --tags` (run from
`$DOTFILES_DIR`) as the section header. This ensures the version number always
matches the most recent git tag:

```zsh
git describe --tags   # e.g. "3.1" — use this as the ### header
```

- Add the new entry at the **top** of `CHANGELOG.md`, above all existing entries.
- Use `### <version>` as the section heading (e.g. `### 3.1`).
- Each bullet should be scoped with `*[file or component]*` and describe the
  change succinctly — what was done and why, not how.

### Commit Message Style

- Write commit messages in the **past tense** (e.g. "Replaced X with Y", "Fixed
  bug in Z") — not imperative mood ("Replace X", "Fix Z").
- The message should describe what changed, not what to do.
