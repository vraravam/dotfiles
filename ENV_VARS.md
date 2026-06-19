# Environment Variables Reference

This document lists all environment variables used by the dotfiles system. These variables are defined in multiple locations and accessed from both shell scripts and Ruby scripts.

## Quick Reference by Category

### Path Variables (Directories)

| Variable | Default | Description | Defined In |
|----------|---------|-------------|------------|
| `HOME` | Shell default | User home directory | Shell (always set) |
| `DOTFILES_DIR` | `~/.config/dotfiles` | Dotfiles repository location | `.shellrc` line 69 |
| `PERSONAL_BIN_DIR` | `~/personal/dev/bin` | Personal scripts/executables | `.shellrc` line 78 |
| `PERSONAL_CONFIGS_DIR` | `~/personal/dev/configs` | Sensitive config files | `.shellrc` line 81 |
| `PERSONAL_PROFILES_DIR` | `~/personal/${USER}/browser-profiles` | Browser profile backups | `.shellrc` line 85 |
| `PROJECTS_BASE_DIR` | `~/dev` | Base directory for git repos | `.shellrc` line 75 |
| `XDG_CACHE_HOME` | `~/.cache` | XDG cache directory | `.shellrc` line 52 |
| `XDG_CONFIG_HOME` | `~/.config` | XDG config directory | `.shellrc` line 48 |
| `XDG_DATA_HOME` | `~/.local/share` | XDG data directory | `.shellrc` line 56 |
| `XDG_STATE_HOME` | `~/.local/state` | XDG state directory | `.shellrc` line 60 |
| `XDG_BIN_HOME` | `~/.local/bin` | XDG bin directory | `.shellrc` line 64 |
| `ZDOTDIR` | `${HOME}` | Zsh dotfiles directory | `.shellrc` line 40 |

### Tool-Specific Paths

| Variable | Default | Description | Defined In |
|----------|---------|-------------|------------|
| `HOMEBREW_PREFIX` | `/opt/homebrew` (ARM) or `/usr/local` (Intel) | Homebrew installation prefix | `brew shellenv` |
| `HOMEBREW_REPOSITORY` | Same as `HOMEBREW_PREFIX` | Homebrew Git repository | `brew shellenv` |
| `ANTIDOTE_HOME` | `~/Library/Caches/antidote` (macOS) | Antidote plugin manager cache | `.shellrc` line 139 |
| `ANTIDOTE_ZSH` | `${HOMEBREW_PREFIX}/opt/antidote/share/antidote/antidote.zsh` | Antidote script location | `.shellrc` line 141 |
| `ANTIDOTE_PLUGIN_ZSH` | `${ZDOTDIR}/.zsh_plugins.zsh` | Generated plugin bundle | `.shellrc` line 168 |
| `ANTIDOTE_PLUGIN_TXT` | `${ZDOTDIR}/.zsh_plugins.txt` | Plugin list source | `.shellrc` line 169 |

### User Identity Variables

| Variable | Default | Description | Defined In |
|----------|---------|-------------|------------|
| `USER` | Shell default | Current user login name | Shell (always set) |
| `SHELL` | `/bin/zsh` | User's default shell | Shell (always set) |
| `GH_USERNAME` | *(must set)* | GitHub username for dotfiles fork | `.shellrc` line 42 ⚠️ |
| `UPSTREAM_GH_USERNAME` | `vraravam` | Parent repo GitHub username | `.shellrc` line 43 |
| `DOTFILES_BRANCH` | `master` | Dotfiles branch to use | `env_vars.rb` line 148 |
| `KEYBASE_USERNAME` | *(optional)* | Keybase username for encrypted backups | `.shellrc` line 44 |
| `KEYBASE_HOME_REPO_NAME` | *(optional)* | Keybase repo for home backup | `.shellrc` line 45 |
| `KEYBASE_PROFILES_REPO_NAME` | *(optional)* | Keybase repo for profiles backup | `.shellrc` line 46 |

