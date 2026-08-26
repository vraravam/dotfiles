# Agent Quick Reference

This dotfiles repository uses a comprehensive instruction system in `.ai/`. This file highlights the non-obvious patterns agents commonly miss.

## Instruction Architecture

**Primary source of truth**: `.ai/instructions.md` → domain-specific files in `.ai/domains/`

Tool-specific configs (`.cursorrules`, `.windsurfrules`, `.github/copilot-instructions.md`) are minimal redirects. Load `.ai/instructions.md` first.

Key instruction files (apply to code in `${DOTFILES_DIR}`, `${PERSONAL_BIN_DIR}`, and `${PERSONAL_CONFIGS_DIR}`):
- `shell-scripting.md` — Shell patterns, utilities, startup optimization
- `ruby-scripting.md` — Ruby patterns, dual-mode scripts, GitProcessor
- `zsh-startup.md` — Performance optimization, caching, plugin loading
- `fresh-install.md` — Bootstrap idempotency, vanilla OS mode
- `git-config.md` — Git aliases, hooks, per-repo customization
- `edit-checklist.md` — Post-edit verification workflow (syntax, format, whitespace)

**CRITICAL**: Any refactoring, formatting, or pattern fixes identified in one location MUST be applied to **all matching files** across all three directories. For example:
- If you fix a `&&` pattern in `${DOTFILES_DIR}/scripts/file.sh`, scan and fix the same pattern in `${PERSONAL_BIN_DIR}/*.sh`
- If you update UTF-8 file reading in a Ruby script, search for all instances of `File.readlines` / `.each_line` across all three locations
- Use grep/glob to find all matching files before starting edits: `grep -r "pattern" ${DOTFILES_DIR} ${PERSONAL_BIN_DIR} ${PERSONAL_CONFIGS_DIR}`

## Git State Management — NEVER Modify Without Permission

**DEFAULT WORKFLOW: The user reviews and stages changes manually.**

After making edits:
1. ✅ Make the requested edits to files
2. ✅ Show `git status` or `git diff` to display what changed
3. ❌ **STOP** - Do NOT stage, commit, or modify git state
4. ✅ Let the user review changes and stage manually

**Prohibited without explicit permission:**
- `git add` / `git add -A` / `git add .` — staging files
- `git commit` / `git commit -a` / `git commit --amend` — creating/modifying commits
- `git reset` / `git restore --staged` — unstaging files
- `git checkout` / `git switch` — changing branches
- `git push` / `git push --force` — pushing to remote
- `git rebase` / `git merge` — modifying history
- `git stash` / `git rm` — any other state-modifying command

**If the user explicitly grants permission for ONE operation:**
- Permission is ONE-TIME ONLY for that specific instruction
- NOT a blanket approval for the rest of the session
- NOT carried over to future sessions
- Each git state change requires fresh explicit permission

**Why this matters:**
- Users manually review all changes before staging
- Users may stage specific hunks or files for different commits
- Automatically staging destroys the user's deliberate staging intent
- The staging area reflects the user's workflow decisions

See: `.ai/instructions.md` § Git State Management Rules

## Critical Commands (Run After Every Edit)

**Shell scripts**:
```zsh
zsh -n file.sh                    # Syntax check
shfmt -w file.sh                  # Format
rm -f file.sh.zwc                 # Delete bytecode cache
chmod +x file.sh                  # Ensure executable
```

**Ruby scripts**:
```zsh
/usr/bin/ruby -c file.rb          # Syntax (Ruby 2.6 compat required)
rufo file.rb                      # Format
```

**All files** (except `.md`):
```zsh
# Verify whitespace rules (see .ai/instructions.md § Whitespace Rules)
tail -c 1 file | od -An -tx1 | grep -q '0a' || echo "Missing final newline"
tail -n 1 file | grep -q '^$' && echo "Has trailing blank lines"
grep -q '[[:space:]]$' file && echo "Has trailing whitespace"
```

## Decision-Making Priority Order

When choices conflict, this order wins:

