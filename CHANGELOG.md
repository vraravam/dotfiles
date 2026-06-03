As documented in the README's [adopting](README.md#how-to-adoptcustomize-the-scripts-to-your-own-settings) section, this repo and its scripts are aimed at developers/techies. If you are stuck or need help in any fashion, you can reach out to the [owner of the parent repo](https://github.com/vraravam) from where this was forked.

For those who follow this repo, here's the changelog for ease of changelog:


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

  ```bash
  unfunction is_aliases_sourced; source ~/.aliases    # to pick up new functions and bug fixes
  ```

* Quit and restart the Terminal application.


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

  ```bash
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

  ```bash
  install-dotfiles.rb
  unfunction is_shellrc_sourced; source ~/.shellrc   # to pick up new functions and bug fixes
  unfunction is_aliases_sourced; source ~/.aliases   # to pick up new functions and bug fixes
  delete_caches   # clear any stale .zwc bytecode and cached shell environment files.
  ```

* Quit and restart the Terminal application (to guarantee that the latest versions of the zsh autoload scripts are loaded).

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

  ```bash
  cp $DOTFILES_DIR/files/--HOME--/custom.gitattributes $HOME/.gitattributes
  cp $DOTFILES_DIR/files/--HOME--/custom.gitignore $HOME/.gitignore
  install-dotfiles.rb
  ```

* Run `delete_caches` to clear any stale `.zwc` bytecode and cached shell environment files.
* Quit and restart the Terminal application.

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

   ```bash
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

### 3.0-17

* *[files/--HOME--/.p10k.zsh (deleted), files/--XDG_CONFIG_HOME--/starship.toml (new), files/--HOME--/Brewfile, files/--ZDOTDIR--/.zshrc]* Replaced **powerlevel10k** with **Starship** as the prompt engine. Deleted `.p10k.zsh` and the OMZ p10k instant-prompt setup from `.zshrc`; added `starship.toml`; replaced `tap 'romkatv/powerlevel10k'` and `brew 'powerlevel10k'` with `brew 'starship'` in the Brewfile.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then run in any open terminal:

  ```bash
  cp $DOTFILES_DIR/files/--HOME--/custom.gitignore $HOME/.gitignore
  install-dotfiles.rb
  rm -f "${HOME}/.p10k.zsh"      # remove dangling symlink — source deleted from repo
  brew install starship
  delete_caches
  ```

* Quit and restart the Terminal application.

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

  ```bash
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitattributes" "${HOME}/.gitattributes"
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  ```

* Quit and restart the Terminal application.

### 3.0.15

* *[scripts]* AI-based refactoring of shell scripts and ruby scripts to remove redundant scripting issues like unnecessary `local`/`unset` declarations.
* *[.curlrc, .envrc, .gitconfig, .iex.exs, .profile, .zlogin, .zshrc]* General cleanup and minor improvements across dotfiles.
* *[zsh scripts]* Refactored `cc`, `count`, `pull`, `push`, `st`, `status_all_repos`, `update_all_repos`, and `upreb` scripts.
* *[.eclintignore, .editorconfig]* Added editor config and eclint ignore files for consistent code style enforcement.
* *[add-upstream-git-config.sh, .shellrc] Potential fix for `direnv allow` hanging when run in the `$PERSONAL_PROFILES_DIR` folder by ensuring that the git config is properly set up for that folder.
* *[.gitconfig]* Added new alias `default-branch` to get the default branch of a git repository.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  ```

* Quit and restart the Terminal application.

### 3.0.14

* *[Brewfile]* Replaced `Ice` with `Thaw`.

### 3.0.13

* *[Brewfile]* Added `Dockdoor`, `flux-markdown`, `dbeaver` and `codeql` to the Brewfile and captured their preferences for backup.
* *[.aliases]* The dynamically generated aliases for the git repositories found under the `$PROJECTS_BASE_DIR` will now enable more fine-grained control. To find out what all aliases have been setup on your machine, you can run `alias | \grep rug`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  source "${HOME}/.aliases"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  ```

* Quit and restart the Terminal application.

### 3.0.12

* *[.aliases]* New alias for `mkdir` that will create the directory and its parent directories if they don't exist.

### 3.0.11

* *[.aliases]* `recron` will now generate the default crontab file and then register it with the system's `crontab` command.
* *[Brewfile]* Added `mole` instead of `pearcleaner` for a cli-based tool to clean disk space.
* Custom git-related zsh scripts in `${XDG_CONFIG_HOME}/zsh/` now properly handle git switches passed to them.
* Added `direnv` configuration file.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  source "${HOME}/.shellrc"
  source "${HOME}/.aliases"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  recron
  crontab -l # should now show the crontab with the software updates cron job
  ```

* Quit and restart the Terminal application.

### 3.0.10

* *[install-dotfiles.rb]* Now handles the case where there's no env var substitution needed in the file's relative path, in which case, the file is treated as needing to be processed from the machine's root directory.
* Use `git restore` instead of `git checkout` to restore files.

### 3.0.9

* Fixed issues when running `install-dotfiles.rb` script on a vanilla macos with ruby 2.6 and optimized it for better performance.
* Fixed all shell scripts using claude-sonnet for better readability and maintainability.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  rm -rf "${XDG_CONFIG_HOME}/zsh"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  ```
* Quit and restart the Terminal application.

