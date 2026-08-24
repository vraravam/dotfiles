# Logging Conventions

> Cross-language logging rules applicable to both shell and Ruby scripts.

## Scope

**This file applies to**: All logging, output formatting, and error collection patterns across the repository, including:
- Logging function calls in shell scripts (`info`, `success`, `warn`, `error`, `debug`, `user_action`)
- Logging module usage in Ruby scripts (`Logging.info`, `Logging.success`, etc.)
- Deferred error/warning collection (`_record_error`, `record_warning`)
- Script infrastructure (`print_script_start`, `print_script_summary`, `section_header`)
- Color standards for paths, commands, components, counts, and booleans
- Message prefixes for Root Cause Analysis (`[script_name][section]`)
- Terminal output formatting (ANSI codes, indentation, padding)

**Related files**:
- [`script-depth-tracking.md`](./script-depth-tracking.md) - Auto-indentation based on nesting depth
- [`shell-scripting.md`](./shell-scripting.md) - Shell-specific logging implementation
- [`ruby-scripting.md`](./ruby-scripting.md) - Ruby-specific logging implementation

**Does NOT apply to**: Raw command output (git, brew, etc.), external tool stdout/stderr, or debugging output not using the logging infrastructure.

## Unified Color Standard

All logging messages across shell scripts and Ruby scripts follow this unified color classification for consistency.

### Color Classification Rules

1. **Paths/Files/Folders**: cyan + single quotes
   - File paths, directory paths, full app paths like `/Applications/App.app`
   - Shell: `info "Processing '$(cyan "${path}")'"`
   - Ruby: `info "Processing '#{path.cyan}'"`

2. **Action verbs** (in headers/labels): yellow
   - "Installing", "Updating", "Finding", "Processing"
   - Section header action verbs
   - Shell: `section_header "$(yellow 'Installing') dotfiles"`
   - Ruby: `section_header "#{'Installing'.yellow} dotfiles"`

3. **Labels/Keys in key-value pairs**: yellow + colon
   - "Branch:", "Folder:", "Dry run:", env var names as subjects
   - Shell: `info "$(yellow 'Branch:') '$(cyan "${branch}")'"`
   - Ruby: `info "#{'Branch:'.yellow} '#{branch.cyan}'"`

4. **Component/tool/app names** (non-paths): yellow
   - "homebrew", "antidote plugins", "KeyClu" (app name without path)
   - Shell: `section_header "$(yellow 'Updating') $(yellow 'homebrew')"`
   - Ruby: `section_header "#{'Updating'.yellow} #{'homebrew'.yellow}"`

5. **Commands/executable strings**: cyan + single quotes
   - Actual command strings like `'git status'`
   - Shell: `info "Running '$(cyan "git status")'"`
   - Ruby: `info "Running '#{cmd.cyan}'"`

6. **Domain/preference identifiers**: light_cyan
   - `com.apple.Finder`, `com.google.Chrome`
   - Shell: `debug "Processing domain: $(light_cyan "${domain}")"`
   - Ruby: `debug "Processing domain: #{domain.light_cyan}"`

7. **Numeric values**:
   - Success counts (in summaries): green
   - Error counts (in summaries): red
   - Neutral/informational counts: purple
   - Shell: `success "Created $(green "${count}") files"`
   - Ruby: `puts "Created: #{count.to_s.green}"`

8. **Boolean values**: orange
   - Shell: `info "$(yellow 'Dry run:') $(orange "${dry_run}")"`
   - Ruby: `info "#{'Dry run:'.yellow} #{dry_run.to_s.orange}"`

9. **Error messages/failed items**: red
   - Entire error messages can be red
   - Failed items in lists
   - Shell: `_record_error "$(red "Failed to process '$(cyan "${file}")'")"`
   - Ruby: `record_error("Failed to process '#{file.cyan}'".red)`

### Application Guidelines

- **Regular text**: No color decoration (white/default terminal color)
- **Consistency across languages**: Apply same rules in Shell and Ruby scripts
- **Single quotes for paths/commands**: Always single-quote paths and commands when coloring
- **No mixing**: Don't apply multiple colors to the same text element
- **Context matters**: Neutral counts get purple; success/error counts get green/red
- **Yellow-context rule**: When the main message text is already yellow (labels, action verbs), use purple for quoted special content (env vars, component names, script names) to create visual distinction

**Implementation**: Color methods are defined in `colorizable.rb` (shared Ruby module), `string_ext.rb` (String extension), `pathname_ext.rb` (Pathname extension), and `.shellrc` (shell functions).

## Deferred Error/Warning Collection

Both shell and Ruby scripts use deferred collection patterns:

