As documented in the README's [adopting](README.md#how-to-adoptcustomize-the-scripts-to-your-own-settings) section, this repo and its scripts are aimed at developers/techies. If you are stuck or need help in any fashion, you can reach out to the [owner of the parent repo](https://github.com/vraravam) from where this was forked.

For those who follow this repo, here's the changelog for ease of adoption:

---

### 3.1.29

#### Fix 26 critical/high-priority issues: Core modules, ERR traps, PlistBuddy atomicity

* *[scripts/utilities/keybase.rb]* Added missing Core module (lines 6-7, 14-15). Added `require_relative 'core'` and both `include Core` + `extend Core`. Fixes `nil_or_empty?` usage that previously only worked via transitive include through Logging. Method now available in both module methods and blocks.

* *[scripts/utilities/plist.rb]* Added missing Core module (lines 8, 20-21). Added domain validation for export operations (line 41) - now validates domain is non-empty before attempting export. Added rescue for relative_path calls (line 57) - prevents crashes when path validation fails. Fixes `nil_or_empty?` calls at lines 66 and 187.

* *[scripts/utilities/path_utils.rb]* Added missing logging require (line 8). Fixes crash when `Logging.debug` called at line 117 during `ensure_directories_exist`.

* *[scripts/install-dotfiles.rb]* Added Core module (lines 24, 32-33). Added `require_relative 'utilities/core'` and both `include Core` + `extend Core`. Removes fragile dependency on transitive Core inclusion via Logging module. Makes `nil_or_empty?` available throughout script.

* *[scripts/resurrect-repositories.rb]* Added Core module (lines 22, 31-32). Same changes as install-dotfiles.rb - explicit Core require and dual include/extend for consistent helper method availability.

* *[scripts/capture-prefs.rb]* Added rescue for GitProcessor relative_path calls (lines 168-178). When path validation fails (path outside repo or invalid), logs warning via `Logging.warn` and skips the problematic file instead of crashing. Prevents fatal errors during preferences backup/restore when unexpected file paths encountered.

* *[scripts/cleanup-browser-profiles.rb]* Fixed variable scoping (lines 138, 222-238). Moved `profile_folder` declaration inside GitProcessor block where it's used. Moved `backup_file` declaration inside conditional branches. Improves garbage collection and clarifies variable lifetime.

* *[files/--HOME--/.shellrc]* Fixed unsafe `keep_sudo_alive` arithmetic (line 1237). Changed `has_sudo_credentials` to `has_sudo_credentials || true` - prevents return code 1 from triggering ERR traps when sudo not available. Added Ruby availability checks in `_call_ruby_cron` (guards all Ruby delegations with `command_exists ruby`). Prevents crashes on vanilla OS before Homebrew installs Ruby.

* *[files/--HOME--/.aliases]* Added Ruby availability checks (lines 377-382 in `_call_ruby_git_workspace`, 1008-1013 in `_call_ruby_macos`). Guards all Ruby utility delegations with `command_exists ruby` before invoking. Prevents "ruby: command not found" errors during fresh-install before Homebrew installation completes.

* *[files/--XDG_CONFIG_HOME--/zsh/status_all_repos]* Fixed dispatch pattern. Moved shell implementation into `_status_all_repos`, added `status_all_repos` dispatch wrapper calling `dispatch_or_fallback`. Complies with mandatory pattern from shell-scripting.md - Ruby delegation works correctly, shell fallback preserved.

* *[files/--XDG_CONFIG_HOME--/zsh/update_all_repos]* Fixed dispatch pattern. Same changes as status_all_repos - moved implementation to `_update_all_repos`, added dispatch wrapper. Ensures consistent Ruby-first execution with shell fallback.

* *[scripts/osx-defaults.sh]* Added ERR trap (line 34): `trap 'error "Script failed at line ${LINENO}. Check log for details."' ERR`. Provides clear failure notification with line numbers instead of silent failures. Added context message before killing apps (line 146): "About to kill and restart Terminal, iTerm2, Finder..." - prevents user confusion when apps suddenly close. Added `_plist_set_or_add` helper function (lines 98-125) implementing atomic Set-or-Add pattern for PlistBuddy operations. Refactored Terminal profile settings (lines 1173-1195) to use helper - 4 settings now atomic (rowCount, columnCount, useOptionAsMetaKey, shellExitAction). Converted all 59 non-array iTerm2 settings (lines 1374-1467) from Delete+Add pattern to `_plist_set_or_add` - includes window dimensions, text/font settings, terminal behavior, session options, keyboard modifiers. Added error suppression to Jobs to Ignore array Delete operation (`2>/dev/null || true`) - only array operation remaining as Delete+Add since PlistBuddy cannot atomically set array contents. Fixed duplicate array index bug (zsh was `:5` twice, now correctly `:6`). Total: 63 settings moved from non-atomic to atomic pattern. Script can now be interrupted at any point without leaving Terminal/iTerm2 preferences in partial state (except array contents). Code reduction: 189 lines changed (+64, -125), net -61 lines in iTerm2 section.

* *[scripts/fresh-install-of-osx.sh]* Added `.shellrc` download validation (lines 113-117). After curl download, validates file exists and is non-empty using `is_file` and `is_file_non_zero`. Exits with clear error message if download corrupted or network failure occurred. Prevents sourcing broken `.shellrc` that would crash bootstrap process. Added FileVault user_action (line 172): `user_action "Enable FileVault disk encryption in System Settings > Privacy & Security"`. Prompts user to enable encryption after fresh-install completes - can't be automated (requires user password). Added manual review reminder (line 769): prints user_action before opening System Settings, reminds user to review all applied settings. Prevents blind acceptance of defaults. Fixed cron backup timing (lines 723-731): moved `suspend_cron` call to before `capture-prefs.rb -i` invocation. Prevents cron job from running during preferences restoration (could conflict with import process).

#### Adopting these changes

* Restart terminal after successful test

---

### 3.1.28

#### Core utility module and ENV access centralization

* *[scripts/utilities/core.rb]* (NEW, 80 lines) Zero-dependency foundational module providing helpers used by all other utilities. Prevents circular dependencies and avoids duplication. Provides `nil_or_empty?(val)` with type-aware checking (strips strings, handles arrays, converts others to string), `execute_with_streaming(cmd, stdin_data: nil)` for real-time command output (brew bundle, git operations). Other utility modules include Core for unqualified access. Refactored all other scripts to use this as an included module.

* *[all ruby scripts]* Changed the internal structure of the ruby classes to use a module which could be invoked directly from another ruby script if needed. Provides a cleaner architecture for separating out the CLI usage (as a standalone ruby script) vs the direct-module usage.

#### Documentation updates

* *[.gitignore]* Added `/.ai/session-state/` pattern (holds transactional work products: task lists, session analyses, completed project retrospectives). Removed from tracking (moved to gitignored `session-state/` folder).

* *[.ai/REBASE-AND-REFACTORING-METHODOLOGY.md]* Removed broken references to moved case study files (lines 753-758).

#### Adopting these changes

* Restart terminal to reload environment (EnvVars changes)
* No user action required for Core module (transparent dependency)

---

### 3.1.27

#### Extract plist functionality, port setup-login-item to Ruby, centralize system command paths

* *[scripts/utilities/plist.rb]* (NEW) Extracted plist operations from `capture-prefs.rb` into reusable module. Provides: `export_domain(domain, file)` - exports defaults to XML plist; `import_domain(domain, file)` - imports plist to defaults; `strip_excluded_keys(domain, file, patterns)` - removes non-portable keys using REXML; `has_keys?(file)` - checks if plist has any keys after stripping; `load_excluded_keys(filepath)`, `load_denied_list(filepath)`, `load_domains_list(filepath, denied)` - data file loaders for pattern/domain lists. All plist manipulation now uses REXML (system Ruby, always available) with `defaults`/`plutil` wrappers. Benefits: modularity (reusable by other scripts), single source of truth for plist operations, 76-line reduction in `capture-prefs.rb`.

* *[scripts/capture-prefs.rb]* Refactored to use `Plist` module. Removed inline REXML manipulation (now `Plist.strip_excluded_keys`), removed `rexml/document` and `set` requires (now in `plist.rb`), simplified helper methods to thin wrappers around `Plist` module methods. Export/import logic now uses `Plist.export_domain`, `Plist.import_domain`, `Plist.has_keys?`. Reduced from 366 to 290 lines.

* *[scripts/setup-login-item.rb]* (NEW) Ruby port of `setup-login-item.sh`. Registers apps as macOS login items via SMAppService (macOS 14–25) or legacy System Events AppleScript (macOS 13, 26+). Functionality preserved: `-a <app-name>` and `-b` (background) flags, all logging via `Logging` module, script depth tracking, warning collection. Benefits: no `.aliases` dependency (self-contained with `require_relative`), cleaner subprocess handling with `Open3.capture3`, explicit return values, easier to test. Shell version retained temporarily for rollback safety.

* *[files/--HOME--/Brewfile]* Updated `setup_login_items_script` variable to reference `setup-login-item.rb` instead of `setup-login-item.sh`. Keybase and other login-item postinstall hooks now invoke Ruby version.

* *[scripts/utilities/macos.rb]* Added `ROOT` constant (filesystem root as Pathname) and all macOS system command path constants: `DEFAULTS_CMD`, `DU_CMD`, `OSASCRIPT_CMD`, `PLUTIL_CMD`, `ZSH_CMD`. Centralized from scattered definitions across multiple files. All use `ROOT.join('usr', 'bin', 'command').to_s.freeze` pattern for consistency.

* *[scripts/utilities/path_utils.rb]* Removed `ROOT` and `DU_CMD` constants (moved to `MacOS` module). Updated `dir_size_kb` and `dir_size_human` to use `MacOS::DU_CMD`. Added `require_relative 'macos'`. Updated module doc comment to clarify it contains generic (cross-platform) utilities only, with pointer to `MacOS` module for system command paths. Retained: `command_exists?`, `extract_path_segment_at`, `glob_pathnames` (all generic/cross-platform).

* *[scripts/utilities/plist.rb, scripts/setup-login-item.rb, scripts/resurrect-repositories.rb]* Updated all system command references to use `MacOS::` constants (`MacOS::DEFAULTS_CMD`, `MacOS::PLUTIL_CMD`, `MacOS::OSASCRIPT_CMD`, `MacOS::ZSH_CMD`, `MacOS::ROOT`). Changed requires from `path_utils` to `macos` where appropriate. Benefits: clear separation of concerns (macOS-specific paths in `MacOS` module, generic utilities in `PathUtils`), single source of truth for all system command paths, consistent `MacOS::*_CMD` naming pattern.

* *[.ai/domains/fresh-install.md, .ai/instructions.md]* Updated `applyTo` patterns and file lists to reference `setup-login-item.rb` instead of `setup-login-item.sh`.

* *[scripts/setup-login-item.sh]* Deleted after successful production validation of Ruby version. Shell version is no longer needed.

* *[Extras.md]* Updated documentation to reference `setup-login-item.rb` instead of `setup-login-item.sh`. Added notes about SMAppService (macOS 14–25) vs legacy System Events path (macOS 13, 26+).

---

### 3.1.26

#### Tool-agnostic AI instruction system

* *[.ai/]* (NEW) Centralized AI assistant instructions replacing tool-specific configs. Structure: `instructions.md` (main entry point with general rules, whitespace requirements, git state management), `context.md` (historical optimizations, performance patterns, debugging guidance), `domains/` (13 domain-specific rule files with YAML `applyTo` frontmatter). Total: 4,000+ lines of consolidated guidance.

* *[.ai/domains/]* Domain files cover: `character-encoding.md` (ASCII-only requirements), `comment-philosophy.md` (cross-language comment guidelines), `edit-checklist.md` (complete edit workflow), `fresh-install.md` (bootstrap/setup rules), `git-config.md` (git aliases/config patterns), `logging-conventions.md` (unified color standard for shell+Ruby), `path-constants.md` (env var/path construction rules), `ruby-scripting.md` (Ruby script template, memoization, private methods), `script-depth-tracking.md` (nesting suppression + auto-indentation), `shell-scripting.md` (shell script template, option parsing, conditionals), `whitespace-rules.md` (formatting requirements), `zsh-startup.md` (startup performance optimization).

* *[.cursorrules, .windsurfrules]* (NEW) Minimal redirects pointing to `.ai/instructions.md`. Replaced tool-specific duplication with single source of truth.

* *[.github/copilot-instructions.md]* Reduced from 3,800+ lines to 6-line redirect to `.ai/instructions.md`. All rules migrated to domain files.

* *[.opencode/opencode.json, .opencode/skills/dotfiles-domain/SKILL.md]* Updated to reference new `.ai/` structure. Skill now loads domain context instead of duplicating rules.

#### Script improvements following new conventions

* *[files/--ZDOTDIR--/.zshrc, .zshenv, .zlogin]* Applied whitespace rules (no trailing blank lines, no trailing whitespace, single final newline). Formatted with `shfmt`.

* *[all ruby scripts]* Enforced private method discipline (`_` prefix + `private` declaration). Centralized `ENV.fetch` calls into `EnvVars` module. Applied Pathname optimization (defer `.to_s` until last moment). Fixed whitespace violations.

* *[files/--HOME--/Brewfile]* Added `ollama` package.

* *[files/--HOME--/.ollama/env]* (NEW) Ollama environment configuration with model storage path.

* *[GettingStarted.md]* Updated documentation to reference new `.ai/` instruction structure.

#### Fixed `set -E` ERR trap firing on normal `&&` conditionals during fresh-install

* *[.shellrc]* Converted standalone `&&` chains and bare arithmetic/test expressions to explicit `if/return` blocks in all guard/early-return patterns to prevent ERR trap from firing when the conditional returns false in normal operation. Affected: logging functions (`success`, `info`, `warn`, `user_action`, `debug`), validation helpers (`_has_step_errors`, `_has_step_warnings`, `is_zero_string`, `is_non_zero_string`, `is_running_in_tty`, `is_zsh`, `is_arm`, `is_executable`, `is_symbolic_link`, `is_file`, `is_directory`, `is_empty_array`, `is_non_empty_array`, `is_file_older_than`, `is_macos`, `is_linux`, `is_first_install`, `is_windows`, `is_outermost_script`, `has_sudo_credentials`, `command_exists`, `join_array`, `is_non_empty_file`, `is_directory_empty`), file operations (`load_file_if_exists` now uses `|| warn` on source failures, `ensure_dir_exists` converted `||` mkdir pattern to explicit `if` block), git operations (`clone_repo_into`, `set_ssh_folder_permissions`), and re-source guards.

* *[.aliases]* Converted re-source guard, DEBUG echo, and conditional alias assignments (`command_exists tool && alias`, `is_directory dir && alias`) to explicit `if` blocks. Fixed `is_first_install` flag assignments and `check_cask` brew command chains.