### Runtime Flags (Boolean)

| Variable | Description | When Set | Checked In |
|----------|-------------|----------|------------|
| `FIRST_INSTALL` | Vanilla OS first-time installation | Bootstrap command | `env_vars.rb` line 200 |
| `DEBUG` | Enable verbose debug logging | Manually for debugging | `.shellrc` line 16, `env_vars.rb` line 206 |
| `ZSH_PROFILE` | Enable zsh startup profiling | Manually for profiling | `.zshrc` line 11 |
| `FORCE_COLOR` | Force color output in non-TTY | Manually or scripts | `env_vars.rb` line 212 |
| `CACHE_BUST_HEADERS` | Add cache-busting headers to curl | Manually or scripts | `env_vars.rb` line 248 |
| `DIRENV_IN_ENVRC` | Running inside direnv subshell | direnv (automatic) | `env_vars.rb` line 242 |

### Temporary Operation Variables

These are set temporarily for specific operations and cleared afterward:

| Variable | Description | Used By | Defined In |
|----------|-------------|---------|------------|
| `FILTER` | Filter pattern for repo operations | `run-all.rb`, `resurrect-repositories.rb` | `env_vars.rb` line 170 |
| `FOLDER` | Base directory for run-all operations | `run-all.rb` | `env_vars.rb` line 184 |
| `REF_FOLDER` | Reference directory for verification | `resurrect-repositories.rb` | `env_vars.rb` line 177 |
| `MINDEPTH` | Minimum depth for repo search | `run-all.rb` | `env_vars.rb` line 190 |
| `MAXDEPTH` | Maximum depth for repo search | `run-all.rb` | `env_vars.rb` line 194 |

### Internal/System Variables

These are managed automatically by the system and should not be set manually:

| Variable | Description | Managed By |
|----------|-------------|------------|
| `_DOTFILES_SCRIPT_DEPTH` | Script nesting depth for indentation | `logging.rb`, shell scripts |
| `_DOTFILES_CRON_BACKUP_FILE` | Temporary cron backup file path | `suspend_cron` in `.shellrc` |

## Required Customization (⚠️ MUST SET)

Before running `fresh-install-of-osx.sh`, you **MUST** customize these variables in `.shellrc`:

### 1. GitHub Username (Line 42)

```zsh
export GH_USERNAME='your-github-username'  # ⚠️ CHANGE THIS
```

This is used for:
- Cloning your dotfiles fork
- Setting up git remotes
- All GitHub-related operations

### 2. Optional: Keybase Integration (Lines 44-46)

If you use Keybase for encrypted backups:

```zsh
export KEYBASE_USERNAME='your-keybase-username'
export KEYBASE_HOME_REPO_NAME='home-backup'
export KEYBASE_PROFILES_DIR_NAME='profiles-backup'
```

Leave blank if you don't use Keybase.

### 3. Optional: Custom Paths (Lines 75-85)

If your directory structure differs from defaults:

```zsh
export PROJECTS_BASE_DIR="${HOME}/code"              # Default: ~/dev
export PERSONAL_BIN_DIR="${HOME}/bin"                # Default: ~/personal/dev/bin
export PERSONAL_CONFIGS_DIR="${HOME}/configs"        # Default: ~/personal/dev/configs
export PERSONAL_PROFILES_DIR="${HOME}/profiles"      # Default: ~/personal/${USER}/browser-profiles
```

## Where Variables Are Defined

### Source Locations

1. **`.shellrc` (lines 40-85, 139-169, 696)** - Primary definitions
   - All path variables (`*_DIR`, `*_HOME`)
   - User identity variables (`GH_USERNAME`, `KEYBASE_*`)
   - Tool-specific paths (`ANTIDOTE_*`)
   - Internal variables (`_DOTFILES_*`)

2. **`env_vars.rb` (all lines)** - Ruby mirror + runtime methods
   - Constants mirror shell exports (lines 67-148)
   - Runtime flag methods (lines 166-256)
   - Normalized optional strings (lines 153-159)
   - Dynamic values (cron backup file, depth, etc.)

