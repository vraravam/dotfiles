---
applyTo: "all cross-language scripts and configuration files"
---

# Path Constants and Construction

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Never hardcode user-specific or machine-specific paths. Always use environment variables that are defined in `.shellrc` and centralized in the `EnvVars` module (Ruby).

**For a complete reference of all environment variables, see [ENV_VARS.md](../../ENV_VARS.md) in the repository root.**

## Available Path Constants

| Concept | Shell | Ruby | Description |
|---------|-------|------|-------------|
| Home directory | `${HOME}` | `EnvVars::HOME` | User home directory |
| Dotfiles | `${DOTFILES_DIR}` | `EnvVars::DOTFILES_DIR` | `~/.config/dotfiles` |
| Personal bin | `${PERSONAL_BIN_DIR}` | `EnvVars::PERSONAL_BIN_DIR` | `~/personal/dev/bin` |
| Personal configs | `${PERSONAL_CONFIGS_DIR}` | `EnvVars::PERSONAL_CONFIGS_DIR` | `~/personal/dev/configs` |
| Personal profiles | (N/A in shell) | `EnvVars::PERSONAL_PROFILES_DIR` | `~/personal/dev/profiles` |
| Projects base | `${PROJECTS_BASE_DIR}` | `EnvVars::PROJECTS_BASE_DIR` | `~/dev` or custom |
| XDG config | `${XDG_CONFIG_HOME}` | `EnvVars::XDG_CONFIG_HOME` | `~/.config` |
| XDG cache | `${XDG_CACHE_HOME}` | `EnvVars::XDG_CACHE_HOME` | `~/.cache` |
| XDG bin | `${XDG_BIN_HOME}` | (N/A in Ruby) | `~/.local/bin` |
| XDG data | `${XDG_DATA_HOME}` | `EnvVars::XDG_DATA_HOME` | `~/.local/share` |
| XDG state | `${XDG_STATE_HOME}` | `EnvVars::XDG_STATE_HOME` | `~/.local/state` |
| Homebrew prefix | `${HOMEBREW_PREFIX}` | `EnvVars::HOMEBREW_PREFIX` | `/opt/homebrew` or `/usr/local` |
| Homebrew repo | (N/A in shell) | `EnvVars::HOMEBREW_REPOSITORY` | Homebrew's Git repository |

## Language-Specific Usage

### Shell

**Always use `${var}` brace notation** (not bare `$var`) to unambiguously delimit variable names:

```zsh
# Good -- braces delimit variable name
config_file="${DOTFILES_DIR}/scripts/data/cleanup.txt"
nested="${HOME}/.config/zsh/completions"

# BAD -- ambiguous parsing or concatenation issues
config_file="$DOTFILES_DIR/scripts/data/cleanup.txt"
```

**Always quote variable expansions** (prevents word-splitting):

```zsh
# Good -- quoted
cd "${DOTFILES_DIR}/scripts" || exit 1
rm -f "${XDG_CACHE_HOME}/cache.db"

# BAD -- unquoted (breaks if path contains spaces)
cd $DOTFILES_DIR/scripts || exit 1
```

**Never hardcode derived paths**:

```zsh
# BAD -- hardcoded
config_dir="${HOME}/.config"
dotfiles="${HOME}/.config/dotfiles"
brew_prefix="/opt/homebrew"

# Good -- use env vars
config_dir="${XDG_CONFIG_HOME}"
dotfiles="${DOTFILES_DIR}"
brew_prefix="${HOMEBREW_PREFIX}"
```

**`${HOME}` itself is acceptable** as a standard shell variable, but prefer named env vars for its derived paths:

```zsh
# Acceptable
user_home="${HOME}"

# But prefer named vars for derived paths
config_dir="${XDG_CONFIG_HOME}"     # NOT "${HOME}/.config"
dotfiles="${DOTFILES_DIR}"          # NOT "${HOME}/.config/dotfiles"
```

### Ruby

**Use `EnvVars::CONSTANT`** (returns Pathname objects, not strings):

```ruby
require 'env_vars'

# Good -- returns Pathname
config_file = EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup.txt')
nested = EnvVars::HOME.join('.config', 'zsh', 'completions')

# BAD -- hardcoded
config_file = Pathname.new("#{ENV['HOME']}/.config/dotfiles/scripts/data/cleanup.txt")
```

**Always use `Pathname#join()` to build paths** (maintains type consistency):

```ruby
# Good -- returns Pathname, can chain further operations
config = EnvVars::DOTFILES_DIR.join('config', 'settings.yml')
subdir = config.dirname.join('cache')

# BAD -- converts to String too early, loses Pathname methods
config = File.join(EnvVars::DOTFILES_DIR.to_s, 'config', 'settings.yml')
```

**Defer `.to_s` until the last possible moment** -- keep Pathname objects throughout code, only convert to String at system call boundaries:

```ruby
# Good -- Pathname throughout, .to_s only at system boundary
profile_folder = EnvVars::HOME.join('.config', 'browser', 'Profile 1')
if File.directory?(profile_folder)  # File methods accept Pathname
  du_out, = Open3.capture3('/usr/bin/du', '-sk', profile_folder.to_s)  # .to_s at boundary
end

# BAD -- premature .to_s loses Pathname methods and type safety
profile_folder = EnvVars::HOME.join('.config', 'browser', 'Profile 1').to_s
if File.directory?(profile_folder)  # now a String, not Pathname
  du_out, = Open3.capture3('/usr/bin/du', '-sk', profile_folder)
end
```

