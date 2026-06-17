# Dotfiles Repository — Tool-Agnostic AI Instructions

## Quick Reference to Detailed Rules

All domain-specific rules are in [`domains/`](./domains/):

| Domain | File | Coverage |
|--------|------|----------|
| Character encoding | [`character-encoding.md`](./domains/character-encoding.md) | All cross-language scripts and configuration files (ASCII-only requirements) |
| Edit checklist | [`edit-checklist.md`](./domains/edit-checklist.md) | All cross-language scripts and configuration files (edit workflow) |
| Fresh install | [`fresh-install.md`](./domains/fresh-install.md) | `fresh-install-of-osx.sh`, `install-dotfiles.rb`, `post-brew-install.rb`, `osx-defaults.sh`, `setup-login-item.rb`, `capture-prefs.rb`, `resurrect-repositories.rb` |
| Git config | [`git-config.md`](./domains/git-config.md) | `.gitconfig`, git aliases, `.gitattributes` |
| Logging conventions | [`logging-conventions.md`](./domains/logging-conventions.md) | All cross-language scripts (logging/color rules) |
| Path constants | [`path-constants.md`](./domains/path-constants.md) | All cross-language scripts (path/env var rules) |
| Ruby scripting | [`ruby-scripting.md`](./domains/ruby-scripting.md) | All `.rb` files |
| Script depth tracking | [`script-depth-tracking.md`](./domains/script-depth-tracking.md) | All cross-language scripts using deferred error collection |
| Shell scripting | [`shell-scripting.md`](./domains/shell-scripting.md) | All `.sh`, `.zsh`, `.bash`, `.shellrc`, `.aliases`, `.envrc`, zsh autoload functions |
| Zsh startup | [`zsh-startup.md`](./domains/zsh-startup.md) | `.zshenv`, `.zshrc`, `.zprofile`, `.zlogin`, zsh config directory |

**Tool-agnostic design**: These files use standard markdown with YAML frontmatter (`applyTo` patterns).
Any AI assistant can parse them. See [`README.md`](./README.md) for details on the `.ai/` folder convention.

---

## About This File

This is the main entry point for all AI coding assistants working on this repository.
Tool-specific configs (`.github/copilot-instructions.md`, `.cursorrules`, `.windsurfrules`, etc.)
are minimal redirects that point here.

---

## General Mapping

