# Background

This repo is used to backup and easily reimage a new macos system. It contains the common dotfiles as well as the scripts that I use as the backup/restore strategy.

These scripts are idempotent and can run on a vanilla OS as well as once the whole setup has been completed.

Each script will warn the users if its skipping a step, and if you want to rerun the script but force that step, you just need to delete the control `if` condition (you should have a basic understanding of shell programming to figure out what to delete/how to force without bypass).

All of the folder structures and the setup/backup operations are governed by the environment variables [defined here](files/.zprofile). Please read the explanation of each variable in the same and edit appropriately.

# How to adopt/customize the scripts to your own settings

If you want to be able to re-image a new machine with your own settings (and overridden choices), and you do not want to repeat these steps manually, you would want to fork my repo and make appropriate changes into your fork.

In your forked repo, make the following changes, commit and push. Once the above steps are done, and committed into your fork, then everytime you need to run the setup, you can run the `curl` commands that point to *your* fork:

1. **_Only in this file, `GettingStarted-Basic.md` and `files/.zprofile` files (and nowhere else):_** Find and replace the strings that reference my usernames to your equivalent ones (for eg, you can search for `vraravam` and `avijayr` and replace them with your values).
2. The nested folder names that you choose for your setup (as referred to by `PROJECTS_BASE_DIR`, `PERSONAL_CONFIGS_DIR`, `PERSONAL_PROFILES_DIR`, `PERSONAL_BIN_DIR`, and `DOTFILES_DIR` in the `files/.zprofile` file) **should be reflected** in the folder structure of the nested folders in the `files` directory of the committed github repo itself. For eg, I have `PROJECTS_BASE_DIR="${HOME}/dev"`, and if your setup uses `workspace` instead of `dev`, then, in your forked repository, the folder name `files/dev` should be renamed to `files/workspace` and so on.
3. Review all entries in the `${HOME}/Brewfile`, and ensure that there are no unwanted libraries/applications. If you have any doubts (if comparing with my Brewfile), you will need to search the internet for the uses of those libraries/applications.

# Pre-requisites

if you want to capture data from your current mac, please follow the instructions [here](Prerequisites.md)

# Script discriptors
Some utility scripts have been provided in this repo - which you can use to manage the backup strategy in a better fashion. [click here](Extras.md)

# Basic setup

The backup strategy is split into 2 stages. The [basic "getting started"](GettingStarted-Basic.md) provides the instructions for the most common/basic setup. This covers everything that a typical user might need - without the need to backup other parts of the existing laptop.

These files will typically have changes between your setup and mine:

* `GettingStarted-Basic.md` (references to your usernames instead of mine, and typically any other changes that you introduce in the `files/.zprofile` - look below)
* `files/.gitconfig` (the `IncludeIf` line to match your global/base configuration filename)
* `files/.zprofile` (`GH_USERNAME`, `KEYBASE_USERNAME`, and other changeable env vars to control which steps to perform vs which to bypass)
* `files/Brewfile` (the list of applications and command-line utilities that you choose to install in your local machine)
* `scripts/capture-defaults.sh` (what application preferences that you choose to backup - based on the entries in the `Brewfile`)
* `scripts/fresh-install-of-osx.sh` (what applications you choose to set as login items on every reboot)

# Ongoing tasks to keep your backup up-to-date

The backup strategy is **not a one-off activity**. It will require you to take snapshots from time-to-time. Similarly, adherance to maintainence of the "catalogs" will need to be strictly upheld for the backup strategy to be effective.

* Ensure that the software catalogs (`files/Brewfile`, `scripts/fresh-install-of-osx.sh`, `scripts/capture-defaults.sh`) are always kept in sync with the actual applications that you install and use
* Ensure that the git repo catalogs that you are "tracking" in the `${PERSONAL_CONFIGS_DIR}/repositories-*.yml` files are kept up-to-date so that resurrection in your new machine will be seamless
* Ensure to run the `scripts/capture-defaults.sh` (with the export switch) to export and capture/backup your preferences for all installed applications from your current machine

# [Click here](GettingStarted-Basic.md) to get started with the basic setup
