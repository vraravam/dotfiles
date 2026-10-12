# Dotfiles Repository — Tool-Agnostic AI Instructions

Main entry point for all AI coding assistants working on this repository. Tool-specific configs
(`AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`, `.cursorrules`, `.windsurfrules`)
are minimal redirects that point here or to `AGENTS.md`.

**Tool-agnostic design**: these files are plain markdown with YAML frontmatter (`applyTo`, `name`,
`description`). Any assistant can parse them. They assume only generic capabilities -- read a file,
edit a file, run a shell command, search -- and do not depend on any particular model or harness.
See [`README.md`](./README.md) for the folder layout.

## Loading Strategy

1. **Always loaded**: this file, [`whitespace-rules.md`](./domains/whitespace-rules.md), and
   [`edit-checklist.md`](./domains/edit-checklist.md).
2. **Load on demand**: the domain file(s) matching the files being edited (table below). Large domains
   are split into a *core* file (read first) plus *topic* files (read only when the task touches the topic).
3. **Do not preload everything.** Reading every file wastes context and buries the rules that matter.

## Domain Files

All domain-specific rules are in [`domains/`](./domains/):

| Domain | File | Read when editing / doing |
|--------|------|---------------------------|
| Ruby (core) | [`ruby-scripting.md`](./domains/ruby-scripting.md) | Any `.rb` file: dual-mode, parameters, exit points, Ruby 2.6 compatibility |
| Ruby infrastructure | [`ruby-infrastructure.md`](./domains/ruby-infrastructure.md) | `Logging`, `CliParser`, `EnvVars`, colors, `require` ordering, module/class structure |
| Ruby shell/git/IO | [`ruby-shell-git-io.md`](./domains/ruby-shell-git-io.md) | `system()`/escaping, `GitProcessor`, UTF-8 file reading, `nil_or_empty?` |
| Ruby performance | [`ruby-performance-idioms.md`](./domains/ruby-performance-idioms.md) | Memoization, frozen constants, hoisting, collection/string performance, idioms |
| Shell (core) | [`shell-scripting.md`](./domains/shell-scripting.md) | Any `.sh`/`.zsh`/`.bash`, `.shellrc`, `.aliases`: utilities, template, logging, `&&` safety |
| Shell functions | [`shell-functions-autoload.md`](./domains/shell-functions-autoload.md) | Autoload functions, `local`/`unset`, positional parameters, expansion operators |
| Shell portability | [`shell-portability-cron.md`](./domains/shell-portability-cron.md) | bash/direnv compatibility, `.envrc`, cron, globs, caches, shebangs |
| Zsh startup | [`zsh-startup.md`](./domains/zsh-startup.md) | `.shellrc`, `.aliases`, `.zshenv`, `.zshrc`, `.zprofile`, `.zlogin` (includes the mandatory startup-impact verification) |
| Git config | [`git-config.md`](./domains/git-config.md) | `.gitconfig`, git aliases, `scripts/git-*`, `.gitattributes` |
| Git overrides/hooks | [`git-overrides.md`](./domains/git-overrides.md) | Per-repo override scripts, folder-context dispatch, global git hooks |
| Git workflow | [`git-workflow.md`](./domains/git-workflow.md) | Staging, committing, branching, rebasing, pre-commit verification |
| Changelog | [`changelog.md`](./domains/changelog.md) | Changelog entries, commit messages, amending commits |
| Fresh install | [`fresh-install.md`](./domains/fresh-install.md) | `fresh-install-of-osx.sh`, `install-dotfiles.rb`, `osx-defaults.sh`, `setup-login-item.rb`, `capture-prefs.rb`, `resurrect-repositories.rb` |
| Logging conventions | [`logging-conventions.md`](./domains/logging-conventions.md) | Logging/color output in any script |
| Script depth tracking | [`script-depth-tracking.md`](./domains/script-depth-tracking.md) | Nested-script indentation, deferred error collection |
| Path constants | [`path-constants.md`](./domains/path-constants.md) | Any path/env-var reference |
| Custom gitignore | [`custom-gitignore-maintenance.md`](./domains/custom-gitignore-maintenance.md) | Files under `files/`, `install-dotfiles.rb`, `custom.gitignore` |
| SSH config | [`ssh-config.md`](./domains/ssh-config.md) | SSH config files (no variable expansion) |
| Markdown blocks | [`markdown-blocks.md`](./domains/markdown-blocks.md) | Markdown with copy-paste command blocks |
| Comments | [`comment-philosophy.md`](./domains/comment-philosophy.md) | Writing or changing code comments |
| Character encoding | [`character-encoding.md`](./domains/character-encoding.md) | ASCII-only requirement for scripts and config |
| Edit checklist | [`edit-checklist.md`](./domains/edit-checklist.md) | Post-edit workflow (always) |
| Whitespace | [`whitespace-rules.md`](./domains/whitespace-rules.md) | Post-edit whitespace checks (always) |

Also: [`context.md`](./context.md) (navigation, debugging, testing, related repos),
[`REBASE-AND-REFACTORING-METHODOLOGY.md`](./REBASE-AND-REFACTORING-METHODOLOGY.md) and
[`FEATURE-PARITY-CHECKLIST.md`](./FEATURE-PARITY-CHECKLIST.md) (long-running branch work).

## Editing Rules

- Read a file before editing it. Prefer targeted edits over whole-file rewrites; a rewrite must not
  lose the executable bit (see [Executable Permission](#executable-permission-rule--mandatory-for-scripts)).
- Ruby scripts must stay compatible with **Ruby 2.6** (system Ruby on vanilla macOS).
- After every edit, run the [edit checklist](./domains/edit-checklist.md).

### Whitespace Rules — Mandatory for All Edits

**After every edit to any file (except Markdown `.md` files), the file MUST pass all three whitespace checks** (ends with exactly one newline, no trailing blank lines, no trailing whitespace on any line).

See [`domains/whitespace-rules.md`](./domains/whitespace-rules.md) for the complete rules, verification commands, fix commands, and exceptions -- this is the single source of truth; do not duplicate it here.

### Executable Permission Rule — Mandatory for Scripts

After creating or editing a shell script (`.sh`, `.zsh`, `.bash`) or Ruby script (`.rb`) that is executed directly, ensure it has executable permission (`chmod +x`). This covers scripts in `${DOTFILES_DIR}/scripts/`, `${PERSONAL_BIN_DIR}/`, and autoload functions in `${XDG_CONFIG_HOME}/zsh/`. Library files that are only `source`d or `require`d do not need it (but it does no harm).

Check before editing; restore after if the editing method rewrote the file:

```zsh
[[ -x path/to/script.sh ]] && echo "executable" || echo "NOT executable"
find <dir> \( -name "*.sh" -o -name "*.rb" \) ! -perm +111 -type f   # list scripts missing +x
```

## Git State Management — Mandatory Summary

**DO NOT modify Git state (staging area, commits, branches, remotes) without explicit permission from the user.**

The user reviews and stages changes manually. After making edits: show `git status` / `git diff`,
then **STOP**. Prohibited without explicit permission: `git add`, `commit`, `reset`,
`restore --staged`, `checkout`, `switch`, `push`, `rebase`, `merge`, `stash`, `rm`, `branch -d/-D`,
`tag`, `cherry-pick`, `revert`, `clean`, `mv`. Permission is one-time for the single instruction
given -- never blanket, never carried over to later requests or sessions.

Full staging/commit/branch/rebase rules and the pre-commit verification: [`git-workflow.md`](./domains/git-workflow.md).
Commit messages and changelog entries: [`changelog.md`](./domains/changelog.md).
