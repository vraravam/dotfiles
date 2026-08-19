---
applyTo: "**/files/**,**/scripts/install-dotfiles.rb,**/files/--HOME--/custom.gitignore"
---

# Custom Gitignore Maintenance Instructions

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

## Scope

**This file applies to**: All operations on the `files/` directory and `custom.gitignore` files, including:
- Adding, deleting, renaming, or moving files in `${DOTFILES_DIR}/files/`
- Editing `files/--HOME--/custom.gitignore` (home directory repo)
- Editing `files/--PERSONAL_PROFILES_DIR--/custom.gitignore` (browser profiles repo)
- Running `install-dotfiles.rb` (which processes `files/` and copies `custom.gitignore` files)

**Related files**:
- [`fresh-install.md`](./fresh-install.md) - Bootstrap and installation scripts that call `install-dotfiles.rb`
- [`path-constants.md`](./path-constants.md) - Environment variable substitution rules (`--VAR--` patterns)
- [`shell-scripting.md`](./shell-scripting.md) - Shell patterns for verification commands

**Does NOT apply to**: Files outside the `files/` directory, temporary files, build artifacts, or content in `.gitignore` entries that are not managed by this repository's symlink system.

## Rule: Sync `custom.gitignore` with `files/` Directory

**When adding/deleting/renaming files in `files/` directory, you MUST update `files/--HOME--/custom.gitignore` to match.**

### Why This Matters

Files in `${DOTFILES_DIR}/files/` are processed by `install-dotfiles.rb` and installed to their destination paths via:
- **Symlinks** (most files) - linked from repo based on env var substitution (e.g., `--HOME--` → `~`, `--XDG_CONFIG_HOME--` → `~/.config`)
- **Copies** (git config files) - `custom.git*` files are copied and renamed (e.g., `custom.gitignore` → `.gitignore`)

Any directory that is a git repo needs to ignore these symlinks and copies when they are nested within it to avoid tracking them.

Each `custom.gitignore` file is copied to `.gitignore` in its destination directory and defines ignore patterns for all dotfiles managed by this repository in that location.

**Existing custom.gitignore locations:**
- `files/--HOME--/custom.gitignore` → `~/.gitignore` (home directory repo)
- `files/--PERSONAL_PROFILES_DIR--/custom.gitignore` → `~/personal/browser-profiles/.gitignore` (browser profiles repo)

The same maintenance rules apply to any `custom.gitignore` files added in the future.

### Path Transformation Rules

`install-dotfiles.rb` transforms source paths to destination paths:

1. **Strip `files/` prefix**: `files/--HOME--/.shellrc` → `--HOME--/.shellrc`
2. **Interpolate env vars**: `--HOME--/.shellrc` → `~/.shellrc` (or `/Users/vijay/.shellrc`)
3. **Custom git prefix replacement**: `custom.gitconfig` → `.gitconfig`, `custom.gitattributes` → `.gitattributes`
4. **Remove root `/`**: Gitignore entries use HOME-relative paths starting with `/`

