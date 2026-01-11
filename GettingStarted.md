**Before starting to run this script** (for the first time on a new machine), these steps are *recommended* so that the process doesn't error out midway.

On your local machine:

1. **If you use `mas` to install apps from the App Store**, login into the `App Store` application.
2. Open the `System Preferences` application.
   * Search for 'Full Disk Access' and add 'Terminal' (if not, the setup script will error out in between)
   * Search for 'File Vault' and turn it on (if not, then the setup script will exit in the beginning itself)
3. If you are going to use Raycast, open the `System Preferences` application.
   * Search for 'Privacy & Security > Accessibility', and enable/approve for the Terminal app (and later for iTerm once its installed).

The meta script to setup the macos machine from a vanilla OS can be run using the following command:

```zsh
export GH_USERNAME='vraravam' DOTFILES_BRANCH='master' HOMEBREW_BASE_INSTALL='true'; curl --retry 3 --retry-delay 5 -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/scripts/fresh-install-of-osx.sh" | zsh; unset HOMEBREW_BASE_INSTALL
```

This script can be run in an idempotent manner, and will setup [oh-my-zsh](https://ohmyz.sh/), [homebrew](https://brew.sh), the dotfiles (this repo), etc. (There is 1 caveat though: on a fresh machine, this script silently fails after the first basic installation, and so has to be run again manually *after* running the following steps.)
All these scripts are optimized for fast loading of the shell so that the user can work almost immediately upon starting the app.

**Important Note** After the above script has completed running successfully, you need to do the following *manually*

1. Use [this gist](https://gist.github.com/vraravam/e9676759db46950e1fd817e49e513394) <!-- Note: Do NOT change this --> as a template to create equivalent configuration files with your details and make corresponding changes in `files/--HOME--/.gitconfig-oss.inc` to reflect the same.

   *Tip*: Since these configurations are deep-merged (latest one wins), you will not want to expose your other client-specific configs or your personal configs like email to the outside world (via this public repo). So, you will want to make these changes in the `${HOME}/.gitconfig-oss.inc` and not in `${HOME}/.gitconfig` directly.
2. Quit and Open the `Terminal` application.
   * Goto Preferences > Profiles > Basic > Text (and change the font to 'MesloLGS Nerd Font')
3. Open the `iTerm2` application.
   * Goto Preferences > Profiles > Default > Text (and change the font to 'MesloLGS Nerd Font')
   * Goto Preferences > Profiles > Default > Keys > Key Mappings > Presets (and choose 'Natural Text Editing')
   * Run `bupc` within a *new* Terminal so that the rest of the applications can be installed via Homebrew.

*These are optional based on your preferences:*

1. Open the `System Preferences` application.
   * Search for 'Trackpad' and turn on 'Tap to click' (Note: Apple trackpads are notorious for breaking down if used via a hard-click)
   * Search for 'Displays' and set scaling / screen resolution as per your preference
   * Search for 'Displays' and turn off 'Automatically adjust brightness'
   * Search for 'Control Centre' and turn off battery from showing in the Control Center (nice to have especially if you use the Stats app)
   * Search for 'Control Centre' and scroll down to 'Clock options' and change the built-in clock to show as analog to save horizontal space in the top menu bar
   * Search for 'Full Disk Access' and add `iTerm', 'Terminal', 'zoom.us'
   * Search for 'Keyboard' and enable Keyboard Navigation
   * Search for 'Camera' and add 'Brave', 'Firefox', 'Zen', 'zoom.us'
   * Search for 'Microphone' and add 'Brave', 'Firefox', 'Zen', 'zoom.us'
   * Search for 'Close and restore windows', and uncheck 'Close windows when quitting an application' (this will ensure that iTerm, Terminal, all browsers, etc (whichever have multiple windows open while quitting that application), will restore the same windows and tabs the next time you start that application.)
   * Search for 'Default web browser' and set as per your preferences
   * Search for 'iCloud' and login and setup Desktop sync
2. Open the `Finder` application and manually adjust the Finder sidebar preferences

**Continuing the setup process**

1. If you are using my keybase-based advanced setup), make sure that you have logged into `Keybase` either via the application or the command-line. The script will prompt you to login using its in-built cli if you haven't done so.
2. Rerun the `fresh-install-of-osx.sh` script. This portion of the script will setup the home folder repo, the browser profiles, resurrect the repositories that you have created a registry for, install all the programming languages (each specific version of each language) using [mise](https://github.com/jdx/mise), apply some [OSX defaults](scripts/osx-defaults.sh) and finally re-import your preferences (that were captured from the old machine) using the [capture-prefs](scripts/capture-prefs.sh) script. If you had captured the Raycast preferences, then you can re-import them using the `import settings` option in the Raycast application.

**Important Note** After the above script has completed running successfully, you need to do the following *manually* if you *hadn't* captured the Raycast preferences (otherwise, you can skip these steps):

1. Open the `Raycast` application.
   * If you are using Raycast, then turn off Spotlight from being triggered with the `Cmd+Space` shortcut since you would want this key combo to trigger Raycast itself. This can be done in the `System Preferences` application - search for 'Keyboard shortcuts', click on the button 'Keyboard shortcuts' and then go to 'Spotlight' on the left, and uncheck `Show Spotlight search`.
   * Setup the preferences and keyboard shortcuts as per your choices within Raycast. (I have setup for Clipboard history, Window management and Import/Export of the Raycast settings.)
    *Hint:* If you had exported the configs into a file and had captured it as part of your home git repo, then simply re-importing will be sufficient on the new machine.
   * I switched to using the 'Coffee' extension of Raycast instead of the KeepingYouAwake standalone app. If you want this functionality, you might also want to install that extension within Raycast's preferences.


Back to the [readme](README.md#complete-setup)