| Copilot Tool | GPT Tool | Notes |
|--------------|----------|-------|
| `apply_patch` | `apply_patch` | Both editors use the same Git‑style patch tool. The GPT
| `read` / `write` | `read` / `write` | `write` replaces any direct file manipulation such as `cat
| `edit` | `edit` | `edit` is the primary file‑edit tool for GPT. When a change is
| `glob` / `grep` | `glob` / `grep` | The same command set is used for searching.

## Editing Rules

- Use **`apply_patch`** for line‑based changes that you want to be part of a Git commit.  The GPT model can also use **`write`** for creating new files or performing wholesale rewrites, but it must read the file first with `read`.
- When you need to **read** a file for inspection or for building a patch, call the `read` tool.  GPT must **not** edit files it hasn't read.
- For **small, incremental edits** that do not require a patch (e.g., adding a comment), `edit` is sufficient.

### Whitespace Rules — Mandatory for All Edits

**After every edit to any file (except Markdown `.md` files), the file MUST pass all three whitespace checks:**

#### Check 1: File Must End with Newline
Every file must end with exactly one newline character (`\n`, hex `0a`).

**Verification:**
```zsh
# Check if file ends with newline
tail -c 1 <file> | od -An -tx1 | grep -q '0a' || echo "Missing final newline"
```

**Why:** POSIX requires text files to end with a newline. Most tools expect this.

#### Check 2: No Trailing Blank Lines
The file must not have any blank lines at the end after the last line of content.

**Verification:**
```zsh
# Check if file has trailing blank lines (empty lines at end)
tail -n 1 <file> | grep -q '^$' && echo "Has trailing blank lines"
```

**Fix:**
```zsh
# Remove all trailing blank lines while preserving final newline
sed -i '' -e :a -e '/^\s*$/d;N;ba' <file>
```

**Why:** Trailing blank lines create noise in diffs and are flagged by formatters.

#### Check 3: No Trailing Whitespace on Any Line
No line in the file may end with spaces or tabs (trailing whitespace within lines).

**Verification:**
```zsh
# Check for lines ending with space or tab
grep -n '[[:space:]]$' <file> && echo "Found trailing whitespace"
```

**Fix:**
```zsh
# Remove trailing whitespace from all lines
sed -i '' 's/[[:space:]]*$//' <file>
```

**Why:** Trailing whitespace is invisible, causes spurious diffs, and is rejected by most linters.

---

### Whitespace Rule Application

**Applies to:**
- Shell scripts (`.sh`, `.zsh`, `.bash`, `.shellrc`, `.aliases`, `.envrc`)
- Ruby scripts (`.rb`)
- Configuration files (`.yml`, `.yaml`, `.json`, `.xml`, `.toml`, `.ini`, `.conf`, `.rc`)
- Git configuration (`.gitconfig`, `.gitattributes`, `.gitignore`)
- All other text files

**Exceptions:**
- **Markdown files (`.md`)** may have intentional trailing blank lines for formatting purposes and are exempt from Check 2 only. Checks 1 and 3 still apply.
- **Cryptographic files (`.key`, `.pem`)** must not be modified — they are generated by external tooling and any modification breaks their integrity.

**When using the Edit tool:**
- Ensure `newString` ends with exactly one `\n`
- No blank lines after the last content line
- No trailing spaces/tabs on any line

**When using the Write tool:**
- Ensure `content` ends with exactly one newline
- No trailing blank lines
- No trailing spaces/tabs on any line

**Comprehensive verification (run after every edit):**
```zsh
# Check 1: Ends with newline
tail -c 1 <file> | od -An -tx1 | grep -q '0a' || echo "FAIL: Missing final newline"

# Check 2: No trailing blank lines
tail -n 1 <file> | grep -q '^$' && echo "FAIL: Has trailing blank lines"

# Check 3: No trailing whitespace on any line
grep -q '[[:space:]]$' <file> && echo "FAIL: Has trailing whitespace"

# Or use this all-in-one check
if tail -c 1 <file> | od -An -tx1 | grep -q '0a' && \
   ! tail -n 1 <file> | grep -q '^$' && \
   ! grep -q '[[:space:]]$' <file>; then
  echo "✅ All whitespace checks pass"
else
  echo "❌ Whitespace violations found"
