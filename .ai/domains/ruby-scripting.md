---
applyTo: "**/*.rb"
---

# Ruby Script Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules when writing or editing any Ruby script in this repository.

## Scope

**This file applies to**: All Ruby code in the repository, including:
- Executable scripts in `${DOTFILES_DIR}/scripts/*.rb` (e.g., `install-dotfiles.rb`, `capture-prefs.rb`)
- Executable scripts in `${PERSONAL_BIN_DIR}/*.rb` (personal automation scripts)
- Utility modules in `${DOTFILES_DIR}/scripts/utilities/*.rb` (e.g., `logging.rb`, `git_processor.rb`, `env_vars.rb`)
- Dual-mode scripts (module + standalone CLI)
- Any Ruby code that uses the logging infrastructure, EnvVars module, or GitProcessor

**Related files**:
- [`logging-conventions.md`](./logging-conventions.md) - Cross-language color standards and logging patterns
- [`script-depth-tracking.md`](./script-depth-tracking.md) - Nesting depth and auto-indentation
- [`path-constants.md`](./path-constants.md) - EnvVars module usage and Pathname patterns
- [`edit-checklist.md`](./edit-checklist.md) - Post-edit verification workflow

**Does NOT apply to**: Vendored Ruby gems, external Ruby libraries, or Ruby code in other repositories not using this dotfiles infrastructure.

## Quick Reference

