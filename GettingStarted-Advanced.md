The "Advanced" setup is the set of final steps to capture your application preferences (both system apps as well as custom apps) and back them up into an *encrypted remote repository*. Currently this kind of a service is offered by [keybase](https://keybase.io/) where you can get private, fully-encrypted repos for free.
*Before getting started with the advanced setup these steps are optional based on your preferences:*

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


**Before starting to run this script** (for the first time on a new machine), these steps are *recommended*

1. Open the `Keybase` application.
   * Login into keybase
2. Quit and restart the `Terminal` application.

The meta script to setup the macos machine AFTER the generic script has been run, can be invoked by using the following command:

```zsh
curl -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/master/scripts/fresh-install-of-osx-custom.sh" | zsh
```

This script can also be run in an idempotent manner, and will setup the home folder repo, the browser profiles, resurrect the repositories that you have created a registry for, install all the languages (each specific version of each language) using [mise](https://github.com/jdx/mise), apply some [OSX defaults](scripts/osx-defaults.sh) and finally re-import your preferences that were captured from the old machine using the [capture-defaults](scripts/capture-defaults.sh) script

**Important Note** After the above script has completed running successfully, you need to do the following *manually*

1. Open the `VSCode` (or `VSCodium`) application.
   * Go to the Command Palette (`Cmd+Shift+P`) > Sync: Advanced Options > Sync: Open Settings and setup your Github integration for backing up your VSCode settings. To seed your VSCode/VSCodium for the first time with my settings, you can use '6624ce6f4618e4c9d7682975fea0ef95' for the GH gist id. Remember to leave the text box empty AFTER the initial download, so that the plugin will auto-create a new gist in your GH id for future backups
2. Open the `Raycast` application.
   * If you are using Raycast, then turn off Spotlight from being triggered with the `Cmd+Space` shortcut since you would want this key combo to trigger Raycast itself. This can be done in the `System Preferences` application - search for 'Keyboard shortcuts', click on the button 'Keyboard shortcuts' and then go to 'Spotlight'
   * Setup the preferences and keyboard shortcuts as per your preferences. (I have setup for Clipboard history and Window management.)

Back to [Readme](README.md#advanced-setup-in-addition-to-the-basic-setup-if-you-want-to-capture-other-files-in-an-encrypted-private-git-repo)