fi
```

## Ruby and Shell Tool Differences

- Ruby scripts are still required to be compatible with **Ruby 2.6**; no changes are needed.
- The shell‑editing conventions (such as using `apply_patch` instead of direct `sed` or `echo > file`) remain the same.

## Git Rules

The Git‑related rules in `git-config.instructions.md` are unchanged.  Both editors honour the same commit and push restrictions.

### Git State Management Rules — Mandatory

**DO NOT modify Git state (staging area, commits, branches, remotes) without explicit permission from the user.**

#### Staging Rules

**DO NOT stage, unstage, add, or reset files without explicit permission.**

When reviewing changes:
- Use `git status` and `git diff` to inspect changes
- Use `git diff --cached` to review staged changes
- **NEVER** run `git add`, `git add -A`, `git reset`, `git restore`, or any other command that modifies the staging area unless the user explicitly requests it

**Applies to:**
- `git add <file>` — stages a file
- `git add -A` — stages all changes
- `git add .` — stages all changes in current directory
- `git reset <file>` — unstages a file
- `git restore --staged <file>` — unstages a file
- `git checkout -- <file>` — discards unstaged changes
- `git rm <file>` — stages a deletion
- Any other command that modifies the index/staging area

**Why this matters:**
- Users may have carefully staged specific hunks or files for different commits
- Automatically staging all changes destroys that intent
- Mixing unrelated changes into a single commit breaks atomic commit principles
- The user's staging state is a deliberate choice, not something to override

**Correct workflow:**
1. Make edits to files as requested
2. Show `git status` or `git diff` to display what changed
3. Ask the user if they want to stage the changes
4. Only after explicit permission: run `git add` commands

**Exception:** When the user explicitly says "stage everything", "commit all changes", or similar clear intent to modify staging state, then `git add -A` is permitted.

#### Commit Rules

**DO NOT create, amend, or modify commits without explicit permission.**

**Prohibited without permission:**
- `git commit` — creates a new commit
- `git commit -a` — stages and commits all tracked changes
- `git commit --amend` — modifies the last commit
- `git rebase` — rewrites commit history
- `git reset --soft/--mixed/--hard` — moves HEAD and potentially discards commits
- `git cherry-pick` — applies commits from other branches
- Any other command that creates or modifies commits

**Why this matters:**
- Commits are permanent snapshots in the repository history
- Commit messages must be authored by the user, not generated automatically
- Users may want to review staged changes before committing
- The timing of commits is part of the user's workflow

**Correct workflow:**
1. Make edits and stage files (with explicit permission)
2. Show `git diff --cached` to display what will be committed
3. Ask the user if they want to commit and what message to use
4. Only after explicit permission: run `git commit` with user-provided message

**Exception:** When the user explicitly says "commit with message X", "create a commit", or similar clear intent, then `git commit` is permitted.

#### Rebase Rules

**When rebasing branches, ensure code quality is maintained or improved.**

After completing any rebase (whether manual conflict resolution or automated):

1. **No functional loss**: All functionality from both branches must be preserved
2. **No duplication**: Avoid duplicate implementations of the same logic
3. **No loss in modularity**: Keep extracted modules separate; don't inline them back
4. **No degradation in maintainability**: Code should be clearer after rebase, not harder to understand
5. **Documentation must be updated**: All references to renamed/moved files must be updated in docs, configs, and scripts

**Conflict resolution guidelines:**
- When both branches add the same file with different implementations:
  - Choose the more modular/maintainable version
  - If both have unique improvements, merge the best of both
- When both branches modify the same file:
  - Preserve all new functionality from both sides
  - Remove any duplicated code introduced by the merge
  - Ensure naming and structure remain consistent
- When file references change (e.g., `.sh` → `.rb`):
  - Update all references to use the newest file name
  - Verify documentation, configs, and scripts are all updated

**Verification after rebase:**
- Check for duplicate functions/methods (same logic in multiple places)
- Verify all file references point to correct files
- Ensure no functionality was lost in conflict resolution
- Run syntax checks on all modified files

**See also:** [FEATURE-PARITY-CHECKLIST.md](.ai/FEATURE-PARITY-CHECKLIST.md) for comprehensive post-rebase verification workflow.

## SSH Config Rules — Variable Expansion Limitations

**SSH config files (`~/.ssh/config`, `templates/ssh-config.template`) have strict limitations on variable expansion.**

### What SSH Config Supports

SSH config only supports:
- **Simple variable expansion**: `${VAR}` — requires the variable to be set in the environment
- **Tilde expansion**: `~` or `~/path` — expands to home directory
- **Tokens**: `%d` (home directory), `%h` (remote hostname), `%r` (remote username)

### What SSH Config Does NOT Support

SSH config does **NOT** support:
- **Bash-style default values**: `${VAR:-default}` — causes `vdollar_percent_expand` errors
- **Nested expansion**: `${VAR:-${OTHER_VAR}}` — fails to parse
- **Command substitution**: `$(command)` — not evaluated
- **Arithmetic expansion**: `$((expr))` — not evaluated

### The Rule

**ALL paths in SSH config files MUST use hardcoded `~/.ssh/` paths or simple `~` expansion.**

```ssh-config
# BAD — causes "vdollar_percent_expand: env var has no value" errors
IdentityFile "${SSH_CONFIGS_DIR:-${HOME}/.ssh}/id_rsa-personal"
Include "${SSH_CONFIGS_DIR:-${HOME}/.ssh}/global_config"

