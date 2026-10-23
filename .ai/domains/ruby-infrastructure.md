---
applyTo: "**/*.rb"
name: dotfiles-ruby-infrastructure
description: Use when a Ruby script in this dotfiles repo needs shared infrastructure -- Logging, CliParser option parsing, EnvVars path constants, string color helpers, `require` ordering, utility-module or class structure, or the standard script output format. Covers load order, the Logging module pattern, and the cost of `require` on per-command paths.
---

# Ruby Infrastructure Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules when a Ruby script uses (or adds to) the shared infrastructure modules in `scripts/utilities/`.

**Related files**:
- [`ruby-scripting.md`](./ruby-scripting.md) - Core rules (dual-mode, parameters, exit points, version compatibility) -- read this first
- [`logging-conventions.md`](./logging-conventions.md) - Cross-language color standards and logging patterns
- [`script-depth-tracking.md`](./script-depth-tracking.md) - Nesting depth and auto-indentation
- [`path-constants.md`](./path-constants.md) - EnvVars module usage and Pathname patterns

## Logging

```ruby
Logging.info    "message"    # informational
Logging.success "message"    # success
Logging.warn    "message"    # warning
Logging.error   "message"    # prints error and raises RuntimeError -- callers must rescue if execution should continue
Logging.debug   "message"    # debug
Logging.user_action "message"  # manual step the user must perform after the script exits

# NEVER use Ruby stdlib warn
warn "message"               # BAD -- use Logging.warn instead
```

The log levels mirror the shell functions in `.shellrc`. See [`logging-conventions.md`](./logging-conventions.md) for complete rules on:
- When to use each log level
- Message prefixes (`[script][section]`) for RCA
- Deferred error/warning collection
- Color standards

**Quick reference:**

| Level | When to use |
|---|---|
| `debug` | Expected-absent tools or optional steps silently skipped (e.g. "binary not found -- skipping"). Hidden by default. |
| `info` | Normal progress and idempotency guards ("already configured -- skipping"). |
| `success` | An operation completed successfully. |
| `warn` | Argument-parsing failures followed by `abort`; non-fatal operation failures where execution continues (e.g. rescue blocks that log and move on). |
| `error` | Unexpected operation failures. Raises `RuntimeError` -- callers must `rescue` if processing should continue for remaining items. |
| `user_action` | Manual steps the user must perform after the script (restart an app, run a command, open a URL). |

### Deferred Error/Warning Collection

See [`logging-conventions.md`](./logging-conventions.md) § Deferred Error Collection for complete patterns.

**Quick summary for Ruby:**
```ruby
Logging.increment_script_depth
script_start_time = Logging.print_script_start

Logging.current_section = 'Checking dependencies'
Logging.record_warning "optional tool missing -- some features disabled"
Logging.record_error   "required env var FOO is not set"

# At end of script
Logging.print_script_summary(script_start_time)
```

`record_warning` and `record_error` prefix each entry with `[script_name][current_section]` for traceability. Set `Logging.current_section` to track which logical step is executing.

No macOS notification is sent from Ruby -- `osascript` is not appropriate for
library code. Scripts that need a notification must handle it themselves.

## Script Depth Tracking

See [`script-depth-tracking.md`](./script-depth-tracking.md) for complete details on `_DOTFILES_SCRIPT_DEPTH`.

**Quick summary for Ruby**:
- Increment: `Logging.increment_script_depth` (registers `at_exit` hook automatically)
- Dual purpose: nesting suppression (outermost only prints banners) + auto-indentation (2 spaces per depth)
- Never manually indent log messages
- External tool output intentionally unindented

### Argument-parse failures -- use `warn`, not `error`

```ruby
if nil_or_empty?(options[:required])
  parser.abort_with_usage('Missing required argument.')
end
```

`error` raises `RuntimeError`. For arg-parse failures, prefer
`parser.abort_with_usage` (which calls `abort`) -- it prints usage and exits
cleanly without raising. Reserve `error` for unexpected failures mid-execution.

### Idempotency guard messages -- use `info`, not `warn`

```ruby
if File.exist?(target)
  Logging.info "#{target} already exists -- skipping."
else
  # create ...
end
```

### Action items for the user -- use `user_action`, not `warn`

```ruby
Logging.user_action "Restart the app to apply changes."
Logging.user_action "Run 'bupc' to update nix packages and Homebrew casks."
```

## Path Constants

See [`path-constants.md`](./path-constants.md) for complete rules on environment variables, path construction, and avoiding hardcoded paths.

