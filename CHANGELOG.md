As documented in the README's [adopting](README.md#how-to-adoptcustomize-the-scripts-to-your-own-settings) section, this repo and its scripts are aimed at developers/techies. If you are stuck or need help in any fashion, you can reach out to me at my email.

For those who follow this repo, here's the changelog for ease of adoption:

### 1.0-2
* *[install-dotfiles.rb]* Refactored the logic to handle ssh global configuration file for ease of readability and maintainability.

### 1.0-1

* *[Brewfile]* Added `virtualbox` to test out linux as a Virtual machine.
* *[CHANGELOG.md]* Added changelog which will be maintained going forward for each commit.
* *[README.md]* Added a [new section](README.md#how-to-upgrade--catch-up-to-new-changes) detailing steps to adopt updates/catchups for new changes on an ongoing basis.
* Changed all colored messages to be uniform and added a `success` function to print in green. These are optimized for a dark theme in your terminal emulator.

### 1.0

* `install-dotfiles.rb` can now handle multiple env vars for nested files/folders in the `files` sub-folder. They follow the naming convention of the env var being enclosed within 2 pairs of hyphens (`--`). For eg, `files/--PERSONAL_PROFILES_DIR--/.envrc` will be symlinked on your local machine into `files/personal/<yourLocalUsername>/profiles/.envrc` assuming that the `PERSONAL_PROFILES_DIR` env var has been defined. This is not a breaking change.

#### Adopting these changes

* Since I recreated the `1.0` tag as part of this push, you might need to delete the tag in both your local and your remote and then do `git upreb`.
* Run the `install-dotfiles.rb` script which will automatically remove the older (broken) symlink and recreate the new one in the correct location.
