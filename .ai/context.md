# Dotfiles Domain Context

## Overview
This file provides domain-specific navigation and operational reference for the dotfiles repository, personal bin scripts, and configs. It complements the formal rules in [`domains/`](./domains/) with debugging guidance and quick-reference material. It is not a changelog or session journal -- see `CHANGELOG.md` for version history.

## Instruction Files (The Source of Truth)
All detailed rules, patterns, and conventions are in `.ai/domains/`. The full file list, with "read when" guidance, is the table in [`instructions.md`](./instructions.md#domain-files) -- it is the single index; not repeated here. Large domains (Ruby, shell, git) are split into a core file plus topic files.

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

- **When rebasing all WIP branches onto an updated `master`**: as of this
  writing the only long-lived WIP branch is `nix-migration`, based directly on
  `master`. See `REBASE-AND-REFACTORING-METHODOLOGY.md` § Forward Rebase for the
  chain mechanics (used if a branch is ever stacked on another), its § Rebase
  Workflow step 3 for the `rebase --onto <new-base> <old-base> <branch>` form
  required when `master`'s tip commit was itself amended (a plain `git rebase
  master` will conflict in that case), and its § 3a for the mandatory
  post-rebase no-functionality-lost checklist -- applies to every branch.
  The former experiment branches (`fresh-install-ruby`, `osx-defaults-ruby`, `deja`,
  `stout-migration`, `test-gpg`) were deleted without an archive: the first two are
  explained in `TechnicalDeepDive.md` § 13, the others are recorded in `ToRevisit.md`
  or can be recreated (e.g. `test-gpg` is just toggling the KEYBASE_/ENCRYPTED_ env vars).

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
  see [`domains/shell-scripting.md`](./domains/shell-scripting.md),
  [`domains/shell-functions-autoload.md`](./domains/shell-functions-autoload.md),
  [`domains/shell-portability-cron.md`](./domains/shell-portability-cron.md)
- Ruby: `EnvVars` as source of truth, memoization, `Pathname` usage, private
  method discipline, single exit point, `GitProcessor` block vs instance form,
  shell delegation pattern, env var inheritance across shell/Ruby boundaries --
  see [`domains/ruby-scripting.md`](./domains/ruby-scripting.md),
  [`domains/ruby-infrastructure.md`](./domains/ruby-infrastructure.md),
  [`domains/ruby-shell-git-io.md`](./domains/ruby-shell-git-io.md),
  [`domains/ruby-performance-idioms.md`](./domains/ruby-performance-idioms.md)
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
| Per-repo git overrides, hooks | domains/git-overrides.md |
| Git state / commit / rebase rules | domains/git-workflow.md |
| Ruby Logging/CliParser/EnvVars | domains/ruby-infrastructure.md |
| Ruby GitProcessor, shell-out, UTF-8 | domains/ruby-shell-git-io.md |
| Ruby performance idioms | domains/ruby-performance-idioms.md |
| Glob qualifiers for performance | domains/shell-portability-cron.md § Glob Patterns |
| Logging conventions | domains/logging-conventions.md |
| Path constants | domains/path-constants.md |
| Ruby script template | domains/ruby-scripting.md § Dual-Mode Ruby Scripts |
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

## Related Repositories

**Known related repo -- `git-remote-gpg-encrypt`** (`${PROJECTS_BASE_DIR}/oss/git-remote-gpg-encrypt`,
standalone, its own git history, not managed by `install-dotfiles.rb`): a Ruby tool
extracted from this repo's `EncryptedBackup` module, with its own trimmed/adapted copy
of `ruby-scripting.md` and friends under its own `.ai/domains/` (see that repo's
`AGENTS.md` for specifics on what was dropped: `Logging`/`EnvVars`/`GitProcessor`/
`CliParser`). It is NOT a fourth directory to blindly propagate identical fixes into --
its rules were deliberately trimmed to that project's own, much smaller, dependency-free
shape. When a Ruby-related refactoring/pattern fix/rule change is made here, check
whether the *equivalent, adapted* version of that fix should also be back-ported to
`git-remote-gpg-encrypt`'s own code and its own `.ai/domains/ruby-scripting.md` -- the
same way a fix might get backported to any other sibling project that forked this
repo's conventions.

**Known related repo -- `homebrew-tap`** (`${PROJECTS_BASE_DIR}/oss/homebrew-tap`,
standalone, its own git history, not managed by `install-dotfiles.rb`): a personal
Homebrew tap (deliberately generic-named, not `homebrew-git-remote-gpg-encrypt` --
intended to hold formulae for any number of future personal tools, not just this one),
currently containing only `Formula/git-remote-gpg-encrypt.rb`. This is how
`git-remote-gpg-encrypt` is installed from `files/--HOME--/Brewfile` (`tap
'vraravam/tap'` + `brew 'vraravam/tap/git-remote-gpg-encrypt'`). Its only Ruby files are
Homebrew Formula DSL files, which follow Homebrew's own established style (enforced by
`brew style`/`brew audit`, see that repo's own `.rubocop.yml`) rather than this repo's
`ruby-scripting.md` conventions -- there is nothing to back-port here the way there is
for `git-remote-gpg-encrypt` above. When `git-remote-gpg-encrypt` cuts a new tagged
release, this tap's `Formula/git-remote-gpg-encrypt.rb` needs its `tag:`/`revision:`
updated to match (see that repo's own `README.md` for the exact steps).

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
FIRST_INSTALL=1 "${DOTFILES_DIR}/scripts/fresh-install-of-osx.sh"

# Second run (pre-configured mode)
"${DOTFILES_DIR}/scripts/fresh-install-of-osx.sh"
```

## Startup Performance Snapshot

**Current startup**: ~30ms average (Apple Silicon, verified via 20-run `time zsh -i -c exit`; re-verify before citing -- see `.ai/context.md` § Bottleneck Analysis for the June 2026 snapshot this superseded)

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

---

**Remember**: This file is a navigation guide and operational reference.
Detailed rules live in the instruction files -- don't duplicate them here, and
don't use this file as a changelog (see `CHANGELOG.md` for that).
