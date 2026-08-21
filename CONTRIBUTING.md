# Contributing to dotfiles

Thank you for considering contributing to this project! This document provides guidelines for contributing code, documentation, and reporting issues.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Code Style Guidelines](#code-style-guidelines)
- [Testing](#testing)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Documentation](#documentation)
- [Questions and Support](#questions-and-support)

## 📜 Code of Conduct

This project follows standard open source etiquette:
- Be respectful and constructive in all interactions
- Focus on what is best for the community
- Show empathy towards other community members
- Accept constructive criticism gracefully

## 🚀 Getting Started

### Prerequisites

- macOS 11+ (Intel or Apple Silicon)
- Git
- GitHub account
- Familiarity with shell scripting (zsh) and Ruby 2.6+

### Setting Up Your Development Environment

1. **Fork the repository** on GitHub
2. **Clone your fork** to your local machine:
   ```zsh
   git clone https://github.com/YOUR_USERNAME/dotfiles.git ~/dev/dotfiles
   cd ~/dev/dotfiles
   ```
3. **Add upstream remote**:
   ```zsh
   git remote add upstream https://github.com/vraravam/dotfiles.git
   ```
4. **Review the codebase architecture**:
   - Read [TechnicalDeepDive.md](TechnicalDeepDive.md) for internal architecture
   - Review [.ai/instructions.md](.ai/instructions.md) for AI coding guidelines
   - Check code documentation (RDoc in Ruby files, comments in shell scripts) for environment variable definitions

## 🔄 Development Workflow

### Creating a Feature Branch

```zsh
git checkout -b feature/your-feature-name
```

### Making Changes

1. **Follow existing patterns** — the codebase has consistent conventions for:
   - File naming (kebab-case for scripts, snake_case for Ruby modules)
   - Function naming (snake_case in both shell and Ruby)
   - Logging (Logging module in Ruby, logging functions in shell)
   - Path handling (EnvVars module for all path constants)

2. **Test your changes** locally:
   - For shell scripts: `zsh -n script.sh` (syntax check)
   - For Ruby scripts: `/usr/bin/ruby -c script.rb` (Ruby 2.6 compatibility)
   - Manual testing in both vanilla OS and pre-configured machine contexts

3. **Document new features**:
   - Add RDoc comments for all public methods
   - Update relevant .md files (README, Extras, TechnicalDeepDive)
   - Add inline comments for non-obvious logic

### Syncing with Upstream

```zsh
git fetch upstream
git rebase upstream/master
```

## 📐 Code Style Guidelines

### Shell Scripts (zsh)

- Use `set -euo pipefail` unless the script has legitimate non-zero returns
- Always quote variables: `"${var}"` not `$var`
- Use `${var}` brace notation, never bare `$var`
- Prefer zsh built-ins over external commands in startup hot path
- Follow logging conventions: `info`, `success`, `warn`, `error`, `debug`
- See [.ai/domains/shell-scripting.md](.ai/domains/shell-scripting.md) for complete rules

### Ruby Scripts

- Target Ruby 2.6 compatibility (system Ruby on vanilla macOS)
- Use `Logging` module for all output (never `puts`/`warn` in utility modules)
- Use `EnvVars` module for all environment variable access
- Follow dual-mode pattern (module + CLI) for all standalone scripts
- Prefer `Pathname` over `String` for all path operations
- See [.ai/domains/ruby-scripting.md](.ai/domains/ruby-scripting.md) for complete rules

### Formatting

**After every edit:**

1. **Shell scripts**:
   ```zsh
   zsh -n script.sh                    # syntax check
   shfmt -w script.sh                  # format (check .shfmtignore first)
   chmod +x script.sh                  # ensure executable
   ```

2. **Ruby scripts**:
   ```zsh
   /usr/bin/ruby -c script.rb          # Ruby 2.6 syntax check
   rufo script.rb                      # format
   chmod +x script.rb                  # ensure executable (if in bin/)
   ```

3. **All scripts** (remove consecutive blank lines):
   ```zsh
   awk 'NF {blank=0; print} !NF {if (!blank) print; blank=1}' file > file.tmp && mv file.tmp file
   ```

### Whitespace Rules

**All files except Markdown**:
- Must end with exactly one newline character (`\n`)
- No trailing blank lines after last content line
- No trailing whitespace on any line

**Verification**:
```zsh
# Check all three rules
tail -c 1 <file> | od -An -tx1 | grep -q '0a' || echo "FAIL: Missing final newline"
tail -n 1 <file> | grep -q '^$' && echo "FAIL: Has trailing blank lines"
grep -q '[[:space:]]$' <file> && echo "FAIL: Has trailing whitespace"
```

## 🧪 Testing

### Manual Testing Checklist

- [ ] Test on both Intel and Apple Silicon if possible
- [ ] Test on vanilla macOS (no Homebrew, no dotfiles)
- [ ] Test on pre-configured machine (existing dotfiles installation)
- [ ] Verify idempotency (run twice, second run should skip completed steps)
- [ ] Check log output for clarity and correctness

### Test Scenarios

1. **Fresh install**: Bootstrap on vanilla macOS
2. **Update existing**: Run on machine with dotfiles already installed
3. **Error recovery**: Interrupt mid-run, verify resume works
4. **Cron context**: Test scripts that run via cron (no TTY, minimal environment)

## 📝 Commit Messages

### Format

```
<type>: <short summary>

<optional detailed description>

<optional footer>
```

### Types

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `style:` Formatting, whitespace (no code change)
- `refactor:` Code restructuring (no behavior change)
- `perf:` Performance improvement
- `test:` Adding or fixing tests
- `chore:` Tooling, dependencies, maintenance

### Examples

```
feat: add reftable migration to GitProcessor

Adds migrate_refs_to_reftable method that migrates legacy
repos from files format to reftable (git 2.45+).

No-op if already reftable or if git version doesn't support
the 'git refs migrate' command.
```

```
fix: correct variable quoting in fresh-install curl opts

The _curl_opts array expansion was missing quotes, causing
word splitting on paths with spaces. Now properly quoted.
```

## 🔀 Pull Request Process

### Before Submitting

1. **Rebase on latest upstream**:
   ```zsh
   git fetch upstream
   git rebase upstream/master
   ```

2. **Squash if needed** (prefer single commit per PR):
   ```zsh
   git rebase -i upstream/master
   ```

3. **Self-review**:
   - Run formatting checks on all modified files
   - Verify no debug code or console.log equivalents left in
   - Add RDoc comments to new environment variables in Ruby code
   - Add inline comments to new environment variables in shell code
   - Ensure TechnicalDeepDive.md is updated for architectural changes

### PR Template

```markdown
## Summary
Brief description of what this PR does and why.

## Changes
- Bullet list of specific changes

## Testing
How you tested this change (vanilla OS, pre-configured, etc.)

## Related Issues
Closes #123 (if applicable)

## Checklist
- [ ] Code follows style guidelines
- [ ] Documentation updated
- [ ] Tested on both vanilla and pre-configured machines
- [ ] Commit message follows format
- [ ] No trailing whitespace or formatting issues
```

### Review Process

1. Maintainer reviews code and provides feedback
2. You address feedback via additional commits or rebasing
3. Once approved, maintainer will merge (or you'll be asked to squash + force-push first)

### After Merge

1. **Update your fork**:
   ```zsh
   git checkout master
   git pull upstream master
   git push origin master
   ```

2. **Clean up branch**:
   ```zsh
   git branch -d feature/your-feature-name
   git push origin --delete feature/your-feature-name
   ```

## 📚 Documentation

### What to Document

- **New scripts**: Add section to [Extras.md](Extras.md)
- **Architecture changes**: Update [TechnicalDeepDive.md](TechnicalDeepDive.md)
- **New environment variables**: Add RDoc comments in `scripts/utilities/env_vars.rb` and inline comments in `files/--HOME--/.shellrc`
- **Public methods**: Add RDoc comments (Ruby) or inline comments (shell)
- **Breaking changes**: Note in commit message and PR description

### Documentation Style

- Use **Markdown** for all documentation files
- Use **RDoc** for Ruby method documentation
- Use **inline comments** for non-obvious shell logic
- Keep README.md high-level; details go in Extras.md or TechnicalDeepDive.md

## ❓ Questions and Support

- **General questions**: Open a GitHub Discussion
- **Bug reports**: Open a GitHub Issue with:
  - macOS version and architecture
  - Steps to reproduce
  - Expected vs actual behavior
  - Relevant log excerpts
- **Feature requests**: Open a GitHub Issue describing:
  - Use case
  - Proposed solution
  - Alternatives considered

## 🙏 Thank You

Your contributions make this project better for everyone. Whether it's code, documentation, bug reports, or suggestions — all contributions are valued and appreciated!