**Quick summary for Ruby**:
- Use `EnvVars::CONSTANT` (returns Pathname objects)
- Use `Pathname#join()` to build paths
- **Defer `.to_s` until the last possible moment** (system calls, string manipulation, color methods)
- Keep Pathname throughout: function params, return values, local variables
- String interpolation auto-converts: `"#{EnvVars::HOME}"` works
- Never hardcode derived paths: use `EnvVars::XDG_CONFIG_HOME` not `HOME.join('.config')`
- Use `Core::ROOT` for filesystem root

## Option Parsing -- Use `CliParser`

Always use `CliParser.parse` (from `utilities/cli_parser.rb`) for all CLI
option parsing -- never raw `OptionParser` or manual `ARGV` shifting.
`CliParser.parse` is the Ruby equivalent of `getopts` in shell scripts.

`CliParser.parse` automatically:
- Formats the usage banner as `Usage: <script>.cyan <banner>.yellow`
- Adds `-h`/`--help` (prints usage and exits)
- Rescues `InvalidOption` / `MissingArgument` and calls `abort_with_usage`

```ruby
require 'cli_parser'

options = {}
parser = CliParser.parse('<folder> [options]') do |opts|
  opts.separator 'Arguments:'.purple
  opts.separator "  #{'<folder>'.yellow}  Target folder to process"
  opts.separator ''
  opts.separator 'Options:'.purple
  opts.on('-f', '--flag', 'Enable flag behaviour') { options[:flag] = true }
  opts.on('-v', '--value VALUE', 'Required value')  { |v| options[:value] = v }
end

# Guard required positional args (not caught by OptionParser automatically)
if nil_or_empty?(ARGV.first)
  parser.abort_with_usage('Missing required argument: <folder>')
end
```

Rules:
- Pass a **positional arg summary** as the banner string (e.g. `'<folder>'`,
  `'<old> <new> [options]'`). This appears after the script name in the usage
  line.
- Use `opts.separator 'Label:'.purple` for section headings inside the help
  block.
- Use `'<placeholder>'.yellow` for argument names in separator lines.
- Use `parser.abort_with_usage('message')` for post-parse validation failures
  (missing required positional args, conflicting flags, etc.). This prints the
  message via `Logging.warn` followed by the full usage, then exits 1.
- Do NOT add `-h`/`--help` manually -- `CliParser.parse` adds it automatically.

### Usage block structure

The body of `CliParser.parse` follows a fixed layout:

```ruby
parser = CliParser.parse('<old> <new> [options]') do |opts|
  # 1. One-line description of what the script does (no label)
  opts.separator 'Renames all files ending with <old> suffix to <new>.'
  opts.separator ''

  # 2. Arguments section -- positional args only
  opts.separator 'Arguments:'.purple
  opts.separator "  #{'<old>'.yellow}  Original suffix to remove"
  opts.separator "  #{'<new>'.yellow}  Replacement suffix to add"
  opts.separator ''

  # 3. Options section -- flags/switches only (omit if no flags)
  opts.separator 'Options:'.purple
  opts.on('-r', '--recursive', 'Recurse into subdirectories') { options[:recursive] = true }
  opts.separator ''

  # 4. Example line -- always last, uses File.basename(__FILE__).cyan
  opts.separator "  eg: #{File.basename(__FILE__).cyan} -compressed ''"
end
```

Rules for the usage block:
- **Description first** -- a plain `opts.separator` sentence before any labelled
  section. Omit if `CliParser.parse`'s banner string is already self-explanatory.
- **`Arguments:`.purple** -- list every positional arg with `'<name>'.yellow` and
  a short description. Omit section entirely if the script takes no positional args.
- **`Options:`.purple** -- list every flag with `opts.on`. Omit section entirely if
  there are no flags (do not emit an empty `'Options:'.purple` heading).
- **`eg:` line last** -- always use `File.basename(__FILE__).cyan` for the script
  name so the example stays correct if the file is renamed.

## Unified Color Standard (Ruby + Shell)

**See [`logging-conventions.md`](./logging-conventions.md) for the complete unified color standard.**

That file documents:
- Color classification rules (paths, commands, components, booleans, counts, etc.)
- Application guidelines
- Language-specific syntax (Ruby vs shell)
- Deferred error/warning collection
- Script depth tracking
- Message prefixes

The rules apply equally to Ruby and shell scripts for consistency across the codebase.

## Requires

Only `require` what you directly use. Do not transitively pre-load:

```ruby
# BAD in logging.rb -- hash_ext is not used here, push to caller
require 'hash_ext'

# Good -- only require what this file uses
require 'logging'
```