# Good — hardcoded path with tilde expansion
IdentityFile ~/.ssh/id_rsa-personal
Include ~/.ssh/global_config
```

### Why Hardcoded Paths

1. **SSH runs without shell environment** — many tools invoke SSH without loading `.zshrc` or `.shellrc`, so `SSH_CONFIGS_DIR` and other custom env vars are not available
2. **Syntax errors break git operations** — invalid variable expansion in `~/.ssh/config` causes all git operations over SSH to fail
3. **Cron jobs fail silently** — scripts running via cron don't have the interactive shell environment

### Files This Rule Applies To

- `~/.ssh/config` — active SSH client configuration
- `templates/ssh-config.template` — template for new installs
- Any file referenced by SSH (global_config, etc.)

### Required Warning Comment

Both `~/.ssh/config` and `templates/ssh-config.template` must have this comment near the top:

```
# **IMPORTANT:** SSH config does NOT support bash-style variable expansion like ${VAR:-default}.
# SSH only understands simple ${VAR} or ~ (home directory). Since many tools invoke ssh
# commands without the zsh environment loaded, this
# file MUST use hardcoded paths like ~/.ssh/id_rsa-personal instead of variable references.
```

### Enforcement

**When editing any SSH config file:**
1. **NEVER** introduce `${VAR:-default}` syntax
2. **NEVER** use `${SSH_CONFIGS_DIR}` or other custom env vars
3. **ALWAYS** use `~/.ssh/` hardcoded paths
4. **VERIFY** the config parses correctly: `ssh -G github.com`

## Changelog Generation Rules

- When generating a changelog, first examine the list of staged changes.
- For changes that affect the zwc cache (e.g., edits to autoloaded function files), prepend a call to `delete_caches` before any `unfunction` or re‑compile instructions so the cache is regenerated correctly.
- If any function definitions in `~/.shellrc` have been added, renamed, or removed, include a run‑time instruction to reload the function definitions:
  ```zsh
  unfunction is_shellrc_sourced; zcompile ~/.shellrc; source ~/.shellrc
  ```
- If any function definitions in `~/.aliases` have been added, renamed, or removed, include a run‑time instruction to reload the function definitions:
  ```zsh
  unfunction is_aliases_sourced; zcompile ~/.aliases; source ~/.aliases
  ```
- If any new files have been added or existing files have been deleted/renamed in the `files` folder, then add instructions to run `install-dotfiles.rb`.
- If any modifications touch the zsh boot‑up files (`.zshenv`, `.zshrc`, `.zlogin`, `.aliases`, `.shellrc`, etc.) or other scripts that are sourced during a terminal start‑up, add a note that the user should quit and restart the Terminal/iTerm application to reload the configuration.
- If the staged changes involve fresh‑install logic (e.g., modifications to `fresh-install-of-osx.sh` or related scripts), advise running the fresh‑install script in an idempotent manner, e.g. `./fresh-install-of-osx.sh` (it will guard against already‑configured machines).

### Changelog Entry Structure

When creating or editing CHANGELOG.md sections, follow these rules:

1. **Group related changes by category** rather than listing individual files when multiple files share similar changes.
   - Use `*[all ruby scripts]*` or `*[all zsh autoload scripts in files/--XDG_CONFIG_HOME--/zsh/]*` for changes that apply across multiple files with the same pattern.
   - Example: Instead of separate bullets for `antidote.rb`, `cron.rb`, and `keybase.rb` when they all adopt the same pattern, write one bullet covering all affected files.

2. **Keep essential technical details** while removing redundant specifics:
   - Always include: line numbers, method names, key implementation details, specific behavior changes.
   - Remove: repetitive file-by-file descriptions when a category description suffices.
   - Example: Keep "`update_repo(dir)` - fetch all remotes and rebase onto upstream" but consolidate "uses `GitProcessor.repo?(path)` for validation" once rather than per file.

3. **Use concise, high-level summaries** in the adoption section:
   - Focus on user-visible actions (restart terminal, run a script).
   - Remove implementation details that are already covered in the bullet points above.
   - Combine related adoption steps into single bullets when possible.

4. **Structure each version section consistently**:
   - Version number header (e.g., `### 3.1.23`)
   - Descriptive subheading summarizing the theme (e.g., `#### Backport utility enhancements and convert zsh autoload functions to Ruby`)
   - Bullet points with specific changes (technical details with line numbers)
   - `#### Adopting these changes` section with user action items (optional - omit if no user actions required)