### Shell
```zsh
_record_warning "$(red "Warning message")"
_record_error "$(red "Error message")"
print_script_summary "${start_time}"  # Prints collected warnings/errors
```

### Ruby
```ruby
Logging.record_warning("Warning message".red)
Logging.record_error("Error message".red)
Logging.print_script_summary(start_time)  # Prints collected warnings/errors
```

## Logging Functions

### Shell (from `.shellrc`)
- `success "message"` - Green checkmark + message
- `info "message"` - Blue info icon + message
- `warn "message"` - Yellow warning + message
- `error "message"` - Red error + message
- `debug "message"` - Cyan debug (only if DEBUG=true)
- `user_action "message"` - Magenta prompt for user

### Ruby (from `Logging` module)
- `Logging.success("message")` - Green checkmark + message
- `Logging.info("message")` - Blue info icon + message
- `Logging.warn("message")` - Yellow warning + message
- `Logging.error("message")` - Red error + message
- `Logging.debug("message")` - Cyan debug (only if EnvVars.debug?)
- `Logging.user_action("message")` - Magenta prompt for user

## Script Depth Tracking

See [`script-depth-tracking.md`](./script-depth-tracking.md) for complete details on `_DOTFILES_SCRIPT_DEPTH`.

Both shell and Ruby track script nesting depth for:
1. **Banner suppression**: Only outermost script prints start/summary
2. **Auto-indentation**: All logging auto-indents based on depth (2 spaces per level)

**Never manually prepend spaces to log messages** -- the depth counter handles indentation automatically.

### Indentation Formula

All logging functions use this formula:
- **Base indentation**: `(depth - 1) * 2` spaces
- **Subordinate indentation**: `(depth - 1 + level) * 2` spaces

Where:
- `depth` = `_DOTFILES_SCRIPT_DEPTH` (minimum 1)
- `level` = optional parameter to logging functions (default 0)

**Examples:**
```
depth=1 (outermost): base = 0 spaces, subordinate (level 1) = 2 spaces
depth=2 (nested):    base = 2 spaces, subordinate (level 1) = 4 spaces
depth=3 (deeper):    base = 4 spaces, subordinate (level 1) = 6 spaces
```

### Section Header Auto-Leveling

`section_header(text)` automatically derives its visual style from current depth:
- **Level calculation**: `level = max(depth - 1, 0)`
- **Style selection**: Uses `SECTION_STYLES[level]` (char/glyph/color)
- **Indentation**: Uses base indentation only (not subordinate)

**Visual hierarchy:**
```
Level 0 (depth 1): === ⏳ (light_blue)   # Top-level script sections
Level 1 (depth 2): --- 🔷 (cyan)         # Sub-operations
Level 2 (depth 3): ··· ▸ (yellow)        # Individual items
Level 3 (depth 4): ··· ▫ (purple)        # Operations within items
Level 4 (depth 5): ··· ▪ (dark_gray)     # Deeper nesting
```

**Result**: Nested operations have progressively distinct visual styles without caller needing to specify level.

### Section Header Formatting

Section headers use **left-aligned formatting** for better vertical scanability:

**Formula:**
```
left_padding = max(5 - indent_length, 1)
right_padding = max(terminal_width - indent_length - left_padding - 3 - header_visual_length - 10, 1)
```

**Layout:**
```
[indent][left_padding][glyph] [header_text] [right_padding]
         ^^^^^^^^^^^^^          ^^^^^^^^^^^
         Fixed 5 chars          Variable (depends on text length)
         (minus indent)
```

**Benefits:**
- Header text starts at consistent horizontal position (easier to scan vertically)
- Full terminal width is used (no 3/4 multiplier)
- ANSI color codes stripped before calculating padding (correct alignment)

**Terminal width detection:**
- **Ruby**: Uses `$stdout.winsize[1]` (real TTY), falls back to `EnvVars.columns` (COLUMNS env var or 80)
- **Shell**: Uses `${COLUMNS:-80}` (defaults to 80 when not set)
- **COLUMNS passing**: Pass `COLUMNS="${COLUMNS}"` when calling Ruby scripts (not exported, allows resize detection)
- **Cron**: Set `COLUMNS=80` in crontab for consistent width in cron jobs

### ANSI Code Stripping

Both Ruby and shell strip ANSI escape codes before:
1. **Length calculations**: Section header padding, macOS notifications
2. **Setting current_section**: Ensures error prefixes never contain escape codes

**Implementation:**
- **Ruby**: Regex `/\e\[[0-9;]*m/` in `_strip_ansi` helper
- **Shell**: Zsh parameter expansion `${(S)var//${_esc}\[[0-9;]##[a-zA-Z]/}` with `extendedglob`