**Why defer `.to_s`**:
- Preserves Pathname methods (`.dirname`, `.basename`, `.join`, `.exist?`, etc.)
- Maintains type safety throughout the call chain
- Makes refactoring safer (callers know they receive Pathname)
- Most Ruby stdlib methods (`File`, `Dir`, `FileUtils`) accept Pathname natively

**String interpolation auto-converts Pathname to String**:

```ruby
# Both are equivalent -- interpolation calls .to_s automatically
puts "Processing #{EnvVars::HOME}"
puts "Processing #{EnvVars::HOME.to_s}"

# Color methods require explicit .to_s (they're defined on String, not Pathname)
info "Processing '#{EnvVars::HOME.join('dotfiles').to_s.cyan}'"
```

**Function parameters should accept Pathname**:

```ruby
# Good -- accepts Pathname, returns Pathname
def build_config_path(base_dir)
  base_dir.join('config', 'settings.yml')
end

# Call site -- pass Pathname, receive Pathname
config = build_config_path(EnvVars::HOME)
File.read(config)  # File.read accepts Pathname

# BAD -- forces caller to convert
def build_config_path(base_dir_str)
  File.join(base_dir_str, 'config', 'settings.yml')  # returns String
end
```

**When to use `.to_s` (and ONLY these cases)**:

1. **System commands**: `system()`, `Open3.capture3()`, backticks
2. **String manipulation**: when you need String methods like `.gsub`, `.split`
3. **Color methods**: they're defined on String, not Pathname (see logging-conventions.md)
4. **String concatenation**: rare cases where `+` is required (prefer `Pathname#join` instead)

```ruby
# 1. System commands require String arguments
system('git', '-C', repo_path.to_s, 'status')

# 2. String manipulation (need .gsub for tilde replacement)
display_path = folder.to_s.gsub(EnvVars::HOME.to_s, '~')

# 3. Color methods (defined on String, not Pathname)
info "Processing '#{config_file.to_s.cyan}'"

# 4. String concatenation (but prefer Pathname.join instead)
# BAD
path = EnvVars::HOME.to_s + '/' + 'file.txt'
# Good
path = EnvVars::HOME.join('file.txt')
```

**Use `PathUtils::ROOT` for filesystem root**:

```ruby
require 'path_utils'

# Good -- cross-platform filesystem root
system_path = PathUtils::ROOT.join('etc', 'hosts')

# BAD -- hardcoded Unix root
system_path = Pathname.new('/etc/hosts')
```

`PathUtils::ROOT` uses `File::SEPARATOR` internally and works on Windows (`C:\`).

**Never hardcode derived paths**:

```ruby
# BAD -- hardcoded
config_dir = Pathname.new(ENV['HOME']).join('.config')
dotfiles = Pathname.new("#{ENV['HOME']}/.config/dotfiles")

# Good -- use EnvVars
config_dir = EnvVars::XDG_CONFIG_HOME
dotfiles = EnvVars::DOTFILES_DIR  # already includes .config/dotfiles
```

## Scan Rule

When editing any script or config file, flag every occurrence of a literal expanded path and replace it with the corresponding env var:

| Find | Replace (Shell) | Replace (Ruby) |
|------|-----------------|----------------|
| `"${HOME}/dev"` | `"${PROJECTS_BASE_DIR}"` | `EnvVars::PROJECTS_BASE_DIR` |
| `"${HOME}/personal/dev/bin"` | `"${PERSONAL_BIN_DIR}"` | `EnvVars::PERSONAL_BIN_DIR` |
| `"${HOME}/personal/dev/configs"` | `"${PERSONAL_CONFIGS_DIR}"` | `EnvVars::PERSONAL_CONFIGS_DIR` |
| `"${HOME}/.config/dotfiles"` | `"${DOTFILES_DIR}"` | `EnvVars::DOTFILES_DIR` |
| `"${HOME}/.config"` | `"${XDG_CONFIG_HOME}"` | `EnvVars::XDG_CONFIG_HOME` |
| `"${HOME}/.cache"` | `"${XDG_CACHE_HOME}"` | `EnvVars::XDG_CACHE_HOME` |
| `"${HOME}/.local/bin"` | `"${XDG_BIN_HOME}"` | N/A |
| `"${HOME}/.local/share"` | `"${XDG_DATA_HOME}"` | `EnvVars::XDG_DATA_HOME` |
| `"${HOME}/.local/state"` | `"${XDG_STATE_HOME}"` | `EnvVars::XDG_STATE_HOME` |
| `/opt/homebrew` or `/usr/local` | `"${HOMEBREW_PREFIX}"` | `EnvVars::HOMEBREW_PREFIX` |

## Why This Matters

1. **Portability**: Scripts work on any machine regardless of directory structure
2. **Maintainability**: Change base paths in one place (`.shellrc` / `EnvVars`)
3. **Consistency**: All scripts use the same path conventions
4. **Testability**: Easier to mock paths in tests
5. **Safety**: Reduces hardcoded assumptions about filesystem layout