See [TechnicalDeepDive.md § 9](../../TechnicalDeepDive.md#9-install-dotfilesrb-mechanics) for additional `install-dotfiles.rb` behavior: `--VAR--` resolution, adopt-existing-file behavior, copy vs symlink rules, and SSH config injection.

### Pattern Examples

| Source File in `files/` | Destination Path | Gitignore Entry |
|--------------------------|------------------|-----------------|
| `files/--HOME--/.shellrc` | `~/.shellrc` | `/.shellrc` |
| `files/--HOME--/.zshrc` | `~/.zshrc` | `/.zshrc` |
| `files/--HOME--/custom.gitignore` | `~/.gitignore` | `/.gitignore` |
| `files/--HOME--/custom.gitconfig` | `~/.gitconfig` | `/.gitconfig` |
| `files/--HOME--/.config/starship.toml` | `~/.config/starship.toml` | `/.config/starship.toml` |
| `files/--XDG_CONFIG_HOME--/zsh/foo` | `~/.config/zsh/foo` | `/.config/zsh/*` |
| `files/--PERSONAL_BIN_DIR--/script.rb` | `~/personal/bin/script.rb` | (NOT in HOME gitignore - different repo) |

### Adding a New File

When adding a file to any `files/--VAR--/` directory that has a corresponding `custom.gitignore`:

1. **Create the source file**: `files/--VAR--/.newfile`
2. **Add gitignore entry**: Add the repo-relative path to `files/--VAR--/custom.gitignore`
3. **Maintain sort order**: Insert in alphabetical order
4. **Use wildcard for directories**: If adding multiple files in a directory, use wildcard patterns

**Examples:**
```bash
# Adding to HOME repo
files/--HOME--/.newfile → Add `/.newfile` to files/--HOME--/custom.gitignore

# Adding to browser profiles repo
files/--PERSONAL_PROFILES_DIR--/chrome/profile.txt → Add `/chrome/profile.txt` to files/--PERSONAL_PROFILES_DIR--/custom.gitignore

# Historical example (now DELETED)
# files/--HOME--/.envrc → Would have added `/.envrc` to files/--HOME--/custom.gitignore
```

### Deleting a File

When removing a file from any `files/--VAR--/` directory that has a corresponding `custom.gitignore`:

1. **Delete the source file**: `rm files/--VAR--/path/to/file`
2. **Remove gitignore entry**: Delete the corresponding pattern from `files/--VAR--/custom.gitignore`
3. **Verify no broken symlink**: Check destination directory for orphaned symlink and remove if exists

**Examples:**
```bash
# Deleted from HOME repo (completed)
# files/--HOME--/.envrc → Removed `/.envrc` from custom.gitignore (line 413)

# Deleting from browser profiles repo
files/--PERSONAL_PROFILES_DIR--/firefox/prefs.js → Remove `/firefox/prefs.js` from files/--PERSONAL_PROFILES_DIR--/custom.gitignore
```

### Renaming or Moving a File

When renaming or moving a file in any `files/--VAR--/` directory that has a corresponding `custom.gitignore`:

1. **Rename/move source file**: `git mv files/--VAR--/oldpath files/--VAR--/newpath`
2. **Update gitignore**: Change the old pattern to the new pattern in `files/--VAR--/custom.gitignore`
3. **Maintain sort order**: Move entry if alphabetical position changes
4. **Cross-directory moves**: If moving from one `--VAR--` directory to another, remove the entry from the old `custom.gitignore` and add to the new one

**Examples:**
```bash
# Renaming in HOME repo
git mv files/--HOME--/.oldname files/--HOME--/.newname
# Update custom.gitignore: `/.oldname` → `/.newname`

# Moving across directories in HOME repo (e.g., HOME root to XDG_CONFIG_HOME)
git mv files/--HOME--/.vimrc files/--XDG_CONFIG_HOME--/vim/vimrc
# Remove `/.vimrc` from files/--HOME--/custom.gitignore
# Add `/.config/vim/vimrc` to files/--HOME--/custom.gitignore (if vim/ is in HOME repo)

# Moving files between repos
git mv files/--HOME--/.shellcheckrc files/--XDG_CONFIG_HOME--/shellcheck/shellcheckrc
# Remove `/.shellcheckrc` from files/--HOME--/custom.gitignore
# Add `/.config/shellcheck/shellcheckrc` to files/--HOME--/custom.gitignore

# Renaming in browser profiles repo
git mv files/--PERSONAL_PROFILES_DIR--/chrome/old.txt files/--PERSONAL_PROFILES_DIR--/chrome/new.txt
# Update custom.gitignore: `/chrome/old.txt` → `/chrome/new.txt`
```

### Special Cases

**1. `custom.git*` files (COPIED, not symlinked):**
- `custom.gitignore` → `.gitignore`
- `custom.gitconfig` → `.gitconfig`
- `custom.gitattributes` → `.gitattributes`
- These are COPIED (not symlinked) because git has issues with symlinked config files
- Still need gitignore entries because the copies exist in the destination repo

**2. Cross-repo boundaries:**
- `files/--PERSONAL_BIN_DIR--/*` → NOT in HOME gitignore (different git repo entirely)
- `files/--XDG_CONFIG_HOME--/*` → HOME gitignore (defaults to `~/.config/` which is nested within HOME)
- `files/--ZDOTDIR--/*` → HOME gitignore (defaults to `~/.config/zsh/` which is nested within HOME)
- `files/--PERSONAL_PROFILES_DIR--/*` → Own gitignore (separate git repo with its own `custom.gitignore`)

**3. Directory wildcards:**
- Wildcards like `/.config/zsh/*` cover all files in that directory
- Don't add individual entries for each file in a wildcard directory
- Use specific entries only when you need to track some files but ignore others

### Verification Commands

**Check for missing gitignore entries (adapt VAR to your target directory):**
```bash
# List all files that would be symlinked (example for HOME)
cd "${DOTFILES_DIR}/files/--HOME--"
find . -type f ! -name "custom.git*" ! -name ".DS_Store" | sed 's|^\./|/|' | sort

# Compare with gitignore entries
grep "^/" custom.gitignore | sort

# For browser profiles repo
cd "${DOTFILES_DIR}/files/--PERSONAL_PROFILES_DIR--"
find . -type f ! -name "custom.git*" ! -name ".DS_Store" | sed 's|^\./|/|' | sort
grep "^/" custom.gitignore | sort
```

**Check for orphaned gitignore entries (adapt VAR to your target directory):**
```bash
# Find gitignore entries without corresponding source files (example for HOME)
while IFS= read -r pattern; do
  [[ "$pattern" =~ ^/ ]] || continue
  source_file="files/--HOME--${pattern}"
  source_file_custom="${source_file/\/.git/\/custom.git}"
  [[ -f "$source_file" ]] || [[ -f "$source_file_custom" ]] || echo "Orphaned: $pattern"
done < files/--HOME--/custom.gitignore

# For browser profiles repo
while IFS= read -r pattern; do
  [[ "$pattern" =~ ^/ ]] || continue
  source_file="files/--PERSONAL_PROFILES_DIR--${pattern}"
  source_file_custom="${source_file/\/.git/\/custom.git}"
  [[ -f "$source_file" ]] || [[ -f "$source_file_custom" ]] || echo "Orphaned: $pattern"
done < files/--PERSONAL_PROFILES_DIR--/custom.gitignore
```

### Scan Rule for AI

When editing `files/` directory:

1. **After adding a file**: Search `custom.gitignore` for the transformed path. If missing, add it.
2. **After deleting a file**: Search `custom.gitignore` for the entry. If present, remove it.
3. **After renaming a file**: Update the corresponding entry in `custom.gitignore`.
4. **After moving a file between directories**: Remove from old location's gitignore, add to new location's gitignore.
5. **Always maintain alphabetical sort order** within each section of `custom.gitignore`.
6. **After adding/deleting/renaming/moving ANY file in `files/` directory**: Add `install-dotfiles.rb` instruction to CHANGELOG adoption section for that commit.

## Example Session

```bash
# Scenario: Adding a new config file
touch files/--HOME--/.myconfigrc
# → Add /.myconfigrc to custom.gitignore in alphabetical position

# Scenario: Deleting .envrc (completed)
rm files/--HOME--/.envrc
# → Remove /.envrc from custom.gitignore ✓ (already done by user)

# Scenario: Renaming .oldrc to .newrc
git mv files/--HOME--/.oldrc files/--HOME--/.newrc
# → Change /.oldrc to /.newrc in custom.gitignore
```

---

**CRITICAL**: This is a load-bearing pattern. Forgetting to update `custom.gitignore` causes the destination git repo to track symlinks and copies, creating noise in `git status` and potentially committing symlink targets or file copies instead of keeping them properly ignored.
