---
applyTo: "**/*.rb"
---

# Ruby Script Instructions

Apply these rules when writing or editing any Ruby script in this repository.

## Version Compatibility

All Ruby scripts in `$DOTFILES_DIR/scripts/` (including `utilities/`) must be
compatible with **Ruby 2.6** (the system Ruby available on a vanilla macOS).
Scripts in `$PERSONAL_BIN_DIR` may target newer versions but prefer 2.6 compat.

Do NOT use:
- Endless range `(1..)` -- use `(1..Float::INFINITY)` or avoid
- Pattern matching (`case x in`) -- Ruby 3.0+
- Numbered block parameters (`_1`, `_2`) -- Ruby 2.7+
- Rightward assignment (`=> variable`) -- Ruby 3.0+
- Hash shorthand syntax (`{x:, y:}`) -- Ruby 3.1+

### Verification

After editing any Ruby file, verify it parses with Ruby 2.6:

```bash
/usr/bin/ruby -c path/to/script.rb
```

This command must succeed with no syntax errors. Run it before formatting.

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

### `require` vs `require_relative`

Never use `require_relative` outside of `$DOTFILES_DIR/scripts/utilities/`.
Use plain `require` everywhere else -- it works because `RUBYLIB` is set by
`.shellrc` to include the utilities directory at runtime:

```ruby
# BAD -- require_relative is fragile outside utilities/; breaks when the script
# is invoked from a different working directory or via a symlink
require_relative '../scripts/utilities/logging'

# Good -- RUBYLIB includes utilities/, so bare require always works
require 'logging'
require 'cli_parser'
```

Exception: scripts inside `$DOTFILES_DIR/scripts/utilities/` **must** use
`require_relative` for sibling files in the same directory, and **must not** use
`require_relative` for anything else. Use plain `require` for stdlib and gems
even inside `utilities/`:

```ruby
# Inside utilities/cli_parser.rb -- Good
require 'optparse'           # stdlib -- plain require
require_relative 'logging'   # sibling script -- require_relative

# Inside utilities/logging.rb -- BAD
require_relative 'optparse'  # optparse is stdlib, not a sibling script
```

This keeps `require_relative` paths within `utilities/` as an explicit,
auditable list of intra-module dependencies. A `require_relative` path pointing
outside `utilities/` is always wrong -- it would be fragile when the script is
invoked from a different working directory or via a symlink.

Exception: `$DOTFILES_DIR/scripts/` (non-utilities) scripts must additionally
prepend the utilities path to `$LOAD_PATH` before any `require` calls. This is
necessary because during `FIRST_INSTALL` (vanilla OS), `.shellrc` has not yet
been sourced when `install-dotfiles.rb` first runs, so `RUBYLIB` is not set yet:

```ruby
# At the top of any script in $DOTFILES_DIR/scripts/ (not utilities/):
$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'logging'
require 'cli_parser'
```

Scripts in `$PERSONAL_BIN_DIR` are only ever run in an interactive shell where
`.shellrc` is already sourced, so `RUBYLIB` is always set -- no `$LOAD_PATH`
manipulation needed.

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

## Quoting

Prefer **single quotes** for static strings with no interpolation. Use **double
quotes** only when the string contains `#{}` interpolation or escape sequences
(`\n`, `\t`, etc.):

```ruby
# Good -- single quotes for static strings
sep = '------'
raise 'File not found'
Logging.info 'Already installed -- skipping.'

# Good -- double quotes when interpolating
Logging.info "Processing #{repo_name}"
msg = "Done: #{count} files"

# BAD -- double quotes on strings with no interpolation (unnecessary)
sep = "------"
raise "File not found"
```

## Path Construction

Never use hardcoded `/` for path separators. Always use Ruby's cross-platform
path utilities to ensure Windows compatibility.

### File.join for Path Construction

Use `File.join` for constructing paths from segments:

```ruby
# BAD -- hardcoded '/' breaks on Windows
path = "#{home}/.config/dotfiles"
file = dir + '/scripts/data/cleanup-browser-files.txt'

# Good -- File.join uses the platform's separator
path = File.join(home, '.config', 'dotfiles')
file = File.join(dir, 'scripts', 'data', 'cleanup-browser-files.txt')
```

### Pathname for Complex Path Operations

