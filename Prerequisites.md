# This section is important if you want to capture the installed softwares, etc from an *existing* machine.

1. If you are starting this process on a machine where you have already installed some apps using homebrew, then use `cd "${HOME}"; brew bundle dump` to create the `${HOME}/Brewfile` file and avoid starting from scratch. Remember though that this is a *1-time* run of this command. In the future, if you regenerate the Brewfile using this command, any custom comments/formatting that you might have written into that file - would be lost.
2. Use the `scripts/capture-prefs.sh` script with the `-e` (export) option to export your application and system preferences. Please ensure that you edit the whitelist of applications to what you have installed and would like to capture the preferences for.
3. Use the `scripts/resurrect-repositories.rb` script with the `-g` (generate) option to generate the yaml for all git repos that you might have on your current machine. Please see the usage to provide the appropriate cmd-line arguments to generate and capture the appropriate yaml structure. *Note: The output of this generation step is printed onto the console stdout, you will have to capture and store it in an appropriate file for backup.*
4. If you use Raycast, you can enable the 'Export Settings & Data' option in the Raycast Extensions, and back-up that exported file so as to use it to resurrect in the new machine.

Back to the [readme](README.md#pre-requisites)
