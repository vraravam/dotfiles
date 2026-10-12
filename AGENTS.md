# Agent Quick Reference

Entry point for any AI coding agent. This file is deliberately short: it holds the hard rules
and a routing table. Detailed rules live in `.ai/` and are loaded on demand -- read only the
files that match the task.

## Instruction Architecture

- **Always read**: this file, [`.ai/instructions.md`](.ai/instructions.md), and
  [`.ai/domains/whitespace-rules.md`](.ai/domains/whitespace-rules.md) /
  [`.ai/domains/edit-checklist.md`](.ai/domains/edit-checklist.md) before editing code or config.
- **Read on demand**: the domain file(s) matching the files you are touching (table below).
  Each domain file starts with its scope and a list of related files; the big ones (Ruby, shell,
  git) have a core file plus topic files -- read the core first, then only the topic you need.
- **Reference**: [`.ai/context.md`](.ai/context.md) (navigation, debugging, testing, related repos),
  [`.ai/README.md`](.ai/README.md) (layout and tool entry points).
- Rules apply to code in `${DOTFILES_DIR}`, `${PERSONAL_BIN_DIR}`, and `${PERSONAL_CONFIGS_DIR}`.
- **Maintenance**: when adding or moving rules, or on the periodic cadence, follow
  [`.ai/README.md`](.ai/README.md) § Periodic Review (size thresholds, dedupe, cross-reference checks).

### Routing Table

| If the task touches... | Read (under `.ai/domains/`) |
|------------------------|-----------------------------|
| Any Ruby script | `ruby-scripting.md`, then as needed `ruby-infrastructure.md` (Logging/CliParser/EnvVars/requires), `ruby-shell-git-io.md` (system/GitProcessor/UTF-8), `ruby-performance-idioms.md` |
| Any shell script, `.shellrc`, `.aliases`, `.envrc` | `shell-scripting.md`, then as needed `shell-functions-autoload.md`, `shell-portability-cron.md` |
| Zsh startup files (`.zshenv`, `.zshrc`, `.zlogin`, autoload functions) | `zsh-startup.md` (startup-impact check is mandatory) |
| Logging/color output, depth tracking, path constants | `logging-conventions.md`, `script-depth-tracking.md`, `path-constants.md` |
| `.gitconfig`, git aliases, `scripts/git-*`, `.gitattributes` | `git-config.md` |
| Per-repo overrides (`upreb-<basename>.*`), git hooks | `git-overrides.md` |
| Staging, committing, branching, rebasing | `git-workflow.md`, `changelog.md` (commit messages), `../REBASE-AND-REFACTORING-METHODOLOGY.md` |
| `fresh-install-of-osx.sh`, `install-dotfiles.rb`, bootstrap scripts | `fresh-install.md` |
| Adding/removing files under `files/` | `custom-gitignore-maintenance.md` |
| SSH config | `ssh-config.md` |
| Markdown with copy-paste command blocks | `markdown-blocks.md` |
| Comments, non-ASCII characters | `comment-philosophy.md`, `character-encoding.md` |

**CRITICAL -- apply fixes everywhere**: any refactoring, formatting, or pattern fix identified in one
location MUST be applied to **all matching files** across the three directories above. Search first
(`grep -r "pattern" ${DOTFILES_DIR} ${PERSONAL_BIN_DIR} ${PERSONAL_CONFIGS_DIR}`), then edit.

**Related repos**: `git-remote-gpg-encrypt` carries its own trimmed copy of the Ruby rules, and
`homebrew-tap` pins its release tag. When a Ruby rule or tool-release change is made here, check
whether an adapted version belongs there -- see `.ai/context.md` § Related Repositories.

## Git State Management -- NEVER Modify Without Permission

**DEFAULT WORKFLOW: the user reviews and stages changes manually.**

1. Make the requested edits.
2. Show `git status` / `git diff`.
3. **STOP.** Do not stage, commit, or otherwise change git state.

Prohibited without explicit permission: `git add`, `commit`, `reset`, `restore --staged`,
`checkout`, `switch`, `push`, `rebase`, `merge`, `stash`, `rm`, and similar state-changing
commands. Permission is **one-time, for that one instruction only** -- never blanket, never carried
into later requests or sessions. Details: `domains/git-workflow.md`.

## Critical Commands (Run After Every Edit)

**Shell scripts**:
```zsh
zsh -n file.sh                    # Syntax check
shfmt -w file.sh                  # Format (check .shfmtignore first)
rm -f file.sh.zwc                 # Delete bytecode cache
chmod +x file.sh                  # Ensure executable
```

**Ruby scripts**:
```zsh
/usr/bin/ruby -c file.rb          # Syntax (Ruby 2.6 compat required)
rufo file.rb                      # Format
```

**All files** (except `.md`): ends with exactly one newline, no trailing blank lines, no trailing
whitespace -- verification and fix commands in `domains/whitespace-rules.md`.

## Startup-Time Check -- Mandatory for Zsh Startup Files

