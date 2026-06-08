# Extras

Reference documentation for the utility scripts bundled in this repo. Each section describes what a script does and how to invoke it. For the internal architecture — how the logging system works, the `.shellrc` vs `.aliases` split, startup optimisation, cron safety, and more — see the [Technical Deep Dive](TechnicalDeepDive.md).

## add-upstream-git-config.rb

When you fork a repo, you need an `upstream` remote pointing to the original so you can fetch and rebase against it. This script adds that remote automatically, deriving the upstream URL from the existing `origin` URL by substituting the owner username — so you do not have to look up or copy-paste the URL manually. The new remote is always named `upstream`.

  ```zsh
  add-upstream-git-config.rb -d <target-folder> -u <upstream-repo-owner>
  ```

## capture-prefs.sh

This script exports or imports the preferences of known applications (both system and custom-installed) using the `defaults` command. Use `-e` to export from the current machine into the dotfiles repo, and `-i` to import into a new machine.

Three data files govern which domains are processed and how:

- **[`scripts/data/capture-prefs-allowed-list.txt`](scripts/data/capture-prefs-allowed-list.txt)** — domains to export/import. Use `find_and_append_prefs <search-string>` to discover and append a domain automatically; it checks the denied list before appending.
- **[`scripts/data/capture-prefs-denied-list.txt`](scripts/data/capture-prefs-denied-list.txt)** — domains that must never be exported or imported (machine-specific identifiers, account credentials, ephemeral sync state). Each entry has an inline comment explaining why.
- **[`scripts/data/capture-prefs-excluded-keys.txt`](scripts/data/capture-prefs-excluded-keys.txt)** — individual keys within allowed domains that are stripped before export or import (display geometry, device UUIDs embedded in per-domain keys).

