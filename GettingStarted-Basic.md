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

Back to [Readme](README.md#basic-setup)