### Remove Unused Requires

After refactoring, always remove `require` and `require_relative` statements
that are no longer used. A require is unused when:
- The module/class is never referenced in the file
- Methods from the module are no longer called
- Constants from the module are not accessed

Scan for unused requires when:
- Replacing method calls with constants from a different module
- Extracting functionality to a new module
- Removing code that was the only user of a require

```ruby
# BAD -- path_utils no longer used after switching to EnvVars constants
require 'path_utils'
require 'env_vars'

home = EnvVars::HOME_DIR  # path_utils not needed

# Good -- only require what is actually used
require 'env_vars'

home = EnvVars::HOME_DIR

# BAD -- inside utilities/, logging no longer used after removing all log calls
require_relative 'logging'
require_relative 'env_vars'

EnvVars::HOME_DIR  # logging not needed

# Good -- only require_relative what is actually used
require_relative 'env_vars'

EnvVars::HOME_DIR
```

This rule applies equally to both `require` and `require_relative` statements.

Exception: `require 'pathname'` must remain even when not directly referenced
in the file body if the file defines Pathname constants at module level -- the
require makes Pathname available to the constant initializers.

### Deleting Methods/Functions -- Mandatory Codebase Scan

**Before deleting ANY method or function as "unused", perform a comprehensive codebase scan to verify no call sites exist.**

A method/function is NOT unused until verified by:
1. **Grep all Ruby files**: `grep -rn "method_name" scripts/ files/`
2. **Grep all shell files**: `grep -rn "function_name" files/ scripts/`
3. **Check git history**: `git log --all -S"def method_name" --oneline` (verify not recently added elsewhere)
4. **Check all branches**: `git grep "method_name" $(git branch -a | grep -v HEAD)`

**Why this matters**: A method may appear unused in the current branch but could be:
- Called from code in other branches under development
- Invoked dynamically via `send`, `public_send`, or `method`
- Referenced in external repositories or scripts
- Used by code that hasn't been committed yet

Deleting without verification can break production code in subtle ways that only appear at runtime.

**Why simple search isn't enough**:
- Methods may be called dynamically (`send`, `public_send`, `method`)
- Shell functions may be called from autoload scripts or other repositories
- Call sites may use aliases or wrapper functions
- Methods may be called from code in other branches being developed

**Safe deletion checklist**:
```bash
# 1. Search all Ruby files for method name
grep -rn "method_name" scripts/

# 2. Search all shell files for function name
grep -rn "function_name" files/

# 3. Check if recently added in other branches
git log --all --since="6 months ago" -S"def method_name" --oneline

# 4. Search across all branches (not just current)
for branch in $(git branch -a | grep -v HEAD); do
  echo "=== ${branch} ==="
  git grep "method_name" "${branch}" -- '*.rb' '*.sh' || true
done

# 5. Syntax check all files after deletion
find scripts -name "*.rb" -exec ruby -c {} \;
find files -name "*.zsh" -o -name "*.sh" | xargs -n1 zsh -n
```

**Only delete when ALL checks pass**: No matches in current branch, no matches in other branches, no recent additions in git history.

### `require` vs `require_relative`

**Ruby community best practice**: Use `require_relative` for all internal files, `require` only for external dependencies (gems, stdlib).

**Benefits of `require_relative`**:
- **Faster**: O(1) direct path resolution vs O(N) `$LOAD_PATH` search
- **Clearer**: Explicitly shows file is part of your project
- **More reliable**: Works regardless of `$LOAD_PATH` or working directory
- **Idiomatic**: Standard Ruby convention endorsed by style guides and RuboCop

#### Current Dotfiles Convention

**Scripts in `${DOTFILES_DIR}/scripts/`** (non-utilities):

Use `require_relative` for utilities and other internal files:

```ruby
# At the top of scripts in ${DOTFILES_DIR}/scripts/:
require 'fileutils'                        # stdlib - plain require
require 'pathname'                         # stdlib - plain require
require_relative 'utilities/logging'       # internal file - require_relative
require_relative 'utilities/cli_parser'    # internal file - require_relative
require_relative 'utilities/env_vars'      # internal file - require_relative

include Logging
```

This is **idiomatic Ruby** and works because the path from script to utilities is fixed and relative.

**Scripts in `${DOTFILES_DIR}/scripts/utilities/`**:

Use `require_relative` for sibling files, `require` for stdlib/gems:

```ruby
# Inside utilities/cli_parser.rb
require 'optparse'                    # stdlib - plain require
require_relative 'logging'            # sibling - require_relative
```

