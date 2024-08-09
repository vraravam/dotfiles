# Background

This repo was created from the gists that I was using to help others adopt my machine setup. It contains the common dotfiles as well as the scripts that I use to share the machine setup. These scripts are idempotent and can run on a vanilla OS as well as once the whole setup has been completed. Each script will warn the users if its skipping a step, and if you want to rerun the script but force that step, you just need to delete the control `if` condition (you should have a basic understanding of shell programming to figure out what to delete/how to force without bypass).
Most of the folder structures are governed by the following environment variables [defined here](files/.zprofile). If you do not wish to configure a specific folder, just delete it from the `.zprofile` and all other setup steps should adhere to that.

| Env var| Meaning | Default Value |
| -------|---------|---------------|
| `GH_USERNAME` | The github username | "vraravam" |
| `UPSTREAM_GH_USERNAME` | Vijay's github username for setting upstream remote **Do NOT change** | "vraravam" |
| `PROJECTS_BASE_DIR` | All codebases are cloned into a subfolder of this folder | "${HOME}/dev" |
| `PERSONAL_CONFIGS_DIR` | Many configuration files (eg `.envrc`, `.tool-versions`) for specific repos are stored here and symlinked to their target destination | "${HOME}/personal/dev" |
| `PERSONAL_PROFILES_DIR` | All browser profiles are captured in this folder | "${HOME}/personal/$(whoami)/profiles" |
| `PERSONAL_BIN_DIR` | Scripts that are not shared as part of this repo are present here | "${HOME}/.bin" |
| `DOTFILES_DIR` | This repo is cloned here | "${HOME}/.bin-oss" |
| `KEYBASE_USERNAME` | Keybase username | "avijayr" |
| `KEYBASE_HOME_REPO_NAME` | Keybase home repo name | "home" |
| `KEYBASE_PROFILES_REPO_NAME` | Keybase profiles repo name | "profiles" |

**If you want to be able to re-image a new machine with your settings (and overridden choices), and do not want to repeat the steps  manually, you would want to fork my repo and make appropriate changes.**

# Pre-requisite (if you want to capture data from your current mac)

This section is important if you want to capture the installed softwares, etc from an existing setup.

1. If you are starting this process on a machine where you have already installed some apps using brew, then use `brew bundle dump` to create the `${HOME}/Brewfile` file and avoid starting from scratch. Remember though that this is a *1-time* run of this command. In the future, if you regenerate the Brewfile using this command, any custom comments/formatting that you might have written into that file - would be lost.
2. Use the `scripts/capture-defaults.sh` script with the `-e` (export) option to export your application and system preferences. Please ensure that you edit the list of applications to what you have installed and would like to capture the preferences for.

# Generic/Common Getting started

**Before starting to run this script** (for the first time on a new machine), these steps are *recommended* so that the process doesn't error out midway.

On your local machine:

1. Open the `App Store` application.
   * Login into Apple App store (if not, then the setup script will complain about not being able to download applications from the App Store)
2. Open the `System Preferences` application.
   * Search for 'Full Disk Access' and add 'Terminal' (if not, the setup script will error out in between)
   * Search for 'File Vault' and turn it on (if not, then the setup script will exit in the beginning itself)

In your forked repo, make the following changes, commit and push (Once the above steps are done, and committed into your fork, then everytime you need to run the setup, you can run the `curl` commands that point to your fork instead of mine so as to avoid manual effort.):

1. **_Only in this README file and `files/.zprofile` files (and nowhere else):_** Find and replace the strings that reference my usernames to your equivalent ones (for eg, you can search for `vraravam` and `avijayr` and replace them with your values).
2. The nested folder names that you choose for your setup (as referred to by `PROJECTS_BASE_DIR`, `PERSONAL_CONFIGS_DIR`, `PERSONAL_PROFILES_DIR`, `PERSONAL_BIN_DIR`, and `DOTFILES_DIR` in the `files/.zprofile` file) **should be reflected** in the folder structure of the nested folders in the `files` directory of the committed github repo itself. For eg, I have `PROJECTS_BASE_DIR="${HOME}/dev"`, and if your setup uses `workspace` instead of `dev`, then, in your forked repository, the folder name `files/dev` should be renamed to `files/workspace` and so on.
3. Review all entries in the `${HOME}/Brewfile`, and ensure that there are no unwanted libraries/files. If you have any doubts (if comparing with my Brewfile), you will need to search the internet for the uses of those libraries/applications.

The meta script to setup the macos machine from a vanilla OS can be run using the following command:

```zsh
export GH_USERNAME="vraravam"; export DOTFILES_DIR="${HOME}/.bin-oss"; curl -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/master/scripts/fresh-install-of-osx.sh" | zsh
```

