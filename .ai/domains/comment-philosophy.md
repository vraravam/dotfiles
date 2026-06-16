---
applyTo: "**/*.sh*,**/.shellrc,**/.aliases,**/.envrc,**/.zsh*,**/files/--XDG_CONFIG_HOME--/zsh/*,**/scripts/**,**/*.rb"
---

# Comment Philosophy

Comments must serve as **timeless reference documentation**, not as a changelog
or commit message.

## Comment Format

### Shell Scripts

```zsh
################################################################################
# file-header.sh
# Purpose: Brief description of script purpose
################################################################################

# ---------------------------------------------------------------------------
# Section Name

# Individual function comments use plain #
function_name() {
  # Implementation detail comment
}
```

**Conventions**:
- File headers: 80-character `#` line with script name and purpose
- Section separators: `# -----` line (71 dashes)
- Regular comments: Plain `#` with single space before text
- No trailing `#` or closing separators

### Ruby Scripts

```ruby
# frozen_string_literal: true

################################################################################
# file_name.rb
# Purpose: Brief description of script purpose
################################################################################

# ---------------------------------------------------------------------------
# Section Name

# Individual function/method comments use plain #
def method_name
  # Implementation detail comment
end
```

**Conventions**:
- Frozen string literal pragma at top (if used)
- File headers: Plain `#` lines with script name and purpose
- Section separators: `# -----` line (71 dashes) - same as shell
- Regular comments: Plain `#` with single space before text
- No special RDoc/YARD tags (keep comments simple and readable)

## What Good Comments Explain

**✅ Good comments explain:**
- **Why** a non-obvious implementation exists (e.g., "resolves symlinks because -nt compares symlink mtime")
- **What** edge case is being handled (e.g., "returns true if either argument is missing")
- **How** to use a function correctly (e.g., examples in function headers)
- **When** certain conditions matter (e.g., "only needed before .shellrc is sourced")

**❌ Bad comments describe:**
- **Past changes** (e.g., "now resolves internally" or "used to require manual resolution")
- **Commit-specific context** (e.g., "fixed in this commit" or "removed duplicate pattern")
- **Temporal language** (e.g., "currently does X" or "as of this session")
- **What the code obviously does** (e.g., `count += 1  # increment count`)

## Examples

### Shell Script Examples

```zsh
# BAD -- describes a change, not the current behavior
# Resolve symlinks explicitly: while is_file_older_than now resolves internally,
# we need the real path here for other reasons.

# GOOD -- explains why resolution is needed
# Resolve symlinks: .zwc file lives next to the symlink, not the target file.

# BAD -- changelog-style temporal language
# Updated to use utility function instead of raw test switch.
if is_non_zero_string "${var}"; then

# GOOD -- explains why this approach is used
# Use utility function for consistent error handling under set -u.
if is_non_zero_string "${var}"; then

# BAD -- describes what was removed
# Removing the explicit resolution since the function handles it now.

# GOOD -- explains what exists and why
# Function resolves symlinks automatically to detect Homebrew upgrades.
```

### Ruby Script Examples

```ruby
# BAD -- describes a change, not the current behavior
# Now resolves symlinks automatically instead of requiring callers to do it.

# GOOD -- explains why resolution happens
# Resolves symlinks to detect when Homebrew upgrades change the target binary.

# BAD -- changelog-style temporal language
# Updated to use is_non_zero_string for consistency.
if Validation.is_non_zero_string(var)

# GOOD -- explains why this approach is used
# Use validation helper for consistent nil/empty handling across the codebase.
if Validation.is_non_zero_string(var)
```

## Rationale

1. **Comments are code documentation, not commit history** — use `git log` for that
2. **Future readers need to understand the current state** — not how it evolved
3. **Temporal language becomes stale** — immediately after the next change
4. **"Why" explanations prevent bugs** — future refactoring won't reintroduce issues

## When Updating Code

1. Remove or reword comments that describe past behavior
2. Add/update comments to explain current behavior and rationale
3. Move historical context to commit messages, not inline comments
