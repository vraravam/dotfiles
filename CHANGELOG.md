As documented in the README's [adopting](README.md#how-to-adoptcustomize-the-scripts-to-your-own-settings) section, this repo and its scripts are aimed at developers/techies. If you are stuck or need help in any fashion, you can reach out to me at my email.

For those who follow this repo, here's the changelog for ease of adoption:

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