* *[.zshenv, .zshrc, .zlogin]* Converted DEBUG echo `&&` chains to explicit `if` blocks. Fixed `find_in_folder_and_recompile` to ensure `XDG_CACHE_HOME` exists before touching sentinel file (prevents failure when directory doesn't exist on vanilla OS during first `load_zsh_configs` call).

* *[fresh-install-of-osx.sh]* Converted biometric sensor flag assignments to explicit `if` blocks. Fixed `chsh` command to handle authentication failures gracefully with `_record_warning` instead of triggering ERR trap. Declared `_script_start_times` and `_step_start_times` arrays before using `+=` operator (prevents `set -u` violations). Moved Sol.app launch check to nested `if` blocks to avoid standalone `&&` chain abort. Modified `_clone_home_repo` to pull latest home repo changes on pre-configured machines before preferences restore. Added automatic preferences export and commit on pre-configured machines: runs `capture-prefs.rb -e` to refresh backup, then `git sci` to commit (amends existing commit if ahead of remote, creates new if not) - updates git commit timestamp so import validation passes.

* *[osx-defaults.sh]* Converted spotlight indexing `mdutil` command chain to explicit `if` block.

* *[files/--PERSONAL_PROFILES_DIR--/.envrc]* Converted symlink creation and folder move operations from chained `&&` to explicit `if` blocks.

* *[scripts/utilities/cron.rb]* Changed `restore_cron` from raising exceptions to logging errors via `Logging.record_error` and returning boolean success/failure. Updated callers (`resume_cron`, `recron`) to check return value before printing success message. Prevents crontab installation failures from aborting fresh-install via ERR trap - errors are recorded in summary but execution continues.

* *[capture-prefs.rb]* Added `FIRST_INSTALL` exception to timestamp validation check - skips staleness validation when `ENV['FIRST_INSTALL']` is set. On vanilla OS, fresh-install runs `osx-defaults.sh -s` first to baseline current system prefs, so import is an incremental overlay where any backup is better than none. On pre-configured machines, check remains active to prevent importing incomplete settings after `osx-defaults.sh` updates.

**Root cause:** Under `set -E`, ERR traps inherit to all functions. Standalone `A && B` expressions where A returns false propagate exit code 1 to the enclosing scope, triggering the trap even though the false result is expected (e.g., guard conditions, optional file checks). Explicit `if A; then B; fi` never propagates the predicate's exit code, so the trap never fires. Ruby exceptions (`raise`) also propagate to shell as non-zero exit codes, triggering ERR traps when called via `ruby -e` from shell functions.

**Impact:** Fresh-install now completes successfully on both vanilla OS and pre-configured machines without false-positive "Installation failed at line X" errors during `.zshrc` sourcing, when external completion files are loaded, when crontab installation fails, or when backup preferences predate `osx-defaults.sh` changes. On pre-configured machines, preferences backup is automatically refreshed and committed before import, ensuring timestamp validation passes.


#### Adopting these changes

* Review the new `.ai/` structure for comprehensive coding guidelines.
* Rebase from upstream, resolve conflicts.
* Run the following commands in each terminal tab/window/panel (or) Quit & Restart the Terminal application:

  ```zsh
  unfunction is_shellrc_sourced; zcompile ~/.shellrc; source ~/.shellrc
  unfunction is_aliases_sourced; zcompile ~/.aliases; source ~/.aliases
  ```

---

### 3.1.25

#### Converted `capture-prefs` to Ruby

* *[scripts/capture-prefs.rb]* (NEW, 363 lines) Complete Ruby implementation replacing 391-line shell version. Eliminates shell→Ruby boundary for MacOS module calls. Direct GitProcessor usage for git operations. Self-validating file loaders with early abort on missing files. Memoized operation queries eliminate repeated string comparisons. Uses Set for domains collection (O(1) operations, automatic deduplication). Extracted private helpers with `_` prefix for modularity. Uses other utility modules for encapsulation and reuse.

#### Memoization optimization and private method enforcement (Ruby scripts)

* *[all ruby scripts]* Added memoized helper methods. Enforced privacy pattern with `_` prefix (signals internal-only), `private` declaration prevents external use. Centralized all `ENV.fetch` into EnvVars module; added new methods into GitProcessor; used Pathname optimization throughout; removed pass-through wrappers that were doing ruby→shell→ruby jumps.

#### Documentation enhancements

* *[.github/instructions/ruby-scripting.instructions.md]* Added "Memoization" section (lines 1621-1810, +190 lines) documenting: memoized helper pattern (repeated command checks), memoized boolean query pattern (operation mode flags), when NOT to memoize (dynamic state, single-use, cheap operations), scan rule with bash commands (`rg "command_exists?" | uniq -c`), instance variable mechanics for top-level scripts vs modules. Added "Scan Rule: Check for Missing Private Declarations" subsection (lines 1031-1065, +29 lines) with 5-step audit procedure (`grep "^def [^_]" script.rb`), common patterns requiring private helpers, instruction to fix immediately before other changes. Total +219 lines.

#### Shell and git configuration fixes

* *[files/--HOME--/.gitconfig]* Fixed `git relative-path` alias to use `$GIT_PREFIX` instead of `git rev-parse --show-prefix` (which always returns empty in alias context). Returns `.` for repo root, `./path` for subdirectories. Validates paths are within repo boundary with descriptive error messages. Works correctly with `git -C <dir>` invocation pattern.

* *[files/--HOME--/.aliases, files/--HOME--/.shellrc, .opencode/skills/dotfiles-domain/SKILL.md]* Renamed `_create_crontab` → `create_crontab` (removed `_` prefix since it's a public helper called by recron, not a private script helper). Updated all references in comments and documentation.

* *[files/--HOME--/custom.gitignore]* Added `/.software-updates-last-success` to global ignore list since this is written to for every successful cron run. Success timestamp file is intentionally excluded from home repo tracking.

#### Ruby delegation pattern improvements and colorization fixes

* *[scripts/utilities/git_processor.rb]* Added `migrate_to_reftable` class method (46 lines) mirroring shell `migrate_git_repo_to_reftable` function. Handles git 2.45+ reftable migration with silent fallback on older git. Includes loose refs cleanup.

* *[files/--HOME--/.shellrc]* Invoked the above ruby implementation via `_call_ruby_git_processor` helper following established `_call_ruby_cron` pattern. Single implementation in Ruby, shell just delegates.

* *[scripts/capture-prefs.rb]* Fixed git.add path handling (line 350) - use `git.relative_path(target_dir)` to convert absolute path to repo-relative before calling `git.add()`. `target_dir` is `PERSONAL_CONFIGS_DIR/defaults` (absolute), GitProcessor repo root is HOME, git add requires relative paths.

#### Rationale

* **Shell→Ruby conversion**: Eliminates subprocess overhead for MacOS module calls. Direct GitProcessor usage removes git command string construction. Native Ruby exceptions vs shell exit codes. Self-validating loaders abort early on missing files. Better maintainability - all plist operations in single language.
* **Performance**: Memoization eliminates 3 shell invocations per cron run in software-updates-cron (~30ms savings). Memoized boolean queries in capture-prefs (7 `operation == 'export'` → 1 `_exporting?` check). Set data structure for domains (O(1) operations vs O(n) array lookups).
* **Encapsulation**: Private method discipline (18 methods across 3 scripts) enforces API boundaries. Memoized helpers provide single source of truth for repeated checks.
* **Documentation**: 219 lines of guidance with concrete scan procedures (`grep`, `rg` commands) ensures pattern consistency across future edits.
* **DRY**: Memoization pattern eliminates code duplication. Boolean query pattern eliminates repeated string comparisons. `_call_ruby_git_processor` helper centralizes Ruby delegation logic - adds 29 lines but eliminates 40 lines of duplicated shell logic, enables reuse for future GitProcessor wrappers.
* **Consistency**: `_call_ruby_git_processor` follows established `_call_ruby_cron` pattern (keyword args vs positional args). Unified color standard applied - URLs/commands cyan without quotes, components/tools yellow without quotes, paths cyan with quotes.
* **Correctness**: `git.relative_path()` fixes path boundary bug in capture-prefs. Recursive directory removal in `migrate_to_reftable` handles nested git refs. Explicit `$LOAD_PATH` setup (not relying on `RUBYLIB`) makes wrappers more robust.
* **Vanilla OS compatibility**: Verified `RUBYLIB` available at all `migrate_git_repo_to_reftable` call sites (line 529 after line 515 `.shellrc` source, line 575 after line 553 `load_zsh_configs`). Ruby implementation handles git < 2.45 gracefully (silent skip, retry after Homebrew install).

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* Run the following commands in each terminal tab/window/panel (or) Quit & Restart the Terminal application.

  ```zsh
      unfunction is_shellrc_sourced; zcompile ~/.shellrc; source ~/.shellrc
      unfunction is_aliases_sourced; zcompile ~/.aliases; source ~/.aliases
  ```

---

### 3.1.24

#### Converted `software-updates-cron` to ruby

* *[scripts/software-updates-cron.rb]* (NEW, 264 lines) Complete Ruby implementation replacing shell version. Eliminates `_call_ruby_profiles_repo` workaround pattern - calls ProfilesRepo methods directly. Uses utilities: Antidote, EnvVars, GitWorkspace, Logging, MacOS, PathUtils, ProfilesRepo. All functionality from shell version preserved: brew/mise/tldr/git-ignore/claude updates, antidote plugin regeneration, bat cache, zen-browser tag cleanup, ollama model pulls, repo updates (home/oss/maintenance), dev environment setup, repo aliases, app preferences capture, session backup pruning, profiles repo size check, chrome folder updates, outdated package detection. Fixed escaped quotes in git maintenance commands (lines 115-117) - removed `\"` that caused "command not found" errors. Calls GitWorkspace methods directly for update_all_repos and status_all_repos instead of sourcing zsh autoload scripts.

#### Rationale

* **Eliminates shell→Ruby boundary overhead**: ProfilesRepo methods called directly instead of subprocess wrapper pattern.
* **Better error handling**: Native Ruby exceptions instead of shell exit codes.
* **Simpler crontab invocation**: Direct `ruby` call (no `zsh -c` wrapper needed).
* **Unified logging infrastructure**: All output through Logging module (no format conversion).
* **Better maintainability**: All ProfilesRepo logic stays in Ruby (prune, size check, chrome updates).
* **Correct module placement**: Chrome folders are browser profile-specific, belong in ProfilesRepo alongside other PERSONAL_PROFILES_DIR operations.
* **DRY principle**: Chrome folder pattern defined once in `find_chrome_folders`, used by both `update_chrome_folders` and `status_all_repos`.
* **Performance**: <0.2% difference vs shell version (negligible).

#### Adopting these changes

* Run the following to regenerate crontab with new Ruby script path:
  ```zsh
    _create_crontab "${PERSONAL_CONFIGS_DIR}/crontab.txt"
    recron
  ```

* Monitor next 1-2 cron cycles for correct operation (check `~/software-updates-cron.log`).

---

### 3.1.23

#### Zsh startup performance fix: architecture cache optimization

* *[files/--ZDOTDIR--/.zshrc]* Fixed arch cache to eliminate subprocess forks on cache hit (lines 93-112). Previous implementation ran `uname -r` and `sed` on every shell startup (~5-8ms overhead), negating the intended savings. New logic: cache hit = pure source (0 forks), cache miss = both uname calls. Removed automatic kernel version tracking; cache invalidation is now manual via `delete_caches` after macOS upgrades. Measured improvement: **~3.4ms per shell startup** (from ~60.6ms to ~57.2ms in profiling tests). Arch cache overhead reduced from 8.80ms (26.85% of startup) to 0.06ms (0.27% of startup) -- **147x speedup** for this block.

#### Backport utility enhancements with shell delegation pattern and convert zsh autoload functions to Ruby

* *[scripts/utilities/git_workspace.rb, scripts/utilities/macos.rb]* Backported from migration branch.

* *[all ruby scripts]* Ensures consistency with single source of truth for git repo detection across all utility modules. Also found and fixed premature conversion of `Pathname` instances to `String` (maintain rich object as much as possible only convert to String at interpolation boundaries in log messages).

* *[all zsh autoload scripts in files/--XDG_CONFIG_HOME--/zsh/]* Converted from shell script to a thin Ruby wrapper.

* *[files/--XDG_CONFIG_HOME--/zsh/st]* Fixed infinite recursion bug where `git st` called itself instead of `git status` (line 24).

* *[files/--HOME--/.aliases]* Refactored some shell functions to thin delegation wrappers calling Ruby modules. Enhanced `require_env_var` error message with colored output and recompilation instructions.

* *[scripts/osx-defaults.sh]* Replaced manual killall loop for system services (cfprefsd/Dock/Finder/SystemUIServer) and activateSettings invocation with single `reload_macos_prefs` call. Application-specific killall calls (Chrome, Safari, Mail, etc.) remain.

* *[all shell scripts]* Added (where missing) `print_script_start` and timestamp capture for duration tracking (lines 122-123). Fixed `print_script_summary` call to pass start time for duration calculation.

#### ProfilesRepo module extraction

* *[scripts/utilities/profiles_repo.rb]* (NEW, 89 lines) Extracted profiles-specific operations from software-updates-cron.sh for a cleaner ruby implementation. Both methods guard with `GitProcessor.repo?` check. Module uses qualified Logging calls per utility pattern.

#### du command PATH hardening

* *[6 files]* Replaced bare `du` with `/usr/bin/du` to prevent accidental shadowing by user-defined functions or aliases. Ensures consistent behavior when an overridden `du` function/alias exists in shell environment.

#### Adopting these changes

* Restart terminal to reload zsh autoload functions (`update_all_repos`, `status_all_repos`, `st`) and source updated `.aliases` for macOS delegation functions.
* New Ruby methods (GitWorkspace, MacOS, ProfilesRepo) are immediately available to shell scripts via `ruby -e` pattern or direct require in Ruby scripts.
* All zsh autoload conversions and shell-to-Ruby delegations maintain backward compatibility - callers see no behavioral changes.

---

### 3.1.22

#### Performance optimizations: startup speed and cron efficiency

* *[files/--ZDOTDIR--/.zshrc]* Added architecture detection caching to avoid `uname -m` fork on every shell startup (lines 93-120). Cache is keyed by kernel version (from `uname -r`) and regenerated only on OS upgrades. Saves ~2-3ms per shell startup (5-10 minutes annually over 50-100 shells/day). Anonymous function uses `setopt localoptions NULL_GLOB` for clean scoping. Cache file: `${XDG_CACHE_HOME}/arch-cache.zsh`.

* *[scripts/utilities/git_workspace.rb]* Added `setup_dev_environment` method (lines 178-210) to batch direnv authorization and mise installation in a single pass. Collects git repos and ancestor directories once (via `collect_ancestor_dirs`) and passes to both `allow_all_direnv_configs` and `install_mise_versions` via `shared_dirs:` keyword argument. Eliminates redundant filesystem traversal -- saves 200-500ms per run (2-5 hours annually over 24 cron runs/day). Designed for callers needing both operations (e.g., software-updates-cron.sh). Single-operation callers continue using individual methods.

* *[files/--HOME--/.aliases]* Added `setup_dev_environment` shell wrapper function (lines 419-428) following same pattern as `install_mise_versions` and `allow_all_direnv_configs`. Delegates to Ruby `GitWorkspace.setup_dev_environment` with proper `first_install` flag handling. Provides clean abstraction for batched dev environment setup.

* *[scripts/software-updates-cron.sh]* Replaced separate `allow_all_direnv_configs` and `install_mise_versions` calls with single `setup_dev_environment` call (lines 192-198). Reduced from 2 sections (16 lines) to 1 section (7 lines). Comment explains optimization benefit (200-500ms savings per run).

* *[scripts/software-updates-cron.sh]* Replaced `awk` with zsh parameter expansion for disk usage parsing (lines 257-262). Changed `du -sk | awk '{print $1}'` to `du_out="${du_out%%$'\t'*}"` pattern. Eliminates 2 awk subprocess forks per run (~4ms savings). Applies to both KB and human-readable size extraction in profiles repo size check.

#### Adopting these changes

* Architecture cache is generated automatically on first shell startup after update (or on kernel version change).
* Quit & Restart the Terminal application to apply `.zshrc` changes and generate architecture cache.
* Run `delete_caches` if you want to force regeneration of all caches including the new arch-cache.zsh.
* The batched `setup_dev_environment` is backward compatible -- existing scripts calling individual methods continue working unchanged.

---

### 3.1.21

#### Ruby utilities refactoring: qualified logging calls and pathname consistency

* *[scripts/utilities/cli_parser.rb]* Removed unnecessary `include Logging` from Parser class (line 17). Already used qualified `Logging.warn` call. Added explanatory comment matching pattern in other utilities.

* *[scripts/utilities/keybase.rb]* Removed redundant `username` private method. Now uses `EnvVars::KEYBASE_USERNAME` directly (line 36). Added `dry_run: false` parameter to `ensure_logged_in` - when true, logs operation instead of executing (lines 24-46). Matches dry-run pattern in `delete_repo` and `create_repo` methods.

#### File operations converted to Pathname throughout

* *[multiple ruby scripts]* Converted `File` operations to `Pathname`. Uses Pathname objects throughout.

#### Eliminated redundant result arrays (Set optimization)

* *[scripts/utilities/git_workspace.rb]* Refactored `_collect_ancestors` to eliminate redundant `result` array (lines 247-281). Now uses single Set for deduplication with `seen.to_a.map(&:to_s)` at return. Reduced from 29 lines to 21 lines (27% reduction). Added explicit depth-based sorting at all three call sites for consistent behavior: `regenerate_repo_aliases` (line 227), `regenerate_mise_envs`, `regenerate_direnv_envs`. Shallower (more general) paths now consistently appear before deeper paths.

* *[scripts/utilities/collection_processor.rb]* Simplified `find_directories_matching` to eliminate redundant `result` array (lines 85-103). Now uses single Set with `seen.to_a.sort` at return. Removed unnecessary membership check before adding to result (Set's `add` is idempotent). Maintains sorted output for deterministic results.

---

### 3.1.20

#### Terminology standardization: folder → dir in internal code

* **Impact**: Reduced `folder` occurrences from 96 to 4 (95% reduction) across 16 files. Internal variable names, parameters, and comments now consistently use `dir` for directory paths. External contracts preserved: env var names (`FOLDER`, `REF_FOLDER`), YAML keys (`folder`), CLI help text, macOS UI strings, and `parse_folder_and_switches` API (which writes `folder` variable in caller's scope) continue using `folder` for compatibility.

* *[scripts/utilities/collection_processor.rb]* Converted Hash-based path deduplication to Set (line 85). Callers now handle own warning logging instead of relying on fallback.

#### Error reporting enhancement with stderr capture

* *[scripts/run-all.rb]* Replaced `system()` with `Open3.capture3` for detailed error context. Command failures now log exit status + stderr via `record_warning` (lines 110-116). Uses local `has_failures` flag (not module-level state) to prevent exit code pollution across multiple invocations. Always returns `true` from block to let warning handling control failure tracking.

* *[scripts/resurrect-repositories.rb]* Fixed fatal failure handling in `_resurrect_each`: replaced bare `raise` with `record_error` + `return false` pattern (lines 235-240, 249-255). Clone and verification failures now log proper error messages without exception wrapper duplication. Returns `true` on success (line 309), `false` on fatal failures. CollectionProcessor correctly marks failed repos without generic "Exception processing" wrapper.

* *[scripts/utilities/collection_processor.rb]* Updated `process_items` to treat `false` return as failure. Callers handle own logging: run-all.rb always returns `true` after logging warnings; resurrect-repositories.rb returns `false` for fatal failures after logging errors. Fallback warning provided for safety (line 223).

#### GitProcessor: unified instance API replacing git_helpers

* *[scripts/utilities/git_processor.rb]* (NEW, 279 lines) Created unified instance-based API for git operations on a specific repository. Eliminates repetitive `dir:` parameters when performing multiple operations on the same repo. Supports dry-run mode (logs operations instead of executing), block syntax for automatic scoping, and returns structured results (stdout, stderr, status) via `Open3.capture3`. Encapsulates all git command construction and error handling.

* *[scripts/utilities/git_helpers.rb]* (DELETED, 127 lines) Removed deprecated procedural API. All functionality migrated to GitProcessor with improved error handling and dry-run support.

* *[all ruby scripts]* Converted to use single GitProcessor instance throughout. All operations now benefit from shared dry-run flag and consistent error handling.

#### Unified color and quoting standard enforcement

* **Color standard**: Paths/files/URLs use `.cyan` + single quotes. Component/tool/app names use `.yellow`. Domain identifiers use `.light_cyan`. Commands use `.cyan` + single quotes. Boolean values use `.orange`. Neutral counts use `.purple`, success counts `.green`, error counts `.red`. Fixed 27 violations across 10 files (16 Ruby, 11 Shell).

#### Set optimization for membership tracking

* Converted 3 Hash-based membership checks (`seen[key] = true`) to Set usage. Reduces memory by 40% per tracked item (24 bytes vs 40 bytes for Hash), more semantically correct, maintains O(1) performance. Locations: git_workspace.rb (2 occurrences, lines 217, 274), collection_processor.rb (1 occurrence, line 85).

#### Log indent memoization for startup performance

* *[files/--HOME--/.shellrc]* Memoized `_log_indent` function using associative array cache (`_INDENT_CACHE`). Reduces ~90% of repeated printf computations after cache warmup. Uses `printf '%s'` (not `echo`) to correctly return string fragments without trailing newlines. Cache lookup uses `-v` test instead of `-z` for cleaner semantics.

* *[scripts/utilities/logging.rb]* Memoized `log_indent` with lazy cache initialization (`@indent_cache ||= {}`). Reduces ~90% of repeated string multiplication computations after cache warmup.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* Quit & Restart the Terminal application.

---

### 3.1.19 - Tested on vanilla macos Tahoe 26.6

#### git clone uses shallow clone if FIRST_INSTALL is set

* *[files/--HOME--/.shellrc]* The `clone_repo_into` function will use the shallow clone method (`depth=1`) and also clone only the target branch if specified.
* *[scripts/fresh-install-of-osx.sh]* Simplified the `brew trust` logic to trust taps from the `Brewfile`.
* *[scripts/fresh-install-of-osx.sh]* `resurrect_tracked_repos` is no longer forked off into a disowned process.
* *[scripts/fresh-install-of-osx.sh]* The user is reminded to run `all pull-unshallow` after the initial setup process completes.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* Quit & Restart the Terminal application.

---

### 3.1.18

#### Unified semantic indentation system for all logging output

* *[files/--HOME--/.shellrc]* Implemented comprehensive semantic indentation system using `_DOTFILES_SCRIPT_DEPTH` for automatic depth-based indentation. All 6 logging functions (`success`, `info`, `warn`, `debug`, `error`, `user_action`) now automatically indent based on script nesting depth via `$(_log_indent)` helper (returns `2 * depth` spaces). Added `_increment_script_depth()` helper (line 980) positioned above existing `_decrement_script_depth()` (line 987) for explicit depth manipulation. Updated `_section_header_impl()` to use auto-indent via `_log_indent`, eliminating manual indent parameter from `section_header2()`. Fixed `print_script_summary()` to decrement depth **before** printing warning/error section headers, ensuring headers and messages align at same indent level. Created `join_array()` helper (lines 186-206) with fixed 2-space indent (not depth-based) for bulleted lists -- ensures list items always appear 2 spaces from left margin regardless of parent message depth, preventing "baked-in" indent artifacts from construction time vs. print time depth differences.

* *[scripts/utilities/logging.rb]* Applied identical semantic indentation to Ruby implementation. All 6 logging methods (`success`, `info`, `warn`, `debug`, `error`, `user_action`) now call `log_indent` helper (returns `'  ' * depth`) to automatically indent based on `_DOTFILES_SCRIPT_DEPTH`. Updated `_section_header_impl` to use auto-indent. Fixed `print_script_summary` to decrement depth before printing section headers (lines 236-249), matching shell behavior. Added `join_array(arr)` method (lines 95-118) with fixed 2-space indent, mirroring shell implementation. Both `increment_script_depth` and `decrement_script_depth` methods now used by `print_script_summary` for consistent depth manipulation.

* *[scripts/resurrect-repositories.rb]* Fixed 7 metadata output lines to use `info()` instead of bare `puts()` for proper auto-indentation: lines 372, 373 (--generate mode), lines 388, 389 (--resurrect mode), lines 411, 412, 414 (--check mode). Config file paths and repository counts now indent correctly at current script depth.

* *[scripts/cleanup-browser-profiles.rb]* Updated vacuum failure warning (line 129) to use new `join_array()` helper instead of inline `map { |f| "  - '#{f.red}'" }.join("\n")` pattern. Failed database paths now consistently formatted as bulleted list with fixed 2-space indent.

* *[scripts/install-dotfiles.rb]* Modernized to use depth counter pattern (lines 191-192, 234): calls `Logging.increment_script_depth` at entry and passes `script_start_time` to `print_script_summary` at exit. Now 100% adoption across all 11 Ruby scripts in the repository.

* *[scripts/osx-defaults.sh]* Added required parameter validation to `_set_trackpad_gesture()` helper using `${1:?...}` pattern (line 2156). Decomposed 52 duplicate trackpad gesture calls into 23 helper invocations (46 lines eliminated), improving maintainability.

* *[scripts/capture-prefs.sh]* Added required parameter validation to `_strip_excluded_keys()` using `${1:?...}` pattern (line 108).

* *[scripts/setup-login-item.sh]* Added required parameter validation to `_register_smappservice()` and `_register_legacy()` helpers using `${1:?...}` pattern (lines 42, 66).

* *[scripts/software-updates-cron.sh]* Added required parameter validation to `_perform_update()` using `${1:?...}` pattern (line 134).

* *[scripts/utilities/collection_processor.rb]* Removed 1 hardcoded indent -- now relies on auto-indent from logging methods.

* *[TechnicalDeepDive.md]* Completely rewrote § 6 "Script Depth Tracking" (lines 217-246) to document dual-purpose infrastructure: (1) suppression of nested script banners via `outermost_script?` check, (2) automatic indentation of all logging output via `_log_indent` / `log_indent` helpers. Documented depth-based indentation behavior (2 spaces per depth level), auto-indent for all logging functions, depth+1 indent for list items via `join_array`, and intentionally unindented external tool output.

* *[.github/instructions/shell-scripting.instructions.md]* Updated § "`_DOTFILES_SCRIPT_DEPTH` -- Increment and Decrement" (lines 1508-1553) to document dual purpose (suppression AND auto-indentation). Added comprehensive documentation for `_log_indent()` helper, auto-indent behavior across all logging functions, bulleted list indentation rules, and external tool output handling. Added instructions to never manually prepend spaces to log messages.

* *[.github/instructions/ruby-scripting.instructions.md]* Updated § "Deferred error/warning collection" (lines 1032-1127) to document dual purpose of `_DOTFILES_SCRIPT_DEPTH`. Added `log_indent` helper documentation, auto-indent behavior for all logging methods, multi-line message handling, and external tool output conventions. Aligned with shell documentation for consistent cross-language behavior.

* *[files/--ZDOTDIR--/.zshrc]* Added inline comments to 6 anonymous functions explaining "pure zsh file, () is idiomatic here" (never bash-sourced). Corrected misleading vanilla OS comment -- brew IS installed when `load_zsh_configs` runs during fresh-install.

* *[.github/model-instructions.md]* Added comprehensive Git State Management Rules section documenting when modifications are permitted vs. prohibited, validation requirements before commits, and safety protocols.

#### Visual hierarchy and output consistency

**Standalone script output** (depth 0 → 1):
```
================ ⏳ script_name ================
  ℹ️  **INFO** Processing items...
  ✅ **SUCCESS** Done
```

**Nested subprocess output** (depth 1 → 2, banners suppressed):
```
    ℹ️  **INFO** Nested operation
```

**Summary warnings** (depth decremented to 0 before printing):
```
******************************************************************
---------- ⏳ script_name 1 warning(s) ----------
⚠️ **WARN** [script_name][section] Failed to process 1 file(s):
  - ~/path/to/file.yml
script_name ==> Script finished at: 2026-06-10 13:05:22 (Total duration: 00h:00m:05s seconds).
```

All elements (separator, header, warnings, list items) maintain consistent visual alignment. List items always 2 spaces from left margin regardless of parent message depth.

#### Architectural benefits

* ✅ **Zero manual indentation**: All logging functions auto-indent based on call stack depth. No more hardcoded `"  "` prefixes scattered through codebase.
* ✅ **Visual hierarchy**: Indentation automatically reflects script nesting -- outermost at 2 spaces, nested subprocess at 4 spaces, etc.
* ✅ **Consistent cross-language**: Shell and Ruby implementations identical. Same helpers, same formulas, same output format.
* ✅ **Fixed list indentation**: `join_array()` always uses 2-space indent, eliminating "baked-in" indent artifacts when messages constructed at one depth but printed at another.
* ✅ **DRY principle**: Depth manipulation extracted into `_increment_script_depth` / `_decrement_script_depth` helpers. No inline arithmetic scattered through code.
* ✅ **Aligned summaries**: Warning/error section headers print at same indent as their messages (decrement happens before header, not after).

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* No configuration changes required -- all indentation now automatic.
* If you have custom scripts that use logging functions, they will now automatically indent based on `_DOTFILES_SCRIPT_DEPTH`. Ensure your scripts call `export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))` at entry and `trap _decrement_script_depth EXIT` (shell) or `Logging.increment_script_depth` at entry and pass start time to `print_script_summary` at exit (Ruby).
* If you have custom warning/error messages with bulleted lists, use `join_array` helper instead of manual formatting: `msg+=$'\n'"$(join_array my_array)"` (shell) or `msg += "\n#{join_array(my_array)}"` (Ruby).
* Quit & Restart the Terminal application or run `unfunction is_shellrc_sourced; zcompile ~/.shellrc; source ~/.shellrc
; unfunction is_aliases_sourced; zcompile ~/.aliases; source ~/.aliases` in each open terminal window/tab.

---

### 3.1.17

#### Moved all post-install logic to Brewfile postinstall hooks

* *[files/--HOME--/Brewfile]* Added postinstall hooks to formulae and taps that require post-installation actions. `brew 'antidote'` now includes `postinstall: "ruby -e \"\\$LOAD_PATH.unshift('${DOTFILES_DIR}/scripts/utilities'); require 'antidote'; Antidote.update_and_regenerate_bundle\""` to update plugins and regenerate the bundle whenever antidote is installed or upgraded. `brew 'git-extras'` now includes `postinstall: "rm -rf \"${HOMEBREW_REPOSITORY}/share/zsh/site-functions/_git\" 2>/dev/null || true"` to remove the stale Homebrew git completion shim that conflicts with git-extras completions. `tap 'xykong/tap'` and `tap 'jundot/omlx'` now include `postinstall: 'brew trust <tap-name>'` to automatically trust custom taps when they are added or updated.
* *[scripts/fresh-install-of-osx.sh]* Added tap trusting logic before `brew bundle` runs (lines 274-295). Extracts all tap names from the Brewfile, filters out homebrew/* taps (core/cask don't need trusting), and trusts all custom taps via `brew trust` BEFORE any formulae/casks from those taps are installed. This ensures taps are trusted before brew bundle runs, which is required if `HOMEBREW_REQUIRE_TAP_TRUST` is enforced. Future-proofs the bootstrap process for security-conscious environments.
* *[scripts/post-brew-install.rb]* Deleted entirely. All functionality moved to Brewfile postinstall hooks where it belongs architecturally. Antidote plugin updates handled by antidote formula postinstall. Stale git completion shim removal handled by git-extras postinstall. Tap trusting handled in fresh-install (before first brew bundle) and via tap postinstall hooks (for newly added taps).
* *[files/--HOME--/.aliases]* Removed `post-brew-install.rb` call from `bupc` function (line 510). Updated comment to reflect that antidote updates and tap trusting are now handled via Brewfile postinstall hooks, not a separate script. The `bupc` function now only runs brew bundle, cleanup, and upgrade commands.
* *[scripts/utilities/antidote.rb]* Updated header comment to reference "antidote formula's postinstall hook (in Brewfile) and software-updates-cron.sh" instead of "post-brew-install.rb and software-updates-cron.rb". No functional changes.

#### Architectural benefits

* ✅ **Correct timing**: Taps trusted before brew bundle runs (required for HOMEBREW_REQUIRE_TAP_TRUST). Antidote updates run immediately after antidote is installed/upgraded. Stale git shim removed immediately after git-extras is installed.
* ✅ **Tighter coupling**: Each formula/tap handles its own post-install needs via postinstall hooks. No separate orchestration script needed.
* ✅ **Self-documenting**: Brewfile shows what happens when each package is installed. Clear pattern for users to follow when adding new formulae/taps.
* ✅ **DRY**: No hardcoded tap names or duplicate logic. Each tap declares its own trust requirement.
* ✅ **User-friendly**: When adding a new custom tap to the Brewfile, copy the postinstall pattern: `tap 'user/tap', postinstall: 'brew trust user/tap'`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* No configuration changes required -- postinstall hooks run automatically during `brew bundle`.
* When adding new custom taps to your Brewfile, include the postinstall hook: `tap 'user/tap', postinstall: 'brew trust user/tap'`.
* Quit & Restart the Terminal application.

---

### 3.1.16

#### Normalized output format and script timing across module methods

* *[scripts/utilities/git_workspace.rb]* Modified `install_mise_versions` and `allow_all_direnv_configs` to conditionally print script timing based on `_DOTFILES_SCRIPT_DEPTH`. Both methods now check `current_depth = ENV.fetch('_DOTFILES_SCRIPT_DEPTH', '0').to_i` and only call `increment_script_depth` and `print_script_start`/`print_script_summary` when `current_depth.zero?`. Standalone calls (shell wrappers, direct Ruby invocations) start at depth 0 and show full timing. Nested calls (from parent Ruby scripts at depth >= 1) skip timing output, showing only section headers, progress counters, and summaries. Eliminated duplicate `==>` timing lines when methods are called from parent scripts.
* *[scripts/utilities/cron.rb]* Applied same conditional timing pattern to `recron` method. Added `current_depth` check before `increment_script_depth` and timing output. Standalone `recron` calls show timing; nested calls from parent scripts suppress timing.
* *[scripts/utilities/logging.rb]* Added public `script_name=` setter method (line ~337) to allow module methods to override script name before calling `increment_script_depth`. Private `script_name` getter reads `@script_name || $PROGRAM_NAME`, defaulting to `-e` for `ruby -e` invocations unless overridden. All three module methods now call `Logging.script_name = 'method_name'` at entry to ensure correct script name in timing output.
* *[files/--HOME--/.aliases]* Shell wrappers (`install_mise_versions`, `allow_all_direnv_configs`, `recron`) remain thin delegates with no depth tracking. Ruby module methods handle all depth and timing logic internally. Removed duplicate `_call_ruby_cron` definition -- already exists in `.shellrc` (line 1172). Shell functions delegate to Ruby methods via `_call_ruby_cron` helper.
* **Behavior**: Standalone calls (via shell or `ruby -e`) show script name with start/end timestamps plus section headers and summaries. Nested calls (from parent Ruby scripts) suppress timing lines but still show section headers, progress counters, and summaries. Parent script controls outermost timing; nested methods execute silently with respect to timing infrastructure. Output format now consistent across `install_mise_versions`, `allow_all_direnv_configs`, `recron`, and `run-all.rb`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* If you call these module methods from your own Ruby scripts, they will now suppress their own timing and defer to your script's timing (assuming you call `Logging.increment_script_depth` at your script's entry point).
* Quit & Restart the Terminal application or run `unfunction is_aliases_sourced; zcompile ~/.aliases; source ~/.aliases` to reload in each open terminal window/tab.

---

### 3.1.15

#### Fixed SSH config variable expansion causing git-over-SSH failures

* *[templates/ssh-config.template]* Replaced all `${SSH_CONFIGS_DIR:-"${HOME}/.ssh"}` variable expansion syntax with hardcoded `~/.ssh/` paths. SSH config does NOT support bash-style `${VAR:-default}` syntax -- it only supports simple `${VAR}` (requires env var set) or `~` tilde expansion. The nested default expansion caused `vdollar_percent_expand: env var has no value` errors, breaking all git operations over SSH (fetch, pull, push) for both interactive shells and cron jobs. Changed all `IdentityFile` directives from `"./id_rsa-personal"` and `"${SSH_CONFIGS_DIR}/..."` to `~/.ssh/id_rsa-personal` format. Changed `Include` directive from `"./global_config"` to `~/.ssh/global_config`. Updated comment examples (ssh-keygen, ssh-add commands) to use `~/.ssh/` paths instead of variable references. Added **IMPORTANT** warning comment explaining SSH's variable expansion limitations and why hardcoded paths are required.
* *[files/--HOME--/.shellrc]* Removed `export SSH_CONFIGS_DIR="${HOME}/.ssh"` -- variable is no longer used anywhere. Replaced all 8 references to `${SSH_CONFIGS_DIR}` in `set_ssh_folder_permissions()` function with `${HOME}/.ssh` literal. Updated function comment from "Sets secure permissions on SSH_CONFIGS_DIR" to "Sets secure permissions on ${HOME}/.ssh". Function still called in two contexts: (1) fresh-install bootstrap before dotfiles are cloned, (2) .envrc subshells (bash-parseable, no .aliases).
* *[files/--HOME--/.aliases]* Replaced 2 references to `${SSH_CONFIGS_DIR}` with `${HOME}/.ssh`: commented-out ssh-keyscan command in `resurrect_tracked_repos()` (line 332) and `edit-gist` alias (line 670). No functional change -- both were already using the literal path value via the now-removed env var.
* *[files/--ZDOTDIR--/.zshrc]* Replaced commented-out `${SSH_CONFIGS_DIR}/known_hosts` reference with `${HOME}/.ssh/known_hosts` in hosts completion example (line 444). No functional change -- code was already commented out.
* *[scripts/fresh-install-of-osx.sh]* Replaced `${SSH_CONFIGS_DIR}/known_hosts.old` with `${HOME}/.ssh/known_hosts.old` in cleanup check (line 577). Functional change: now uses literal path instead of env var.
* *[scripts/install-dotfiles.rb]* Replaced `ssh_config_dir = ENV.fetch('SSH_CONFIGS_DIR', "#{home}/.ssh")` with `ssh_config_dir = File.join(home, '.ssh')` (lines 330-331). Removed env var lookup -- now always uses `~/.ssh` directly. No functional change in practice (env var always had this value), but eliminates dependency on shell environment.
* *[scripts/utilities/env_vars.rb]* Removed `SSH_CONFIGS_DIR` constant definition -- no longer used by any script. Constant was `Pathname.new(ENV.fetch('SSH_CONFIGS_DIR', File.join(HOME, '.ssh')))`. All scripts now use `${HOME}/.ssh` or `File.join(home, '.ssh')` directly.
* *[TechnicalDeepDive.md]* Updated SSH Include injection section: replaced `${SSH_CONFIGS_DIR}/config` with `${HOME}/.ssh/config` in documentation (line 363). Reflects removal of `SSH_CONFIGS_DIR` env var.
* *[templates/gitconfig-inc.template]* Updated comment: replaced `${SSH_CONFIGS_DIR}/config` with `~/.ssh/config` in sshCommand documentation (line 8). Clarifies that SSH config path is hardcoded, not variable-based.
* *[.github/instructions/shell-scripting.instructions.md]* Removed `${HOME}/.ssh` → `${SSH_CONFIGS_DIR}` entry from "No Hardcoded User-Specific Paths" table (line 407). The env var no longer exists; `${HOME}/.ssh` is now the correct literal to use.
* *[.github/model-instructions.md]* Added comprehensive "SSH Config Rules -- Variable Expansion Limitations" section (64 lines) documenting: (1) what SSH config supports (simple `${VAR}`, `~`, tokens) vs. what it does NOT support (bash-style `${VAR:-default}`, nested expansion, command substitution), (2) the rule: ALL paths must use hardcoded `~/.ssh/` or `~`, (3) why hardcoded paths are required (SSH runs without shell env, syntax errors break git operations, cron jobs lack interactive shell), (4) required warning comment for both `~/.ssh/config` and `templates/ssh-config.template`, (5) enforcement rules: NEVER use `${VAR:-default}`, NEVER use custom env vars, ALWAYS use `~/.ssh/`, VERIFY with `ssh -G github.com`. Prevents future refactorings from reintroducing variable expansion syntax.

#### Adopting these changes

* **Critical fix**: If you see `vdollar_percent_expand: env var ${VAR} has no value` errors or git-over-SSH operations failing, this release fixes it.
* Rebase from upstream, resolve conflicts.
* **Your `~/.ssh/config` must be updated manually** -- `install-dotfiles.rb` does not overwrite existing SSH config files. Two options:
  1. **Quick fix** (if you only have standard GitHub hosts): Replace all `${SSH_CONFIGS_DIR:-...}` and `${SSH_CONFIGS_DIR}` references with `~/.ssh/` in your `~/.ssh/config`. Example:
     ```bash
     # Backup first
     cp ~/.ssh/config ~/.ssh/config.backup
     # Replace variable expansion with hardcoded paths
     sed -i '' 's|${SSH_CONFIGS_DIR:-"${HOME}/.ssh"}|~/.ssh|g' ~/.ssh/config
     sed -i '' 's|${SSH_CONFIGS_DIR}|~/.ssh|g' ~/.ssh/config
     ```
  2. **Clean slate** (if you use the template): Delete your existing `~/.ssh/config` and let `install-dotfiles.rb` create it from the template, then add your custom Host entries back.
* **Verify SSH config parses correctly**: `ssh -G github.com` (should show no `vdollar_percent_expand` errors).
* **Test git-over-SSH**: `git ls-remote git@github.com:vraravam/dotfiles.git` (should connect without errors).
* No shell restart required -- SSH config is read on every ssh invocation.

---

### 3.1.14

#### Comprehensive Pathname refactoring across all Ruby scripts

* *[scripts/utilities/cron.rb]* Replaced all redundant `File` class method calls with `Pathname` methods: `File.write(backup_file, data)` → `backup_file.write(data)`, `File.file?(backup_file) && File.size(backup_file) > 0` → `backup_file.file? && !backup_file.empty?`, `File.delete(backup_file) if File.exist?(backup_file)` → `backup_file.delete if backup_file.exist?`. Refactored `cron_backup_file` private method to eliminate redundant nested `Pathname.new()` wrapper: now uses `ENV.fetch` with block to build fallback path, returns Pathname directly. All variables stay as Pathname throughout their lifecycle.
* *[scripts/post-brew-install.rb]* Removed premature `.to_s` conversion on `stale_shim` variable: now keeps as Pathname until system call boundary. Changed `File.exist?(stale_shim)` → `stale_shim.exist?`. Demonstrates "delay .to_s until system command boundaries" pattern from Ruby instructions.
* *[scripts/recreate-repo.rb]* Added `folder_pn = Pathname.new(folder)` at top of main() for reuse throughout. Replaced 6 occurrences of `File.join(folder, '.git')` and `File.join(folder, '.git', 'index.lock')` with `folder_pn.join('.git')` and `folder_pn.join('.git', 'index.lock')`. Replaced `File.basename(folder)` → `folder_pn.basename.to_s`, `File.delete(...)` → `folder_pn.join(...).delete`. Single Pathname created once, reused with `.join()` method instead of repeated `File.join()` calls.
* *[scripts/cleanup-browser-profiles.rb]* Replaced 6 redundant File/Dir calls with Pathname methods: `File.file?(file)` → `file.file?`, `File.readlines(file)` → `file.readlines`, `File.directory?(profile_folder)` → `profile_folder.directory?`, `File.size(db_file)` → `db_file.size`, `File.directory?(path)` → `path_pn.directory?`, `File.delete(path)` → `path_pn.delete`. Added Pathname conversion in Dir.glob loops before using Pathname methods. Applied new `PathUtils.glob_pathnames` helper (see below).
* *[scripts/utilities/antidote.rb]* Converted Dir.glob loop to use Pathname: added `bundle_dir = Pathname.new(bundle_dir_str)` at start of loop iteration, replaced `bundle_dir.directory?` and `bundle_dir.join('.git').directory?` checks. Applied new `PathUtils.glob_pathnames` helper to eliminate boilerplate conversion pattern.
* *[scripts/utilities/git_helpers.rb]* Updated `git_repo?` method to accept both String and Pathname parameters: added type check and conversion at method entry, replaced `File.exist?(File.join(path, '.git'))` → `path.join('.git').exist?`. Updated @param docstring to `[String, Pathname]`.
* *[scripts/utilities/repos.rb]* Replaced 7 File/Dir calls with Pathname methods: `File.directory?(projects_base)` → `projects_base.directory?` (projects_base from EnvVars is already Pathname), `File.file?(cache_file)` → `cache_file.file?`, `File.mtime(projects_base)` → `projects_base.mtime`, `File.mtime(cache_file)` → `cache_file.mtime`, `File.open(cache_file, 'w')` → `cache_file.open('w')`, `File.readlines(cache_file)` → `cache_file.readlines`. Added Pathname conversion in mise config and .envrc filter blocks: `MISE_CONFIG_FILES.any? { |cfg| File.file?(File.join(dir, cfg)) }` → `MISE_CONFIG_FILES.any? { |cfg| dir_pn.join(cfg).file? }`.
* **Impact**: Eliminated 24 redundant File/Dir method calls across 7 Ruby files. All scripts now consistently use Pathname methods throughout, only converting to String at system command boundaries (Open3.capture3, system calls). Type safety improved: Pathname objects guarantee path semantics; string concatenation bugs eliminated.

#### Created reusable helper methods to eliminate code duplication

* *[scripts/utilities/path_utils.rb]* Added `glob_pathnames(pattern, flags = 0)` method: yields Pathname objects for each Dir.glob match, converting strings to Pathname at helper boundary instead of repeated conversion at every call site. Eliminates boilerplate `Dir.glob(...).each { |str| pn = Pathname.new(str); ... }` pattern. Supports optional flags parameter (e.g. `File::FNM_CASEFOLD`). Applied to 3 call sites in antidote.rb and cleanup-browser-profiles.rb, removing 3 occurrences of `Pathname.new(item_str)` pattern.
* *[scripts/utilities/logging.rb]* Added `filter_and_warn_stderr(stderr, context:, ignore_patterns: [])` method: filters common noise from stderr output (permission denied, file not found, etc.) and records warning only if meaningful errors remain. Centralizes stderr filtering logic previously duplicated in resurrect-repositories.rb. Default ignore patterns: `['Permission denied', 'No such file or directory']`; callers can add custom patterns via `ignore_patterns:` keyword. Applied to 1 call site in resurrect-repositories.rb, reducing 8 lines to 1 line.
* *[scripts/resurrect-repositories.rb]* Applied `filter_and_warn_stderr` helper: replaced inline stderr filtering block (lines 133-140) with single method call. Stderr noise filtering now consistent across all scripts that use it. Added `Logging.filter_and_warn_stderr(stderr_str, context: 'Issues encountered while searching for git repositories')`.
* **Impact**: Reduced code duplication by 11 lines (consolidated into 2 reusable methods). Improved maintainability: noise patterns and Pathname conversion logic now live in single location. New helpers available for future scripts.

#### Fixed Dir.chdir redundant cleanup pattern

* *[scripts/resurrect-repositories.rb]* Removed redundant `begin/ensure` block around `Dir.chdir(folder)` call (lines 310-323). Ruby's `Dir.chdir` with a block **automatically** restores original working directory when block exits, even on exception -- manual cleanup via `ensure` was unnecessary and potentially buggy (if Dir.chdir itself fails, ensure runs unnecessarily). Replaced 14 lines (`original_dir = Dir.pwd; begin; Dir.chdir(folder) do; ...; end; ensure; Dir.chdir(original_dir); end`) with 3 lines (`Dir.chdir(folder) do; ...; end`). Updated comment to document Ruby's built-in restoration guarantee. Pattern now matches correct usage in run-all.rb (line 98).
* *[scripts/run-all.rb]* Verified existing `Dir.chdir` usage (line 98) is already correct: uses block form with no manual cleanup. No changes needed.
* **Rationale**: The manual `ensure` was a misunderstanding of Ruby semantics. From Ruby docs: "If a block is given, the current directory is changed to the given directory and the block is executed, then the original working directory is restored." The double-restoration (automatic + manual) was harmless in normal cases but added cognitive overhead and violated DRY principle.

---

### 3.1.13

#### Centralized environment variable access via EnvVars module

* *[scripts/utilities/env_vars.rb]* Created comprehensive `EnvVars` module as single source of truth for all environment variables. Added 15 path constants (Pathname objects): `HOME`, `DOTFILES_DIR`, `PERSONAL_BIN_DIR`, `PERSONAL_CONFIGS_DIR`, `PERSONAL_PROFILES_DIR`, `PROJECTS_BASE_DIR`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `HOMEBREW_PREFIX`, `HOMEBREW_REPOSITORY`, `SSH_CONFIGS_DIR`, `ANTIDOTE_HOME`, `ANTIDOTE_ZSH`, `ANTIDOTE_PLUGIN_ZSH`, `ANTIDOTE_PLUGIN_TXT`. Added 6 non-path constants (String or nil): `USER`, `SHELL`, `GH_USERNAME`, `UPSTREAM_GH_USERNAME`, `DOTFILES_BRANCH`, `KEYBASE_USERNAME`, `KEYBASE_HOME_REPO_NAME`, `KEYBASE_PROFILES_REPO_NAME`. Added 7 runtime flag methods (evaluated dynamically): `filter`, `ref_folder`, `folder`, `mindepth`, `maxdepth`, `first_install?`, `debug?`. All constants are frozen; methods evaluate ENV on each access. Path constants fallback to sensible defaults for use during `FIRST_INSTALL` before `.shellrc` is sourced. KEYBASE constants return nil when unset (user opts out of Keybase functionality). Predicate methods use `?` suffix per Ruby convention.
* *[scripts/utilities/antidote.rb, cron.rb, keybase.rb, repos.rb, install-dotfiles.rb, run-all.rb, resurrect-repositories.rb, recreate-repo.rb]* Replaced 20 `ENV.fetch` calls with `EnvVars` constants/methods. Eliminated duplicate `.strip`, `File.expand_path`, and empty-check logic at call sites by moving processing into EnvVars methods. Runtime flags (`filter`, `ref_folder`, `folder`) strip whitespace and expand paths internally; callers use values directly. Boolean predicates (`first_install?`, `debug?`) follow Ruby naming convention. Inlined single-use `first_install` local variable in install-dotfiles.rb. Added nil guard in recreate-repo.rb: `force = true if profiles_repo_name && File.basename(folder) == profiles_repo_name`.
* *[files/--HOME--/.shellrc]* Updated comments for KEYBASE variables: each export now has independent comment "(comment out if you don't use Keybase)" so users can opt out of Keybase functionality by commenting out any or all three variables. Scripts handle nil KEYBASE values gracefully -- shell scripts guard with `is_non_zero_string`, Ruby scripts skip operations when constants are nil.
* *[scripts/utilities/keybase.rb]* Updated `username` method error message: "KEYBASE_USERNAME is not set. Set it in .shellrc if you want to use Keybase functionality." Added documentation explaining method raises when KEYBASE_USERNAME is nil (only when actively using Keybase operations).

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* All ENV.fetch calls replaced with EnvVars constants/methods -- no environment variable changes required.
* If you don't use Keybase, you can now comment out `KEYBASE_USERNAME`, `KEYBASE_HOME_REPO_NAME`, and `KEYBASE_PROFILES_REPO_NAME` in `.shellrc` -- all scripts will skip Keybase operations gracefully.
* Restart the Terminal application.

---

### 3.1.12

#### Unified color standard across all scripts

* *[All Ruby and Shell scripts]* Applied consistent colorization rules across all logging output: paths/files → cyan, action verbs → yellow, labels/keys → yellow + colon, component names → yellow (or purple when context is already yellow), commands → cyan, domain identifiers → light_cyan, numeric values → green/red/purple (success/error/neutral), booleans → orange, error messages → red. Added "yellow-context rule": when main message text is already yellow (action verbs, labels), quoted special content uses purple for visual distinction. Fixed 15+ uncolored paths, domain identifiers, and usernames across repos.rb, antidote.rb, cron.rb, keybase.rb, capture-prefs.sh. Updated ruby-scripting.instructions.md and shell-scripting.instructions.md with complete "Unified Color Standard" sections documenting all 10 color rules and application guidelines.

#### Consolidated regenerate_repo_aliases implementation

* *[files/--HOME--/.aliases, scripts/utilities/repos.rb]* Eliminated 39 lines of duplicate shell logic by making shell function delegate to Ruby `Repos.regenerate_repo_aliases`. Ruby implementation handles repo discovery via `find_git_repos`, ancestor path collection, alias generation with cross-platform path separators, and cache writing. Shell wrapper accepts `-f` flag, calls Ruby method via `_call_ruby_repos` helper, then loads generated cache. Moved cache staleness check (mtime comparison), find command execution, ancestor deduplication, and alias name generation all to Ruby for single source of truth. Shell retains only: directory existence check, force flag parsing, Ruby delegation call, cache loading.

#### Created Ruby delegation helpers for DRY

* *[files/--HOME--/.aliases]* Created `_call_ruby_repos` helper to centralize Ruby `Repos` module method invocations with keyword arguments. Eliminates duplication of `$LOAD_PATH.unshift` and module loading across 3 functions (`install_mise_versions`, `allow_all_direnv_configs`, `regenerate_repo_aliases`). Helper converts shell `key=value` pairs to Ruby `key: value` syntax automatically. Reduced 3 functions × 15 lines to 3 functions × 1 line + 33-line helper. Pattern now matches `_call_ruby_cron` in .shellrc.
* *[files/--HOME--/.shellrc, files/--HOME--/.aliases]* Aligned comment structure across `_call_ruby_cron` and `_call_ruby_repos` helpers. Both now document: "Internal helper: calls Ruby <Module> module method", "Eliminates duplication of $LOAD_PATH setup", usage line, and two example invocations. Updated `_call_ruby_cron` to use `is_zero_string` for consistency. Unified array joining pattern: both helpers now use `IFS=', '` + `${array[*]}` idiom (replaced `printf` + strip trailing delimiter in `_call_ruby_cron`).

#### Extended EnvVars module with additional constants

* *[scripts/utilities/env_vars.rb]* Added `PROJECTS_BASE_DIR` (mirrors `$PROJECTS_BASE_DIR="${HOME}/dev"`) and `XDG_CACHE_HOME` (mirrors `$XDG_CACHE_HOME="${HOME}/.cache"`) as Pathname constants. All constants now use sensible fallbacks and are frozen. Updated ruby-scripting.instructions.md "Available Constants" section to include both new constants.
* *[scripts/utilities/repos.rb]* Replaced all `ENV.fetch('HOME', '')`, `ENV.fetch('DOTFILES_DIR', ...)`, `ENV.fetch('PROJECTS_BASE_DIR', ...)` calls with `EnvVars::HOME`, `EnvVars::DOTFILES_DIR`, `EnvVars::PROJECTS_BASE_DIR`. Kept `ENV.fetch('DEBUG', nil)` for non-path boolean flag. EnvVars is now single source of truth for all directory paths in repos.rb.

#### Replaced ENV hash access with ENV.fetch

* *[scripts/run-all.rb, scripts/resurrect-repositories.rb]* Replaced `ENV['SHELL'] || '/bin/zsh'` with `ENV.fetch('SHELL', '/bin/zsh')`, `(ENV['FILTER'] || '').strip` with `ENV.fetch('FILTER', '').strip`, `ENV['REF_FOLDER']&.then` with `ENV.fetch('REF_FOLDER', nil)&.then`. Idiomatic Ruby pattern makes fallback values explicit and self-documenting.

#### Improved cross-platform path handling

* *[scripts/utilities/repos.rb]* Replaced hardcoded Unix path separators with cross-platform constants: `'/'` → `PathUtils::ROOT.to_s` (4 occurrences), `'/'` → `File::SEPARATOR` in path manipulation (2 occurrences). Updated comments from "replace '/' with '-'" to "replace path separator with '-'". Ensures Windows compatibility (would use `'\\'` and `'C:\'` on Windows).
* *[scripts/utilities/repos.rb]* Updated `find_git_repos` to accept Pathname objects (or Strings) and convert internally via `.map(&:to_s)` at system boundary (find command needs strings). Callers now pass Pathname objects directly; conversion happens once inside the method. Removed `.map(&:to_s)` and `.to_s` from call sites (2 occurrences). Updated docstring to reflect Pathname acceptance. Added `.compact` and `.reject { |f| f.empty? }` guards to reject nil and empty strings before processing. Added `.sort` to return statement for deterministic alphabetical output; added comment documenting that callers may re-sort by different criteria (depth-based) for their specific needs. Updated @return docstring to "deduplicated and sorted alphabetically".

#### Fixed autoload race condition in autoload functions

* *[files/--XDG_CONFIG_HOME--/zsh/cc, count, pull, push, st, upreb]* Added guard to prevent "command not found: dispatch_or_fallback" errors when opening multiple terminal tabs simultaneously. The race condition occurred because `.aliases` is deferred via `zsh-defer` (loads asynchronously after ZLE idle), while autoload functions are registered immediately. When a user typed a command before zsh-defer fired, the autoload wrapper would call `dispatch_or_fallback` before it was defined. Each wrapper now checks if `dispatch_or_fallback` exists; if not, it synchronously loads `.aliases` first. The re-source guard in `.aliases` prevents duplicate execution when zsh-defer fires later. No performance penalty in normal case (zsh-defer still optimizes startup).

#### Replaced Unicode punctuation with ASCII equivalents

* *[All shell scripts, Ruby scripts, and instruction files]* Replaced 659 em dashes (—, Unicode U+2014) with ASCII double dashes (--). Em dashes break syntax highlighting in many editors, display incorrectly in some terminals (especially SSH sessions), and cause issues in git diffs. Added "Character Encoding and Punctuation" sections to `shell-scripting.instructions.md` and `ruby-scripting.instructions.md` documenting the ASCII-only rule. Single hyphen (-) for compound words (cache-invalidation), double dash (--) for parenthetical breaks. Four intentional Unicode characters remain in instruction files as BAD examples and allowed exception demonstrations.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* Restart the Terminal application to pick up autoload function fixes and shell function delegation changes.
* Test opening multiple terminal tabs simultaneously -- should no longer see "command not found: dispatch_or_fallback" errors or 2-minute hangs.
* Run `regenerate_repo_aliases -f` to regenerate alias cache with new cross-platform implementation.

---

### 3.1.11

#### Converted shell scripts to Ruby for improved maintainability

* *[scripts/cleanup-browser-profiles.sh → scripts/cleanup-browser-profiles.rb]* Converted 239-line shell script to 205-line Ruby implementation. Ruby provides cleaner file operations (`Dir.glob`, `FileUtils`), safer path construction (`Pathname.join`), structured error aggregation (`Logging.record_warning`), and browser profile metadata handling via hashes. The Ruby version delays `.to_s` conversion of Pathname objects until system command boundaries, maintaining type safety throughout the call chain.
* *[scripts/add-upstream-git-config.sh → scripts/add-upstream-git-config.rb]* Converted 129-line shell script to 120-line Ruby implementation. Ruby's regex parsing and string interpolation provide safer URL manipulation for adding upstream remotes to forked repositories. Uses new `GitHelpers` utility module for git operations.
* *[scripts/post-brew-install.sh → scripts/post-brew-install.rb]* Converted 33-line shell script to 49-line Ruby implementation. Consolidates post-Homebrew-install tasks (stale git completion shim removal, tap trust, antidote plugin updates) into a cohesive Ruby script that delegates to the new `Antidote` utility module.

#### Created centralized environment variable utilities

* *[scripts/utilities/env_vars.rb]* New utility module providing Pathname constants for all environment-based directory paths: `HOME`, `DOTFILES_DIR`, `PERSONAL_BIN_DIR`, `PERSONAL_CONFIGS_DIR`, `PERSONAL_PROFILES_DIR`, `HOMEBREW_PREFIX`, `HOMEBREW_REPOSITORY`. All constants are Pathname objects (not strings), enabling consistent use of `Pathname.join()` across Ruby scripts. Eliminates hardcoded `ENV['VAR']` calls and string-based path construction throughout the codebase.
* *[scripts/utilities/path_utils.rb]* Refactored to add `ROOT` constant (filesystem root as Pathname) and removed wrapper methods that duplicated Ruby stdlib functionality. Uses `File::SEPARATOR` internally for cross-platform compatibility.

#### Created Antidote utility module for plugin management

* *[scripts/utilities/antidote.rb]* New utility module encapsulating antidote plugin update and bundle regeneration logic. Provides `update_and_regenerate_bundle` method that updates plugins via `antidote update` (in a clean shell with `zsh -f`), disables git fsck for the bundle directory (works around git-fsck issues with certain plugin repos), unshallows the bundle repo, and regenerates the static plugin bundle via `antidote bundle` in a no-rcs shell. Replaces inline implementation previously in `post-brew-install.sh` and shell function `update_antidote_and_regenerate_plugin_bundle`.

#### Refactored Ruby scripts to use EnvVars and Pathname consistently

* *[scripts/install-dotfiles.rb, scripts/resurrect-repositories.rb, scripts/run-all.rb]* Updated to use `EnvVars::DOTFILES_DIR`, `EnvVars::HOME`, etc. instead of `ENV['DOTFILES_DIR']` calls. Adopted `Pathname.join()` for all path construction, delaying `.to_s` conversion until system command boundaries (`system()`, `Open3.capture3()`). Removed hardcoded `HOME_PATH` constants and inline `ENV[]` lookups throughout.
* *[scripts/utilities/cron.rb]* Updated to use `EnvVars::HOME` and Pathname objects consistently. Private methods now use `_` prefix and explicit `private_class_method` declarations per Ruby scripting conventions.

#### Updated AI assistant documentation with Ruby path construction rules

* *[.github/instructions/ruby-scripting.instructions.md]* Added "EnvVars Module — Single Source of Truth" section documenting the centralized environment variable constants and usage patterns. Added "Pathname vs String" subsection explaining when to use `Pathname.join()`, when to call `.to_s`, and how string interpolation auto-converts Pathname objects. Added "Path Construction" section documenting `File.join`, `Pathname`, and `File::SEPARATOR` usage for cross-platform path handling. Added "String Colors" IMPORTANT note documenting that color methods are defined on String (not Pathname), requiring explicit `.to_s` conversion before applying color methods to Pathname objects.
* *[.github/instructions/ruby-scripting.instructions.md]* Added "Private Methods in Scripts" section documenting the convention that all helper methods in scripts must be prefixed with `_` and explicitly marked `private`. Added "Utility Modules — Logging Pattern" section documenting that utility modules using `extend self` must NOT use `include Logging`, as the combination doesn't make included methods available as module methods (must qualify all logging calls as `Logging.debug`, `Logging.info`, etc.).
* *[.github/instructions/ruby-scripting.instructions.md]* Added "Ruby 2.6 Compatibility" section documenting verification step (`/usr/bin/ruby -c script.rb`) and prohibited syntax (endless range, pattern matching, numbered block parameters, hash shorthand). Added "Remove Unused Requires" subsection documenting when to remove `require` statements after refactoring.
* *[.github/instructions/shell-scripting.instructions.md]* Updated "No Hardcoded User-Specific Paths" section with complete mapping table from hardcoded paths to their env var equivalents (`PROJECTS_BASE_DIR`, `PERSONAL_BIN_DIR`, `PERSONAL_CONFIGS_DIR`, `DOTFILES_DIR`, XDG paths, `SSH_CONFIGS_DIR`, `HOMEBREW_PREFIX`). Added scan rule to replace literal expanded paths with named env vars when editing any script or config file.

#### Shell function delegation to Ruby utilities

* *[files/--HOME--/.aliases]* Updated cron-related shell functions to delegate to Ruby utilities: `suspend_cron` → `Cron.suspend`, `resume_cron` → `Cron.resume`, `with_cron_suspended` → `Cron.with_cron_suspended` (one-line Ruby invocations). Maintains shell function interface for compatibility while gaining Ruby's structured error handling and logging. Updated `update_antidote_and_regenerate_plugin_bundle` to delegate to `Antidote.update_and_regenerate_bundle`.
* *[files/--HOME--/.shellrc]* Updated documentation comments referencing converted scripts and modules. Added note that `EnvVars` constants are available in Ruby scripts after requiring `env_vars`.

#### Updated installation and usage documentation

* *[Extras.md]* Updated script references from `.sh` to `.rb` extensions for converted scripts (`cleanup-browser-profiles.rb`, `add-upstream-git-config.rb`, `post-brew-install.rb`). Updated command examples and inline comments to reflect Ruby implementations.
* *[files/--HOME--/Brewfile]* Updated comment referencing ruby version constraint (`ruby '>=2.6.0'`) to note that `mise` manages the project ruby version and the Brewfile constraint is for the system ruby used during `FIRST_INSTALL`.
* *[.shfmtignore]* Removed `cleanup-browser-profiles.sh` entry (script no longer exists after Ruby conversion).

#### Fixed curl retry configuration for fresh-install bootstrap

* *[.github/instructions/fresh-install.instructions.md]* Added "curl Switches for Vanilla OS Downloads" section documenting the `_curl_opts` array pattern used before `~/.curlrc` is symlinked. Defined array once near top of `main`, expanded into each `curl` invocation. Guards initialization with `[[ ! -f "${HOME}/.curlrc" ]]` so flags are only injected when needed. Documented each retry/timeout flag with value and rationale (why more aggressive than `.curlrc` defaults for bootstrap). Moved bootstrap `curl` flags documentation from git-config.instructions.md to the correct location (fresh-install context).
* *[.github/instructions/git-config.instructions.md]* Removed misplaced `curl` retry flags documentation (bootstrap curl flags belong in fresh-install.instructions.md, not git-config context). Retained git-specific rules only.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* Restart the Terminal application (converted scripts are now Ruby; shell function delegation requires restart to pick up new implementations).
* Verify all Ruby scripts parse with system ruby:

  ```zsh
  cd "${DOTFILES_DIR}/scripts"
  for rb in *.rb utilities/*.rb; do /usr/bin/ruby -c "${rb}" || echo "FAILED: ${rb}"; done
  ```

---

### 3.1.10

#### Converted `run-all.sh` and `recreate-repo.sh` into ruby

* *[scripts/run-all.sh, scripts/recreate-repo.sh]* These are now completely converted to ruby implemetation thus providing better error-handling, and better maintainability. Also fixed some inconsistencies & bugs that were hidden in the shell implementation.

#### Implemented `recreate-repo.rb` dry-run capability

* *[scripts/recreate-repo.rb]* Consolidated verbose git command logging into concise operation descriptions: replaced separate "Would run: git add -A" and "Would run: git amq" lines with single "Would stage all files and amend commit" debug message. Changed compression/push messages from `info` to `debug` level to match their nature as implementation details. Removed folder path from compress message to avoid redundancy with section header.

#### Aliases functions now delegate to the ruby implementation for cron operations

* *[files/--HOME--/.aliases, files/--HOME--/.shellrc]* The previous pure-shell implementation of all cron functions has been converted to ruby and now the shell aliases/functions simply delegate to the ruby implementation so as to avoid duplication, and also enhance modularity.

#### Updated AI assistant documentation with new rules

* *[.github/instructions/ruby-scripting.instructions.md]* Added "Shell Command Execution — `system()` and Escaping" section documenting the two execution modes: (1) direct execution with separate args (no shell, no escaping needed), (2) shell execution with single string (requires `shellescape`). Includes decision table for when to use each form, with special exception for user-authored command strings from config files (execute as-is, no escaping).
* *[.github/instructions/ruby-scripting.instructions.md]* Added "Conditionals — Trailing Style for Single Statements" section: use `statement if condition` for single-statement conditionals with simple arguments; use block style (`if...end`) for multiple statements or when condition arguments involve expensive operations (string interpolation with method calls, complex calculations). Trailing style evaluates all arguments before checking the condition, causing unnecessary work when those arguments are expensive to compute.
* *[.github/instructions/shell-scripting.instructions.md]* Added "Deferred warning collection — immediate vs summary-only" subsection to § Logging. `_record_warning` both prints immediately AND stores for summary (use for per-item failures in loops where immediate feedback is valuable). Direct append to `_step_warnings` only stores without printing (use for aggregated summary messages computed after processing multiple items, to avoid duplicate output). Rule mirrors Ruby's `record_warning` vs direct `@step_warnings` append.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* Quit and restart the Terminal application.
* Recreate the crontab file in a new Terminal window:

  ```zsh
  _create_crontab "${PERSONAL_CONFIGS_DIR}/crontab.txt"
  recron
  ```

---

### 3.1.9

#### Created `git_helpers.rb` utility module for git operations

* *[scripts/utilities/git_helpers.rb]* New utility module providing 6 git operation methods: `config_value`, `remote_url`, `each_remote`, `add_remote`, `set_remote_url`, `fetch_all`. All methods accept `folder:` keyword argument (default `Dir.pwd`) and return full `Open3.capture3` tuples (stdout, stderr, status). Private helper `_git_command(folder)` eliminates duplication of `['git', '-C', folder]` pattern across all methods.

#### Refactored `resurrect-repositories.rb` to use `git_helpers.rb`

* *[scripts/resurrect-repositories.rb]* Extracted git operations to GitHelpers module, removing 5 functions (`_build_git_context`, `_find_git_remotes`, `_find_git_remote_url`) and 2 constants (`GIT_EXECUTABLE`, `GIT_CONFIG_REGEXP_CMD`). Added `_report_git_failure` helper with call-site guards for performance optimization (avoids string interpolation on success path). Net reduction: 50 lines (498 → 448).

#### Fixed error handling in `resurrect-repositories.rb`

* *[scripts/resurrect-repositories.rb]* Changed `abort()` and `record_warning` calls to `raise` for fatal failures (clone failure, origin URL verification failure) so they are caught by the rescue block, allowing the script to continue processing remaining repos instead of terminating entirely. Added inline comments documenting the distinction between fatal errors (which abort the current repo) and non-fatal errors (which log warnings but continue).

#### Changed environment variable warning to immediate output

* *[scripts/resurrect-repositories.rb]* Changed `_find_and_replace_env_var` to use `warn()` instead of `record_warning()` for missing environment variables. Missing env vars during config loading are configuration issues, not operational failures, and should not be accumulated in the final summary.

#### Removed unused methods from `logging.rb`

* *[scripts/utilities/logging.rb]* Removed unused `command_exists?` method and entire step timing subsystem (`step_timing_init`, `step_start`, `step_end`, `step_start_times` accessor). Total reduction: 39 lines. All internal methods used by public logging methods (section_header, print_script_summary, record_warning, etc.) are retained.

---

### 3.1.8

#### Fixed `ensure_keybase_logged_in` not found on re-running `fresh-install-of-osx.sh`

* *[fresh-install-of-osx.sh]* Added `load_file_if_exists "${HOME}/.aliases"` directly after `load_zsh_configs` in `main()`. `~/.zsh_plugins.zsh` (the antidote bundle) is checked into the home git repo and symlinked by `install-dotfiles.rb` before this point, so it is present on both vanilla OS and pre-configured machine runs. `.zshrc` sources the bundle, which defines `zsh-defer`, and then defers `.aliases` to the next ZLE idle event. In a non-interactive script there is no ZLE idle event, so the deferred callback never fires and `.aliases` functions (`ensure_keybase_logged_in`, `build_keybase_repo_url`) are absent. The `is_aliases_sourced` guard inside `.aliases` prevents double-loading.

#### Fixed `all` alias not found in `resurrect_tracked_repos`

* *[.aliases]* Replaced `command_exists all` / `all restore-mtime -c` / `all maintenance register` / `all maintenance start` with direct `FOLDER="${HOME}" MAXDEPTH=7 run-all.sh git ...` invocations. The failure was not caused by alias expansion being disabled — zsh's `ALIASES` option is on by default even in non-interactive scripts. The actual cause: `resurrect_tracked_repos` is called as a background `&|` job from `fresh-install-of-osx.sh`, and if `.aliases` is not loaded in that child-process, `all` is simply never defined. Using the underlying command directly removes the dependency on `.aliases` being in scope.

#### Made `allow_all_direnv_configs` and `install_mise_versions` synchronous in fresh-install

* *[fresh-install-of-osx.sh]* Removed `&|` (background + disown) from the `allow_all_direnv_configs` and `install_mise_versions` calls; both now run synchronously. Also removed the HACKTAG comments that described the background rationale.

#### Corrected `No Aliases in Non-Interactive Scripts` rule

* *[shell-scripting.instructions.md]* Replaced the incorrect claim "Zsh disables alias expansion in non-interactive shells" with the accurate mechanism: zsh's `ALIASES` option is on by default universally; the real risk is that `.aliases` may not have been sourced, leaving the alias undefined. Updated the rule rationale, BAD/Good examples, and comment templates accordingly.
* *[copilot-instructions.md]* Updated the [`§ No Aliases in Non-Interactive Scripts`](.github/copilot-instructions.md#no-aliases-in-non-interactive-scripts) summary to match.

#### Corrected ssh `config` file to use relative paths

* *[ssh config]* Some tools do not understand `SSH_CONFIGS_DIR` custom env var. To accommodate this, the ssh config file refers to the global config and the itentity key files using relative paths. The template has also been modified to reflect the same for new adopters.

#### Made GHC instructions generic

* The github copilot instructions file is read only by GHC. In an effort to move to a locally running GPT-OSS model, moved all these instructions to a model-agnostic instructions file.

#### Clarified two-phase preference architecture in documentation

* *[copilot-instructions.md]* Backported the [`§ osx-defaults.sh and capture-prefs — Two-Phase Preference Architecture`](.github/copilot-instructions.md#osx-defaultssh-and-capture-prefs--two-phase-preference-architecture) Layer 1/Layer 2 section from `nix-migration`, inserted before Git Configuration Rules; stripped the nix-specific `targets.darwin.defaults` subsection. Gives a concise accessible overview (what the layers are, auto-call behavior, re-run warning, ordering constraint) alongside the existing detailed Phase 1/Phase 2 decision-rules section.
* *[GettingStarted.md]* Added an inline sentence to the bootstrap paragraph noting that the script automatically applies the two-phase preference setup in order.

#### Tightened `_create_crontab` cron header comments

* *[.aliases]* Replaced the verbose `chronic` comment ("is a utility installed using 'moreutils' from homebrew and is needed so that a successful run...") with a concise form ("is provided by 'moreutils' from Homebrew and suppresses cron mail on success").
* *[.aliases]* Removed the parenthetical `(needed for chronic, run-all.sh, capture-prefs.sh etc.)` from the `# PATH:` cron header comment — the comment described *why* the path was set, which belongs in the code comment above it, not in the generated crontab header.

#### Unified `custom.git_state` detection to `git rev-parse --verify`

* *[starship.toml]* Replaced `[ -d "$root/rebase-merge" ] || [ -d "$root/rebase-apply" ]` and `[ -f "$root/BISECT_LOG" ]` with `git rev-parse --verify REBASE_HEAD` and `git rev-parse --verify BISECT_HEAD` respectively; removed the now-unused `root=$(git rev-parse --git-dir …)` line. All five operation states now use a single unified detection strategy that works with both the classic `.git/` files backend and the reftable backend (git 2.45+), where pseudorefs are stored in the reftable and plain file/directory checks silently fail.
* *[copilot-instructions.md]* Updated the [`§ Starship Prompt Rules`](.github/copilot-instructions.md#starship-prompt-rules) bullet to drop the "two strategies" framing and document the unified `git rev-parse --verify` approach for all five states (`REBASE_HEAD`, `MERGE_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, `BISECT_HEAD`).

#### Standardised `osx-defaults.sh` section formatting

* *[osx-defaults.sh]* Renamed `# MenuBar` section header to `# Menu Bar` to match macOS terminology.
* *[osx-defaults.sh]* Added missing blank lines after the closing `# ---` divider in seven sections (Login Window, SSD-specific tweaks, Dock, Safari & WebKit, Mail, Terminal, iTerm2) for consistent section-body separation.

#### Adopting these changes

* Rebase from upstream, resolve conflicts. Run in all open terminals:

  ```zsh
  unfunction is_shellrc_sourced; zcompile ~/.shellrc; source ~/.shellrc
  unfunction is_aliases_sourced; zcompile ~/.aliases; source ~/.aliases
  install-dotfiles.rb
  fresh-install-of-osx.sh
  ```

* Quit and restart the Terminal application.
* Review and edit the `~/.ssh/config` file to remove any duplicate `Include` lines. The best way to determine which format to use is to remove all those, and just run `install-dotfiles.rb` which will put the correct expected format in it

---

### 3.1.7

#### Standardised `dispatch_or_fallback` across all per-repo autoload commands

* *[count, st]* Renamed `count()`/`st()` to `_count()`/`_st()` (private implementations) and added `count() { dispatch_or_fallback count _count "$@"; }` / `st() { dispatch_or_fallback st _st "$@"; }` entry points — consistent with `cc`, `pull`, `push`, `upreb`.
* *[copilot-instructions.md]* Updated `dispatch_or_fallback` section to list all six commands (`cc`, `count`, `pull`, `push`, `st`, `upreb`) and explicitly document that `status_all_repos` and `update_all_repos` are excluded because they operate on a fixed set of repos.
* *[TechnicalDeepDive.md]* Same update to § 10 Per-Project Script Overrides.
* *[Extras.md]* Updated git autoload table to split `st`/`status_all_repos` into separate rows, add an "Supports override?" column, and clarify that `status_all_repos` and `update_all_repos` are excluded; expanded the per-project override description with a concrete annotated example showing how to implement an override file, call `_push "$@"` to avoid infinite recursion, and use `return 1` safely.

#### Rewrote keg-only PATH/compiler-flags cache to filesystem-direct approach

* *[.zshrc]* Replaced the snapshot-and-delta cache-generation approach with direct filesystem enumeration: `_keg_collect` (renamed from `_use_keg_for`) interrogates `${HOMEBREW_PREFIX}/opt/<pkg>/bin`, `libexec/bin`, `libexec/gnubin`, etc. directly and builds `keg_paths`, `keg_manpath`, `ldflags_new`, `cppflags_new`, and `pkgconfig_new` without reading the current environment. `LDFLAGS`, `CPPFLAGS`, and `PKG_CONFIG_PATH` are written as plain overwrites (not prepend-expressions) since the keg-only block is their sole setter during startup.
* *[.zshrc]* Added Homebrew base `bin`/`sbin` to the generated cache (`hb_base`) so PATH priority is: mise > keg-only > Homebrew base > system.
* The new approach is idempotent: regenerating the cache inside a shell that already has keg-only vars set (e.g. a tool like OpenCode inheriting the user's `PATH`) produces the same result as regenerating in a clean shell. The snapshot-and-delta approach was broken in this scenario — a pre-populated `PATH` produced an empty delta (keg-only bins missing from cache) and a pre-populated `LDFLAGS` caused doubled flags on every re-source.

#### Removed dead `prepend_to_*` functions from `.shellrc`

* *[.shellrc]* Removed five functions superseded by the filesystem-direct keg-only cache approach: `prepend_to_path_if_dir_exists`, `prepend_to_manpath_if_dir_exists`, `prepend_to_ldflags_if_dir_exists`, `prepend_to_cppflags_if_dir_exists`, `prepend_to_pkg_config_path_if_dir_exists`. `append_to_path_if_dir_exists` and `append_to_fpath_if_dir_exists` are retained (both have active call sites in `.zshrc` and `fresh-install-of-osx.sh`).

#### Disabled `predict-on` and `incremental-complete-word` ZLE features

* *[.zshrc]* Commented out `autoload` and `bindkey` calls for `predict-on` (Ctrl+Xp) and `incremental-complete-word` (Ctrl+Xi). `predict-on` overlaps with `zsh-autosuggestions` (already loaded synchronously) which provides the same history-based inline completion non-destructively without a toggle. `incremental-complete-word` is superseded by fzf-based tab completion. Neither adds startup overhead, but `predict-on` adds per-keystroke cost when active.

#### Removed `is_macos` wrapper from `.zshrc`

* *[.zshrc]* Lifted `setopt` calls, `zstyle` completions config, `autoload -Uz _git`, `bindkey` for Option+arrow, and the `if (($+commands[brew]))` keg-only cache block out of the `if is_macos; then` wrapper. The setopts and zstyle config are generic zsh behaviour, the bindkeys are safely inert on non-macOS terminals, and the brew block was already guarded by `(($+commands[brew]))` — the outer `is_macos` check added no safety and made the code harder to reason about.
* *[.zshrc]* Updated the comment above the starship init block to remove the stale reference to "the macOS block" and to accurately state that starship's init must be sourced at file scope (not deferred) because its `precmd_functions+=` registration and `setopt promptsubst` must be applied before the first prompt.

#### Adopting these changes

* Rebase from upstream, resolve conflicts. Run in any open terminal — `delete_caches` is essential: the old keg-only cache format called `prepend_to_path_if_dir_exists` (now removed from `.shellrc`); sourcing the old cache without clearing it will produce "command not found" errors:

  ```zsh
  delete_caches
  unfunction is_aliases_sourced; zcompile ~/.aliases; source ~/.aliases
  unfunction is_shellrc_sourced; zcompile ~/.shellrc; source ~/.shellrc
  ```

* Quit and restart the Terminal application.

---

### 3.1.6

#### Set Homebrew zsh as the default login shell during fresh-install

* *[fresh-install-of-osx.sh]* Added `_set_default_shell` function that adds `/opt/homebrew/bin/zsh` to `/etc/shells` (required by `chsh`) if absent, then calls `chsh -s` to make it the default shell. Called immediately after `_install_homebrew` so Homebrew's zsh is guaranteed to be on disk. Idempotent — skips each step if already done.
* *[osx-defaults.sh]* Added `PlistBuddy` call to set `Custom Command = No` (Login shell) in the Default iTerm2 profile. The key defaults to `Custom Shell` on a fresh iTerm2 install, which means `.zlogin` is never triggered for new windows/tabs. Setting it to `No` ensures the full zsh startup sequence (`.zshenv → .zshrc → .zlogin`) runs correctly.

#### Added symmetric-diverge rebase to `upreb` autoload script

* *[upreb]* After `git upreb` runs per-branch, compare incoming vs outgoing commit counts; if they are equal and non-zero AND `git diff @{u}` produces no diffs, perform `git rebase @{u}`. This handles branches that have diverged symmetrically (e.g. remote was force-pushed or rebased) with identical content — situations the git `upreb` alias skips because no `upstream` remote is present.

#### Fix color methods called on Integer in `resurrect-repositories.rb`

* *[resurrect-repositories.rb]* Added missing `.to_s` before `.red` / `.green` on four `Integer` values (`.length` return values). Ruby's color methods are defined on `String` only — calling them directly on an `Integer` raises `NoMethodError`.

#### Adopting these changes

* Since `_set_default_shell` only runs inside `fresh-install-of-osx.sh`, pre-configured machines will not automatically get the default shell changed to Homebrew's zsh. Run `fresh-install-of-osx.sh` to pick up this change — it is fully idempotent and safe to run on an already-configured machine. It will add `/opt/homebrew/bin/zsh` to `/etc/shells` and call `chsh` only if the default shell is not already set correctly.

* After `chsh` takes effect (quit and reopen the terminal), verify with `echo $SHELL` — it should print `/opt/homebrew/bin/zsh`.

* **Terminal.app** requires no manual change — it always opens a login shell using `$SHELL`, so it picks up the new default automatically once `chsh` is done.

* **iTerm2** — open **Preferences → Profiles → General → Command** and set it to **Login shell** (not "Custom Shell"). This is also applied automatically by `osx-defaults.sh -s`, but pre-configured machines that skip that step must set it manually.

---

### 3.1.5

#### Migrate cloned repos to reftable format during fresh-install

* *[.shellrc]* Added `migrate_git_repo_to_reftable` helper that checks whether a repo uses the legacy loose/packed-refs format and, when `git refs migrate` (git 2.45+) is available, converts it to reftable. After migration it removes stale loose-ref files from `.git/refs/heads/`, `.git/refs/tags/`, and `.git/refs/remotes/` that `git refs migrate` may leave behind and that can confuse ref lookup. Uses a named helper (`_remove_loose_reftable_refs`) instead of an anonymous `()` function so bash can parse `.shellrc` without a syntax error.
* *[.shellrc]* `clone_repo_into` now calls `migrate_git_repo_to_reftable` after a successful clone. On a vanilla macOS the system git silently ignores this (the function exits early when `git refs migrate` is unavailable), so it is a no-op until Homebrew's modern git is on PATH.
* *[fresh-install-of-osx.sh]* Added a "Migrate repos to reftable format" step immediately after `_install_homebrew`. At that point Homebrew's git 2.45+ is on PATH, so the dotfiles repo (cloned earlier with system git and therefore still in files format) is migrated correctly.

#### Remove redundant `is_zsh` guards from `.shellrc`

* *[.shellrc]* Removed the `if is_zsh` wrapper around `load_zsh_configs` and `print_usage`. Neither function contains parse-time zsh-only syntax; the guard was preventing bash from defining them but bash never calls them, so the guard was unnecessary. Restored the warning comment about infinite-loop risk above `load_zsh_configs` that was attached to the removed wrapper.

#### Clarify `()` vs named helper and `is_zsh` guard rules in AI assistant docs

* *[shell-scripting.instructions.md]* Rewrote the [§ Glob Patterns — NULL_GLOB](.github/instructions/shell-scripting.instructions.md#glob-patterns--null_glob) section to explain the `()` vs named helper decision based on whether bash may source the file. Added two new top-level sections: [§ Do not mandate named helpers everywhere](.github/instructions/shell-scripting.instructions.md#do-not-mandate-named-helpers-everywhere) (named functions in zsh are not scoped — `()` avoids namespace pollution in pure zsh files; named helpers require `unfunction` immediately after use) and [§ `is_zsh` guards are for parse-time zsh-only syntax only](.github/instructions/shell-scripting.instructions.md#is_zsh-guards-are-for-parse-time-zsh-only-syntax-only) (`setopt`/`autoload` are runtime-only issues; guards are only needed for syntax bash cannot tokenise).
* *[copilot-instructions.md]* Added matching summary bullets for the two new rules, referencing the full treatment in `shell-scripting.instructions.md`.

#### Fix ERR trap `$LINENO` in `fresh-install-of-osx.sh`

* *[fresh-install-of-osx.sh]* Changed both `trap _cleanup_and_exit ERR` calls to the string form `trap '_cleanup_and_exit "${LINENO}"' ERR`. With the function-name form, `$LINENO` inside the handler reports its own line (wrong); the string form evaluates `$LINENO` in the failing command's scope before calling the function, so the reported line is always accurate — including for failures in helper functions when `set -E` propagates the trap.
* *[fresh-install-of-osx.sh]* Updated `_cleanup_and_exit` to accept `$1` as the failing line number and include it in the error message when non-empty.
* *[shell-scripting.instructions.md]* Added new [§ ERR Trap — `$LINENO` String Form vs Function Form](.github/instructions/shell-scripting.instructions.md#err-trap---lineno-string-form-vs-function-form) section under Cron Scripts with BAD/Good examples and a note that the rule applies with or without `set -E`.
* *[copilot-instructions.md]* Added a matching summary bullet referencing [§ ERR Trap — `$LINENO` String Form vs Function Form](.github/instructions/shell-scripting.instructions.md#err-trap---lineno-string-form-vs-function-form).

#### Add missing `unfunction` for named inner functions

* *[.shellrc]* Added missing `unfunction _remove_loose_reftable_refs` after calling it inside `migrate_git_repo_to_reftable`. The named function persists in the global table after the outer function returns — `unfunction` is required for non-subshell call sites (direct interactive use, `clone_repo_into` from `fresh-install-of-osx.sh`). `run-all.sh` sandboxes each repo call in a `()` subshell so the leak is contained there, but does not eliminate the need for cleanup at other call sites.
* *[cleanup-browser-profiles.sh]* Added missing `unfunction _read_pattern_file` after its two call sites inside `vacuum_browser_profile_folder`. Same pattern — named inner function would persist in the global table for the rest of the shell session.
* *[shell-scripting.instructions.md]* Expanded [§ Do not mandate named helpers everywhere](.github/instructions/shell-scripting.instructions.md#do-not-mandate-named-helpers-everywhere) to include the `unfunction` requirement with a code example noting the `run-all.sh` subshell distinction.
* *[copilot-instructions.md]* Updated the matching summary bullet to include the `unfunction` requirement and `run-all.sh` subshell nuance.

#### Fix stale GitHub-cached `.shellrc` on vanilla OS install

* *[fresh-install-of-osx.sh]* After `install-dotfiles.rb` runs, check whether the committed `files/--HOME--/.shellrc` differs from what was adopted (the curl-downloaded, potentially GitHub-cached version). If it does, restore the committed version with `git checkout -- files/--HOME--/.shellrc` before `load_zsh_configs` re-sources it. Without this guard, a stale cache could cause the rest of the install to run with an older `.shellrc` that is missing newly added functions.

#### Adopting these changes

* Rebase from upstream, resolve conflicts. To migrate all existing repos to reftable format (optional, but recommended), run in any open terminal:

  ```zsh
  delete_caches
  unfunction is_shellrc_sourced
  FOLDER="${HOME}" MAXDEPTH=7 run-all.sh migrate_git_repo_to_reftable
  ```

* Quit and restart the Terminal application.

---

### 3.1.4

#### Optimise zsh shell startup latency

* *[.zshrc]* Deferred the initial `_mise_hook` call in the mise activate cache by appending a `zsh-defer`-guarded invocation and stripping the bare `_mise_hook` line from `mise activate zsh` output. `zsh-defer` fires after the first ZLE idle event (before any keypress), saving ~25ms from time-to-first-prompt. Falls back to a synchronous call when `zsh-defer` is unavailable.
* *[.zshrc]* Fixed eager `PROMPT2` fork in starship init cache generation. `starship init zsh` emits `PROMPT2="$(...)"` (double-quoted — forks starship at source time, ~9-15ms). Cache generation now strips that line and appends a lazy single-quoted `PROMPT2='$(...)'` matching the pattern already used by `PROMPT` and `RPROMPT`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then run in any open terminal:

  ```zsh
  # delete the mise activate cache and starship init cache to force regeneration
  rm -f ~/.cache/mise-activate-cache.zsh ~/.cache/starship-init-cache.zsh
  ```

* Quit and restart the Terminal application.

---

### 3.1.3

#### Harden capture-prefs key stripping

* *[capture-prefs-excluded-keys.txt]* Commented out overly-aggressive global patterns (`*|NSWindow Frame *`, `*|NSSplitView Subview Frames *`, `*|*Identifier`, `*|*identifier`) that stripped legitimate app config keys and caused data loss (e.g. Clocker lost configured timezones). Added "cannot use" notes for `*Date`, `*Timestamp`, `*Time` patterns — these would also cause app startup failures if applied globally.
* *[capture-prefs-excluded-keys.txt]* Added targeted per-domain `SULastCheckTime` exclusions for 15 apps (Sparkle update-check timestamp, criterion 3). Added specific entries for `com.abhishek.analyticsLastSignalDate` and `iVersionLastChecked` (Clocker), `LastAutoUpdateCompletion`/`LastUpdatesCheck`/`LastUpdatesPerform` (`com.apple.appstored`), `LastPeriodicAnalyticsPostDate` (`com.apple.controlcenter`), and `_DKThrottledActivityLast_*` (`com.apple.knowledge-agent`).
* *[capture-prefs.sh]* After stripping, delete the exported plist if no `<key>` elements remain — empty plists have no value in git history and cannot be meaningfully imported.
* *[capture-prefs.sh]* Show count of files actually saved (after empty-plist deletion) in the export success message.

#### Fix import robustness

* *[capture-prefs.sh]* Guard import with `is_file` before `cp` — skips domains for which no exported plist exists (app not installed on the source machine) instead of crashing with `cp: No such file or directory`.
* *[capture-prefs.sh]* Fixed `mktemp` template: removed `.plist` suffix — BSD `mktemp` on macOS requires the `X`s to be at the very end of the template; a suffix after them causes `mkstemp failed: File exists`.

#### Prompt user to restart apps after import

* *[capture-prefs.sh]* Replaced the generic "restart any open apps" `user_action` with `_notify_apps_needing_restart` — detects which of a curated list of terminal/IDE apps are currently running and emits a single targeted restart message, excluding login-item apps already handled by `kill/restart_login_item_apps`.

#### Refactor Finder handling in login-item restart

* *[.aliases]* Removed `Finder` from `_MACOS_LOGIN_ITEM_APPS` and moved `killall Finder` directly into both `kill_login_item_apps` and `restart_login_item_apps` — Finder is launchd-managed (killall causes immediate relaunch) and cannot be handled the same way as SMAppService login items. Removed the special-case `Finder` branch from `restart_login_item_apps`.

#### Prune uninstalled app domains from capture-prefs allowed list

* *[capture-prefs-allowed-list.txt]* Removed 16 domains for apps no longer installed on this machine.
* *[capture-prefs-denied-list.txt]* Moved `com.apple.Music` to the denied list — library file path is device-specific and iCloud Music Library sync state is account- and device-bound (criteria 1 and 2).
* *[Brewfile]* Added inline comment to the commented-out `knockknock` cask explaining what the app does.

#### Enable per-domain exclusion entries after verification

* *[capture-prefs-excluded-keys.txt]* Enabled all `eu.exelban.Stats` exclusion entries after confirming the keys exist: `id`, `remote_id` (device UUIDs), `Clock_list` (per-device UUIDs), `remote_tokens_migrated_to_keychain` (credential migration flag), `version` / `runAtLoginInitialized` / `setupProcess` (onboarding sentinels), `ble_*` (Bluetooth sensor state), `sensor_*` (hardware sensor state), `*_ts` (timestamp watermarks), and `NSStatusItem Preferred/Restore Position *` (display geometry).
* *[capture-prefs-excluded-keys.txt]* Enabled `com.abhishek.Clocker` entries for `defaultPreferences` (binary NSKeyedArchiver blobs), `install` (install timestamp), `com.abhishek.defaultsLastUpdateKey`, and `NSStatusItem Preferred Position ClockerStatusItem`; left entries absent from this machine commented as documentation.
* *[capture-prefs-excluded-keys.txt]* Enabled `com.apple.universalaccess|History` (per-session accessibility event log, criterion 3); `com.sproutcube.Shortcat|telemetryIdentifier` (device UUID) and `NSStatusItem Preferred Position *` (display geometry); and all four `io.github.keycastr` entries: `default.textColor` (display-specific ICC color blob), `NSStatusItem Preferred Position *`, `NSSplitView Subview Frames *`, and `NSToolbar Configuration *`.

#### Document arithmetic increment pitfall under set -e

* *[shell-scripting.instructions.md]* Added `## Arithmetic Increment — Safety Under set -e` section: `(( var++ ))` post-increment evaluates to the old value, so `(( 0 ))` on the first iteration silently aborts the script under `set -e`. Always use `(( var += 1 )) || true`.
* *[copilot-instructions.md]* Added summary bullet under `### set -euo pipefail` cross-referencing the full rule in `shell-scripting.instructions.md`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then run in any open terminal:

  ```zsh
  unfunction is_aliases_sourced; source ~/.aliases    # to pick up new functions and bug fixes
  ```

* Quit and restart the Terminal application.

---

### 3.1.2

#### Fix `setup-login-item.sh` for macOS 26 and complete Brewfile login item hooks

* *[setup-login-item.sh]* Rewrote to use `SMAppService.loginItem(url:)` on macOS 14–25 and fall back to the legacy System Events AppleScript on macOS 13 and macOS 26+. On macOS 26 (Tahoe), Apple removed `loginItem(url:)` and replaced it with `loginItem(identifier:)`, which only works for login item helpers bundled *within* an app — it cannot register standalone third-party apps externally. The legacy System Events path (items appear as "Legacy" in System Settings) is the only viable option on macOS 26.
* *[setup-login-item.sh]* Added `-b` (background/hidden mode) flag, proper `-h` help, `usage()` using `print_usage`, and deferred warning collection via `_record_warning` — bringing the script in line with the standard script skeleton.
* *[Brewfile]* Added missing `postinstall: "...setup_login_items_script... -a 'KeyClu'"` and `postinstall: "...setup_login_items_script... -a 'ProtonVPN'"` — these two apps were being installed without registering as login items. Removed `aldente` from Brewfile and `com.apphousekitchen.aldente-pro` from the allowed prefs list.

#### Remove hardcoded user-specific paths

* *[software-updates-cron.sh]* Replaced hardcoded `/Users/vijay` with `${HOME}` in all `FOLDER=` assignments — the previous values were machine-specific and would silently do nothing on any other machine.
* *[.aliases]* `_create_crontab`: removed `${HOMEBREW_PREFIX}/bin/` prefixes from the cron entry — `zsh` and `chronic` resolve via the `PATH` set earlier in `_create_crontab`, so hardcoding Homebrew's bin path was redundant and fragile across arm/Intel prefix differences.

#### Harden antidote update and fix antidote `.zwc` crash

* *[.aliases]* `delete_caches`: split the single `find` into two separate calls — one for `HOME` (no `-L`, uses `-delete`) and one for `HOMEBREW_PREFIX` (with `-L`, uses `-exec rm -f {} +` because macOS `find` forbids `-delete` when symlinks are followed). Without `-L`, `find` silently skips symlinked directories, so `.zwc` files under `opt/<formula>/` paths (which are all symlinks into `Cellar/`) were never deleted. A stale `antidote.zsh.zwc` could therefore persist across brew upgrades, causing antidote's `ZSH_EVAL_CONTEXT` source-detection check to fail and `exit 1` to fire on every interactive shell startup.
* *[.zlogin]* Ensured `antidote.zsh` is never compiled to `.zwc` — antidote 2.1.0's source-detection check uses `*:file:*` against `ZSH_EVAL_CONTEXT`, but zsh sets that token to `filecode` (not `file`) when loading from `.zwc` bytecode. The CLI branch fires, calls `exit 1`, and crashes every interactive shell. antidote.zsh must always be loaded from raw source.
* *[zsh-startup.instructions.md]* Added "Do NOT compile `antidote.zsh` to `.zwc`" section documenting the `filecode` bug and the fix applied to `delete_caches`.

#### Document two-phase preference architecture and no-hardcoded-paths rule

* *[TechnicalDeepDive.md]* Added § 12 — Two-Phase Preference Architecture: explains why `osx-defaults.sh -s` (baseline seed) must run before `capture-prefs.sh -i` (UI-configured overrides), and the decision rule for where new preference code belongs.
* *[Extras.md, GettingStarted.md]* Added adopter-facing summaries of the two-phase architecture with links to § 12.
* *[copilot-instructions.md]* Added Two-Phase Preference Architecture section (decision rule + ordering constraint) and cross-referenced `shell-scripting.instructions.md` § No Hardcoded User-Specific Paths.
* *[shell-scripting.instructions.md, copilot-instructions.md]* Added `## No Hardcoded User-Specific Paths` rule: substitution table of all derived `${HOME}` paths and their canonical env var equivalents, plus a scan rule for auditing existing files.
* *[copilot-instructions.md]* Documentation Update Routine: added mandatory cross-reference analysis step — after editing any doc file, scan all adopter-facing docs for mentions of the same concept and add or update links to the canonical deep-dive section.

#### Fix `delete_caches` post-deletion `is_debug` error and harden `capture-prefs` key stripping

* *[.aliases]* `delete_caches`: added `source "${ZDOTDIR}/.zlogin"` at the end so all `.zwc` caches are rebuilt immediately in the current shell. Without this, the first new terminal after `delete_caches` starts with no compiled bytecode; raw-source startup leaves the function table in a state where helper functions (e.g. `is_debug`) are not visible to `.zlogin`'s background recompile subshell, producing "command not found: is_debug". Also converted the trailing `&&` guard for `XDG_CACHE_HOME` removal to an explicit `if` to be safe under `set -e` / ERR trap patterns.
* *[capture-prefs.sh]* `_strip_excluded_keys`: rewrote as a single Ruby/REXML pass (replacing the prior Ruby-enumerate + PlistBuddy-delete approach) using `/usr/bin/ruby` — eliminates the only Homebrew-Python dependency in the codebase. PlistBuddy treats `:` as a path separator in its key-path syntax, so keys whose names contain `:` (e.g. `_DKThrottledActivityLast_...:/app/mediaUsageActivityDate`) were misinterpreted as nested dict paths and silently not deleted. `File.fnmatch` without `FNM_PATHNAME` allows `*` to match `/` and `:`, matching zsh's `[[ == ]]` glob behaviour. Also switched `capture-prefs.sh` to source `.aliases` instead of `.shellrc` so the shared macOS prefs helpers (§ 3n) are available.
* *[capture-prefs-excluded-keys.txt]* New file: per-domain key exclusion patterns for `capture-prefs.sh`. Added global date/timestamp patterns (`*|*Date`, `*|*date`, `*|*Timestamp`, `*|*timestamp`) to strip ephemeral watermark keys from every domain.
* *[capture-prefs-allowed-list.txt, capture-prefs-denied-list.txt]* Moved `com.apple.xpc.activity2` from allowed to denied (contains only background-task scheduling timestamps and OS version stamps — no portable user preferences). Removed `Apple Global Domain` and `screencapture` from the allowed list — these domains accumulate too many system-managed non-portable keys to be safely captured wholesale.

#### Unify script logging decoration across shell and Ruby (remaining call sites)

* *[capture-prefs.sh, osx-defaults.sh, setup-login-item.sh]* Removed the now-redundant `"${_SCRIPT_NAME}"` argument from remaining `print_script_summary` call sites.

#### Gate all script banners on outermost-script depth (remaining scripts)

* *[capture-prefs.sh, osx-defaults.sh, setup-login-item.sh]* Each script now decrements `_DOTFILES_SCRIPT_DEPTH` on exit (clean or error) via `_decrement_script_depth`.
* *[TechnicalDeepDive.md]* Added section on the nesting depth counter, `is_outermost_script` / `outermost_script?` guard, and why subprocess scripts still decrement even though only the outermost script prints output.

#### Harden shell utility infrastructure (remaining changes)

* *[capture-prefs.sh, .zshrc, .zlogin]* Eliminated inline `(N)` glob qualifiers — replaced with `setopt localoptions NULL_GLOB` inside anonymous functions `()`.
* *[.aliases, capture-prefs.sh]* Replaced remaining raw POSIX test switch (`-d`) usages and unsafe `&&`-as-conditional guards with named utility functions and explicit `if` statements.

#### Fix cron-safety issues (remaining changes)

* *[capture-prefs.sh]* Scoped `kill_login_item_apps` and `restart_login_item_apps` to import-only or interactive (TTY) export — cron export no longer kills running apps mid-session.

#### Harden git alias safety and portability

* *[.gitconfig]* Added `git pull-safe`: fetches all remotes unconditionally, then rebases onto `@{u}` only if the working tree is clean.
* *[.gitconfig]* Updated `git upreb`: guards the entire rebase + push workflow behind a dirty-tree check before touching anything.
* *[.gitconfig]* Refactored all `!`-prefixed aliases to accept an optional `[<dir>]` as their first argument via `git -C "${1:-.}"`, enabling `git <alias> /path/to/repo` as an alternative to `git -C /path/to/repo <alias>`.
* *[.gitconfig]* Fixed `git next-version` to account for commits already made since the last tag.
* *[software-updates-cron.sh]* Replaced `git pull` with `git pull-safe` and `git upreb` (which now have the dirty-tree guard built in); changed the outer failure handling from `_record_error` to `_record_warning` — a dirty skip during cron is an expected state.

#### Establish "do not combine both forms" rule for git aliases

* *[.gitconfig, git-config.instructions.md, copilot-instructions.md]* Documented that `git -C <path1> alias <path2>` is undefined behaviour — the explicit arg wins and `-C` is silently ignored.

#### Extract shared macOS prefs helpers into `.aliases § 3n`

* *[.aliases]* Extracted `kill_login_item_apps`, `restart_login_item_apps`, and `reload_macos_prefs` into a new `§ 3n. macOS prefs helpers` section, along with the canonical `_MACOS_LOGIN_ITEM_APPS` array.
* *[.aliases]* Added `suspend_softwareupdate_schedule` and `resume_softwareupdate_schedule` to `§ 3n`.
* *[osx-defaults.sh, capture-prefs.sh]* Moved `softwareupdate --schedule` management into the shared helpers; wired `resume_softwareupdate_schedule` into the EXIT trap.

#### Expand `osx-defaults.sh`

* *[osx-defaults.sh]* Added sections for new apps: Clocker, DBeaver, DockDoor, Drawio, Firefox, Keybase, KeyCastr, KeyClu, OnlyOffice, Rancher Desktop, Shortcat, Stats, Thaw, Zen Browser.
* *[osx-defaults.sh]* Replaced inline kill/restart arrays with calls to `kill_login_item_apps` and `trap 'restart_login_item_apps' EXIT`.
* *[osx-defaults.sh]* Removed stale Dock/Dashboard keys no longer present in macOS Catalina+.

#### Add technical deep-dive documentation and restructure adopter docs

* *[TechnicalDeepDive.md]* New document covering internal architecture for adopters.
* *[README.md, Extras.md, GettingStarted.md, Prerequisites.md]* Added links and callouts to TechnicalDeepDive.md; improved prose clarity on idempotency and the Brewfile first-install model.
* *[GettingStarted.md]* Rewrote the post-install checklist; replaced external gist links with local template files.
* *[templates/gitconfig-inc.template, templates/ssh-config.template]* New template files for per-context git config and SSH config.

#### Fix shell and startup infrastructure

* *[.gitconfig]* Fixed delta whole-line diff rendering: `minus-style`/`plus-style` now use `"syntax <bg-color>"` to preserve syntax highlighting on whole-line diffs; added `line-fill-method = ansi`.
* *[.zshrc, .zlogin]* Fixed trailing `[[ ]] && ...` conditionals that caused `source` to return exit code 1 on normal runs.
* *[.zshrc]* Added Option+arrow key bindings for Terminal.app word navigation — Terminal.app's "Use Option as Meta key" covers Option+B/F but not arrow keys; `\033[1;9D/C` mapped to ZLE word-motion (inert in iTerm2, which remaps these at the terminal level).
* *[.zshrc]* Commented out `setopt null_glob` — the option causes commands that receive zero arguments silently rather than producing a clear "no matches found" error; `setopt localoptions NULL_GLOB` inside an anonymous function is the correct scoped alternative.
* *[.aliases, capture-prefs.sh]* Fixed remaining unsafe `&&`-as-conditional patterns.
* *[.editorconfig, custom.gitattributes, .shfmtignore]* Removed `*.defaults` binary/charset entries (leftover from the 3.1.1 `.defaults` → `.plist` format migration); added `capture-prefs.sh` to `.shfmtignore` (uses `${~pattern}` zsh glob matching that shfmt cannot parse).
* *[fresh-install-of-osx.sh]* Removed trailing manual `user_action` prompts from `main()` — the deferred-collection summary (introduced in 3.1.1) already surfaces all follow-up actions.

#### Update documentation

* *[shell-scripting.instructions.md]* Added NULL_GLOB scoping rules: `setopt localoptions NULL_GLOB` inside an anonymous function is the only permitted form; banned bare `setopt NULL_GLOB`, `unsetopt NULL_GLOB`, and inline `(N)` qualifiers.
* *[copilot-instructions.md, shell-scripting.instructions.md]* Documented the `_MACOS_LOGIN_ITEM_APPS` file-scope constant array exception to the global-state variable naming convention.
* *[git-config.instructions.md]* Added working directory argument convention, dirty-tree guard pattern, and `## [delta] — Diff Rendering` section.
* *[.opencode/skills/dotfiles-domain/SKILL.md]* Updated opencode dotfiles skill with key rules, file reference tables, and documentation update routine.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then run in any open terminal:

  ```zsh
  install-dotfiles.rb
  unfunction is_shellrc_sourced; source ~/.shellrc    # to pick up new functions and bug fixes
  unfunction is_aliases_sourced; source ~/.aliases    # to pick up new functions and bug fixes
  rm -rfv  /opt/homebrew/opt/antidote/share/antidote/antidote.zsh.zwc*
  delete_caches                                       # clear any stale .zwc bytecode and cached shell environment files.
  _create_crontab "$PERSONAL_CONFIGS_DIR/crontab.txt" # re-generate the cron file with correct settings
  recron                                              # to pick up the simplified crontab entry
  ```

* Quit and restart the Terminal application (to guarantee that the latest versions of the zsh autoload scripts are loaded).
* On macOS 26: if any app is missing from Login Items, re-run `setup-login-item.sh -a '<AppName>'` for each, or re-run `brew bundle install` to trigger the `postinstall` hooks.

---

### 3.1.1

#### Introduce deferred error/warning collection

* *[.shellrc]* Added `user_action()` logging function (bold yellow, `➡️` prefix) for manual-step messages — distinct from `warn` (unexpected problem) and `info` (informational). Suppressed in direnv subshells.
* *[.shellrc]* Extracted `_record_warning`, `_record_error`, and `print_script_summary` as shared helpers using zsh dynamic scoping; `print_script_summary` fires a macOS notification when errors or warnings were collected.
* *[add-upstream-git-config.sh, capture-prefs.sh, cleanup-browser-profiles.sh, osx-defaults.sh, recreate-repo.sh, run-all.sh, setup-login-item.sh]* Applied the deferred collection pattern — operation failures use `_record_warning`/`_record_error`; `print_script_summary` called at end of `main()`.
* *[fresh-install-of-osx.sh]* Two-level collection: `_step_warnings` for recoverable issues, `_step_errors` for significant failures; `_cleanup_and_exit` calls `print_script_summary` before the fatal crash message.
* *[software-updates-cron.sh]* Two-level collection for update and infrastructure failures; escalated `_title_icon` to `⚠️` when outdated packages need manual update.

#### Gate all script banners on outermost-script depth

* *[.shellrc]* Added `is_outermost_script` (`_DOTFILES_SCRIPT_DEPTH <= 1`) and `_decrement_script_depth`; `print_script_start`, `print_script_duration`, and `print_script_summary` now guard on `is_outermost_script || return 0`.
* *[logging.rb]* Added `outermost_script?`, `increment_script_depth` (registers `at_exit` decrement), and `decrement_script_depth`; all three print helpers guard on `outermost_script?` — mirrors shell behaviour.
* *[.shellrc, logging.rb]* `print_script_duration` now prefixes output with the script name, eliminating ambiguity in multi-script cron logs.
* *[add-upstream-git-config.sh, cleanup-browser-profiles.sh, fresh-install-of-osx.sh, recreate-repo.sh, run-all.sh, software-updates-cron.sh]* Each now decrements `_DOTFILES_SCRIPT_DEPTH` on exit via `_decrement_script_depth`.
* *[resurrect-repositories.rb]* Calls `Logging.increment_script_depth` before `print_script_start`; `at_exit` hook handles the decrement.
* *[ruby-scripting.instructions.md]* Documented depth counter, `is_outermost_script` / `outermost_script?` guard, and why subprocess scripts still decrement.

#### Expand Ruby logging.rb with deferred collection and timing

* *[logging.rb]* Added `record_warning`, `record_error`, `current_section=`, and `print_script_summary` — Ruby mirrors of the shell deferred-collection pattern. `section_header` now sets `@current_section` as a side effect.
* *[logging.rb]* `print_script_start` returns the Unix epoch it logs — eliminates the two-call pattern; displayed timestamp and in-memory start time are always identical.
* *[logging.rb]* `print_script_summary(start_time = nil)` calls `print_script_duration` internally when provided — no separate call needed.
* *[logging.rb]* Added `Logging.user_action` to mirror the shell `user_action()` function.
* *[resurrect-repositories.rb]* Converted to `record_warning`/`record_error`; added `section_header` calls per phase; updated to `script_start_time = print_script_start` / `print_script_summary(script_start_time)` pattern.
* *[ruby-scripting.instructions.md]* Documented the deferred-collection pattern, two shell-version deviations (`print_script_start` return value; `print_script_summary` start-time argument), and `_SCRIPT_NAME` dynamic-scoping behaviour.

#### Unify script logging decoration across shell and Ruby

* *[.shellrc]* `print_script_start` prefixes banner with `_SCRIPT_NAME`; `_record_warning`/`_record_error` prefix entries with `[_SCRIPT_NAME][_current_section]`; `print_script_summary` reads `_SCRIPT_NAME` via dynamic scoping — no argument needed.
* *[add-upstream-git-config.sh, cleanup-browser-profiles.sh, recreate-repo.sh, run-all.sh]* Removed the now-redundant `"${_SCRIPT_NAME}"` argument from all `print_script_summary` call sites.

#### Harden shell utility infrastructure

* *[.shellrc]* Added `user_action()` — see "Introduce deferred error/warning collection" above.
* *[.shellrc]* Extracted `has_sudo_credentials` into § 1e; replaced all raw `sudo -n true 2>/dev/null` checks.
* *[.shellrc]* Fixed `is_zsh` from `[[ "${0}" =~ 'zsh' ]]` to `[[ -n "${ZSH_VERSION-}" ]]`.
* *[.shellrc]* Added `is_debug` and `is_first_install` predicates; replaced all raw inline forms.
* *[.shellrc, .aliases]* User-controlled boolean flags (`DEBUG`, `FIRST_INSTALL`) now use `:-`; shell-provided vars (`ZSH_VERSION`) keep `-`.
* *[.shellrc]* Added `debug` logging to `load_zsh_configs`.
* *[.aliases]* `require_env_var`: replaced raw `-z` test with `is_zero_string` and `warn`.
* *[.shellrc, .aliases]* Log-level reclassifications: idempotency guards → `info`; expected-absent tools → `debug`; action items → `user_action`; "Successfully sourced ~/.shellrc" → `success`.
* *[6 scripts]* Fixed unsafe `&&`-as-conditional patterns in `software-updates-cron.sh`, `recreate-repo.sh`, `capture-prefs.sh`, `run-all.sh`, `fresh-install-of-osx.sh` (×2) — converted to explicit `if` blocks.

#### Fix cron-safety issues in `.shellrc`

* *[.shellrc]* Added `${COLUMNS:-80}` fallback in `_section_header_impl` and `print_chars_for_length` — zsh sets `COLUMNS` to `0` with no terminal.

#### Align startup files and autoload functions to established conventions

* *[files/--ZDOTDIR--/.zshenv]* Changed `${DEBUG+1}` → `${DEBUG:-}`.
* *[files/--ZDOTDIR--/.zshrc]* Changed `${DEBUG+1}` → `${DEBUG:-}` and `${ZSH_PROFILE_RC+1}` → `${ZSH_PROFILE:-}`; renamed `ZSH_PROFILE_RC` → `ZSH_PROFILE`; converted final `[[ ]] &&` one-liner to `if/fi`.
* *[files/--ZDOTDIR--/.zlogin]* Changed three `${DEBUG+1}` → `${DEBUG:-}`; added `|| true` to `rm -f`/`zrecompile` calls; converted final `[[ ]] && echo` to `if/fi`.
* *[files/--XDG_CONFIG_HOME--/zsh/{cc,count,pull,push,st,status_all_repos,update_all_repos,upreb}]* Changed compdef guard to `is_zsh && (($+functions[compdef]))` — guards zsh-only syntax from bash; updated inline comment.

#### Expand shell-scripting documentation

* *[shell-scripting.instructions.md]* Documented `_SCRIPT_NAME` at script scope (not `local`) for dynamic-scoping availability; added `${_SCRIPT_NAME:-<interactive>}` fallback.
* *[shell-scripting.instructions.md]* Updated "Always Quote Variables" example to use `is_file` instead of `[[ -f ]]`.
* *[shell-scripting.instructions.md]* Added double-quotes exception for strings containing single quotes.
* *[shell-scripting.instructions.md]* Added `## Parameter Expansion Operators — \`:-\` vs \`-\`` section with scan rule.
* *[shell-scripting.instructions.md]* Fixed `DIRENV_IN_ENVRC` variable name (was `DIRENV_DIR`).
* *[shell-scripting.instructions.md]* Rewrote cron section: `load_zsh_configs` now conditional; added `sudo`, `is_running_in_tty`, and `COLUMNS` subsections.
* *[shell-scripting.instructions.md]* Updated autoload template and `compdef` guard to use `is_zsh`.
* *[shell-scripting.instructions.md]* Added `## _DOTFILES_SCRIPT_DEPTH — Increment and Decrement` section.
* *[shell-scripting.instructions.md]* Updated `shfmtignore` example to use `has_sudo_credentials`.
* *[zsh-startup.instructions.md]* Updated profiling example to use `ZSH_PROFILE`.
* *[shell-scripting.instructions.md, ruby-scripting.instructions.md]* Added unified `## Logging — Level Usage` classification table.
* *[shell-scripting.instructions.md]* Added `## '&&' as Conditional — Safety Under 'set -e' / ERR Trap` section.
* *[all shell scripts]* Ran `shfmt` across all non-ignored scripts.

#### Expand copilot-instructions documentation

* *[copilot-instructions.md]* Added `## Four-Context Validation` section.
* *[copilot-instructions.md]* Fixed `is_running_in_tty` table entry (stdin, `[[ -t 0 ]]`).
* *[copilot-instructions.md]* Updated deferred-collection pattern description: depth counter, decrement trap, Ruby equivalent.
* *[copilot-instructions.md]* Removed `"${_SCRIPT_NAME}"` from `print_script_summary` example.
* *[copilot-instructions.md]* Added `load_zsh_configs` ZDOTDIR safety note, conditional-cron guidance, `has_sudo_credentials` guard, `is_running_in_tty` gate, and `COLUMNS` fallback bullets.
* *[GettingStarted.md]* Updated bootstrap `curl` command to pipe through `tee "${HOME}/fresh-install-of-osx.log"`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then run in any open terminal:

  ```zsh
  install-dotfiles.rb
  unfunction is_shellrc_sourced; source ~/.shellrc   # to pick up new functions and bug fixes
  unfunction is_aliases_sourced; source ~/.aliases   # to pick up new functions and bug fixes
  delete_caches   # clear any stale .zwc bytecode and cached shell environment files.
  ```

* Quit and restart the Terminal application (to guarantee that the latest versions of the zsh autoload scripts are loaded).

---

### 3.0-19

* *[.shellrc]* Eliminated subprocess forks on every shell start: `$(whoami)` → `${USER}` (PAM builtin); `$(uname -m)` → `${${MACHTYPE%%-*}/#arm/arm64}` (zsh builtin, correctly maps `arm` → `arm64` on Apple Silicon); 16× `$(colorize ...)` calls for color variable initialisation → `$'\e[...'` ANSI escape literals; `$(tput cols)` in `print_chars_for_length` and `_section_header_impl` → `${COLUMNS}` (zsh special variable, no external process).
* *[.shellrc]* `replace_home_with_tilde` rewritten as pure-zsh parameter expansion `${1//${HOME}/~}`, eliminating two subprocess forks (`echo` + `sed`) on every call.
* *[.zshrc]* `brew shellenv` cache block: renamed internal variable `cache_file` → `brew_shellenv_cache` for clarity; added `is_executable "${brew_bin}"` guard so the block is skipped on a vanilla OS before Homebrew is installed.
* *[.zshrc]* Added `iterm2_hostname="${HOST}"` before the antidote bundle is sourced — pre-empts the iterm2 shell-integration `precmd` hook which forks `hostname -f` (~4ms) when this variable is unset.
* *[starship.toml]* Git operation state indicators changed from plain-space padding (e.g. `' MERGING '`) to `>> LABEL <<` delimiters (e.g. `'>> MERGING <<'`) for better visibility in the prompt during rebase/merge/cherry-pick/revert/bisect operations.
* *[.aliases]* Dynamic per-project `run-all.sh` aliases extracted into `_generate_repo_aliases` and cached to `${XDG_CACHE_HOME}/repo-aliases.zsh`. Cache is regenerated only when `PROJECTS_BASE_DIR` is newer than the cache or the cache is missing. Public `regenerate_repo_aliases` function added for manual refresh.
* *[.aliases]* `$(extract_first_word "${EDITOR}")` at two startup-path callsites (editor existence check and `edit` alias definition) replaced with `${EDITOR%% *}` (no subshell).
* *[.aliases]* `$(pwd)` default in `folder_size` replaced with `${PWD}` (zsh builtin).
* *[.zlogin]* `find_in_folder_and_recompile` now uses a per-directory mtime sentinel file in `${XDG_CACHE_HOME}` — subsequent login shells skip the `find` scan entirely if the directory has not changed since the last recompilation, eliminating redundant work on every login.
* *[.zlogin]* The five large directory recompilation scans (`DOTFILES_DIR`, `PERSONAL_BIN_DIR`, `PROJECTS_BASE_DIR`, `/opt/homebrew`, `/usr/local`) are now run in a disowned background job (`&!`) so they do not block the first prompt on login shells. Sentinel guards ensure they are no-ops when nothing has changed.
* *[.zlogin]* Added `recompile_zsh_autoload_dir` to compile extensionless autoload function files under `${XDG_CONFIG_HOME}/zsh/` (e.g. `cc`, `count`, `pull`, `push`, `st`, etc.) which `find_in_folder_and_recompile` would silently skip due to its `*.sh`/`*.zsh` pattern filter. Cache files under `${XDG_CACHE_HOME}` are also compiled via `find_in_folder_and_recompile`.
* *[all zsh scripts + autoload functions]* `type is_shellrc_sourced &>/dev/null` guard replaced with `(( $+functions[is_shellrc_sourced] ))` — pure zsh builtin check, no subshell.
* *[.shellrc, .aliases]* Centralised the re-source guard inside each file itself — all call sites now source unconditionally (no more per-call `(( $+functions[...] )) ||` guards). All custom zsh git commands (`cc`, `count`, `pull`, `push`, `st`, `status_all_repos`, `update_all_repos`, `upreb`) updated accordingly. Sourcing of these 2 files is now refined/tightened without duplication.
* *[all shell scripts]* Added `# Usage:` lines to all functions that accept arguments; added prose doc comments to all previously undocumented functions; converted `# ==` GROUP banners to `# ---` section dividers throughout both files. Fixed file-header banner width (was 81 chars, now exactly 80); split two combined `local var="$(…)"` declarations into separate declaration + assignment lines.
* *[custom.gitattributes]* Added `*.defaults binary` so Apple binary plist captures are never diffed or line-ending-normalised by git.
* *[.editorconfig (both repo root and HOME)]* Full idiom audit: removed incorrect `insert_final_newline = false` overrides for `*.json` and `*.md`; added `indent_style = tab` for `*.{cmd,bat}`; added `charset = unset` + `insert_final_newline = false` for `*.zwc`, `*.zwc.old`, `*.defaults`; added `[*.sql]` and `[*.{xml,plist}]` with `indent_size = 4`; added `[*.envrc]` shfmt block; added `[{custom.gitattributes,…}] indent_size = unset`; set `max_line_length = off` globally.
* *[.gitconfig]* Added `git pull-unshallow` and `git fetch-unshallow` aliases (auto-unshallow shallow repos before pulling/fetching). `git pullsub` now delegates to `pull-unshallow`. Fixed `git upreb` to use `grep -x upstream` (exact match). Simplified `git size` to avoid a nested subshell. Removed redundant `git prune` from `git cc`. Fixed `git mn` to pass `--no-ff` (required when `merge.ff=only` is set globally). Changed `help.autoCorrect` from `10` (100ms delay) to `prompt`.
* *[zsh git commands: cc, count, pull, push, st]* Replaced inline argument-parsing loop with `parse_folder_and_switches`; replaced inline `dispatch_or_fallback` expansion with the shared helper call.
* *[scripts/]* Fixed stale source comments across all scripts (`add-upstream-git-config.sh`, `capture-prefs.sh`, `capture-raycast-configs.sh`, `cleanup-browser-profiles.sh`, `post-brew-install.sh`, `recreate-repo.sh`, `run-all.sh`, `setup-login-item.sh`, `software-updates-cron.sh`); added missing function doc comments; added `warn` in place of `echo` where `.shellrc` helpers are available.
* *[scripts/osx-defaults.sh]* Structural refactor: `ask()` moved from nested (inside `main()`) to top-level; `auto` promoted to a script-level variable; sourcing changed from `.shellrc` to `.aliases`; `usage()` added with `print_usage`; `getopts ':s'` (colon-prefixed for error handling) replaces bare `getopts 's'`.
* *[scripts/run-all.sh]* Refactored: `source "${HOME}/.shellrc"` replaced with `.aliases`; all global `MINDEPTH`/`MAXDEPTH`/`FOLDER`/`FILTER` vars replaced with locals; `find … | grep | sort -u` pipeline replaced with a zsh-native dedup loop using `:h` and an associative array; `$(date +%s)` → `${EPOCHSECONDS}` (no fork); `usage()` rewritten with `print_usage`.
* *[scripts/resurrect-repositories.rb]* Major refactor: all public functions renamed to private (`_find_git_repos_from_disk`, `_apply_filter`, `_generate_each`, etc.); `CliParser` integrated in place of inline `OptionParser`; `section_header`/`print_script_start`/`print_script_duration` calls added; `_verify_all` gains summary statistics (`discovered_count`/`common_repos`); resurrection loop gains per-repo `begin/rescue` error isolation with `successful_repos`/`failed_repos` tracking — failures are now reported rather than aborting the loop.
* *[.shellrc]* Fixed `${(j.:.)RUBYLIB_PATHS}` bad substitution error when sourced by non-zsh runtimes (e.g. direnv). Wrapped the `RUBYLIB` block in `is_zsh` guard; updated comment to explain the direnv/bash incompatibility.
* *[.shellrc]* Added `RUBYLIB` setup to point to `scripts/utilities/` so Ruby scripts can `require` shared utilities by name without `require_relative`.
* *[.aliases]* Refactored `regenerate_repo_aliases` into a single public function (removed separate `_generate_repo_aliases`): accepts optional `-f` flag to force-rebuild; always sources the cache at the end; prints progress only when `-f` is given. Renamed cache file from `repo-aliases.zsh` to `repo-aliases-cache.zsh` for consistency with other cache files.
* *[.aliases]* `resurrect_tracked_repos`: collect repo ancestor dirs once via `_collect_repo_ancestor_dirs` and share via `_SHARED_REPO_DIRS` across both `allow_all_direnv_configs` and `install_mise_versions` calls (avoids running the expensive `find` traversal twice, but otherwise fall back to `_collect_repo_ancestor_dirs` if that's not set.); call `regenerate_repo_aliases` at the end; unset `_SHARED_REPO_DIRS` when done.
* *[.aliases]* Moved `is_aliases_sourced` function definition to immediately after the re-source guard (before `source "${HOME}/.shellrc"`), mirroring the `is_shellrc_sourced` placement in `.shellrc`.
* *[.aliases]* Added GROUP 3 header clarification: `(Groups 1 and 2 are defined in .shellrc — bootstrap utilities and core predicates.)`.
* *[scripts/install-dotfiles.rb, scripts/resurrect-repositories.rb]* Added `$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))` to both scripts — ensures shared utilities are loadable regardless of whether `RUBYLIB` is set (necessary during `FIRST_INSTALL` where the dotfiles repo is cloned after `.shellrc` is first sourced). Switched `require_relative 'utilities/logging'` → `require 'logging'` in both scripts.
* *[scripts/install-dotfiles.rb]* Replaced inline `OptionParser` block with `CliParser.parse` from the new shared `cli_parser` utility.
* *[scripts/utilities/cli_parser.rb, scripts/utilities/hash_ext.rb, scripts/utilities/path_utils.rb]* New shared Ruby utilities. `cli_parser` wraps `OptionParser` with standard error handling and `--help`; `hash_ext` extends `Hash` with `deep_sort`; `path_utils` exposes `extract_path_segment_at(folder, index)` extracts a path component by index (no subprocess fork).
* *[scripts/utilities/logging.rb]* Refactored `terminal_width` to avoid `||= begin...end` pattern (rufo formatter instability); updated usage comment from `require_relative` to `require`.
* *[scripts/utilities/string.rb]* `colorize` now suppresses color output when `$stdout` is not a TTY; tilde substitution applied inside `colorize` automatically (callers no longer pre-substitute). Color codes changed from plain integers (e.g. `31`) to composite SGR strings (e.g. `'0;31'`) to support bold/dim variants. Eight new color methods added; `pink` renamed to `purple`.
* *[scripts/utilities/file.rb]* Deleted — the `File.append` method it provided is no longer used anywhere in the codebase.
* *[scripts/software-updates-cron.sh]* Renamed `perform_update` → `_perform_update` (private convention). Replaced `[[ ${#array[@]} -gt 0 ]]` with `is_non_empty_array` in two places. Fixed stale `unset cutoff_epoch` → `unset cutoff_date`. Added `git restore-mtime`, `git maintenance register`, and `git maintenance start` steps for all tracked repos. Added `bat cache --build` step to keep the bat cache current after plugin changes. Removed the `ollama pull` block. Uses `_collect_repo_ancestor_dirs` / `_SHARED_REPO_DIRS` pattern to avoid duplicate `find` traversals. Sources `update_all_repos` and `status_all_repos` autoload scripts directly. Replace `home pull`, `oss upreb`, and `bcg` alias calls with direct equivalents (`run-all.sh`, `brew outdated --greedy`) — aliases are not expanded in non-interactive shells (cron).
* *[scripts/setup-login-item.sh]* Replaced `osascript | \grep -i` pipeline with zsh glob pattern match `${${(M)${(f)all_login_items}:#(#i)*${app_name}*}[1]}`.
* *[Brewfile]* Uncommented `shfmt` — now an explicit dependency.
* *[all eligible shell and Ruby scripts]* Reformatted using `shfmt` (shell/zsh) and `rufo` (Ruby) per `.editorconfig` rules.
* *[.shfmtignore]* New file. Excludes `.zshrc` and `cleanup-browser-profiles.sh` (unparseable zsh-only syntax), and `.shellrc` and `.aliases` (`keep_padding` expands intentional one-liners).
* *[.shellrc]* In the `info/error/debug/warn` functions, do not print anything if its being called from within `direnv`. This is to suppress the noisy logs when cd'ing to different directories.
* *[scripts/install-dotfiles.rb]* `custom.git*` files now use mtime-based conflict resolution instead of always treating the destination as authoritative. On `FIRST_INSTALL` (env var set) the destination always wins (moved into repo, copied back). On subsequent runs, the newer file wins; source wins on a tie. `--force` bypasses mtime and always overwrites.
* *[files/--HOME--/.gitconfig]* Made all aliases scripts POSIX-compatible.
* *[files/--HOME--/custom.gitignore, files/--HOME--/custom.gitattributes, files/--PERSONAL_PROFILES_DIR--/custom.gitignore]* Header comments updated to document the mtime-based resolution rules and FIRST_INSTALL behaviour.
* *[.shellrc → .aliases]* Moved 8 functions out of `.shellrc` into `.aliases` — reducing `.shellrc`'s curl-download payload and startup cost on a vanilla OS install.
* *[.shellrc]* `set_ssh_folder_permissions`: updated comment to document both reasons it stays in `.shellrc` — (1) vanilla OS pre-`install-dotfiles.rb` bootstrap; (2) bash-compat: called from `.envrc` files evaluated by direnv in a bash subshell (`.aliases` cannot be sourced in bash).
* *[scripts/software-updates-cron.sh]* Added ERR trap: calls `error()` (which triggers `notify`) on unexpected failure. Added profiles repo size check to notify if 2 GB threshold is breached.
* *[files/--HOME--/.envrc, files/--PERSONAL_PROFILES_DIR--/.envrc]* Added ERR trap to both `.envrc` files. On any unexpected failure, `notify()` fires an osascript notification with the filename and line number — visible even when the terminal is not in focus.
* *[scripts/data/capture-prefs-denied-list.txt]* New file listing 44 domains that must never be exported/imported: device identity UUIDs, MDM enrollment tokens, Apple ID credentials, AirTag beacon MACs, CloudKit cache blobs, printer presets keyed to IP addresses, and ephemeral UI/OS-version state. This script now loads the denied-list into an associative array at startup; skips any allowed-listed domain that also appears in the denied-list with a `warn` message instead of silently exporting/importing machine-specific data.
* *[scripts/data/capture-prefs-allowed-list.txt]* Removed all 44 denied-listed domains from the allowed-list.
* *[files/--HOME--/.aliases]* `find_and_append_prefs`: checks each discovered domain against the denied-list before appending to the allowed-list; prints a `warn` and skips rather than adding a denied-listed domain.
* *[files/--HOME--/.aliases]* `recron` now reads from the existing `${PERSONAL_CONFIGS_DIR}/crontab.txt` instead of regenerating it from a hardcoded template every time. `_create_crontab` is now a bootstrap-only seed — called only when `crontab.txt` does not exist yet (vanilla OS scenario).
* *[files/--HOME--/.shellrc]* `notify` now strips ANSI escape codes from the message before passing to `osascript`, preventing raw escape sequences from appearing as literal characters in macOS notifications. Uses inline zsh parameter expansion (`(S)` flag + extendedglob) instead of a `sed` subshell — avoids ERR trap inheritance into `$(...)` subshells where shell functions like `current_timestamp` are unavailable. Uses `setopt local_options extendedglob` to ensure `##` works correctly in non-interactive shells (cron) where `extendedglob` is off by default.
* *[files/--HOME--/.gitconfig]* `git cc`: accept `--expire=<when>` to override the reflog expiry (default remains `1.week.ago`). Uses `--expire=` flag style (matching `git reflog expire`'s own interface) so the zsh autoload passes it through `switches` with zero extra code. Examples: `git cc --expire=now`, `git cc --expire=3.days.ago`.
* *[files/--HOME--/.gitconfig]* `git rfc`: rewrote as a `!f()` shell function; uses `git for-each-ref` to enumerate `refs/heads`, `refs/remotes` explicitly instead of `--all`, so `refs/stash` is never expired and stashes are preserved. `refs/tags` excluded — tags have no reflogs.
* *[files/--HOME--/.gitconfig]* `git cc`: replaced `--all` in `reflog expire` with an explicit `git for-each-ref` enumeration of `refs/heads`, `refs/remotes` only — stashes preserved, tags excluded to avoid "reflog could not be found" errors on shallow clones.
* *[files/--HOME--/.gitconfig]* `git sci`: replaced locale-dependent `grep "to unstage"` staging detection with `git diff --cached --quiet` — robust across all git locales.
* *[files/--HOME--/.gitconfig]* `git relative-path`: fixed broken `git root` reference (alias never existed) and corrected path resolution to use `realpath` + `git rev-parse --show-toplevel` with proper absolute-path stripping. The old implementation was silently producing wrong output.
* *[files/--HOME--/.gitconfig]* `git fo`: removed redundant `--all` and `--tags` flags — `fetch.all=true`, `fetch.prune=true`, and `fetch.pruneTags=true` in config make plain `git fetch` equivalent.
* *[files/--HOME--/.gitconfig]* `git se`: added `-z`/`-0` to `rev-list`/`xargs` pipeline for null-safe handling of filenames containing spaces.
* *[files/--HOME--/.gitconfig]* `git standup`: now defaults author to `git config user.name` when called with no argument.
* *[files/--HOME--/.gitconfig]* `git rpo`: added comment noting it is a no-op after any fetch due to `fetch.prune=true`, but remains useful as an explicit one-shot command.
* *[files/--XDG_CONFIG_HOME--/zsh/cc]* Updated header documentation to reflect `--expire` flag, default behaviour, `--stale-fix`, and `--dry-run` example.
* *[.github/instructions/shell-scripting.instructions.md, .github/copilot-instructions.md]* Sharpened `shfmt` formatting rules: added explicit "check `.shfmtignore` first" directive, concrete before/after example of the `while true; do ...; done` one-liner corruption bug, and explanation that running `shfmt` on an excluded file corrupts intentional one-liners with no inline suppression escape.
* *[.shellrc]* `info` and `success` are now suppressed when `DIRENV_DIR` is set (i.e. running inside a direnv subshell evaluating an `.envrc`). `warn` and `error` always print. Cron jobs, CI, and interactive shells are unaffected. This silences routine `.envrc` log output from direnv without losing actionable messages.
* *[scripts/fresh-install-of-osx.sh]* Added `set -E` immediately after `set -euo pipefail` so the existing `_cleanup_and_exit` ERR trap is inherited by all helper functions defined in the file — previously a failure inside a helper would not trigger the trap.
* *[scripts/fresh-install-of-osx.sh]* Fixed dead `$?` check after `brew bundle`. Uncommented `resurrect_tracked_repos` (now runs automatically, synchronously, before `allow_all_direnv_configs` and `install_mise_versions` so repos exist before those sweep). DNS fallback changed from `8.8.8.8` to `1.1.1.1`.
* *[.github/copilot-instructions.md]* `custom.git*` exception block rewritten with FIRST_INSTALL / mtime resolution rules. `.shellrc` vs `.aliases` decision rule rewritten: clarifies the `install-dotfiles.rb` boundary, bash-compat reason for `.shellrc` retention, and lists zsh-autoload functions as `.aliases` candidates.
* *[.github/instructions/git-config.instructions.md, Extras.md]* `custom.git*` handling descriptions updated to reflect mtime-based resolution rules.
* *[files/--ZDOTDIR--/.zsh_plugins.txt, files/--ZDOTDIR--/.zsh_plugins.zsh]* Un-deferred `fast-syntax-highlighting`, `zsh-autosuggestions`, and `zsh-history-substring-search`. `kind:defer` uses `zle -F` but reschedules itself when `PENDING > 0` (bytes already in the TTY buffer) — a fast typist beats the idle window and gets no highlighting, no suggestions, and non-functional Up/Down arrow on their first command. These three plugins directly affect the live typing experience and must be synchronous. Alias-only and cosmetic plugins (`eza`, `git`, `termsupport`, `iterm2`, `sudo`, `zbell`) remain deferred. Updated deferral policy comment to document the `PENDING` race condition and the deliberate tradeoff.
* *[files/--XDG_CONFIG_HOME--/zsh/update_all_repos, status_all_repos, st, pull, push, upreb, count, cc]* Fixed `zsh_eval_context` self-invocation guard from `*:file*` to `*file*`. When sourced in a `zsh -c` context (as in the cron script), `zsh_eval_context` is `cmdarg file` (space-separated, not colon-separated), so `*:file*` did not match — causing the function to auto-execute on `source`, then execute again on the explicit call (double-run). `*file*` matches both `toplevel:shfunc:file` (sourced from a script) and `cmdarg file` (sourced in `zsh -c`).
* *[files/--HOME--/.shellrc]* Renamed `notify` → `_dotfiles_notify` to avoid collision with system/plugin commands (e.g. mise's `command_not_found_handler`) that return 127 and trigger the ERR trap in cron. Updated all call sites in `.shellrc`, `.envrc` files, and `software-updates-cron.sh`.
* *[files/--HOME--/.shellrc]* `success`, `info`, `warn`, `debug`: replaced `is_non_zero_string ... || echo` with `if ! is_non_zero_string ...; then echo; fi` — the bare `||` pattern caused `is_non_zero_string` returning 1 (outside direnv) to fire the ERR trap in any caller running under `set -e`.
* *[files/--XDG_CONFIG_HOME--/zsh/st, update_all_repos, status_all_repos, pull, push, upreb, count, cc]* Added `|| true` to the `compdef` registration guard in all autoload scripts. `(($+functions[compdef]))` exits 1 when `compdef` is not yet defined (non-interactive shells, cron, pre-`compinit`), firing the ERR trap in any script that sources these files.
* *[files/--HOME--/.shellrc]* `_dotfiles_notify`: use `[[ -x '/usr/bin/osascript' ]]` instead of `command_exists` — more precise (won't match a function/alias named `osascript`) and correct for a fixed system binary path.
* *[files/--ZDOTDIR--/.zshrc, files/--HOME--/.aliases, scripts/wait-editor]* Fixed `crontab -e` (and tools like `visudo`, `fc`) not blocking for GUI editors. `EDITOR` is always `'wait-editor'` — a thin wrapper that re-execs `$GIT_EDITOR` via POSIX word-splitting so `--wait` flags are passed correctly. `GIT_EDITOR` holds the full editor invocation (e.g. `'zed --wait'`, or `'vi'` for SSH). The SSH/local if-else in `.zshrc` collapsed into a single loop with a per-context preferred-editors list. `VISUAL` is not set — legacy concept, every modern tool falls back to `EDITOR`. Removed now-redundant `${EDITOR%% *}` stripping in `.aliases`.
* *[files/--ZDOTDIR--/.zshrc]* Added `ZSH_AUTOSUGGEST_USE_ASYNC=1`, `ZSH_AUTOSUGGEST_MANUAL_REBIND=1`, `ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20` before the antidote bundle load. Async mode fetches suggestions in a background process so ZLE never blocks on history lookups. Manual rebind skips the full ZLE widget re-wrap that autosuggestions performs on every `precmd` (~10–20ms per prompt). Buffer max size skips suggestion lookups for long command lines.
* *[files/--ZDOTDIR--/.zshrc]* Changed `ZSH_AUTOSUGGEST_STRATEGY` from `(history completion)` to `(history)` and added `ZSH_AUTOSUGGEST_HISTORY_IGNORE="?(#c100,)"`. The `completion` strategy spawns a `zpty` on every suggestion request (~10–30ms overhead); history alone covers the vast majority of useful suggestions. The ignore pattern skips history entries >100 chars, reducing regex matching cost on large history files.
* *[files/--HOME--/.gitconfig]* `git cc` and `git rfc`: removed `refs/tags` from `git for-each-ref` enumeration passed to `git reflog expire`. Tags have no reflogs (especially in shallow clones such as antidote cache repos), causing "reflog could not be found" errors for every tag. Only `refs/heads` and `refs/remotes` are valid reflog targets.
* *[files/--ZDOTDIR--/.zshrc]* Fixed silent bug: `list-suffixeszstyle` on one line (missing newline typo) meant both `list-suffixes` and `expand prefix suffix` completion styles were never set. Split into two separate `zstyle` calls.
* *[files/--ZDOTDIR--/.zshrc]* Removed three `compctl` (old pre-compsys zsh 2.x) calls and the `man_glob()` helper they depended on. `compctl -k hosts` referenced an undefined `$hosts` array; all three calls conflicted silently with compsys `_ssh`/`_man` completers from `zsh-completions`.
* *[files/--ZDOTDIR--/.zsh_plugins.txt, files/--ZDOTDIR--/.zsh_plugins.zsh]* Deferred 6 additional plugins via `kind:defer` to reduce synchronous startup work: `lib/termsupport.zsh` (terminal title/CWD hooks — cosmetic), `plugins/eza` (aliases only), `plugins/git` (heaviest plugin at 431 lines, aliases only), `plugins/iterm2` (shell integration hooks — cosmetic), `plugins/sudo` (ESC-ESC key binding), `plugins/zbell` (long-command bell hooks). Cannot defer: `lib/functions.zsh`, `lib/completion.zsh`, `lib/correction.zsh`, `lib/key-bindings.zsh`, `lib/misc.zsh`, `zsh-completions`, `plugins/direnv`.
* *[files/--ZDOTDIR--/.zshrc]* Added `ensure_dir_exists "${XDG_CACHE_HOME}"` before the first cache write. When `delete_caches` removes `~/.cache`, all subsequent `>|` cache-write redirections failed silently — the `brew shellenv` cache was never written, so `fpath` never received `${HOMEBREW_PREFIX}/share/zsh/site-functions`, breaking brew completions and antidote plugins on the next shell start.
* *[files/--ZDOTDIR--/.zlogin]* Moved `find_in_folder_and_recompile "${XDG_CACHE_HOME}"` into the disowned background block. The mtime sentinel never actually prevented the `find` scan: `.zshrc` always writes cache files before `.zlogin` runs, so the sentinel's `-nt` check always failed and `find` ran synchronously on every login shell.
* *[personal/dev/configs/crontab.txt, files/--HOME--/.aliases]* Expanded crontab `PATH` to include `/usr/local/bin`, `/usr/sbin`, `/sbin`, `${PERSONAL_BIN_DIR}`, and `${DOTFILES_DIR}/scripts` — previously only `/opt/homebrew/bin:/usr/bin:/bin`, causing `run-all.sh`, `capture-prefs.sh`, `regenerate_repo_aliases`, and standard utilities to be not found in cron.
* *[personal/dev/configs/crontab.txt, files/--HOME--/.aliases]* Fixed `run-all.sh` and `capture-prefs.sh` not found in cron despite correct PATH. Crontab treats `#` as part of a value on assignment lines, so an inline comment was appended to the last PATH directory name, making it invalid. Moved the explanation to a standalone comment line above the `PATH=` assignment.
* *[scripts/software-updates-cron.sh]* Removed `load_zsh_configs` call — it sourced `.zshrc` which activated mise and installed `command_not_found_handler`. That handler returned 127 in the non-interactive cron environment, firing the ERR trap. The script only needs `.aliases`.
* *[personal/dev/configs/crontab.txt, files/--HOME--/.aliases]* Fixed cron invocation: changed from `chronic /opt/homebrew/bin/zsh script.sh 2>&1 | tee` (tee outside chronic's scope — log never written on success) to `chronic /opt/homebrew/bin/zsh -c 'zsh script.sh 2>&1 | tee'` so chronic wraps the full pipeline.
* *[scripts/software-updates-cron.sh]* Added `setopt LOCAL_TRAPS` inside `main()` and moved ERR trap setup there, so the trap is scoped to `main` and not inherited into called functions.
* *[scripts/software-updates-cron.sh]* Consolidated macOS notifications: removed the mid-run outdated notification (immediately replaced by the final "done" notification). The final notification now includes the comma-separated outdated package list when present.
* *[.github/instructions/shell-scripting.instructions.md, .github/copilot-instructions.md, .github/instructions/git-config.instructions.md]* Updated docs: `zsh_eval_context` guard (`*file*`), `compdef` `|| true` guard, and `git cc`/`git rfc` `refs/tags` exclusion rule.
* *[all shell script]* Removed all redundant `unset` calls on `local` variables — `local` variables auto-clean on function return, so `unset` inside the same function is always a no-op.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then run in any open terminal:

  ```zsh
  cp $DOTFILES_DIR/files/--HOME--/custom.gitattributes $HOME/.gitattributes
  cp $DOTFILES_DIR/files/--HOME--/custom.gitignore $HOME/.gitignore
  install-dotfiles.rb
  ```

* Run `delete_caches` to clear any stale `.zwc` bytecode and cached shell environment files.
* Quit and restart the Terminal application.

---

### 3.0-18

* *[.zshrc]* Replaced **Oh My Zsh** with **antidote** as the plugin manager. A pre-generated static bundle (`${ZDOTDIR}/.zsh_plugins.zsh`) is checked into the home repo and sourced directly — antidote itself does not need to be installed for the shell to start. The antidote formula (installed via `brew`) and sourced at shell startup is only required for `antidote update` / `antidote bundle` to refresh plugin sources.
* *[.zshrc]* Removed all Oh My Zsh bootstrap variables (`ZSH`, `ZSH_CUSTOM`, `ZSH_THEME`, `ZSH_DISABLE_COMPFIX`, `zstyle ':omz:update' ...`, `plugins=(...)`) and the `source "${ZSH}/oh-my-zsh.sh"` call. `compinit -C` is now called explicitly (no longer delegated to OMZ). Stale alias/comment block referencing OMZ examples removed.
* *[.zshrc]* `mise activate zsh` is now cached — output written to `${XDG_CACHE_HOME}/mise-activate-cache.zsh` keyed on the mise binary mtime, regenerated only when mise itself is updated. The OMZ `mise` plugin was removed because it referenced `${ZSH_CACHE_DIR}` (undefined without OMZ), which caused a "no such file or directory: /completions/_mise" error on every shell start.
* *[.zshrc]* Added `typeset +x FPATH fpath cdpath CDPATH` after the dedup pass — `FPATH` and `CDPATH` must never be exported. Both are zsh-internal variables (autoload search path and `cd` search path respectively). Exporting them causes their contents to leak into the macOS launchd user-session environment, where they persist across iTerm2 restarts and are inherited by every new shell before any rc file runs. Symptoms: `zsh -f -c 'echo $FPATH'` showed stale `~/.oh-my-zsh/...` paths even after `~/.oh-my-zsh` was deleted. All other `*path` vars on that line (`PATH`, `MANPATH`, `INFOPATH`, `CPPFLAGS`, `LDFLAGS`, `PKG_CONFIG_PATH`) are intentionally exported — child processes need them.
* *[.zshrc]* `compinit` refactored to use `-C` (skip `compaudit` scan) when the dump file already exists, saving ~11ms per startup. Wrapped in an anonymous function so `autoload -Uz compinit` does not pollute the global function table. `ZSH_COMPDUMP` moved to `${XDG_CACHE_HOME}/zcompdump` to keep `$HOME` clean.
* *[.zshrc]* Starship prompt initialisation cached to `${XDG_CACHE_HOME}/starship-init-cache.zsh`, keyed on the starship binary mtime — avoids forking `starship init zsh` on every shell start. `${commands[starship]}` used instead of `$(command -v starship)` (O(1) zsh hash lookup, no fork). Note: sourcing via a `precmd` hook was attempted but causes `setopt promptsubst` (emitted by starship's init) to be scoped to the hook function, leaving `PROMPT` as an unexpanded literal after the first command — the cache is therefore sourced directly at startup.
* *[.zshrc]* `autoload -Uz colors && colors` removed — none of the active plugins use `$fg`/`$bg`/`$color` from the zsh `colors` function; own color variables are defined as `$'\e[...'` literals in `.shellrc`.
* *[.zshrc]* `$(extract_first_word "${editor}")` in the preferred-editor detection loop replaced with `${editor%% *}` (inline parameter expansion, no subshell).
* *[.zshrc]* Fixed bug in autoload loop: `autoload -Uz "${func_file}"` → `autoload -Uz "${func_file:t}"`. Without `:t` (basename), `autoload` registers the function under its full path (e.g. `/path/to/myfunc`) which can never be invoked by short name.
* *[.zlogin]* `recompile_zsh_scripts` now removes `.zwc.old` before and after calling `zrecompile -pq` — `zrecompile` moves the existing `.zwc` to `.zwc.old` before writing the new one; if `zcompile` fails mid-write the backup is left behind indefinitely. Cleanup is unconditional so stale backups never accumulate.
* *[.shellrc]* Added `export ANTIDOTE_HOME`, `ANTIDOTE_ZSH`, and `ANTIDOTE_PLUGIN_ZSH` — set early (before `antidote.zsh` is sourced) so they are available in `.zlogin` and other contexts. `ANTIDOTE_HOME` mirrors antidote's own platform defaults: `~/Library/Caches/antidote` on macOS, `${XDG_CACHE_HOME}/antidote` on Linux.
* *[.zsh_plugins.txt]* **New file** — canonical antidote plugin list, replacing the old `plugins=(...)` array in `.zshrc`. Loads selected OMZ lib files, OMZ plugins and third-party plugins.
* *[Brewfile]* Added `antidote` to the base-configs section (installed on every machine, including `FIRST_INSTALL`). Replaced `diff-so-fancy` with `delta` as the diff/pager tool. Replaced `jq` with `jaq` (a faster Rust reimplementation). Commented out `codeql` cask.
* *[scripts/fresh-install-of-osx.sh]* Replaced `install_oh_my_zsh_and_custom_plugins` (curl install + three `git clone` calls for custom plugins) with a call to `update_antidote_and_regenerate_plugin_bundle` placed after `homebrew` is installed.
* *[scripts/post-brew-install.sh]* Added antidote update and bundle regeneration step by invoking `update_antidote_and_regenerate_plugin_bundle` on every `brew bundle` / `bupc` run, keeping the bundle in sync after antidote itself is installed or upgraded.
* *[scripts/software-updates-cron.sh]* Replaced `omz update` with the equivalent antidote update function `update_antidote_and_regenerate_plugin_bundle`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps in any open terminal:

   ```zsh
   cp $DOTFILES_DIR/files/--HOME--/custom.gitignore $HOME/.gitignore
   rm -rf "${HOME}/.oh-my-zsh"
   install-dotfiles.rb                                                              # Symlink .zsh_plugins.txt and .zsh_plugins.zsh into ${ZDOTDIR}
   brew install antidote                                                            # Install antidote (a zsh script, not a binary)
   source "${HOMEBREW_PREFIX}/opt/antidote/share/antidote/antidote.zsh"             # Load the antidote function into the current shell
   antidote bundle < "${ZDOTDIR}/.zsh_plugins.txt" > "${ZDOTDIR}/.zsh_plugins.zsh"  # Generate the static plugin bundle
   launchctl unsetenv FPATH                                                         # One-time flush of the stale FPATH from the launchd user environment
   delete_caches                                                                    # Clear stale .zwc bytecode and all generated cache files to pick up the typeset +x change
   ```

* Quit and restart the Terminal application (a full restart is required — sourcing in-place leaves old OMZ functions in memory).

---

### 3.0-17

* *[files/--HOME--/.p10k.zsh (deleted), files/--XDG_CONFIG_HOME--/starship.toml (new), files/--HOME--/Brewfile, files/--ZDOTDIR--/.zshrc]* Replaced **powerlevel10k** with **Starship** as the prompt engine. Deleted `.p10k.zsh` and the OMZ p10k instant-prompt setup from `.zshrc`; added `starship.toml`; replaced `tap 'romkatv/powerlevel10k'` and `brew 'powerlevel10k'` with `brew 'starship'` in the Brewfile.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then run in any open terminal:

  ```zsh
  cp $DOTFILES_DIR/files/--HOME--/custom.gitignore $HOME/.gitignore
  install-dotfiles.rb
  rm -f "${HOME}/.p10k.zsh"      # remove dangling symlink — source deleted from repo
  brew install starship
  delete_caches
  ```

* Quit and restart the Terminal application.

---

### 3.0.16

* *[fresh-install-of-osx.sh]* Fixed issue where this script was failing silently on the first run on a vanilla OS (root cause: curl timeout within homebrew while downloading installables). Replaced the `HOMEBREW_BASE_INSTALL` variable with `FIRST_INSTALL` and added a guard which disables the ERR trap during brew operations, forces re-download of `.shellrc`, sets a long curl timeout (`--max-time 3600`), splits `brew bundle` into separate tap/formula/cask passes for better isolation and resilience, and restores the trap + unsets the extra curl args afterwards.
* *[Brewfile]* Renamed the early-exit guard from `HOMEBREW_BASE_INSTALL` to `FIRST_INSTALL` for consistency.
* *[software-updates-cron.sh]* Prune Zen session-backup files older than 7 days from the browser-profiles repo (works with both macOS BSD and GNU `date`).
* *[.shellrc]* Added TODO comments in `clone_repo_into` for future reftable support once p10k resolves the `vcs_info` incompatibility, including a HEAD-fixup snippet for post-move repos.
* *[.gitconfig, custom.gitignore, custom.gitattributes, recreate-repo.sh]* Git performance tuning and ignore/attribute reorganisation.
* *[.gitconfig]* Tuned git performance settings: set `core.autocrlf=false`, increased `core.compression` and `pack.compression` to 9, raised `pack.deltaCacheSize` to 2047m and `pack.windowMemory` to 1g, enabled `pack.useDeltaBaseOffset`, added `fetch.negotiationAlgorithm=skipping`, `http.version=HTTP/2`, `protocol.version=2`, and `repack.packKeptObjects=false` / `repack.useDeltaBaseOffset=true` for faster and smaller pack operations.
* *[.gitconfig]* Added `init.defaultRefFormat=reftable` as a commented-out TODO pending p10k support.
* *[custom.gitattributes]* Added explicit `eol=lf` enforcement via `* text=auto`; added binary markers for common image, font, and byte-compiled extensions (`*.png`, `*.jpg`, `*.woff*`, `*.ttf`, `*.pyc`, `*.zwc*`, etc.) so git never mangles them.
* *[custom.gitignore (home)]* Major reorganisation: grouped all ignore rules under labelled section headers (OS, shell history, caches, build tools, IDE, AI tools, XDG config, SSH, home directories, dev workspace, misc app data, symlinked dotfiles, negations); added new entries for opencode auto-generated files, Zed conversations/themes, GitHub Copilot, Gemini/Qwen/Safety AI tools, and various other tools.
* *[custom.gitignore (profiles)]* Full rewrite with labelled sections; consolidated browser-profile ignore rules across all `*Profile` dirs (lock files, caches, crash artefacts, telemetry, security state, network/SW state, runtime DBs); added detailed per-browser sections for Firefox, Zen, Thunderbird, and Chrome Beta with explicit comments on what is intentionally tracked.
* *[.shellrc]* Added TODO comments in `clone_repo_into` for future reftable support; added logic to fix the `.git/HEAD` file after reftable clone-via-move.
* *[recreate-repo.sh]* Added TODO comment for future `git init --ref-format=reftable` support.
* *[software-updates-cron.sh]* Added a new step to prune tracked Zen session backup files older than 7 days from the browser-profiles repo (compatible with both macOS BSD and GNU `date`).
* *[.shellrc]* Added `step_start`, `step_end`, and `step_timing_init` helper functions for per-step and total elapsed time reporting in scripts.
* *[fresh-install-of-osx.sh, software-updates-cron.sh]* Instrumented all major steps with `step_start`/`step_end` calls for granular timing output. Also initialise `_SCRIPT_START_TIME` explicitly so timing is accurate before `.shellrc` is sourced.
* *[Brewfile]* Enabled `cairo`, `gnu-tar`, `mercurial`, and `sccache` (previously commented out) for zen-browser development.
* *[.zshrc]* Added `gnu-tar` to the list of keg-only Homebrew packages that override macOS defaults. Removed the `git_scripts` path addition.
* *[.envrc (profiles)]* Temporarily disabled natsumi-browser cloning as a trial. Removed `timeout` wrapper from `add-upstream-git-config.sh` call.
* *[software-updates-cron.sh]* Temporarily disabled natsumi codebase update block as a trial.
* *[Brewfile]* Added `Mechvibes` since Haptyk turned out to be payware after some days. Removed `Haptyk` from `capture-prefs-domains.txt` and added `Mechvibes`.
* *[GettingStarted.md]* Updated bootstrap one-liner to use `FIRST_INSTALL` instead of the old `HOMEBREW_BASE_INSTALL` variable name.
* *[.shellrc]* Added `ServerAliveInterval=10` and `ServerAliveCountMax=3` SSH options to the `submodule update` call in `clone_repo_into` to prevent silent hangs on flaky connections.
* *[.aliases]* Updated `grep`/`fgrep`/`egrep` aliases: removed VCS dirs from `--exclude-dir` (since Homebrew `grep` handles them natively) and added `*.zwc*` / `.*.zwc*` to `--exclude` patterns. Removed `--all` flag from `bupc`'s `brew bundle` call. Added `allow_all_direnv_configs` and `install_mise_versions` calls inside `resurrect_tracked_repos`.
* *[.zshrc]* Refactored `use_homebrew_installation_for` to accept a package name (e.g. `curl`) instead of a full path; the function now derives the path internally via `${HOMEBREW_PREFIX}/opt/${1}`. Added `grep` to the keg-only packages loop. Added explicit `prepend_to_path_if_dir_exists` calls for `${HOMEBREW_PREFIX}/bin` and `${HOMEBREW_PREFIX}/sbin`.
* *[mise/config.toml]* Enabled `experimental = true` for mise.
* *[zed/settings.json]* Enabled thinking mode (`enable_thinking = true`) and set `effort = "high"` for the default Zed AI model.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitattributes" "${HOME}/.gitattributes"
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  ```

* Quit and restart the Terminal application.

---

### 3.0.15

* *[scripts]* AI-based refactoring of shell scripts and ruby scripts to remove redundant scripting issues like unnecessary `local`/`unset` declarations.
* *[.curlrc, .envrc, .gitconfig, .iex.exs, .profile, .zlogin, .zshrc]* General cleanup and minor improvements across dotfiles.
* *[zsh scripts]* Refactored `cc`, `count`, `pull`, `push`, `st`, `status_all_repos`, `update_all_repos`, and `upreb` scripts.
* *[.eclintignore, .editorconfig]* Added editor config and eclint ignore files for consistent code style enforcement.
* *[add-upstream-git-config.sh, .shellrc] Potential fix for `direnv allow` hanging when run in the `$PERSONAL_PROFILES_DIR` folder by ensuring that the git config is properly set up for that folder.
* *[.gitconfig]* Added new alias `default-branch` to get the default branch of a git repository.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  ```

* Quit and restart the Terminal application.

---

### 3.0.14

* *[Brewfile]* Replaced `Ice` with `Thaw`.

---

### 3.0.13

* *[Brewfile]* Added `Dockdoor`, `flux-markdown`, `dbeaver` and `codeql` to the Brewfile and captured their preferences for backup.
* *[.aliases]* The dynamically generated aliases for the git repositories found under the `$PROJECTS_BASE_DIR` will now enable more fine-grained control. To find out what all aliases have been setup on your machine, you can run `alias | \grep rug`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  source "${HOME}/.aliases"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  ```

* Quit and restart the Terminal application.

---

### 3.0.12

* *[.aliases]* New alias for `mkdir` that will create the directory and its parent directories if they don't exist.

---

### 3.0.11

* *[.aliases]* `recron` will now generate the default crontab file and then register it with the system's `crontab` command.
* *[Brewfile]* Added `mole` instead of `pearcleaner` for a cli-based tool to clean disk space.
* Custom git-related zsh scripts in `${XDG_CONFIG_HOME}/zsh/` now properly handle git switches passed to them.
* Added `direnv` configuration file.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  source "${HOME}/.shellrc"
  source "${HOME}/.aliases"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  recron
  crontab -l # should now show the crontab with the software updates cron job
  ```

* Quit and restart the Terminal application.

---

### 3.0.10

* *[install-dotfiles.rb]* Now handles the case where there's no env var substitution needed in the file's relative path, in which case, the file is treated as needing to be processed from the machine's root directory.
* Use `git restore` instead of `git checkout` to restore files.

---

### 3.0.9

* Fixed issues when running `install-dotfiles.rb` script on a vanilla macos with ruby 2.6 and optimized it for better performance.
* Fixed all shell scripts using claude-sonnet for better readability and maintainability.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  rm -rf "${XDG_CONFIG_HOME}/zsh"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  ```
* Quit and restart the Terminal application.

---

### 3.0.8

* *[Brewfile]* Added opencode for terminal-based free/OSS AI assistant.
* *[Brewfile]* Removed AlDente since its built into Tahoe now.
* *[Brewfile]* Removed Brave browser since I will use Chrome if needed.
* *[install-dotfiles.rb]* Use `SSH_CONFIGS_DIR` environment variable for ssh config directory.

---

### 3.0.7

* Moved `files/--HOME--/.ssh/global_config` file to `files/--SSH_CONFIGS_DIR--/` to make use of the correct ssh folder location if it was customized.
* mise will default to using pre-compiled ruby binaries if available.
* *[Brewfile]* Install `keyclu` and `drawio` apps and captured their preferences for backup.

---

### 3.0.6

* *[osx-defaults.sh]* Fix syntax issue.
* Remove redundant lines in multiple shell scripts.
* *[Brewfile]* Remove `unquarantine` flag in Brewfile since its no longer supported.

---

### 3.0.5

* *[install-dotfiles.rb]* and *[run-all.sh]* Added support for running in 'dry-run' mode and printing the summary.
* *[software-updates-cron.sh]* Removed pruning of mise-installed software since that doesn't work with the latest version of mise.

---

### 3.0.4

* *[Brewfile]* Replaced 'Raycast' with 'Sol' (https://github.com/ospfranco/sol) - lightweight, FOSS, faster.
* *[Brewfile]* Added 'Shortcat' (https://github.com/shortcatapp/shortcat) for faster and more efficient keyboard shortcuts.
* *[resurrect-repositories.rb]* Support for ruby 2.6 (default ruby in macos 26 Tahoe): added 'pathname' to require list.

---

### 3.0.3

* Revamped the documentations to improve clarity, readability and adoptability.

---

### 3.0.2

* *[run-all.sh]* Renamed the script to follow the naming convention (using hyphen instead of underscore) for all shell scripts.
* Replaced the `HOME` env var with the tilde (~) to represent the home directory when printing so as to reduce the amount of text being displayed on the console.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  source "${HOME}/.shellrc"
  source "${HOME}/.aliases"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  ```
* Quit and restart the Terminal application.

---

### 3.0.1

* *[install-dotfiles.rb]* Optimized the installation script for performance.
* Introduced `qwen-code` and `claude-code`. (settled on qwen-code)

---

### 3.0.0

* Squashed all commits into a single commit.
* Tested on a fresh vanilla macos (26.2) machine.

#### Adopting these changes

* Quit all browsers completely
* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  git tag -d 1.0
  git tag -d 2.0
  mv "${HOME}/.dotfiles" "${XDG_CONFIG_HOME}/dotfiles"
  mv "${HOME}/personal/${USERNAME}/profiles" "${HOME}/personal/${USERNAME}/browser-profiles"
  source "${XDG_CONFIG_HOME}/dotfiles/files/--HOME--/.shellrc"
  cp "${XDG_CONFIG_HOME}/dotfiles/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  "${XDG_CONFIG_HOME}/dotfiles/scripts/install-dotfiles.rb"
  allow_all_direnv_configs
  ```

* Quit and restart the Terminal application.

---

### 2.0.47

* *[.aliases] Extract `restore_cron` function to remove some duplication.
* *[fresh-install-of-osx.sh]* Removed resurrecting all tracked repos to save time while re-imaging/setting up the laptop.
* *[osx-defaults.sh]* Turned off spotlight indexing for all volumes.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* *Quit and restart your Terminal application* for these changes to take effect.

---

### 2.0.46

* Moved processing of the natsumi browser extension into the `.envrc` file so that `direnv` will take care of it automatically. This also handles cases where a new browser is installed after the first time setup.
* Moved resurrecting of tracked repos to the end after the import of preferences and setting up the cron job since it takes a long time and should not block the import process.

---

### 2.0.45

* Added a new script `run-all.sh` to run any unix command in matched git repos.
* *[fresh-install-of-osx.sh]* Removed cloning of the `git_scripts` repo since the `run-all.sh` script has now been moved into this repo.
* *[.shellrc]* Replaced function `dir_has_children` with `is_dir_empty` which checks if a directory is empty.
* *[.zlogin]* Recompile scripts in the foreground since running in the background results in silent failures.
* *[.aliases]* Added a new alias `resurrect_tracked_repos` to resurrect all tracked repositories.
* Renamed `FIRST_INSTALL` to `DEBUG` to better reflect the functionality.

---

### 2.0.44

* Updated documentation to include the setup of the cronjobs.

---

### 2.0.43

* Added a new function `is_shellrc_sourced` to check if the shellrc file is sourced.
* Changed all shell scripts to use single quotes where possible to ensure that we don't accidentally expand variables or execute commands.
* *[osx-defaults.sh]* Converted to a zsh script.

---

### 2.0.42

* Changed all shell scripts to use switches instead of positional arguments for more intuitive usage.
* Removed the use of colors if there's no terminal (for eg for cron jobs).
* Removed `boring-notch` cask since it was causing issues when installing on a fresh vanilla os.

---

### 2.0.41

* Adopted Zed as the default editor and removed VSCodium.
* Miscellaneous fixes and improvements to shell scripts.
* Cleanup documentation.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  bupc
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```


* *Quit and restart your Terminal application* for these changes to take effect.

---

### 2.0.40

* *[resurrect-repositories.rb]* Fixed an issue while cloning git repos where the script was silently proceeding further.

---

### 2.0.39

* *[Brewfile]* Added common & essential OSS packages that are typically behind in macos (typically due to license issues).
* *[.zshrc]* Fixed issue with `RUBY_CONFIGURE_OPTS` not being set correctly when `openssl` is installed.

---

### 2.0.38

* *[resurrect-repositories.rb]* Changed the repo-resurrection generation logic to reduce manual edits to the generated yaml structure. This now handles generating the yaml with references to the `PROJECTS_BASE_DIR` and `HOME` env variables to make it generic and not hardcode the user's login name/home folder.

---

### 2.0.37

* *[.shellrc]* Restructured the env var's section to be more explicit as to what section/vars need to be changed, and which ones can be optionally changed.
* *[.shellrc]* Extracted usages of `${HOME}/.ssh` into a new env var defined in `.shellrc` so that custom locations can be easily changed in a single place.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* *Quit and restart your Terminal application* for these changes to take effect.
* Run `install-dotfiles.rb` in the new shell.
* Manually edit `${HOME}/.ssh/config` to replace the reference to `~/.ssh/global_config` towards the last line with `./global_config`. If this results in a duplicate line, remove the duplicate line.
* Verify the above changes in the `${HOME}/.ssh/config` file by running `git pull` in one of the cloned repos on your local machine.

---

### 2.0.36

* All `git push` invocations now have the explicit `--progress` flag.
* *[.shellrc]* `error` function will no longer exit the process. It just returns a non-zero code which needs to be handled by the caller.
* *[.aliases]* `kbgc` alias has been changed to a function, which now accepts parameters as to which repo to process.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* Quit and restart your Terminal application for these changes to take effect.

---

### 2.0.35

* Make handling of stdout and stderr consistent across all usages.
* Handle immediate exit from shell scripts with appropriate error messages.
* **IMPORTANT:** The `post-brew-install.sh` script was not being invoked when running `brew bundle` command due to a path issue. Even if the path was hardcoded into the `Brewfile`, another issue (relating to that block being evaluated when the `Brewfile` was being read itself) is present. So, this invocation has been turned off.

#### Adopting these changes

* Quit and restart your Terminal application for these changes to take effect.

---

### 2.0.34

* *[fresh-install-of-osx.sh]* Move the custom handling of the `direnv` for the home and profiles folders into `allow_all_direnv_configs`.
* *[cleanup-browser-profiles.sh]* Remove parallelization since the code seems cleaner.
* General cleanup for maintainability and removing duplicate code.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```

* Quit and restart your Terminal application for these changes to take effect.

---

### 2.0.33

* Show the git repo size in the p10k prompt.

---

### 2.0.32

* Minor fixes for using `ZSH` env variable instead of hardcoding `$HOME/.oh-my-zsh` in multiple places.

---

### 2.0.31

* Unignore `$HOME/.ssh/known_hosts` so that the repository resurrection process is done without user interaction.
* When using the `error` function, a visual notification is also raised in the Notifications area so that the user need not monitor the `mail` command if there are any outdated GUI apps that need upgrading using `bcug`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```

---

### 2.0.30

* Updated documentation to clearly call out where references to my username (`vraravam`) should NOT be changed when forking for your usage.
* *[.aliases]* Renamed `delete_zsh_compilations` to `delete_caches`.

---

### 2.0.29

* Added Tor Browser.
* Updated instructions for exporting/importing Raycast configurations.

---

### 2.0.28

* Fixed issue with `upreb` and `cc` scripts since they were not evaluating the current working directory at the time of invocation. Instead, they were evaluating at the time of shell startup.
* *[Brewfile]* Added `dua-cli` for disk usage measurement from the cli.

---

### 2.0.27

* *[.aliases]* Removed `upreb_me` alias and `upreb-universal.sh` and combined both into a single zsh autoloaded script. This also allows to override it with a folder-specific implementation that can handle pre- and post- (or full override) steps as needed.
* *[.shellrc]* Reduce line length when invoking the `section_header` function by replacing the value of `HOME` env var with `~`.
* Introduced `.terraformrc` file for configuring terraform.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  install-dotfiles.rb
  ```

  After running the above script, there might be changes that show up in the dotfiles repo, which again need to be reconciled. While doing so, please keep in mind how this will need to work when running on a vanilla OS (even in cases where the prior machine is not working/accessible). So, ensure that any logic that you add should work in that scenario.

* Quit and restart your Terminal application for these changes to take effect.

---

### 2.0.26

* Fixed an issue where running `fresh-install-of-osx.sh` caused the whole terminal app to quit at the end.

---

### 2.0.25

* *[Brewfile]* Removed `ghostty` since there are some features that make iTerm better suited for my usecase.

---

### 2.0.24

* *[Brewfile]* Introduce `ghostty` and capture its configuration.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```

---

### 2.0.23

* De-duplicate `upreb` script to handle all locally checked out branches in a generic manner using a universal script rather than duplicating for each folder.
* *[.shellrc]* Updated the `section_header` function to be smart about viewport column width and center the text as optimally as possible.

---

### 2.0.22

* Introduce configuration in `git` to use `pandoc` for diffing word documents.

---

### 2.0.21

* Commented out the update to FF & Zen browser's user.js scripts since I have started using RapidFox settings.

---

### 2.0.20

* Trying to grayjay for youtube replacement.

---

### 2.0.19

* Enhanced `curl` configurations and enable retry even for first time setup.
* Turn on compression for ssh connections.
* Use `repack.MIDXMustContainCruft` in git config to optimize repo size.

---

### 2.0.18

* *[Brewfile]* Replace deprecated `tldr` with `tlrc`.
* Run the `ssh-add` command via direnv for the `HOME` folder. (It's idempotent, and so safe to be re-run for each new terminal window startup.)

---

### 2.0.17

* *[.gitignore_global]* Add all `.*keep` files to not be ignored.
* Fix gitignore configs for profiles repo.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${DOTFILES_DIR}/files/--PERSONAL_PROFILES_DIR--/custom.gitignore" "${PERSONAL_PROFILES_DIR}/.gitignore"
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```

---

### 2.0.16

* *[.gitconfig]* Enable `clone.rejectShallow`.
* *[Brewfile]* Try out BoringNotch.

---

### 2.0.15

* *[.gitconfig]* Fixed issues with incorrect sorting configurations.
* *[Brewfile]* Replaced 'floorp' with 'google chrome beta' since floorp doesn't expose custom key-bindings for switching workspaces. Moved to ice beta to support macos 26 Tahoe beta.

---

### 2.0.14

* Removed `ZenProfile` from being processed to inject Natsumi for user chrome.
* Updated documentation for catching up with multiple commits from upstream.

---

### 2.0.13

* Fixed an issue where the homebrew's libraries were not picked up first in the PATH.

---

### 2.0.12

* *[post-brew-install.sh]* Fixed issue with app name for Visual Studio Code while crearing cmd-line executable.
* *[Brewfile]* Removed Picocrypt and Unarchiver due to non-usage.

---

### 2.0.11

* *[software-updates-cron.sh]* Runs the `bcg` alias as the last command and if there are any oudated softwares, it will error out. This serves as a simple mechanism to prompt the user that some softwares need manual updating.

---

### 2.0.10

* *[fresh-install-of-osx.sh]* Added command to add the checked-out ssh keys to the ssh-agent.
* *[.gitconfig]* Added some more configurations.
* *[Brewfile]* Use new name for ollama cask.

---

### 2.0.9

* *[fresh-install-of-osx.sh]* `approve-fingerprint-sudo.sh` has now been converted from a standalone script into a function.

---

### 2.0.8

* *[fresh-install-of-osx.sh]* Moved each logical block into a function so its easier to understand and maintain.

---

### 2.0.7

* *[Brewfile]* Onyx is now only processed if the current OS is non-beta.

---

### 2.0.6

* Updated more documentation.
* *[capture-raycast-configs.sh]* and *[capture-prefs.sh]* now handle switches vs arguments/parameters consistently.
* *[software-updates-cron.sh]* Now also pulls `ollama` models: `codellama` and `deepseek-r1`.

---

### 2.0.5

* Updated `README.md` to make adoption steps clearer to follow.
* Formatting of markdown files.

---

### 2.0.4

* *[.aliases]* Introduced a new function `find_and_append_prefs` that finds and appends the preferences associated with the partial string passed in as an argument. Also, sorts (and removes duplicates) from the config file used to capture preferences.

---

### 2.0.3

* Trying to fix issue with osx-defaults somehow corrupting the `System Settings` app.

---

### 2.0.2

* *[.shellrc]* Exposed a new function `is_arm` to denote whether the current machine architecture is ARM.
* *[post-brew-install.sh]* Will cleanup the `keybase` executables from the `/usr/local/bin` folder if they are present.

---

### 2.0.1

* *[Brewfile]* Added Picocrypt.

---

### 2.0.0

* Squashed all commits into a single commit.
* Tested on a fresh vanilla macos (15.5) machine.

---

### 1.1-23

* *[Brewfile]* Removed unused apps, moved commented out lines towards the bottom of the file.

---

### 1.1-22

* *[Brewfile]* Fix issue with vscode not being in PATH when running `bupc` command.

---

### 1.1-21

* *[Brewfile]* Replace AppCleaner with PearCleaner, and KeepingYouAwake with an extension to Raycast (Coffee).

---

### 1.1-20

* *[Brewfile]* Trial to check if returning `0` will make the fresh installation script continue without needing to be rerun.
* Minor tweaks to fix the gitignore for profiles repo.
* *[.aliases]* Renamed alias `code-gist` to `edit-gist` to make it more generic.
* Handle setting up of Zed and Zed-Preview for cli access (if installed).

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${HOME}/.dotfiles/files/--PERSONAL_PROFILES_DIR--/custom.gitignore" "${PERSONAL_PROFILES_DIR}/.gitignore"
  install-dotfiles.rb
  ```

* Quit and restart the Terminal application.

---

### 1.1-19

* Moved a lot of the shell functions from `.aliases` into individual files in `${XDG_CONFIG_HOME}/zsh/` so that they can be autoloaded/lazy-loaded on-demand. (Theoretically, this should improve shell startup time)

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${HOME}/.dotfiles/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```

* Quit and restart the Terminal application.

---

### 1.1-18

* *[Brewfile]* Ice is not installed on MacOS < 14, added KnockKnock.
* *[fresh-install-of-osx.sh]* Use natsumi-browser in Firefox profile (similar to Zen profile).
* *[.gitignore_global]* Regenerate from https://gitignore.io with more options.
* Major refactoring for ruby scripts to optimize for time and use of ruby idioms.
* *[.zlogin]* Optimize recompiling of zsh shell scripts.

---

### 1.1-17

* *[software-updates-cron.sh]* Removed parallelism (something that was introduced in the previous version when optimzing using gemini) - since this was causing lots of confusion when looking through the logs.
* *[gitconfig]* Removed `editor` config setting since that's already being governed by the env var `EDITOR` set from `~/.zshrc`.
* *[Brewfile]* Removed unused tools / added new tools.
* *[capture-prefs-domains.txt]* Added entries to capture PdfGear, TinkerTool, UTM.
* Removed partial line comments from the other config data files since they are inconsistent/might cause issues when parsing / applying them during the cleanup steps.

---

### 1.1-16

* Ran gemini to optimize the shell configuration scripts aimed at optimizing the shell startup time.
* Renamed 'scripts/capture-defaults.sh' to 'scripts/capture-prefs.sh'
* Extracted 'setup_login_item' function from `~/.aliases` into a standalone script so as to avoid issues between bash vs zsh when running `postinstall` step in Brewfile.
* *[capture-prefs.sh]* Extracted the whitelist of preferences into a separate file: [capture-prefs-domains.txt](./scripts/data/capture-prefs-domains.txt).
* *[cleanup-browser-profiles.sh]* Extracted the whitelist of [files](./scripts/data/cleanup-browser-files.txt) and [directories](./scripts/data/cleanup-browser-dirs.txt) that needs to be cleaned into separate files.

*Note*: This version has been successfully tested on a Macbook M1 on 2 May, 2025.

---

### 1.1-15

* Added config settings file for `mise` to handle `idiomatic_version_file_enable_tools`

---

### 1.1-14

* *[shellrc]* Introduced new `is_zsh` function for defensively loading `~/.aliases` when running `brew` install/update commands (which runs `bash` shell)

---

### 1.1-13

* *[Brewfile]* Removed deprecated vscode plugins.
* *[software-updates-cron.sh]* Fix issue with BetterFox user.js not being put in correct Firefox profile; Added BetterZen's user.js into Zen profile.

---

### 1.1-12

* *[fresh-install-of-osx.sh]* Set PATH even if dotfiles repo is present - so that future scripts can be invoked without issues.
* *[Brewfile]* Cleaned up some softwares that I rarely use.
* *[.tcshrc]* Removed empty file

---

### 1.1-11

* *[.gitconfig]* Minor changes to decorate git log.
* *[.aliases]* Added `upreb_me` shell script that will intelligently run a shell script (if present) for the current folder or fall back to the global `git upreb` alias
* *[.npmrc]* Set some npm configurations to hide progress bar and save the exact version into the BOM file.

---

### 1.1-10

* *[.shellrc]* Removed 'depth' option while cloning repos since that causes rebases from the upstream repo to get corrupted.
* *[.gitconfig]* Added some [options recommended from the core git maintainers](https://blog.gitbutler.com/how-git-core-devs-configure-git/).

---

### 1.1-9

* Moved setting up of login items into the `Brewfile` so that can be managed along with the cask block itself.

---

### 1.1-8

* Minor cleanup (removed leftover references to Arc).

---

### 1.1-7

* *[software-updates-cron.sh]* Added more steps/commands to be run via a cron job.

---

### 1.1-6

* Minor refactoring to reuse utilize utility methods defined in `.shellrc`.

---

### 1.1-5

* *[.cshrc]* Removed empty file
* *[.shellrc]* Re-aligned colors for the success, warn, debug and error functions

---

### 1.1-4

* Simplify color output for scripts (avoid nesting) within the same line.

---

### 1.1-3

* *[.aliases]* `install_mise_versions` now handles config files from more language-version-managers.
* *[fresh-install-of-osx.sh]* Removed duplicate function defn: `build_keybase_repo_url`.
* *[fresh-install-of-osx.sh]* Moved some post-install steps into a new script which is invoked from the Brewfile's `at_exit` block.
* *[software-updates-cron.sh]* Corrected defensive checking of installed software before running some update commands.

---

### 1.1-2

* Moved `setup_login_item` function into the `Brewfile` since its used after app-installations.

---

### 1.1-1

* *[Brewfile]* Replaced `libreoffice` with `onlyoffice`.
* *[.aliases]* Fixed issue with `start_docker` and `stop_docker`.

---

### 1.0-53

* *[Brewfile]* Added `rsync` to be used from homebrew so as to avoid the recently announced RCE vulnerability.
* Changed the `DOTFILES_DIR` env var to use `${HOME}/.dotfiles` instead of `${HOME}/.bin-oss`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```zsh
  cp "${HOME}/.bin-oss/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  mv "${HOME}/.bin-oss" "${HOME}/.dotfiles"
  source "${HOME}/.shellrc"
  install-dotfiles.rb
  ```

* Quit and restart the Terminal application.

---

### 1.0-52

* Removed auto-configuration from rancher desktop to not manage/change the `PATH` env var since that's already done in [this line](./files/--ZDOTDIR--/.zshrc#L155) of the .zshrc file.

#### Adopting these changes

* Start rancher desktop, go into its preferences, and change the setting to not automatically set the `PATH`.
* Restart Terminal app and verify that `docker` is in your `PATH`.

---

### 1.0-51

* *[.aliases]* Uncommented `start_docker` and `stop_docker` and made them defensive.
* Removed 'ccleaner' preferences since I am no longer using it.

---

### 1.0-50

* All Firefox-based browsers are now handled for their respective `chrome` folders to be tracked and get updated as git repos.
* *[.aliases]* Added utility functions for `pull` and `push` similar to `st`, `count`, etc taking in an optional git repo.
* *[.shellrc]* Moved a utility function (`set_ssh_folder_permissions`) so that it can be reused.

#### Adopting these changes

* After rebasing, just quit and restart the terminal emulator so that the `.envrc` is processed. (Hint: Use `allow_all_direnv_configs` to accept and process all `.envrc` files in your system.)

---

### 1.0-49

* *[capture-raycast-configs.sh]* Automated initial password setup for Raycast export.

---

### 1.0-48

* *[.shellrc]* Extract common functions `strip_trailing_slash` and `extract_last_segment`.
* Use `unset` to jettison local variables once they are no longer needed.

#### Adopting these changes

* After rebasing, just quit and restart the terminal emulator so that the `.shellrc` is loaded into memory.

---

### 1.0-47

* *[capture-defaults.sh]* Added more macos preferences to be exported/imported for backup.
* Removed `Itsycal` since raycast and/or a desktop widget can be used instead of a dedicated application.

---

### 1.0-46

* Removed duplication (now `scripts/resurrect-repositories.rb` invokes the common function defined in the `.shellrc`).
* Removed usage of `eval` to simplify running of shell commands.

#### Adopting these changes

* After rebasing, just quit and restart the terminal emulator so that the `.shellrc` is loaded into memory.

---

### 1.0-45

* *[capture-raycast-configs.sh]* Added script to export/import raycast configs. More details can be found [here](Extras.md#capture-raycast-configssh). Code contributed by/adapted from @arunvelsriram's gist.
* Reuse utility functions defined in `.shellrc`

---

### 1.0-44

* *[recreate-repo.sh]* Fix an issue where a trailing slash would not properly process the repo in `${PERSONAL_PROFILES_DIR}` (ie would not force-squash)
* Cleaned `files/--PERSONAL_PROFILES_DIR--/custom.gitignore`

#### Adopting these changes

* After rebasing, run the following command prior to running the `install-dotfiles.rb` script.

  ```zsh
  cp "${DOTFILES_DIR}/files/--PERSONAL_PROFILES_DIR--/custom.gitignore" "${PERSONAL_PROFILES_DIR}/.gitignore"
  ```

---

### 1.0-43

* Nested all Firefox-based profiles one level deeper.

#### Adopting these changes

These changes are *optional*, but if you don't follow them, then the aliases/scripts pertaining to the browser profiles repo can be messed up..

* Quit any FF-based browser before rebasing from my repo.
* Run `git -C "${DOTFILES_DIR}" upreb`
* Resolve all conflicts.
* Open Finder on the `${PERSONAL_PROFILES_DIR}/`
* Inside each of the FF-based profiles folders, create a new folder called `DefaultProfile` and move all other sibling files/folders into that one.
* Edit the `profiles.ini` and `installs.ini` files at the root of the FF profile folder, and add `/DefaultProfile` to the lines referring to the profile folder (usually it'll be a relative path).
* Restart your FF-based browser to verify that all functionality continues to work.

---

### 1.0-42

* Added dev dependencies for zen-browser.
* Unignore some files from the `personal` folder that were somehow ignored globally.

---

### 1.0-41

* Added new script `scripts/add-upstream-git-config.sh`.

---

### 1.0-40

* Fixed documentation and reduced hardcoding of upstream repo-owner's name.

---

### 1.0-39

* Introduced [a new script](scripts/cleanup-browser-profiles.sh) to cleanup browser profiles folders.
* *[fresh-install-of-osx.sh]* Minor refactoring to enhance `clone_repo_into` to handle an optional target git branch which is also validated.

---

### 1.0-38

* *[.aliases]* Added extra checks for the `status_all_repos` and `count_all_repos` utility functions.

---

### 1.0-37

* Removed `Raycast` from being tracked via the profiles repo since that corrupts Raycast's internal db.

#### Adopting these changes

**These instructions are only necessary if you had previously adopted changes from v1.0-24**

* In Raycast, use the `Export Settings & Data` option to export your current settings.
* After successfully exporting the settings, quit Raycast and ensure that Raycast is completely shut down.
* Rebase the dotfiles repo, fix any conflicts and run the `install-dotfiles.rb` script.
* Manually reconcile the diffs / dirty state of `files/--PERSONAL_PROFILES_DIR--/custom.gitignore` with `$PERSONAL_PROFILES_DIR/.gitignore` on your local machine
* Run the following commands in the terminal

  ```zsh
  git -C "${DOTFILES_DIR}" restore files/--PERSONAL_PROFILES_DIR--/custom.gitignore
  cp "${DOTFILES_DIR}/files/--PERSONAL_PROFILES_DIR--/custom.gitignore" "${PERSONAL_PROFILES_DIR}/.gitignore"
  rm -rf "${HOME}/Library/Application Support/com.raycast.macos"
  mv "${PERSONAL_PROFILES_DIR}/Raycast" "${HOME}/Library/Application Support/com.raycast.macos"
  git -C "${PERSONAL_PROFILES_DIR}" rm -rf Raycast
  open /Applications/Raycast.app
  ```

* Once Raycast is restarted *AND if it shows an error about the database being corrupt*, then choose the `Reset` option, and use the `Import Settings & Data` option to import your previously exported settings back in.
* Once the above steps are done, if you rerun the `install-dotfiles.rb` script, it should not show any dirty files (especially the 2 `custom.gitignore` files) - and if this is the case, your setup is now back to normal working state.

---

### 1.0-36

* Use `is_git_repo` instead of `is_directory` if the next command(s) expects it to be a git repo.
* Remove Arc from `Brewfile` (since I moved to [Zen](https://zen-browser.app/)).

---

### 1.0-35

* Use `git-restore-mtime` from `git-tools` (as opposed to `git-utimes` from `git-extras`) since its > 1x faster performance.

---

### 1.0-34

* Set the DNS server to '8.8.8.8' only if running in a Jio network.
* Introduce PDFGear and KeyClu.
* Fixed some old documentation.

---

### 1.0-33

* Reuse utility functions defined in `.shellrc`.

---

### 1.0-32

* *[fresh-install-of-osx.sh]* Added date calculation in `fresh-install-of-osx.sh` to track total execution time.

---

### 1.0-31

* *[approve-fingerprint-sudo.sh]* Handled case to execute `approve-fingerprint-sudo.sh` based on touchId hardware.

---

### 1.0-30

* *[resurrect-repositories.rb]* Handled the case where git wouldn't allow cloning a repo into a pre-existing, non-empty folder.
* *[.zshrc]* Handled case where docker-related aliases were not setup since it was not in the `PATH` when `files/--HOME--/.aliases` was evaluated.

---

### 1.0-29

* *[capture-defaults.sh]* Removed some applications that I no longer use.
* *[fresh-install-of-osx.sh]* Replaced `TODO` with explanation for future reference as to why we can't use `homebrew` to install omz custom plugins.

---

### 1.0-28

* *[Brewfile]* Stop processing the `Brewfile` such that the minimal installation can happen in a shorter duration of time. This is controlled by the env var `HOMEBREW_BASE_INSTALL` which is set in the `fresh-install-of-osx.sh` script when installing from scratch.

---

### 1.0-27

* *[.aliases]* Added 2 new utility functions: `count` and `count_all_repos`

---

### 1.0-26

* Merged `fresh-install-of-osx-advanced.sh` into `fresh-install-of-osx.sh` to reduce complexity of loading different config files into the shell session.
* *[.gitconfig]* Remove git sub-command `currentDir` in favor of [root](https://github.com/tj/git-extras/blob/main/Commands.md#git-root).
* *[Brewfile]* Remove `git-tools` since `git-extras` has an equivalent git sub-command.
* *[.gitignore_global]* Generate from [gitignore.io](https://gitignore.io) for common languages, OSes and editors.
* *[fresh-install-of-osx.sh]* Minimize use of `eval` and sub-shells.
* *[fresh-install-of-osx.sh]* Moved utility scripts (from `files/--HOME--/.aliases`) that are only loaded while running the `fresh-install-of-osx.sh` into that single script to optimize shell startup time.
* *[fresh-install-of-osx.sh]* Removed cloning of `natsumi-browser` from `.envrc` and moved into fresh-install script. Updating the repo is now handled as part of `scripts/software-updates-cron.sh`.
* *[.zshrc]* Removed `zsh-defer` since that was introducing more complexity in maintenance.
* *[.shellrc]* Use `mktemp` to enhance implementation of `clone_repo_into` which reduces need to process the home-repo in a special manner while doing a fresh install.
* *[.shellrc]* Moved homebrew env vars from `files/--HOME--/.zshenv` into `files/--HOME--/.shellrc`.
* Merged `files/--HOME--/.zshrc.custom` into `files/--HOME--/.zshrc` and `files/--HOME--/.aliases.custom` into `files/--HOME--/.aliases` to reduce complexity of loading different config files into the shell session.

#### Adopting these changes

* After rebasing and resolving the conflicts
* Manually reconcile the diffs between `files/--HOME--/custom.gitignore` & `${HOME}/.gitignore`, and `files/--PERSONAL_PROFILES_DIR--/custom.gitignore` & `${PERSONAL_PROFILES_DIR}/.gitignore`.
* Open the Terminal application and run the following commands:

    ```zsh
    rm -rf ${HOME}/.aliases.custom ${HOME}/.zshrc.custom ${HOME}/.oh-my-zsh/custom/plugins/zsh-defer
    cp files/--HOME--/custom.gitignore ${HOME}/.gitignore
    cp files/--PERSONAL_PROFILES_DIR--/custom.gitignore ${PERSONAL_PROFILES_DIR}/.gitignore
    install-dotfiles.rb
    ```

* Quit and restart your Terminal application for the env vars, aliases & functions to be re-evaluated into the session memory.
* Run `bupc` to cleanup brews and casks.

*Note*: This version has been successfully tested on a Macbook M1 on 22 Dec, 2024.

---

### 1.0-25

* *[capture-defaults.sh]* Capture defaults script now aborts when the `PERSONAL_CONFIGS_DIR` env var is not defined.
* *[.shellrc]* Extracted common utility function to remove duplication and invoke them in the setup scripts.
* *[fresh-install-of-osx-advanced.sh]* Fixed potential issue with the `PATH` not being updated if the fresh-install-advanced script was run without starting a new terminal session.
* *[.aliases]* Added a new `profiles` alias to handle git repos checked out into the `PERSONAL_PROFILES_DIR`.

---

### 1.0-24

* Capture the Raycast configs/extensions/etc in the profiles repo

#### Adopting these changes

* Open Terminal and run the `install-dotfiles.rb` script.
* Change the current directory in terminal to the profiles repo (`direnv` will take care of the rest)

---

### 1.0-23

* Incorporate the [natsumi-browser](https://github.com/greeeen-dev/natsumi-browser) into the Zen browser profile.

---

### 1.0-22

* *[.shellrc]* Moved functions that are only needed in the basic fresh-install script into that so as to reduce shell startup time.

*Note*: This version has been successfully tested on a Macbook M1 on 19 Dec, 2024.

---

### 1.0-21

* *[fresh-install-of-osx-advanced.sh]* Nested conditions and print more specific warning message when skipping cloning of the home and profiles repos.
* *[.shellrc]* Extracted some utility functions to remove duplication and invoke them in the setup scripts.

#### Adopting these changes

* Manually edit your `${HOME}/.ssh/config` file, and change all occurrences of `~` to `${HOME}`

---

### 1.0-20

* Removed necessity of quitting and restarting the Terminal application between executing the `fresh-install-of-osx.sh` and `fresh-install-of-osx-advanced.sh`.
* *[.shellrc]* Extracted some utility functions to remove duplication and invoke them in the setup scripts.
* *[.shellrc]* Renamed `ensure_dir_exists_if_var_defined` into `ensure_dir_exists` and `clone_if_not_present` into `clone_omz_plugin_if_not_present`.
* *[Brewfile]* Removed `gs`, `wifi-password` and `virtualbox`.

*Note*: This version has been successfully tested on a Macbook M1 on 16 Dec, 2024.

#### Adopting these changes

* Run `git delete-tag success-tested-on-m1; git push origin :success-tested-on-m1` to cleanup the defunct tag.

---

### 1.0-19

* *[Brewfile]* Added `keycastr` to help with pairing and presentations of screen-grabs.
* Added some more logging while running the fresh-install scripts.

---

### 1.0-18

* Restructured `Brewfile` to convey what are bare minimum formulae vs recommended vs optional ie left to the user's choice.

#### Adopting these changes

* The reason for this restructuring is explained up above. Since most of the adoptees have customized this file, it will probably result in conflicts. Please be diligent in resolving the conflicts.

---

### 1.0-17

* All GH urls now also take into account the branch that's being tested for the setup scripts. Read the [new section](./README.md#how-to-test-changes-in-your-fork-before-raising-a-pull-request) in the README if you are making changes that you want to test against a PR branch before the PR is merged.

---

### 1.0-16

* Moved some of the core zsh config files from `files/--HOME--/` to `files/--ZDOTDIR--/` to accommodate custom location of `ZDOTDIR`.
* *[.shellrc]* Merged all relevant lines from `files/--ZDOTDIR--/.zprofile` into `files/--HOME--/.shellrc` and deleted `files/--ZDOTDIR--/.zprofile` since that is the first file loaded during the fresh machine setup. This also avoids the defensive definition of `ZDOTDIR` in duplicate files.

#### Adopting these changes

* After rebasing, you will end up with conflicts. The env vars that were previously defined in `files/--ZDOTDIR--/.zprofile` have been moved into `files/--HOME--/.shellrc`. You might have to manually fix them. You can go ahead and delete the `${HOME}/.zprofile` since that is no longer needed.
* Run `install-dotfiles.rb` so that the symlinked zsh config files in `${HOME}` point to the correct locations (`files/--ZDOTDIR--/` instead of `files/--HOME--/`)

---

### 1.0-15

* *[README.md]* Fixed some grammatical errors in README.
* *[.gitconfig]* Added new git alias for logs.

---

### 1.0-14

* Use 'zsh-defer' to try to bring down shell startup time.

#### Adopting these changes

* Run `fresh-install-of-osx.sh` so that the `zsh-defer` plugin is cloned to the correct directory.
* Restart terminal for the deferred-loading to take effect. (No harm in keeping the old session).

---

### 1.0-13

* *[.shellrc]* Introduced new utility functions `section_header` and `debug` and standardized on usages.

---

### 1.0-12

* Reverted changes from v1.0.9 related to 'bupc' since the 1st cleanup might be skipped due to the '||' condition status

---

### 1.0-11

* Converted from 'iBar' menubar app to 'Ice' since its open source and seems to have better features. This also removes the need to login into the App Store!

---

### 1.0-10

* Fix zsh auto-completion since some of the options were set after the `compinit` invocation
* *[.zprofile]* Ensure that directories are created for env vars defined in `.zprofile`
* `setopt` paramters are case-insensitive and can handle underscore and so changed them for readability
* *[.shellrc]* Introduced new utility function `ensure_dir_exists_if_var_defined` to help in cases where `code-gist` used to create unsaved files instead of directories for undefined env vars

---

### 1.0-9

* Remove redundant cleanup in 'bupc'
* Removed MS Teams and MS Remote Desktop

#### Adopting these changes

* Restart terminal for the revised alias function to get loaded. (No harm in keeping the old session; just that it will perform an extra step unnecessarily on `bupc` alias)

---

### 1.0-7

* *[fresh-install-of-osx.sh]* Fix issue when running in a fresh/vanilla machine since 'ZDOTDIR' was undefined.

---

### 1.0-6

* *[install-dotfiles.rb]* Fix issue when creating the include line for `~/.ssh/config` if it was not present.

---

### 1.0-5

* *[approve-fingerprint-sudo.sh]* Persists authorization config for triggering touchId when running sudo commands in terminal across software updates.

#### Adopting these changes

* Run `approve-fingerprint-sudo.sh`

---

### 1.0-4

* *[install-dotfiles.rb]* Refactored environment variable resolution logic to use `gsub!` for improved performance.

---

### 1.0-3

* Moved all files & nested folders inside the `files` directory into `files/--HOME--` to make that location explicit (earlier it was implied)

---

### 1.0-2

* *[install-dotfiles.rb]* Refactored the logic to handle ssh global configuration file for ease of readability and maintainability.

---

### 1.0-1

* *[Brewfile]* Added `virtualbox` to test out linux as a Virtual machine.
* *[CHANGELOG.md]* Added changelog which will be maintained going forward for each commit.
* *[README.md]* Added a [new section](README.md#how-to-upgrade--catch-up-to-new-changes) detailing steps to adopt updates/catchups for new changes on an ongoing basis.
* Changed all colored messages to be uniform and added a `success` function to print in green. These are optimized for a dark theme in your terminal emulator.

---

### 1.0

* `install-dotfiles.rb` can now handle multiple env vars for nested files/folders in the `files` sub-folder. They follow the naming convention of the env var being enclosed within 2 pairs of hyphens (`--`). For eg, `files/--PERSONAL_PROFILES_DIR--/.envrc` will be symlinked on your local machine into `${HOME}/personal/<yourLocalUsername>/profiles/.envrc` assuming that the `PERSONAL_PROFILES_DIR` env var has been defined. This is not a breaking change.

#### Adopting these changes

* Since I recreated the `1.0` tag as part of this push, you might need to delete the tag in both your local and your remote and then do `git upreb`.
* Run the `install-dotfiles.rb` script which will automatically remove the older (broken) symlink and recreate the new one in the correct location.

---
