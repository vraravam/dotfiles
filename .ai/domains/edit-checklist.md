---
applyTo: "all cross-language scripts and configuration files"
---

# Edit Checklist

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply this checklist after every edit to any script or configuration file in this repository.

## Universal Steps (All Files)

### Step 1 -- Verify Decision-Making Philosophy

Verify every new or changed line upholds the four priorities defined in
`copilot-instructions.md` § **Decision-Making Philosophy**:

1. **Startup speed** (for zsh startup paths)
2. **Maintainability** (readability, DRY, clear intent)
3. **POSIX compatibility** (when scripts run in bash/direnv)
4. **Zsh built-ins** (when they don't conflict with #1-3)

A higher priority always wins; document the tradeoff in a comment when they conflict.
If it is unclear which priority applies, ask the user before proceeding.

Only continue once every changed line satisfies the highest applicable priority.

### Step 2 -- Language-Specific Safety Checks

#### Shell Scripts

Scan every standalone `A && B` line in the edited file. If the script uses
`set -e` or an ERR trap, verify that A returning false is an *error*, not a
normal/expected outcome. Fix any unsafe patterns before proceeding.

See [`shell-scripting.md`](./shell-scripting.md) § **`&&` as Conditional -- Safety Under `set -e` / ERR Trap**.

#### Ruby Scripts

Verify Ruby 2.6 compatibility. Do NOT use:
- Endless range `(1..)` -- use `(1..Float::INFINITY)` or avoid
- Pattern matching (`case x in`) -- Ruby 3.0+
- Numbered block parameters (`_1`, `_2`) -- Ruby 2.7+
- Rightward assignment (`=> variable`) -- Ruby 3.0+
- Hash shorthand syntax (`{x:, y:}`) -- Ruby 3.1+

Only continue to formatting once all unsafe patterns are resolved.

### Step 3 -- Syntax Verification

#### Shell Scripts

```zsh
zsh -n path/to/script.sh
```

This command must succeed with no syntax errors. Run it before formatting.

#### Ruby Scripts

```bash
/usr/bin/ruby -c path/to/script.rb
```

This command must succeed with no syntax errors. Run it before formatting.

### Step 4 -- Format

#### Shell Scripts

**Check `.shfmtignore` first.** If the file is listed there, do NOT run `shfmt`
on it -- skip formatting entirely for that file. Running `shfmt` on an excluded
file will corrupt intentional one-liners.

Run `shfmt`:

```zsh
shfmt -w <file>
```

**shfmt has no inline per-line or per-block ignore directive.** Whole files can
be excluded via `.shfmtignore`, but only for two valid reasons:

1. The file contains zsh-only syntax that shfmt cannot parse (e.g. `${^array}`,
   `for key value in "${(@kv)assoc}"`).
2. The file hits a shfmt bug where one-liners inside loop or compound bodies are
   forcibly expanded into an unreadable (and often misaligned) multi-line form
   with no way to suppress it. Example -- shfmt transforms this intentional
   one-liner:
   ```zsh
   while true; do has_sudo_credentials; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
   ```
   into this broken padded expansion:
   ```zsh
   while true; do
                  sudo -n true
                                sleep 60
                                          kill -0 "$$" || exit
   done                                                          2>/dev/null &
   ```
   The one-liner form is correct and must be preserved. Adding the file to
   `.shfmtignore` is the only reliable fix.

Do not add files to `.shfmtignore` for any other reason.

#### Ruby Scripts

Run `rufo` from `$HOME` (required for correct path resolution):

```bash
cd "${HOME}" && rufo path/to/script.rb
```

### Step 5 -- Verify All Whitespace Rules

See [`whitespace-rules.md`](./whitespace-rules.md) for complete verification
steps and fixes.

All files must pass these three checks:
1. File ends with exactly one newline
2. File has no trailing blank lines (except markdown files)
3. No lines have trailing spaces or tabs

### Step 6 -- Ensure Executable Permission (Shell Scripts Only)

After editing shell scripts, ensure they have executable permission. This is especially important if your editing method rewrites the file (which can lose the executable bit).

**Check if executable:**
```zsh
[[ -x path/to/script.sh ]] && echo "✅ Executable" || echo "❌ Not executable"
```

**Restore executable permission:**
```zsh
chmod +x path/to/script.sh
```

**Applies to:**
- All scripts in `$DOTFILES_DIR/scripts/` (`.sh`, `.zsh`)
- All scripts in `$PERSONAL_BIN_DIR/` (`.sh`, `.zsh`, `.bash`)
- Autoload functions in `$XDG_CONFIG_HOME/zsh/` (`.zsh` files)

**Why:** Scripts must be executable to run. Without this permission, they fail with "Permission denied" errors.

## Quick Reference

| Language | Syntax Check | Format Command | Whitespace | Executable |
|----------|-------------|----------------|------------|------------|
| Shell    | `zsh -n file` | `shfmt -w file` (check `.shfmtignore` first) | ✅ | ✅ |
| Ruby     | `/usr/bin/ruby -c file` | `cd "${HOME}" && rufo file` | ✅ | ❌ |
| Markdown | N/A | N/A | ✅ (Check 2 exempt) | ❌ |
| Other    | N/A | N/A | ✅ | ❌ |
