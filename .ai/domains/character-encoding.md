---
applyTo: "all cross-language scripts and configuration files"
---

# Character Encoding and Punctuation

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

All scripts and comments must use **ASCII-only characters**. Never use Unicode punctuation characters such as em dashes, en dashes, curly quotes, or other typographic symbols.

## Rule: Use ASCII Dashes Only

```sh
# Good -- ASCII double dash for parenthetical comments
# This function caches the result -- no subprocess fork needed.

# Good -- ASCII single dash for hyphenated terms
# The cache-invalidation pattern uses mtime comparison.

# BAD -- em dash (Unicode U+2014) breaks some syntax highlighters
# This function caches the result — no subprocess fork needed.

# BAD -- en dash (Unicode U+2013)
# The cache–invalidation pattern uses mtime comparison.
```

## Rule: Use ASCII Quotes Only

**In code:**
```sh
# Good -- ASCII straight quotes
echo "Processing 'file.txt'"

# BAD -- curly quotes (Unicode)
echo "Processing 'file.txt'"
```

**In comments:**
```sh
# Good -- ASCII straight quotes
# The 'cache_dir' variable holds the path.

# BAD -- curly quotes (Unicode)
# The 'cache_dir' variable holds the path.
```

## Why ASCII-Only?

1. **Syntax highlighters**: Many editors and syntax highlighters break or display incorrectly when encountering Unicode punctuation in code/comments
2. **Terminal compatibility**: Not all terminals render Unicode punctuation correctly, especially in SSH sessions or minimal environments
3. **Copy-paste safety**: Unicode characters can be accidentally converted or corrupted when copying code between systems
4. **Searchability**: ASCII dashes can be searched with simple regex patterns; Unicode variants require special handling
5. **Git diffs**: Unicode characters can display as escape sequences in some git diff viewers, making code review harder

## Allowed Unicode

The only Unicode allowed in scripts:

### 1. ANSI Color Codes

ANSI escape sequences for terminal colors are allowed:

```sh
# Shell
echo "\e[31mError:\e[0m Something went wrong"

# Ruby
puts "\e[31mError:\e[0m Something went wrong"
```

### 2. User-Facing Output (Where Typography Matters)

Unicode in **logged output** where typographic quality matters:

```sh
# Shell
info "Processing — 50% complete"

# Ruby
Logging.info "Processing — 50% complete"
```

**Important:** This exception applies ONLY to the string content being logged, NOT to comments or variable names in the code itself.

### 3. What Is NOT Allowed

Even in user-facing output, avoid:
- Unicode in comments or code (only in output strings)
- Unicode in variable names or function names
- Unicode in configuration keys or identifiers

## When In Doubt

Use ASCII. The readability benefits of Unicode typography do not outweigh the compatibility and maintenance costs.

## Verification

Check for Unicode punctuation in code/comments:

```zsh
# Find Unicode dashes (em dash, en dash)
grep -n '[—–]' file.sh

# Find curly quotes
grep -n '[""'']' file.rb

# Find any non-ASCII characters (including comments)
grep -P -n '[^\x00-\x7F]' file.sh
```

**Fix:** Replace Unicode punctuation with ASCII equivalents:
- Em dash `—` → `--` (double dash)
- En dash `–` → `-` (single dash)
- Curly quotes `""` → `""` (straight quotes)
- Single curly quotes `''` → `''` (straight quotes)
