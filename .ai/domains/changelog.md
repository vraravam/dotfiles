---
applyTo: "**/CHANGELOG.md"
name: dotfiles-changelog
description: Use when generating a changelog entry, writing a commit message, or amending a commit in this dotfiles repo -- covers the commit workflow, changelog entry structure and rules, and eliminating intermediate-state cruft when amending.
---

# Changelog Generation Rules

> Part of the [tool-agnostic instruction set](../instructions.md) for this repository.

Apply these rules whenever the user asks for a changelog entry or commit message.

**Related files**:
- [`git-workflow.md`](./git-workflow.md) - Commit permission rules

**MANDATORY: Every commit in `${DOTFILES_DIR}` MUST include a new CHANGELOG.md section.**

## Workflow for Creating Commits

1. Make all code/documentation changes
2. Run `git next-version` to get the next version number
3. Add a new section to CHANGELOG.md with that version number
4. Document ALL changes in the commit (not just the "main" change)
5. Stage all changes including CHANGELOG.md
6. Create ONE atomic commit containing both the changes and the CHANGELOG entry

## Rules

- The CHANGELOG entry must document ALL changes in the commit (not just the "main" change)
- Include changes to `.ai/` instructions when they're part of the same logical change (e.g., adding a feature + documenting the pattern in instructions)
- Never create separate commits for CHANGELOG updates - include CHANGELOG in the same commit as the changes it documents
- **Never include line number references** - line numbers become stale as files are edited and add no value to users adopting changes
- When generating a changelog, first examine the list of staged changes
- For changes that affect the zwc cache (e.g., edits to autoloaded function files), prepend a call to `delete_caches` before any `unfunction` or re‑compile instructions so the cache is regenerated correctly.
- **Restarting and reloading are alternatives, never both.** A restarted Terminal/iTerm starts new shells that source every startup file from scratch, so a separate reload instruction after a restart is redundant. The reload commands below are only for picking up the change in the *current* shell without restarting. When a change needs either, write one adoption step: the restart note, with the matching reload command offered as the no-restart alternative (e.g. "Restart the Terminal/iTerm application (or, to avoid a restart, run: `unfunction ...`)"). Never write "restart, then reload".
- If any function definitions in `~/.shellrc` have been added, renamed, or removed, offer this reload command (the no-restart alternative above):
  ```zsh
  unfunction is_shellrc_sourced; DEBUG=true load_file_if_exists ~/.shellrc
  ```
- If any function definitions in `${ZDOTDIR}/.aliases` have been added, renamed, or removed, offer this reload command (the no-restart alternative above):
  ```zsh
  unfunction is_aliases_sourced; DEBUG=true load_file_if_exists ${ZDOTDIR}/.aliases
  ```
- If any new files have been added or existing files have been deleted/renamed in the `files` folder, then add instructions to run `install-dotfiles.rb`.
- If any modifications touch the zsh boot‑up files (`.zshenv`, `.zshrc`, `.zlogin`, `.aliases`, `.shellrc`, etc.) or other scripts that are sourced during a terminal start‑up, add a note that the user should quit and restart the Terminal/iTerm application to reload the configuration (combined with any reload command into a single step, see above).
- If the staged changes involve fresh‑install logic (e.g., modifications to `fresh-install-of-osx.sh` or related scripts), decide whether an already‑set‑up machine gains anything from a re‑run. Advise `./fresh-install-of-osx.sh;` (it is idempotent) only when a re‑run actually repairs or updates something there (e.g., it migrates existing state, or applies a new setting to a configured machine). When the change only affects what a vanilla install does, say so instead: "nothing to do on a machine that is already set up; applies the next time the script runs". Never list a re‑run as an adoption step just because the script was edited.

## Amending a Commit -- Eliminate Intermediate-State Cruft

**MANDATORY: When amending (or squashing) a commit that already has an existing CHANGELOG.md section and/or commit message, both must be rewritten to describe only the final, squashed state -- never left as a chronological narrative of intermediate edits.**

This applies whenever a commit is amended with new changes, or multiple commits are squashed together (e.g. `git reset --soft <base>` followed by a single new commit). Do not simply append new bullets/paragraphs describing the newest edit on top of what was already there -- both artifacts must be re-derived from the final squashed diff.

**Workflow:**

