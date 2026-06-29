# AI Assistant Instructions

This repository uses a **tool-agnostic** instruction system in the `.ai/` folder.

## Quick Start

All AI coding assistants (GitHub Copilot, Cursor, Windsurf, Claude Code, etc.) should read:
1. **[`instructions.md`](./instructions.md)** - Main entry point with general rules
2. **[`domains/`](./domains/)** - Domain-specific rules
3. **[`context.md`](./context.md)** - Historical insights, optimization patterns, debugging guidance

## Structure

```
.ai/
├── instructions.md              # Main entry point
│                                # - General editing rules
│                                # - Whitespace requirements
│                                # - Git state management
│                                # - Decision-making philosophy
│
├── context.md                   # Domain context
│                                # - Historical optimizations
│                                # - Performance patterns
│                                # - Coding lessons learned
│                                # - Debugging commands
│
└── domains/                     # Domain-specific rules
    ├── character-encoding.md    # Cross-language ASCII-only requirements
    ├── comment-philosophy.md    # Cross-language comment guidelines
    ├── edit-checklist.md        # Cross-language edit workflow
    ├── fresh-install.md         # Bootstrap & setup
    ├── git-config.md            # Git aliases & config
    ├── logging-conventions.md   # Cross-language logging/color rules
    ├── path-constants.md        # Cross-language path/env var rules
    ├── ruby-scripting.md        # All Ruby scripts
    ├── script-depth-tracking.md # Cross-language depth tracking
    ├── shell-scripting.md       # All shell scripts
    ├── whitespace-rules.md      # Cross-language formatting/whitespace rules
    └── zsh-startup.md           # Startup performance
```

## File Coverage (via YAML frontmatter)

Each domain file uses `applyTo` patterns to specify which files it covers:

| Domain | Applies To |
|--------|------------|
| **character-encoding** | All cross-language scripts and configuration files (ASCII-only requirements) |
| **comment-philosophy** | All cross-language scripts (comment guidelines) |
| **edit-checklist** | All cross-language scripts and configuration files (edit workflow) |
| **fresh-install** | `fresh-install-of-osx.rb`, `install-dotfiles.rb`, setup/backup scripts |
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

- **GitHub Copilot**: `.github/copilot-instructions.md`
- **Cursor**: `.cursorrules`
- **Windsurf**: `.windsurfrules`
- **OpenCode**: `.opencode/skills/dotfiles-domain/SKILL.md`
- **Aider**: `.aider.conf.yml` (if added)
- **Others**: Can read `.ai/` directly

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
3. **Follow the rules exactly** - they're refined over 3+ years
4. **Verify your changes** - Each domain has verification steps
5. **Don't duplicate rules** - Reference `.ai/` files, don't copy them

## For Human Contributors

See the [main README](../README.md) for:
- How to adopt/customize these rules
- Decision-making philosophy (startup speed → maintainability → POSIX → zsh)
- Historical optimization milestones
- Common debugging commands

## Questions?

The `.ai/` convention is custom to this repository but follows patterns used by:
- Aider (`CONVENTIONS.md` / `CONTRIBUTING.md`)
- Cursor (`.cursorrules` / `.cursor/`)
- Windsurf (`.windsurfrules`)
- GitHub Copilot (`.github/` folder)

Each tool can read markdown files and follow cross-references. The `.ai/` folder centralizes all instructions in one place.
