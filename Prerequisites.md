# This section is important if you want to capture the installed softwares, etc from an *existing* machine.

These steps capture the state of your current machine so that `fresh-install-of-osx.rb` can restore it faithfully on the new one. Without them, you would have to reinstall apps, reconfigure preferences, and re-clone repositories manually after re-imaging.

1. If you are starting this process on a machine where you have already installed some apps using `homebrew`, then use `brew bundle dump --force --file="${HOME}/Brewfile"` to create the `${HOME}/Brewfile` file and avoid starting from scratch. Remember though that this is a **1-time** run of this command. In the future, if you regenerate the Brewfile using this command, any custom comments/formatting that you might have written into that file would be lost.
2. Use the `scripts/capture-prefs.rb` script with the `-e` (export) option to export your application and system preferences. Please ensure that you edit the whitelist of applications to what you have installed and would like to capture the preferences for.
3. Use the `scripts/resurrect-repositories.rb` script with the `-g` (generate) option to generate the yaml for all git repos that you might have on your current machine. The output must be saved into `${PERSONAL_CONFIGS_DIR}` (the same directory that `resurrect_tracked_repos` reads from during restore) using a filename matching `repositories-*.yml`. For example:

   ```zsh
   # If your shell is already configured (i.e. ~/.shellrc is sourced), PERSONAL_CONFIGS_DIR will
   # already be set. If not (e.g. on a machine where the dotfiles are not yet installed), export
   # it explicitly first:
   export PERSONAL_CONFIGS_DIR="${HOME}/personal/dev/configs"

   # ~/dev is the value of PROJECTS_BASE_DIR — the root folder under which all your git repos live.
   # Replace it with your actual projects root if it differs (e.g. ~/code, ~/workspace).
   resurrect-repositories.rb -g -d ~/dev > "${PERSONAL_CONFIGS_DIR}/repositories-personal.yml"
   ```

   If you have repos spread across multiple root folders, run the command once per folder and use distinct filenames (e.g. `repositories-oss.yml`, `repositories-work.yml`). Review and edit the generated yaml to set `active: true` only for repos you want resurrected on a fresh machine, and add any `post_clone` commands needed per repo.

Back to the [readme](README.md#pre-requisites)