1. After finalizing the squash/amend's staged content (working tree and index in their final state), get the full diff for the amended commit's overall range: `git diff <original-base> <final-staged-tree>` (or per-file: `git diff <original-base> -- <file>`).
2. Cross-check **every existing CHANGELOG bullet** (and every paragraph of the existing commit message) against that final diff, file by file:
   - If a bullet describes something that does not appear at all in the final diff (e.g. a feature added in one intermediate commit and fully reverted/replaced in a later one within the same squash) -- it is pure intermediate-state cruft. **Delete the bullet entirely.**
   - If a bullet's specific claim (e.g. "does not call into X at all", "now calls Y directly") was true of an intermediate commit but has since been further changed by a later edit in the same squash -- **rewrite the bullet to describe only the final, accurate behavior.** Never leave a claim that contradicts the actual staged/committed diff.
   - If two bullets (originally written for two separate, now-squashed commits) both describe the same file/behavior, and the second supersedes/extends the first -- **merge them into one bullet** describing the final state, rather than presenting it as "first we did X, then we changed it to Y."
3. Apply the same cross-check to the **commit message** -- it must read as a single, coherent description of the final change, not a stitched-together history of "first this happened, then this fix, then this other fix." Remove or rewrite any paragraph that only made sense as a description of an intermediate, now-superseded state.
4. Verify the rewritten CHANGELOG section and commit message pass a final read-through: every claim should be independently verifiable against `git diff <original-base> <final-state>` for the specific file/behavior it describes.

**Why this matters:** once commits are squashed, the intermediate commits never existed from the reader's perspective -- a CHANGELOG or commit message that still narrates them (e.g. "removed the X we added earlier in this same entry", or "now calls Y directly" when the final code doesn't) is actively misleading, not just imprecise. This is distinct from the [`git-workflow.md`](./git-workflow.md) § Rebase Rules content-correctness checklist above -- that verifies no functionality was lost during a rebase; this specifically targets stale narrative/documentation left over from the squash mechanics.

## Changelog Entry Structure

When creating or editing CHANGELOG.md sections, follow these rules:

1. **Group related changes by category** rather than listing individual files when multiple files share similar changes.
   - Use `*[all ruby scripts]*` or `*[all zsh autoload scripts in files/--XDG_CONFIG_HOME--/zsh/]*` for changes that apply across multiple files with the same pattern.
   - Example: Instead of separate bullets for `antidote.rb`, `cron.rb`, and `keybase.rb` when they all adopt the same pattern, write one bullet covering all affected files.

2. **Keep essential technical details** while removing redundant specifics:
   - Include: method names, key implementation details, specific behavior changes
   - Remove: line numbers (they become stale as files are edited); repetitive file-by-file descriptions when a category description suffices
   - Example: Keep "`update_repo(dir)` - fetch all remotes and rebase onto upstream" but consolidate "uses `GitProcessor.repo?(path)` for validation" once rather than per file

3. **Use concise, high-level summaries** in the adoption section:
   - Focus on user-visible actions (restart terminal, run a script).
   - Remove implementation details that are already covered in the bullet points above.
   - Combine related adoption steps into single bullets when possible.

4. **Structure each version section consistently**:
   - Version number header (e.g., `### 3.1.23`)
   - Descriptive subheading summarizing the theme (e.g., `#### Backport utility enhancements and convert zsh autoload functions to Ruby`)
   - Bullet points with specific changes (technical details without line numbers)
   - `#### Adopting these changes` section with user action items (optional - omit if no user actions required)

5. **Version section spacing and visual separation**:
   - Each version section (starting with `### X.Y.Z`) must be separated by **exactly one blank line, followed by a horizontal rule (`---`), followed by one blank line**
   - Pattern: `[end of previous section]\n\n---\n\n### X.Y.Z`
   - The horizontal rule provides clear visual separation between sections when rendered in markdown viewers
   - The horizontal rule is a *separator* between version sections, not a header decoration
   - **Horizontal rule before the first version section** (one blank line after introductory text, then `---`, then one blank line before `### 3.1.27`)
   - **Horizontal rule after the last version section** (one blank line after last content, then `---` as the final line of the file)

**Example of good structure:**
```markdown
### 3.1.23

#### Backport utility enhancements and convert zsh autoload functions to Ruby

* *[scripts/utilities/git_workspace.rb]* Added four new public methods for git operations: `update_repo(dir)` - fetch all remotes and rebase onto upstream; `update_all_repos` - update key repos (home, dotfiles, profiles) plus Chrome profile directories; `status_repo(dir)` - show status with custom formatting; `status_all_repos` - status check all repos. All methods use `GitProcessor.repo?(path)` for validation and return boolean success.

* *[all ruby scripts]* Ensures consistency with single source of truth for git repo detection across all utility modules. Also found and fixed premature conversion of `Pathname` instances to `String` (maintain rich object as much as possible only convert to String at interpolation boundaries).

* *[all zsh autoload scripts in files/--XDG_CONFIG_HOME--/zsh/]* Converted from shell script to a thin Ruby wrapper.

#### Adopting these changes

* Restart terminal to reload zsh autoload functions.
* New Ruby methods are immediately available to shell scripts via `ruby -e` pattern.
```
