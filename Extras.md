## add-upstream-git-config.sh

This script can be used to quickly add a new upstream remote to the specified git repo. The name of the new remote is hardcoded to `upstream`. The rest of the url remains the same with just the username switched to the specified username.

  ```bash
  add-upstream-git-config.sh -d <target-folder> -u <upstream-repo-owner>
  ```

## capture-prefs.sh

This script is useful to capture the preferences of the known applications (both system-installed and custom-installed applications) using the `defaults read` command. It can be used to both export the preferences/settings (from the old system) or import them (into the new system). As of version 2.0.4, added a new shell function to help with the above called: `find_and_append_prefs`.

Two data files govern which domains are processed:

- **[`scripts/data/capture-prefs-allowed-list.txt`](scripts/data/capture-prefs-allowed-list.txt)** — the list of preference domains to export/import. Add entries here (one domain per line) to include an app's preferences in the backup. Use `find_and_append_prefs <search-string>` to discover and append a domain automatically; it will warn and refuse to add the domain if it appears on the denied list.
- **[`scripts/data/capture-prefs-denied-list.txt`](scripts/data/capture-prefs-denied-list.txt)** — domains that must never be exported or imported. These contain machine-specific identifiers (device UUIDs, hardware MAC addresses), account-bound credentials (Apple ID DSID, MDM enrollment tokens, AirTag beacon keys), or ephemeral CloudKit cache state that is meaningless or harmful when applied to a different machine. Any domain present in this file is skipped with a warning during both export and import, even if it also appears in the allowed list. `find_and_append_prefs` also checks this file before appending to the allowed list.

## cleanup-browser-profiles.sh

This script is used to cleanup browser profiles folders (delete cache, session and other files that will anyways be recreated when you restart that browser). It can be safely invoked even if that browser is running (in which case it will skip processing after printing a warning to quit that application).

The lists of files and directories to clean are maintained in [`scripts/data/cleanup-browser-files.txt`](scripts/data/cleanup-browser-files.txt) and [`scripts/data/cleanup-browser-dirs.txt`](scripts/data/cleanup-browser-dirs.txt).

## fresh-install-of-osx.sh

This is the main setup script for a fresh macOS installation. It is idempotent and can be run multiple times safely. The script:

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

The script has two modes controlled by the `FIRST_INSTALL` environment variable: when set to `true`, it performs a minimal bootstrap suitable for a vanilla OS (with extended curl timeouts and relaxed error handling for Homebrew operations). On subsequent runs, it performs the full setup.

See the [GettingStarted](GettingStarted.md) guide for the recommended invocation.

## install-dotfiles.rb

Basically, to get started with the dotfiles, you just need to run the `${DOTFILES_DIR}/scripts/install-dotfiles.rb` script. If you have that folder in the `PATH`, then you don't need the fully qualified or relative location (only file name is enough to run it).

* If you already have any of the dotfiles that are managed via this repo, *DON'T WORRY!* Your files will be moved to the cloned folder - so that you can then commit and push them to your fork!
* This script will also handle nested config files - as long as they are already present in this repo.
* Special handling (copy instead of symlink) for `custom.git*` files (`.gitattributes`, `.gitignore`) — git itself does not handle symlinks reliably for its own core config files, so these are copied rather than symlinked. Resolution when both the source and the destination exist as real files: on `FIRST_INSTALL` the destination always wins (moved into repo, then copied back); otherwise the file with the **newer mtime** wins. Prefer editing the `custom.git*` source files in this repo; if you edit the destination directly, ensure its mtime is newer before re-running `install-dotfiles.rb`.
* If you do not want a specific file from the home folder to be overridden, simply delete it from this repo's `files` folder - and it will not be processed.
* If you wish to add a new file to be tracked and managed via this backup mechanism, add it into the appropriate `files/--VAR--/` subdirectory matching the destination env var. The `--VAR--` naming convention: each subdirectory name is an environment variable name wrapped in double-dashes (e.g. `--HOME--` resolves to `$HOME`, `--XDG_CONFIG_HOME--` resolves to `$XDG_CONFIG_HOME`). Files inside are symlinked into the resolved directory. Plain subdirectory names without the `--VAR--` pattern are also valid — they resolve literally from `/` (e.g. `files/etc/` → `/etc/`), but the `--VAR--` convention is preferred for portability across machines where paths may differ.

## osx-defaults.sh

This script is the erstwhile script to codify the macos setup. It can be used to setup some options, but it hasn't been maintained for newer versions of macos. Though the system will not get corrupted, there might be cruft introduced into the system preferences which might not be easy to identify and remove at a later point in time. Use caution and YMMV.

## post-brew-install.sh

