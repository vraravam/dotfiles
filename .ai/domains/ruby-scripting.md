---
applyTo: "**/*.rb"
name: dotfiles-ruby-scripting
description: Use when creating or editing any Ruby script (.rb) in this dotfiles repo -- scripts/*.rb, scripts/utilities/*.rb, or ${PERSONAL_BIN_DIR}/*.rb. This is the CORE Ruby file; read it first. Covers the dual-mode module+CLI pattern, named vs positional parameters, fail-fast validation, single exit point, private method discipline, and Ruby 2.6 compatibility (no endless ranges, pattern matching, numbered block params). Topic files cover infrastructure (Logging/CliParser/EnvVars), shell/git/IO (GitProcessor, UTF-8), and performance idioms (memoization).
---

# Ruby Script Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules when writing or editing any Ruby script in this repository.

## Topic Files (load on demand)

This file holds the rules every Ruby edit needs. Read the sibling file when the task touches its topic:

| File | Read when the task involves |
|------|-----------------------------|
| [`ruby-infrastructure.md`](./ruby-infrastructure.md) | `Logging`, `CliParser`, `EnvVars`, color helpers, `require` ordering, utility-module/class structure, script output format |
| [`ruby-shell-git-io.md`](./ruby-shell-git-io.md) | `system()`/shell escaping, `GitProcessor`, reading files (UTF-8), `nil_or_empty?` |
| [`ruby-performance-idioms.md`](./ruby-performance-idioms.md) | Memoization, frozen constants, loop hoisting, string/collection performance, trailing conditionals, idiomatic patterns |

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
| Required-value fail-fast | `raise ArgumentError, '...' if nil_or_empty?(x)` | [§ Parameter Validation](#parameter-validation----fail-fast-on-missing-required-values) |
| Logging | `Logging.info`, `Logging.success`, `Logging.warn` | [§ Logging](./ruby-infrastructure.md#logging) |
| Path constants | `EnvVars::DOTFILES_DIR` | [§ Path Constants](./ruby-infrastructure.md#path-constants) |
| Option parsing | `CliParser.parse` | [§ Option Parsing](./ruby-infrastructure.md#option-parsing----use-cliparser) |
| Git operations | `GitProcessor.new(dir:)` | [§ GitProcessor Usage](./ruby-shell-git-io.md#gitprocessor-usage-patterns) |
| Nil check | `nil_or_empty?(value)` | [§ `nil_or_empty?` Helper](./ruby-shell-git-io.md#nil_or_empty-helper) |
| File reading (UTF-8) | `Core.read_lines_utf8(file)` | [§ UTF-8 File Reading](./ruby-shell-git-io.md#utf-8-file-reading) |
| Color methods | `string.to_s.cyan` (NOT on Pathname) | [§ String Colors](./ruby-infrastructure.md#string-colors) |
| Script depth | `Logging.increment_script_depth` | [§ Script Depth Tracking](./script-depth-tracking.md) |
| Memoization | `@_var ||= expensive_operation` | [§ Memoization](./ruby-performance-idioms.md#memoization) |
| Loop-invariant work | Compute once before the loop | [§ Loop-Invariant Hoisting](./ruby-performance-idioms.md#loop-invariant-hoisting----move-unchanging-work-outside-loops) |
| Repeated `.include?` checks | `Set.new(arr)` instead of `Array` | [§ Set vs Array](./ruby-performance-idioms.md#set-vs-array----membership-checks) |
| `.select{}.any?`/`.sort.first` | `.any?{}`/`.min` (no intermediate collection) | [§ Enumerable Chains](./ruby-performance-idioms.md#enumerable-chains----avoid-intermediate-collection-allocation) |
| Guard before expensive work | Cheap check first, expensive work after | [§ Early-Exit](./ruby-performance-idioms.md#early-exit-before-expensive-computation) |

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

**Autoload function naming**: Zsh autoload functions in `${XDG_CONFIG_HOME}/zsh/` use single-word names by design (e.g., `st`, `count`). This is not a "no separator needed" exception—it's a deliberate convention for autoloaded commands that matches shell built-in naming patterns.

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

  # run_script increments the script depth, prints the start banner and, when the block
  # finishes (or raises), the grouped warnings/errors summary and duration.
  Logging.run_script do
    exit(MyScript.run(param: options[:param]) ? 0 : 1)
  end
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
   - Wraps the call in `Logging.run_script { ... }` (script depth, start banner, final summary;
     pass a message as the second argument for a custom completion line, e.g.
     `Logging.run_script(nil, 'Done.') { ... }`)
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

5. **Long procedural scripts follow the same shape**
   - An install-style script with many sequential steps still puts its body in `run` (returning
     `true`/`false`) and keeps process-level concerns (`at_exit` hooks, `exit`, the final
     notification) in the CLI block, so requiring the file never starts an install.
   - Numbered progress uses `StepCounter` (`utilities/step_counter.rb`): `StepCounter.new(total)`
     then `counter.step(title, header) { ... }`, or `counter.next_prefix` when the caller composes
     its own header.
   - A single grouped notification is built from `Logging.issue_summary_parts` (the
     "N error(s): ..." / "N warning(s): ..." entries) rather than re-deriving them from
     `Logging.step_errors`/`step_warnings`.

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

`fresh-install-of-osx.sh` invokes `add-upstream-git-config.rb` as a CLI subprocess
(not a direct module call) because it runs before Ruby scripts have any guarantee
of being on `PATH`/`RUBYLIB` during the earliest bootstrap steps. `UPSTREAM_GH_USERNAME`
is a shell-only env var (see `files/--HOME--/.shellrc`) passed as a `-u` flag --
there is no corresponding `EnvVars::UPSTREAM_GH_USERNAME` Ruby constant:

```zsh
COLUMNS="${COLUMNS}" add-upstream-git-config.rb -d "${DOTFILES_DIR}" -u "${UPSTREAM_GH_USERNAME}" || _record_warning '...'
```

For scripts that *do* call each other as Ruby modules directly (the common case --
see the dual-mode pattern above), the calling convention looks like:

```ruby
# Top of file
require_relative 'install-dotfiles'

# Inside main()
unless InstallDotfiles.run
  record_error 'install-dotfiles encountered errors'
end
```

#### From shell (still works)

```zsh
# Call as standalone CLI tool (bare invocation -- shebang + executable bit +
# ${DOTFILES_DIR}/scripts already in PATH via .zshrc)
add-upstream-git-config.rb -d ~/repo -u upstream-owner
install-dotfiles.rb --dry-run
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

**capture-prefs.rb** - Used to be a subprocess because of `at_exit` hooks; now runs in-process:
- `CapturePrefs.run(operation:, manage_apps:)` restores everything in an `ensure` instead of `at_exit`
- `manage_apps` defaults to false when `DOTFILES_APPS_BRACKETED` is set (the caller -- `PreferencesRestore` --
  brackets the baseline and the import once); a standalone run brackets by itself
- Its per-domain export/import loops use a bounded thread pool whose workers never log (see
  `fresh-install.md` § Preferences Step)

**Key insight**: `at_exit` hooks fire at *process* end, not after each operation, so a module that needs
per-operation cleanup must use `begin/ensure` (or `Logging.run_script`), not `at_exit`. Keep a script as a
subprocess only when it genuinely needs its own process lifecycle.

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
def size_kb(dir)
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

## Parameter Validation -- Fail Fast on Missing Required Values

**Every method must either fail fast on a missing/invalid required value, or
have a default it can safely proceed with. There is no third option: a
parameter that's silently used while nil/empty is a bug.**

### Required positional and keyword parameters -- Ruby already fails fast

A required positional parameter (`def foo(bar)`) or required keyword parameter
(`def foo(bar:)`, no default) automatically raises `ArgumentError` if the
caller omits it. This is real, immediate fail-fast behavior -- no manual
check is needed for these:

```ruby
# Good -- Ruby itself raises ArgumentError if dir is omitted; no guard needed
def clone_repo(dir:)
  # ...
end
```

### Optional parameters with a nil-like default -- guard before use

An optional parameter's default only removes the `ArgumentError` -- it does
**not** make a nil value safe to use. If the method cannot sensibly proceed
with `nil`/empty, guard it explicitly with `nil_or_empty?` (see
[§ `nil_or_empty?` Helper](./ruby-shell-git-io.md#nil_or_empty-helper)) and fail fast, rather than
letting `nil` propagate into a path, command, or method call where it would
raise a confusing low-level error (`NoMethodError`, malformed path) instead of
a clear message:

```ruby
# BAD -- dir: nil is not a genuine "no-op" default; a nil here breaks
# Pathname()/system() downstream with a confusing error, not a clear one
def clone_repo(dir: nil)
  system('git', 'clone', dir.to_s)  # dir.to_s == "" if nil -- silently wrong
end

# Good -- fail fast with a clear message if the value the method actually
# needs to proceed is missing
def clone_repo(dir: nil)
  raise ArgumentError, 'clone_repo: dir is required' if nil_or_empty?(dir)

  system('git', 'clone', dir.to_s)
end
```

Do NOT add a guard when the default is a genuinely safe, fully-functional
value the method is designed to proceed with (`dry_run: false`, `force: false`,
`ref_format: 'reftable'`, `remote: 'origin'`) -- these are real defaults, not
placeholders standing in for "should have been required."

### CLI-collected values -- `options` hash and `ARGV` bypass Ruby's enforcement

The dual-mode CLI wrapper collects flags into an `options` hash and calls
`Module.run(**options)`. A missing CLI flag becomes whatever the method's own
keyword default is (often `nil`) rather than raising `ArgumentError` -- the
`**options` splat bypasses Ruby's automatic required-keyword enforcement.
Any value the script cannot function without must be checked explicitly
**before** it's used, immediately after parsing:

```ruby
parser.abort_with_usage('Missing required option: --dir') if nil_or_empty?(options[:dir])
```

The same applies to positional `ARGV` reads:

```ruby
folder = ARGV.first
parser.abort_with_usage('Missing required argument: <folder>') if nil_or_empty?(folder)
```

See [§ Option Parsing -- Use `CliParser`](./ruby-infrastructure.md#option-parsing----use-cliparser)
for the complete `abort_with_usage` pattern.

**Scan rule:** when editing any method, check every optional/keyword-default
parameter that isn't a genuinely safe default, and every `options[:x]`/`ARGV`
read -- confirm a `nil_or_empty?` guard (or Ruby's automatic enforcement, for
required params) exists before first use.

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

## RubyGems -- Off on Hot Entry Points

Loading RubyGems costs ~70ms per Ruby start (measured on the macOS system Ruby 2.6). Short-lived entry points that run on every `push`/`pull`/
`upreb`/`rug` (`scripts/git-command.rb`, `scripts/run-all.rb`) therefore use
`#!/usr/bin/env -S ruby --disable-gems` (`env -S` splits the arguments; works with macOS `env`), and
`call_utility` / `GitOverrides.command_for` start Ruby with `--disable-gems` too. Every other script
keeps `#!/usr/bin/env ruby`.

Rules for code that can run on those paths (everything reachable from `GitCommands`, `RunAll`,
`GitWorkspace`, `CollectionProcessor`, `GitProcessor`, `EnvVars`, `Core`, `Logging`):

- Use the standard library only. Default stdlib (`pathname`, `set`, `open3`, `json`, `yaml`, ...) loads
  fine; a **gem** (including bundled gems such as `rexml`, which Ruby 3.0+ no longer loads without
  RubyGems) does not. `utilities/plist.rb` requires `rexml/document`, so it (and anything that loads it,
  e.g. `capture-prefs.rb`, `PreferencesRestore`) must not be put behind `--disable-gems` on Ruby 3+.
- Do not `require 'rbconfig'` at the top of a file: RubyGems loads it for free, but under
  `--disable-gems` it is a real load (~30ms on the macOS system Ruby). Read the platform from the core constant `RUBY_PLATFORM`
  (`RUBY_PLATFORM.match?(/arm|aarch64/)`) and `require 'rbconfig'` lazily inside the one method that
  needs `RbConfig.ruby`.
- Check a new entry point with `/usr/bin/ruby --disable-gems -I scripts/utilities -e "require 'the_module'"`.

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
   config = Pathname("~/.config/file")
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

11. **Optional/CLI parameter used without a nil guard** → Fails confusingly downstream instead of failing fast (see § Parameter Validation)
    ```ruby
    # BAD - dir: nil silently reaches system() as an empty string
    def clone_repo(dir: nil)
      system('git', 'clone', dir.to_s)
    end
    # Good - fail fast with a clear message
    def clone_repo(dir: nil)
      raise ArgumentError, 'clone_repo: dir is required' if nil_or_empty?(dir)

      system('git', 'clone', dir.to_s)
    end
    ```
