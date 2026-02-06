- [Background](#background)
- [How to adopt/customize the scripts to your own settings](#how-to-adoptcustomize-the-scripts-to-your-own-settings)
  - [How to upgrade / catch-up to new changes](#how-to-upgrade--catch-up-to-new-changes)
  - [How to test changes in your fork before raising a Pull Request](#how-to-test-changes-in-your-fork-before-raising-a-pull-request)
- [Pre-requisites](#pre-requisites)
- [Basic setup](#complete-setup)
- [Finally...](#finally)
- [Ongoing tasks to keep your backup up-to-date on a regular basis](#ongoing-tasks-to-keep-your-backup-up-to-date-on-a-regular-basis)
- [Extras/Details](#extrasdetails)
- [Attributions \& Thanks](#attributions--thanks)

# Background

This repo is used to backup and easily reimage a new macos system. It contains the common dotfiles as well as the scripts that I use as the backup/restore strategy.

These scripts are idempotent and can run on a vanilla OS as well as once the whole setup has been completed.

Each script will warn the users if its skipping a step, and if you want to rerun the script but force that step, you just need to delete the control `if` condition (you should have a basic understanding of shell programming to figure out what to delete/how to force without bypass).

All of the folder structures and the setup/backup operations are governed by the environment variables [defined here](files/--HOME--/.shellrc). Please read the explanation of each variable in the same and edit appropriately.

# How to adopt/customize the scripts to your own settings

If you want to be able to re-image a new machine with your own settings (and overridden choices), and you do not want to repeat these steps manually, you would want to fork my repo and make appropriate changes into your fork.

_Note:_

- ***_DO NOT clone this repo into your local machine. The setup script will put it in the correct folder and setup the PATH environment variable as well._***
- Make the following changes via the Github web UI/portal itself.
- If you end up with multiple commits on top of the parent repo, you can squash them at the end.

In your forked repo, make the following changes, commit and push _via the Github web-UI itself_ (for the first time before running the script). Once the above steps are done, and committed into your fork, then everytime you need to run the setup, you can run the `curl` commands that point to _your_ fork:

1. **_Only in this file (`README.md`), `GettingStarted.md` and `files/--HOME--/.shellrc` files (and nowhere else; 3 files in total):_** Find and replace the strings that reference my usernames to your equivalent ones (for eg, you can search for `vraravam` (referred to as the `GH_USERNAME` env var) and `avijayr` (referred to as the `KEYBASE_USERNAME` env var) and replace them with your values). If you are not going to use keybase (or are going to defer setting that up), please comment out the lines for the environment variables that start with `KEYBASE_` in the `files/--HOME--/.shellrc`.
2. Review all entries in the `files/--HOME--/Brewfile`, and ensure that there are no unwanted libraries/applications. If you have any doubts (if comparing with my [Brewfile](files/--HOME--/Brewfile)), you will need to search the internet for the uses of those libraries/applications and decide whether to retain each one or not.

## How to upgrade / catch-up to new changes

1. My recommendation is to _always_ have all your customizations as a single commit on top of the upstream. This allows to easily rebase and adopt new changes in the future.
2. Run the `git -C "${DOTFILES_DIR}" fetch --all` command.
   - Run the `git -C "${DOTFILES_DIR}" upreb` command. Most of the times, this should simply rebase your changes on top of the latest upstream master.
   - As an alternative to the above step, if there are too many commits to catch-up to, AND your fork had only 1 commit on top of any of my historical commits, then you can quickly re-apply your changes (remember: single commit) using the following script:

      ```bash
      latest_head="$(git -C "${DOTFILES_DIR}" rev-parse HEAD)"
      git -C "${DOTFILES_DIR}" reset --hard upstream/master
      git -C "${DOTFILES_DIR}" cherrypick ${latest_head}
      # TODO: manually fix any conflicts
      ```

3. _Hint:_ Before pushing your changes to your remote, if you want to ensure (diff) that your old changes are retained (for eg in `Brewfile`) and no new/unnecessary changes are present, you can run the following 2 commands and review the diffs manually

   ```bash
    git -C "${DOTFILES_DIR}" diff @{u}  # will diff your local HEAD against the remote HEAD of your own fork. Please remember that this diff will show new changes that I have made in my repo, and which are now going-to-be-adopted into yours. It's a good idea to remove entries in Brewfile that you won't need

    git -C "${DOTFILES_DIR}" diff upstream/`git branch --show-current`  # will diff your local HEAD against the remote HEAD of the parent repo. These changes should be exactly the changes that you had done previously (most likely only in GettingStarted.md, files/--HOME--/.shellrc and files/--HOME--/Brewfile)
   ```

4. You will have to force-push to your fork's remote after the above step. To accomplish this, I recommend using `git -C "${DOTFILES_DIR}" push --force-with-lease`
5. After the above step, it is always recommended to run the `install-dotfiles.rb` script once to ensure all (non symlinked) changes are setup on your machine correctly.
6. In case there are any other changes that might be needed after updating, these steps will be detailed in the [changelog](./CHANGELOG.md). In such rare cases, you might have to run the appropriate steps in sequence as detailed out in that section for that version.
7. After updating/catching-up, it is recommended to quit and restart the terminal app so that all "in session memory" aliases, etc are up-to-date so that the files are sourced correctly.

## How to test changes in your fork before raising a Pull Request

1. **Especially if you are making changes to the fresh-install scripts and want to test it out on a vanilla OS**, you can change the github urls to refer to your branch in these files `GettingStarted.md` and `files/--HOME--/.shellrc`. For eg, if your PR branch is called `zdotdir-fixes`, you can search for `DOTFILES_BRANCH=` in those files, and replace `master` with `zddotdir-fixes`. Once your PR is tested and approved, please remember to revert `zddotdir-fixes` back to `master` and then merge the PR into the main working branch.

# Pre-requisites

If you want to capture data from your current mac, please follow the instructions [here](Prerequisites.md)

# Complete setup

The backup strategy is split into 2 stages - both of which are run by the [same script](scripts/fresh-install-of-osx.sh). The [basic "getting started"](GettingStarted.md) provides the instructions for the most common/basic setup. This covers everything that a typical user might need - without the need to backup other parts of the existing laptop.
The "advanced" setup is the set of final steps to capture your application preferences (both system apps as well as custom apps) and back them up into an _encrypted remote repository_. Currently this kind of **_private, fully-encrypted and free_** service is offered only by [keybase](https://keybase.io/).
If you want to automate the repetitive running of these scripts/commands, you can use the system-level cronjobs to set this up, the details of which can be found in the Extras, by which you can reduce more manual efforts.

# Finally...

The softwares in the `files/--HOME--/Brewfile` will be run only with the bare minimum of formulae with the above invocation. Once the process completes, and you restart the Terminal app, you would want to run `bupc` so that all the other applications can be installed.

Once the above is done, and if you have setup the [keybase](https://keybase.io)-based home repo, profile repo, etc - you can then re-import your exported preferences from the [pre-requisites section](#pre-requisite-if-you-want-to-capture-data-from-your-current-mac).

Of course, you will have to manually take snapshots of your machine for backup from time-to-time as an _ongoing activity_. This can be done using the `scripts/capture-prefs.sh` script and pushing into the remote repo of your home folder. (More details can be found in the next section.)

As a summary, these files will typically have changes between your setup and mine:

- `GettingStarted.md` (references to your usernames instead of mine, and typically any other changes that you introduce in the `files/--HOME--/.shellrc` - look below)
- `files/--HOME--/.gitconfig` (the `IncludeIf` line to match your global/base configuration filename)
- `files/--HOME--/.shellrc` (`GH_USERNAME`, `KEYBASE_USERNAME`, and other changeable env vars to control which steps to perform vs which to bypass)
- `files/--HOME--/Brewfile` (the list of applications and command-line utilities that you choose to install in your local machine)
- `scripts/data/capture-prefs-domains.txt` (what application preferences that you choose to backup - based on the entries in the `Brewfile`)

# Ongoing tasks to keep your backup up-to-date on a regular basis

The backup strategy is **not a one-off activity**. It will require you to take snapshots from time-to-time. Similarly, adherance to maintainence of the "catalogs" will need to be strictly upheld for the backup strategy to be effective.

- Ensure that the software catalogs (`files/--HOME--/Brewfile`, `scripts/fresh-install-of-osx.sh`, `scripts/capture-prefs.sh`) are always kept in sync with the actual applications that you install and use
- Ensure that the git repo catalogs that you are "tracking" in the `${PERSONAL_CONFIGS_DIR}/repositories-*.yml` files are kept up-to-date so that resurrection in your new machine will be seamless
- Ensure to run the `scripts/capture-prefs.sh` (with the export switch) to export and capture/backup your preferences for all installed applications from your current machine.

# Extras/Details

Some utility scripts have been provided in this repo - which you can use to manage the backup strategy in a better fashion. Details can be found [here](Extras.md)

# Attributions & Thanks

These folks have contributed to this codebase till date:

- @arunvelsriram
- @shaz-ahammed
- @jotheeswaran-dev
