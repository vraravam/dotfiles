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

## PRE-TASK CHECKLIST — MANDATORY FILE READING PROTOCOL

Before ANY code changes, verify:
- [ ] All applicable instruction files read COMPLETELY
- [ ] Report line counts to user
- [ ] Last line of every file confirmed present in tool output

**NOT OPTIONAL. BLOCKING REQUIREMENT.**

### How to read instruction files

**Problem**: Large files (500+ lines) are silently truncated when using high endLine values.

**Solution**: Read in manageable chunks and verify completeness.

1. Run `wc -l <file>` in the terminal to get the EXACT line count.
2. Read in chunks of 200 lines max:
   - `read_file(startLine=1, endLine=200)`
   - `read_file(startLine=201, endLine=400)`
   - Continue until all lines read
3. After all chunks, verify the LAST LINE of the file appeared in tool output.
4. Report to user: "Read `<filename>`: `<N>` lines in `<K>` chunks. Last line confirmed."

**NEVER use endLine=99999 — it silently truncates and you will miss rules.**

**If the last line is NOT in tool output, the read is INCOMPLETE. Keep reading.**

---

## CRITICAL RULES

- **Not following instructions = task failure**
- **Existing code may not follow current standards** — never use existing code as template; always follow instruction files
- **Before editing any file**, check if it matches an instruction file's `applyTo` pattern:
  - `**/*.sh`, `**/.shellrc`, `**/.aliases` → MUST read `shell-scripting.md` first
  - `**/*.rb` → MUST read `ruby-scripting.md` first
  - `**/zsh/**` → MUST read `zsh-startup.md` first
  - `**/.gitconfig`, `**/git/**` → MUST read `git-config.md` first
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

- Follow comment philosophy in `comment-philosophy.md`
- Explain WHY, not WHAT (code is self-documenting)
- Document tradeoffs and non-obvious decisions
- Never add unnecessary comments to generated code

---

## Security

- Never log, expose in responses, or store credentials, tokens, or PII in plain text
- Never commit secrets, API keys, or tokens to git
- Use Keybase for sensitive file storage
- SSH keys managed via keychain, not plaintext
- Use environment variables or Keybase for secrets

---

## Git State Management

**NEVER stage, commit, or push without explicit user permission.**

Default workflow: User reviews and stages changes manually.

After making edits:
1. ✅ Make the requested edits to files
2. ✅ Show `git status` or `git diff` to display what changed
3. ❌ **STOP** - Do NOT stage, commit, or modify git state
4. ✅ Let the user review changes and stage manually

See `git-config.md` § Git State Management Rules for complete details.

---

## Agent Mode

After completing all code changes:
1. Run syntax checks: `zsh -n <files>`, `ruby -c <files>`
2. Fix all syntax errors before presenting output
3. Report what was changed and what needs manual verification

---

**COMPLETE INSTRUCTIONS**: All detailed instructions are in the [`.ai/`](../.ai/) folder.

Read [`.ai/README.md`](../.ai/README.md) for the complete file structure, domain-specific rules, and repository context.