For any change to `.shellrc`, `.aliases`, `.zshenv`, `.zshrc`, `.zlogin`, autoload functions, or other
code run during shell startup: verify there is no startup-time regression and report old-vs-new
numbers. Starting Ruby on the startup path costs ~100ms -- guard it with a pure-shell freshness
check. See `domains/zsh-startup.md` § Startup-Impact Verification (Mandatory).

## Decision-Making Priority Order

When choices conflict, this order wins:

1. **Startup speed** (for the zsh hot path)
2. **Maintainability** (readability, DRY, clear intent)
3. **POSIX compatibility** (when scripts run in bash/direnv)
4. **Zsh built-ins** (when they don't conflict with #1-3)

Document the tradeoff in a comment when priorities conflict.

## Common Agent Mistakes (one-liners; follow the link for the full rule)

1. **`&&` under `set -e`** -- a standalone `A && B` whose `A` is *expected* to be false triggers the
   ERR trap. Use `if A; then B; fi`. Safe exception: `A && B || C` where `C` returns 0.
   See `shell-scripting.md` § `&&` as Conditional.
2. **Ruby scripts are dual-mode** -- `module X; extend self; def run(...)` returning a boolean (never
   `exit`), plus an `if __FILE__ == $PROGRAM_NAME` CLI block. Call other scripts via
   `require_relative` + `Mod.run`, not a subprocess. See `ruby-scripting.md` § Dual-Mode.
3. **Never hardcode paths** -- shell `${DOTFILES_DIR}`, `${PERSONAL_BIN_DIR}`, `${XDG_CONFIG_HOME}`;
   Ruby `EnvVars::XDG_CONFIG_HOME.join(...)`. Defined in `files/--HOME--/.shellrc` and
   `scripts/utilities/env_vars.rb`. See `path-constants.md`.
4. **No subshell forks on the startup hot path** -- use `${PWD:t}` not `$(basename ...)`, the cached
   `is_arm`, the `zsh/stat` module. See `zsh-startup.md` § No Subshell Forks.
5. **Per-repo git overrides** -- `push`/`pull`/`cc`/`upreb` dispatch to
   `${PERSONAL_BIN_DIR}/<command>-<basename>.rb` (or `.sh`; `.rb` wins) via
   `GitOverrides.script_for`. Override scripts use `Logging.run_script` and
   `GitCommands.<cmd>(args: ARGV, header: false)`. See `git-overrides.md`.
6. **Bootstrap functions live in `.shellrc`, not `.aliases`** -- anything needed before Ruby or the
   dotfiles repo exists: `clone_repo_into`, `suspend_cron`/`resume_cron`, logging functions,
   `is_file`/`is_directory`/`nil_or_empty`. Ruby delegates to them via
   `zsh -c "source ~/.shellrc && clone_repo_into ..."`.
7. **UTF-8 file reading in Ruby** -- use `Core.read_lines_utf8` / `Core.each_line_utf8`, never bare
   `File.readlines` / `File.foreach` (US-ASCII under cron breaks on em dashes). See
   `ruby-shell-git-io.md` § UTF-8 File Reading.
8. **Whitespace rules after every non-`.md` edit** -- `domains/whitespace-rules.md`.
9. **Fresh install must be idempotent** -- every section has a guard that skips finished work;
   supports vanilla-OS (`FIRST_INSTALL=1`) and pre-configured modes. See `fresh-install.md`.
10. **Logging auto-indents** -- never add manual leading spaces to `info`/`Logging.info` output;
    indentation follows `_DOTFILES_SCRIPT_DEPTH`. See `script-depth-tracking.md`.

## Repository Structure (Quick Map)

```
~/.config/dotfiles/
├── files/
│   ├── --HOME--/          # Symlinked to ~/ (Brewfile, .shellrc, .gitconfig)
│   ├── --ZDOTDIR--/       # Zsh config (.zshenv, .zshrc, .zlogin)
│   └── --XDG_CONFIG_HOME--/zsh/  # Autoload functions
├── scripts/
│   ├── utilities/         # Shared Ruby modules (logging*.rb, env_vars.rb, env_lite.rb, git_processor.rb, ...)
│   ├── fresh-install-of-osx.sh    # Bootstrap entry point
│   ├── install-dotfiles.rb        # Symlink/copy manager
│   └── capture-prefs.rb           # Preferences export/import
└── .ai/                   # AI instruction files (tool-agnostic)
```

**Key paths**:
- `${DOTFILES_DIR}` = `~/.config/dotfiles` (this repo)
- `${PERSONAL_BIN_DIR}` = `~/personal/dev/bin` (user scripts, not in repo)
- `${PERSONAL_CONFIGS_DIR}` = `~/personal/dev/configs` (sensitive configs, not in repo)
- `${XDG_CONFIG_HOME}` = `~/.config`
- `${ZDOTDIR}` = `~/.config/zsh`

Testing patterns, debugging commands and performance numbers: `.ai/context.md`.

## When to Ask Questions

Ask ONLY if the repo cannot answer: undocumented team conventions, branch/PR/release expectations,
or missing setup prerequisites. Do NOT ask about anything covered in `.ai/`, standard shell/Ruby/git
conventions, or the README/Adoption/TechnicalDeepDive docs.