This script is a collection of commands that need to be run after `brew bundle` to set up proper command-line usage of some GUI apps (VSCode, Rancher, etc.), remove conflicting zsh completion files, and clean up legacy executable paths. It is called automatically by `fresh-install-of-osx.sh` after `brew bundle` completes. It can also be run manually at any time — it is idempotent.

## recreate-repo.sh

Usually, over time, if a repo has lots of branches that were deleted or became stale, and constant rebases done - it can lead to the repo bloating in size (both on local and remote). This is especially true of the browser-profiles repo in my usage since I have a cron job setup to amend the repo with the new state files. To effectively reduce the size on the remote so that any future clone does not pull down dangling commits and other cruft, the simplest way that I have found is to recreate the remote after running the `git cc` command on the local.

  ```bash
  recreate-repo.sh [-f] -d <repo-folder>
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

## run-all.sh

This script will find all git repositories within the specified `FOLDER` (defaults to the current directory), filtered by `FILTER` (defaults to empty string meaning that it will not filter anything; accepts regex) and for a minimum depth of `MINDEPTH` (defaults to 1) and a maximum depth of `MAXDEPTH` (defaults to 3); and then runs the specified commands in each of the matched git repos. This script is not limited to only running 'git' commands - it can run any shell command! Examples:

```bash
  run-all.sh git status                                      # to get the git status of all git repos
  run-all.sh git clean -fxd                                  # to clean all git repos
  run-all.sh git remote prune origin                         # to run the git remote prune command
  run-all.sh git add -p                                      # to add all modified (unstaged) files for a commit eventually
  run-all.sh find . -iname patch.txt --exec rm -rfv {} \;    # find all files with the name 'patch.txt'
```

You can also control the starting folder by specifying the `FOLDER` env var, the filter for matching either the path and/or the name of the folders to be processed using `FILTER` (including using regular expressions for the same!) and also simultaneously control the depth using the `MINDEPTH` and `MAXDEPTH` env vars. So, for eg, to search in multiple nested folders starting at `~/dev`, you can use the following command:

```bash
  FOLDER=~/dev MINDEPTH=2 MAXDEPTH=5 FILTER="oss|zsh|antidote" run-all.sh git status
  FOLDER=~/dev MINDEPTH=2 MAXDEPTH=5 run-all.sh git fetch
```

Note: **Any unix command can be run** (specific to the shell that you are currently using) or git commands. These commands are run within the context of each git repository that is matched after applying the filter logic.

## setup-login-item.sh

This script was originally present as a function within the `~/.aliases` file, but, since loading this became cumbersome within `bash` (as part of the post-installation step for specific casks), it made sense to extract it out as a standalone script. This script will be used to setup specific applications as login items in the macOS system preferences.

  ```bash
  setup-login-item.sh -a <app-name>
  ```

## software-updates-cron.sh

There are so many tools installed, and some of them require their local caches/dbs/configs/etc to be updated from time to time. Rather than remembering each tool and its invocation (for updates), this script is a single place where any new tooling is added so that I don't need to remember the incantation for each separately.
Run the following command to generate and update your crontab:

  ```bash
  recron
  ```

## Zsh Autoload Functions

A set of git-workflow functions are available as zsh autoloads (lazily loaded on first call) from `files/--XDG_CONFIG_HOME--/zsh/`:

| Function | What it does |
|----------|-------------|
| `cc` | Compacts the git repo (`git cc` — garbage collection, pruning, etc.) |
| `push` | Pushes current branch; handles force-with-lease for rebased branches |
| `pull` | Pulls with rebase; handles shallow-clone unshallowing |
| `upreb` | Fetches upstream and rebases the current branch onto it |
| `st` / `status_all_repos` | Git status for the current repo / all tracked repos |
| `update_all_repos` | Pulls/rebases all tracked repos in one shot |
| `count` | Counts commits in the current branch ahead of the remote |

Each of these supports **per-project overrides**: if a file named `<cmd>-<current-directory-name>.sh` exists in `$PERSONAL_BIN_DIR` and is executable, it is sourced instead of the default implementation. This lets you customize behaviour for specific projects without modifying the shared function. For example, a file `$PERSONAL_BIN_DIR/push-my-project.sh` will be sourced when you run `push` from inside a directory called `my-project`.

## delete_caches

Removes all compiled zsh bytecode (`.zwc` files) and other generated cache files (Homebrew shellenv cache, starship cache, mise activation cache, git version cache). Run this when zsh startup behaves unexpectedly or after making significant changes to startup files — zsh will regenerate everything on the next shell open.

```zsh
delete_caches
```

Back to the [readme](README.md#extrasdetails)
