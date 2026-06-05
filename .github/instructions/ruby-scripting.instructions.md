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
- Endless range `(1..)` — use `(1..Float::INFINITY)` or avoid
- Pattern matching (`case x in`) — Ruby 3.0+
- Numbered block parameters (`_1`) — Ruby 2.7+

## Requires

Only `require` what you directly use. Do not transitively pre-load:

```ruby
# BAD in logging.rb — hash_ext is not used here, push to caller
require 'hash_ext'

# Good — only require what this file uses
require 'logging'
```

### `require` vs `require_relative`

Never use `require_relative` outside of `$DOTFILES_DIR/scripts/utilities/`.
Use plain `require` everywhere else — it works because `RUBYLIB` is set by
`.shellrc` to include the utilities directory at runtime:

```ruby
# BAD — require_relative is fragile outside utilities/; breaks when the script
# is invoked from a different working directory or via a symlink
require_relative '../scripts/utilities/logging'

# Good — RUBYLIB includes utilities/, so bare require always works
require 'logging'
require 'cli_parser'
```

Exception: scripts inside `$DOTFILES_DIR/scripts/utilities/` **must** use
`require_relative` for sibling files in the same directory, and **must not** use
`require_relative` for anything else. Use plain `require` for stdlib and gems
even inside `utilities/`:

```ruby
# Inside utilities/cli_parser.rb — Good
require 'optparse'           # stdlib — plain require
require_relative 'logging'   # sibling script — require_relative

# Inside utilities/logging.rb — BAD
require_relative 'optparse'  # optparse is stdlib, not a sibling script
```

This keeps `require_relative` paths within `utilities/` as an explicit,
auditable list of intra-module dependencies. A `require_relative` path pointing
outside `utilities/` is always wrong — it would be fragile when the script is
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
`.shellrc` is already sourced, so `RUBYLIB` is always set — no `$LOAD_PATH`
manipulation needed.

### Sorting and grouping `require` statements

Sort `require` statements alphabetically within each group. Keep two groups in
order: stdlib/gem `require` first, then `require_relative` — each group sorted
independently. A blank line separates the two groups when both are present.

A blank line must also separate the last `require`/`require_relative` line from
the first `include` line:

```ruby
# BAD — unsorted requires; no blank line before include
require 'logging'
require 'cli_parser'
require 'fileutils'
include Logging

# Good — sorted within group; blank line before include
require 'cli_parser'
require 'fileutils'
require 'logging'

include Logging

# Good — stdlib group then require_relative group, each sorted; blank line before include
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
# Good — single quotes for static strings
sep = '------'
raise 'File not found'
Logging.info 'Already installed — skipping.'

# Good — double quotes when interpolating
Logging.info "Processing #{repo_name}"
msg = "Done: #{count} files"

# BAD — double quotes on strings with no interpolation (unnecessary)
sep = "------"
raise "File not found"
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

# Custom nil guard — NEVER replace with .empty?
return if nil_or_empty?(value)

# Cross-platform path separator
File::SEPARATOR             # not hardcoded "/"

# Hash class extensions (from hash_ext.rb)
hash.deep_sort              # recursive sort by keys

# String color extensions — see ## String Colors for the full convention table
'text'.blue
'path/to/file'.cyan         # HOME->tilde substitution happens inside color methods
```

## String Colors

Color methods are defined on `String` in `utilities/string.rb`. They:
- Wrap the string in ANSI escape codes (no-op when stdout is not a TTY)
- Automatically substitute `$HOME` with `~` in any path passed to them

**Never** call `replace_home_path_with_tilde` before passing a path to a color
method — the substitution happens inside. Only call it explicitly for bare
`puts`/`print` call sites that display paths without any color method.

### Available methods