5. **Version section spacing and visual separation**:
   - Each version section (starting with `### X.Y.Z`) must be separated by **exactly one blank line, followed by a horizontal rule (`---`), followed by one blank line**
   - Pattern: `[end of previous section]\n\n---\n\n### X.Y.Z`
   - The horizontal rule provides clear visual separation between sections when rendered in markdown viewers
   - The horizontal rule is a *separator* between version sections, not a header decoration
   - **Horizontal rule before the first version section** (one blank line after introductory text, then `---`, then one blank line before `### 3.1.27`)
   - **Horizontal rule after the last version section** (one blank line after last content, then `---` as the final line of the file)

**Example of good structure:**
```markdown
### 3.1.23

#### Backport utility enhancements and convert zsh autoload functions to Ruby

* *[scripts/utilities/git_workspace.rb]* Added four new public methods for git operations (lines 278-377): `update_repo(dir)` - fetch all remotes and rebase onto upstream; `update_all_repos` - update key repos (home, dotfiles, profiles) plus Chrome profile directories; `status_repo(dir)` - show status with custom formatting; `status_all_repos` - status check all repos. All methods use `GitProcessor.repo?(path)` for validation and return boolean success.

* *[all ruby scripts]* Ensures consistency with single source of truth for git repo detection across all utility modules. Also found and fixed premature conversion of `Pathname` instances to `String` (maintain rich object as much as possible only convert to String at interpolation boundaries).

* *[all zsh autoload scripts in files/--XDG_CONFIG_HOME--/zsh/]* Converted from shell script to a thin Ruby wrapper.

#### Adopting these changes

* Restart terminal to reload zsh autoload functions.
* New Ruby methods are immediately available to shell scripts via `ruby -e` pattern.
```


---

### Executable Permission Rule — Mandatory for Scripts

**After creating or editing shell scripts (`.sh`, `.zsh`, `.bash`) or Ruby scripts (`.rb`), ensure they have executable permission (`chmod +x`).**

This applies to:
- All scripts in `$DOTFILES_DIR/scripts/`
- All scripts in `$PERSONAL_BIN_DIR/`
- Autoload functions in `$XDG_CONFIG_HOME/zsh/` (`.zsh` files)
- Any standalone scripts intended to be executed directly

**When creating a new script:**
```zsh
chmod +x path/to/script.sh
chmod +x path/to/script.rb
```

**When editing an existing script:**
If the file had executable permission before editing, ensure it retains it after the edit. Most editing tools preserve permissions, but if you're using a method that rewrites the file (like Python's `open(file, 'w')`), you must restore the permission:

```python
import os
import stat

# Before editing, check if executable
was_executable = os.access(filepath, os.X_OK)

# ... edit file ...

# After editing, restore executable permission if it had it
if was_executable:
    st = os.stat(filepath)
    os.chmod(filepath, st.st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
```

**Bulk fix command (apply to all scripts):**
```zsh
# Fix all shell scripts in a directory
find <dir> -name "*.sh" -o -name "*.zsh" -o -name "*.bash" | xargs chmod +x

# Fix all Ruby scripts in a directory
find <dir> -name "*.rb" | xargs chmod +x
```

**Verification:**
```zsh
# Check if a file is executable
[[ -x path/to/script.sh ]] && echo "✅ Executable" || echo "❌ Not executable"

# List files missing executable permission
find <dir> \( -name "*.sh" -o -name "*.rb" \) ! -perm +111 -type f
```

**Why this matters:**
- Scripts in `$PERSONAL_BIN_DIR` are intended to be executed directly from PATH
- Scripts in `$DOTFILES_DIR/scripts/` are invoked by other scripts and must be executable
- Autoload functions must be executable for zsh to load them
- Without executable permission, scripts fail with "Permission denied" errors

**Exception:** Library files that are only `source`d or `require`d (not executed directly) don't need executable permission, but it doesn't hurt to have it.

---

**End of Unified Model Instructions**