**Scripts in `${PERSONAL_BIN_DIR}`**:

These can use either pattern:

**Option 1** (idiomatic Ruby - recommended):
```ruby
require 'pathname'
require_relative '../../../.config/dotfiles/scripts/utilities/logging'
```

**Option 2** (pragmatic - works via `RUBYLIB`):
```ruby
# RUBYLIB is always set in interactive shells (via .shellrc)
require 'pathname'
require 'logging'  # works because RUBYLIB includes utilities/
```

Choose based on preference. Option 1 is more idiomatic Ruby, Option 2 is more concise.

### Shell integration with `call_utility`

Shell functions invoke Ruby utilities via the `call_utility` helper defined in `.shellrc`, which runs `scripts/call-utility.rb`. Arguments travel as real argv entries -- never spliced into Ruby source -- so values with quotes or spaces are safe, and no `RUBYLIB` setup is needed. It preserves `COLUMNS` for terminal width:

```zsh
# Shell function in .shellrc or .aliases
my_function() {
  call_utility DevEnvironment.setup_dev_environment "--maxdepth=3"
  call_utility Cron.create_crontab -- "${file}"      # '--' makes the rest positional
  call_utility --truthy Keybase.username              # exit 1 if the method returns nil/false
}
```

**Argument conventions** (see `scripts/call-utility.rb`):
- `<Module>.<method>` is the first argument; only the modules in its `UTILITIES` allow-list can be called -- add a new utility module there to expose it
- `--key=value` becomes a keyword argument (`true`/`false` become booleans); everything else is positional; after a literal `--` everything is positional
- `--truthy` also fails (exit 1) when the method returns nil/false, for predicate-style methods

**Benefits of `call_utility`:**
- No string-built Ruby source (no quoting/injection hazards)
- Preserves `COLUMNS` env var (needed for terminal width)
- Runs the system Ruby with `--disable-gems` (saves ~80ms per call; utilities must only use the standard library)
- Ruby availability check (graceful no-op if Ruby not installed)
- Consistent pattern across all shell->Ruby calls

**Do NOT use raw `ruby -e` calls directly:**
```zsh
# BAD -- builds Ruby source from shell values, needs RUBYLIB set up
ruby -e "require 'logging'; Logging.info('${message}')"

# Good -- use the call_utility wrapper
call_utility MacOS.notify -- "${message}" "${title}"
```

**Before the dotfiles repo is cloned** `scripts/call-utility.rb` does not exist, so `call_utility` returns 1 without doing anything. Anything `.shellrc` must do on a vanilla OS (e.g. `suspend_cron`/`resume_cron`/`restore_cron`) therefore keeps a pure-shell fallback, selected with `_call_utility_script_available`.

If a shell function only wraps a single Ruby entry point that is also useful on the command line, prefer an alias for the script itself (e.g. `alias bupc='brew-update-cleanup.rb'`) over a shell function.

### Sorting and grouping `require` statements

Sort `require` statements alphabetically within each group. Keep two groups in
order: stdlib/gem `require` first, then `require_relative` -- each group sorted
independently. A blank line separates the two groups when both are present.

A blank line must also separate the last `require`/`require_relative` line from
the first `include` line:

```ruby
# BAD -- unsorted requires; no blank line before include
require 'logging'
require 'cli_parser'
require 'fileutils'
include Logging

# Good -- sorted within group; blank line before include
require 'cli_parser'
require 'fileutils'
require 'logging'

include Logging

# Good -- stdlib group then require_relative group, each sorted; blank line before include
require 'fileutils'
require 'open3'

require_relative 'logging'
require_relative 'string'

include Logging
```

## Environment Variables

Always use `ENV.fetch` instead of `ENV['...']` for environment variable access:

```ruby
# BAD -- ENV['VAR'] returns nil if VAR is unset; easy to miss in code
value = ENV['FORCE_COLOR']
if !value.to_s.strip.empty?
  # ...
end

# Good -- ENV.fetch with default value
value = ENV.fetch('FORCE_COLOR', '')
if !value.strip.empty?
  # ...
end

# Good -- ENV.fetch with nil default when you want to check presence
value = ENV.fetch('OPTIONAL_VAR', nil)
if value
  # ...
end

# Good -- ENV.fetch without default raises KeyError if missing (use for required vars)
api_key = ENV.fetch('API_KEY')  # Raises if API_KEY not set
```