### 3.0.8

* *[Brewfile]* Added opencode for terminal-based free/OSS AI assistant.
* *[Brewfile]* Removed AlDente since its built into Tahoe now.
* *[Brewfile]* Removed Brave browser since I will use Chrome if needed.
* *[install-dotfiles.rb]* Use `SSH_CONFIGS_DIR` environment variable for ssh config directory.

### 3.0.7

* Moved `files/--HOME--/.ssh/global_config` file to `files/--SSH_CONFIGS_DIR--/` to make use of the correct ssh folder location if it was customized.
* mise will default to using pre-compiled ruby binaries if available.
* *[Brewfile]* Install `keyclu` and `drawio` apps and captured their preferences for backup.

### 3.0.6

* *[osx-defaults.sh]* Fix syntax issue.
* Remove redundant lines in multiple shell scripts.
* *[Brewfile]* Remove `unquarantine` flag in Brewfile since its no longer supported.

### 3.0.5

* *[install-dotfiles.rb]* and *[run-all.sh]* Added support for running in 'dry-run' mode and printing the summary.
* *[software-updates-cron.sh]* Removed pruning of mise-installed software since that doesn't work with the latest version of mise.

### 3.0.4

* *[Brewfile]* Replaced 'Raycast' with 'Sol' (https://github.com/ospfranco/sol) - lightweight, FOSS, faster.
* *[Brewfile]* Added 'Shortcat' (https://github.com/shortcatapp/shortcat) for faster and more efficient keyboard shortcuts.
* *[resurrect-repositories.rb]* Support for ruby 2.6 (default ruby in macos 26 Tahoe): added 'pathname' to require list.

### 3.0.3

* Revamped the documentations to improve clarity, readability and adoptability.

### 3.0.2

* *[run-all.sh]* Renamed the script to follow the naming convention (using hyphen instead of underscore) for all shell scripts.
* Replaced the `HOME` env var with the tilde (~) to represent the home directory when printing so as to reduce the amount of text being displayed on the console.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  source "${HOME}/.shellrc"
  source "${HOME}/.aliases"
  "${DOTFILES_DIR}/scripts/install-dotfiles.rb"
  ```
* Quit and restart the Terminal application.

### 3.0.1

* *[install-dotfiles.rb]* Optimized the installation script for performance.
* Introduced `qwen-code` and `claude-code`. (settled on qwen-code)

### 3.0.0

* Squashed all commits into a single commit.
* Tested on a fresh vanilla macos (26.2) machine.

#### Adopting these changes

* Quit all browsers completely
* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
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

### 2.0.47

* *[.aliases] Extract `restore_cron` function to remove some duplication.
* *[fresh-install-of-osx.sh]* Removed resurrecting all tracked repos to save time while re-imaging/setting up the laptop.
* *[osx-defaults.sh]* Turned off spotlight indexing for all volumes.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* *Quit and restart your Terminal application* for these changes to take effect.

### 2.0.46

* Moved processing of the natsumi browser extension into the `.envrc` file so that `direnv` will take care of it automatically. This also handles cases where a new browser is installed after the first time setup.
* Moved resurrecting of tracked repos to the end after the import of preferences and setting up the cron job since it takes a long time and should not block the import process.

### 2.0.45

* Added a new script `run-all.sh` to run any unix command in matched git repos.
* *[fresh-install-of-osx.sh]* Removed cloning of the `git_scripts` repo since the `run-all.sh` script has now been moved into this repo.
* *[.shellrc]* Replaced function `dir_has_children` with `is_dir_empty` which checks if a directory is empty.
* *[.zlogin]* Recompile scripts in the foreground since running in the background results in silent failures.
* *[.aliases]* Added a new alias `resurrect_tracked_repos` to resurrect all tracked repositories.
* Renamed `FIRST_INSTALL` to `DEBUG` to better reflect the functionality.

### 2.0.44

* Updated documentation to include the setup of the cronjobs.

### 2.0.43

* Added a new function `is_shellrc_sourced` to check if the shellrc file is sourced.
* Changed all shell scripts to use single quotes where possible to ensure that we don't accidentally expand variables or execute commands.
* *[osx-defaults.sh]* Converted to a zsh script.

### 2.0.42

* Changed all shell scripts to use switches instead of positional arguments for more intuitive usage.
* Removed the use of colors if there's no terminal (for eg for cron jobs).
* Removed `boring-notch` cask since it was causing issues when installing on a fresh vanilla os.

### 2.0.41

* Adopted Zed as the default editor and removed VSCodium.
* Miscellaneous fixes and improvements to shell scripts.
* Cleanup documentation.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  bupc
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```


* *Quit and restart your Terminal application* for these changes to take effect.

### 2.0.40

* *[resurrect-repositories.rb]* Fixed an issue while cloning git repos where the script was silently proceeding further.

### 2.0.39

* *[Brewfile]* Added common & essential OSS packages that are typically behind in macos (typically due to license issues).
* *[.zshrc]* Fixed issue with `RUBY_CONFIGURE_OPTS` not being set correctly when `openssl` is installed.

### 2.0.38

* *[resurrect-repositories.rb]* Changed the repo-resurrection generation logic to reduce manual edits to the generated yaml structure. This now handles generating the yaml with references to the `PROJECTS_BASE_DIR` and `HOME` env variables to make it generic and not hardcode the user's login name/home folder.

### 2.0.37

* *[.shellrc]* Restructured the env var's section to be more explicit as to what section/vars need to be changed, and which ones can be optionally changed.
* *[.shellrc]* Extracted usages of `${HOME}/.ssh` into a new env var defined in `.shellrc` so that custom locations can be easily changed in a single place.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* *Quit and restart your Terminal application* for these changes to take effect.
* Run `install-dotfiles.rb` in the new shell.
* Manually edit `${HOME}/.ssh/config` to replace the reference to `~/.ssh/global_config` towards the last line with `${SSH_CONFIGS_DIR}/global_config`. If this results in a duplicate line, remove the duplicate line.
* Verify the above changes in the `${HOME}/.ssh/config` file by running `git pull` in one of the cloned repos on your local machine.

### 2.0.36

* All `git push` invocations now have the explicit `--progress` flag.
* *[.shellrc]* `error` function will no longer exit the process. It just returns a non-zero code which needs to be handled by the caller.
* *[.aliases]* `kbgc` alias has been changed to a function, which now accepts parameters as to which repo to process.

#### Adopting these changes

* Rebase from upstream, resolve conflicts.
* Quit and restart your Terminal application for these changes to take effect.

### 2.0.35

* Make handling of stdout and stderr consistent across all usages.
* Handle immediate exit from shell scripts with appropriate error messages.
* **IMPORTANT:** The `post-brew-install.sh` script was not being invoked when running `brew bundle` command due to a path issue. Even if the path was hardcoded into the `Brewfile`, another issue (relating to that block being evaluated when the `Brewfile` was being read itself) is present. So, this invocation has been turned off.

#### Adopting these changes

* Quit and restart your Terminal application for these changes to take effect.

### 2.0.34

* *[fresh-install-of-osx.sh]* Move the custom handling of the `direnv` for the home and profiles folders into `allow_all_direnv_configs`.
* *[cleanup-browser-profiles.sh]* Remove parallelization since the code seems cleaner.
* General cleanup for maintainability and removing duplicate code.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```

* Quit and restart your Terminal application for these changes to take effect.

### 2.0.33

* Show the git repo size in the p10k prompt.

### 2.0.32

* Minor fixes for using `ZSH` env variable instead of hardcoding `$HOME/.oh-my-zsh` in multiple places.

### 2.0.31

* Unignore `$HOME/.ssh/known_hosts` so that the repository resurrection process is done without user interaction.
* When using the `error` function, a visual notification is also raised in the Notifications area so that the user need not monitor the `mail` command if there are any outdated GUI apps that need upgrading using `bcug`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```

### 2.0.30

* Updated documentation to clearly call out where references to my username (`vraravam`) should NOT be changed when forking for your usage.
* *[.aliases]* Renamed `delete_zsh_compilations` to `delete_caches`.

### 2.0.29

* Added Tor Browser.
* Updated instructions for exporting/importing Raycast configurations.

### 2.0.28

* Fixed issue with `upreb` and `cc` scripts since they were not evaluating the current working directory at the time of invocation. Instead, they were evaluating at the time of shell startup.
* *[Brewfile]* Added `dua-cli` for disk usage measurement from the cli.

### 2.0.27

* *[.aliases]* Removed `upreb_me` alias and `upreb-universal.sh` and combined both into a single zsh autoloaded script. This also allows to override it with a folder-specific implementation that can handle pre- and post- (or full override) steps as needed.
* *[.shellrc]* Reduce line length when invoking the `section_header` function by replacing the value of `HOME` env var with `~`.
* Introduced `.terraformrc` file for configuring terraform.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  install-dotfiles.rb
  ```

  After running the above script, there might be changes that show up in the dotfiles repo, which again need to be reconciled. While doing so, please keep in mind how this will need to work when running on a vanilla OS (even in cases where the prior machine is not working/accessible). So, ensure that any logic that you add should work in that scenario.

* Quit and restart your Terminal application for these changes to take effect.

### 2.0.26

* Fixed an issue where running `fresh-install-of-osx.sh` caused the whole terminal app to quit at the end.

### 2.0.25

* *[Brewfile]* Removed `ghostty` since there are some features that make iTerm better suited for my usecase.

### 2.0.24

* *[Brewfile]* Introduce `ghostty` and capture its configuration.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```

### 2.0.23

* De-duplicate `upreb` script to handle all locally checked out branches in a generic manner using a universal script rather than duplicating for each folder.
* *[.shellrc]* Updated the `section_header` function to be smart about viewport column width and center the text as optimally as possible.

### 2.0.22

* Introduce configuration in `git` to use `pandoc` for diffing word documents.

### 2.0.21

* Commented out the update to FF & Zen browser's user.js scripts since I have started using RapidFox settings.

### 2.0.20

* Trying to grayjay for youtube replacement.

### 2.0.19

* Enhanced `curl` configurations and enable retry even for first time setup.
* Turn on compression for ssh connections.
* Use `repack.MIDXMustContainCruft` in git config to optimize repo size.

### 2.0.18

* *[Brewfile]* Replace deprecated `tldr` with `tlrc`.
* Run the `ssh-add` command via direnv for the `HOME` folder. (It's idempotent, and so safe to be re-run for each new terminal window startup.)

### 2.0.17

* *[.gitignore_global]* Add all `.*keep` files to not be ignored.
* Fix gitignore configs for profiles repo.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  cp "${DOTFILES_DIR}/files/--PERSONAL_PROFILES_DIR--/custom.gitignore" "${PERSONAL_PROFILES_DIR}/.gitignore"
  cp "${DOTFILES_DIR}/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```

### 2.0.16

* *[.gitconfig]* Enable `clone.rejectShallow`.
* *[Brewfile]* Try out BoringNotch.

### 2.0.15

* *[.gitconfig]* Fixed issues with incorrect sorting configurations.
* *[Brewfile]* Replaced 'floorp' with 'google chrome beta' since floorp doesn't expose custom key-bindings for switching workspaces. Moved to ice beta to support macos 26 Tahoe beta.

### 2.0.14

* Removed `ZenProfile` from being processed to inject Natsumi for user chrome.
* Updated documentation for catching up with multiple commits from upstream.

### 2.0.13

* Fixed an issue where the homebrew's libraries were not picked up first in the PATH.

### 2.0.12

* *[post-brew-install.sh]* Fixed issue with app name for Visual Studio Code while crearing cmd-line executable.
* *[Brewfile]* Removed Picocrypt and Unarchiver due to non-usage.

### 2.0.11

* *[software-updates-cron.sh]* Runs the `bcg` alias as the last command and if there are any oudated softwares, it will error out. This serves as a simple mechanism to prompt the user that some softwares need manual updating.

### 2.0.10

* *[fresh-install-of-osx.sh]* Added command to add the checked-out ssh keys to the ssh-agent.
* *[.gitconfig]* Added some more configurations.
* *[Brewfile]* Use new name for ollama cask.

### 2.0.9

* *[fresh-install-of-osx.sh]* `approve-fingerprint-sudo.sh` has now been converted from a standalone script into a function.

### 2.0.8

* *[fresh-install-of-osx.sh]* Moved each logical block into a function so its easier to understand and maintain.

### 2.0.7

* *[Brewfile]* Onyx is now only processed if the current OS is non-beta.

### 2.0.6

* Updated more documentation.
* *[capture-raycast-configs.sh]* and *[capture-prefs.sh]* now handle switches vs arguments/parameters consistently.
* *[software-updates-cron.sh]* Now also pulls `ollama` models: `codellama` and `deepseek-r1`.

### 2.0.5

* Updated `README.md` to make adoption steps clearer to follow.
* Formatting of markdown files.

### 2.0.4

* *[.aliases]* Introduced a new function `find_and_append_prefs` that finds and appends the preferences associated with the partial string passed in as an argument. Also, sorts (and removes duplicates) from the config file used to capture preferences.

### 2.0.3

* Trying to fix issue with osx-defaults somehow corrupting the `System Settings` app.

### 2.0.2

* *[.shellrc]* Exposed a new function `is_arm` to denote whether the current machine architecture is ARM.
* *[post-brew-install.sh]* Will cleanup the `keybase` executables from the `/usr/local/bin` folder if they are present.

### 2.0.1

* *[Brewfile]* Added Picocrypt.

### 2.0.0

* Squashed all commits into a single commit.
* Tested on a fresh vanilla macos (15.5) machine.

### 1.1-23

* *[Brewfile]* Removed unused apps, moved commented out lines towards the bottom of the file.

### 1.1-22

* *[Brewfile]* Fix issue with vscode not being in PATH when running `bupc` command.

### 1.1-21

* *[Brewfile]* Replace AppCleaner with PearCleaner, and KeepingYouAwake with an extension to Raycast (Coffee).

### 1.1-20

* *[Brewfile]* Trial to check if returning `0` will make the fresh installation script continue without needing to be rerun.
* Minor tweaks to fix the gitignore for profiles repo.
* *[.aliases]* Renamed alias `code-gist` to `edit-gist` to make it more generic.
* Handle setting up of Zed and Zed-Preview for cli access (if installed).

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  cp "${HOME}/.dotfiles/files/--PERSONAL_PROFILES_DIR--/custom.gitignore" "${PERSONAL_PROFILES_DIR}/.gitignore"
  install-dotfiles.rb
  ```

* Quit and restart the Terminal application.

### 1.1-19

* Moved a lot of the shell functions from `.aliases` into individual files in `${XDG_CONFIG_HOME}/zsh/` so that they can be autoloaded/lazy-loaded on-demand. (Theoretically, this should improve shell startup time)

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  cp "${HOME}/.dotfiles/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  install-dotfiles.rb
  ```

* Quit and restart the Terminal application.

### 1.1-18

* *[Brewfile]* Ice is not installed on MacOS < 14, added KnockKnock.
* *[fresh-install-of-osx.sh]* Use natsumi-browser in Firefox profile (similar to Zen profile).
* *[.gitignore_global]* Regenerate from https://gitignore.io with more options.
* Major refactoring for ruby scripts to optimize for time and use of ruby idioms.
* *[.zlogin]* Optimize recompiling of zsh shell scripts.

### 1.1-17

* *[software-updates-cron.sh]* Removed parallelism (something that was introduced in the previous version when optimzing using gemini) - since this was causing lots of confusion when looking through the logs.
* *[gitconfig]* Removed `editor` config setting since that's already being governed by the env var `EDITOR` set from `~/.zshrc`.
* *[Brewfile]* Removed unused tools / added new tools.
* *[capture-prefs-domains.txt]* Added entries to capture PdfGear, TinkerTool, UTM.
* Removed partial line comments from the other config data files since they are inconsistent/might cause issues when parsing / applying them during the cleanup steps.

### 1.1-16

* Ran gemini to optimize the shell configuration scripts aimed at optimizing the shell startup time.
* Renamed 'scripts/capture-defaults.sh' to 'scripts/capture-prefs.sh'
* Extracted 'setup_login_item' function from `~/.aliases` into a standalone script so as to avoid issues between bash vs zsh when running `postinstall` step in Brewfile.
* *[capture-prefs.sh]* Extracted the whitelist of preferences into a separate file: [capture-prefs-domains.txt](./scripts/data/capture-prefs-domains.txt).
* *[cleanup-browser-profiles.sh]* Extracted the whitelist of [files](./scripts/data/cleanup-browser-files.txt) and [directories](./scripts/data/cleanup-browser-dirs.txt) that needs to be cleaned into separate files.

*Note*: This version has been successfully tested on a Macbook M1 on 2 May, 2025.

### 1.1-15

* Added config settings file for `mise` to handle `idiomatic_version_file_enable_tools`

### 1.1-14

* *[shellrc]* Introduced new `is_zsh` function for defensively loading `~/.aliases` when running `brew` install/update commands (which runs `bash` shell)

### 1.1-13

* *[Brewfile]* Removed deprecated vscode plugins.
* *[software-updates-cron.sh]* Fix issue with BetterFox user.js not being put in correct Firefox profile; Added BetterZen's user.js into Zen profile.

### 1.1-12

* *[fresh-install-of-osx.sh]* Set PATH even if dotfiles repo is present - so that future scripts can be invoked without issues.
* *[Brewfile]* Cleaned up some softwares that I rarely use.
* *[.tcshrc]* Removed empty file

### 1.1-11

* *[.gitconfig]* Minor changes to decorate git log.
* *[.aliases]* Added `upreb_me` shell script that will intelligently run a shell script (if present) for the current folder or fall back to the global `git upreb` alias
* *[.npmrc]* Set some npm configurations to hide progress bar and save the exact version into the BOM file.

### 1.1-10

* *[.shellrc]* Removed 'depth' option while cloning repos since that causes rebases from the upstream repo to get corrupted.
* *[.gitconfig]* Added some [options recommended from the core git maintainers](https://blog.gitbutler.com/how-git-core-devs-configure-git/).

### 1.1-9

* Moved setting up of login items into the `Brewfile` so that can be managed along with the cask block itself.

### 1.1-8

* Minor cleanup (removed leftover references to Arc).

### 1.1-7

* *[software-updates-cron.sh]* Added more steps/commands to be run via a cron job.

### 1.1-6

* Minor refactoring to reuse utilize utility methods defined in `.shellrc`.

### 1.1-5

* *[.cshrc]* Removed empty file
* *[.shellrc]* Re-aligned colors for the success, warn, debug and error functions

### 1.1-4

* Simplify color output for scripts (avoid nesting) within the same line.

### 1.1-3

* *[.aliases]* `install_mise_versions` now handles config files from more language-version-managers.
* *[fresh-install-of-osx.sh]* Removed duplicate function defn: `build_keybase_repo_url`.
* *[fresh-install-of-osx.sh]* Moved some post-install steps into a new script which is invoked from the Brewfile's `at_exit` block.
* *[software-updates-cron.sh]* Corrected defensive checking of installed software before running some update commands.

### 1.1-2

* Moved `setup_login_item` function into the `Brewfile` since its used after app-installations.

### 1.1-1

* *[Brewfile]* Replaced `libreoffice` with `onlyoffice`.
* *[.aliases]* Fixed issue with `start_docker` and `stop_docker`.

### 1.0-53

* *[Brewfile]* Added `rsync` to be used from homebrew so as to avoid the recently announced RCE vulnerability.
* Changed the `DOTFILES_DIR` env var to use `${HOME}/.dotfiles` instead of `${HOME}/.bin-oss`.

#### Adopting these changes

* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
  cp "${HOME}/.bin-oss/files/--HOME--/custom.gitignore" "${HOME}/.gitignore"
  mv "${HOME}/.bin-oss" "${HOME}/.dotfiles"
  source "${HOME}/.shellrc"
  install-dotfiles.rb
  ```

* Quit and restart the Terminal application.

### 1.0-52

* Removed auto-configuration from rancher desktop to not manage/change the `PATH` env var since that's already done in [this line](./files/--ZDOTDIR--/.zshrc#L155) of the .zshrc file.

#### Adopting these changes

* Start rancher desktop, go into its preferences, and change the setting to not automatically set the `PATH`.
* Restart Terminal app and verify that `docker` is in your `PATH`.

### 1.0-51

* *[.aliases]* Uncommented `start_docker` and `stop_docker` and made them defensive.
* Removed 'ccleaner' preferences since I am no longer using it.

### 1.0-50

* All Firefox-based browsers are now handled for their respective `chrome` folders to be tracked and get updated as git repos.
* *[.aliases]* Added utility functions for `pull` and `push` similar to `st`, `count`, etc taking in an optional git repo.
* *[.shellrc]* Moved a utility function (`set_ssh_folder_permissions`) so that it can be reused.

#### Adopting these changes

* After rebasing, just quit and restart the terminal emulator so that the `.envrc` is processed. (Hint: Use `allow_all_direnv_configs` to accept and process all `.envrc` files in your system.)

### 1.0-49

* *[capture-raycast-configs.sh]* Automated initial password setup for Raycast export.

### 1.0-48

* *[.shellrc]* Extract common functions `strip_trailing_slash` and `extract_last_segment`.
* Use `unset` to jettison local variables once they are no longer needed.

#### Adopting these changes

* After rebasing, just quit and restart the terminal emulator so that the `.shellrc` is loaded into memory.

### 1.0-47

* *[capture-defaults.sh]* Added more macos preferences to be exported/imported for backup.
* Removed `Itsycal` since raycast and/or a desktop widget can be used instead of a dedicated application.

### 1.0-46

* Removed duplication (now `scripts/resurrect-repositories.rb` invokes the common function defined in the `.shellrc`).
* Removed usage of `eval` to simplify running of shell commands.

#### Adopting these changes

* After rebasing, just quit and restart the terminal emulator so that the `.shellrc` is loaded into memory.

### 1.0-45

* *[capture-raycast-configs.sh]* Added script to export/import raycast configs. More details can be found [here](Extras.md#capture-raycast-configssh). Code contributed by/adapted from @arunvelsriram's gist.
* Reuse utility functions defined in `.shellrc`

### 1.0-44

* *[recreate-repo.sh]* Fix an issue where a trailing slash would not properly process the repo in `${PERSONAL_PROFILES_DIR}` (ie would not force-squash)
* Cleaned `files/--PERSONAL_PROFILES_DIR--/custom.gitignore`

#### Adopting these changes

* After rebasing, run the following command prior to running the `install-dotfiles.rb` script.

  ```bash
  cp "${DOTFILES_DIR}/files/--PERSONAL_PROFILES_DIR--/custom.gitignore" "${PERSONAL_PROFILES_DIR}/.gitignore"
  ```

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

### 1.0-42

* Added dev dependencies for zen-browser.
* Unignore some files from the `personal` folder that were somehow ignored globally.

### 1.0-41

* Added new script `scripts/add-upstream-git-config.sh`.

### 1.0-40

* Fixed documentation and reduced hardcoding of upstream repo-owner's name.

### 1.0-39

* Introduced [a new script](scripts/cleanup-browser-profiles.sh) to cleanup browser profiles folders.
* *[fresh-install-of-osx.sh]* Minor refactoring to enhance `clone_repo_into` to handle an optional target git branch which is also validated.

### 1.0-38

* *[.aliases]* Added extra checks for the `status_all_repos` and `count_all_repos` utility functions.

### 1.0-37

* Removed `Raycast` from being tracked via the profiles repo since that corrupts Raycast's internal db.

#### Adopting these changes

**These instructions are only necessary if you had previously adopted changes from v1.0-24**

* In Raycast, use the `Export Settings & Data` option to export your current settings.
* After successfully exporting the settings, quit Raycast and ensure that Raycast is completely shut down.
* Rebase the dotfiles repo, fix any conflicts and run the `install-dotfiles.rb` script.
* Manually reconcile the diffs / dirty state of `files/--PERSONAL_PROFILES_DIR--/custom.gitignore` with `$PERSONAL_PROFILES_DIR/.gitignore` on your local machine
* Run the following commands in the terminal

  ```bash
  git -C "${DOTFILES_DIR}" restore files/--PERSONAL_PROFILES_DIR--/custom.gitignore
  cp "${DOTFILES_DIR}/files/--PERSONAL_PROFILES_DIR--/custom.gitignore" "${PERSONAL_PROFILES_DIR}/.gitignore"
  rm -rf "${HOME}/Library/Application Support/com.raycast.macos"
  mv "${PERSONAL_PROFILES_DIR}/Raycast" "${HOME}/Library/Application Support/com.raycast.macos"
  git -C "${PERSONAL_PROFILES_DIR}" rm -rf Raycast
  open /Applications/Raycast.app
  ```

* Once Raycast is restarted *AND if it shows an error about the database being corrupt*, then choose the `Reset` option, and use the `Import Settings & Data` option to import your previously exported settings back in.
* Once the above steps are done, if you rerun the `install-dotfiles.rb` script, it should not show any dirty files (especially the 2 `custom.gitignore` files) - and if this is the case, your setup is now back to normal working state.

### 1.0-36

* Use `is_git_repo` instead of `is_directory` if the next command(s) expects it to be a git repo.
* Remove Arc from `Brewfile` (since I moved to [Zen](https://zen-browser.app/)).

### 1.0-35

* Use `git-restore-mtime` from `git-tools` (as opposed to `git-utimes` from `git-extras`) since its > 1x faster performance.

### 1.0-34

* Set the DNS server to '8.8.8.8' only if running in a Jio network.
* Introduce PDFGear and KeyClu.
* Fixed some old documentation.

### 1.0-33

* Reuse utility functions defined in `.shellrc`.

### 1.0-32

* *[fresh-install-of-osx.sh]* Added date calculation in `fresh-install-of-osx.sh` to track total execution time.

### 1.0-31

* *[approve-fingerprint-sudo.sh]* Handled case to execute `approve-fingerprint-sudo.sh` based on touchId hardware.

### 1.0-30

* *[resurrect-repositories.rb]* Handled the case where git wouldn't allow cloning a repo into a pre-existing, non-empty folder.
* *[.zshrc]* Handled case where docker-related aliases were not setup since it was not in the `PATH` when `files/--HOME--/.aliases` was evaluated.

### 1.0-29

* *[capture-defaults.sh]* Removed some applications that I no longer use.
* *[fresh-install-of-osx.sh]* Replaced `TODO` with explanation for future reference as to why we can't use `homebrew` to install omz custom plugins.

### 1.0-28

* *[Brewfile]* Stop processing the `Brewfile` such that the minimal installation can happen in a shorter duration of time. This is controlled by the env var `HOMEBREW_BASE_INSTALL` which is set in the `fresh-install-of-osx.sh` script when installing from scratch.

### 1.0-27

* *[.aliases]* Added 2 new utility functions: `count` and `count_all_repos`

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

    ```bash
    rm -rf ${HOME}/.aliases.custom ${HOME}/.zshrc.custom ${HOME}/.oh-my-zsh/custom/plugins/zsh-defer
    cp files/--HOME--/custom.gitignore ${HOME}/.gitignore
    cp files/--PERSONAL_PROFILES_DIR--/custom.gitignore ${PERSONAL_PROFILES_DIR}/.gitignore
    install-dotfiles.rb
    ```

* Quit and restart your Terminal application for the env vars, aliases & functions to be re-evaluated into the session memory.
* Run `bupc` to cleanup brews and casks.

*Note*: This version has been successfully tested on a Macbook M1 on 22 Dec, 2024.

### 1.0-25

* *[capture-defaults.sh]* Capture defaults script now aborts when the `PERSONAL_CONFIGS_DIR` env var is not defined.
* *[.shellrc]* Extracted common utility function to remove duplication and invoke them in the setup scripts.
* *[fresh-install-of-osx-advanced.sh]* Fixed potential issue with the `PATH` not being updated if the fresh-install-advanced script was run without starting a new terminal session.
* *[.aliases]* Added a new `profiles` alias to handle git repos checked out into the `PERSONAL_PROFILES_DIR`.

### 1.0-24

* Capture the Raycast configs/extensions/etc in the profiles repo

#### Adopting these changes

* Open Terminal and run the `install-dotfiles.rb` script.
* Change the current directory in terminal to the profiles repo (`direnv` will take care of the rest)

### 1.0-23

* Incorporate the [natsumi-browser](https://github.com/greeeen-dev/natsumi-browser) into the Zen browser profile.

### 1.0-22

* *[.shellrc]* Moved functions that are only needed in the basic fresh-install script into that so as to reduce shell startup time.

*Note*: This version has been successfully tested on a Macbook M1 on 19 Dec, 2024.

### 1.0-21

* *[fresh-install-of-osx-advanced.sh]* Nested conditions and print more specific warning message when skipping cloning of the home and profiles repos.
* *[.shellrc]* Extracted some utility functions to remove duplication and invoke them in the setup scripts.

#### Adopting these changes

* Manually edit your `${HOME}/.ssh/config` file, and change all occurrences of `~` to `${HOME}`

### 1.0-20

* Removed necessity of quitting and restarting the Terminal application between executing the `fresh-install-of-osx.sh` and `fresh-install-of-osx-advanced.sh`.
* *[.shellrc]* Extracted some utility functions to remove duplication and invoke them in the setup scripts.
* *[.shellrc]* Renamed `ensure_dir_exists_if_var_defined` into `ensure_dir_exists` and `clone_if_not_present` into `clone_omz_plugin_if_not_present`.
* *[Brewfile]* Removed `gs`, `wifi-password` and `virtualbox`.

*Note*: This version has been successfully tested on a Macbook M1 on 16 Dec, 2024.

#### Adopting these changes

* Run `git delete-tag success-tested-on-m1; git push origin :success-tested-on-m1` to cleanup the defunct tag.

### 1.0-19

* *[Brewfile]* Added `keycastr` to help with pairing and presentations of screen-grabs.
* Added some more logging while running the fresh-install scripts.

### 1.0-18

* Restructured `Brewfile` to convey what are bare minimum formulae vs recommended vs optional ie left to the user's choice.

#### Adopting these changes

* The reason for this restructuring is explained up above. Since most of the adoptees have customized this file, it will probably result in conflicts. Please be diligent in resolving the conflicts.

### 1.0-17

* All GH urls now also take into account the branch that's being tested for the setup scripts. Read the [new section](./README.md#how-to-test-changes-in-your-fork-before-raising-a-pull-request) in the README if you are making changes that you want to test against a PR branch before the PR is merged.

### 1.0-16

* Moved some of the core zsh config files from `files/--HOME--/` to `files/--ZDOTDIR--/` to accommodate custom location of `ZDOTDIR`.
* *[.shellrc]* Merged all relevant lines from `files/--ZDOTDIR--/.zprofile` into `files/--HOME--/.shellrc` and deleted `files/--ZDOTDIR--/.zprofile` since that is the first file loaded during the fresh machine setup. This also avoids the defensive definition of `ZDOTDIR` in duplicate files.

#### Adopting these changes

* After rebasing, you will end up with conflicts. The env vars that were previously defined in `files/--ZDOTDIR--/.zprofile` have been moved into `files/--HOME--/.shellrc`. You might have to manually fix them. You can go ahead and delete the `${HOME}/.zprofile` since that is no longer needed.
* Run `install-dotfiles.rb` so that the symlinked zsh config files in `${HOME}` point to the correct locations (`files/--ZDOTDIR--/` instead of `files/--HOME--/`)

### 1.0-15

* *[README.md]* Fixed some grammatical errors in README.
* *[.gitconfig]* Added new git alias for logs.

### 1.0-14

* Use 'zsh-defer' to try to bring down shell startup time.

#### Adopting these changes

* Run `fresh-install-of-osx.sh` so that the `zsh-defer` plugin is cloned to the correct directory.
* Restart terminal for the deferred-loading to take effect. (No harm in keeping the old session).

### 1.0-13

* *[.shellrc]* Introduced new utility functions `section_header` and `debug` and standardized on usages.

### 1.0-12

* Reverted changes from v1.0.9 related to 'bupc' since the 1st cleanup might be skipped due to the '||' condition status

### 1.0-11

* Converted from 'iBar' menubar app to 'Ice' since its open source and seems to have better features. This also removes the need to login into the App Store!

### 1.0-10

* Fix zsh auto-completion since some of the options were set after the `compinit` invocation
* *[.zprofile]* Ensure that directories are created for env vars defined in `.zprofile`
* `setopt` paramters are case-insensitive and can handle underscore and so changed them for readability
* *[.shellrc]* Introduced new utility function `ensure_dir_exists_if_var_defined` to help in cases where `code-gist` used to create unsaved files instead of directories for undefined env vars

### 1.0-9

* Remove redundant cleanup in 'bupc'
* Removed MS Teams and MS Remote Desktop

#### Adopting these changes

* Restart terminal for the revised alias function to get loaded. (No harm in keeping the old session; just that it will perform an extra step unnecessarily on `bupc` alias)

### 1.0-7

* *[fresh-install-of-osx.sh]* Fix issue when running in a fresh/vanilla machine since 'ZDOTDIR' was undefined.

### 1.0-6

* *[install-dotfiles.rb]* Fix issue when creating the include line for `~/.ssh/config` if it was not present.

### 1.0-5

* *[approve-fingerprint-sudo.sh]* Persists authorization config for triggering touchId when running sudo commands in terminal across software updates.

#### Adopting these changes

* Run `approve-fingerprint-sudo.sh`

### 1.0-4

* *[install-dotfiles.rb]* Refactored environment variable resolution logic to use `gsub!` for improved performance.

### 1.0-3

* Moved all files & nested folders inside the `files` directory into `files/--HOME--` to make that location explicit (earlier it was implied)

### 1.0-2

* *[install-dotfiles.rb]* Refactored the logic to handle ssh global configuration file for ease of readability and maintainability.

### 1.0-1

* *[Brewfile]* Added `virtualbox` to test out linux as a Virtual machine.
* *[CHANGELOG.md]* Added changelog which will be maintained going forward for each commit.
* *[README.md]* Added a [new section](README.md#how-to-upgrade--catch-up-to-new-changes) detailing steps to adopt updates/catchups for new changes on an ongoing basis.
* Changed all colored messages to be uniform and added a `success` function to print in green. These are optimized for a dark theme in your terminal emulator.

### 1.0

* `install-dotfiles.rb` can now handle multiple env vars for nested files/folders in the `files` sub-folder. They follow the naming convention of the env var being enclosed within 2 pairs of hyphens (`--`). For eg, `files/--PERSONAL_PROFILES_DIR--/.envrc` will be symlinked on your local machine into `${HOME}/personal/<yourLocalUsername>/profiles/.envrc` assuming that the `PERSONAL_PROFILES_DIR` env var has been defined. This is not a breaking change.

#### Adopting these changes

* Since I recreated the `1.0` tag as part of this push, you might need to delete the tag in both your local and your remote and then do `git upreb`.
* Run the `install-dotfiles.rb` script which will automatically remove the older (broken) symlink and recreate the new one in the correct location.