| Method | ANSI | Typical use |
|---|---|---|
| `.red` | normal red | `'Usage'` label (auto via `CliParser`); error messages; failure counts |
| `.light_red` | bright red | `'**WARN**'` label (auto via `Logging.warn`) |
| `.green` | normal green | `'**SUCCESS**'` label (auto); success/positive counts; yes-option in prompts |
| `.light_green` | bright green | — (available; no fixed convention) |
| `.orange` | normal orange | — (available; no fixed convention) |
| `.yellow` | bright yellow | Argument placeholders in usage (`'<folder>'.yellow`); key names in key-value output; summary sub-headers |
| `.blue` | normal blue | Verbose/debug-only supplementary output |
| `.light_blue` | bright blue | Timestamps and durations (used internally by `Logging`) |
| `.purple` | normal purple | `opts.separator` section headings in usage blocks (`'Options:'.purple`) |
| `.light_purple` | bright purple | `'**DEBUG**'` label (auto via `Logging.debug`) |
| `.cyan` | normal cyan | File/folder paths; script name in banner (auto via `CliParser`) |
| `.light_cyan` | bright cyan | — (available; no fixed convention) |
| `.dark_gray` | dark gray | — (available; no fixed convention) |
| `.light_gray` | light gray | — (available; no fixed convention) |
| `.white` | bright white | — (available; no fixed convention) |
| `.black` | black | — (available; no fixed convention) |

### Conventions

```ruby
# Usage block — section labels purple, placeholders yellow, script example cyan
opts.separator 'Arguments:'.purple
opts.separator "  #{'<folder>'.yellow}  Target folder to process"
opts.separator "  eg: #{File.basename(__FILE__).cyan} /path/to/folder"

# Paths in log messages — color method handles tilde substitution
Logging.info "Processing '#{folder.cyan}'"
Logging.warn "Skipping '#{path.cyan}': already exists"

# Counts in summary output — green for good, red for bad
puts "  Processed: #{count.to_s.green}"
puts "  Errors:    #{errors.positive? ? errors.to_s.red : errors}"

# Sub-headers inside a summary
Logging.info 'Summary'.yellow
```

## Module / Class Structure

```ruby
module MyModule
  # Public API — no prefix, no private declaration needed for simple modules
  def self.public_method(arg)
    _private_helper(arg)
  end

  # Private helpers — prefix with _ OR use private
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

  def internal_method; end
end
```

## Option Parsing — Use `CliParser`

Always use `CliParser.parse` (from `utilities/cli_parser.rb`) for all CLI
option parsing — never raw `OptionParser` or manual `ARGV` shifting.
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
- Do NOT add `-h`/`--help` manually — `CliParser.parse` adds it automatically.

### Usage block structure

The body of `CliParser.parse` follows a fixed layout:

```ruby
parser = CliParser.parse('<old> <new> [options]') do |opts|
  # 1. One-line description of what the script does (no label)
  opts.separator 'Renames all files ending with <old> suffix to <new>.'
  opts.separator ''

  # 2. Arguments section — positional args only
  opts.separator 'Arguments:'.purple
  opts.separator "  #{'<old>'.yellow}  Original suffix to remove"
  opts.separator "  #{'<new>'.yellow}  Replacement suffix to add"
  opts.separator ''

  # 3. Options section — flags/switches only (omit if no flags)
  opts.separator 'Options:'.purple
  opts.on('-r', '--recursive', 'Recurse into subdirectories') { options[:recursive] = true }
  opts.separator ''

  # 4. Example line — always last, uses File.basename(__FILE__).cyan
  opts.separator "  eg: #{File.basename(__FILE__).cyan} -compressed ''"
end
```

Rules for the usage block:
- **Description first** — a plain `opts.separator` sentence before any labelled
  section. Omit if `CliParser.parse`'s banner string is already self-explanatory.
- **`Arguments:`.purple** — list every positional arg with `'<name>'.yellow` and
  a short description. Omit section entirely if the script takes no positional args.
- **`Options:`.purple** — list every flag with `opts.on`. Omit section entirely if
  there are no flags (do not emit an empty `'Options:'.purple` heading).
- **`eg:` line last** — always use `File.basename(__FILE__).cyan` for the script
  name so the example stays correct if the file is renamed.

## CLI Scripts Structure

Two variants depending on where the script lives:

