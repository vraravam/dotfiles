# Dotfiles Repository - AI Coding Assistant Instructions

## Project Overview

Personal macOS configuration management system using shell scripts (zsh/bash), Ruby utilities, and git-managed dotfiles.

**Tech Stack:**
- **Shell**: zsh (primary), bash (compatibility for direnv)
- **Scripting**: Ruby 2.6+ (system Ruby compatibility)
- **Version Control**: git with custom aliases and hooks
- **Package Management**: Homebrew, antidote (zsh plugins), mise (runtime versions)
- **macOS Integration**: defaults, plist manipulation, login items, cron

---

## PRE-TASK PROTOCOL -- LOAD ONLY WHAT THE TASK NEEDS

Read these before any code change:

1. [`AGENTS.md`](../AGENTS.md) -- hard rules and the task-to-domain routing table
2. [`.ai/instructions.md`](../.ai/instructions.md), [`.ai/domains/whitespace-rules.md`](../.ai/domains/whitespace-rules.md), [`.ai/domains/edit-checklist.md`](../.ai/domains/edit-checklist.md)

Then read **only** the domain file(s) matching the files you will edit (see the routing table in
`AGENTS.md`). Large domains have a core file (read first) plus topic files (read only when the task
touches that topic). Do NOT read every file under `.ai/` -- that wastes context and buries the
rules that matter.

When reading a long file, read it in sections and make sure you reach the end; if a read was cut
off, continue from where it stopped before relying on it.

---

## CRITICAL RULES

- **Not following instructions = task failure**
- **Existing code may not follow current standards** — never use existing code as template; always follow instruction files
- **Before editing any file**, load the matching domain file(s) (all under `.ai/domains/`):
  - `**/*.sh`, `**/.shellrc`, `**/.aliases` -> `shell-scripting.md` (core); topic files `shell-functions-autoload.md` / `shell-portability-cron.md` as needed
  - `**/*.rb` -> `ruby-scripting.md` (core); topic files `ruby-infrastructure.md` / `ruby-shell-git-io.md` / `ruby-performance-idioms.md` as needed
  - `**/zsh/**`, zsh startup files -> `zsh-startup.md`
  - `**/.gitconfig`, `**/git/**` -> `git-config.md`; per-repo overrides and hooks -> `git-overrides.md`
- **Before editing any file**, check for uncommitted changes with `git status`. Never overwrite uncommitted changes without asking for confirmation.

---

## Testing

- **Syntax validation**: `zsh -n <file>`, `ruby -c <file>` (mandatory before considering task complete)
- **Format validation**: `shfmt`, `rufo`
- **Manual testing**: Required on current machine for all changes
- **Fresh install testing**: Required for changes to bootstrap/install-dotfiles

Every task that modifies shell/Ruby code MUST include syntax validation before the task is considered complete. Never present code as "done" without running syntax checks.

---

## Comments

- Follow comment philosophy in `.ai/domains/comment-philosophy.md`
- Explain WHY, not WHAT (code is self-documenting)
- Document tradeoffs and non-obvious decisions
- Never add unnecessary comments to generated code

---

## Security

- Never log, expose in responses, or store credentials, tokens, or PII in plain text
- Never commit secrets, API keys, or tokens to git
- Use Keybase and/or the encrypted-backup mechanism (`gpg` + `git bundle`, see `TechnicalDeepDive.md` § 14) for sensitive file storage
- SSH keys managed via keychain, not plaintext
- Use environment variables, Keybase, or the macOS Keychain for secrets

---

## Git State Management

**NEVER stage, commit, or push without explicit user permission.**

Default workflow: User reviews and stages changes manually.

After making edits:
1. ✅ Make the requested edits to files
2. ✅ Show `git status` or `git diff` to display what changed
3. ❌ **STOP** - Do NOT stage, commit, or modify git state
4. ✅ Let the user review changes and stage manually

See `.ai/domains/git-workflow.md` § Git State Management Rules for complete details.

---

## Agent Mode

After completing all code changes:
1. Run syntax checks: `zsh -n <files>`, `ruby -c <files>`
2. Fix all syntax errors before presenting output
3. Report what was changed and what needs manual verification

---

**COMPLETE INSTRUCTIONS**: All detailed instructions are in the [`.ai/`](../.ai/) folder.

Read [`.ai/README.md`](../.ai/README.md) for the complete file structure, domain-specific rules, and repository context.