**Where `ENV` may be read directly**: only inside `env_vars.rb` (the typed accessors every other
script uses) and `env_lite.rb`. `EnvLite` is the dependency-free accessor layer for the modules
underneath `EnvVars` in the require chain (`Core`, `Colorizable`), which cannot require `EnvVars`
without a circular dependency. Everything else uses `EnvVars` (add an accessor there, e.g.
`EnvVars.log_file`, `EnvVars.rubylib`, `EnvVars.script_depth=`, rather than calling `ENV.fetch`).
Dynamic lookups by a name that comes from data (template/YAML `${VAR}` expansion) are the
legitimate exception. Never mutate the process `ENV` to configure one child: pass an env Hash as
the first argument to `system`/`Open3`/`CommandUtils.query` instead.

**Why `ENV.fetch` is better:**
- **Explicit defaults**: `ENV.fetch('VAR', '')` makes it clear the default is empty string
- **Intentional failure**: `ENV.fetch('VAR')` without default raises KeyError for required vars
- **No `.to_s` needed**: When using a default, you get the type you specify
- **Catches typos**: `ENV['VARNAME']` silently returns nil for typos; `ENV.fetch('VARNAME')` raises

**When to use each form:**
```ruby
# Optional var with default value
color = ENV.fetch('FORCE_COLOR', '')

# Optional var where nil vs empty matters
value = ENV.fetch('OPTIONAL', nil)

# Required var (should crash if missing)
token = ENV.fetch('GITHUB_TOKEN')

# Setting env vars (ENV['VAR'] = value is fine for writes)
ENV['MY_VAR'] = 'value'  # OK -- this is a write, not a read
```

### Move String Literal ENV.fetch Calls to EnvVars Module

All `ENV.fetch('STRING_LITERAL', ...)` calls must be moved to the `EnvVars` module
(`scripts/utilities/env_vars.rb`). Only dynamic variable names (where the env var
name is itself a variable) should remain as inline `ENV.fetch` calls.

```ruby
# BAD -- string literal ENV.fetch scattered in codebase
def running_in_tty?
  $stdout.tty? || !ENV.fetch('FORCE_COLOR', '').strip.empty?
end

def script_depth
  ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i
end

# Good -- centralized in EnvVars module
module EnvVars
  # Returns true if FORCE_COLOR is set (used by color output methods).
  def self.force_color?
    !ENV.fetch('FORCE_COLOR', '').strip.empty?
  end

  # Current script depth (incremented by increment_script_depth).
  def self.script_depth
    ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i
  end
end

# Usage in other files
def running_in_tty?
  $stdout.tty? || EnvVars.force_color?
end

def script_depth
  EnvVars.script_depth
end
```

**EnvVars Structure -- Constants vs Methods:**

- **Pathname env vars → Constants**: Path variables that never change at runtime are
  Pathname constants (e.g., `HOME`, `DOTFILES_DIR`, `XDG_CACHE_HOME`) because Pathname
  objects are immutable and the path resolution is expensive -- freeze once at load time.

- **Non-Pathname env vars → Methods**: All non-Pathname env vars must be methods
  (e.g., `force_color?`, `script_depth`, `debug?`) so they are re-evaluated on
  each access. This allows them to reflect runtime changes (e.g., script depth
  increments, debug flag toggled mid-execution).

- **Methods can return Pathname**: Methods that compute paths dynamically (e.g.,
  `cron_backup_file`) should return Pathname objects directly so callers don't need
  to wrap the result. This keeps Pathname usage consistent throughout the codebase.

```ruby
# Good -- Pathname constants (expensive to construct, immutable, never change)
HOME = Pathname(ENV.fetch('HOME', '~')).expand_path.freeze
DOTFILES_DIR = Pathname(ENV.fetch('DOTFILES_DIR', HOME.join('.config', 'dotfiles'))).expand_path.freeze

# Good -- Non-Pathname methods (evaluated on each call)
def self.force_color?
  !ENV.fetch('FORCE_COLOR', '').strip.empty?
end

def self.script_depth
  ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i
end

# Good -- Methods can return Pathname when appropriate
def self.cron_backup_file
  Pathname(
    ENV.fetch('_DOTFILES_CRON_BACKUP_FILE') do
      TMPDIR.join('crontab_backup').to_s
    end
  )
end

# BAD -- non-Pathname as constant (won't reflect runtime changes)
SCRIPT_DEPTH = ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i  # frozen at load time
```

**Exceptions** -- inline `ENV.fetch` IS correct when:
- The env var name is dynamic (variable, not literal): `ENV.fetch(var_name, '')`
- Setting env vars: `ENV['VAR'] = value`
- Inside `env_vars.rb` itself (the centralization target)

