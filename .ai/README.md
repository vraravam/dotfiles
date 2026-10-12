# AI Assistant Instructions

This repository uses a **tool-agnostic** instruction system in the `.ai/` folder.

## Quick Start

All AI coding assistants (GitHub Copilot, Cursor, Windsurf, Claude Code, OpenCode, etc.) should:
1. Read **[`../AGENTS.md`](../AGENTS.md)** (hard rules + task-to-domain routing table) and **[`instructions.md`](./instructions.md)**.
2. Load the **[`domains/`](./domains/)** file(s) that match the files being edited -- *not* all of them.
3. Consult **[`context.md`](./context.md)** for navigation, debugging, testing and related repos.

## Structure

```
.ai/
├── instructions.md              # Always-loaded entry: domain index, editing + git-state rules
├── context.md                   # Navigation, debugging, testing, related repos, perf snapshot
├── REBASE-AND-REFACTORING-METHODOLOGY.md  # Rebase/backport/branch-chain methodology
├── FEATURE-PARITY-CHECKLIST.md            # Post-rebase verification checklist
│
└── domains/                     # Domain-specific rules (one concern per file)
    ├── changelog.md                        # Changelog entries and commit messages
    ├── character-encoding.md               # ASCII-only requirements
    ├── comment-philosophy.md               # Comment guidelines
    ├── custom-gitignore-maintenance.md     # files/ <-> custom.gitignore sync
    ├── edit-checklist.md                   # Post-edit workflow (always loaded)
    ├── fresh-install.md                    # Bootstrap & setup
    ├── git-config.md                       # Git aliases & config (core)
    ├── git-overrides.md                    # Per-repo overrides & git hooks
    ├── git-workflow.md                     # Staging/commit/branch/rebase rules
    ├── logging-conventions.md              # Logging/color rules
    ├── markdown-blocks.md                  # Copy-paste command blocks in markdown
    ├── path-constants.md                   # Path/env var rules
    ├── ruby-infrastructure.md              # Ruby: Logging/CliParser/EnvVars/requires/structure
    ├── ruby-performance-idioms.md          # Ruby: memoization, hoisting, idioms
    ├── ruby-scripting.md                   # Ruby (core): dual-mode, params, exit points
    ├── ruby-shell-git-io.md                # Ruby: system(), GitProcessor, UTF-8, nil_or_empty?
    ├── script-depth-tracking.md            # Depth tracking
    ├── shell-functions-autoload.md         # Shell: functions, autoload, expansion
    ├── shell-portability-cron.md           # Shell: bash/direnv/cron portability
    ├── shell-scripting.md                  # Shell (core): utilities, template, logging
    ├── ssh-config.md                       # SSH config limitations
    ├── whitespace-rules.md                 # Whitespace rules (always loaded)
    └── zsh-startup.md                      # Startup performance
```

## Context Budget

Context is the scarce resource, so the layout is tuned for loading as little as possible:

- **Always loaded** (about 28 KB, down from about 75 KB): `AGENTS.md`, `instructions.md`, `whitespace-rules.md`, `edit-checklist.md`.
- **Core + topic split**: Ruby, shell and git rules are a core file (read first, 25-45 KB) plus topic files (read only when the task touches the topic). A typical Ruby edit loads the core plus at most one topic instead of one monolithic file.
- **Each domain file declares its scope** (`applyTo`, "Related files") and a "Topic Files" table where it has siblings.
- **When adding a rule**: put it in the narrowest file where it applies; add to a core file only if virtually every edit of that language needs it. Do not restate a rule in `AGENTS.md` -- link to it.

## Periodic Review -- Keep the Context Budget Healthy

Instruction files only grow. Review the `.ai/` layout on a regular cadence (suggested: whenever a
release bumps the minor version, or roughly quarterly) and whenever a single rule addition pushes a
file past a threshold below.

**Measure** (sizes in bytes; about 4 bytes per token):

```zsh
wc -c "${DOTFILES_DIR}/AGENTS.md" "${DOTFILES_DIR}/.ai/instructions.md" "${DOTFILES_DIR}/.ai/domains/"{whitespace-rules,edit-checklist}.md;
wc -c "${DOTFILES_DIR}/.ai/domains/"*.md | sort -rn | head -10;
```

**Thresholds** (a trigger to review, not a hard failure):

| Item | Target | Action when exceeded |
|------|--------|----------------------|
| Always-loaded total (`AGENTS.md`, `instructions.md`, `whitespace-rules.md`, `edit-checklist.md`) | 30 KB or less | Move non-universal sections into an on-demand domain file; replace restated rules with links |
| Any single domain file | 45 KB or less | Split into a core file plus topic files (see the Ruby/shell/git splits for the pattern) |
| `AGENTS.md` | 10 KB or less | Keep only hard rules, the routing table and one-line pointers |

**Checklist for each review:**