**`$PERSONAL_BIN_DIR` scripts** — `RUBYLIB` is always set (interactive shell):

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
# displayed time and the in-memory start time are identical — no two-call pattern.
# This deviates from the shell version, which cannot return a value.
script_start_time = Logging.print_script_start

# ... main logic ...

# Passing start_time to print_script_summary causes it to call print_script_duration
# internally — no separate call needed. This deviates from the shell version where
# print_script_summary cannot access the start time (shell functions cannot return
# values to be threaded through). Omit the argument only on early-exit paths inside
# methods that cannot access the top-level start-time local.
Logging.print_script_summary(script_start_time)
```

**`$DOTFILES_DIR/scripts/` scripts** — must prepend utilities path because
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

## Logging

```ruby
Logging.info    "message"    # informational
Logging.success "message"    # success
Logging.warn    "message"    # warning
Logging.error   "message"    # prints error and raises RuntimeError — callers must rescue if execution should continue
Logging.debug   "message"    # debug
Logging.user_action "message"  # manual step the user must perform after the script exits

# NEVER use Ruby stdlib warn
warn "message"               # BAD — use Logging.warn instead
```

The log levels mirror the shell functions in `.shellrc`. Use the same
classification rules across both shell and Ruby:

| Level | When to use |
|---|---|
| `debug` | Expected-absent tools or optional steps silently skipped (e.g. "binary not found — skipping"). Hidden by default. |
| `info` | Normal progress and idempotency guards ("already configured — skipping"). |
| `success` | An operation completed successfully. |
| `warn` | Argument-parsing failures followed by `abort`; non-fatal operation failures where execution continues (e.g. rescue blocks that log and move on). |
| `error` | Unexpected operation failures. Raises `RuntimeError` — callers must `rescue` if processing should continue for remaining items. |
| `user_action` | Manual steps the user must perform after the script (restart an app, run a command, open a URL). |

### Deferred error/warning collection

`record_warning` and `record_error` mirror `_record_warning` / `_record_error`
from `.shellrc`. Each entry is prefixed with `[script_name][current_section]`
for traceability. Pass `start_time` to `print_script_summary` at the end of the
script — it prints collected issues and calls `print_script_duration` internally.
Set `Logging.current_section = 'name'` to track which logical step is executing
— mirrors `_current_section` in shell scripts.

Call `Logging.increment_script_depth` once before `print_script_start`. It
increments `ENV['_DOTFILES_SCRIPT_DEPTH']` and registers an `at_exit` hook that
decrements it on both clean and error exits — the exact mirror of the shell
increment + EXIT trap pair. `print_script_start` and `print_script_summary` gate
their output on `outermost_script?` (`depth <= 1`), so nested subprocess scripts
stay silent and only the outermost script prints its banners and summary.

```ruby
Logging.increment_script_depth
script_start_time = Logging.print_script_start

Logging.current_section = 'Checking dependencies'
Logging.record_warning "optional tool missing — some features disabled"
Logging.record_error   "required env var FOO is not set"

# At end of script — duration is printed internally; no separate call needed:
Logging.print_script_summary(script_start_time)
```

No macOS notification is sent from Ruby — `osascript` is not appropriate for
library code. Scripts that need a notification must handle it themselves.

### Argument-parse failures — use `warn`, not `error`

```ruby
if nil_or_empty?(options[:required])
  parser.abort_with_usage('Missing required argument.')
end
```

`error` raises `RuntimeError`. For arg-parse failures, prefer
`parser.abort_with_usage` (which calls `abort`) — it prints usage and exits
cleanly without raising. Reserve `error` for unexpected failures mid-execution.

### Idempotency guard messages — use `info`, not `warn`

```ruby
if File.exist?(target)
  Logging.info "#{target} already exists — skipping."
else
  # create ...
end
```

### Action items for the user — use `user_action`, not `warn`

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
`$HOME` — NOT from `$DOTFILES_DIR` which is pinned to system Ruby 2.6 and
cannot run rufo:

```zsh
cd "${HOME}" && rufo <path/to/file.rb>
```
