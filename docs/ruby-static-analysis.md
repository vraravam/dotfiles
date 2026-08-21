# Ruby Static Analysis Tools

This repository uses four complementary tools for Ruby code quality:

## Tools Overview

| Tool | Purpose | What It Catches |
|------|---------|-----------------|
| **RuboCop** | Style and lint checker | Unused variables, unreachable code, style violations, potential bugs |
| **Reek** | Code smell detector | Duplicate method calls, nested iterators, poor naming, unused methods |
| **Flay** | Duplication analyzer | Structural duplication across files (copy-paste code) |
| **Flog** | Complexity analyzer | High complexity methods (candidates for refactoring) |

## Installation

### Automatic (for new Ruby versions via mise)
Gems install automatically when you install a new Ruby version:
```zsh
mise install ruby@3.3.0
# rubocop, reek, flay, flog installed automatically
```

### Manual (for current Ruby)
```zsh
gem install rubocop reek flay flog
```

## Usage

### Run All Tools at Once
```zsh
# All scripts
ruby scripts/ruby-lint.rb

# Specific directory
ruby scripts/ruby-lint.rb scripts/utilities/

# Specific file
ruby scripts/ruby-lint.rb scripts/my-script.rb
```

### Run Individual Tools
```zsh
# RuboCop - style and lint
rubocop scripts/
rubocop -a scripts/  # Auto-fix safe issues

# Reek - code smells
reek scripts/

# Flay - duplication
flay scripts/

# Flog - complexity
flog scripts/
```

## Pre-Commit Hook

The global pre-commit hook validates Ruby and shell syntax automatically:
- Blocks commits with syntax errors in `.rb` files
- Blocks commits with syntax errors in `.sh`/`.zsh`/`.bash` files
- Skip with `git commit --no-verify` (not recommended)

Test it:
```zsh
# Create intentional syntax error
echo "def foo" >> test.rb
git add test.rb
git commit -m "test"
# Should block: "❌ Syntax validation failed"
```

## Configuration Files

- `~/.config/rubocop/config.yml` - RuboCop rules (targets Ruby 2.6+)
- `~/.config/reek/config.yml` - Reek code smell detectors
- `~/.config/mise/default-gems` - Gems installed with every Ruby version
- `~/.config/git/hooks/pre-commit` - Pre-commit validation hook

## Interpreting Results

### RuboCop
- **Lint cops** (red) - Actual bugs, fix immediately
- **Style cops** (yellow) - Style violations, fix for consistency
- Use `rubocop -a` to auto-fix safe issues

### Reek
- **DuplicateMethodCall** - Consider memoization (`@_var ||= expensive_call`)
- **NestedIterators** - Flatten loops or extract methods
- **UncommunicativeVariableName** - Use descriptive names

### Flay
- High similarity score (>50) - Consider extracting shared logic to module
- Exact duplicates - Refactor immediately

### Flog
- Score >30 - Method is complex, consider splitting
- Score >50 - Refactor urgently

## CI/CD Integration

To run in CI (if added later):
```zsh
# In CI script
gem install rubocop reek flay flog
ruby scripts/ruby-lint.rb || exit 1
```

## See Also

- [ruby-scripting.md](.ai/domains/ruby-scripting.md) - Ruby coding standards
- [edit-checklist.md](.ai/domains/edit-checklist.md) - Post-edit verification workflow
