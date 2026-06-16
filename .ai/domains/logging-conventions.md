# Logging Conventions

> Cross-language logging rules applicable to both shell and Ruby scripts.

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

**Implementation**: Color methods are defined in `string.rb` (Ruby) and `.shellrc` (shell functions).

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

## External Tool Output

External tools (`git`, `mise`, `sqlite3`, `keybase`, etc.) invoked via `system()` or `Open3.capture3()` print at column 0 (no indentation). This is intentional -- wrapping their output would add complexity for minimal UX benefit. Tool output remains visually distinct from our structured logging.

**Examples of unindented tool output**:
- Shell: `system('git', '-C', repo, 'status')`
- Ruby: `system('mise', 'install')`, `Open3.capture3('git', 'log')`

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
- `_SCRIPT_NAME` - Set at script/function start
- `_current_section` - Update before each major section
- `_record_error`/`_record_warning` - Automatically prefix messages

**Ruby** (`logging.rb`):
- `_script_name` - Set via `Logging` module
- `@current_section` - Update before each major section
- `Logging.record_error`/`record_warning` - Automatically prefix messages

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
