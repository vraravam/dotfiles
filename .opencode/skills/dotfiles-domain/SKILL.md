---
name: dotfiles-domain
description: Use when working in the dotfiles repository (${HOME}/.config/dotfiles), personal bin (${HOME}/personal/dev/bin), or personal configs (${HOME}/personal/dev/configs). Covers shell scripting rules, Ruby conventions, zsh startup optimization, fresh-install idempotency, antidote plugin manager, and all coding decisions from prior sessions.
---

# Dotfiles Domain Skill

This skill provides context for working in the personal dotfiles repository
and companion script directories.

## Absolute Rules

- **NEVER push to any remote** (`git push`, `git push --force`, `git push --force-with-lease`, or any variant). This is unconditional — no exceptions, no user prompts. Only the user pushes.
- **NEVER commit, amend, or create a PR** unless explicitly requested by the user. This includes `git commit`, `git commit --amend`, and `gh pr create`. Only the user decides when to record history.

## Quick Reference: The Three Directories

| Variable | Path |
|----------|------|
| `$DOTFILES_DIR` | `${HOME}/.config/dotfiles` |
| `$PERSONAL_BIN_DIR` | `${HOME}/personal/dev/bin` |
| `$PERSONAL_CONFIGS_DIR` | `${HOME}/personal/dev/configs` |

## Key Files

| File | Purpose |
|------|---------|
| `files/--HOME--/.shellrc` | Core shell utilities, functions, env vars |
| `files/--HOME--/.aliases` | Higher-level aliases; sources `.shellrc` |
| `files/--ZDOTDIR--/.zshrc` | Interactive zsh config |
| `files/--ZDOTDIR--/.zshenv` | Env vars for all shell types |
| `files/--ZDOTDIR--/.zlogin` | Post-startup work (compilation, etc.) |
| `scripts/fresh-install-of-osx.sh` | Bootstrap: vanilla OS + idempotent re-run |
| `scripts/utilities/logging.rb` | Ruby logging module |
| `scripts/utilities/string.rb` | String color extensions |
| `scripts/utilities/cli_parser.rb` | Ruby CLI option parser |
| `scripts/utilities/hash_ext.rb` | Hash extensions (`deep_sort`) |
| `scripts/utilities/path_utils.rb` | Path utility functions |

## Critical Rules (Never Violate)

1. **`fresh-install-of-osx.sh` must be idempotent** — works on vanilla OS
   AND pre-configured machine. Check `FIRST_INSTALL` env var for first-run-only logic.

2. **Do not use bare `echo`** in scripts — use `info`/`warn`/`success`/`error`/`debug`.

3. **Do not use raw test switches** (`-f`, `-z`, `-n`, etc.) — use `.shellrc` utility functions.

4. **Do not use `.empty?` in Ruby** — use `nil_or_empty?` custom helper.

5. **Do not replace `nil_or_empty?` with `.empty?`** — it is intentional.

6. **Encapsulation**: guards that belong inside a function/file must NOT be
   repeated across multiple files. The `.shellrc` re-source guard is inside
   `.shellrc` itself via `is_shellrc_sourced` sentinel.

7. **Source tightest file**: source `.shellrc` if only `.shellrc` functions
   needed; source `.aliases` if `.aliases` functions needed (it auto-sources
   `.shellrc`). Never source both.

8. **Ruby 2.6 compat**: `$DOTFILES_DIR/scripts/` code must work with system
   Ruby 2.6 (vanilla macOS).

9. **Private naming**: prefix internal/private functions/methods with `_`.

10. **`main` function**: all shell scripts (except `*-common.sh`) must have a
    `main()` function as the entry point.

11. **Quoting**: always quote variable expansions (`"${var}"`). Use single
    quotes for static strings with no variable expansion. Always use `${var}`
    brace notation — never bare `$var`.

12. **`parse_folder_and_switches` API contract**: This function (defined in
    `.aliases`) writes into `folder` and `switches` variables in the caller's
    scope. Autoload functions and shell scripts that call it MUST declare
    `local folder` and `local -a switches` (NOT `local dir`). The function
    name and variable names are part of the public API and cannot be changed
    without breaking all callers. See `files/--XDG_CONFIG_HOME--/zsh/{push,pull,st,cc,count}`
    for usage examples.

