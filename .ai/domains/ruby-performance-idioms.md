---
applyTo: "**/*.rb"
name: dotfiles-ruby-performance-idioms
description: Use when writing or optimizing Ruby in this dotfiles repo for speed or idiom -- memoization, frozen constants, variable extraction vs inlining, loop-invariant hoisting, string operations, Set vs Array, enumerable chains, early exits, trailing conditionals, and avoiding mutating `!` methods.
---

# Ruby Performance and Idioms

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules when writing hot-path Ruby, optimizing existing code, or choosing between equivalent idioms.

**Related files**:
- [`ruby-scripting.md`](./ruby-scripting.md) - Core rules (dual-mode, parameters, exit points, version compatibility) -- read this first
- [`ruby-infrastructure.md`](./ruby-infrastructure.md) - Cost of `require` on the per-command path

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
GitProcessor.new(
  dir: Pathname.new(ENV.fetch('PERSONAL_PROFILES_DIR')).expand_path.join('Chrome')
) { |git| git.pull }

# Good -- keep variable for complex multi-step construction
chrome_profiles = Pathname.new(ENV.fetch('PERSONAL_PROFILES_DIR')).expand_path.join('Chrome')
GitProcessor.new(dir: chrome_profiles) { |git| git.pull }
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

# BAD -- GitProcessor.new(dir: git_dir) constructed twice
def check_size_limit(limit_gb: 2)
  size_mb = GitProcessor.new(dir: git_dir).pack_size_mb
  size_human = GitProcessor.new(dir: git_dir).pack_size_human
end

# Good -- build the processor once
def check_size_limit(limit_gb: 2)
  git = GitProcessor.new(dir: git_dir)
  size_mb = git.pack_size_mb
  size_human = git.pack_size_human
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

## String Operations -- Performance-Aware Patterns

Ruby provides multiple methods for string manipulation with significant performance differences. Choose the right method based on the operation type.

### `String#tr` vs `String#gsub` for Single-Character Replacement

**Use `String#tr` for single-character replacements (3x faster than `gsub`):**

```ruby
# BAD -- gsub for single-character replacement
alias_name = relative.gsub(File::SEPARATOR, '-')
cleaned = str.gsub('/', '_')

# Good -- tr for single-character replacement (3x faster)
alias_name = relative.tr(File::SEPARATOR, '-')
cleaned = str.tr('/', '_')
```

**Why `tr` is faster:**
- Optimized for character-to-character translation
- No regex compilation overhead
- Direct character mapping (not pattern matching)

**When to use `tr`:**
- Replacing single characters: `'/' -> '-'`, `' ' -> '_'`
- Character class replacement: `tr('a-z', 'A-Z')` (lowercase to uppercase)
- Character deletion: `tr('0-9', '')` (remove all digits)

