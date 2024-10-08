**Before starting to run this script** (for the first time on a new machine), these steps are *recommended* so that the process doesn't error out midway.

On your local machine:

1. Open the `App Store` application.
   * Login into Apple App store (if not, then the setup script will complain about not being able to download applications from the App Store)
2. Open the `System Preferences` application.
   * Search for 'Full Disk Access' and add 'Terminal' (if not, the setup script will error out in between)
   * Search for 'File Vault' and turn it on (if not, then the setup script will exit in the beginning itself)

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