## Antidote (Replaces OMZ)

Antidote is the zsh plugin manager (replaced oh-my-zsh):
- Installed via Homebrew.
- `ANTIDOTE_HOME` = `~/Library/Caches/antidote` (macOS-specific).
- Generated bundle file is checked into home git repo.
- `update_antidote_and_regenerate_plugin_bundle` defined in `.shellrc`.
- Run `antidote bundle` in `zsh --no-rcs -c "..."` to avoid ANSI code leaks.
- Guard `--unshallow` with shallow-repo check before calling.
- `ZSH` and `ZSH_CUSTOM` env vars from OMZ era must be unset.

## Cron Split Architecture

Cron functions are split intentionally:

- **`.shellrc`**: `suspend_cron`, `resume_cron` — needed before dotfiles cloned.
- **`.aliases`**: `_create_crontab`, `recron`, higher-level helpers — only
  needed after dotfiles installed.

Scripts that need cron functions: source the tightest file that has them.

## Color / Logging Architecture

Shell color functions (`blue`, `red`, `green`, etc.) apply `${1//${HOME}/~}`
**inline** for performance (avoids a subshell fork). This is intentional — do
not refactor into a separate `replace_home_with_tilde` call inside each color
function.

The same pattern applies in Ruby: color methods on `String` apply the tilde
substitution internally.

Logging functions (`info`, `warn`, `success`) do NOT apply the substitution —
it is applied by the color functions they call.

## `RUBYLIB` Setup

`.shellrc` sets `RUBYLIB` to include `$DOTFILES_DIR/scripts/utilities`. This
allows `require 'logging'` without `require_relative`.

On vanilla OS during fresh-install, `RUBYLIB` may not be set. Scripts that
run early must handle this.

## `.envrc` Architecture

`.envrc` files are evaluated by direnv in a **bash** subshell:
- Source `.shellrc` unconditionally (no `type` guard needed).
- POSIX syntax only — no zsh-specific constructs.
- Functions from `.shellrc` are available after sourcing.

## Shell Formatting Tools

- Shell scripts: `shfmt` (installed via Homebrew). Run `shfmt -w <file>` after
  every edit. No inline ignore directive exists — exclude whole files via
  `.shfmtignore` only (two valid reasons: zsh-only syntax parse failures, or
  shfmt bug with one-liners in loop/push bodies).
- Ruby scripts: `rufo` — run from `$HOME` (uses mise-managed Ruby), NOT from
  `$DOTFILES_DIR` (which is pinned to system Ruby 2.6).

## GitProcessor Pattern: When to Apply Instance-Based Wrappers

The GitProcessor pattern (instance-based API eliminating repetitive parameters)
applies when ALL of these conditions hold:

1. **Common tool** with many subcommands (e.g., git with 20+ operations)
2. **Common flag/parameter** needed on every invocation (e.g., `-C dir`)
3. **Shared state** across multiple operations (e.g., dry_run, error tracking)
4. **Multiple operations per target** (5-10+ calls on the same repository)
5. **Complex error handling** (parsing output, checking state, structured results)

The pattern does NOT apply to:
- Different tools with different flag positions (mise vs direnv)
- Simple 1-2 call operations per target
- Tools with simple exit-code-only error handling
- Operations with no shared state

Example of where it does NOT apply: mise/direnv in `git_workspace.rb` do single
operations per directory with simple error handling. The current pattern
(`system('mise', '-C', dir, 'install')`) is cleaner than wrapping.

---

## Documentation Update Routine

Run this routine **proactively at the end of every session** and **at least
once per day** when multiple sessions occur. Do not wait to be asked.

### Trigger conditions

Run the routine whenever any of the following occurred during the session:

- A new design decision was made or an existing one was revised
- A bug was discovered and fixed (especially if the fix reveals a general rule)
- A new pattern, constraint, or naming convention was established
- A new script or function was added or significantly changed
- An existing rule in the instructions was found to be incorrect or incomplete
- A new adopter-facing workflow step was introduced

### Routing: what goes where

Scan the session context and apply each piece of pertinent information to the
**tightest** file that owns it. Never duplicate the same rule across files —
put it in one place and cross-reference from broader files where needed.

| Type of information | Primary file | Cross-reference if significant |
|---|---|---|
| Shell scripting rule, pattern, or pitfall | `shell-scripting.instructions.md` | `copilot-instructions.md` summary bullets |
| Zsh startup optimisation or startup-path constraint | `zsh-startup.instructions.md` | `copilot-instructions.md` summary bullets |
| Git config alias pattern or delta/diff rule | `git-config.instructions.md` | `copilot-instructions.md` summary bullets |
| Ruby scripting pattern or convention | `ruby-scripting.instructions.md` | — |
| Fresh-install idempotency guard or bootstrap constraint | `fresh-install.instructions.md` | `copilot-instructions.md` if affects general readers |
| Naming convention, global state variable, or sourcing rule | `copilot-instructions.md` (primary) | `TechnicalDeepDive.md` § 2 or § 3 if architectural |
| Architectural explanation (why a design exists) | `TechnicalDeepDive.md` | link from adopter docs if user-visible |
| New or changed script behaviour | `Extras.md` | link to `TechnicalDeepDive.md` for internals |
| Adopter workflow change (fork, upgrade, import/export steps) | `README.md` | `GettingStarted.md` if affects first-run |
| Bug fix or behavioural change with adoption steps | `CHANGELOG.md` under current version | — |
| Inaccuracy found in any doc | Fix in-place in the affected file | Fix all files that carry the same error |

### Process

1. Scan the full session for decisions, fixes, and patterns not yet reflected
   in any doc.
2. For each item, identify the tightest owning file from the routing table.
3. Draft the addition in the style of the surrounding content in that file
   (see the code comment rules in `copilot-instructions.md` § **Code Comments**:
   explain *why*, not what; no temporal language; no changelog phrasing).
4. Apply the edit. If a broader file needs a cross-reference or summary bullet,
   add that too.
5. If the item belongs in `CHANGELOG.md`, add it under the current `### x.y.z`
   version using the `####` sub-section format. Check whether an unpushed commit
   exists (`git log @{u}..HEAD`) before deciding whether to create a new version
   entry or extend the existing one.
5a. **CHANGELOG conciseness rule**: When describing a pattern that applies across
    multiple files, state the pattern once with aggregate metrics (e.g., "95%
    reduction across 16 files"). Only call out individual files if they have
    unique behavior beyond the general pattern. Do NOT list every file when the
    pattern description is sufficient.
5b. **Commit message format**: Use the `####` sub-section goal headings from the
    current CHANGELOG entry as section headers, with bulleted summaries under each.
    Format: Title line (first section header), blank line, then for each section:
    section header, blank line, 2-4 bullet points (`-` prefix), blank line.
    End with `Total: N files changed, X insertions(+), Y deletions(-)` line.
    Omit `Adopting these changes` section — it is not a code change.
    Example structure:
    ```
    Title: First section header from CHANGELOG

    - Key change 1
    - Key change 2

    Second section header

    - Key change 3
    - Key change 4

    Total: N files changed, X insertions(+), Y deletions(-)
    ```
6. After all updates, verify no file now contains a stale or contradicted
   version of the same rule.

### What does NOT belong in documentation

- Changelog-style phrasing in code comments ("Added X to fix Y").
- Temporal language ("currently", "as of this session", "now uses").
- Implementation details that are already self-evident from reading the code.
- Redundant duplication of a rule already present in the tightest file.

### What does NOT belong in CHANGELOG or commit messages

- Updates to AI assistant documentation files (`.github/model-instructions.md`, `.github/instructions/*.instructions.md`, `.opencode/skills/*/SKILL.md`). These are internal development aids, not user-facing changes. Document them only in the files themselves, never in CHANGELOG or commit messages.