**Why centralize:**
- **Single source of truth**: All env var defaults and access patterns in one place
- **DRY**: Repeated `ENV.fetch('SAME_VAR', 'same_default')` across files is duplication
- **Discoverability**: New developers see all env vars used by the system in one file
- **Type safety**: EnvVars can provide typed accessors (`.to_i`, `Pathname()`, etc.)
- **Documentation**: Comments in EnvVars document what each var is for

**Scan rule**: When adding/editing code, search for `ENV.fetch('` with a string
literal. If it's not in `env_vars.rb`, move it there. Use methods for non-Pathname
values, constants only for Pathname objects.

## String Colors

Color methods are defined in `utilities/colorizable.rb` (shared module) and extended to both `String` (via `string_ext.rb`) and `Pathname` (via `pathname_ext.rb`). They:
- Wrap the string in ANSI escape codes (no-op when stdout is not a TTY)
- Automatically substitute `${HOME}` with `~` in any path passed to them
- Return String objects (important for `Pathname#cyan` - it converts to colored string)

**Never** call `replace_home_path_with_tilde` before passing a path to a color
method -- the substitution happens inside. Only call it explicitly for bare
`puts`/`print` call sites that display paths without any color method.

**Color methods work on both String and Pathname**: The `Colorizable` module is included
in both `String` (via `string_ext.rb`) and `Pathname` (via `pathname_ext.rb`). Since
`logging.rb` requires `pathname_ext`, all files that require logging automatically get
Pathname color methods:

```ruby
# Both work - Pathname color methods available everywhere logging is required
profile_folder = EnvVars::HOME.join('.config')
info "Processing '#{profile_folder.cyan}'"  # Works! Returns colored String

# String color methods also work
info "Processing '#{profile_folder.to_s.cyan}'"  # Also works, but .to_s is redundant

# Non-Pathname objects still need .to_s
count = 42
info "Processed #{count.to_s.purple} files"  # .to_s required for Integer
```

**Rule**: Call color methods directly on Pathname objects. Only use `.to_s` before color
methods when the object is NOT a String or Pathname (e.g., Integer, Boolean, Array).

### Available methods

| Method | ANSI | Typical use |
|---|---|---|
| `.red` | normal red | `'Usage'` label (auto via `CliParser`); error messages; failure counts |
| `.light_red` | bright red | `'**WARN**'` label (auto via `Logging.warn`) |
| `.green` | normal green | `'**SUCCESS**'` label (auto); success/positive counts; yes-option in prompts |
| `.light_green` | bright green | -- (available; no fixed convention) |
| `.orange` | normal orange | Boolean values (`true`/`false`) |
| `.yellow` | bright yellow | Argument placeholders in usage (`'<folder>'.yellow`); key names in key-value output; summary sub-headers |
| `.blue` | normal blue | Verbose/debug-only supplementary output |
| `.light_blue` | bright blue | Timestamps and durations (used internally by `Logging`) |
| `.purple` | normal purple | `opts.separator` section headings in usage blocks (`'Options:'.purple`); neutral/informational counts |
| `.light_purple` | bright purple | `'**DEBUG**'` label (auto via `Logging.debug`) |
| `.cyan` | normal cyan | File/folder paths; script name in banner (auto via `CliParser`) |
| `.light_cyan` | bright cyan | Domain/preference identifiers (`com.apple.Finder`) |
| `.dark_gray` | dark gray | -- (available; no fixed convention) |
| `.light_gray` | light gray | -- (available; no fixed convention) |
| `.white` | bright white | -- (available; no fixed convention) |
| `.black` | black | -- (available; no fixed convention) |

### Conventions

```ruby
# Usage block -- section labels purple, placeholders yellow, script example cyan
opts.separator 'Arguments:'.purple
opts.separator "  #{'<folder>'.yellow}  Target folder to process"
opts.separator "  eg: #{File.basename(__FILE__).cyan} /path/to/folder"

# Paths in log messages -- color method handles tilde substitution
Logging.info "Processing '#{folder.cyan}'"
Logging.warn "Skipping '#{path.cyan}': already exists"

# Counts in summary output -- green for good, red for bad
puts "  Processed: #{count.to_s.green}"
puts "  Errors:    #{errors.positive? ? errors.to_s.red : errors}"

# Sub-headers inside a summary
Logging.info 'Summary'.yellow
```

## Module / Class Structure

### Ruby Class Organization Pattern

**When creating or refactoring Ruby class/module files, follow this organization:**

