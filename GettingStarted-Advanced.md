# Before starting to run this portion of the script (for the first time on a new machine), these steps are *mandatory (if you are using my keybase-based advanced setup)*

1. Make sure that you have logged into `Keybase` either via the application or the command-line. The script will error out with an appropriate message if you haven't done so.

This portion of the script will setup the home folder repo, the browser profiles, resurrect the repositories that you have created a registry for, install all the programming languages (each specific version of each language) using [mise](https://github.com/jdx/mise), apply some [OSX defaults](scripts/osx-defaults.sh) and finally re-import your preferences that were captured from the old machine using the [capture-defaults](scripts/capture-defaults.sh) script.

**Important Note** After the above script has completed running successfully, you need to do the following *manually*

1. Open the `VSCodium` application.
   * Go to the Command Palette (`Cmd+Shift+P`) > Sync: Advanced Options > Sync: Open Settings and setup your Github integration for backing up your VSCode settings. To seed your VSCode/VSCodium for the first time with my settings, you can use '6624ce6f4618e4c9d7682975fea0ef95' for the GH gist id. Remember to leave the text box empty AFTER the initial download, so that the plugin will auto-create a new gist in your GH id for future backups
2. Open the `Raycast` application.
   * If you are using Raycast, then turn off Spotlight from being triggered with the `Cmd+Space` shortcut since you would want this key combo to trigger Raycast itself. This can be done in the `System Preferences` application - search for 'Keyboard shortcuts', click on the button 'Keyboard shortcuts' and then go to 'Spotlight' on the left, and uncheck `Show Spotlight search`.
   * Setup the preferences and keyboard shortcuts as per your preferences. (I have setup for Clipboard history, Window management and Import/Export of the Raycast settings.)
    *Hint:* If you had exported the configs into a file and had captured it as part of your home git repo, then simply re-importing will be sufficient on the new machine.

Back to the [readme](README.md#advanced-setup-in-addition-to-the-basic-setup-if-you-want-to-capture-other-files-in-an-encrypted-private-git-repo)
