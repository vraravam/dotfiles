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

Exception: `logging.rb` directly `require_relative`s `string.rb` because color
methods from `string.rb` are used on every logging call — this is an intentional
direct dependency, not a transitive one. All other utilities must not chain requires.

Use `require` (not `require_relative`) for files in `utilities/` — the
`RUBYLIB` env var is set to include that directory at runtime.

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

# String color extensions (from string.rb)
"text".blue
"text".yellow
"path/to/#{HOME}/file".red  # HOME->tilde substitution happens inside color methods
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

## CLI Scripts Structure

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require 'logging'
require 'cli_parser'

# ---------------------------------------------------------------------------
# Constants

SCRIPT_DESCRIPTION = "One-line description of what this script does."

# ---------------------------------------------------------------------------
# Main

parser = CliParser.new(SCRIPT_DESCRIPTION) do |opts|
  opts.on('-f', '--flag', 'Description') { options[:flag] = true }
  opts.on('-h', '--help', 'Show this help') { parser.abort_with_usage('') }
end

options = {}
parser.parse!(ARGV, options)

# Guard required args
if nil_or_empty?(options[:required])
  parser.abort_with_usage('Missing required argument.')
end

Logging.section_header("Script Name")
Logging.info "Starting at #{Time.now}"

# ... main logic ...

Logging.info "Completed at #{Time.now}"
```

## Logging

```ruby
Logging.info    "message"    # informational
Logging.success "message"    # success
Logging.warn    "message"    # warning
Logging.error   "message"    # prints error and raises RuntimeError — callers must rescue if execution should continue
Logging.debug   "message"    # debug

# NEVER use Ruby stdlib warn
warn "message"               # BAD — use Logging.warn instead
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