1. **Class methods** (public class methods first)
2. **`initialize`** (constructor, if applicable)
3. **Query methods** (read-only state inspection)
   - Memoized queries first (methods using `@_var ||=`)
   - Non-memoized queries second (computed/enumeration methods)
4. **Mutation methods** (methods that modify state)
5. **`private`** keyword followed by private methods

This organization improves code navigation - readers see state inspection methods before
state modification methods, and memoized queries are grouped together for easy identification.

**Example structure:**

```ruby
class GitProcessor
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  def self.repo?(path)
    return false if nil_or_empty?(path)
    # ... implementation ...
  end

  def self.clone(url:, target:)
    # ... implementation ...
  end

  # ---------------------------------------------------------------------------
  # Constructor
  # ---------------------------------------------------------------------------

  def initialize(dir:, dry_run: false)
    @dir = dir
    @dry_run = dry_run
  end

  # ---------------------------------------------------------------------------
  # Query methods (read-only state inspection)
  # ---------------------------------------------------------------------------

  # Memoized queries - core repo state that doesn't change during instance lifetime

  def repo?
    @_is_repo ||= @dir.join('.git').exist?
  end

  def config_value(key)
    @_config_values ||= {}
    @_config_values[key] ||= begin
      # ... implementation ...
    end
  end

  # Non-memoized queries - computed values or enumeration

  def status(*switches)
    _execute('status', *switches)
  end

  def commit_count
    out, = _execute('rev-list', '--all', '--count')
    out.strip.to_i
  end

  # ---------------------------------------------------------------------------
  # Mutation methods (modify state)
  # ---------------------------------------------------------------------------

  def add(pathspec = '.')
    _execute('add', pathspec)
  end

  def commit(message)
    _execute('commit', '-m', message)
  end

  # ---------------------------------------------------------------------------
  # Private methods
  # ---------------------------------------------------------------------------

  private

  def _execute(*args)
    # ... implementation ...
  end

  def _format_error(status, stdout, stderr)
    # ... implementation ...
  end
end
```

**Why this order:**

- **Class methods first**: Readers see the public API immediately (often used without instantiation)
- **Initialize second**: Natural transition from class-level to instance-level concerns
- **Query methods third**: State inspection before modification - shows "what can I check?" before "what can I change?"
- **Memoized queries grouped**: Easy to see what's cached, what's computed fresh
- **Mutation methods fourth**: Operations that change state come after queries
- **Private last**: Implementation details that readers can skip

**Query vs Mutation classification:**

- **Query**: Method that only reads state, returns information, has no side effects
  - Examples: `repo?`, `config_value`, `status`, `commit_count`, `ls_files`, `shallow?`
  - Name patterns: Ends with `?`, reads config/state, enumerates/searches
- **Mutation**: Method that modifies state (filesystem, git repo, system state)
  - Examples: `add`, `commit`, `push`, `config_set`, `init`, `recreate`, `delete_tag`
  - Name patterns: Imperative verbs, `set_*`, `delete_*`, `create_*`, `update_*`

**Section separators**: Use `# ---------------------------------------------------------------------------` with descriptive labels for all sections in utility files (even short ones) to clearly demarcate organization.

**Files following this pattern**: `git_processor.rb`, `git_workspace.rb`, `dev_environment.rb`, `mise.rb`, `direnv.rb`, `keybase.rb`, `macos.rb`, `profiles_repo.rb`, `plist.rb`, `path_utils.rb`, `command_utils.rb`.

**GitProcessor as reference**: See `scripts/utilities/git_processor.rb` for a complete example:
- Class methods: lines 59-94
- Constructor: lines 96-105
- Query methods: lines 107-199 (memoized 111-157, non-memoized 158-199)
- Mutation methods: lines 200-398
- Private methods: lines 399-end

### Core Module Usage Pattern

**All utility modules must properly include/extend Core for unqualified `nil_or_empty?` calls:**

```ruby
# Modules with extend self - need BOTH include and extend
module MyModule
  extend self
  include Core  # For instance methods (in blocks)
  extend Core   # For module methods
end

# Modules with only module methods - extend only
module MyModule
  extend Core  # Makes Core methods available as module methods
end

# Classes - need BOTH include and extend
class MyClass
  include Core  # For instance methods
  extend Core   # For class methods (if class methods need Core)
end

# Core module itself - extend self only (can't extend itself)
module Core
  extend self
end
```

**Why both `include` and `extend` for modules with `extend self`?**

- `include Core` alone does NOT make Core methods available as module methods
- `extend Core` makes them available as module methods
- Having both ensures Core methods work everywhere: direct calls, blocks, instance context