**Why shell uses parameter expansion** (not sed/grep):
- No subshell fork (critical for ERR trap contexts where subshells can hide failures)
- Native zsh syntax, fast and reliable
- `_dotfiles_notify` reuses `_strip_ansi` to ensure macOS notifications never contain escape codes

**Where applied:**
- `section_header`: Strips color codes from header text before calculating visual length for padding
- `current_section=` setter (Ruby): Strips automatically so all error messages are clean
- `_dotfiles_notify` (shell): Strips before passing to osascript

## External Tool Output

External tools (`git`, `mise`, `sqlite3`, `keybase`, etc.) may print at column 0 (no indentation) depending on how they're invoked.

**Streaming output** (via `system()`):
- Used for operations that benefit from real-time progress (git push/pull/fetch)
- Output appears at column 0, intentionally unindented
- Example: `system('git', '-C', repo, 'push')`

**Captured output** (via `CommandUtils` or raw `Open3.capture3`):
- Used for operations where we want to suppress success output and only log on error
- Examples: `mise install` (only log if tools missing), `git fetch -q` (suppress unless error)

**Decision tree for choosing the right pattern**:

1. **Use `CommandUtils.query`** when you only need stdout on success:
   ```ruby
   # Returns stdout.strip on success, raises on failure
   version = CommandUtils.query('git', '--version')
   ```
   - Simplest pattern for read-only commands
   - Raises RuntimeError on failure (no need to check status)
   - Use when: Getting command output, failure is unexpected

2. **Use `CommandUtils.capture_output`** for direct command execution with error handling:
   ```ruby
   success = CommandUtils.capture_output('mise', '-C', dir, 'install') do |status, output_msg|
     Logging.warn("mise install failed in '#{dir.cyan}' (status: #{status.exitstatus})#{output_msg}")
   end
   ```
   - Executes command via `Open3.capture3` internally
   - Builds formatted output message (stdout/stderr sections with stderr colored red)
   - Yields `status` and formatted `output_msg` to block on failure only
   - Returns boolean (true on success, false on failure)
   - Use when: Running commands where failure is expected/recoverable

3. **Use `CommandUtils.check_status`** for pre-captured output (e.g., GitProcessor wrappers):
   ```ruby
   stdout, stderr, status = git.fetch_all
   success = CommandUtils.check_status(stdout, stderr, status) do |status, output_msg|
     Logging.record_warning("Fetch failed in '#{dir.cyan}' (status: #{status.exitstatus})#{output_msg}")
   end
   ```
   - Takes pre-captured `stdout, stderr, status` (e.g., from GitProcessor methods)
   - Builds same formatted output message as `capture_output`
   - Optional `noise_patterns: [patterns]` parameter filters stderr noise:
     ```ruby
     noise_patterns = ['Permission denied', 'No such file or directory']
     CommandUtils.check_status(stdout, stderr, status, noise_patterns: noise_patterns) { |st, msg| ... }
     ```
     - Removes lines matching any pattern in the array
     - Useful for commands like `find` that generate expected noise during traversal
     - Patterns visible at call site (not hidden in method implementation)
   - Eliminates duplicate error formatting code at call sites
   - Use when: Already have captured output (GitProcessor, custom capture logic)
   - **Pass `nil` for stdout parameter when**: stdout contains sensitive data (crontab), is large/verbose (directory lists), or represents success not failure (partial-success scenarios)

4. **Use raw `Open3.capture3`** only when you need BOTH stdout and stderr for processing:
   ```ruby
   stdout, stderr, status = Open3.capture3('antidote', 'bundle')
   # Need to process plugin list (stdout) AND check for errors (stderr)
   plugins = stdout.split("\n")
   if !status.success?
     # Custom error handling using both outputs
   end
   ```
   - Use when: Both outputs are needed for logic (not just error logging)
   - Examples: antidote bundle (need plugin list + errors), find with noise filtering (need results + filtered errors)
   - If you only need output for error logging, use `capture_output` or `check_status` instead

## Message Prefixes -- Script Name and Section for RCA

**All log messages must include script name and section context** to enable quick Root Cause Analysis (RCA) when errors occur.

### Format

`[script_name][section] Message`

### Where to Apply

1. **Deferred errors/warnings** (via `_record_error`/`record_error`):
   - Prefix is added automatically by `_record_error`/`_record_warning` functions
   - Shell: `_record_error "$(red "Failed to process file")"`
   - Ruby: `Logging.record_error("Failed to process file".red)`
   - Output: `[script_name][current_section] Failed to process file`

