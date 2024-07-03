# Background

This repo was created from the gists that I was using to help others adopt my machine setup. It contains the common dotfiles as well as the scripts that I use to share the machine setup. These scripts are idempotent and can run on a vanilla OS as well as once the whole setup has been completed. Each script will warn the users if its skipping a step, and if you want to rerun the script but force that step, you just need to delete the control `if` condition (you should have a basic understanding of shell programming to figure out what to delete/how to force without bypass).

# Generic/Common Getting started

The meta script to setup the macos machine from a vanilla OS can be run using the following command:

```zsh
curl -fsSL https://raw.githubusercontent.com/vraravam/dotfiles/master/scripts/fresh-install-of-osx.sh | zsh
```

This can be run in an idempotent manner, and will setup [oh-my-zsh](https://ohmyz.sh/), [homebrew](https://brew.sh), the dotfiles (this repo), etc.
All these scripts are optimized for fast loading of the shell so that the user can work almost immediately upon starting the app.

# Advanced setup

The meta script to setup the macos machine AFTER the generic script has been run, can be invoked by using the following command:

```zsh
curl -fsSL https://raw.githubusercontent.com/vraravam/dotfiles/master/scripts/fresh-install-of-osx-custom.sh | zsh
```

This can also be run in an idempotent manner, and will setup the home folder repo, the browser profiles, resurrect the repositories that you have created a registry for, install all the languages (each specific version) using [mise](https://github.com/jdx/mise), apply some [OSX defaults](scripts/osx-defaults.sh)

# Finally...

Once the scripts are run, if you want to be able to re-image a new machine, but do not want to repeat the manual steps, you would want to fork my repo, and read through ALL the scripts in the `scripts` folder, and change the pointers that reference my username to your equivalent ones (for eg, you can search for `vraravam`, `avijayr`, `vijay`, `KEYBASE_USERNAME`, `KEYBASE_HOME_REPO_NAME` and `KEYBASE_PROFILES_REPO_NAME` and replace them with your values). Similarly, do the same for the configuration files in the `files` folder as well. Once this is done, and committed into your fork, then the next time you setup, you can run the `curl` command that points to your fork, which should contain your changes on top of mine.

# Extras

## install-dotfiles.rb

Basically, to get started with the dotfiles, you just need to run the `<pwd>/scripts/install-dotfiles.rb` script. If you have that folder in the `PATH` env var, then you don't need the fully qualified or relative location (only file name is enough to run).

* If you already have any of the dotfiles that are managed via this repo, *DON'T WORRY!* Your files will be moved to the cloned folder - so that you can then commit and push them to your fork!
* This script will also handle nested config files - as long as they are already present in this repo.
* Special handling (rename + copy instead of symlink) for `.gitattributes` and `.gitignore`
* If you do not want any file from the home folder to be overridden, simply delete it from this repo's `files` folder - and it will not be processed.
* If you wish to add a new file to be tracked and managed via this backup mechanism, simply add it into the `files` folder with the requisite relative path - and it will be processed.

## approve-fingerprint-sudo.sh

This script is useful in macos to enable the touchId as an authentication mechanism even while running command-line tools. Before running this script, the usual mechanism is for a prompt to appear in the terminal window itself whre one has to type in the whole long password. After this script is run, the user is prompted by the touchId modal dialog instead of having to type a really long password.
Note:

* This script is idempotent ie it can be run any number of times safely, it will not corrrupt the system.
* The script needs to be run after each OS upgrade is applied.

## capture-defaults.sh

This script is useful to capture the preferences of the known applications (both system-installed and custom-installed applications) using the `defaults read` command. It can be used to both export the preferences/settings (from the old system) or import them (into the new system)

## osx-defaults.sh

This script is the erstwhile script to codify the macos setup. It can be used to setup some options, but its not been maintained for newer versions of macos. Though the system will not get corrupted, there might be cruft introduced into the system preferences which might not be easy to identify and remove at a later point in time. Use caution and YMMV.

## recreate-repo.sh

Usually, over time, if a repo has lots of branches that were deleted or became stale, and constant rebases done - it can lead to the repo bloating in size. This is especially true of the profiles repo in my usage since I have a cron job setup to amend the repo with the new state files. To effectively reduce the size on the remote so that any future clone does not pull down dangling commits and other cruft, the simplest way that I have found is to recreate the remote (this does not mean that the history is lost!) after running the `git cc` command on the local.

## resurrect-repositories.rb

I usually reimage my laptop once every couple of months. This script is useful as a catalog of all repos that I have ever worked on, and some/most which are marked `active: true` in the yaml to resurrect back into the new machine/image. The yaml (described in the comments at the beginning of the script) also allow to install the required languages and their versions in an automated manner so as to avoid having to read the `README.md` or the `CONTRIBUTING.md` file for each repo on each re-image!
