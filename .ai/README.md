# AI Assistant Instructions

This repository uses a **tool-agnostic** instruction system in the `.ai/` folder.

## Quick Start

All AI coding assistants (GitHub Copilot, Cursor, Windsurf, Claude Code, etc.) should read:
1. **[`instructions.md`](./instructions.md)** - Main entry point with general rules
2. **[`domains/`](./domains/)** - Domain-specific rules
3. **[`context.md`](./context.md)** - Navigation aid, performance workflow, debugging guidance

## Structure

```
.ai/
├── instructions.md              # Main entry point
│                                # - General editing rules
│                                # - Git state management
│                                # - Decision-making philosophy
│
├── context.md                   # Domain context
│                                # - Repository structure and navigation
│                                # - Performance optimization workflow
│                                # - Known issues and debugging commands
│
├── REBASE-AND-REFACTORING-METHODOLOGY.md  # Rebase/backport/branch-chain methodology
├── FEATURE-PARITY-CHECKLIST.md            # Post-rebase verification checklist
│
└── domains/                     # Domain-specific rules
    ├── character-encoding.md               # Cross-language ASCII-only requirements
    ├── comment-philosophy.md               # Cross-language comment guidelines
    ├── custom-gitignore-maintenance.md     # files/ <-> custom.gitignore sync
    ├── edit-checklist.md                   # Cross-language edit workflow
    ├── fresh-install.md                    # Bootstrap & setup
    ├── git-config.md                       # Git aliases & config
    ├── logging-conventions.md              # Cross-language logging/color rules
    ├── path-constants.md                   # Cross-language path/env var rules
    ├── ruby-scripting.md                   # All Ruby scripts
    ├── script-depth-tracking.md            # Cross-language depth tracking
    ├── shell-scripting.md                  # All shell scripts
    ├── whitespace-rules.md                 # Cross-language formatting/whitespace rules
    └── zsh-startup.md                      # Startup performance
```

## File Coverage (via YAML frontmatter)

Each domain file uses `applyTo` patterns to specify which files it covers:

| Domain | Applies To |
|--------|------------|
| **character-encoding** | All cross-language scripts and configuration files (ASCII-only requirements) |
| **comment-philosophy** | All cross-language scripts (comment guidelines) |
| **custom-gitignore-maintenance** | `files/**`, `scripts/install-dotfiles.rb`, `files/--HOME--/custom.gitignore` |
| **edit-checklist** | All cross-language scripts and configuration files (edit workflow) |
| **fresh-install** | `fresh-install-of-osx.sh`, `install-dotfiles.rb`, setup/backup scripts |
| **git-config** | `.gitconfig`, git aliases, `.gitattributes` |
| **logging-conventions** | All cross-language scripts (logging/color rules) |
| **path-constants** | All cross-language scripts (path/env var rules) |
| **ruby-scripting** | `**/*.rb` |
| **script-depth-tracking** | All cross-language scripts using deferred error collection |
| **shell-scripting** | `**/*.sh*`, `.shellrc`, `.aliases`, `.envrc`, `*.zsh*`, zsh autoload functions |
| **whitespace-rules** | All files (cross-language formatting/whitespace rules) |
| **zsh-startup** | `.zshenv`, `.zshrc`, `.zprofile`, `.zlogin`, zsh config directory |

## Tool-Specific Entry Points

Each AI coding assistant has a minimal redirect file that points here:

- **GitHub Copilot**: `.github/copilot-instructions.md` (enhanced with pre-task checklist)
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

- **Always-on** (`.opencode/opencode.json` `instructions` array): only `instructions.md` plus the small, genuinely cross-cutting domains (`whitespace-rules.md`, `edit-checklist.md`, `character-encoding.md`, `comment-philosophy.md`) are force-loaded into every session. These apply to virtually every edit regardless of language, so eager-loading them is cheap and worth the guaranteed availability.
- **On-demand** (`.opencode/skills/dotfiles-*/SKILL.md`): every other domain (`shell-scripting`, `ruby-scripting`, `zsh-startup`, `fresh-install`, `git-config`, `path-constants`, `logging-conventions`, `script-depth-tracking`, `custom-gitignore-maintenance`) plus the rebase methodology docs (`dotfiles-rebase-methodology`, covering `REBASE-AND-REFACTORING-METHODOLOGY.md` and, by cross-reference, `FEATURE-PARITY-CHECKLIST.md`) are exposed as skills, loaded only when opencode recognizes the current task matches. Each `SKILL.md` is a **symlink** into the corresponding `.ai/` file, not a copy -- one physical file, multiple tool-recognized frontmatter keys (`applyTo` for Copilot/Cursor/Windsurf, `name`/`description` for opencode).

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

1. **Read all files in `.ai/` first** (especially `instructions.md`)
2. **Check which domain applies** to the file you're editing
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