2. **Regular log messages** (when context aids debugging):
   - Add prefix manually for operations that may fail or need traceability
   - Shell: `warn "[${_SCRIPT_NAME}][${_current_section}] Retrying operation"`
   - Ruby: `warn "[#{_script_name}][#{@current_section}] Retrying operation"`

3. **High-level summary messages** (optional):
   - Section headers and final summaries typically omit the prefix (redundant)
   - Example: `success "Operation finished. Processed 10 domains."`

### Implementation

**Shell** (`.shellrc`):
- `_SCRIPT_NAME` - Set at script/function start via `_SCRIPT_NAME="${0:t}"`
- `_current_section` - Initialize to `'(init)'` in main(), auto-set by `section_header`, can be manually overridden
- `_record_error`/`_record_warning` - Automatically prefix messages, use `${_current_section:-unknown}` as fallback

**Ruby** (`logging.rb`):
- `_script_name` - Set via `Logging.run_script`
- `@current_section` - Initialize to `'(init)'` in `run_script`, auto-set by `section_header`, can be manually overridden
- `Logging.record_error`/`record_warning` - Automatically prefix messages, use `@current_section || 'unknown'` as fallback

**Three states of `current_section`:**
1. **Unset/nil** → `'unknown'` fallback (error case: variable never initialized)
2. **`'(init)'`** → Initial value (script started, before first section_header)
3. **Actual value** → Set by `section_header` auto-update or manual assignment

The `'unknown'` fallback catches bugs where `record_error`/`record_warning` are called before the variable is initialized. If you see `[script-name][unknown]` in logs, it means the script called error recording before setting up the variable.

### Section Tracking with `section_header`

**Both Ruby and shell `section_header` automatically update `current_section` progressively**, providing more specific context as execution descends through nested operations.

#### Auto-Update Behavior

`section_header(text)` automatically updates `current_section` unless manually overridden:
- Updates happen at **all nesting levels** (not just top-level)
- Each call updates to the new header text (progressively more specific)
- Stops updating once manually set via direct assignment
- ANSI color codes are automatically stripped before setting

**Progressive specificity example:**
```
1. Script starts:  '(init)'
2. First header:   'Processing repositories.yml'
3. Item header:    '[2 of 5] Resurrecting: ~/dev/content-studio'
4. Op header:      '[2 of 5] Resurrecting: ~/dev/content-studio'  (no update, keeps item)
```

**Result**: Error messages show the most specific context:
```
[resurrect-repositories][[2 of 5] Resurrecting: ~/dev/content-studio] Failed to fetch
```

#### Manual Override

**Manual assignment prevents all future auto-updates:**

**Shell:**
```zsh
_current_section='Install Xcode'           # Manual set
_current_section_manual=1                  # Flag prevents future updates
section_header "$(yellow 'Installing') Xcode Command Line Tools"
# Won't update because manual flag is set
# Errors will show: [fresh-install][Install Xcode] ...
```

**Ruby:**
```ruby
Logging.current_section = 'Clone repos'    # Manual set (flag set automatically)
Logging.section_header("#{'Cloning'.yellow} tracked repositories")
# Won't update because manual flag is set
# Errors will show: [resurrect-repositories][Clone repos] ...
```

**Implementation details:**
- **Ruby**: `current_section=` setter automatically sets `@current_section_manual = true`
- **Shell**: Manual assignments must set `_current_section_manual=1` explicitly
- `section_header` checks the flag and skips update when `true`/`1`

### Examples

```zsh
# Shell - deferred error (automatic prefix)
_current_section='homebrew'
_record_error "$(red "Failed to update homebrew")"
# Output: [software-updates-cron][homebrew] Failed to update homebrew

# Shell - inline warning with manual prefix (for critical operations)
warn "[${_SCRIPT_NAME}][${_current_section}] $(yellow 'Cache miss, regenerating')"
# Output: [script-name][section] Cache miss, regenerating
```

```ruby
# Ruby - deferred error (automatic prefix)
@current_section = 'export'
Logging.record_error("Failed to read domain '#{domain.cyan}'".red)
# Output: [capture-prefs][export] Failed to read domain 'com.apple.Finder'

# Ruby - inline warning with manual prefix (for critical operations)
warn "[#{_script_name}][#{@current_section}] Retrying after network timeout"
# Output: [script-name][section] Retrying after network timeout
```

### Why This Matters

When reviewing logs (especially cron logs or multi-script runs):
- **Quick identification**: Know exactly which script/section failed
- **Nested context**: Track failures through call chains (script A → script B → failure)
- **Parallel debugging**: Distinguish concurrent script runs
- **Historical analysis**: Grep logs by `[script][section]` pattern