Use `Pathname` from stdlib for path manipulation (dirname, basename, expand_path, etc.):

```ruby
require 'pathname'

# Good -- Pathname handles platform differences
path = Pathname.new(folder).expand_path
parent = path.dirname
name = path.basename
```

### File::SEPARATOR for Explicit Separators

Only use `File::SEPARATOR` when you genuinely need the separator character itself
(e.g., splitting a PATH environment variable). For path construction, prefer `File.join`:

```ruby
# Rare case where SEPARATOR is needed:
paths = env_path.split(File::SEPARATOR)

# But for building paths, use File.join:
full_path = File.join(base, 'subdir', 'file.txt')
```

### Cross-Platform Considerations

- `File.join` automatically uses `\` on Windows and `/` on Unix
- `Pathname` methods are platform-aware
- Hardcoded `/` will break on Windows (paths like `C:\Users\...`)
- This applies to all path operations: construction, joining, splitting

## EnvVars Module -- Single Source of Truth

The `EnvVars` module (`scripts/utilities/env_vars.rb`) is the single source of
truth for all environment-based directory paths. All constants are **Pathname
objects**, not strings.

### Available Constants

```ruby
EnvVars::HOME                    # $HOME as Pathname
EnvVars::DOTFILES_DIR            # $DOTFILES_DIR as Pathname
EnvVars::PERSONAL_BIN_DIR        # $PERSONAL_BIN_DIR as Pathname
EnvVars::PERSONAL_CONFIGS_DIR    # $PERSONAL_CONFIGS_DIR as Pathname
EnvVars::PERSONAL_PROFILES_DIR   # $PERSONAL_PROFILES_DIR as Pathname
EnvVars::PROJECTS_BASE_DIR       # $PROJECTS_BASE_DIR as Pathname
EnvVars::XDG_CACHE_HOME          # $XDG_CACHE_HOME as Pathname
EnvVars::HOMEBREW_PREFIX         # $HOMEBREW_PREFIX as Pathname
EnvVars::HOMEBREW_REPOSITORY     # $HOMEBREW_REPOSITORY as Pathname
```

### Usage Pattern -- Pathname.join()

Always use `Pathname#join()` to build paths from EnvVars constants. This returns
a Pathname object, maintaining type consistency throughout the call chain:

```ruby
# Good -- returns Pathname, can chain further operations
config_file = EnvVars::DOTFILES_DIR.join('scripts', 'data', 'cleanup-browser-files.txt')
nested = EnvVars::HOME.join('.config', 'zsh', 'completions')

# BAD -- converts to String too early, loses Pathname methods
config_file = File.join(EnvVars::DOTFILES_DIR.to_s, 'scripts', 'data', 'cleanup-browser-files.txt')
```

### Delay .to_s Until System Command Boundaries

Keep Pathname objects throughout your code. Only convert to String when passing
to system commands (`system`, `Open3.capture3`, etc.) or functions that explicitly
require String arguments:

```ruby
# Good -- Pathname throughout, .to_s only at system boundary
profile_folder = EnvVars::HOME.join('.config', 'browser', 'Profile 1')
if File.directory?(profile_folder)  # File methods accept Pathname
  du_out, = Open3.capture3('du', '-sk', profile_folder.to_s)  # .to_s at boundary
end

# BAD -- premature .to_s
profile_folder = EnvVars::HOME.join('.config', 'browser', 'Profile 1').to_s
if File.directory?(profile_folder)
  du_out, = Open3.capture3('du', '-sk', profile_folder)
end
```

### String Interpolation Auto-Converts

Ruby's string interpolation automatically calls `.to_s` on Pathname objects:

```ruby
# Both are equivalent -- interpolation calls .to_s automatically
puts "Processing #{EnvVars::HOME}"
puts "Processing #{EnvVars::HOME.to_s}"

# Color methods require explicit .to_s (they're defined on String, not Pathname)
info "Processing '#{EnvVars::HOME.join('dotfiles').to_s.cyan}'"
```

### Function Parameters -- Accept Pathname

When writing functions that operate on paths, accept Pathname parameters and
return Pathname when building new paths:

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

### When to Use .to_s

Only convert to String in these situations:

1. **System commands**: `system()`, `Open3.capture3()`, backticks
2. **String-only APIs**: rare APIs that explicitly document String-only parameters
3. **String manipulation**: when you need String methods like `.gsub`, `.split`