3. **`brew shellenv`** - Homebrew paths (cached in `.zshrc`)
   - `HOMEBREW_PREFIX`
   - `HOMEBREW_REPOSITORY`
   - `HOMEBREW_CELLAR`
   - Path modifications

## How to Access Variables

### In Shell Scripts

```zsh
# Always use ${VAR} brace notation with quotes
config_file="${DOTFILES_DIR}/scripts/data/cleanup.txt"
cd "${PROJECTS_BASE_DIR}" || exit 1

# Never hardcode derived paths
# BAD:  config_dir="${HOME}/.config"
# Good: config_dir="${XDG_CONFIG_HOME}"
```

### In Ruby Scripts

```ruby
require_relative 'utilities/env_vars'

# Path constants (return Pathname objects)
config_file = EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup.txt')
home_dir = EnvVars::HOME  # Pathname object

# Non-path constants (return String or nil)
username = EnvVars::GH_USERNAME
keybase = EnvVars::KEYBASE_USERNAME  # nil if not set

# Runtime flag methods (return Boolean)
if EnvVars.debug?
  puts "Debug mode enabled"
end

if EnvVars.first_install?
  puts "Running first-time installation"
end

# Temporary operation variables (return String/Pathname or nil)
filter = EnvVars.filter       # nil or String
folder = EnvVars.folder       # nil or Pathname
depth = EnvVars.script_depth  # Integer
```

## Bootstrap Command Variables

The bootstrap command in `GettingStarted.md` sets these temporarily:

```zsh
export GH_USERNAME='your-username' \
       DOTFILES_BRANCH='master' \
       DOTFILES_DIR="${HOME}/.config/dotfiles" \
       FIRST_INSTALL='true'
```

These override defaults for the initial installation only.

## Cross-Reference to Code

- **Shell definitions:** `files/--HOME--/.shellrc` lines 40-85, 139-169, 696
- **Ruby mirror:** `scripts/utilities/env_vars.rb` (entire file)
- **Documentation:** `.ai/domains/path-constants.md` (usage patterns)
- **Bootstrap:** `GettingStarted.md` lines 17-20
- **Adoption guide:** `README.md` line 112

## Validation

To check if variables are set correctly:

```zsh
# In shell
echo "DOTFILES_DIR: ${DOTFILES_DIR}"
echo "GH_USERNAME: ${GH_USERNAME}"
echo "PERSONAL_BIN_DIR: ${PERSONAL_BIN_DIR}"

# In Ruby (from dotfiles dir)
ruby -e "require_relative 'scripts/utilities/env_vars'; \
  puts \"HOME: #{EnvVars::HOME}\"; \
  puts \"DOTFILES_DIR: #{EnvVars::DOTFILES_DIR}\"; \
  puts \"GH_USERNAME: #{EnvVars::GH_USERNAME}\""
```

## Common Issues

### Missing GH_USERNAME

**Symptom:** Bootstrap fails with "GitHub username not set"

**Fix:** Edit `files/--HOME--/.shellrc` line 42 before running fresh-install:
```zsh
export GH_USERNAME='your-github-username'
```

### Wrong DOTFILES_DIR

**Symptom:** Scripts can't find files, require_relative fails

**Fix:** Either:
1. Use default location `~/.config/dotfiles` (recommended)
2. Set `DOTFILES_DIR` in bootstrap command AND update `.shellrc` line 69

### Custom Paths Not Respected

**Symptom:** Scripts create directories in default locations instead of custom paths

**Fix:** Customize variables in `.shellrc` BEFORE symlinking via `install-dotfiles.rb`

## See Also

- `.ai/domains/path-constants.md` - Path construction patterns
- `README.md` - How to adopt/customize
- `GettingStarted.md` - Bootstrap command
- `TechnicalDeepDive.md` - Architecture details
