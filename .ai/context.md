# Dotfiles Domain Context

## Overview
This file provides domain-specific navigation and operational reference for the dotfiles repository, personal bin scripts, and configs. It complements the formal rules in [`domains/`](./domains/) with debugging guidance and quick-reference material. It is not a changelog or session journal -- see `CHANGELOG.md` for version history.

## Instruction Files (The Source of Truth)
All detailed rules, patterns, and conventions are in `.ai/domains/`:
- `.ai/domains/character-encoding.md` (cross-language)
- `.ai/domains/comment-philosophy.md` (cross-language)
- `.ai/domains/edit-checklist.md` (cross-language)
- `.ai/domains/fresh-install.md`
- `.ai/domains/git-config.md`
- `.ai/domains/logging-conventions.md` (cross-language)
- `.ai/domains/path-constants.md` (cross-language)
- `.ai/domains/ruby-scripting.md`
- `.ai/domains/script-depth-tracking.md` (cross-language)
- `.ai/domains/shell-scripting.md`
- `.ai/domains/whitespace-rules.md` (cross-language)
- `.ai/domains/zsh-startup.md`

**DO NOT duplicate content from these files.** They are the authoritative source.

See `.ai/instructions.md` for the main entry point and `.ai/README.md` for the tool-agnostic convention.

## Decision-Making Philosophy
(From `copilot-instructions.md` - already loaded)

Priority order when making decisions:
1. **Startup speed** (for zsh startup paths)
2. **Maintainability** (readability, DRY, clear intent)
3. **POSIX compatibility** (when scripts run in bash/direnv)
4. **Zsh built-ins** (when they don't conflict with #1-3)

Higher priority always wins. Document tradeoffs in comments when they conflict.

## Repository Structure
```
~/.config/dotfiles/
├── files/
│   ├── --HOME--/              # Symlinked to ~/
│   │   ├── .shellrc           # Sourced by all shells
│   │   ├── .aliases           # Shell functions/aliases
│   │   └── Brewfile           # Homebrew packages
│   ├── --ZDOTDIR--/           # Zsh-specific (~/ZDOTDIR)
│   │   ├── .zshenv            # Always sourced first
│   │   ├── .zshrc             # Interactive shells
│   │   └── .zlogin            # After .zshrc (compilation)
│   └── --XDG_CONFIG_HOME--/zsh/  # Autoload functions
├── scripts/
│   ├── utilities/             # Shared Ruby modules
│   ├── fresh-install-of-osx.sh
│   └── install-dotfiles.rb
└── .ai/                        # AI assistant instructions
```

## Forward-Looking Notes

Guidance for specific future work, kept here (not as history) because it's
directly actionable when that work is picked up:

- **If `fresh-install-of-osx.sh` is ever ported to Ruby**: reimplement
  `clone_repo_into` fresh rather than porting the existing Ruby
  `git_processor.rb` implementation (it has drifted since the shell version was
  last enhanced). Use the current `.shellrc` version as the reference --
  it's the canonical implementation (see `shell-scripting.md` § `.shellrc` vs
  `.aliases` for why bootstrap-time functions must stay in `.shellrc`).

- **When rebasing all WIP branches onto an updated `master`**: process them in
  this order: `deja`, `stout-migration`, `fresh-install-ruby`,
  `osx-defaults-ruby`. The last two must stay adjacent
  and in that relative order regardless -- `osx-defaults-ruby` is chained on
  top of `fresh-install-ruby` (not `master` directly), so `fresh-install-ruby`
  must be rebased first and `osx-defaults-ruby` rebased onto the *updated*
  `fresh-install-ruby`, never onto `master`. See
  `REBASE-AND-REFACTORING-METHODOLOGY.md` § Forward Rebase for the mechanics,
  and its § Rebase Workflow for the `rebase --onto <new-base> <old-base>
  <branch>` form required when the branch's old base commit was itself
  amended (a plain `git rebase master` will conflict in that case).

## Known Issues

1. Aliases sometimes fail to load after certain `.zshrc` changes
   - **Cause**: Syntax errors break initialization before `zsh-defer` runs
   - **Debug**: `zsh -n file.zsh` and check for nested expansion errors
2. Autoload functions not found
   - **Cause**: Glob pattern not matching symlinks correctly
   - **Fix**: Use `[[ "${file:e}" == "" ]]` check, not complex globs