1. Re-measure and compare against the thresholds above.
2. Look for rules duplicated across files (grep a distinctive phrase); keep one canonical home and link to it.
3. Look for rules every edit needs that live only in a topic file (promote to core), and rules only rare tasks need that live in an always-loaded or core file (demote to a topic file).
4. Re-check cross-references after any move: every markdown link and anchor resolves, and every `§ Heading` reference names the file that now holds that heading.
5. Keep the routing table in `AGENTS.md`, the index in `instructions.md`, the tree in this README, and the `.opencode/skills/` symlinks (one per domain file, directory name equal to the frontmatter `name`) in sync with the files in `domains/`.
6. Confirm every domain file has `applyTo`, `name` and a "Use when..." `description`, plus a "Related files" or "Topic Files" block where it has siblings.
7. Remove model- or harness-specific guidance; the files must stay usable by any assistant.
8. When a sibling project keeps an adapted copy of these rules (see `context.md` § Related Repositories), check whether the restructuring should be mirrored there.

## File Coverage (via YAML frontmatter)

Each domain file uses `applyTo` patterns (plus `name`/`description` for tools that load files as skills) to specify which files it covers. The authoritative index, with "read when" guidance, is the table in [`instructions.md`](./instructions.md#domain-files).

## Tool-Specific Entry Points

Each AI coding assistant has a minimal redirect file that points here:

- **AGENTS.md-aware tools (OpenCode, Codex, Cursor, etc.)**: `AGENTS.md` (primary entry point)
- **Claude Code**: `CLAUDE.md` (imports `AGENTS.md`) + `.claude/skills` (symlink to `.opencode/skills`)
- **GitHub Copilot**: `.github/copilot-instructions.md` (on-demand pre-task protocol)
- **Cursor**: `.cursorrules`
- **Windsurf**: `.windsurfrules`
- **OpenCode**: `.opencode/opencode.json` `instructions` array (always-on files only) + `.opencode/skills/dotfiles-*/SKILL.md` (on-demand, one skill per domain -- see below)
- **Aider**: `.aider.conf.yml` (if added)
- **Others**: Can read `.ai/` directly

### GitHub-Specific Additions

The `.github/` folder includes Copilot-specific enhancements that complement the tool-agnostic `.ai/` structure:

- **`pull_request_template.md`** - PR checklist for dotfiles changes
- **`CODEOWNERS`** - Repository ownership
- **`agents/`** - Custom review agents for shell and Ruby scripts, invoked by pasting into Copilot Chat (see [agents/README.md](../.github/agents/README.md))

These files follow GitHub conventions but don't duplicate core rules (which remain in `.ai/`).

### OpenCode-Specific Additions

opencode has two loading modes, and this repo deliberately uses both:

- **Always-on** (`.opencode/opencode.json` `instructions` array): only `instructions.md` plus the small, genuinely cross-cutting domains (`whitespace-rules.md`, `edit-checklist.md`) are force-loaded into every session. These apply to virtually every edit regardless of language, so eager-loading them is cheap and worth the guaranteed availability.
- **On-demand** (`.opencode/skills/dotfiles-*/SKILL.md`): every other domain file under `domains/` (one skill per file, named `dotfiles-<file-name>`) plus the rebase methodology docs (`dotfiles-rebase-methodology`, covering `REBASE-AND-REFACTORING-METHODOLOGY.md` and, by cross-reference, `FEATURE-PARITY-CHECKLIST.md`) are exposed as skills, loaded only when opencode recognizes the current task matches. Each `SKILL.md` is a **symlink** into the corresponding `.ai/` file, not a copy -- one physical file, multiple tool-recognized frontmatter keys (`applyTo` for Copilot/Cursor/Windsurf, `name`/`description` for opencode).

opencode also has three review-only subagents under `.opencode/agents/` (`shell-script-reviewer.md`, `ruby-script-reviewer.md`, `security-reviewer.md`), ported from `.github/agents/*.agent.md`. Unlike the Copilot versions (manually pasted into chat), these are real, natively invocable subagents (`mode: subagent`, `edit`/`bash` permissions denied) that the primary agent can delegate a review to directly via the `task` tool.

These files follow opencode conventions but don't duplicate core rules (the skills are symlinks, not copies).

## Design Principles

1. **Single source of truth** - All rules live in `.ai/`, nowhere else
2. **No duplication** - Tool configs are minimal redirects
3. **Model-agnostic** - Standard markdown + YAML frontmatter
4. **Discoverable** - Top-level `.ai/` folder is obvious
5. **Maintainable** - Update once, applies to all tools
6. **Future-proof** - Easy to add new AI assistants
7. **Alphabetical ordering** - File/folder lists in documentation are alphabetically ordered for easy scanning and maintenance

## For AI Assistants

When working on this repository:

1. **Read `AGENTS.md` and `instructions.md` first** -- do not preload every file in `.ai/`
2. **Load the domain file(s) that apply** to the file you're editing (core file first, then only the relevant topic file)
3. **Follow the rules exactly** - they encode specific, tested reasoning
4. **Verify your changes** - Each domain has verification steps
5. **Don't duplicate rules** - Reference `.ai/` files, don't copy them

## For Human Contributors

See the [main README](../README.md) for:
- How to adopt/customize these rules
- Decision-making philosophy (startup speed → maintainability → POSIX → zsh)
- Common debugging commands

## Questions?

The `.ai/` convention is custom to this repository but follows patterns used by:
- Aider (`CONVENTIONS.md` / `CONTRIBUTING.md`)
- Cursor (`.cursorrules` / `.cursor/`)
- Windsurf (`.windsurfrules`)
- GitHub Copilot (`.github/` folder)

Each tool can read markdown files and follow cross-references. The `.ai/` folder centralizes all instructions in one place.