**When NOT to use `tr`:**
- Multi-character replacements: `gsub('--', '-')` (can't use `tr`)
- Pattern-based replacement: `gsub(/\s+/, ' ')` (regex needed)
- Context-dependent replacement: `gsub(/foo/, 'bar')` (specific substring)

**Benchmark data** (from fast-ruby repository):
```
String#tr:  9.1M i/s
String#gsub: 3.0M i/s - 3.01x slower
```

### `String#delete` vs `String#tr` vs `String#gsub` for Character Removal

**Use `String#delete` for removing characters (4x faster than `gsub`):**

```ruby
# BAD -- gsub for character removal
cleaned = str.gsub('/', '')
cleaned = str.gsub(/[^a-z]/, '')

# Good -- delete for character removal (4x faster than gsub)
cleaned = str.delete('/')
cleaned = str.delete('^a-z')  # Keep only a-z, delete everything else

# Also good -- tr for removal (faster than gsub, but delete is better)
cleaned = str.tr('/', '')
```

**Why `delete` is fastest:**
- Purpose-built for character removal
- No replacement string allocation
- Direct character filtering

**Benchmark data:**
```
String#delete (const): 13.2M i/s
String#delete:         11.6M i/s - 1.13x slower
String#tr:              9.9M i/s - 1.34x slower
String#gsub:            3.1M i/s - 4.26x slower
```

**Pattern**: Use frozen constant strings for common character sets:
```ruby
# Good -- frozen constant (13.2M i/s)
CHARS_TO_REMOVE = '/\\'.freeze
cleaned = str.delete(CHARS_TO_REMOVE)

# Acceptable -- inline string (11.6M i/s)
cleaned = str.delete('/\\')
```

### `String#sub` vs `String#gsub` for Single Replacement

**Use `String#sub` when replacing only the first occurrence (2x faster):**

```ruby
# BAD -- gsub when you only need first match
normalized = url.gsub(/\.git$/, '')
name = file.gsub('.rb', '')

# Good -- sub for single replacement (2x faster)
normalized = url.sub(/\.git$/, '')
name = file.sub('.rb', '')
```

**Why `sub` is faster:**
- Stops after first match (no scanning rest of string)
- Less work = faster execution

**When to use `sub`:**
- Removing prefix/suffix: `sub(/^prefix/, '')`, `sub(/suffix$/, '')`
- First occurrence only: `sub('old', 'new')`
- Single pattern match: `sub(/pattern/, 'replacement')`

**When to use `gsub`:**
- All occurrences: `gsub('//', '/')` (collapse multiple slashes)
- Pattern appears multiple times: `gsub(/\s+/, ' ')` (normalize whitespace)

**Benchmark data:**
```
String#sub:  4.7M i/s
String#gsub: 2.3M i/s - 2.00x slower
```

### Modern Ruby Alternatives: `delete_prefix` / `delete_suffix`

**Ruby 2.5+ provides specialized methods for prefix/suffix removal (3x faster than `sub`):**

```ruby
# Old (Ruby 2.4 and earlier)
normalized = url.sub(/^https:\/\//, '')
basename = file.sub(/\.rb$/, '')

# Modern (Ruby 2.5+)
normalized = url.delete_prefix('https://')
basename = file.delete_suffix('.rb')
```

**Benefits:**
- **3x faster** than `sub` with regex
- **More readable** - intent is clearer
- **No regex compilation** - direct string comparison

**When to use:**
- Removing known prefix: `delete_prefix('prefix')`
- Removing known suffix: `delete_suffix('.ext')`
- Static string removal (not pattern-based)

**When NOT to use:**
- Pattern-based removal: `sub(/prefix-\d+/, '')` still needs `sub`
- Ruby 2.4 or earlier compatibility required
- Multiple possible prefixes: `sub(/^(http|https):\/\//, '')` needs regex

**Benchmark data:**
```
String#delete_prefix: 14.9M i/s
String#delete_suffix: 14.9M i/s
String#sub:            4.8M i/s - 3.11x slower
```

### String Method Selection Flowchart

```
Need to modify string?
├─ Remove characters?
│  ├─ Prefix/suffix? → delete_prefix / delete_suffix (3x faster than sub)
│  └─ Any position? → delete (4x faster than gsub)
├─ Replace characters?
│  ├─ Single character? → tr (3x faster than gsub)
│  ├─ First occurrence only? → sub (2x faster than gsub)
│  └─ All occurrences? → gsub (no alternative)
└─ Pattern-based? → gsub with regex (no alternative)
```

### Scan Rule: Identify String Optimization Opportunities

When editing Ruby files, check for:

1. **`gsub` with single character**: `gsub('/', '-')` → Use `tr('/', '-')`
2. **`gsub` with empty replacement**: `gsub('/', '')` → Use `delete('/')`
3. **`gsub` for single match**: `gsub(/\.git$/, '')` → Use `sub(/\.git$/, '')`
4. **`sub` for prefix/suffix**: `sub(/^prefix/, '')` → Use `delete_prefix('prefix')`

**Search patterns:**
```bash
# Find gsub with single-character args
grep -rn "\.gsub('[^']\+', '[^']\+'" scripts/ --include="*.rb"

# Find gsub with empty replacement
grep -rn "\.gsub.*''" scripts/ --include="*.rb"

# Find sub with anchored regex
grep -rn "\.sub(/\^.*\\\$/, '')" scripts/ --include="*.rb"
```

**Example from this codebase:**
```ruby
# Before (git_workspace.rb:332)
alias_name = relative.gsub(File::SEPARATOR, '-')

# After
alias_name = relative.tr(File::SEPARATOR, '-')  # 3x faster
```

### When NOT to Optimize

**Don't optimize when:**
- String operation is NOT in a loop or hot path
- Method is called < 100 times per script execution
- Readability would suffer significantly
- Premature optimization (no profiling data)

**Example - optimization NOT worth it:**
```ruby
# Called once per script execution - optimization has zero measurable impact
script_name = ARGV[0].gsub('.rb', '')  # OK - not hot path
```

**Example - optimization IS worth it:**
```ruby
# Called once per repository (100+ repos) - 3x speedup = measurable gain
repos.each do |dir|
  alias_name = dir.tr(File::SEPARATOR, '-')  # 3x faster than gsub
end
```

## Loop-Invariant Hoisting -- Move Unchanging Work Outside Loops

**If a computation's result does not change across loop iterations, compute it once before the loop, not on every iteration.**

This is distinct from [Memoization](#memoization) (which caches a result across multiple *method calls* using `@_var ||=`) and from [Hot Path Optimization -- Frozen Constants](#hot-path-optimization----frozen-constants) (which hoists *static* literals to the class/module level once for the process lifetime). Loop-invariant hoisting is about a single method call: work that depends only on values already known before the loop starts must not be repeated inside it.

### Pattern: Hoist Regexp Compilation

`Regexp.new(str)` and `/#{str}/` (interpolated regex literals) compile a new `Regexp` object every time they execute. A regex literal with **no** interpolation is compiled once by the Ruby VM and reused automatically -- but an **interpolated** pattern (`/#{filter}/i` or `Regexp.new(filter)`) is recompiled on every evaluation, since the VM cannot know the interpolated value is unchanged.

```ruby
# BAD -- recompiles the same Regexp on every element of repos.select
def _apply_filter(repos, filter)
  return repos if nil_or_empty?(filter)

  repos.select { |repo_item| repo_item.match?(/#{filter}/i) }
end

# Good -- compiled once, reused for every element
def _apply_filter(repos, filter)
  return repos if nil_or_empty?(filter)

  filter_re = Regexp.new(filter, Regexp::IGNORECASE)
  repos.select { |repo_item| repo_item.match?(filter_re) }
end
```

`scripts/utilities/collection_processor.rb` already demonstrates this correctly (regex compiled once before `Find.find`'s traversal block). `scripts/resurrect-repositories.rb`'s `_apply_filter` was fixed to match this pattern.

### Pattern: Hoist File I/O

Reading the same file inside a loop that iterates over *other* items (not the file itself) re-reads unchanged content from disk on every iteration.

```ruby
# BAD -- re-reads the same two pattern files from disk once per browser profile
def run
  browser_profiles.each do |browser_name, profile_dir|
    _vacuum_browser_profile_dir(browser_name, profile_dir, dry_run: dry_run)
  end
end

def _vacuum_browser_profile_dir(browser_name, profile_dir, dry_run:)
  file_patterns = _read_pattern_file(FILES_PATTERN_PATH)  # same file, every call
  dir_patterns = _read_pattern_file(DIRS_PATTERN_PATH)    # same file, every call
  # ...
end

# Good -- read once, pass down to each iteration
def run
  file_patterns = _read_pattern_file(FILES_PATTERN_PATH)
  dir_patterns = _read_pattern_file(DIRS_PATTERN_PATH)

  browser_profiles.each do |browser_name, profile_dir|
    _vacuum_browser_profile_dir(browser_name, profile_dir, file_patterns: file_patterns, dir_patterns: dir_patterns, dry_run: dry_run)
  end
end
```

### Pattern: Hoist Derived-Value Computation

A value derived from a loop's own invariant inputs (not the current item) must not be recomputed per-item.

```ruby
# BAD -- search_roots depends only on 'dirs' (invariant for the whole call), but is
# rebuilt on every iteration of the inner while loop, for every repo in repos.reject
repos.reject do |repo|
  parent = File.dirname(repo)
  while parent != Core::ROOT.to_s
    search_roots = Array(dirs).map { |d| File.expand_path(d.to_s) }
    break if search_roots.include?(parent)
    # ...
  end
end

# Good -- computed once, before the outer repos.reject even starts
search_roots = Set.new(Array(dirs).map { |d| File.expand_path(d.to_s) })
repos.reject do |repo|
  parent = File.dirname(repo)
  while parent != Core::ROOT.to_s
    break if search_roots.include?(parent)
    # ...
  end
end
```

(This example also applies [Set vs Array -- Membership Checks](#set-vs-array----membership-checks) below.)

### Scan Rule

When reviewing a method containing a loop (`each`, `while`, `map`, `select`, nested iteration, etc.), check every line inside the loop body:
1. Does this line's result depend only on values that are the same across all iterations (method parameters, ivars, constants -- not the loop variable)?
2. If yes, move it above the loop.
3. Does it involve `Regexp.new`/interpolated regex, `File.read`/`Core.read_lines_utf8`, or a `.map`/`.select` building a lookup collection? These are the highest-value hoisting targets since they involve real compilation/I/O/allocation cost, not just cheap arithmetic.

## Set vs Array -- Membership Checks

**`Array#include?` is O(n) (linear scan); `Set#include?` is O(1) average (hash lookup).** When a collection is checked repeatedly with `.include?` -- especially inside a loop, or built once and queried many times -- use `Set` instead of `Array`.

```ruby
# BAD -- Array#include? scans the whole array on every call
require 'set' # not required if only using Array

search_roots = Array(dirs).map { |d| File.expand_path(d.to_s) }
repos.each do |repo|
  next if search_roots.include?(File.dirname(repo)) # O(n) per check
end

# Good -- Set#include? is O(1) average
require 'set'

search_roots = Set.new(Array(dirs).map { |d| File.expand_path(d.to_s) })
repos.each do |repo|
  next if search_roots.include?(File.dirname(repo)) # O(1) per check
end
```

### When to Convert

Convert an `Array` to a `Set` when **both** are true:
- The collection is checked with `.include?` **more than once** (a single check has no benefit -- `Set.new` itself is an O(n) allocation, so converting for a single lookup is strictly worse).
- The collection has enough elements, or is checked often enough, that the O(n) vs O(1) difference is measurable (a handful of elements checked a handful of times is not worth the conversion -- see "When NOT to Convert" below).

### When NOT to Convert

Do NOT convert to `Set` when:
- The array is small (roughly under 10-20 elements) and checked infrequently (a few times per script run) -- e.g. a frozen constant like `MacOS::LOGIN_ITEM_APPS` checked once or twice. The `Set.new` allocation cost and the extra `require 'set'` dependency aren't worth it for a scan that's already effectively instant.
- Order matters and is relied upon elsewhere (`Set` does not guarantee insertion order the way `Array` does, though Ruby's `Set` happens to preserve it in practice -- don't rely on this).
- The collection is only ever used with `.each`/`.map`, never `.include?`/`.member?` -- `Set` has no advantage there.

### `require 'set'`

`Set` is part of Ruby's standard library but must be explicitly required: `require 'set'` (not `require_relative`). Add it to the stdlib group of requires (see [`ruby-infrastructure.md`](./ruby-infrastructure.md) § Sorting and grouping `require` statements), sorted alphabetically alongside `pathname`, `open3`, etc.

## Enumerable Chains -- Avoid Intermediate Collection Allocation

**Chaining `Enumerable` methods where the first method builds a full intermediate array/collection, only for the second method to immediately reduce it to a boolean/count/single-element, wastes an allocation the direct method avoids entirely.**

| Wasteful (builds an intermediate collection) | Direct (no intermediate allocation) |
|---|---|
| `arr.select { \|x\| cond }.any?` | `arr.any? { \|x\| cond }` |
| `arr.select { \|x\| cond }.count` / `.size` / `.length` | `arr.count { \|x\| cond }` |
| `arr.select { \|x\| cond }.empty?` | `arr.none? { \|x\| cond }` |
| `arr.select { \|x\| cond }.first` | `arr.find { \|x\| cond }` (aka `.detect`) |
| `arr.reject { \|x\| cond }.empty?` | `arr.none? { \|x\| !cond }` (or restate `cond` to fit `.all?`) |
| `arr.map { \|x\| transform }.first` | `arr.find { \|x\| ... }` when really searching, not transforming every element |
| `arr.sort.first` / `arr.sort_by { \|x\| key }.first` | `arr.min` / `arr.min_by { \|x\| key }` |
| `arr.sort.last` / `arr.sort_by { \|x\| key }.last` | `arr.max` / `arr.max_by { \|x\| key }` |

```ruby
# BAD -- allocates a full filtered array just to check if it's non-empty
if repos.select { |r| r.active? }.any?
  # ...
end

# Good -- any? short-circuits on the first match, no array allocated
if repos.any?(&:active?)
  # ...
end

# BAD -- sort is O(n log n) and allocates a fully sorted array, just to grab one element
oldest = commits.sort_by { |c| c.timestamp }.first
newest = commits.sort_by { |c| c.timestamp }.last

# Good -- min_by/max_by are O(n), no intermediate array
oldest = commits.min_by { |c| c.timestamp }
newest = commits.max_by { |c| c.timestamp }
```

### Why This Matters

- `.select`/`.reject`/`.sort`/`.sort_by` allocate a brand-new `Array` holding (in the worst case) every element of the original collection.
- `.any?`/`.all?`/`.none?`/`.count`/`.find` iterate the collection directly and can **short-circuit** (`.any?`/`.find` stop at the first match; `.none?`/`.all?` stop at the first counter-example) -- `.select` cannot short-circuit because it must produce the complete result set.
- `.min`/`.max`/`.min_by`/`.max_by` are a single O(n) pass; `.sort`/`.sort_by` are O(n log n) and must fully order every element even though only one (the first or last) is kept.

### When NOT to Apply

- If the intermediate collection from `.select`/`.sort` is **also used elsewhere** (not immediately discarded), keep the chain as-is -- there is no waste since the collection isn't thrown away.
- If the block passed to `.select`/`.sort_by` is itself very cheap and the collection is tiny (a handful of elements, called once), the difference is not worth a less-obvious refactor. Prioritize clarity for one-off, small-N code.

### Scan Rule

Search for `.select`/`.reject`/`.sort`/`.sort_by` immediately followed by `.any?`, `.all?`, `.none?`, `.count`, `.size`, `.length`, `.empty?`, `.first`, or `.last` in the same expression or on the very next line where the intermediate value has no other name/use. Rewrite using the direct combinator from the table above.

## Early-Exit Before Expensive Computation

**When a method does expensive work that is conditionally discarded by a check further down the call chain, move the cheap check to the top of the method so the expensive work is skipped entirely when it isn't needed.**

```ruby
# BAD -- log_level detection (multi-branch regex case/when) and ANSI-stripping (regex
# gsub) run on every single log call, even though _write_to_log_file immediately
# discards both and returns if LOG_FILE isn't set (the common case -- it's opt-in)
def emit(message, level:)
  puts "#{_subordinate_indent(level)}#{message}"

  log_level = case message
              when /\*\*SUCCESS\*\*/ then :success
              when /\*\*WARN\*\*/ then :warn
              # ... more branches ...
              else :info
              end

  plain_message = _strip_ansi(message)
  _write_to_log_file(log_level, plain_message)
end

def _write_to_log_file(level, message)
  log_file = ENV.fetch('LOG_FILE', nil)
  return if nil_or_empty?(log_file) # discards all the work above, most of the time
  # ...
end

# Good -- cheap ENV check moved to the top; expensive work only runs when it will
# actually be used
def emit(message, level:)
  puts "#{_subordinate_indent(level)}#{message}"

  return if nil_or_empty?(ENV.fetch('LOG_FILE', nil))

  log_level = case message
              when /\*\*SUCCESS\*\*/ then :success
              # ...
              end
  plain_message = _strip_ansi(message)
  _write_to_log_file(log_level, plain_message)
end
```

### Why Not Just Memoize?

This is not a memoization opportunity (see [Memoization](#memoization) § When NOT to Memoize) -- the check itself (`ENV.fetch('LOG_FILE', nil)`) is already cheap (a single hash lookup). The point is not to avoid re-checking the condition; it's to avoid doing the *expensive* work (regex matching, string building, I/O) that the condition guards, by checking the cheap condition **first** instead of last.

### Scan Rule

When a method does non-trivial work (regex matching across multiple branches, string transformation, file I/O, subprocess calls) unconditionally, then calls another method that immediately discards the result based on a cheap, already-known-early condition (an ENV var, a boolean flag, an early state check) -- move that cheap condition to the top of the calling method as an early `return`/`next`.
