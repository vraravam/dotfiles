---
name: dotfiles-domain
description: Use when working in the dotfiles repository (${HOME}/.config/dotfiles), personal bin (${HOME}/personal/dev/bin), or personal configs (${HOME}/personal/dev/configs). Covers shell scripting rules, Ruby conventions, zsh startup optimization, fresh-install idempotency, antidote plugin manager, and all coding decisions from prior sessions.
---

# Dotfiles Domain Skill

This skill provides context for working in the personal dotfiles repository
and companion script directories.

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
