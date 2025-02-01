As documented in the README's [adopting](README.md#how-to-adoptcustomize-the-scripts-to-your-own-settings) section, this repo and its scripts are aimed at developers/techies. If you are stuck or need help in any fashion, you can reach out to me at my email.

For those who follow this repo, here's the changelog for ease of adoption:

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
