---
applyTo: "**/*.rb"
name: dotfiles-ruby-shell-git-io
description: Use when Ruby code in this dotfiles repo shells out (`system`, `Open3`, backticks, escaping), calls GitProcessor, reads files with explicit UTF-8 encoding (Core.read_lines_utf8 / each_line_utf8), or uses the `nil_or_empty?` helper.
---

# Ruby Shell, Git and File I/O Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules when Ruby code runs external commands, drives git through `GitProcessor`, or reads files.

**Related files**:
- [`ruby-scripting.md`](./ruby-scripting.md) - Core rules (dual-mode, parameters, exit points, version compatibility) -- read this first
- [`ruby-infrastructure.md`](./ruby-infrastructure.md) - Logging, EnvVars, CliParser, requires
- [`character-encoding.md`](./character-encoding.md) - ASCII-only source requirement

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

### Interactive Execution with `CommandUtils.run_interactive`

For commands whose output the user should watch live (installers, `git` with
progress, nested Ruby scripts), use `CommandUtils.run_interactive` instead of a
bare `system`. It streams stdout/stderr to the terminal, returns a boolean, and
accepts an optional block that runs only on failure (the place to record a
warning/error). Like `system`, it accepts a leading env hash:

```ruby
# BAD -- bare system with no failure handling
system(RbConfig.ruby, script.to_s, '-s')

# Good -- boolean result plus a failure hook
CommandUtils.run_interactive({ 'COLUMNS' => EnvVars.columns.to_s }, RbConfig.ruby, script.to_s, '-s') do
  Logging.record_warning("'#{script.to_s.cyan}' failed")
end
```

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
- Homebrew Ruby (if installed) may be in `${PATH}` and used by shebangs
- `RbConfig.ruby` returns the path to the **currently running** interpreter
- Child script uses same version/environment as parent (consistent behavior)

## GitProcessor Usage Patterns

`GitProcessor` (in `utilities/git_processor.rb`) provides a consistent API for
all git operations. It handles dry-run mode, error reporting, and directory
context automatically.

### Block Form (Default) vs Instance Form (Exception)

**Rule: whenever you create a `GitProcessor`, use the block form as much as possible.**
A block scopes the object to the code that needs it: the instance cannot leak into
unrelated code, its lifetime ends when the block does (so it becomes garbage-collectable
immediately rather than whenever the enclosing method/script ends), and every git
operation on one repo is visibly grouped in one place. Prefer it even for a single call.

```ruby
# Good -- block form, multiple operations
GitProcessor.new(dir: repo_dir) do |git|
  git.stage_all
  git.smart_commit
  git.push(branch: 'main')
end

# Good -- block form, localized side effect
GitProcessor.new(dir: EnvVars::PERSONAL_PROFILES_DIR) do |git|
  old_backups.each { |f| git.rm_cached(f, quiet: true) }
end

# Good -- block form, even for a single call
GitProcessor.new(dir: folder_pn) { |git| git.delete_tag('twilight') }

# Good -- rescue outside the block
GitProcessor.new(dir: repo_dir) do |git|
  rel_path = relative_path ? git.relative_path(relative_path) : '.'
  git.add(rel_path)
  git.smart_commit
end
rescue RuntimeError => e
  Logging.warn "Skipping update -- #{e.message}"
  false
```

**`GitProcessor.new(...) { }` returns the new instance, NOT the block's value** (the block
runs inside `initialize`). When you need a result outside the block, assign it to a local
declared before the block:

```ruby
status = nil
GitProcessor.new(dir: folder_pn) { |git| _out, _err, status = git.pull }
log_result(status)
```

**Use the instance form (`git = GitProcessor.new(dir: ...)`) only when the block form
would be clearly worse**, i.e. when:
- The same instance must be shared across separate methods or long, branching control
  flow that cannot reasonably be nested in one block
- The block form would force awkward result-capture for several values

Never keep an instance in an instance variable or constant "to reuse it": create a
scoped one per unit of work (`GitProcessor` is cheap -- it only stores `dir`/`dry_run`).

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

## UTF-8 File Reading

**CRITICAL: Always specify UTF-8 encoding when reading text files.**

`spec/utf8_file_reads_spec.rb` fails the build when any file under `scripts/` reads a file without an
explicit encoding (`.read`, `.readlines`, `File.read/foreach`, `YAML.load_file`, ... on a line that
does not name `encoding:`), so new code cannot regress this.

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
env -i HOME="${HOME}" USER="${USER}" /usr/bin/ruby path/to/script.rb
```

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