1. **Startup speed** (for zsh hot path)
2. **Maintainability** (readability, DRY, clear intent)
3. **POSIX compatibility** (when scripts run in bash/direnv)
4. **Zsh built-ins** (when they don't conflict with #1-3)

Document tradeoffs in comments when priorities conflict.

## Common Agent Mistakes

### 1. `&&` Under `set -e` Triggers ERR Traps

**Problem**: Standalone `A && B` where A returning false is *expected* propagates exit code 1, triggering ERR trap or aborting the script.

```zsh
# BAD -- file not existing is normal, but fires ERR trap
is_file "${optional}" && process_file

# Good -- explicit if/then never propagates predicate exit code
if is_file "${optional}"; then process_file; fi
```

**Safe exception**: `A && B || C` where C returns 0 (overall expression = 0, no trap).

See: `shell-scripting.md` § `&&` as Conditional

### 2. Dual-Mode Ruby Scripts (Module + CLI)

**ALL standalone Ruby scripts MUST follow this pattern** to enable both CLI usage and direct module calls (no subprocess overhead):

```ruby
module MyScript
  extend self
  def run(param:)
    # ... logic ...
    true  # Return boolean, NEVER call exit()
  end
end

if __FILE__ == $PROGRAM_NAME
  include Logging  # Only in CLI block
  # ... option parsing ...
  success = MyScript.run(param: value)
  exit(success ? 0 : 1)
end
```

**When calling from another Ruby script**:
```ruby
require_relative 'my-script'
success = MyScript.run(param: value)  # Direct call, no subprocess
```

See: `ruby-scripting.md` § Dual-Mode Ruby Scripts

### 3. Path Constants — Never Hardcode

**Shell**:
```zsh
# BAD
source "${HOME}/.config/dotfiles/scripts/utilities/file.sh"

# Good
source "${DOTFILES_DIR}/scripts/utilities/file.sh"
```

**Ruby**:
```ruby
# BAD
config = Pathname.new(ENV['HOME']).join('.config/file')

# Good
config = EnvVars::XDG_CONFIG_HOME.join('file')
```

All path env vars are defined in:
- Shell: `files/--HOME--/.shellrc` (lines 40-113)
- Ruby: `scripts/utilities/env_vars.rb`

See: `path-constants.md`

### 4. Startup Hot Path — No Subshell Forks

```zsh
# BAD -- forks subprocess on every shell start
ARCH=$(uname -m)
basename=$(basename "$(pwd)")

# Good -- use cached value or zsh parameter expansion
is_arm  # Checks cached ARCH (see .shellrc architecture cache)
basename="${PWD:t}"  # Zsh :t modifier (no fork)
```

See: `zsh-startup.md` § No Subshell Forks, `shell-scripting.md` § Zsh Parameter Expansion

### 5. Git Alias Overrides — Folder-Context Pattern

Git aliases support per-repository overrides via `${PERSONAL_BIN_DIR}/<alias>-<basename>.sh`:

```ini
# In .gitconfig
upreb = "!f() { \
  dir=\"${1:-.}\"; \
  basename=\"$(basename \"$(cd \"${dir}\" && pwd)\")\"; \
  override=\"${PERSONAL_BIN_DIR}/upreb-${basename}.sh\"; \
  if [ -x \"${override}\" ]; then (cd \"${dir}\" && . \"${override}\"); return $?; fi; \
  # ... default implementation ...; \
}; f"
```

Override script pattern:
```zsh
#!/usr/bin/env zsh
source "${ZDOTDIR}/.aliases"
load_file_if_exists "${XDG_CONFIG_HOME}/zsh/upreb"  # Load common _upreb function

main() {
  # Custom pre-logic
  git delete-tag twilight 2>/dev/null

  # Call common implementation
  _upreb

  # Custom post-logic (if needed)
}
main "$@"
```

See: `git-config.md` § Folder-Context-Aware Override Pattern

### 6. Shell Functions Before Ruby Available

Functions needed during **bootstrap** (before Ruby installed, before dotfiles cloned) MUST live in `.shellrc`, not `.aliases`:

- `clone_repo_into` — Clones dotfiles repo on vanilla OS
- `suspend_cron`/`resume_cron` — Used before repo exists
- Logging functions (`info`, `success`, `warn`, `error`)
- Validation functions (`is_file`, `is_directory`, `nil_or_empty`)

**Ruby delegates to shell** for bootstrap functions:
```ruby
# GitProcessor delegates to shell clone_repo_into
system('zsh', '-c', "source ~/.shellrc && clone_repo_into '#{url}' '#{target}'")
```

See: `shell-scripting.md` § `.shellrc` vs `.aliases` Split, `context.md` § clone_repo_into Delegation Pattern

### 7. UTF-8 File Reading in Ruby

**CRITICAL**: Ruby file reading defaults to system encoding (US-ASCII in cron jobs). Files with UTF-8 content (em dashes, curly quotes) cause `ArgumentError: invalid byte sequence in US-ASCII`.

```ruby
# BAD -- encoding depends on environment
lines = file.readlines
File.foreach(file) { |line| process(line) }

# Good -- explicit UTF-8 encoding
lines = Core.read_lines_utf8(file)
Core.each_line_utf8(file) { |line| process(line) }
```

**Affected files**: Config files in `scripts/data/`, SSH config, plist files.

**Exception**: `String#each_line` on in-memory strings is fine (strings already UTF-8 in memory).

See: `ruby-scripting.md` § UTF-8 File Reading

### 8. Whitespace Rules — Mandatory Checks

**After every edit** (except `.md`), files MUST pass three checks:

1. **File ends with newline**: `tail -c 1 file | od -An -tx1 | grep -q '0a'`
2. **No trailing blank lines**: `! tail -n 1 file | grep -q '^$'`
3. **No trailing whitespace**: `! grep -q '[[:space:]]$' file`

**Fix command**:
```zsh
# Remove trailing blank lines (preserves final newline)
sed -i '' -e :a -e '/^\s*$/d;N;ba' file

# Remove trailing whitespace from all lines
sed -i '' 's/[[:space:]]*$//' file
```

See: `.ai/instructions.md` § Whitespace Rules

### 9. Fresh Install Idempotency

Every section in `fresh-install-of-osx.sh` MUST have a guard that pre-empts execution when work is already done:

```zsh
# Good -- skip if tool already installed
if is_executable "brew"; then
  info "Homebrew already installed -- skipping."
else
  # ... install homebrew ...
fi
```

Script runs in two modes:
- **Vanilla OS** (`FIRST_INSTALL=1`) — Fresh macOS, nothing installed
- **Pre-configured** — Already set up, running updates

See: `fresh-install.md` § Idempotency Contract

### 10. Logging Auto-Indents — Never Manual Spaces

All logging methods auto-indent based on `_DOTFILES_SCRIPT_DEPTH` (2 spaces per depth):

```ruby
# Good -- Logging.info auto-indents
Logging.info "Processing '#{file.cyan}'"

# BAD -- manual indentation breaks nested calls
puts "  Processing '#{file.cyan}'"
```

**Exception**: External tool output intentionally unindented (user expects original format).

See: `script-depth-tracking.md`

## Repository Structure (Quick Map)

```
~/.config/dotfiles/
├── files/
│   ├── --HOME--/          # Symlinked to ~/ (Brewfile, .shellrc, .gitconfig)
│   ├── --ZDOTDIR--/       # Zsh config (.zshenv, .zshrc, .zlogin)
│   └── --XDG_CONFIG_HOME--/zsh/  # Autoload functions
├── scripts/
│   ├── utilities/         # Shared Ruby modules (logging.rb, env_vars.rb, git_processor.rb)
│   ├── fresh-install-of-osx.sh    # Bootstrap entry point
│   ├── install-dotfiles.rb        # Symlink/copy manager
│   └── capture-prefs.rb           # Preferences export/import
└── .ai/                   # AI instruction files (READ THIS FIRST)
```

**Key paths**:
- `${DOTFILES_DIR}` = `~/.config/dotfiles` (this repo)
- `${PERSONAL_BIN_DIR}` = `~/personal/dev/bin` (user scripts, not in repo)
- `${PERSONAL_CONFIGS_DIR}` = `~/personal/dev/configs` (sensitive configs, not in repo)
- `${XDG_CONFIG_HOME}` = `~/.config`
- `${ZDOTDIR}` = `~/.config/zsh`

## Testing Patterns

**Shell scripts**:
```zsh
# Syntax check
zsh -n script.sh

# Profile startup (for .zshrc edits)
ZSH_PROFILE=true zsh -i -c exit
zprof

# Debug load order
DEBUG=true zsh
```

**Ruby scripts**:
```zsh
# Ruby 2.6 compatibility check (system Ruby on vanilla macOS)
/usr/bin/ruby -c script.rb

# Test dual-mode scripts
ruby script.rb --help               # CLI mode
ruby -e "require_relative 'script'; MyModule.run"  # Module mode
```

**Fresh install** (idempotency test):
```zsh
# First run (vanilla OS simulation)
FIRST_INSTALL=1 ./scripts/fresh-install-of-osx.sh

# Second run (pre-configured mode)
./scripts/fresh-install-of-osx.sh
```

## Performance Optimization Notes

**Current startup**: 78-87ms average (Apple Silicon M1+)

**Bottlenecks** (from `zprof`):
- 81% (21ms): Antidote plugin bundle loading — already optimized
- 9% (2.6ms): Syntax highlighting
- 5% (1.4ms): Starship prompt (cached)
- 4% (1.2ms): Mise activation (cached)

**Optimization patterns that work**:
- Mtime-based caching (brew shellenv, starship init, mise activate)
- Zsh parameter expansion over subshells (`${PWD:t}` not `$(basename ...)`)
- `zsh-defer` for non-critical operations (runs after first prompt, before first keypress)
- `zsh/stat` module over `$(stat ...)` forks

See: `zsh-startup.md`, `context.md` § Historical Optimization Milestones

## When to Ask Questions

Ask ONLY if the repo cannot answer:
- Undocumented team conventions
- Branch/PR/release expectations
- Missing setup prerequisites known but not written

Do NOT ask about:
- Anything in `.ai/` instruction files
- Standard shell/Ruby/git conventions
- Information in README/Adoption/TechnicalDeepDive docs

## Quick Debugging Reference

```zsh
# Check if function loaded
type function_name

# Check PATH/FPATH
echo ${PATH} | tr ':' '\n'
echo ${FPATH} | tr ':' '\n'

# Find where function defined
whence -v function_name

# Trace shell startup
DEBUG=true zsh

# Profile Ruby script
ruby-prof script.rb
```
