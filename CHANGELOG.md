As documented in the README's [adopting](README.md#how-to-adoptcustomize-the-scripts-to-your-own-settings) section, this repo and its scripts are aimed at developers/techies. If you are stuck or need help in any fashion, you can reach out to the [owner of the the parent repo](https://github.com/vraravam) from where this was forked.

For those who follow this repo, here's the changelog for ease of adoption:

### 3.0.0

* Squashed all commits into a single commit.
* Tested on a fresh vanilla macos (26.2) machine.

#### Adopting these changes

* Quit all browsers completely
* Rebase from upstream, resolve conflicts, and then proceed with the following steps:

  ```bash
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
  git -C "${DOTFILES_DIR}" checkout files/--PERSONAL_PROFILES_DIR--/custom.gitignore
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
