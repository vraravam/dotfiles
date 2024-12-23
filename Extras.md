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

I usually reimage my laptop once every couple of months. This script is useful as a catalog of all repos that I have ever worked on, and some/most which are marked `active: true` in the yaml to resurrect back into the new machine/image. The yaml (described below) also allows to install the required languages and their versions in an automated manner so as to avoid having to read the `README.md` or the `CONTRIBUTING.md` file for each repo on each re-image!

This script is useful to flag existing repositories that need to be backed up; and the reverse process (ie resurrecting repo-configurations from backup) is also supported by the same script!
To run it, just invoke by `resurrect-repositories.rb` if this folder is already setup in the `PATH`. This will then print the usage by default and you can follow the required parameters.

This script can also be used to generate the basic version of the below yaml (onto the console stdout). See the `-g` option in the usage on how to use this feature.

The config file for this script is a yaml file that is passed into this script as a parameter and the structure of this configuration file is:

```yaml
- folder: "${PROJECTS_BASE_DIR}/oss/git_scripts"
  remote: https://github.com/vraravam/git_scripts.git
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
* `active` (optional; default: false) specifies whether to set this folder/repo up or not on local
* `post_clone` (optional; default: empty array) specifies other `bash` commands (in sequence) to be run once the resurrection is done - for eg, symlink a '.envrc' file if one exists

## software-updates-cron.sh

There are so many tools installed, and some of them require their local caches/dbs/configs/etc to be updated from time to time. Rather than remembering each tool and its invocation (for updates), this script is a single place where any new tooling is added so that I don't need to remember the incantation for each separately.

Back to the [readme](README.md#extrasdetails)