```ruby
# 1. System commands
system('git', '-C', repo_path.to_s, 'status')

# 2. String manipulation (need .gsub)
display_path = folder.to_s.gsub(EnvVars::HOME.to_s, '~')

# 3. String concatenation (but prefer Pathname.join instead)
# BAD
path = EnvVars::HOME.to_s + '/' + 'file.txt'
# Good
path = EnvVars::HOME.join('file.txt')
```

### PathUtils::ROOT for Filesystem Root

When building paths from the filesystem root `/`, use `PathUtils::ROOT`:

```ruby
require 'path_utils'

# Good -- cross-platform filesystem root
system_path = PathUtils::ROOT.join('etc', 'hosts')

# BAD -- hardcoded Unix root
system_path = Pathname.new('/etc/hosts')
```

`PathUtils::ROOT` uses `File::SEPARATOR` internally and works on Windows (`C:\`).

### Never Hardcode Derived Paths

Never hardcode paths that derive from HOME or other env vars. Always use the
EnvVars constant:

```ruby
# BAD -- hardcoded
config_dir = Pathname.new(ENV['HOME']).join('.config')
dotfiles = Pathname.new("#{ENV['HOME']}/.config/dotfiles")

# Good -- use EnvVars
config_dir = EnvVars::HOME.join('.config')
dotfiles = EnvVars::DOTFILES_DIR  # already includes .config/dotfiles
```

## Conditionals -- Trailing Style for Single Statements

Use trailing `if`/`unless` style when the conditional body is a single statement.
Use block style (`if...end`) when the body has multiple statements or when the
condition is complex.

```ruby
# Good -- single statement, use trailing style
return if nil_or_empty?(value)
exit 1 unless success
info "Skipping '#{path}'" if File.exist?(path)
system('git', '-C', folder, 'config', 'user.name', user_name) unless nil_or_empty?(user_name)

# BAD -- single statement in block form (verbose)
if nil_or_empty?(value)
  return
end
unless success
  exit 1
end

# Good -- multiple statements or complex logic, use block style
if condition
  statement1
  statement2
end

unless File.exist?(path) && valid_path?(path)
  error "Invalid path"
  return 1
end

# Good -- if/else always uses block style (can't be trailing)
if dry_run
  info 'Would run command'
else
  system('command')
end
```

**Exception:** Do NOT use trailing style when it makes the line too long (>120
characters) or when it reduces readability. Readability always takes precedence.

**Performance consideration:** Trailing style evaluates all method arguments
**before** checking the condition. For expensive operations (complex string
interpolation, method calls), use block style to avoid unnecessary work:

```ruby
# BAD -- string interpolation happens even when status.success? is true
_report_git_failure("Failed in '#{folder.cyan}': #{compute_details}", status, stderr) unless status.success?

# Good -- string only built when needed
unless status.success?
  _report_git_failure("Failed in '#{folder.cyan}': #{compute_details}", status, stderr)
end

# Trailing style is fine for simple/cheap arguments
return unless items.any?
exit 1 unless success
File.delete(path) if obsolete
```

## Idiomatic Patterns

```ruby
# Collections
items.map { |x| ... }       # not .collect
items.select { |x| ... }    # not .filter
items.any? { |x| ... }
items.all? { |x| ... }
items.reduce({}) { |acc, x| ... }  # not .inject

# Nil safety for arrays
Array(value).each { ... }   # guards against nil

# Custom nil guard -- NEVER replace with .empty?
return if nil_or_empty?(value)

# Cross-platform path separator
File::SEPARATOR             # not hardcoded "/"

# Hash class extensions (from hash_ext.rb)
hash.deep_sort              # recursive sort by keys

# String color extensions -- see ## String Colors for the full convention table
'text'.blue
'path/to/file'.cyan         # HOME->tilde substitution happens inside color methods
```

## Shell Command Execution -- `system()` and Escaping

Ruby's `system()` and `Open3.capture3()` have two execution modes:

### 1. Direct execution (safe, no escaping needed)

Pass command and arguments as separate parameters. Ruby executes the command
directly without invoking a shell. NO shell interpretation happens, so NO
escaping is needed:

```ruby
# Good -- safe, no shell, no escaping needed
system('git', '-C', folder, 'status')
system({ 'VAR' => 'value' }, 'git', '-C', folder, 'command')
Open3.capture3('git', '-C', folder, 'log', '--oneline')
```

Even if `folder` contains spaces or special characters, they are passed as-is
to the command -- no shell interprets them.

### 2. Shell execution (requires escaping)

Pass a single string. Ruby invokes `/bin/sh -c "string"`, which means the shell
interprets the string. Variable interpolation MUST use `shellescape`:

```ruby
# BAD -- unsafe if folder contains spaces or shell metacharacters
system("git -C #{folder} status")

# Good -- shellescape protects against shell interpretation
require 'shellwords'
system("git -C #{folder.shellescape} status")

# Good -- explicit shell invocation (needed for shell functions, pipes, etc.)
Open3.capture3('/bin/zsh', '-lc', "clone_repo_into #{url.shellescape} #{folder.shellescape}")
```

### When to use each form

| Use Case | Form |
|----------|------|
| Simple command with arguments | Direct execution (separate args) |
| Command with env vars | Direct execution with env hash |
| Shell function (e.g., from `.shellrc`) | Shell execution with `shellescape` |
| Pipeline or redirection | Shell execution with `shellescape` |
| User-authored command string from config | Shell execution (no escaping -- user controls the command) |

### Exception: User-controlled command strings

When executing commands from user-authored config files (YAML `post_clone`
commands, etc.), pass the string as-is WITHOUT escaping. The user intends for
their command to be executed exactly as written, including any shell syntax:

```ruby
# User-authored command from YAML config -- execute as-is
command_str = repo['post_clone']  # e.g., "npm install && npm run build"
Open3.capture3(command_str)       # Shell interprets the string as the user intended
```

## String Colors

Color methods are defined on `String` in `utilities/string.rb`. They:
- Wrap the string in ANSI escape codes (no-op when stdout is not a TTY)
- Automatically substitute `$HOME` with `~` in any path passed to them

**Never** call `replace_home_path_with_tilde` before passing a path to a color
method -- the substitution happens inside. Only call it explicitly for bare
`puts`/`print` call sites that display paths without any color method.

**IMPORTANT**: Color methods are defined on `String`, not `Pathname`. Always
call `.to_s` on Pathname objects before applying color methods:

```ruby
# BAD -- color methods don't exist on Pathname
profile_folder = EnvVars::HOME.join('.config')
info "Processing '#{profile_folder.cyan}'"  # NoMethodError: undefined method `cyan' for #<Pathname>

# Good -- convert to String first
info "Processing '#{profile_folder.to_s.cyan}'"

# Also good -- assign to a variable after converting
folder_path = profile_folder.to_s.cyan
info "Processing '#{folder_path}'"
```

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

## Unified Color Standard (Ruby + Shell)

All logging messages across Ruby scripts and shell scripts follow this unified
color classification for consistency.

### Color Classification Rules

1. **Paths/Files/Folders**: `.cyan` + single quotes
   - File paths, directory paths, full app paths like `/Applications/App.app`
   - Example: `info "Processing '#{folder.cyan}'"`

2. **Action verbs** (in headers/labels): `.yellow`
   - "Installing", "Updating", "Finding", "Processing"
   - Section header action verbs
   - Example: `section_header "#{'Installing'.yellow} dotfiles"`

3. **Labels/Keys in key-value pairs**: `.yellow` + colon
   - "Branch:", "Folder:", "Dry run:", env var names as subjects
   - Example: `info "#{'Branch:'.yellow} '#{branch.cyan}'"`

4. **Component/tool/app names** (non-paths): `.yellow`
   - "homebrew", "antidote plugins", "KeyClu" (app name without path)
   - Example: `section_header "#{'Updating'.yellow} #{'homebrew'.yellow}"`

5. **Commands/executable strings**: `.cyan` + single quotes
   - Actual command strings like `'git status'`
   - Example: `info "Running '#{cmd_parts.join(' ').cyan}'"`

6. **Domain/preference identifiers**: `.light_cyan`
   - `com.apple.Finder`, `com.google.Chrome`
   - Example: `debug "Processing domain: #{app_pref.light_cyan}"`

7. **Numeric values**:
   - Success counts (in summaries): `.green`
   - Error counts (in summaries): `.red`
   - Neutral/informational counts: `.purple`
   - Example: `puts "  Created: #{STATS.created.to_s.green}"`
   - Example: `puts "  Processed: #{STATS.processed.to_s.purple}"`
   - Example: `puts "  Errors: #{STATS.errors.to_s.red}"`

8. **Boolean values**: `.orange`
   - Example: `info "#{'Dry run:'.yellow} #{dry_run.to_s.orange}"`

9. **Error messages/failed items**: `.red`
   - Entire error messages can be red
   - Failed items in lists: `  - '#{item.red}'`
   - Example: `record_error("Failed to process '#{file.cyan}'".red)`

### Application Guidelines

- **Regular text**: No color decoration (white/default terminal color)
- **Consistency across languages**: Apply same rules in Ruby and Shell scripts
- **Single quotes for paths/commands**: Always single-quote paths and commands when coloring
- **No mixing**: Don't apply multiple colors to the same text element
- **Context matters**: Neutral counts get purple; success/error counts get green/red
- **Yellow-context rule**: When the main message text is already yellow (labels, action verbs), use purple for quoted special content (env vars, component names, script names) to create visual distinction

## Module / Class Structure

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

## Private Methods in Scripts

All top-level helper methods in scripts that are not part of the main execution
flow must be marked `private` and prefixed with `_`:

```ruby
# BAD -- helper not marked private, no _ prefix
def read_pattern_file(file)
  # ...
end

def process_item(item)
  # ...
end

# main execution
items.each { |item| process_item(item) }

# Good -- helpers marked private with _ prefix
def _read_pattern_file(file)
  # ...
end

def _process_item(item)
  # ...
end

private :_read_pattern_file, :_process_item

# main execution
items.each { |item| _process_item(item) }
```

Rules:
- **All** helper methods that are not the main entry point must be prefixed with `_`
- **All** methods prefixed with `_` must be explicitly marked `private`
- Place the `private` declaration immediately after the last helper method definition
- List all private methods on one or more lines (comma-separated)
- Main execution code (option parsing, main logic) comes after the `private` declaration

Exception: Very short scripts (< 50 lines) with a single helper may omit the
`private` declaration if the `_` prefix makes the intent clear, but prefer
being explicit.

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
- Shell functions delegate to Ruby utilities via `ruby -e` (e.g., `suspend_cron` → `Cron.suspend_cron`)
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

## CLI Scripts Structure

Two variants depending on where the script lives:

**`$PERSONAL_BIN_DIR` scripts** -- `RUBYLIB` is always set (interactive shell):

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logging'
require 'cli_parser'

include Logging

# ---------------------------------------------------------------------------
# Constants

# ---------------------------------------------------------------------------
# Main

options = {}
parser = CliParser.parse('<folder>') do |opts|
  opts.separator 'One-line description of what this script does.'
  opts.separator ''
  opts.separator 'Arguments:'.purple
  opts.separator "  #{'<folder>'.yellow}  Target folder"
  opts.separator ''
  opts.separator 'Options:'.purple
  opts.on('-f', '--flag', 'Enable flag') { options[:flag] = true }
  opts.separator ''
  opts.separator "  eg: #{File.basename(__FILE__).cyan} /path/to/folder"
end

folder = ARGV.first
if nil_or_empty?(folder)
  parser.abort_with_usage('Missing required argument: <folder>')
end

Logging.section_header('Script Name')
# increment_script_depth increments _DOTFILES_SCRIPT_DEPTH and registers an
# at_exit hook to decrement it on exit (clean or error). Mirrors the shell
# export + trap pattern. Must be called before print_script_start.
Logging.increment_script_depth
# print_script_start returns the Unix epoch of the logged timestamp so both the
# displayed time and the in-memory start time are identical -- no two-call pattern.
# This deviates from the shell version, which cannot return a value.
script_start_time = Logging.print_script_start

# ... main logic ...

# Passing start_time to print_script_summary causes it to call print_script_duration
# internally -- no separate call needed. This deviates from the shell version where
# print_script_summary cannot access the start time (shell functions cannot return
# values to be threaded through). Omit the argument only on early-exit paths inside
# methods that cannot access the top-level start-time local.
Logging.print_script_summary(script_start_time)
```

**`$DOTFILES_DIR/scripts/` scripts** -- must prepend utilities path because
`RUBYLIB` is not set during `FIRST_INSTALL` (vanilla OS):

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

# Ensure utilities/ is on the load path so 'require' works regardless of whether
# RUBYLIB is set (e.g. during FIRST_INSTALL before .shellrc has been sourced).
$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'logging'
require 'cli_parser'

# ... rest follows the same structure as above ...
```

## Exit Points -- Single Exit at End of Script

**All Ruby scripts must have a single exit point at the end of the script.**

This rule applies primarily to scripts that **process multiple items** (repos, files, etc.). Never call `exit()` in the middle of a processing loop. Instead:
1. Use flags or variables to track failure state
2. Let the script run to completion
3. Call `exit(code)` once at the very end based on accumulated state

```ruby
# BAD -- exits in middle of processing loop
process_items.each do |item|
  if item.invalid?
    warn "Invalid: #{item}"
    exit(1)  # BAD -- prevents processing remaining items
  end
end

# Good -- single exit at end, all items processed
@has_failures = false

process_items.each do |item|
  if item.invalid?
    warn "Invalid: #{item}"
    @has_failures = true
  end
end

# Single exit point at end of script
exit(1) if @has_failures
```

**Why this matters:**
- **Nested script safety**: When called from another script (e.g., in a loop), premature `exit()` terminates the entire subprocess, making exit code checking work correctly
- **Process all items**: Users expect all items to be processed, not just up to the first failure
- **Complete summaries**: Allows printing a full summary of all successes and failures at the end
- **Predictable cleanup**: `at_exit` hooks and ensure blocks run reliably
- **Better debugging**: Single exit point makes control flow explicit

**Exceptions:**

1. **Help/usage output**: Scripts that print help and exit (e.g., `ARGV.first == '-h'` or `ARGV.empty?`) may call `exit(0)` directly -- these are not processing failures, just usage information requests:

```ruby
# Allowed -- help flag exits immediately
if ARGV.empty? || ARGV.first == '-h' || ARGV.first == '--help'
  puts "Usage: #{File.basename(__FILE__)} <command...>"
  exit 0  # OK -- just printing usage
end
```

2. **Precondition validation**: `error()` (which raises) or `parser.abort_with_usage` are allowed for argument validation and precondition checks at the top of the script -- these are immediate user errors that should abort before any work begins:

```ruby
# Allowed -- precondition checks before processing
unless GitHelpers.git_repo?(folder)
  error "'#{folder}' is not a git repo. Aborting."
end

folder = ARGV.first
if nil_or_empty?(folder)
  parser.abort_with_usage('Missing required argument: <folder>')
end

# ... rest of script processes normally ...
# Single exit at end
exit(1) if @has_failures
```

2. **Fatal mid-operation errors**: Single-item scripts (not processing loops) may use `error()` for truly unrecoverable failures where continuing would cause data corruption. But prefer tracking state and exiting cleanly when possible.

**Summary:** The rule targets scripts that process multiple items. For those, never exit in the middle of the loop. For help/usage, validation, and single-item operations, early exit is acceptable.

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

The log levels mirror the shell functions in `.shellrc`. Use the same
classification rules across both shell and Ruby:

| Level | When to use |
|---|---|
| `debug` | Expected-absent tools or optional steps silently skipped (e.g. "binary not found -- skipping"). Hidden by default. |
| `info` | Normal progress and idempotency guards ("already configured -- skipping"). |
| `success` | An operation completed successfully. |
| `warn` | Argument-parsing failures followed by `abort`; non-fatal operation failures where execution continues (e.g. rescue blocks that log and move on). |
| `error` | Unexpected operation failures. Raises `RuntimeError` -- callers must `rescue` if processing should continue for remaining items. |
| `user_action` | Manual steps the user must perform after the script (restart an app, run a command, open a URL). |

### Deferred error/warning collection

`record_warning` and `record_error` mirror `_record_warning` / `_record_error`
from `.shellrc`. Each entry is prefixed with `[script_name][current_section]`
for traceability. Pass `start_time` to `print_script_summary` at the end of the
script -- it prints collected issues and calls `print_script_duration` internally.
Set `Logging.current_section = 'name'` to track which logical step is executing
-- mirrors `_current_section` in shell scripts.

Call `Logging.increment_script_depth` once before `print_script_start`. It
increments `ENV['_DOTFILES_SCRIPT_DEPTH']` and registers an `at_exit` hook that
decrements it on both clean and error exits -- the exact mirror of the shell
increment + EXIT trap pair. `print_script_start` and `print_script_summary` gate
their output on `outermost_script?` (`depth <= 1`), so nested subprocess scripts
stay silent and only the outermost script prints its banners and summary.

```ruby
Logging.increment_script_depth
script_start_time = Logging.print_script_start

Logging.current_section = 'Checking dependencies'
Logging.record_warning "optional tool missing -- some features disabled"
Logging.record_error   "required env var FOO is not set"

# At end of script -- duration is printed internally; no separate call needed:
Logging.print_script_summary(script_start_time)
```

No macOS notification is sent from Ruby -- `osascript` is not appropriate for
library code. Scripts that need a notification must handle it themselves.

#### Dual Purpose: Nesting Suppression AND Auto-Indentation

`_DOTFILES_SCRIPT_DEPTH` serves two purposes:

1. **Suppression**: Only outermost scripts (depth ≤ 1) print start/summary banners
2. **Auto-indentation**: ALL logging methods automatically indent based on depth

All logging methods (`info`, `warn`, `success`, `error`, `debug`, `user_action`)
and section headers call `log_indent` internally, which returns `'  ' * depth`.
This creates visual hierarchy that matches the call stack:

```ruby
# Standalone script (depth 0 → 1)
Logging.increment_script_depth  # depth now 1
info "Processing items..."      # 2-space indent (depth 1)

# Nested subprocess (depth 1 → 2)
info "Parent message"                 # 2-space indent
system('child-script.rb')             # Child logs at 4-space indent (depth 2)
info "Back to parent"                 # 2-space indent
```

**NEVER manually prepend spaces to log messages.** The depth counter handles all
indentation automatically:

```ruby
# BAD -- manual indent (old pattern, removed during refactoring)
info "  -> Processed #{count} items"

# Good -- auto-indent (current pattern)
info "-> Processed #{count} items"
```

The `log_indent` helper is defined in `logging.rb` and should not be called
directly from scripts -- it is an internal utility for logging methods.

### External Tool Output -- Intentionally Unindented

External tools (`git`, `mise`, `sqlite3`, `keybase`, etc.) invoked via `system()`
or `Open3.capture3()` print at column 0. This is intentional -- wrapping their
output would add complexity for minimal UX benefit. Tool output remains visually
distinct from our structured logging.

**Examples of system calls that produce unindented tool output**:
- `run-all.rb`: `system(shell, '-c', cmd_string)` -- user commands
- `git_workspace.rb`: `system('mise', ...)`, `system('direnv', ...)`
- `keybase.rb`: `system('keybase', 'login')`
- `recreate-repo.rb`: `system('git', '-C', folder, 'init', ...)`


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
Logging.user_action "Run 'bupc' to update Homebrew packages."
```

## Script Output Format

Each Ruby script must print:
1. A `section_header` with the script name.
2. Start time (`info "Starting..."`)
3. Main logic with appropriate `info`/`success`/`warn` per operation.
4. A summary before exit (counts of success/failure/skipped).
5. End time and duration.

## `nil_or_empty?` Helper

Always use `nil_or_empty?` to check for nil-or-empty conditions. It is defined
in `logging.rb` (or injected globally). Never call `.empty?` directly on a
value that might be `nil`.

```ruby
nil_or_empty?(value)          # Good
value.nil? || value.empty?    # Acceptable but verbose
value.empty?                  # BAD if value could be nil
```

## Formatting After Every Edit

After every edit to a Ruby script, reformat with `rufo`. Always run it from
`$HOME` -- NOT from `$DOTFILES_DIR` which is pinned to system Ruby 2.6 and
cannot run rufo:

```zsh
cd "${HOME}" && rufo <path/to/file.rb>
```

After formatting, the file **MUST pass all three whitespace checks**. This applies
to all text files **except Markdown files** (`.md`), which are exempt from Check 2
only (trailing blank lines).

### Check 1: File Ends with Newline
```zsh
# Verify file ends with exactly one newline
tail -c 1 <file> | od -An -tx1 | grep -q '0a' || echo "FAIL: Missing final newline"
```

### Check 2: No Trailing Blank Lines
```zsh
# Verify no blank lines at end of file
tail -n 1 <file> | grep -q '^$' && echo "FAIL: Has trailing blank lines"
```

**Fix:**
```zsh
# Remove trailing blank lines while preserving final newline
sed -i '' -e :a -e '/^\s*$/d;N;ba' <file>
```

### Check 3: No Trailing Whitespace on Any Line
```zsh
# Verify no lines end with spaces or tabs
grep -n '[[:space:]]$' <file> && echo "FAIL: Lines above have trailing whitespace"
```

**Fix:**
```zsh
# Remove trailing whitespace from all lines
sed -i '' 's/[[:space:]]*$//' <file>
```

### All-in-One Verification
```zsh
if tail -c 1 <file> | od -An -tx1 | grep -q '0a' && \
   ! tail -n 1 <file> | grep -q '^$' && \
   ! grep -q '[[:space:]]$' <file>; then
  echo "✅ All whitespace checks pass"
else
  echo "❌ Whitespace violations found"
fi
```

**When using the Edit tool:**
- Ensure `newString` ends with exactly one newline
- No blank lines after the last content line
- No trailing spaces/tabs on any line

**Why this matters:**
- Consistent file endings across the repository
- Cleaner diffs (no spurious blank line changes)
- Matches the output of most formatters and linters
- Reduces visual noise in version control

**Exceptions:**
- **Markdown files (`.md`)** are exempt from Check 2 only (trailing blank lines may be intentional for formatting). Checks 1 and 3 still apply.
- **Cryptographic files (`.key`, `.pem`)** must not be modified -- they are generated by external tooling and any modification breaks their integrity.

## Character Encoding and Punctuation

All Ruby scripts and comments must use **ASCII-only characters**. Never use
Unicode punctuation characters such as em dashes, en dashes, curly quotes, or
other typographic symbols.

### Rule: Use ASCII dashes only

```ruby
# Good -- ASCII double dash for parenthetical comments
# This function caches the result -- no subprocess fork needed.

# Good -- ASCII single dash for hyphenated terms
# The cache-invalidation pattern uses mtime comparison.

# BAD -- em dash (Unicode U+2014) breaks some syntax highlighters
# This function caches the result — no subprocess fork needed.

# BAD -- en dash (Unicode U+2013)
# The cache–invalidation pattern uses mtime comparison.
```

### Rule: Use ASCII quotes only

```ruby
# Good -- ASCII straight quotes
puts "Processing 'file.txt'"

# BAD -- curly quotes (Unicode)
puts "Processing 'file.txt'"
```

### Why ASCII-only?

1. **Syntax highlighters**: Many editors and syntax highlighters break or
   display incorrectly when encountering Unicode punctuation in code/comments
2. **Terminal compatibility**: Not all terminals render Unicode punctuation
   correctly, especially in SSH sessions or minimal environments
3. **Copy-paste safety**: Unicode characters can be accidentally converted or
   corrupted when copying code between systems
4. **Searchability**: ASCII dashes can be searched with simple regex patterns;
   Unicode variants require special handling
5. **Git diffs**: Unicode characters can display as escape sequences in some
   git diff viewers, making code review harder

### Allowed Unicode

The only Unicode allowed in Ruby scripts:
- **Color codes** in ANSI escape sequences (e.g., `\e[31m`)
- **User-facing output** from logging functions where typographic quality matters
  (e.g., `Logging.info "Processing — 50% complete"` is acceptable in logged
  output, but not in comments or code)

When in doubt, use ASCII.

## Executable Permission

After editing Ruby scripts intended to be executed directly, ensure they have executable permission:

```zsh
chmod +x path/to/script.rb
```

**Check if executable:**
```zsh
[[ -x path/to/script.rb ]] && echo "✅ Executable" || echo "❌ Not executable"
```

**Applies to:**
- All Ruby scripts in `$DOTFILES_DIR/scripts/` (`.rb`)
- All Ruby scripts in `$PERSONAL_BIN_DIR/` (`.rb`)

**Why:** Ruby scripts in bin directories are invoked directly and must be executable. Library files in `utilities/` don't strictly need it but it doesn't hurt.