| Task | Pattern | Section Link |
|------|---------|--------------|
| Script template | Module + CLI wrapper | [§ Dual-Mode Ruby Scripts](#dual-mode-ruby-scripts-module--standalone----mandatory) |
| Method parameters | Named for 2+ params | [§ Method Parameters](#method-parameters----named-vs-positional) |
| Logging | `Logging.info`, `Logging.success`, `Logging.warn` | [§ Logging](#logging) |
| Path constants | `EnvVars::DOTFILES_DIR` | [§ Path Constants](#path-constants) |
| Option parsing | `CliParser.parse` | [§ Option Parsing](#option-parsing----use-cliparser) |
| Git operations | `GitProcessor.new(dir:)` | [§ GitProcessor Usage](#gitprocessor-usage-patterns) |
| Nil check | `nil_or_empty?(value)` | [§ `nil_or_empty?` Helper](#nil_or_empty-helper) |
| File reading (UTF-8) | `Core.read_lines_utf8(file)` | [§ UTF-8 File Reading](#utf-8-file-reading) |
| Color methods | `string.to_s.cyan` (NOT on Pathname) | [§ String Colors](#string-colors) |
| Script depth | `Logging.increment_script_depth` | [§ Script Depth Tracking](./script-depth-tracking.md) |
| Memoization | `@_var ||= expensive_operation` | [§ Memoization](#memoization) |

## File Naming Convention

**Executable scripts use kebab-case (hyphens), utility modules use snake_case (underscores).**

This follows standard Ruby community conventions:

| Type | Pattern | Examples | Rationale |
|------|---------|----------|-----------|
| **Executable scripts** | kebab-case | `install-dotfiles.rb`, `recreate-repo.rb`, `capture-prefs.rb` | Matches Unix CLI tool convention; easier to type on command line |
| **Utility modules** | snake_case | `git_processor.rb`, `cli_parser.rb`, `env_vars.rb` | Matches Ruby `require_relative` convention (`require 'git_processor'` → `git_processor.rb`) |
| **Single-word modules** | no separator | `logging.rb`, `cron.rb`, `keybase.rb` | No separator needed for single words |

**Why this convention:**
- `require_relative 'git_processor'` naturally maps to `git_processor.rb`
- CLI tools use hyphens (standard across Unix ecosystem: `git-log`, `npm-install`, etc.)
- Reduces cognitive load - file extension reveals intended usage

**Applies to:**
- `${DOTFILES_DIR}/scripts/*.rb` - All executable scripts use kebab-case
- `${DOTFILES_DIR}/scripts/utilities/*.rb` - All modules use snake_case
- `${PERSONAL_BIN_DIR}/*.rb` - All executable scripts use kebab-case
- Shell scripts follow same pattern: `fresh-install-of-osx.sh`, `osx-defaults.sh`

**Autoload function naming**: Zsh autoload functions in `${XDG_CONFIG_HOME}/zsh/` use single-word names by design (e.g., `upreb`, `status`, `push`). This is not a "no separator needed" exception—it's a deliberate convention for autoloaded commands that matches shell built-in naming patterns.

**Scan rule:** When creating or renaming Ruby files:
1. Is it an executable entry point (has `if __FILE__ == $PROGRAM_NAME`)? → Use kebab-case
2. Is it a utility module (no CLI mode, only `module` definitions)? → Use snake_case
3. Single word? → No separator needed

## Dual-Mode Ruby Scripts (Module + Standalone) -- MANDATORY

**ALL standalone Ruby scripts MUST follow this pattern** to enable both CLI usage and direct module calls from other Ruby scripts.

**CRITICAL RULE: When one Ruby script calls another Ruby script, use the module directly instead of forking a subprocess.**

```ruby
# BAD -- subprocess overhead, complex error handling, no shared context
system(RbConfig.ruby, 'scripts/install-dotfiles.rb')

# Good -- direct module call, returns boolean, shared logging context
require_relative 'install-dotfiles'
InstallDotfiles.run
```

This rule applies to ALL Ruby-to-Ruby calls unless the callee has conflicting `at_exit` hooks (see "When NOT to Use This Pattern" below).

### Why This Pattern is Required

**Problem with traditional scripts:**
- Call `exit()` for control flow → kills parent process if called directly
- Requires subprocess invocation (`system(RUBY_BIN, script, args...)`) → slow, complex error handling
- Can't share script depth tracking or logging context
- Harder to test and debug

**Benefits of dual-mode:**
- **Performance**: No fork/exec overhead when calling from Ruby
- **Error handling**: Returns bool, exceptions propagate naturally
- **Log indentation**: Shared script depth tracking works correctly
- **Debugging**: Single stack trace across all code
- **Reusability**: Same code works as CLI tool and library

### Template

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8

# file location: ${DOTFILES_DIR}/scripts/my-script.rb
#
# One-line description of what this script does.
#
# Usage:
#   Standalone: my-script.rb [options]
#   Module:     MyScript.run(param: value)

require_relative 'utilities/logging'
require_relative 'utilities/env_vars'

# Module contains the business logic.
# Returns true/false instead of calling exit().
module MyScript
  extend self

  # Public API method.
  #
  # @param param [String] Description of parameter
  # @return [Boolean] true on success, false on error
  def run(param:)
    Logging.info "Processing '#{param.cyan}'"

    unless valid_input?(param)
      Logging.record_error "Invalid parameter: #{param}"
      return false
    end

    # ... main logic ...

    Logging.success "Completed successfully"
    true
  end

  # Private helper methods.
  def _helper_method(arg)
    # ...
  end
  private_class_method :_helper_method
end

# ---------------------------------------------------------------------------
# Standalone CLI mode
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  require_relative 'utilities/cli_parser'

  include Logging

  options = {}
  parser = CliParser.parse('<options>') do |opts|
    opts.separator 'Description of what this script does.'
    opts.separator ''
    opts.separator 'Options:'.purple
    opts.on('-p', '--param VALUE', 'Parameter description') { |v| options[:param] = v }
    opts.separator ''
    opts.separator "  eg: #{File.basename(__FILE__).cyan} --param value"
  end

  parser.abort_with_usage('Missing required option: --param') if nil_or_empty?(options[:param])

  increment_script_depth
  start_time = print_script_start

  success = MyScript.run(param: options[:param])

  print_script_summary(start_time)
  exit(success ? 0 : 1)
end
```

### Key Rules

1. **Module contains all business logic**
   - Use `extend self` to make methods callable as module methods
   - Return `true`/`false`, **never call `exit()` or `abort()`**
   - Use `Logging.method_name` (qualified calls, not `include Logging`)
   - Extract helpers as private class methods

2. **Standalone block is CLI wrapper only**
   - Wrapped in `if __FILE__ == $PROGRAM_NAME`
   - Handles argument parsing with `CliParser`
   - Calls `increment_script_depth` / `print_script_start` / `print_script_summary`
   - Converts module's boolean return to exit code: `exit(success ? 0 : 1)`
   - Only place `include Logging` is used (for CLI convenience)

3. **Calling from other Ruby scripts**
   - Add `require_relative 'script-name'`
   - Call directly: `success = MyScript.run(param: value)`
   - Handle boolean return value
   - No subprocess needed

4. **Error handling**
   - Use `Logging.record_error` for non-fatal errors (return false, keep processing)
   - Use `Logging.error` (raises RuntimeError) only for fatal errors that should abort
   - Caller can `rescue` if needed

### Examples

#### Simple Script (add-upstream-git-config.rb)

```ruby
module AddUpstreamGitConfig
  extend self

  def run(dir:, upstream_owner:)
    target_dir = dir.to_s

    unless GitProcessor.repo?(target_dir)
      Logging.info "'#{target_dir.cyan}' is not a git repo -- skipping."
      return true  # Not an error, just nothing to do
    end

    # ... main logic ...

    unless status.success?
      Logging.record_error("Failed to add upstream remote")
      return false
    end

    Logging.success "Successfully added upstream remote"
    true
  end
end

if __FILE__ == $PROGRAM_NAME
  # ... CLI wrapper ...
  success = AddUpstreamGitConfig.run(dir: options[:dir], upstream_owner: options[:upstream_owner])
  exit(success ? 0 : 1)
end
```

#### Script with Statistics (install-dotfiles.rb)

```ruby
module InstallDotfiles
  extend self

  Stats = Struct.new(:processed, :created, :updated, :skipped, :errors, keyword_init: true)

  def run(dry_run: false, verbose: false, force: false)
    stats = Stats.new(processed: 0, created: 0, updated: 0, skipped: 0, errors: 0)

    # ... process files, update stats ...

    # Print summary
    puts ''
    Logging.success('Summary:')
    puts "  Processed: #{stats.processed.to_s.purple}"
    puts "  Errors:    #{stats.errors.positive? ? stats.errors.to_s.red : stats.errors}"

    stats.errors.zero?  # Return true if no errors
  end
end

if __FILE__ == $PROGRAM_NAME
  # ... CLI wrapper ...
  success = InstallDotfiles.run(**options)
  exit(success ? 0 : 1)
end
```

### Calling Patterns

#### From fresh-install-of-osx.sh (parent script)

```ruby
# Top of file
require_relative 'add-upstream-git-config'
require_relative 'install-dotfiles'

# Inside main()
unless AddUpstreamGitConfig.run(dir: EnvVars::DOTFILES_DIR, upstream_owner: EnvVars::UPSTREAM_GH_USERNAME)
  record_warning 'Failed to add upstream git config'
end

unless InstallDotfiles.run
  record_error 'install-dotfiles encountered errors'
end
```

#### From shell (still works)

```zsh
# Call as standalone CLI tool
ruby scripts/add-upstream-git-config.rb -d ~/repo -u upstream-owner
ruby scripts/install-dotfiles.rb --dry-run
```

### When NOT to Use This Pattern

**Keep as subprocess** when:
- **Script must run in isolation** (incompatible lifecycle)
- **Shell script** (`.sh`) that cannot be ported to Ruby
- **Script uses `at_exit` hooks that conflict with parent's lifecycle**

**Examples:**

**osx-defaults.sh** - Shell script, cannot be ported:
- Complex shell script with macOS `defaults` commands
- Must remain as subprocess
- Cannot be ported to Ruby module

**capture-prefs.rb** - Lifecycle conflicts with parent:
- Has `at_exit` hooks that suspend/resume softwareupdate
- Has `at_exit` hooks that kill/restart login-item apps (on import)
- Multiple invocations (export, then import) need independent cleanup
- If called as module, hooks would register in parent and fire at wrong time
- Subprocess isolation ensures each operation has independent lifecycle

**Key insight**: If a script's `at_exit` hooks need to fire **after each operation** (not at parent script end), keep it as subprocess.

### Refactoring Checklist

When converting an existing script to dual-mode:

1. **Extract module**
   - [ ] Wrap main logic in `module ScriptName; extend self; end`
   - [ ] Rename main logic to `run()` method with named parameters
   - [ ] Change all `exit()` calls to `return true/false`
   - [ ] Change `abort()` calls to `Logging.record_error + return false`
   - [ ] Qualify all Logging calls: `info` → `Logging.info`
   - [ ] Move helpers to private class methods

2. **Create standalone block**
   - [ ] Wrap old main code in `if __FILE__ == $PROGRAM_NAME`
   - [ ] Keep `include Logging` inside this block
   - [ ] Keep `CliParser` require inside this block
   - [ ] Call module's `run()` method
   - [ ] Convert return value to exit code

3. **Update callers**
   - [ ] Add `require_relative` to parent script
   - [ ] Replace `system(RUBY_BIN, script, args...)` with `Module.run(params)`
   - [ ] Handle boolean return value

4. **Test both modes**
   - [ ] Standalone: `ruby script.rb --help`
   - [ ] Standalone: `ruby script.rb [normal args]`
   - [ ] Module: Call from parent script

### Scan Rule

When editing any Ruby script, check:
1. Does it call `exit()` or `abort()` in main logic? → Must be refactored to dual-mode
2. Is it called via `system(RUBY_BIN, ...)` from another Ruby script? → Should be refactored
3. Does it have complex `at_exit` hooks? → May need special handling

**Exception**: Scripts that only ever run standalone (cron scripts, one-off utilities) MAY skip dual-mode, but prefer consistency.

## Method Parameters -- Named vs Positional

**Use named parameters for methods with 2+ parameters OR when parameter meaning is not obvious from name alone.**

### Rules

**1. Single obvious parameter → Positional OK:**
```ruby
# Good -- single parameter, meaning clear from method name
def success(message)
def dir_size_kb(dir)
def file?(path)
```

**2. Two or more parameters → Use named parameters:**
```ruby
# BAD -- positional parameters, unclear order
def export_domain(domain, file)
def strip_excluded_keys(domain, plist_file, excluded_by_domain)

# Good -- named parameters, self-documenting
def export_domain(domain:, file:)
def strip_excluded_keys(domain:, plist_file:, excluded_by_domain:)

# Call sites are explicit
export_domain(domain: 'com.apple.dock', file: export_path)
strip_excluded_keys(domain: domain, plist_file: plist, excluded_by_domain: patterns)
```

**3. Optional parameters → Always named:**
```ruby
# BAD -- optional positional parameter
def create_repo(repo_name, dry_run = false)

# Good -- optional named parameter with default
def create_repo(repo_name:, dry_run: false)
```

**4. Boolean flags → Always named:**
```ruby
# BAD -- boolean meaning unclear at call site
def update_repo(repo_dir, true, false)  # What do these booleans mean?

# Good -- boolean flags named
def update_repo(repo_dir:, force: true, dry_run: false)
```

**5. Mixed positional + named OK when first param is obvious:**
```ruby
# Good -- message obvious, level requires clarification
def emit(message, level:)

# Good -- command obvious, options require names
def run_command(cmd, timeout: 30, env: {})
```

### Why Named Parameters

**Benefits:**
- **Self-documenting**: Call sites show what each argument means
- **Order-independent**: Can pass arguments in any order
- **Refactor-safe**: Adding parameters doesn't break existing calls
- **IDE-friendly**: Auto-completion shows parameter names
- **Reduces errors**: Can't accidentally swap arguments

**Performance:**
- Negligible overhead in Ruby 2.6+ (~0.1% difference)
- Readability gain far outweighs any micro-optimization

### When to Keep Positional

**Keep positional only when:**
- Single parameter with obvious meaning from method name
- Very common utility methods where brevity matters (logging, math operations)
- Ruby stdlib-style APIs where convention is established (Array#map, String#split)

**Examples of acceptable positional:**
```ruby
# Logging methods (single obvious parameter)
def info(message)
def success(message)
def error(message)

# Simple utilities (single parameter, name makes purpose clear)
def duration_since(start_time)
def nil_or_empty?(value)
def file?(path)

# Math/formatting utilities
def format_counter(num, width)  # num and width order is conventional
```

### Migration Strategy

**Existing code with positional parameters:**
- **Don't refactor immediately** unless touching that method for other reasons
- **Do convert** when adding new parameters
- **Do convert** when parameter order is confusing at call sites
- **Prioritize** methods called from multiple places (high impact)

**New code:**
- Start with named parameters for 2+ params from day one
- Review: If call sites look verbose but code isn't confusing, named params are working correctly

### Example Refactoring

**Before:**
```ruby
# Method definition
def strip_excluded_keys(domain, plist_file, excluded_by_domain)
  # ...
end

# Call site (unclear what each argument represents)
strip_excluded_keys(domain, plist, patterns)
```

**After:**
```ruby
# Method definition
def strip_excluded_keys(domain:, plist_file:, excluded_by_domain:)
  # ...
end

# Call site (self-documenting)
strip_excluded_keys(
  domain: domain,
  plist_file: plist,
  excluded_by_domain: patterns
)
```

### Update Call Sites

When converting a method to named parameters, update ALL call sites in the same commit:

```bash
# Find all call sites
grep -rn "method_name(" scripts/ --include="*.rb"

# Update each one to use named parameters
# Before: method_name(arg1, arg2, arg3)
# After:  method_name(param1: arg1, param2: arg2, param3: arg3)
```

**Verification:**
```bash
# Syntax check after conversion
find scripts -name "*.rb" -exec /usr/bin/ruby -c {} \;
```

## Script Template (Legacy Single-Mode)

**Note**: The dual-mode pattern above is now MANDATORY for all scripts. This legacy template is kept for reference only.

**`${PERSONAL_BIN_DIR}` scripts** -- use `require_relative` (idiomatic Ruby):

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8

require 'pathname'                                     # stdlib
require_relative '../../../.config/dotfiles/scripts/utilities/logging'
require_relative '../../../.config/dotfiles/scripts/utilities/cli_parser'

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

**`${DOTFILES_DIR}/scripts/` scripts** -- use `require_relative` (idiomatic Ruby):

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8

require 'pathname'                           # stdlib
require_relative 'utilities/logging'         # internal
require_relative 'utilities/cli_parser'      # internal

include Logging

# ... rest follows the same structure as above ...
```

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
Logging.user_action "Run 'bupc' to update Homebrew packages."
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
- Use `PathUtils::ROOT` for filesystem root

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
unless GitProcessor.repo?(folder)
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

## Internal Helpers -- Private Methods

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

### Scan Rule: Check for Missing Private Declarations

When editing any Ruby script, scan for helper methods that should be private:

1. **Find all method definitions**: `grep -n "^def " <script.rb>`
2. **Identify helpers**: Methods called from main execution but not the entry point
3. **Check each helper**:
   - Does it have `_` prefix? If not, rename it
   - Is it listed in a `private` declaration? If not, add it
4. **Update all call sites** to use the `_` prefixed name
5. **Add/update `private` declaration** immediately after the last helper definition

Common patterns requiring private helpers:
- Methods called from option parsing or main execution block
- Methods called in loops (`each`, `map`, etc.) over collections
- Memoized query methods (`_exporting?`, `_importing?`, `_run_all_available?`)
- File loaders, validators, formatters called by main logic

Example scan:
```bash
# Find public helpers (methods without _ prefix)
grep "^def [^_]" scripts/my-script.rb
# → Should only show the script's entry point (if any)
# → Everything else needs _ prefix + private declaration
```

When you find a helper without `_` prefix or `private` declaration, fix it
immediately before proceeding with other changes.

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

## Comment Philosophy

See [`comment-philosophy.md`](./comment-philosophy.md) for complete rules,
rationale, and examples, including comment format conventions.

## Character Encoding and Punctuation

See [`character-encoding.md`](./character-encoding.md) for complete rules on ASCII-only requirements, Unicode restrictions, and allowed exceptions.

**Ruby-specific rule: Use only ASCII symbols in comments.**

```ruby
# BAD -- Unicode arrow in comment
# All color methods apply HOME → ~ substitution automatically

# Good -- ASCII arrow
# All color methods apply HOME -> ~ substitution automatically

# BAD -- Unicode emoji in comment
# - Level 0 (depth 1): = ⏳ light_blue (top-level sections)

# Good -- ASCII description
# - Level 0 (depth 1): = (hourglass) light_blue (top-level sections)
```

Unicode is allowed ONLY in logged output strings where typography matters (see character-encoding.md § Allowed Unicode). It is NOT allowed in:
- Comments (use ASCII equivalents or descriptions)
- Variable names
- Hash keys (as symbols or strings)
- Any other code elements

## Formatting After Every Edit

After every edit to a Ruby script, follow the complete workflow in [`edit-checklist.md`](./edit-checklist.md).

Quick summary for Ruby scripts:
1. Verify decision-making philosophy
2. Verify Ruby 2.6 compatibility (no endless range, pattern matching, etc.)
3. Syntax check: `/usr/bin/ruby -c <file>`
4. Format: `rufo <file>`
5. Remove consecutive empty lines: `awk 'NF {blank=0; print} !NF {if (!blank) print; blank=1}' <file>`
6. Verify whitespace rules (see [`whitespace-rules.md`](./whitespace-rules.md))
7. Ensure executable permission if in bin directory: `chmod +x <file>`

### Consecutive Empty Lines

**Ruby files must not have consecutive empty lines (2+ blank lines in a row).**

```ruby
# BAD -- two blank lines between methods

def method_one
end

def method_two
end

# Good -- single blank line between methods

def method_one
end

def method_two
end
```

**Remove consecutive empty lines:**
```bash
# Collapse 2+ consecutive blank lines into 1
awk 'NF {blank=0; print} !NF {if (!blank) print; blank=1}' <file> > <file>.tmp && mv <file>.tmp <file>
```

**Verification:**
```bash
# Check for consecutive empty lines (3+ newlines = 2+ blank lines)
grep -Pzo '\n\n\n' <file> && echo "Has consecutive empty lines" || echo "OK"
```

**Exception:** `CHANGELOG.md` may have consecutive empty lines for visual separation between version sections.

This rule applies to all Ruby files and markdown documentation in the repository (except CHANGELOG.md).

## Version Compatibility

All Ruby scripts in `${DOTFILES_DIR}/scripts/` (including `utilities/`) must be
compatible with **Ruby 2.6** (the system Ruby available on a vanilla macOS).
Scripts in `${PERSONAL_BIN_DIR}` may target newer versions but prefer 2.6 compat.

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
  echo "=== $branch ==="
  git grep "method_name" $branch -- '*.rb' '*.sh' || true
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

### Shell integration with `call_ruby_utility`

Shell functions invoke Ruby utilities via the `call_ruby_utility` helper function defined in `.shellrc`. This function automatically sets up `RUBYLIB` and preserves `COLUMNS` for terminal width information:

```zsh
# Shell function in .shellrc or .aliases
my_function() {
  # call_ruby_utility handles RUBYLIB setup automatically
  call_ruby_utility "require 'logging'; Logging.info('message')"
  call_ruby_utility "require 'git_processor'; GitProcessor.some_method(arg: 'value')"
}
```

**Benefits of `call_ruby_utility`:**
- Automatic `RUBYLIB` setup (adds `utilities/` and bin directories)
- Preserves `COLUMNS` env var (needed for terminal width)
- Ruby availability check (graceful no-op if Ruby not installed)
- Consistent pattern across all shell→Ruby calls

**Do NOT use raw `ruby -e` calls directly:**
```zsh
# BAD -- bypasses call_ruby_utility, no RUBYLIB setup
ruby -e "require 'logging'; Logging.info('message')"

# BAD -- manual RUBYLIB setup is redundant
setup_rubylib
COLUMNS="${COLUMNS}" ruby -e "require 'logging'; ..."

# Good -- use call_ruby_utility wrapper
call_ruby_utility "require 'logging'; Logging.info('message')"
```

**Pattern for delegation functions:**
```zsh
# Create a thin wrapper that delegates to Ruby module
my_shell_function() {
  call_ruby_utility "require 'my_module'; MyModule.my_method"
}
```

This works in all contexts (vanilla OS and configured OS) because `.shellrc` is always sourced before any shell functions are called.

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
HOME = Pathname.new(ENV.fetch('HOME', '~')).expand_path.freeze
DOTFILES_DIR = Pathname.new(ENV.fetch('DOTFILES_DIR', HOME.join('.config', 'dotfiles'))).expand_path.freeze

# Good -- Non-Pathname methods (evaluated on each call)
def self.force_color?
  !ENV.fetch('FORCE_COLOR', '').strip.empty?
end

def self.script_depth
  ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i
end

# Good -- Methods can return Pathname when appropriate
def self.cron_backup_file
  Pathname.new(
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
- **Type safety**: EnvVars can provide typed accessors (`.to_i`, `Pathname.new()`, etc.)
- **Documentation**: Comments in EnvVars document what each var is for

**Scan rule**: When adding/editing code, search for `ENV.fetch('` with a string
literal. If it's not in `env_vars.rb`, move it there. Use methods for non-Pathname
values, constants only for Pathname objects.

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

**Performance consideration:** Trailing style evaluates the entire statement
(including the operation itself and all its arguments) **before** checking the
condition. For expensive operations, use block style to avoid unnecessary work:

```ruby
# BAD -- expensive operation runs before condition is checked
compute_checksum(large_file) if needs_validation

# Good -- condition checked first, operation only runs if true
if needs_validation
  compute_checksum(large_file)
end

# BAD -- string interpolation happens even when status.success? is true
_report_git_failure("Failed in '#{folder.cyan}': #{compute_details}", status, stdout, stderr) unless status.success?

# Good -- string only built when needed
unless status.success?
  _report_git_failure("Failed in '#{folder.cyan}': #{compute_details}", status, stdout, stderr)
end

# Trailing style is fine for cheap operations and simple arguments
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

## Mutating Methods -- Avoid `!` Variants

**NEVER use mutating methods (`strip!`, `chomp!`, `gsub!`, `map!`, etc.) in this codebase.**

### The Problem

Mutating methods return `nil` when no modification is needed, which breaks assignments:

```ruby
# BAD -- strip! returns nil if string has no whitespace
ref_format = 'files' if nil_or_empty?(ref_format)  # Assigns literal 'files'
ref_format = ref_format.strip!  # Returns nil (no whitespace to strip)
return true if ref_format == 'reftable'  # BROKEN - comparing nil == 'reftable'

# Good -- strip always returns a string
ref_format = 'files' if nil_or_empty?(ref_format)
ref_format = ref_format.strip  # Always returns a string
return true if ref_format == 'reftable'  # Works correctly
```

### The Rule

**Always use non-mutating methods:**

```ruby
# String methods
str.strip      # not str.strip!
str.chomp      # not str.chomp!
str.gsub(...)  # not str.gsub!(...)
str.upcase     # not str.upcase!

# Array methods
arr.map { }     # not arr.map! { }
arr.select { }  # not arr.select! { }
arr.compact     # not arr.compact!
arr.uniq        # not arr.uniq!
```

### Why This Rule

Ruby's mutating methods (`strip!`, `gsub!`, etc.) return `nil` when no modification occurs as a design feature: it lets you detect whether the operation actually changed anything.

**Design intent**:
```ruby
result = str.strip!
if result.nil?
  puts "Already stripped"
else
  puts "Stripped: #{result}"
end
```

**Problem**: This breaks the common pattern `value = value.strip!` because:
- If whitespace exists: `value` is the modified string (correct)
- If no whitespace: `value` is `nil` (breaks subsequent use)

**Our rule**: In this codebase, we never need to detect "did it change?" for strings/arrays. Always use non-mutating methods for predictability.

1. **Safety**: Non-mutating methods always return a value, never `nil`
2. **Immutability**: Easier to reason about - values don't change unexpectedly
3. **Performance**: String/array allocation is cheap in Ruby for the small data in this codebase
4. **Simplicity**: No need to check if the method will actually modify the object

### When Mutating Would Be Appropriate

Mutating methods are only appropriate when:
- Processing very large datasets where allocation matters (not present in this codebase)
- Using for side effect only (not assigning return value) - rare, use carefully

**This codebase has ZERO usage of mutating methods - keep it that way.**

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

### Silent Execution with `CommandUtils.run_silent`

For commands where output needs to be suppressed or redirected, use `CommandUtils.run_silent`:

```ruby
# BAD -- verbose repetition
system('killall', '-TERM', 'Dropbox', out: File::NULL, err: File::NULL)
system('defaults', 'write', domain, key, value, out: File::NULL, err: File::NULL)
system('brew', 'update', out: File::NULL)
system('crontab', '-l', out: temp_file.path, err: File::NULL)

# Good -- concise utility method
CommandUtils.run_silent('killall', '-TERM', 'Dropbox')
CommandUtils.run_silent('defaults', 'write', domain, key, value)
CommandUtils.run_silent('brew', 'update', err: :err)  # suppress stdout, show stderr
CommandUtils.run_silent('crontab', '-l', out: temp_file.path)  # redirect stdout, suppress stderr
```

**Default behavior** (no parameters):
- Suppresses stdout (`out: File::NULL`)
- Suppresses stderr (`err: File::NULL`)
- Returns boolean (true on success, false on failure)

**Optional parameters:**
- `out: target` - Redirect stdout (String path, IO object, or `:out` to show)
- `err: target` - Redirect stderr (String path, IO object, or `:err` to show)

**When to use:**
- Background process termination (`killall`, `pkill`)
- Silent configuration writes (`defaults write`)
- Progress updates in cron context (`brew update`, `mise upgrade`)
- Capturing command output to file (`crontab -l`)
- Operations where only exit status matters

**When NOT to use:**
- Commands where output is needed for debugging
- Operations where stdout/stderr should be visible to user
- Commands where you need to parse stdout/stderr in Ruby code (use `Open3.capture3` instead)

### Exception: User-controlled command strings

When executing commands from user-authored config files (YAML `post_clone`
commands, etc.), pass the string as-is WITHOUT escaping. The user intends for
their command to be executed exactly as written, including any shell syntax:

```ruby
# User-authored command from YAML config -- execute as-is
command_str = repo['post_clone']  # e.g., "npm install && npm run build"
Open3.capture3(command_str)       # Shell interprets the string as the user intended
```

### Invoking Ruby Scripts from Ruby

**When to use subprocess vs direct module call:**

| Scenario | Approach | Reason |
|----------|----------|--------|
| Utility module (utilities/*.rb) | Direct call: `GitWorkspace.update_all_repos` | Module is designed to be called directly; no subprocess overhead |
| CLI script with own lifecycle | Subprocess: `system(RbConfig.ruby, script_path, '-e')` | Script manages traps, logging init, depth tracking - let it run independently |
| Simple function extraction | Direct call after refactoring into module | Prefer extracting to module over subprocess |

**When calling via subprocess**, use `RbConfig.ruby` instead of hardcoded `'ruby'`:

```ruby
# BAD -- hardcoded 'ruby' may invoke a different Ruby than the parent
system('ruby', script_path, '-e')

# Good -- RbConfig.ruby uses the same interpreter as the parent process
require 'rbconfig'
system(RbConfig.ruby, script_path, '-e')
```

**Why subprocess is appropriate for CLI scripts:**
- Script has its own `at_exit` hooks and EXIT traps
- Script calls `increment_script_depth` / `print_script_start` / `print_script_summary`
- Script has option parsing with CliParser
- Script manages its own error collection (`@step_warnings`, `@step_errors`)

**Example of appropriate subprocess use:**
```ruby
# software-updates-cron.rb calling capture-prefs.rb
# capture-prefs.rb is a complete CLI script with its own lifecycle
capture_prefs_script = Pathname.new(__dir__).join('capture-prefs.rb')
system(RbConfig.ruby, capture_prefs_script.to_s, '-e')
```

**Why `RbConfig.ruby` matters:**
- `/usr/bin/ruby` is system Ruby 2.6 (macOS default)
- Homebrew Ruby (if installed) may be in `$PATH` and used by shebangs
- `RbConfig.ruby` returns the path to the **currently running** interpreter
- Child script uses same version/environment as parent (consistent behavior)

## GitProcessor Usage Patterns

`GitProcessor` (in `utilities/git_processor.rb`) provides a consistent API for
all git operations. It handles dry-run mode, error reporting, and directory
context automatically.

### Block Form vs Instance Form

**Use block form when:**
- Performing multiple consecutive git operations in the same scope
- Operations are localized side effects (add, commit, tag, etc.)
- Don't need return values outside the block

```ruby
# Good -- multiple operations, block form
GitProcessor.new(dir: repo_dir) do |git|
  git.stage_all
  git.smart_commit
  git.push(branch: 'main')
end

# Good -- localized side effect, block form
GitProcessor.new(dir: EnvVars::PERSONAL_PROFILES_DIR) do |git|
  old_backups.each { |f| git.rm_cached(f, quiet: true) }
end

# Good -- multiple operations including relative_path (rescue outside block)
GitProcessor.new(dir: repo_dir) do |git|
  rel_path = relative_path ? git.relative_path(relative_path) : '.'
  git.add(rel_path)
  git.smart_commit
end
rescue RuntimeError => e
  Logging.warn "Skipping update -- #{e.message}"
  false
```

**Use instance form when:**
- Only calling a single method (chain directly instead of block overhead)
- Operations spread across conditionals/branches
- Need return values outside the block's scope

```ruby
# Good -- single method call, chain directly
status = GitProcessor.new(dir: repo_dir).status(*switches)

# Good -- return value needed outside block
git = GitProcessor.new(dir: folder_pn)
_out, _err, status = git.pull(rebase: true)
if status.success?
  success "Updated successfully"
else
  record_warning "Failed to update"
end

# Good -- operations across branches
git = GitProcessor.new(dir: repo_dir)
if needs_fetch?
  git.fetch
end
if needs_rebase?
  git.rebase
end
```

**Exception for single calls in blocks:**
When there's only one git operation inside another block (like an `each` loop),
prefer chaining over nested blocks for readability:

```ruby
# Good -- single operation, chain directly (avoids nested block)
chrome_folders.each do |folder_pn|
  status = GitProcessor.new(dir: folder_pn).pull(rebase: true)
  log_result(status)
end

# BAD -- unnecessary nested block for single operation
chrome_folders.each do |folder_pn|
  GitProcessor.new(dir: folder_pn) do |git|
    status = git.pull(rebase: true)
    log_result(status)
  end
end
```

### Exception Handling

Some GitProcessor methods can raise exceptions:
- `relative_path(path)` raises `RuntimeError` if path is invalid or outside repo

When using these methods, wrap the block (or call) in a `rescue` clause:

```ruby
# Good -- rescue outside block when relative_path may raise
GitProcessor.new(dir: repo_dir) do |git|
  rel_path = git.relative_path(some_path)
  git.add(rel_path)
end
rescue RuntimeError => e
  Logging.warn "Skipping operation -- #{e.message}"
  return false
```

### Scan Rule

When adding/editing git operations:
1. Check if there are 2+ consecutive git calls → use block form
2. Check if only 1 git call → use instance form with chaining
3. Check if return value needed in outer scope → use instance form
4. Check if inside another block (each, if/else) with single git call → use chaining
5. Check if using `relative_path` → add `rescue RuntimeError` clause

### Timestamp Standardization

**Always use `Core.current_timestamp` for git commit messages and user-facing timestamps.**

`Core.current_timestamp` (in `utilities/core.rb`) is the single source of truth for
timestamp formatting. It returns `'YYYY-MM-DD HH:MM:SS'` format.

```ruby
# BAD -- direct Time.now.strftime scattered across codebase
timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
git.commit("Update: #{timestamp}")

# Good -- centralized via Core module
require_relative 'core'
git.commit("Update: #{Core.current_timestamp}")
```

**Files must require `core` module:**

When adding timestamp usage to a file that doesn't already require it, add
`require_relative 'core'` to the requires block:

```ruby
require_relative 'git_processor'
require_relative 'logging'
require_relative 'core'      # Add this
```

**Other timestamp patterns (keep as-is):**

Not all `strftime` calls should be replaced:
- **Date-only formats** (`%Y-%m-%d`): Different use case (date without time), keep direct `Time.now.strftime`
- **Custom formats**: If you need a format other than `YYYY-MM-DD HH:MM:SS`, use direct `strftime`

**Examples:**

```ruby
# Good -- git commit messages
git.smart_commit("Incremental commit: #{Core.current_timestamp}")

# Good -- date-only cutoff calculation (different format, keep direct strftime)
cutoff = (Time.now - days * 24 * 3600).strftime('%Y-%m-%d')

# Good -- custom format for specific use case
export_name = Time.now.strftime('%Y%m%d_%H%M%S')
```

**Note on MacOS module:**
`MacOS.current_timestamp` still exists as a delegation method to `Core.current_timestamp`
for backward compatibility. New code should use `Core.current_timestamp` directly to
avoid the extra module dependency (MacOS module requires logging, which creates
unnecessary coupling for simple timestamp access).

### Smart Commit vs Direct `run_alias('sci')`

**Always use `smart_commit` instead of `run_alias('sci')` for git commits.**

`GitProcessor.smart_commit(message = nil)` is a semantic wrapper around `run_alias('sci', message)`.
It provides better API consistency, returns a boolean, and auto-generates commit messages with timestamps.

```ruby
# BAD -- direct run_alias call
git.run_alias('sci', "Commit: #{Core.current_timestamp}")

# BAD -- manual message construction
git.smart_commit("Incremental commit: #{Core.current_timestamp}")

# Good -- auto-generated message based on repo state
git.smart_commit  # "Initial commit: <timestamp>" (no commits) or "Incremental commit: <timestamp>"

# Good -- custom message when auto-generation isn't appropriate
git.smart_commit("Feature: Add user authentication")
```

**Why `smart_commit` is better:**

1. **Semantic clarity**: Name describes intent (not implementation detail)
2. **Boolean return**: Returns true/false instead of `[stdout, stderr, status]`
3. **Auto-generated messages**: No need to manually construct timestamp messages
4. **Repo-aware**: Detects first commit vs subsequent commits automatically via `commit_count`
5. **Consistent API**: Matches other GitProcessor methods (`commit`, `push`, etc.)
6. **Easier testing**: Mock one method instead of `run_alias` with 'sci' check

**Auto-generation behavior:**

When called without a message (`git.smart_commit`):
- Calls `commit_count` to check if any commits exist
- Generates "Initial commit: <timestamp>" if count is 0 (no commits exist)
- Generates "Incremental commit: <timestamp>" if count > 0 (commits exist)
- Works correctly for brand new repos, repos without remotes, and after `git.recreate()`

**Implementation reference:**

```ruby
# From git_processor.rb (simplified)
def smart_commit(message = nil)
  if nil_or_empty?(message)
    prefix = commit_count.zero? ? 'Initial' : 'Incremental'
    message = "#{prefix} commit: #{Core.current_timestamp}"
  end
  _out, _err, status = run_alias('sci', message)
  status.success?
end

def commit_count
  _execute('rev-list', '--all', '--count').strip.to_i
end
```

The `sci` alias (smart commit interactive) handles the logic:
- Aborts if nothing staged
- Amends if 1 unpushed commit
- Creates new commit otherwise

**When to pass explicit messages:**

Use custom messages for:
- Feature commits: `git.smart_commit("Feature: Add user login")`
- Bug fixes: `git.smart_commit("Fix: Resolve authentication issue")`
- Refactoring: `git.smart_commit("Refactor: Extract validation logic")`
- Any commit where the change is semantically meaningful

Use auto-generated messages for:
- Maintenance commits in automated scripts
- Incremental backups/snapshots
- Repository recreation operations
- Automated cron job commits

**Scan rule:**

When editing files with git operations, check for:
1. `Time.now.strftime('%Y-%m-%d %H:%M:%S')` → use `git.smart_commit` with no args
2. `git.run_alias('sci', ...)` → replace with `git.smart_commit(...)`
3. Manual timestamp construction → use `git.smart_commit` with no args
4. Direct `_execute('rev-list', '--all', '--count').strip` → use `git.commit_count` method instead

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

**Files reorganized** (June 2026): `git_processor.rb`, `git_workspace.rb`, `keybase.rb`, `macos.rb`, `profiles_repo.rb`, `plist.rb`, `path_utils.rb`, `command_utils.rb` - all follow this pattern.

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
- Shell functions delegate to Ruby utilities via `call_ruby_utility` (e.g., `suspend_cron` → `Cron.suspend_cron`)
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

## `nil_or_empty?` Helper

Always use `nil_or_empty?` to check for nil-or-empty conditions. It is defined
in `core.rb` and strips strings internally before checking emptiness. Never call
`.empty?` directly on a value that might be `nil`.

```ruby
nil_or_empty?(value)          # Good
value.nil? || value.empty?    # Acceptable but verbose
value.empty?                  # BAD if value could be nil
```

### `nil_or_empty?` Implementation Details

`nil_or_empty?` strips strings internally before checking emptiness:

```ruby
def nil_or_empty?(val)
  return true if val.nil?
  case val
  when String
    val.strip.empty?  # Strips whitespace before checking
  when Array
    val.empty?
  else
    val.to_s.empty?
  end
end
```

This means whitespace-only strings (`"   "`) are treated as empty.

### Safe Method Call Pattern with `nil_or_empty?`

When you need to call a method (like `.strip`, `.upcase`, `.split`) on a potentially-nil
variable, use `nil_or_empty?` as a guard BEFORE calling the method. The `unless/if`
check ensures the method is only called on non-nil values.

**Core Pattern:**
```ruby
# Guard protects method call from nil
output += "\nValue: #{value.strip}" unless nil_or_empty?(value)
```

**Why this works:**
1. `nil_or_empty?(value)` evaluates first
2. If nil/empty, the `unless` condition is true → entire line skipped
3. If non-nil/non-empty, the `unless` condition is false → `value.strip` is evaluated safely

**Common mistake - calling method inside check:**
```ruby
# BAD - strips twice (once in check, once for interpolation)
output += "\nValue: #{value.strip}" unless nil_or_empty?(value.strip)

# Good - check original, strip once for use
output += "\nValue: #{value.strip}" unless nil_or_empty?(value)
```

**When to cache after check:**

If the stripped value is used multiple times, cache it AFTER the nil check:

```ruby
# Single use - inline strip (no caching needed)
meaningful_lines = lines.filter_map do |line|
  next if nil_or_empty?(line)  # Guard against nil/empty/whitespace
  line.strip unless line.strip.match?(/pattern/)  # Use stripped value once
end

# Multiple uses - cache after guard
meaningful_lines = lines.filter_map do |line|
  next if nil_or_empty?(line)  # Guard first
  stripped = line.strip        # Safe to strip now
  stripped unless patterns.any? { |p| stripped.include?(p) }  # Use twice
end
```

**Redundant checks to avoid:**

Because `nil_or_empty?` strips internally, checking the stripped result again is redundant:

```ruby
# BAD - nil_or_empty? already stripped for the check, so stripped can't be empty
next if nil_or_empty?(line)
stripped = line.strip
next if nil_or_empty?(stripped)  # Redundant! line passed nil_or_empty check

# Good - single check is sufficient
next if nil_or_empty?(line)
stripped = line.strip  # Safe now, and guaranteed non-empty after stripping
```

**Summary:**
1. Check `nil_or_empty?` FIRST (on original, potentially-nil value)
2. Call methods like `.strip` AFTER the check passes (safe from nil)
3. Cache stripped value ONLY if used multiple times
4. Avoid redundant `nil_or_empty?` checks on already-validated values

## UTF-8 File Reading

**CRITICAL: Always specify UTF-8 encoding when reading text files.**

### The Problem

Ruby file reading methods use the system's default encoding, which varies by environment:
- **Interactive shells**: Usually UTF-8 (`LC_ALL=en_US.UTF-8`)
- **Cron jobs**: Often US-ASCII (minimal environment)
- **Background processes**: May inherit parent's encoding

When a file contains UTF-8 characters (em dashes, curly quotes, non-ASCII symbols) and is read in a non-UTF-8 environment, Ruby raises:
```
ArgumentError: invalid byte sequence in US-ASCII
```

This commonly affects:
- `scripts/data/capture-prefs-excluded-keys.txt` (UTF-8 content)
- `scripts/data/capture-prefs-denied-list.txt` (UTF-8 content)
- `scripts/data/cleanup-patterns/*.txt` (potentially UTF-8)
- `~/.ssh/config` (potentially UTF-8)
- XML plist files (may contain UTF-8 in values/comments)
- YAML config files (potentially UTF-8)
- Any `.txt` config files

### The Solution

**For line-by-line reading**, use Core module utility methods:

**`Core.read_lines_utf8(filepath)`** - Read all lines into an array:
```ruby
# BAD -- encoding depends on environment
lines = file.readlines
lines = File.readlines(file)

# Good -- explicit UTF-8 encoding
lines = Core.read_lines_utf8(file)
```

**`Core.each_line_utf8(filepath) { |line| ... }`** - Iterate lines with a block:
```ruby
# BAD -- encoding depends on environment
file.each_line { |line| process(line) }
File.foreach(file) { |line| process(line) }
File.open(file, 'r:UTF-8') { |f| f.each_line { |line| process(line) } }

# Good -- explicit UTF-8 encoding
Core.each_line_utf8(file) { |line| process(line) }
```

**For reading entire file content**, use `Pathname#read(encoding: 'UTF-8')`:
```ruby
# BAD -- encoding depends on environment
content = file.read
content = File.read(file)

# Good -- explicit UTF-8 encoding
content = file.read(encoding: 'UTF-8')
content = File.read(file, encoding: 'UTF-8')
```

### When to Use Each Method

**Use `Core.read_lines_utf8`** when:
- You need the entire file as an array
- You'll process the array multiple times
- You need array methods (`.length`, `.select`, `.map`, etc.)

```ruby
# Example: Count non-empty lines
lines = Core.read_lines_utf8(config_file)
count = lines.reject { |l| l.strip.empty? }.length
```

**Use `Core.each_line_utf8`** when:
- You process each line once and discard it
- Memory efficiency matters (large files)
- You break early from the loop

```ruby
# Example: Find first match
Core.each_line_utf8(config_file) do |line|
  next if line.strip.empty?
  next if line.start_with?('#')
  return line if line.include?(search_term)
end
```

**Use `file.read(encoding: 'UTF-8')`** when:
- You need the entire file content as a single string
- Parsing XML/JSON/YAML (pass to parser)
- Pattern matching against full file content

```ruby
# Example: Check if plist has any keys
has_keys = plist_file.read(encoding: 'UTF-8').match?(/<key>/)

# Example: Parse XML with explicit encoding
doc = REXML::Document.new(plist_file.read(encoding: 'UTF-8'))

# Example: Parse YAML with explicit encoding
config = YAML.safe_load(config_file.read(encoding: 'UTF-8'))
```

### Implementation Details

Both methods use `File.open(path, 'r:UTF-8')` internally:
- `'r'` - Read-only mode
- `':UTF-8'` - Explicit encoding (not environment-dependent)

They accept both `String` and `Pathname` arguments and return UTF-8 encoded strings.

### Exception: String#each_line (NOT File Reading)

`String#each_line` operates on in-memory strings (not files) and does NOT need replacement:

```ruby
# This is FINE -- operating on String object, not reading a file
error_message.each_line { |line| puts line }
stdout_output.each_line { |line| process(line) }
```

Strings are already in UTF-8 in memory, so no encoding issues occur.

**Files using String#each_line correctly:**
- `scripts/utilities/logging.rb` - Processing multi-line log messages
- `scripts/utilities/command_utils.rb` - Processing stderr output
- `scripts/utilities/git_processor.rb` - Processing command stdout

### Scan Rule

When adding file reading code:
1. ❌ **Never** use: `file.readlines`, `File.readlines(file)`, `file.each_line`, `File.foreach(file)`, `file.read`, `File.read(file)`
2. ✅ **For line-by-line**: Use `Core.read_lines_utf8(file)` or `Core.each_line_utf8(file) { }`
3. ✅ **For full content**: Use `file.read(encoding: 'UTF-8')` or `File.read(file, encoding: 'UTF-8')`
4. ⚠️ **Exception**: `String#each_line` on in-memory strings is fine

When editing existing code:
1. Search for: `\.readlines`, `File\.readlines`, `\.each_line`, `File\.foreach`, `\.read\b`, `File\.read`
2. Verify: Is this a file operation or string operation?
3. If file (line-by-line): Replace with `Core.read_lines_utf8` or `Core.each_line_utf8`
4. If file (full content): Add `encoding: 'UTF-8'` parameter
5. If string: Keep as-is (no change needed)

### Verification

After replacing file reading calls, verify syntax:
```bash
/usr/bin/ruby -c path/to/script.rb
```

Test in cron-like environment (minimal locale):
```bash
env -i HOME=$HOME USER=$USER /usr/bin/ruby path/to/script.rb
```

## Memoization

Use memoization (`||=`) to cache expensive or repeated operations. Common candidates:
- Methods called multiple times with the same result per script execution
- Shell command existence checks (`command_exists?`)
- Boolean flag queries that compare strings (`operation == 'export'`)
- Expensive computations that don't change during script lifetime

### Memoized Helper Pattern

For repeated checks across multiple helper methods, extract a memoized helper:

```ruby
# BAD -- repeated expensive check (4 calls = 4 shell invocations)
def update_home_repos
  return unless PathUtils.command_exists?('run-all.rb')
  # ...
end

def upreb_oss_repos
  return unless PathUtils.command_exists?('run-all.rb')
  # ...
end

def restore_mtime
  return unless PathUtils.command_exists?('run-all.rb')
  # ...
end

# main
if PathUtils.command_exists?('run-all.rb')
  update_home_repos
end

# Good -- single memoized check (4 calls = 1 shell invocation)
def _run_all_available?
  @_run_all_available ||= PathUtils.command_exists?('run-all.rb')
end

def _update_home_repos
  return unless _run_all_available?
  # ...
end

def _upreb_oss_repos
  return unless _run_all_available?
  # ...
end

def _restore_mtime
  return unless _run_all_available?
  # ...
end

private :_run_all_available?, :_update_home_repos, :_upreb_oss_repos, :_restore_mtime

# main
if _run_all_available?
  _update_home_repos
end
```

### Memoized Boolean Query Pattern

For repeated string comparisons that determine script mode/behavior:

```ruby
# BAD -- repeated string comparison (7 occurrences in one script)
if operation == 'export'
  export_logic
end

if operation == 'import'
  import_logic
end

if operation == 'export'
  more_export_logic
end

# Good -- memoized query (comparison happens once, cached forever)
def _exporting?
  @_exporting ||= @operation == 'export'
end

def _importing?
  @_importing ||= @operation == 'import'
end

private :_exporting?, :_importing?

if _exporting?
  export_logic
end

if _importing?
  import_logic
end

if _exporting?
  more_export_logic
end
```

### When NOT to Memoize

Do NOT memoize when:
- The method is only called once per script execution
- The value can change during script execution (ENV vars that might be modified, file system state)
- The operation is already cheap (simple arithmetic, string concatenation, hash lookup)
- The method has side effects (logging, file I/O, system calls that must run every time)

```ruby
# BAD -- memoizing dynamic state
def _files_exist?
  @_files_exist ||= Dir.glob('*.txt').any?  # file system can change between calls
end

# BAD -- memoizing single-use check
def _valid_argument?
  @_valid_argument ||= ARGV.first && ARGV.first.start_with?('--')  # only checked once
end

# Good -- don't memoize dynamic state
def files_exist?
  Dir.glob('*.txt').any?  # check fresh each time
end

# Good -- don't memoize single-use check (no benefit)
if ARGV.first && ARGV.first.start_with?('--')
  # ...
end
```

### Scan Rule: Identify Memoization Opportunities

When editing a Ruby script, look for:

1. **Repeated method calls in guards**: Same `command_exists?`, `File.exist?`, or boolean check at top of 3+ methods
2. **Repeated string comparisons**: `@var == 'value'` appearing 3+ times across the script
3. **Command existence checks**: `PathUtils.command_exists?('tool')` called multiple times
4. **Operation mode checks**: Comparing an operation/mode variable repeatedly

Example scan:
```bash
# Find repeated method calls
rg "command_exists?\|File\.exist?\|\.any?\|\.empty?" script.rb | sort | uniq -c | sort -rn

# Find repeated string comparisons
rg "@\w+ == ['\"]" script.rb | sort | uniq -c | sort -rn
```

When you find a pattern repeated 3+ times:
1. Extract a memoized helper with `_` prefix
2. Add to `private` declaration
3. Replace all occurrences with the helper call
4. Verify the value doesn't change during script execution

### Proactive Memoization Review

**When making changes to any Ruby file, proactively look for memoization opportunities.**

This applies when:
- Adding new functionality that queries system state
- Refactoring code that calls the same method multiple times
- Reviewing existing code for performance improvements
- Implementing loops that check conditions repeatedly

**Pattern recognition checklist:**
- [ ] Are there repeated `command_exists?` calls?
- [ ] Are there repeated `File.exist?` or `Dir.exist?` checks with same path?
- [ ] Are there repeated string comparisons (`@var == 'value'`)?
- [ ] Are there repeated ENV variable reads (`ENV.fetch('VAR', ...)`)?
- [ ] Are there repeated method calls that return the same value?
- [ ] Are there loop-based operations where guard checks are constant?

**Examples of good opportunities:**

```ruby
# Repeated command checks across methods
def method_a
  return unless PathUtils.command_exists?('tool')  # 1st check
end

def method_b
  return unless PathUtils.command_exists?('tool')  # 2nd check - memoize!
end

# Repeated array allocations in hot path
def _should_stream_output?(args)
  # BAD - creates new arrays every call
  streaming_commands = %w[push pull fetch]
  quiet_flags = %w[-q --quiet]
  # Good - extract to frozen constants
end

# Repeated string operations
def format_output
  stdout.strip  # 1st strip
  # ... later ...
  if !stdout.strip.empty?  # 2nd strip on same value - cache it!
end
```

**When to suggest memoization:**
- Mention it in code review comments
- Add it when performance profiling reveals hot spots
- Include it when refactoring existing code
- Consider it when writing new utility methods

**Balance with readability:**
- Don't over-optimize single-use code
- Don't memoize unless called 3+ times
- Don't memoize dynamic/changing state
- Do document why memoization was added (performance, not premature optimization)

### Instance Variables for Memoization

Memoization in top-level scripts uses instance variables (`@var`). This works because:
- Top-level script code runs in the context of `main` (an Object instance)
- Instance variables persist for the script's lifetime
- Each script execution gets a fresh `main` object (clean slate)

```ruby
# Top-level script (not a class/module)
def _run_all_available?
  @_run_all_available ||= PathUtils.command_exists?('run-all.rb')
end

# Instance variable @_run_all_available persists in main's context
# First call: checks command, caches result
# Subsequent calls: returns cached result immediately
```

In utility modules using `extend self`, memoization uses `@` instance variables on the module singleton:

```ruby
module MyUtility
  extend self

  def expensive_check
    @_expensive_check ||= some_expensive_operation
  end
end

# @_expensive_check lives on MyUtility's singleton, persists across calls
```

## Hot Path Optimization -- Frozen Constants

**Hot path**: Code that executes frequently (called in loops, once per git command, on every file, etc.)

**Problem**: Allocating arrays/hashes repeatedly in hot paths creates garbage collection pressure.

**Solution**: Extract to frozen constants at module/class level.

### Pattern: Extract to Frozen Constants

```ruby
# BAD - allocates new arrays on every call (hot path in git operations)
def _should_stream_output?(args)
  streaming_commands = %w[push pull fetch]     # New array every call
  quiet_flags = %w[-q --quiet]                 # New array every call

  return false if (args & streaming_commands).empty?
  (args & quiet_flags).empty?
end

# Good - allocate once at load time
class GitProcessor
  STREAMING_COMMANDS = %w[push pull fetch].freeze
  QUIET_FLAGS = %w[-q --quiet].freeze

  def _should_stream_output?(args)
    return false if (args & STREAMING_COMMANDS).empty?
    (args & QUIET_FLAGS).empty?
  end
end
```

### When to Use Frozen Constants

Use frozen constants when:
- **Hot path**: Method called frequently (loops, per-item processing, every git command)
- **Static data**: Array/hash contents never change at runtime
- **Repeated allocations**: Same literal array/hash created on every call

**Example hot paths:**
- `_should_stream_output?` - called once per git command
- `_filter_stderr_patterns` - called for every command with stderr filtering
- Validation methods called in loops over files/repos

### Constant Naming and Location

**Naming convention:**
- Use SCREAMING_SNAKE_CASE for constants
- Descriptive names based on purpose (e.g., `STREAMING_COMMANDS` not `COMMANDS`)

**Location:**
- Class-level constants: `class GitProcessor; CONST = ...; end`
- Module-level constants: `module MyModule; CONST = ...; end`
- Place near the top of the class/module (after includes/extends, before methods)

### `.freeze` is Mandatory

Always call `.freeze` on constant arrays/hashes:

```ruby
# BAD - not frozen, can be mutated accidentally
STREAMING_COMMANDS = %w[push pull fetch]

# Good - frozen, mutations raise FrozenError
STREAMING_COMMANDS = %w[push pull fetch].freeze
```

Ruby does NOT auto-freeze constants. Without `.freeze`, constants can be accidentally mutated (`CONST << 'item'`), leading to hard-to-debug issues.

### Scan Rule: Identify Hot Path Array Allocations

When editing Ruby files, look for:

1. **Methods called in loops** - check for array/hash literals inside
2. **Guard methods called frequently** - validation, filtering, checking
3. **Array literals in method bodies** - `%w[...]`, `[...]`, `{...}`
4. **Methods with low call count but high time** - `zprof` profiling data

**Search pattern:**
```bash
# Find methods with array/hash literals
grep -n "def.*\n.*%w\[" file.rb
grep -n "= \[" file.rb
```

**When you find array/hash literals in a method:**
1. Is the method called frequently? (hot path?)
2. Is the array/hash content static? (never changes?)
3. If yes to both → extract to frozen constant

### Real-World Impact

**Example: GitProcessor._should_stream_output?**
- **Before**: Created 2 arrays per git command (100s of commands per cron run)
- **After**: Zero allocations per command
- **Benefit**: Reduced GC pressure, cleaner code, no performance regression

**Note**: Premature optimization is bad, but constants for hot path static data is a standard Ruby idiom (like `Regexp` constants for frequently-used patterns).

## Variable Scoping

Always declare variables in the innermost scope where they are used. This improves
garbage collection, clarifies intent, and prevents accidental reuse.

### Move variables inside blocks when they're only used there

```ruby
# BAD -- variable declared outside block but only used inside
timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
GitProcessor.new(dir: repo_dir) do |git|
  git.add(path)
  git.run_alias('sci', "Commit: #{timestamp}")
end

# Good -- variable scoped to block
GitProcessor.new(dir: repo_dir) do |git|
  timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
  git.add(path)
  git.run_alias('sci', "Commit: #{timestamp}")
end
```

### Declare variables in the branch where they're used

```ruby
# BAD -- variable declared before if/else but only used in one branch
target_file = target_dir.join("#{name}.plist")
if operation == 'export'
  export_file(target_file)
else
  # Import branch doesn't use target_file initially
  unless target_file.file?
    next
  end
  import_file(target_file)
end

# Good -- declare in each branch where needed
if operation == 'export'
  target_file = target_dir.join("#{name}.plist")
  export_file(target_file)
else
  target_file = target_dir.join("#{name}.plist")
  unless target_file.file?
    next
  end
  import_file(target_file)
end
```

### Check scoping when refactoring

When refactoring code:
1. Look for variables declared at function/class scope
2. Check if they're only used within a single block (if/else, loop, GitProcessor block)
3. Move them to the innermost scope where they're used
4. Eliminate intermediate variables that are only used once

**Scan rule:** After editing any Ruby file, search for variables declared before
blocks (`do |var|`, `if/else`, `each`) and verify they're used outside the block.
If not, move them inside.

## Variable Extraction vs Inlining

**Extract a local variable when a value is used multiple times (2+):**

```ruby
# BAD -- repeated computation/access
Logging.info "Processing '#{EnvVars::PERSONAL_CONFIGS_DIR.to_s.cyan}'"
target = EnvVars::PERSONAL_CONFIGS_DIR.join('file.txt')
unless EnvVars::PERSONAL_CONFIGS_DIR.directory?
  # ...
end

# Good -- extract when used 2+ times
configs_dir = EnvVars::PERSONAL_CONFIGS_DIR
Logging.info "Processing '#{configs_dir.to_s.cyan}'"
target = configs_dir.join('file.txt')
unless configs_dir.directory?
  # ...
end
```

**Inline a variable when used only once AND no readability/maintainability benefit:**

```ruby
# BAD -- unnecessary intermediate variable (only used once)
bat_config_dir, = Open3.capture3('bat', '--config-dir')
bat_config_dir_pn = Pathname.new(bat_config_dir.strip)
bat_syntax_dir_pn = bat_config_dir_pn.join('syntaxes')

# Good -- inline single-use intermediate
bat_config_dir, = Open3.capture3('bat', '--config-dir')
bat_syntax_dir_pn = Pathname.new(bat_config_dir.strip).join('syntaxes')

# BAD -- inlining hurts readability (complex expression)
status = GitProcessor.new(
  dir: Pathname.new(ENV.fetch('PERSONAL_PROFILES_DIR')).expand_path.join('Chrome')
).pull(rebase: true)

# Good -- keep variable for complex multi-step construction
chrome_profiles = Pathname.new(ENV.fetch('PERSONAL_PROFILES_DIR')).expand_path.join('Chrome')
status = GitProcessor.new(dir: chrome_profiles).pull(rebase: true)
```

**Keep variable even if used once when it provides:**

1. **Semantic clarity** -- Variable name documents what the value represents:
   ```ruby
   # Good -- variable name adds meaning
   is_shallow = git_dir.join('shallow').exist?
   return unless is_shallow

   # Acceptable but less clear
   return unless git_dir.join('shallow').exist?
   ```

2. **Debugging convenience** -- Can inspect value in debugger:
   ```ruby
   # Good -- can inspect stderr in debugger
   _out, stderr, status = Open3.capture3('git', 'push')
   Logging.error(stderr) unless status.success?

   # BAD -- can't inspect stderr after the fact
   _, stderr, status = Open3.capture3('git', 'push')
   Logging.error(stderr) unless status.success?  # stderr not available in debugger
   ```

3. **Complex computation** -- Breaking into steps improves readability:
   ```ruby
   # Good -- steps are clear
   raw_output, = Open3.capture3('git', 'config', '--get', 'remote.origin.url')
   normalized = raw_output.strip.gsub(%r{\.git$}, '')
   owner = normalized.split('/')[-2]

   # BAD -- hard to parse mentally
   owner = Open3.capture3('git', 'config', '--get', 'remote.origin.url')[0].strip.gsub(%r{\.git$}, '').split('/')[-2]
   ```

4. **Repeated method arguments** -- Extract to avoid duplication:
   ```ruby
   # Good -- DRY
   error_msg = "Failed to process '#{file.to_s.cyan}'"
   Logging.record_error(error_msg)
   notify('Error', error_msg)

   # BAD -- duplicated string construction
   Logging.record_error("Failed to process '#{file.to_s.cyan}'")
   notify('Error', "Failed to process '#{file.to_s.cyan}'")
   ```

**When inlining is preferred:**

- Simple value assignments: `count = 0`, `result = true`
- Single chained method call: `items.select { }.first`
- Direct constant/variable access: `dir = EnvVars::HOME`
- Trivial transformations: `path.to_s`, `value.strip`

**Scan rule:** When editing code, check:
1. Is this variable used 2+ times? → Keep it (or extract if inlined)
2. Used once + complex expression? → Keep it
3. Used once + adds semantic clarity? → Keep it
4. Used once + simple/trivial? → Inline it

### Variable Extraction Rule (Universal)

**MANDATORY: Extract ANY value to local variable when used 2+ times in the same method/block.**

This rule applies universally to:
- **EnvVars constants**: `EnvVars::PERSONAL_PROFILES_DIR`
- **Method calls**: `some_object.method_call`
- **Complex expressions**: `path.join('subdir').expand_path`
- **Pathname operations**: `dir.join('.git')`
- **Computed values**: `limit_gb * 1024`

The 2+ usage threshold is strict - even if used only twice, extract it.

```ruby
# BAD -- EnvVars::PERSONAL_PROFILES_DIR used 4 times
def capture_and_commit
  unless GitProcessor.repo?(EnvVars::PERSONAL_PROFILES_DIR)
    Logging.warn "Skipping profiles repo update -- '#{EnvVars::PERSONAL_PROFILES_DIR.cyan}' is not a git repo"
    return false
  end

  Logging.debug "Updating profiles repo at '#{EnvVars::PERSONAL_PROFILES_DIR.cyan}'"
  GitProcessor.new(dir: EnvVars::PERSONAL_PROFILES_DIR) do |git|
    git.add('.')
    git.smart_commit
  end
end

# Good -- extract to local variable
def capture_and_commit
  profiles_dir = EnvVars::PERSONAL_PROFILES_DIR

  unless GitProcessor.repo?(profiles_dir)
    Logging.warn "Skipping profiles repo update -- '#{profiles_dir.cyan}' is not a git repo"
    return false
  end

  Logging.debug "Updating profiles repo at '#{profiles_dir.cyan}'"
  GitProcessor.new(dir: profiles_dir) do |git|
    git.add('.')
    git.smart_commit
  end
end

# BAD -- git_dir.join('.git') computed twice
def check_size_limit(limit_gb: 2)
  size_mb = PathUtils.git_repo_size_mb(git_dir.join('.git'))
  size_human = PathUtils.git_repo_size_human(git_dir.join('.git'))
end

# Good -- extract .git path
def check_size_limit(limit_gb: 2)
  git_path = git_dir.join('.git')
  size_mb = PathUtils.git_repo_size_mb(git_path)
  size_human = PathUtils.git_repo_size_human(git_path)
end

# BAD -- limit_gb * 1024 appears multiple times
def check_size_limit(limit_gb: 2)
  if size_mb > limit_gb * 1024
    warn "Size exceeds #{limit_gb * 1024}MB"
  end
end

# Good -- extract computed value
def check_size_limit(limit_gb: 2)
  limit_mb = limit_gb * 1024
  if size_mb > limit_mb
    warn "Size exceeds #{limit_mb}MB"
  end
end
```

**Single use → inline (no extraction needed):**

```ruby
# Good -- used only once, inline it
def check_size
  return unless EnvVars::PERSONAL_PROFILES_DIR.directory?  # Single use, inline
  # ... rest of method doesn't use it again ...
end
```

**Why this rule matters:**
1. **Readability**: Shorter lines, clearer intent
2. **Performance**: Avoid repeated expensive operations (Pathname construction, method calls, arithmetic)
3. **Maintainability**: Change the value once instead of N times
4. **DRY principle**: Single source of truth within method scope

**Scan rule:** When editing code, check:
1. Is this value/expression used 2+ times in this method? → Extract to local variable
2. Used only once? → Inline (no extraction)
3. Applies to: constants, method calls, complex expressions, computations - everything

### Destructive Operations -- Capture Metadata Before Destruction

**MANDATORY: Before any destructive operation (deleting `.git`, removing directories, truncating files), capture all required metadata into local variables.**

This prevents data loss when the operation fails partway through.

**Examples of destructive operations:**
- `git_path.rmtree` (deletes `.git` directory)
- `FileUtils.rm_rf(dir)` (deletes directory tree)
- `file.truncate(0)` (empties file)
- `db.execute('DROP TABLE...')` (deletes database table)

**Required pattern:**

```ruby
# Good -- capture BEFORE destroying
def _recreate(ref_format: 'reftable', remote_name: 'origin')
  git_path = @dir.join('.git')

  # Capture current state BEFORE destroying .git
  branch_name = current_branch       # ← Reads from .git
  remote_url = remote_url(name: remote_name)  # ← Reads from .git
  user_name = config_value('user.name')      # ← Reads from .git
  user_email = config_value('user.email')    # ← Reads from .git

  # NOW it's safe to destroy
  git_path.rmtree

  # Restore from captured state
  init(ref_format: ref_format, initial_branch: branch_name)
  add_remote(remote_name, remote_url) unless nil_or_empty?(remote_url)
  config_set('user.name', user_name) unless nil_or_empty?(user_name)
  config_set('user.email', user_email) unless nil_or_empty?(user_email)
end

# BAD -- capture AFTER destroying (data loss!)
def _recreate(ref_format: 'reftable', remote_name: 'origin')
  git_path = @dir.join('.git')
  git_path.rmtree  # ← .git is gone!

  # These calls fail -- .git doesn't exist anymore!
  branch_name = current_branch       # ← FAILS
  remote_url = remote_url(name: remote_name)  # ← FAILS
end
```

**Common destructive operations in this codebase:**
- `GitProcessor#_recreate` → captures branch, remote, config before `rmtree`
- `recreate-repository.rb` → captures remote file list before `_recreate`
- `install-dotfiles.rb` → backs up existing files before symlinking
- `capture-prefs.rb` → validates target dir exists before `unlink`

**Verification checklist before destructive operation:**
1. ✅ All required data captured into local variables
2. ✅ Variables declared BEFORE destruction call
3. ✅ Restoration logic uses captured variables (not re-queries)
4. ✅ Error handling accounts for partial failures

**Scan rule:** When reviewing code with destructive operations, trace backwards from the destruction call and verify all dependent data is captured first.

## Common Mistakes (Code Review Findings)

Based on code review patterns and debugging sessions, here are the most common mistakes to avoid:

1. **Calling color methods on Pathname without extension** → Ensure `pathname_ext.rb` is required
   ```ruby
   # BAD -- pathname_ext.rb not required
   info "Processing '#{profile_folder.cyan}'"  # NoMethodError

   # Good -- require pathname_ext.rb at top of file
   require_relative 'utilities/pathname_ext'
   info "Processing '#{profile_folder.cyan}'"  # Works! Returns colored String

   # Also acceptable -- explicit .to_s if pathname_ext not needed elsewhere
   info "Processing '#{profile_folder.to_s.cyan}'"
   ```

2. **Hardcoding paths** → Use `EnvVars::HOME` and other constants
   ```ruby
   # BAD
   config = Pathname.new("/Users/vijay/.config/file")
   # Good
   config = EnvVars::XDG_CONFIG_HOME.join('file')
   ```

3. **Using `exit()` in module methods** → Return boolean instead
   ```ruby
   # BAD - kills parent process if module is called directly
   def run
     exit(1) if error
   end
   # Good - let caller decide what to do
   def run
     return false if error
     true
   end
   ```

4. **Forgetting to increment script depth** → Indentation breaks for nested calls
   ```ruby
   # BAD - no depth tracking
   start_time = print_script_start
   # Good - always increment first
   Logging.increment_script_depth
   start_time = print_script_start
   ```

5. **Using `set -e` with `&&` conditionals in shell** → Use explicit `if` statements (see shell-scripting.md § `&&` as Conditional)

6. **Forgetting `.freeze` on constant arrays** → Can be mutated accidentally
   ```ruby
   # BAD
   STREAMING_COMMANDS = %w[push pull fetch]
   # Good
   STREAMING_COMMANDS = %w[push pull fetch].freeze
   ```

7. **Not quoting shell variables** → Breaks with spaces in paths (see shell-scripting.md § Quoting)

8. **Using `ENV['VAR']` instead of `ENV.fetch`** → Returns nil silently on typos
   ```ruby
   # BAD - typo returns nil, hard to debug
   value = ENV['FORCE_COLLOR']
   # Good - raises KeyError on typo
   value = ENV.fetch('FORCE_COLOR', '')
   ```

9. **Mutating methods returning nil** → Use non-mutating versions (`strip` not `strip!`)
   ```ruby
   # BAD - returns nil if no whitespace
   value = value.strip!
   # Good - always returns a string
   value = value.strip
   ```

10. **Subprocess calls when Ruby mode available** → Use module methods for performance
    ```ruby
    # BAD - forks subprocess
    system(RbConfig.ruby, 'scripts/install-dotfiles.rb')
    # Good - direct module call
    require_relative 'install-dotfiles'
    InstallDotfiles.run
    ```
