**Before starting to run this script** (for the first time on a new machine), these steps are *recommended* so that the process doesn't error out midway.

> Curious how the script works internally? See the [Technical Deep Dive](TechnicalDeepDive.md).

On your local machine:

1. **If you use `mas` to install apps from the App Store**, login into the `App Store` application before running the script — `mas` cannot authenticate mid-run.
2. Open the `System Preferences` application.
   * Search for 'Full Disk Access' and add 'Terminal' — without this the script cannot read certain protected directories and will error out mid-run.
   * Search for 'File Vault' and turn it on — the script checks for FileVault and exits early if it is off, to avoid setting up a machine with an unencrypted disk.
3. Open the `System Preferences` application.
   * Search for 'Privacy & Security > Accessibility', and enable/approve for the Terminal app (and later for iTerm once its installed) — some macOS automation commands require Accessibility permission to control UI elements.

The meta script to setup the macos machine from a vanilla OS can be run using the following command:

```zsh
export GH_USERNAME='vraravam' DOTFILES_BRANCH='master' FIRST_INSTALL='true' CACHE_BUST_HEADERS='true' CURL_RETRY_OPTS='true'; curl -H "Cache-Control: no-cache, no-store, must-revalidate" -H "Pragma: no-cache" -H "Expires: 0" --retry 5 --retry-delay 10 --retry-max-time 120 --max-time 150 --connect-timeout 30 --retry-connrefused -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/scripts/fresh-install-of-osx.sh?$(date +%s)" | zsh 2>&1 | tee "${HOME}/fresh-install-of-osx.log"; unset FIRST_INSTALL
```

This script can be run in an idempotent manner, and will setup [antidote](https://antidote.sh/), [homebrew](https://brew.sh), the dotfiles (this repo), etc. It automatically applies the two-phase macOS preference setup in order: `osx-defaults.sh -s` (baseline defaults) followed by `capture-prefs.rb -i` (UI-configured overrides from your previous machine). To test changes on a branch before merging, see [How to test changes in your fork](README.md#how-to-test-changes-in-your-fork-before-raising-a-pull-request).

All these scripts are optimized for fast loading of the shell so that the user can work almost immediately upon starting the app.

### Preference restoration: two-phase sequence

The script seeds and restores macOS preferences in two ordered phases automatically as part of `fresh-install-of-osx.sh`:

1. **`osx-defaults.sh -s`** — seeds a partial baseline of known-good starting values.
2. **`capture-prefs.rb -i`** — imports preferences exported from your previous machine, overriding the baseline where they overlap.

If you have not yet exported preferences from a previous machine, skip step 2 for now and run `capture-prefs.rb -i` once your old machine's export is available. See [Extras.md — osx-defaults.sh](Extras.md#osx-defaultssh) for full details.

**Important Note** After the above script has completed running successfully, you need to do the following *manually* (items marked *optional* are based on your preferences):

- [ ] 1. Use [gitconfig-inc.template](templates/gitconfig-inc.template) as a template to create per-context git config include files (e.g. `${HOME}/.gitconfig-personal.inc`, `${HOME}/.gitconfig-work.inc`), then wire them into `${HOME}/.gitconfig-oss.inc` using [`includeIf "gitdir:..."`](https://git-scm.com/docs/git-config#_conditional_includes) so that git automatically applies the right identity and settings depending on which directory a repo lives in. Other conditions beyond `gitdir:` — such as `onbranch:` and `hasconfig:` — are documented at that link. See the template file for guidance on keeping sensitive values private.

- [ ] 2. Use [ssh-config.template](templates/ssh-config.template) as a template to create `${HOME}/.ssh/config` with your SSH key paths and host aliases. Replace all placeholders with your own values. Note: `install-dotfiles.rb` automatically inserts the `Include "./global_config"` line — you do not need to add it manually. These settings only apply when cloning repos over SSH, not HTTPS.

- [ ] 3. *(optional)* Open the `System Preferences` application.
   * Search for 'Displays' and set scaling / screen resolution as per your preference
   * Search for 'Full Disk Access' and add 'iTerm', 'Terminal', 'zoom.us'
   * Search for 'Camera' and add 'Brave', 'Firefox', 'Zen', 'zoom.us'
   * Search for 'Microphone' and add 'Brave', 'Firefox', 'Zen', 'zoom.us'
   * Search for 'Default web browser' and set as per your preferences
   * Search for 'iCloud' and login and setup Desktop sync

Back to the [readme](README.md#complete-setup)