3. Architecture cache stale after OS upgrade
   - **Symptom**: Wrong arch detection after major macOS update
   - **Fix**: Run `delete_caches` to regenerate

## Quick Debugging Commands

```zsh
# Check syntax
zsh -n ~/.zshrc

# Profile startup
ZSH_PROFILE=true zsh -i -c exit
zprof

# Debug load order
DEBUG=true zsh

# Check if function loaded
type function_name

# Check PATH/FPATH
echo ${PATH} | tr ':' '\n'
echo ${FPATH} | tr ':' '\n'
```

## Common Task Checklists

For complete edit workflows (syntax checks, formatting, whitespace verification, executable permissions), see [`domains/edit-checklist.md`](./domains/edit-checklist.md).

**Quick debugging commands:**
- Syntax check shell: `zsh -n file.zsh`
- Syntax check Ruby: `/usr/bin/ruby -c file.rb`
- Test new shell: `zsh -i -c "type some_alias"`
- Profile startup: `ZSH_PROFILE=true zsh -i -c exit` then `zprof`
- Benchmark startup: 20 iterations of `time zsh -i -c exit`

## Coding Patterns Quick Index

The rules below live in full detail in the domain files -- this is just a
lookup aid, not a substitute for reading them:

- Shell: `&&`/`set -e` interaction, arithmetic increment safety, for-loop
  locality, parameter expansion (`:-` vs `-`), quoting, NULL_GLOB scoping,
  ERR trap `${LINENO}` capture, progressive trap cleanup, stderr capture --
  see [`domains/shell-scripting.md`](./domains/shell-scripting.md)
- Ruby: `EnvVars` as source of truth, memoization, `Pathname` usage, private
  method discipline, single exit point, `GitProcessor` block vs instance form,
  shell delegation pattern, env var inheritance across shell/Ruby boundaries --
  see [`domains/ruby-scripting.md`](./domains/ruby-scripting.md)
- Cross-language: unified color standard, deferred error collection, script
  depth tracking, no hardcoded paths, ASCII-only in code/comments -- see
  [`domains/logging-conventions.md`](./domains/logging-conventions.md),
  [`domains/script-depth-tracking.md`](./domains/script-depth-tracking.md),
  [`domains/path-constants.md`](./domains/path-constants.md),
  [`domains/character-encoding.md`](./domains/character-encoding.md)

## Where to Find Information

| Topic | Location |
|-------|----------|
| ASCII-only requirements | domains/character-encoding.md |
| Cache patterns | domains/zsh-startup.md § Caching |
| Color standards | domains/logging-conventions.md |
| Comment guidelines | domains/comment-philosophy.md |
| Edit workflow | domains/edit-checklist.md |
| EnvVars module usage | domains/path-constants.md § Ruby |
| Fresh install rules | domains/fresh-install.md |
| Git alias patterns | domains/git-config.md |
| Glob qualifiers for performance | domains/shell-scripting.md § Glob Patterns |
| Logging conventions | domains/logging-conventions.md |
| Path constants | domains/path-constants.md |
| Ruby script template | domains/ruby-scripting.md § Script Template |
| Script depth tracking | domains/script-depth-tracking.md |
| Shell script template | domains/shell-scripting.md § Script Template |
| Whitespace rules | domains/whitespace-rules.md |

## Performance Optimization Workflow

When optimizing startup (see zsh-startup.md for full details):

1. **Profile**: `ZSH_PROFILE=true zsh -i -c exit` then `zprof`
2. **Identify**: Look for:
   - High call counts on simple functions
   - Function calls in loops
   - Subprocess forks `$(...)`
3. **Optimize**:
   - Use glob qualifiers `(N/)` for directory filtering (free at expansion time)
   - Keep utility functions for non-glob checks (consistency over micro-optimization)
   - Cache expensive commands
4. **Verify**: Profile again, benchmark with 20+ iterations (`time zsh -i -c exit`)
5. **Document**: Add the resulting pattern/rule to the relevant `domains/` file
   (not here) if it's a new, generalizable technique

---

**Remember**: This file is a navigation guide and operational reference.
Detailed rules live in the instruction files -- don't duplicate them here, and
don't use this file as a changelog (see `CHANGELOG.md` for that).