**Examples:**

```ruby
# ✅ CORRECT: Module with extend self
module Antidote
  extend self
  include Core  # For use in blocks/instance context
  extend Core   # For module method calls

  def update_plugins
    return if nil_or_empty?(path)  # Works!
  end
end

# ✅ CORRECT: Module with only module methods
module EnvVars
  extend Core  # Only need extend, no extend self

  def self.script_depth
    ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i
  end
end

# ✅ CORRECT: Class with both instance and class methods
class GitProcessor
  include Core  # For instance methods
  extend Core   # For class methods

  def remote_url
    return nil if nil_or_empty?(url)  # Instance method - works via include
  end

  def self.repo?(path)
    return false if nil_or_empty?(path)  # Class method - works via extend
  end
end

# ❌ WRONG: Module with extend self but only include Core
module MyModule
  extend self
  include Core  # NOT ENOUGH!

  def my_method
    nil_or_empty?(val)  # ERROR: undefined method
  end
end
```

### Private Helpers

```ruby
module MyModule
  # Public API -- no prefix, no private declaration needed for simple modules
  def self.public_method(arg)
    _private_helper(arg)
  end

  # Private helpers -- prefix with _ AND use private_class_method
  def self._private_helper(arg)
    # ...
  end
  private_class_method :_private_helper
end
```

For classes, use `private` keyword:

```ruby
class MyClass
  def public_method; end

  private

  def _internal_helper; end
end
```

## Utility Modules -- Logging Pattern

**CRITICAL RULE**: All utility modules in `scripts/utilities/` use `extend self`
to make all methods available as module methods (e.g., `Cron.suspend_cron`,
`Logging.debug`, `Logging.info`, etc.). This allows them to be called from both
Ruby scripts and shell wrappers.

Do NOT use `include Logging` in utility modules. The combination `extend self` +
`include Logging` does NOT make Logging's methods available as module methods.
Always use fully-qualified method calls instead (e.g., `Logging.debug`,
`Logging.info`).

```ruby
# BAD -- Logging methods won't be available
module Cron
  extend self
  include Logging  # This doesn't work!

  def suspend_cron
    debug 'Suspending...'  # ERROR: undefined method 'debug'
  end
end

# Good -- Qualify all Logging calls
module Cron
  extend self

  # Note: Logging methods must be qualified (Logging.debug, Logging.info, etc.)
  # because 'include Logging' + 'extend self' doesn't make included methods
  # available as module methods.

  def suspend_cron
    Logging.debug 'Suspending...'  # Works correctly
  end
end
```

**Why this matters:**
- Shell functions delegate to Ruby utilities via `call_utility` (e.g., `suspend_cron` → `Cron.suspend_cron`)
- Ruby scripts call utility modules directly (e.g., `Cron.with_cron_suspended { }`)
- Both contexts need the same behavior
- Qualified calls work everywhere: module methods, class methods, instance methods

**This rule applies to ALL files in `scripts/utilities/`** including:
- Modules with `extend self` (cron.rb, keybase.rb, antidote.rb, collection_processor.rb, etc.)
- Classes (cli_parser.rb's Parser class, etc.)
- Any other code structures

**Exception:** Top-level scripts in `scripts/` (not `scripts/utilities/`) can use
`include Logging` because they execute in the main context where `include` works
as expected.

## Script Output Format

Each Ruby script must print:
1. A `section_header` with the script name.
2. Start time (`info "Starting..."`)
3. Main logic with appropriate `info`/`success`/`warn` per operation.
4. A summary before exit (counts of success/failure/skipped).
5. End time and duration.

## Cost of `require` on the Per-Command Path

Utilities such as `git_commands.rb` run on every `git cc`/`push`/`pull`/`upreb` and from hooks, so
the stdlib they load eagerly is paid on every invocation (measured on system Ruby 2.6: `json` 4.5ms,
`time` 4.3ms, `fileutils` 7ms, `yaml` 29ms, `rexml/document` 27ms; `open3`/`set`/`pathname` ~1ms each).

- Load a heavy library lazily, inside the one method that needs it, when that method is rarely
  reached (`Logging::Sinks` requires `json`/`time` only when `LOG_FORMAT=json` is actually used;
  `Core.mark_updated!` requires `fileutils` on first call). A repeated `require` is a cheap no-op.
- Keep `yaml`/`rexml` out of shared utilities; require them in the script that parses with them.
- Re-measure with `ruby -I scripts/utilities -rbenchmark -e 'p Benchmark.realtime { require "git_commands" }'`
  after changing a utility's requires.