See [Technical Deep Dive § 11](TechnicalDeepDive.md#11-capture-prefssh-architecture) for how key stripping, XML plist conversion, and cron-safe export work internally.

## cleanup-browser-profiles.rb

Cleans up browser profile folders by vacuuming SQLite databases larger than 10 MB and deleting known cache/session files. Skips processing if the target browser is currently running (prints a warning to quit that application first).

The lists of files and directories to clean are maintained in [`scripts/data/cleanup-browser-files.txt`](scripts/data/cleanup-browser-files.txt) and [`scripts/data/cleanup-browser-dirs.txt`](scripts/data/cleanup-browser-dirs.txt).

## fresh-install-of-osx.sh

This is the main setup script for a fresh macOS installation. It is idempotent (see [Technical Deep Dive § 1.4](TechnicalDeepDive.md#14-idempotency)) and can be run multiple times safely. The script:

* Detects Intel vs Apple Silicon architecture automatically
* Installs Homebrew, antidote (zsh plugin manager), and Starship prompt
* Sets up the dotfiles repo and symlinks all config files
* Installs essential CLI tools and GUI applications via the Brewfile
* Configures macOS system defaults
* Sets up SSH keys and permissions
* Resurrects tracked git repositories *(skipped by default — `resurrect_tracked_repos` is commented out; must be run manually)*
* Installs programming language versions via mise
* Restores application preferences from backups
* Configures cron jobs for ongoing maintenance

The script has two modes, distinguished by the `FIRST_INSTALL` environment variable (checked via `is_first_install`): a minimal bootstrap for a vanilla OS — with extended curl timeouts and relaxed Homebrew error handling because the network may be unreliable and not all tools exist yet — and a full idempotent run for an already-configured machine.

See the [GettingStarted](GettingStarted.md) guide for the recommended invocation. See [Technical Deep Dive § 12](TechnicalDeepDive.md#12-two-phase-preference-architecture) for the ordering rationale.

## install-dotfiles.rb

Run `${DOTFILES_DIR}/scripts/install-dotfiles.rb` to symlink all dotfiles from this repo into their target locations. If this folder is in `PATH`, you can call it by filename alone.

- Existing files at symlink targets are **moved into the repo** (never silently discarded) before the symlink is created. Use `--force` to delete rather than adopt.
- `custom.git*` files (`.gitignore`, `.gitattributes`) are **copied** rather than symlinked, because git does not handle symlinks reliably for its own core config.
- The `files/--VAR--/` directory naming convention resolves each `--ENV_VAR--` name to the env var it wraps (`--HOME--` → `$HOME`, etc.) and symlinks files inside into the resolved path.

See [Technical Deep Dive § 9](TechnicalDeepDive.md#9-install-dotfilesrb-mechanics) for conflict resolution rules, mtime tie-breaking, and `FIRST_INSTALL` behaviour.

## osx-defaults.sh

Codifies a **partial baseline** of macOS system and application preferences as a repeatable script. It kills affected apps upfront (graceful SIGTERM), applies all `defaults write` calls, then restarts them via an EXIT trap — so the settings take effect immediately without a logout.

### Two-phase preference architecture

Preferences are managed in two ordered phases on every fresh install. The order is load-bearing:

**Phase 1 — `osx-defaults.sh -s` (baseline seed)**

Seeds known-good starting values for settings the user has not yet configured via the UI on a fresh machine. It is intentionally incomplete — it only codifies defaults where a specific starting value is worth establishing. It does **not** attempt to capture every preference.

**Phase 2 — `capture-prefs.sh -i` (UI-configured overrides)**

Imports the preferences the user previously exported from their old machine via `capture-prefs.sh -e`. Because this runs *after* phase 1, every UI-configured value overwrites the corresponding baseline. The user's deliberate choices always win.

`fresh-install-of-osx.sh` enforces this order:

```zsh
osx-defaults.sh -s    # phase 1 — seed baseline
capture-prefs.sh -i   # phase 2 — UI-configured values override on top
```

Never reverse the order — running `capture-prefs.sh -i` before `osx-defaults.sh -s` would cause `osx-defaults.sh` to overwrite the user's restored preferences.

### What belongs where

| Preference type | Where it goes |
|---|---|
| One-time baseline the user will never change via UI | `osx-defaults.sh` |
| Something the user configures through the app's UI | `capture-prefs-allowed-list.txt` (not `osx-defaults.sh`) |
| Ephemeral state (window positions, sync cursors, UUIDs) | `capture-prefs-excluded-keys.txt` or `-denied-list.txt` — nowhere else |

See [Technical Deep Dive § 12](TechnicalDeepDive.md#12-two-phase-preference-architecture) for the full architectural rationale and ordering constraint.

## post-brew-install.rb

This script runs post-bundle cleanup and plugin setup that cannot live in the Brewfile itself. It removes conflicting zsh completion files, trusts known taps, and updates antidote plugins. It is called automatically by `fresh-install-of-osx.sh` after `brew bundle` completes. It can also be run manually at any time — it is idempotent.

## recreate-repo.rb

Usually, over time, if a repo has lots of branches that were deleted or became stale, and constant rebases done - it can lead to the repo bloating in size (both on local and remote). This is especially true of the browser-profiles repo in my usage since I have a cron job setup to amend the repo with the new state files. To effectively reduce the size on the remote so that any future clone does not pull down dangling commits and other cruft, the simplest way that I have found is to recreate the remote after running the `git cc` command on the local.

  ```zsh
  recreate-repo.rb [-f] -d <repo-folder>
  ```

## resurrect-repositories.rb

I usually reimage my laptop once every couple of months. This script is useful as a catalog of all repos that I have ever worked on, and some/most which are marked `active: true` in the yaml to resurrect back into the new machine/image. The yaml (described below) also allows to install the required languages and their versions in an automated manner so as to avoid having to read the `README.md` or the `CONTRIBUTING.md` file for each repo on each re-image!

This script is useful to flag existing repositories that need to be backed up; and the reverse process (ie resurrecting repo-configurations from backup) is also supported by the same script!
To run it, just invoke by `resurrect-repositories.rb` if this folder is already setup in the `PATH`. This will then print the usage by default and you can follow the required parameters.

This script can also be used to generate the basic version of the below yaml (onto the console stdout). See the `-g` option in the usage on how to use this feature.

The config file for this script is a yaml file that is passed into this script as a parameter and the structure of this configuration file is:

```yaml
- folder: "${PROJECTS_BASE_DIR}/oss/git_scripts"
  remote: https://github.com/vraravam/git_scripts
  other_remotes:
    upstream1: <upstream remote url1>
    upstream2: <upstream remote url2>
  active: true
  post_clone:
    - ln -sf "${PERSONAL_CONFIGS_DIR}/XXX.gradle.properties" ./gradle.properties
    - git-crypt unlock XXX
    - echo "java 21" > ./.tool-versions
```

* `folder` (mandatory) specifies the target folder where the repo should reside on local machine. If the folder name starts with `/`, then its assumed that the path starts from the root folder; if not, then its assumed to be relative to where the script is being run from. The ruby script also supports glob expansion of `~` to `${HOME}` if `~` is used. It can also handle shell env vars if they are in the format `${<env-key>}`
* `remote` (mandatory) specifies the remote url of the repository
* `other_remotes` (optional) specifies a hash of the other remotes keyed by the name with the value of the remote url
* `active` (optional; default: false) specifies whether to process this folder/repo or not on your local machine
* `post_clone` (optional; default: empty array) specifies other `bash` commands (in sequence) to be run once the resurrection is done - for eg, symlink a '.envrc' file if one exists

## run-all.rb

This script finds all git repositories within the specified `FOLDER` (defaults to the current directory), filtered by `FILTER` (regex pattern; defaults to empty = match all) for a minimum depth of `MINDEPTH` (defaults to 1) and a maximum depth of `MAXDEPTH` (defaults to 4), then runs the specified command in each matched repository's root directory.

**Key feature**: Commands run in the context of each git repo's root directory (the folder containing `.git`). This works for both git commands (`git status`, `git pull`) and any other shell command (`ls`, `find`, custom scripts, etc.).

Examples:

```zsh
  run-all.rb git status                                      # get git status of all repos
  run-all.rb git clean -fxd                                  # clean all repos
  run-all.rb git remote prune origin                         # prune remotes in all repos
  run-all.rb git add -p                                      # stage files interactively in each repo
  run-all.rb ls -la                                          # list files in each repo root
  run-all.rb find . -name "*.rb" -type f                     # find Ruby files in each repo
```

You can control the search scope and filtering using environment variables:

```zsh
  FOLDER=~/dev MINDEPTH=2 MAXDEPTH=5 FILTER="oss|zsh|antidote" run-all.rb git status
  FOLDER=~/dev MINDEPTH=2 MAXDEPTH=5 run-all.rb git fetch
  FILTER="dotfiles" run-all.rb git pull
```

**Note**: Any shell command can be run — not just git commands. Each command executes in the context of the git repository root, giving you access to the repo's files and structure.

## setup-login-item.sh

Some apps must be registered as macOS login items programmatically after installation — the System Settings UI is not scriptable in a repeatable way. This script handles that registration so `fresh-install-of-osx.sh` can set up login items unattended. It is also safe to run manually at any time.

  ```zsh
  setup-login-item.sh -a <app-name>
  ```

## software-updates-cron.sh

There are so many tools installed, and some of them require their local caches/dbs/configs/etc to be updated from time to time. Rather than remembering each tool and its invocation (for updates), this script is a single place where any new tooling is added so that I don't need to remember the incantation for each separately.
Run the following command to generate and update your crontab:

  ```zsh
  recron
  ```

See [Technical Deep Dive § 8](TechnicalDeepDive.md#8-cron-safety-mechanisms) for how cron safety, `sudo` guards, and TTY detection work internally.

## Zsh Autoload Functions

A set of git-workflow functions are available as zsh autoloads (lazily loaded on first call) from `files/--XDG_CONFIG_HOME--/zsh/`:

| Function | What it does | Supports override? |
|----------|-------------|:-----------------:|
| `cc` | Compacts the git repo (`git cc` — garbage collection, pruning, etc.) | ✓ |
| `count` | Counts commits in the current branch ahead of the remote | ✓ |
| `pull` | Pulls with rebase; handles shallow-clone unshallowing | ✓ |
| `push` | Pushes current branch; handles force-with-lease for rebased branches | ✓ |
| `st` | Git status for the current repo | ✓ |
| `upreb` | Fetches upstream and rebases the current branch onto it | ✓ |
| `status_all_repos` | Git status for all tracked repos (HOME, dotfiles, profiles, chrome folders) | — |
| `update_all_repos` | Stages and commits all changes in the HOME and profiles repos | — |

`status_all_repos` and `update_all_repos` do not support per-project overrides — they operate on a fixed set of repos and a cwd-based override would not be meaningful.

### Per-project overrides

For the six commands marked ✓, if a file named `<cmd>-<current-directory-name>.sh` exists in `$PERSONAL_BIN_DIR` and is executable, it is sourced in the current shell instead of the built-in implementation.

**Example**: to customise `push` when inside a directory named `my-project`, create:

```zsh
# $PERSONAL_BIN_DIR/push-my-project.sh

# All functions and env vars from .shellrc and .aliases are available because
# this file is sourced (not exec'd) in the current interactive shell.

# Run whatever pre-push steps are needed, then call the default implementation.
info "Running pre-push checks for my-project..."
some_check || { warn "Pre-push check failed — aborting."; return 1; }

# Call the private default implementation directly to avoid infinite recursion.
# dispatch_or_fallback already resolved to this file, so calling push() again
# would loop. _push (or _st, _count, etc.) is always the safe fallback target.
_push "$@"
```

The override file receives the same arguments the user passed to the public command (`"$@"`). It runs in the current shell, so `return 1` correctly aborts the operation without killing the terminal.

See [Technical Deep Dive § 10](TechnicalDeepDive.md#10-per-project-script-overrides) for the internal mechanics.

## delete_caches

Removes all compiled zsh bytecode (`.zwc` files) and other generated cache files (Homebrew shellenv cache, starship cache, mise activation cache, git version cache). Run this when zsh startup behaves unexpectedly or after making significant changes to startup files — zsh will regenerate everything on the next shell open.

```zsh
delete_caches
```

Back to the [readme](README.md#extrasdetails)
