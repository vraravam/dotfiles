---
applyTo: "**/*.md"
name: dotfiles-markdown-blocks
description: Use when writing or editing markdown documentation in this dotfiles repo that contains copy-paste shell command blocks -- every command ends with `;`, and prefer `git -C <dir>` or full script paths over `cd`.
---

# Markdown Copy-Paste Command Blocks

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules to any fenced code block in a markdown file that a reader is expected to copy-paste and run.

**Related files**:
- [`edit-checklist.md`](./edit-checklist.md) - Post-edit workflow for code and config files

## Markdown Copy-Paste Command Blocks — Every Command Ends With `;`

**In any fenced code block in a markdown file that a reader is expected to copy-paste and run** (setup instructions, troubleshooting steps, bootstrap commands, etc.), every command line must end with a semicolon `;` — including a lone single command in an otherwise one-line block, and the last command in a multi-line block. Only comment lines (`# ...`) are exempt.

```zsh
# BAD -- relies purely on newlines to separate commands
security delete-generic-password -a "${USER}" -s 'some-service'
security add-generic-password -A -a "${USER}" -s 'some-service' -w

# Good -- every command explicitly terminated
security delete-generic-password -a "${USER}" -s 'some-service';
security add-generic-password -A -a "${USER}" -s 'some-service' -w;
```

```zsh
# BAD -- lone command with no trailing terminator
brew bundle install

# Good -- terminated even though it's the only command in the block
brew bundle install;
```

**Why:** some terminal emulators, paste mechanisms, or automation (e.g. "bracketed paste" edge cases, or a block being flattened into one line by some intermediary) can lose or merge the newlines between commands. Without an explicit `;` after each command, two merged lines run together as one malformed command instead of failing loudly or behaving as two separate commands. A trailing `;` makes every command boundary explicit and immune to newline loss, regardless of how the block is pasted or by what mechanism.

**Applies to**: any fenced code block (` ```bash `, ` ```zsh `, ` ```sh `, or unlabeled ` ``` `) in a markdown file, when its content is a command or sequence of commands meant to be executed by the reader (setup guides, `KeybaseMigration.md`, `Adoption.md`, `Advanced.md`, `TechnicalDeepDive.md`, `Extras.md`, `CONTRIBUTING.md`, etc.). Does **not** apply to code blocks illustrating something other than "run these commands verbatim" (e.g. a bare filename, a config-file snippet not meant for a shell, or a diff).

## Markdown Copy-Paste Command Blocks — Prefer `git -C <dir>` Over `cd`-ing

**In the same fenced code blocks described above, never show the reader `cd`-ing into a target directory before running a git command or one of this repo's own scripts.** Use `git -C <dir> <command>` for git operations, and pass the target directory as an explicit argument for this repo's own scripts (they all accept a directory/file argument for exactly this reason -- see `ruby-scripting.md` and `shell-scripting.md`'s script-argument conventions). This matches how the scripts themselves are designed to be called (with fully-qualified, non-relative-path arguments) rather than relying on the reader's current working directory.

```zsh
# BAD -- relies on the reader's shell staying in this directory for every
# subsequent command in the block (and in any later block that assumes it)
cd "${DOTFILES_DIR}";
git log --oneline -20;
git commit -m "message";

# Good -- each command is self-contained; works regardless of cwd
git -C "${DOTFILES_DIR}" log --oneline -20;
git -C "${DOTFILES_DIR}" commit -m "message";
```

```zsh
# BAD -- cd + relative invocation of one of this repo's own scripts
cd /tmp/dotfiles-master;
./scripts/capture-prefs.rb -e;

# Good -- invoke via its full path, no cd needed
/tmp/dotfiles-master/scripts/capture-prefs.rb -e;
```

**Why:** `cd`-based examples silently depend on shell state carried over from an earlier command or fenced block -- state that is invisible in the rendered documentation and easy to lose (a reader may only copy one block, may have `cd`'d elsewhere in between reading sections, or may run the blocks out of order). `git -C <dir>` and full-path script invocation make every command block independently correct no matter what directory the reader's shell is currently in, exactly mirroring how the underlying scripts are written to be called.

**Exception:** a `cd` (or a script invoked without an explicit directory argument) is acceptable when the command has no `-C`-style affordance and genuinely cannot take a directory as an argument (e.g. `curl -o <file>` writing into the current directory, or a generic third-party tool with no path-argument support) -- prefer redirecting/parameterizing the output path instead of `cd`-ing where possible (e.g. `curl -o /tmp/dotfiles.zip ...` rather than `cd /tmp; curl -o dotfiles.zip ...`).
