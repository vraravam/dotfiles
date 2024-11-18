**Before starting to run this script** (for the first time on a new machine), these steps are *recommended*

1. Open the `Keybase` application.
   * Login into keybase
2. Quit and restart the `Terminal` application.

The meta script to setup the macos machine AFTER the generic script has been run, can be invoked by using the following command:

```zsh
curl -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/master/scripts/fresh-install-of-osx-advanced.sh" | zsh
```

This script can also be run in an idempotent manner, and will setup the home folder repo, the browser profiles, resurrect the repositories that you have created a registry for, install all the languages (each specific version of each language) using [mise](https://github.com/jdx/mise), apply some [OSX defaults](scripts/osx-defaults.sh) and finally re-import your preferences that were captured from the old machine using the [capture-defaults](scripts/capture-defaults.sh) script

**Important Note** After the above script has completed running successfully, you need to do the following *manually*

1. Open the `VSCode` (or `VSCodium`) application.
   * Go to the Command Palette (`Cmd+Shift+P`) > Sync: Advanced Options > Sync: Open Settings and setup your Github integration for backing up your VSCode settings. To seed your VSCode/VSCodium for the first time with my settings, you can use '6624ce6f4618e4c9d7682975fea0ef95' for the GH gist id. Remember to leave the text box empty AFTER the initial download, so that the plugin will auto-create a new gist in your GH id for future backups
2. Open the `Raycast` application.
   * If you are using Raycast, then turn off Spotlight from being triggered with the `Cmd+Space` shortcut since you would want this key combo to trigger Raycast itself. This can be done in the `System Preferences` application - search for 'Keyboard shortcuts', click on the button 'Keyboard shortcuts' and then go to 'Spotlight'
   * Setup the preferences and keyboard shortcuts as per your preferences. (I have setup for Clipboard history and Window management.)

Back to [Readme](README.md#advanced-setup-in-addition-to-the-basic-setup-if-you-want-to-capture-other-files-in-an-encrypted-private-git-repo)