This script can be run in an idempotent manner, and will setup [oh-my-zsh](https://ohmyz.sh/), [homebrew](https://brew.sh), the dotfiles (this repo), etc.
All these scripts are optimized for fast loading of the shell so that the user can work almost immediately upon starting the app.

**Important Note** After the above script has completed running successfully, you need to do the following *manually*

1. Use [this gist as a template](https://gist.github.com/vraravam/e9676759db46950e1fd817e49e513394) to create equivalent configuration files with your logins and make corresponding changes in `${HOME}/.gitconfig` to reflect the same
2. Open the `Terminal` application.
   * Goto Preferences > Profiles > Basic > Text (and change the font to 'MesloLGS Nerd Font')
3. Open the `iTerm2` application.
   * Goto Preferences > Profiles > Default > Text (and change the font to 'MesloLGS Nerd Font')
   * Goto Preferences > Profiles > Default > Keys > Key Mappings > Presets (and choose 'Natural Text Editing')

*These are optional based on your preferences:*

1. Open the `System Preferences` application.
   * Search for 'Trackpad' and turn on 'Tap to click' (Trackpads are notorious to breakdown if using via hard-click)
   * Search for 'Displays' and set scaling / screen resolution as per your preference
   * Search for 'Displays' and turn off 'Automatically adjust brightness'
   * Search for 'Control Centre" and turn off battery from showing in the Control Center (nice to have especially if you use the Stats app)
   * Search for 'Control Centre" and scroll down to 'Clock options' and change the built-in clock to show as analog to save horizontal space in the top menu bar
   * Search for 'Full Disk Access' and add `iTerm', 'Terminal', 'zoom.us'
   * Search for 'Camera' and add 'Arc', 'Brave', 'Firefox', 'zoom.us'
   * Search for 'Microphone' and add 'Arc', 'Brave', 'Firefox', 'zoom.us'
   * Search for 'Close and restore windows', and uncheck 'Close windows when quitting an application' (this will ensure that iTerm, Terminal, all browsers, etc - whichever have multiple windows open while quitting that application, will restore the same windows and tabs the next time you start that application.)
   * Search for 'Default web browser' and set as per your preferences
   * Search for 'iCloud' and login setup Desktop sync
2. Open the `Finder` application and manually adjust the Finder sidebar preferences

# Advanced setup

The "Advanced" setup is the set of final steps to capture your application preferences (both system apps as well as custom apps) and back them up into an encrypted remote repository. Currently this kind of a service is offered by [keybase](https://keybase.io/) where you can get private, fully-encrypted repos for free.

**Before starting to run this script** (for the first time on a new machine), these steps are *recommended*

1. Open the `Keybase` application.
   * Login into keybase
2. Quit and restart the `Terminal` application.

The meta script to setup the macos machine AFTER the generic script has been run, can be invoked by using the following command:

```zsh
curl -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/master/scripts/fresh-install-of-osx-custom.sh" | zsh
```

This script can also be run in an idempotent manner, and will setup the home folder repo, the browser profiles, resurrect the repositories that you have created a registry for, install all the languages (each specific version of each language) using [mise](https://github.com/jdx/mise), apply some [OSX defaults](scripts/osx-defaults.sh) and finally re-import your preferences that were captured from the old machine using the [capture-defaults](scripts/capture-defaults.sh) script

**Important Note** After the above script has completed running successfully, you need to do the following *manually*

1. Open the `VSCode` (or `VSCodium`) application.
   * Go to the Command Palette (`Cmd+Shift+P`) > Sync: Advanced Options > Sync: Open Settings and setup your Github integration for backing up your VSCode settings. To seed your VSCode/VSCodium for the first time with my settings, you can use '6624ce6f4618e4c9d7682975fea0ef95' for the GH gist id. Remember to leave the text box empty AFTER the initial download, so that the plugin will auto-create a new gist in your GH id for future backups
2. Open the `Raycast` application.
   * If you are using Raycast, then turn off Spotlight from being triggered with the `Cmd+Space` shortcut since you would want this key combo to trigger Raycast itself. This can be done in the `System Preferences` application - search for 'Keyboard shortcuts', click on the button 'Keyboard shortcuts' and then go to 'Spotlight'
   * Setup the preferences and keyboard shortcuts as per your preferences. (I have setup for Clipboard history and Window management.)

# Finally...

Once the above is done, and if you have setup the [keybase](https://keybase.io)-based home repo, profile repo, etc - you can then re-import your exported preferences from the [pre-requisites section](#pre-requisite-if-you-want-to-capture-data-from-your-current-mac). Of course, you will have to manually take snapshots of your machine for backup. This can be done using the `scripts/capture-defaults.sh` script and pushing into the remote repo of your home folder.

As a summary, these files will typically have changes between your setup and mine:

* `README.md` (references to your usernames instead of mine)
* `files/.aliases` (aliases based on `PROJECTS_BASE_DIR` - lines 58-61)
* `files/.aliases.custom` (folders of browser profiles that you track inside of the `PERSONAL_PROFILES_DIR` folder on your local machine)
* `files/.gitconfig` (all the `IncludeIf` lines to match your folder structure where you clone git repos and the configurations for each group of them)
* `files/.zprofile` (`GH_USERNAME`, `KEYBASE_USERNAME`, etc)
* `files/Brewfile` (the list of applications and command-line utilities that you choose to install in your local machine)
* `scripts/capture-defaults.sh` (what application preferences that you choose to backup - based on the entries in the `Brewfile`)
* `scripts/fresh-install-of-osx.sh` (what applications you choose to set a login items on every reboot)

# Extras/Details

## install-dotfiles.rb

Basically, to get started with the dotfiles, you just need to run the `<pwd>/scripts/install-dotfiles.rb` script. If you have that folder in the `PATH`, then you don't need the fully qualified or relative location (only file name is enough to run it).

* If you already have any of the dotfiles that are managed via this repo, *DON'T WORRY!* Your files will be moved to the cloned folder - so that you can then commit and push them to your fork!
* This script will also handle nested config files - as long as they are already present in this repo.
* Special handling (rename + copy instead of symlink) for `.gitattributes` and `.gitignore` - which means that, *for those files alone*, you will have to **keep them manually in sync**.
* If you do not want a specific file from the home folder to be overridden, simply delete it from this repo's `files` folder - and it will not be processed.
* If you wish to add a new file to be tracked and managed via this backup mechanism, simply add it into the `files` folder with the requisite relative path (relative to your `HOME` folder) - and it will be processed.

## approve-fingerprint-sudo.sh

This script is useful in macos to enable TouchId as an authentication mechanism even while running command-line tools. Before running this script, the usual mechanism is for a prompt to appear in the terminal window itself where one has to type in the whole long password. After this script is run, the user is prompted by the touchId modal dialog instead of having to type a really long password.
Note:

* This script is idempotent ie it can be run any number of times safely, it will not corrrupt the system.
* The script needs to be run after each OS upgrade is applied.

## capture-defaults.sh

This script is useful to capture the preferences of the known applications (both system-installed and custom-installed applications) using the `defaults read` command. It can be used to both export the preferences/settings (from the old system) or import them (into the new system)

## osx-defaults.sh

This script is the erstwhile script to codify the macos setup. It can be used to setup some options, but its not been maintained for newer versions of macos. Though the system will not get corrupted, there might be cruft introduced into the system preferences which might not be easy to identify and remove at a later point in time. Use caution and YMMV.

## recreate-repo.sh

Usually, over time, if a repo has lots of branches that were deleted or became stale, and constant rebases done - it can lead to the repo bloating in size (both on local and remote). This is especially true of the profiles repo in my usage since I have a cron job setup to amend the repo with the new state files. To effectively reduce the size on the remote so that any future clone does not pull down dangling commits and other cruft, the simplest way that I have found is to recreate the remote (this does not mean that the history is lost!) after running the `git cc` command on the local.

## resurrect-repositories.rb

I usually reimage my laptop once every couple of months. This script is useful as a catalog of all repos that I have ever worked on, and some/most which are marked `active: true` in the yaml to resurrect back into the new machine/image. The yaml (described in the comments at the beginning of the script) also allow to install the required languages and their versions in an automated manner so as to avoid having to read the `README.md` or the `CONTRIBUTING.md` file for each repo on each re-image!

This script is useful to flag existing repositories that need to be backed up; and the reverse process (ie resurrecting repo-configurations from backup) is also supported by the same script!
To run it, just invoke by `resurrect-repositories.rb` if this folder is already setup in the `PATH`. This will then print the usage by default and you can follow the required parameters.

The config file for this script is a yaml file that is passed into this script as a parameter and the structure of this configuration file is:

```yaml
- folder: "${PROJECTS_BASE_DIR}/oss/git_scripts"
  remote: https://github.com/vraravam/git_scripts.git
  other_remotes:
    upstream: <upstream remote url>
  active: true
  post_clone:
    - ln -sf "${PERSONAL_CONFIGS_DIR}/XXX.gradle.properties" ~/.gradle/gradle.properties
    - git-crypt unlock XXX
```

* `folder` specifies the target folder where the repo should reside on local machine. If the folder name starts with `/`, then its assumed that the path starts from the root folder; if not, then its assumed to be relative to where the script is being run from. The ruby script also supports glob expansion of `~` to `${HOME}` if `~` is used. It can also handle shell env vars if they are in the format `#{<env-key>}`
* `remote` specifies the remote url of the repository
* `other_remotes` specifies a hash of the other remotes keyed by the name with the value of the remote url
* `active` (optional; default: false) specifies whether to set this folder/repo up or not on local
* `post_clone` (optional; default: empty array) specifies other `bash` commands (in sequence) to be run once the resurrection is done - for eg, symlink a '.envrc' file if one exists

## software-updates-cron.sh

There are so many tools installed, and some of them require their local caches/dbs/configs/etc to be updated from time to time. Rather than remembering each tool and its invocation (for updates), this script is a single place where any new tooling is added so that I don't need to remember the incantation for each separately.
