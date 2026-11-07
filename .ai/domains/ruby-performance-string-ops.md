---
applyTo: "**/*.rb"
name: dotfiles-ruby-performance-string-ops
description: Use when optimizing Ruby string processing in this dotfiles repo -- tr vs gsub, delete vs gsub, sub vs gsub, delete_prefix/delete_suffix, method-selection flowchart, and when string optimizations are (and aren't) worth it.
---

# Ruby Performance and Idioms: String Operations

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

This is a topic file of [`ruby-performance-idioms.md`](./ruby-performance-idioms.md): string
transformation performance rules extracted there so the core performance file stays focused on
memoization, constants, hoisting, and collection patterns. Read the core file first.

**Related files**:
- [`ruby-scripting.md`](./ruby-scripting.md) - Core rules (dual-mode, parameters, exit points, version compatibility) -- read this first
- [`ruby-performance-idioms.md`](./ruby-performance-idioms.md) - Core performance rules (this topic's parent)
- [`ruby-infrastructure.md`](./ruby-infrastructure.md) - Cost of `require` on the per-command path

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
