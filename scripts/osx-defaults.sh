#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This is a script with useful tips taken from: https://gist.github.com/DAddYE/2108403
# Please, share your tips by forking the repo and adding your customizations
# Thanks to: @erikh, @DAddYE, @mathiasbynens

# set -euo pipefail is intentionally omitted: many 'defaults write' and 'killall'
# calls return non-zero when a setting is unsupported on the current OS version,
# which is expected and must not abort the script.

source "${HOME}/.aliases"
_SCRIPT_NAME="${0:t}"

usage() {
  print_usage "${1}" \
    "$(yellow '[-s]') --> $(yellow '-s') (optional) Run in silent/auto mode without interactive prompts"
}

# Script-level flag for silent mode; set by main() when -s is passed
auto='N'

# Interactive y/n prompt with silent (auto) mode support.
ask() {
  local prompt default yn=''
  while true; do
    case "${2}" in
      'Y')
        prompt="$(green 'Y')/n"
        default='Y'
        ;;
      'N')
        prompt="y/$(green 'N')"
        default='N'
        ;;
      *)
        prompt='y/n'
        default=
        ;;
    esac

    printf "%s" "${1} [${prompt}] "

    if [[ "${auto}" == 'Y' ]]; then
      echo
    else
      read -r yn
    fi

    if is_zero_string "${yn}"; then
      yn="${default}"
    fi

    case ${yn} in
      [Yy]) return 0 ;;
      [Nn]) return 1 ;;
    esac
  done
}

main() {
  auto='N'
  while getopts ':s' opt; do
    case ${opt} in
      s)
        debug 'Running in silent mode...'
        auto='Y'
        ;;
      \?)
        warn "-${OPTARG} is not a valid option"
        usage "${_SCRIPT_NAME}"
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if [[ "${auto}" == 'N' ]] && ! is_running_in_tty; then
    error 'Interactive mode needs terminal!'
    exit 1
  fi

  # Ask for the administrator password upfront and keep it alive until this script has finished
  keep_sudo_alive

  # Close any open System Preferences panes, to prevent them from overriding
  # settings we're about to change
  osascript -e 'tell application "System Preferences" to quit'

  # While applying any changes to SoftwareUpdate defaults, set software update to OFF to avoid any conflict with the defaults system cache. (Also close the System Preferences app)
  sudo softwareupdate --schedule OFF

  # Couldn't find the following settings in macOS Mojave (10.14.3)
  # Expand 'save as...' dialog by default
  # defaults write -g NSNavPanelExpandedStateForSaveMode -bool true
  # defaults write -g NSNavPanelExpandedStateForSaveMode2 -bool true

  # Expand print panel by default
  # defaults write -g PMPrintingExpandedStateForPrint -bool true
  # defaults write -g PMPrintingExpandedStateForPrint2 -bool true

  # Automatically quit printer app once the print jobs complete
  # defaults write com.apple.print.PrintingPrefs 'Quit When Finished' -bool true

  # Restore the 'Save As' menu item (Equivalent to adding a Keyboard shortcut in the System Preferences.app )
  # defaults write -g NSUserKeyEquivalents -dict-add 'Save As...' '@$S'

  # Global User Interface Scale Multiplier:
  # defaults write -g AppleDisplayScaleFactor -float

  # Enable continuous spell checking everywhere:
  # defaults write -g WebContinuousSpellCheckingEnabled -boolean

  # Enable automatic dash replacement everywhere:
  # defaults write -g WebAutomaticDashSubstitutionEnabled -boolean

  # Enable automatic text replacement everywhere:
  # defaults write -g WebAutomaticTextReplacementEnabled -boolean

  # Icon Size for Open Panels:
  # defaults write -g NSNavPanelIconViewIconSizeForOpenMode -number

  # Disable press-and-hold for keys in favor of key repeat

  # Set a blazingly fast keyboard repeat rate
  # defaults write NSGlobalDomain KeyRepeat -int 1
  # defaults write NSGlobalDomain InitialKeyRepeat -int 10

  # Login Window
  if ask 'Disable guest login' 'Y'; then
    sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
  fi

  # MenuBar
  # Disable menu bar transparency - Couldn't find this in mac OS Mojave
  # defaults write -g AppleEnableMenuBarTransparency -bool false

  # System Settings > Control Center > Menu Bar Only items
  # Bluetooth = on
  defaults write com.apple.controlcenter 'NSStatusItem Visible Bluetooth' 1
  # WiFi = on
  defaults write com.apple.controlcenter 'NSStatusItem Visible WiFi' -bool true
  # Battery = off
  defaults write com.apple.controlcenter 'NSStatusItem Visible Battery' 0
  # Clock = off (use a dedicated clock app such as Clocker instead)
  defaults write com.apple.controlcenter 'NSStatusItem VisibleCC Clock' -bool false
  # Spotlight = off (use Raycast instead)
  defaults write com.apple.controlcenter 'NSStatusItem Visible Spotlight' -bool false
  # AirDrop = off
  defaults write com.apple.controlcenter 'NSStatusItem Visible AirDrop' -bool false
  # Text Input = off
  defaults write com.apple.controlcenter 'NSStatusItem Visible TextInput' -bool false
  # Keyboard Brightness = off
  defaults write com.apple.controlcenter 'NSStatusItem Visible KeyboardBrightness' -bool false
  # Weather = off
  defaults write com.apple.controlcenter 'NSStatusItem Visible Weather' -bool false
  # Focus = show when active (8=when active, 16=always, 24=never)
  defaults write com.apple.controlcenter 'FocusModes' -int 8
  # Screen Mirroring = show when active
  defaults write com.apple.controlcenter 'AirPlayDisplay' -int 8
  # Display = show when active
  defaults write com.apple.controlcenter 'Display' -int 8
  # Sound = show when active
  defaults write com.apple.controlcenter 'Sound' -int 8
  # Now Playing = show when active
  defaults write com.apple.controlcenter 'NowPlaying' -int 8

  if ask 'Keep keyboard brightness at maximum' 'Y'; then
    defaults -currentHost write com.apple.controlcenter KeyboardBrightness 8
  fi

  # TODO: Doesn't seem to work (tried in sequoia 15.5)
  # if ask 'Turn off keyboard backlight auto-dim' 'Y'; then
  #   defaults write com.apple.CoreBrightness KeyboardBacklightAutoDim -bool false
  # fi

  if ask 'Disable automatic keyboard brightness adjustment in low light' 'Y'; then
    # com.apple.BezelServices dAuto controls "Adjust keyboard brightness in low light"
    # (System Settings > Keyboard). CoreBrightness KeyboardBacklightAutoDim does not
    # work on modern macOS; dAuto is the correct key.
    defaults write com.apple.BezelServices dAuto -bool false
  fi

  # General UI/UX

  if ask 'Set computer name (as done via System Preferences → Sharing)' 'Y'; then
    local username_in_camel_case="${(C)USER}"
    local human_date
    current_timestamp_for_filename human_date

    sudo scutil --set ComputerName "IND-CHN-${username_in_camel_case}'s MBP-${human_date}"
    sudo scutil --set HostName "${username_in_camel_case}-${human_date}"
    sudo scutil --set LocalHostName "${username_in_camel_case}-${human_date}"
    sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "${username_in_camel_case}-${human_date}"
  fi

  if ask 'Set standby delay to 6 hours (default: 1 hour)' 'Y'; then
    sudo pmset -a standbydelay 21600
  fi

  # Disable the sound effects on boot
  # sudo nvram SystemAudioVolume=' '

  # Disable transparency in the menu bar and elsewhere on Yosemite
  # defaults write com.apple.universalaccess reduceTransparency -bool true

  # Set highlight color to green
  # defaults write NSGlobalDomain AppleHighlightColor -string '0.764700 0.976500 0.568600'

  # Use zsh glob qualifier (N.) for nullglob and regular files
  for domain in "${HOME}"/Library/Preferences/ByHost/com.apple.systemuiserver.*(N.); do
    defaults write "${domain}" dontAutoLoad -array \
      '/System/Library/CoreServices/Menu Extras/TimeMachine.menu' \
      '/System/Library/CoreServices/Menu Extras/Volume.menu' \
      '/System/Library/CoreServices/Menu Extras/User.menu'
  done
  defaults write com.apple.systemuiserver menuExtras -array \
    '/System/Library/CoreServices/Menu Extras/Bluetooth.menu' \
    '/System/Library/CoreServices/Menu Extras/AirPort.menu' \
    '/System/Library/CoreServices/Menu Extras/Battery.menu' \
    '/System/Library/CoreServices/Menu Extras/Clock.menu' \
    '/System/Library/CoreServices/Menu Extras/User.menu' \
    '/System/Library/CoreServices/Menu Extras/Volume.menu'

  defaults write com.apple.systemuiserver 'NSStatusItem Visible Siri' -bool false
  defaults write com.apple.systemuiserver 'NSStatusItem Visible com.apple.menuextra.airport' -bool true
  defaults write com.apple.systemuiserver 'NSStatusItem Visible com.apple.menuextra.appleuser' -bool true
  defaults write com.apple.systemuiserver 'NSStatusItem Visible com.apple.menuextra.battery' -bool true
  defaults write com.apple.systemuiserver 'NSStatusItem Visible com.apple.menuextra.bluetooth' -bool true
  defaults write com.apple.systemuiserver 'NSStatusItem Visible com.apple.menuextra.volume' -bool true

  defaults write com.apple.menuextra.clock DateFormat -string 'EEE d MMM hh:mm:ss a'
  defaults write com.apple.menuextra.clock FlashDateSeparators -bool true
  defaults write com.apple.menuextra.clock IsAnalog -bool true # Since I am using `The Clocker` app, turning this to analog
  defaults write com.apple.menuextra.clock Show24Hour -bool false
  defaults write com.apple.menuextra.clock ShowAMPM -bool true
  defaults write com.apple.menuextra.clock ShowDate -bool false
  defaults write com.apple.menuextra.clock ShowDayOfMonth -bool true
  defaults write com.apple.menuextra.clock ShowDayOfWeek -bool false
  defaults write com.apple.menuextra.clock ShowSeconds -bool true

  if ask "Remove duplicates in the 'Open With' menu (also see 'lscleanup' alias)" 'Y'; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
  fi

  # Display ASCII control characters using caret notation in standard text views
  # Try e.g. `cd /tmp; unidecode "\x{0000}" > cc.txt; open -e cc.txt`
  # defaults write -g NSTextShowsControlCharacters -bool true

  # if ask 'Enable multitouch trackpad auto orientation sensing (for all users)' 'Y'; then
  #   defaults write /Library/Preferences/com.apple.MultitouchSupport ForceAutoOrientation -boolean
  # fi

  if ask 'Keep windows open when quitting and re-opening apps (Resume)' 'Y'; then
    defaults write -g NSQuitAlwaysKeepsWindows -bool true
  fi

  if ask 'Restart automatically if the computer freezes' 'Y'; then
    # systemsetup emits a harmless Error:-99 to stderr on modern macOS (SIP restriction
    # on the InternetServices subsystem); the command still applies the setting correctly.
    sudo systemsetup -setrestartfreeze on 2>/dev/null
  fi

  if ask "Set the timezone to Asia/Calcutta" 'Y'; then
    # see 'sudo systemsetup -listtimezones' for other values
    sudo systemsetup -settimezone 'Asia/Calcutta' 2>/dev/null
  fi

  if ask 'Sync time automatically using network time servers' 'Y'; then
    sudo systemsetup -setusingnetworktime on 2>/dev/null
  fi

  if ask 'Set the computer sleep time to 10 minutes' 'Y'; then
    # To never go into computer sleep mode, use 'Never' or 'Off'
    sudo systemsetup -setcomputersleep 10 2>/dev/null
  fi

  if ask 'Set the display sleep time to 10 minutes' 'Y'; then
    # To never go into display sleep mode, use 'Never' or 'Off'
    sudo systemsetup -setdisplaysleep 10 2>/dev/null
  fi

  if ask 'Set the hard disk sleep time to 15 minutes' 'Y'; then
    # To never go into harddisk sleep mode, use 'Never' or 'Off'
    sudo systemsetup -setharddisksleep 15 2>/dev/null
  fi

  # TODO: This causes terminal.app to run in an interactive loop
  # if ask 'Set the remote login to off' 'Y'; then
  #   sudo systemsetup -setremotelogin off
  # fi

  # Disable Notification Center and remove the menu bar icon
  # launchctl unload -w /System/Library/LaunchAgents/com.apple.notificationcenterui.plist 2> /dev/null

  if ask 'Disable automatic capitalization' 'Y'; then
    defaults write -g NSAutomaticCapitalizationEnabled -bool false
  fi

  if ask 'Set preferred languages to English (India, US) and clear recent places' 'Y'; then
    defaults write -g NSLinguisticDataAssetsRequested -array 'en_IN' 'en_US' 'en'
    # Suppress error when the key doesn't exist — delete is a no-op in that case.
    defaults delete NSGlobalDomain NSNavRecentPlaces 2>/dev/null || true
  fi

  # TODO: defaults write -g NSPreferredWebServices NSWebServicesProviderWebSearch

  if ask 'Set text shortcuts for common phrases (dfdm, ntd, cyl, ttyl, omw, omg)' 'Y'; then
    defaults write -g NSUserDictionaryReplacementItems -array \
      '{ on = 1; replace = dfdm; with = "dropping off for different meeting"; }' \
      '{ on = 1; replace = ntd; with = "need to drop"; }' \
      '{ on = 1; replace = cyl; with = "Cya later!"; }' \
      '{ on = 1; replace = ttyl; with = "Talk to you later!"; }' \
      '{ on = 1; replace = omw; with = "On my way!"; }' \
      '{ on = 1; replace = omg; with = "Oh my God!"; }'
  fi

  if ask 'Disable automatic period substitution (double-space → period)' 'Y'; then
    defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false
  fi

  if ask 'Disable adding apps to the Services contextual menu (reduces right-click clutter)' 'Y'; then
    # com.apple.SetupAssistant domain is machine-specific overall, but this single key
    # is a portable user preference controlling whether apps populate the Services submenu.
    defaults write com.apple.SetupAssistant NSAddServicesToContextMenus -bool false
  fi

  # TODO: This is not working yet
  # Set a custom wallpaper image. `DefaultDesktop.jpg` is already a symlink, and
  # all wallpapers are in `/Library/Desktop Pictures/`. The default is `Wave.jpg`.
  #rm -rf ${HOME}/Library/Application Support/Dock/desktoppicture.db
  #sudo rm -rf /System/Library/CoreServices/DefaultDesktop.jpg
  #sudo ln -s /path/to/your/image /System/Library/CoreServices/DefaultDesktop.jpg

  # TextEdit

  # SSD-specific tweaks
  if ask 'Disable hibernation (speeds up entering sleep mode)' 'Y'; then
    sudo pmset -a hibernatemode 0
  fi

  if ask "Disable the sudden motion sensor (not useful for SSDs)" 'Y'; then
    sudo pmset -a sms 0
  fi

  # Trackpad, mouse, keyboard, Bluetooth accessories, and input

  # Bluetooth trackpad (com.apple.driver.AppleBluetoothMultitouch.trackpad) and
  # built-in trackpad (com.apple.AppleMultitouchTrackpad) share the same gesture
  # keys — both domains must be written to keep wired and wireless behaviour in sync.
  if ask 'Enable trackpad gestures (tap-to-click, three-finger drag, etc.)' 'Y'; then
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -int 1
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad DragLock -int 0
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Dragging -int 0
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadCornerSecondaryClick -int 0
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFiveFingerPinchGesture -int 2
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerHorizSwipeGesture -int 2
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerPinchGesture -int 2
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadFourFingerVertSwipeGesture -int 2
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadHandResting -int 1
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadHorizScroll -int 1
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadMomentumScroll -int 1
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadPinch -int 1
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRightClick -int 1
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadRotate -int 1
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadScroll -int 1
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -int 0
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerHorizSwipeGesture -int 2
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerTapGesture -int 0
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerVertSwipeGesture -int 2
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadTwoFingerDoubleTapGesture -int 1
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadTwoFingerFromRightEdgeSwipeGesture -int 3
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad USBMouseStopsTrackpad -int 0
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad UserPreferences -int 1
    # Built-in trackpad — same gesture settings applied to the internal hardware domain.
    defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
    defaults write com.apple.AppleMultitouchTrackpad DragLock -int 0
    defaults write com.apple.AppleMultitouchTrackpad Dragging -int 0
    defaults write com.apple.AppleMultitouchTrackpad FirstClickThreshold -int 1
    defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -int 0
    defaults write com.apple.AppleMultitouchTrackpad SecondClickThreshold -int 1
    defaults write com.apple.AppleMultitouchTrackpad TrackpadCornerSecondaryClick -int 0
    defaults write com.apple.AppleMultitouchTrackpad TrackpadFiveFingerPinchGesture -int 2
    defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerHorizSwipeGesture -int 2
    defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerPinchGesture -int 2
    defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture -int 2
    defaults write com.apple.AppleMultitouchTrackpad TrackpadHandResting -int 1
    defaults write com.apple.AppleMultitouchTrackpad TrackpadHorizScroll -int 1
    defaults write com.apple.AppleMultitouchTrackpad TrackpadMomentumScroll -int 1
    defaults write com.apple.AppleMultitouchTrackpad TrackpadPinch -int 1
    defaults write com.apple.AppleMultitouchTrackpad TrackpadRightClick -int 1
    defaults write com.apple.AppleMultitouchTrackpad TrackpadRotate -int 1
    defaults write com.apple.AppleMultitouchTrackpad TrackpadScroll -int 1
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -int 0
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture -int 2
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 2
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 2
    defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerDoubleTapGesture -int 1
    defaults write com.apple.AppleMultitouchTrackpad TrackpadTwoFingerFromRightEdgeSwipeGesture -int 3
    defaults write com.apple.AppleMultitouchTrackpad USBMouseStopsTrackpad -int 0
    defaults write com.apple.AppleMultitouchTrackpad UserPreferences -int 1
    # System Settings > Trackpad > Tap to click: this host-level key is what the
    # Settings UI reads to show the toggle state. All three writes are required:
    # the two domain writes above configure the hardware drivers; this one tells
    # the UI the user has enabled tap-to-click.
    defaults -currentHost write -g com.apple.mouse.tapBehavior -int 1
  fi

  # Apple Multitouch Mouse
  if ask 'Apple Multitouch mouse features' 'Y'; then
    defaults write com.apple.AppleMultitouchMouse MouseButtonMode -string 'OneButton'
    defaults write com.apple.AppleMultitouchMouse MouseHorizontalScroll -int 1
    defaults write com.apple.AppleMultitouchMouse MouseMomentumScroll -int 1
    defaults write com.apple.AppleMultitouchMouse MouseOneFingerDoubleTapGesture -int 0
    defaults write com.apple.AppleMultitouchMouse MouseTwoFingerDoubleTapGesture -int 3
    defaults write com.apple.AppleMultitouchMouse MouseTwoFingerHorizSwipeGesture -int 2
    defaults write com.apple.AppleMultitouchMouse MouseVerticalScroll -int 1
    defaults write com.apple.AppleMultitouchMouse UserPreferences -int 1
  fi

  if ask 'Enable full keyboard access for all controls (e.g. Tab in modal dialogs)' 'Y'; then
    defaults write -g AppleKeyboardUIMode -int 2
  fi

  if ask 'Set language to English (India), locale to INR currency, metric units, double-click titlebar to maximise' 'Y'; then
    # Note: if you're in the US, replace `EUR` with `USD`, `Centimeters` with
    # `Inches`, `en_GB` with `en_US`, and `true` with `false`.
    defaults write -g AppleLanguages -array 'en-IN' 'en'
    defaults write -g AppleLocale -string 'en_IN@currency=INR'
    defaults write -g AppleMeasurementUnits -string 'Centimeters'
    defaults write -g AppleMetricUnits -bool true
    defaults write -g AppleActionOnDoubleClick -string 'Maximize'
  fi

  # Stop iTunes from responding to the keyboard media keys
  # launchctl unload -w /System/Library/LaunchAgents/com.apple.rcd.plist 2> /dev/null

  # Use scroll gesture with the Ctrl (^) modifier key to zoom
  # defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
  # defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144
  # Follow the keyboard focus while zoomed in
  # defaults write com.apple.universalaccess closeViewZoomFollowsFocus -bool true

  # Finder

  if ask 'Allow quitting Finder via ⌘Q (also hides desktop icons)' 'Y'; then
    defaults write com.apple.finder QuitMenuItem -bool true
  fi

  # if ask 'Disable window animations and Get Info animations' 'Y'; then
  #   defaults write com.apple.finder DisableAllAnimations -bool true
  #fi

  if ask 'Set Home folder as the default location for new Finder windows' 'Y'; then
    # For other paths, use `PfLo` and `file:///full/path/here/`
    defaults write com.apple.finder NewWindowTarget -string 'PfHm'
    defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"
  fi

  if ask 'Hide hard drive icons on the desktop' 'N'; then
    defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
  fi

  if ask 'Hide hidden files by default in Finder' 'N'; then
    defaults write com.apple.finder AppleShowAllFiles -bool false
  fi

  if ask 'Show all filename extensions' 'Y'; then
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  fi

  if ask 'Display full POSIX path as Finder window title' 'Y'; then
    defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
  fi

  if ask 'Show status bar in Finder windows' 'Y'; then
    defaults write com.apple.finder ShowStatusBar -bool true
  fi

  if ask "Start the status bar path at \${HOME} (instead of 'Hard drive')" 'Y'; then
    sudo defaults write /Library/Preferences/com.apple.finder PathBarRootAtHome -bool true
  fi

  if ask 'Show path (breadcrumb) bar in Finder windows' 'Y'; then
    defaults write com.apple.finder ShowPathbar -bool true
  fi

  if ask 'Hide the preview pane in Finder' 'Y'; then
    defaults write com.apple.finder ShowPreviewPane -bool false
  fi

  defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
  defaults write com.apple.finder ShowMountedServersOnDesktop -bool false
  defaults write com.apple.finder ShowRecentTags -bool false
  defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
  defaults write com.apple.finder ShowSidebar -bool true
  defaults write com.apple.finder SidebarDevicesSectionDisclosedState -bool true
  defaults write com.apple.finder SidebarPlacesSectionDisclosedState -bool true
  defaults write com.apple.finder SidebarShowingSignedIntoiCloud -bool true
  defaults write com.apple.finder SidebarShowingiCloudDesktop -bool true
  defaults write com.apple.finder SidebarTagsSctionDisclosedState -bool true
  defaults write com.apple.finder SidebarWidth 172
  defaults write com.apple.finder SidebariCloudDriveSectionDisclosedState -bool true
  defaults write com.apple.finder FXRemoveOldTrashItems -bool true
  defaults write com.apple.finder _FXEnableColumnAutoSizing -bool true

  if ask 'Enable iCloud Drive Optimize Mac Storage (keep full copies in iCloud, evict local copies when space is needed)' 'Y'; then
    # com.apple.bird is the iCloud Drive daemon. The optimize-storage key is the only
    # portable user preference in this domain; all other keys are runtime/account state.
    defaults write com.apple.bird optimize-storage -bool true
  fi

  if ask 'Allow text selection in Quick Look / Preview' 'Y'; then
    defaults write com.apple.finder QLEnableTextSelection -bool true
  fi

  if ask 'Keep folders on top when sorting by name (Finder and Desktop)' 'Y'; then
    defaults write com.apple.finder _FXSortFoldersFirst -bool true
    defaults write com.apple.finder _FXSortFoldersFirstOnDesktop -bool true
  fi

  if ask 'When performing a search, search the current folder by default (not This Mac)' 'Y'; then
    defaults write com.apple.finder FXDefaultSearchScope -string 'SCcf'
  fi

  if ask 'Disable the warning when changing a file extension' 'N'; then
    defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
  fi

  # if ask 'Enable spring loading for directories' 'Y'; then
  #   defaults write -g com.apple.springing.enabled -bool true
  #fi

  # if ask 'Remove the delay for spring loading for directories' 'Y'; then
  #   defaults write -g com.apple.springing.delay -float 0
  # fi

  if ask 'Enable snap-to-grid for icons on the desktop and in other icon views' 'Y'; then
    /usr/libexec/PlistBuddy -c 'Set :DesktopViewSettings:IconViewSettings:arrangeBy grid' "${HOME}/Library/Preferences/com.apple.finder.plist"
    /usr/libexec/PlistBuddy -c 'Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid' "${HOME}/Library/Preferences/com.apple.finder.plist"
    /usr/libexec/PlistBuddy -c 'Set :StandardViewSettings:IconViewSettings:arrangeBy grid' "${HOME}/Library/Preferences/com.apple.finder.plist"
  fi

  if ask 'Increase grid spacing for icons on the desktop and in other icon views' 'Y'; then
    /usr/libexec/PlistBuddy -c 'Set :DesktopViewSettings:IconViewSettings:gridSpacing 54' "${HOME}/Library/Preferences/com.apple.finder.plist"
    /usr/libexec/PlistBuddy -c 'Set :FK_StandardViewSettings:IconViewSettings:gridSpacing 54' "${HOME}/Library/Preferences/com.apple.finder.plist"
    /usr/libexec/PlistBuddy -c 'Set :StandardViewSettings:IconViewSettings:gridSpacing 54' "${HOME}/Library/Preferences/com.apple.finder.plist"
  fi

  if ask 'Increase the size of icons on the desktop and in other icon views' 'Y'; then
    /usr/libexec/PlistBuddy -c 'Set :DesktopViewSettings:IconViewSettings:iconSize 64' "${HOME}/Library/Preferences/com.apple.finder.plist"
    /usr/libexec/PlistBuddy -c 'Set :FK_StandardViewSettings:IconViewSettings:iconSize 64' "${HOME}/Library/Preferences/com.apple.finder.plist"
    /usr/libexec/PlistBuddy -c 'Set :StandardViewSettings:IconViewSettings:iconSize 64' "${HOME}/Library/Preferences/com.apple.finder.plist"
  fi

  # Show item info near icons on the desktop and in other icon views
  # /usr/libexec/PlistBuddy -c 'Set :DesktopViewSettings:IconViewSettings:showItemInfo true' "${HOME}/Library/Preferences/com.apple.finder.plist"
  # /usr/libexec/PlistBuddy -c 'Set :FK_StandardViewSettings:IconViewSettings:showItemInfo true' "${HOME}/Library/Preferences/com.apple.finder.plist"
  # /usr/libexec/PlistBuddy -c 'Set :StandardViewSettings:IconViewSettings:showItemInfo true' "${HOME}/Library/Preferences/com.apple.finder.plist"

  # Show item info to the right of the icons on the desktop
  # /usr/libexec/PlistBuddy -c 'Set :DesktopViewSettings:IconViewSettings:labelOnBottom false' "${HOME}/Library/Preferences/com.apple.finder.plist"

  if ask 'Use column view in all Finder windows by default' 'Y'; then
    # Four-letter codes for the other view modes: `icnv` (icon), `Nlsv` (list), `Flwv` (cover flow)
    defaults write com.apple.finder FXPreferredViewStyle -string 'clmv'
    defaults write com.apple.finder SearchRecentsSavedViewStyle -string 'clmv'
  fi

  if ask 'Disable the warning before emptying the Trash' 'Y'; then
    defaults write com.apple.finder WarnOnEmptyTrash -bool false
  fi

  if ask 'Empty Trash securely by default' 'Y'; then
    defaults write com.apple.finder EmptyTrashSecurely -bool true
  fi

  if ask 'Show app-centric sidebar' 'Y'; then
    defaults write com.apple.finder FK_AppCentricShowSidebar -bool true
  fi

  if ask 'Automatically open a new Finder window when a volume is mounted' 'Y'; then
    defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true
  fi

  if ask "Show the ${HOME}/Library folder" 'Y'; then
    chflags nohidden "${HOME}/Library"
  fi

  if ask 'Enable the MacBook Air SuperDrive on any Mac' 'N'; then
    sudo nvram boot-args='mbasd=1'
  fi

  if ask "Show the '/Volumes' folder" 'Y'; then
    sudo chflags nohidden /Volumes
  fi

  # Remove Dropbox's green checkmark icons in Finder
  # file=/Applications/Dropbox.app/Contents/Resources/emblem-dropbox-uptodate.icns
  # is_file "${file}" && mv -fv "${file}" "${file}.bak"

  if ask "Expand File Info panes: 'General', 'Open with', 'Sharing & Permissions', 'Comments', 'Name', 'Metadata'" 'Y'; then
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'Comments' -bool true
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'General' -bool true
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'MetaData' -bool true
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'Name' -bool true
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'OpenWith' -bool true
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'Privileges' -bool true
  fi

  if ask 'Windows which were open prior to logging out are re-opened after logging in' 'Y'; then
    defaults write com.apple.finder RestoreWindowState -bool true
  fi

  # Applications often need to be relaunched to see the change.
  # if ask 'Location and style of scrollbar arrows' 'N'; then
  #   defaults write -g AppleScrollBarVariant -string 'DoubleBoth' true
  # fi

  # if ask 'Disable window animations' 'N'; then
  #   defaults write -g NSAutomaticWindowAnimationsEnabled -bool false && killall Finder
  #fi

  # Avoiding the creation of .DS_Store files on network volumes
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

  # Energy saving

  # Enable lid wakeup
  sudo pmset -a lidwake 1

  # Restart automatically on power loss
  sudo pmset -a autorestart 1

  # Sleep the display after 15 minutes
  # sudo pmset -a displaysleep 15

  # Disable machine sleep while charging
  # sudo pmset -c sleep 0

  # Set machine sleep to 5 minutes on battery
  # sudo pmset -b sleep 5

  # Set standby delay to 24 hours (default is 1 hour)
  # sudo pmset -a standbydelay 86400

  # Never go into computer sleep mode
  # sudo systemsetup -setcomputersleep Off &>/dev/null

  # Hibernation mode
  # 0: Disable hibernation (speeds up entering sleep mode)
  # 3: Copy RAM to disk so the system state can still be restored in case of a
  #    power failure.
  # sudo pmset -a hibernatemode 0

  # Remove the sleep image file to save disk space
  # sudo rm /private/var/vm/sleepimage
  # Create a zero-byte file instead…
  # sudo touch /private/var/vm/sleepimage
  # …and make sure it can't be rewritten
  # sudo chflags uchg /private/var/vm/sleepimage

  # Preview
  # if ask 'Scale images by default when printing' 'Y'; then
  #   defaults write com.apple.Preview PVImagePrintingScaleMode -bool true
  #fi

  # if ask 'Preview Auto-rotate by default when printing' 'Y'; then
  #   defaults write com.apple.Preview PVImagePrintingAutoRotate -bool true
  #fi

  # if ask 'Quit Always Keeps Windows' 'Y'; then
  #   defaults write com.apple.Preview NSQuitAlwaysKeepsWindows -bool true
  #fi

  # Keychain
  if ask 'Keychain shows expired certificates' 'Y'; then
    defaults write com.apple.keychainaccess 'Show Expired Certificates' -bool true
  fi

  if ask 'Makes Keychain Access display *unsigned* ACL entries in italics' 'Y'; then
    defaults write com.apple.keychainaccess 'Distinguish Legacy ACLs' -bool true
  fi

  # Remote Desktop
  # if ask 'Admin Console Allows Remote Control' 'N'; then
  #   defaults delete /Library/Preferences/com.apple.RemoteManagement AdminConsoleAllowsRemoteControl
  # fi

  # if ask 'Disable Multicast' 'Y'; then
  #   defaults write /Library/Preferences/com.apple.RemoteManagement ARD_MulticastAllowed -bool true
  # fi

  # if ask 'Prevents system keys like command-tab from being sent' 'Y'; then
  #   defaults write com.apple.RemoteDesktop DoNotSendSystemKeys -bool true
  # fi

  if ask 'Show the Debug menu Remote Desktop' 'Y'; then
    defaults write com.apple.remotedesktop IncludeDebugMenu -bool true
  fi

  if ask 'Define user name display behavior' 'Y'; then
    defaults write com.apple.remotedesktop showShortUserName -bool true
  fi

  # if ask 'Set the maximum number of computers that can be observed: (up to 50 opposed to the default of 9)' 'Y'; then
  #   defaults write com.apple.RemoteDesktop multiObserveMaxPerScreen -int 20
  # fi

  # Screen Sharing
  # if ask 'Prevent protection when attempting to remotely control this computer' 'Y'; then
  #   defaults write com.apple.ScreenSharing skipLocalAddressCheck -bool true
  # fi

  # if ask 'Disables system-level key combos like command-option-esc (Force Quit), command-tab (App switcher) to be used on the remote machine' 'Y'; then
  #   defaults write com.apple.ScreenSharing DoNotSendSystemKeys -bool true
  # fi

  # if ask 'Debug (To Show Bonjour)' 'Y'; then
  #   defaults write com.apple.ScreenSharing debug -bool true
  # fi

  # if ask 'Do Not Send Special Keys to Remote Machine' 'Y'; then
  #   defaults write com.apple.ScreenSharing DoNotSendSystemKeys -bool true
  # fi

  # if ask 'Skip local address check' 'Y'; then
  #   defaults write com.apple.ScreenSharing skipLocalAddressCheck -bool true
  # fi

  # if ask 'Screen sharing image quality' 'Y'; then
  #   defaults write com.apple.ScreenSharing controlObserveQuality -int 10
  # fi

  # if ask 'Number of recent hosts on ScreenSharingMenulet' 'Y'; then
  #   defaults write com.klieme.ScreenSharingMenulet maxHosts -int 5
  # fi

  # if ask 'Display IP-Addresses of the local hosts on ScreenSharingMenulet' 'Y'; then
  #   defaults write com.klieme.ScreenSharingMenulet showIPAddresses -bool true
  # fi

  # Dock, Dashboard, and hot corners
  if ask 'Set the icon size of Dock items to 35 pixels' 'Y'; then
    defaults write com.apple.dock tilesize -int 35
  fi

  if ask 'Move the dock to the right side of the screen' 'Y'; then
    defaults write com.apple.dock orientation -string 'right'
  fi

  if ask "Minimize windows into their application's icon" 'Y'; then
    defaults write com.apple.dock 'minimize-to-application' -bool true
  fi

  if ask 'Show only active apps in Dock' 'Y'; then
    defaults write com.apple.dock 'static-only' -bool true
  fi

  # if ask 'Enable spring loading for all Dock items' 'Y'; then
  #   defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true
  # fi

  if ask 'Enable highlight hover effect for the grid view of a stack (Dock)' 'Y'; then
    defaults write com.apple.dock mouse-over-hilite-stack -bool true
  fi

  if ask 'Show indicator lights for open applications in the Dock' 'Y'; then
    defaults write com.apple.dock 'show-process-indicators' -bool true
  fi

  if ask 'Animate opening applications from the Dock' 'Y'; then
    defaults write com.apple.dock launchanim -bool true
  fi

  if ask 'Change minimize/maximize window effect' 'Y'; then
    defaults write com.apple.dock mineffect -string 'suck'
  fi

  if ask 'Speed up Mission Control animations' 'Y'; then
    defaults write com.apple.dock 'expose-animation-duration' -float 0.5
  fi

  if ask "Don't group windows by application in Mission Control (i.e. use the old Exposé behavior instead)" 'N'; then
    defaults write com.apple.dock "expose-group-by-app" -bool false
  fi

  if ask 'Enable Mission Control' 'N'; then
    defaults write com.apple.Dock 'mcx-expose-disabled' -bool false
  fi

  if ask "Don't show Dashboard as a Space" 'N'; then
    defaults write com.apple.dock 'dashboard-in-overlay' -bool true
  fi

  if ask 'Show image for notifications' 'Y'; then
    defaults write com.apple.dock 'notification-always-show-image' -bool true
  fi

  if ask 'Enable the 2D Dock' 'N'; then
    defaults write com.apple.dock 'no-glass' -bool true
  fi

  if ask 'Enable Bouncing dock icons' 'Y'; then
    defaults write com.apple.dock 'no-bouncing' -bool false
  fi

  if ask 'Keep multi-display swoosh animations enabled' 'N'; then
    defaults write com.apple.dock 'workspaces-swoosh-animation-off' -bool false
  fi

  if ask 'Remove the animation when hiding or showing the dock' 'Y'; then
    defaults write com.apple.dock 'autohide-time-modifier' -float 0
  fi

  if ask 'Enable iTunes pop-up notifications' 'N'; then
    defaults write com.apple.dock 'itunes-notifications' -boolean false
  fi

  # if ask "Add a 'Recent Applications' stack to the Dock" 'Y'; then
  #   defaults write com.apple.dock persistent-others -array-add '{ 'tile-data' = { 'list-type' = 1; }; 'tile-type' = 'recents-tile'; }'
  #fi

  if ask 'In Expose, only show windows from the current space' 'N'; then
    defaults write com.apple.dock 'wvous-show-windows-in-other-spaces' -bool false
  fi

  if ask 'Automatically rearrange Spaces based on most recent use' 'Y'; then
    defaults write com.apple.dock 'mru-spaces' -bool true
  fi

  if ask 'Remove the auto-hiding Dock delay' 'N'; then
    defaults write com.apple.dock 'autohide-delay' -float 0
  fi

  if ask 'Automatically hide and show the Dock' 'Y'; then
    defaults write com.apple.dock autohide -bool true
  fi

  if ask 'Automatically magnify the Dock' 'Y'; then
    defaults write com.apple.dock magnification -bool true
  fi

  if ask 'Make Dock icons of hidden applications translucent' 'Y'; then
    defaults write com.apple.dock showhidden -bool true
  fi

  if ask "Enable the 'reopen windows when logging back in' option" 'N'; then
    # This works, although the checkbox will still appear to be checked.
    defaults write com.apple.loginwindow TALLogoutSavesState -bool true
    defaults write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -bool true
  fi

  # Launchpad
  if ask 'Number of columns and rows in the dock springboard set to 10' 'Y'; then
    defaults write com.apple.dock springboard-rows -int 10
    defaults write com.apple.dock springboard-columns -int 10
  fi
  # defaults write com.apple.dock ResetLaunchPad -bool true

  if ask 'Disable the Launchpad gesture (pinch with thumb and three fingers)' 'N'; then
    defaults write com.apple.dock showLaunchpadGestureEnabled -int 0
  fi

  # Add iOS & Watch Simulator to Launchpad
  # sudo ln -sf '/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app' '/Applications/Simulator.app'
  # sudo ln -sf '/Applications/Xcode.app/Contents/Developer/Applications/Simulator (Watch).app' '/Applications/Simulator (Watch).app'

  # Add a spacer to the left side of the Dock (where the applications are)
  # defaults write com.apple.dock persistent-apps -array-add '{tile-data={}; tile-type="spacer-tile";}'
  # Add a spacer to the right side of the Dock (where the Trash is)
  # defaults write com.apple.dock persistent-others -array-add '{tile-data={}; tile-type="spacer-tile";}'

  if ask 'Hot corners' 'Y'; then
    # Possible values:
    #  0: no-op
    #  2: Mission Control
    #  3: Show application windows
    #  4: Desktop
    #  5: Start screen saver
    #  6: Disable screen saver
    #  7: Dashboard
    # 10: Put display to sleep
    # 11: Launchpad
    # 12: Notification Center
    # Top left screen corner → Desktop
    defaults write com.apple.dock wvous-tl-corner -int 4
    defaults write com.apple.dock wvous-tl-modifier -int 0
    # Bottom left screen corner → No-op
    defaults write com.apple.dock wvous-bl-corner -int 0
    defaults write com.apple.dock wvous-bl-modifier -int 0
    # Top right screen corner → Mission Control
    defaults write com.apple.dock wvous-tr-corner -int 2
    defaults write com.apple.dock wvous-tr-modifier -int 0
    # Bottom right screen corner → Start screen saver
    defaults write com.apple.dock wvous-br-corner -int 5
    defaults write com.apple.dock wvous-br-modifier -int 0
  fi

  # Safari & WebKit
  if ask "Privacy: don't send search queries to Apple" 'Y'; then
    defaults write com.apple.Safari UniversalSearchEnabled -bool false
    defaults write com.apple.Safari SuppressSearchSuggestions -bool true
  fi

  # if ask 'Press Tab to highlight each item on a web page' 'Y'; then
  #   defaults write com.apple.Safari WebKitTabToLinksPreferenceKey -bool true
  #   defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2TabsToLinks -bool true
  # fi

  if ask 'Show the full URL in the address bar (note: this still hides the scheme)' 'Y'; then
    defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
  fi

  if ask "Set Safari's home page to 'about:blank' for faster loading" 'N'; then
    defaults write com.apple.Safari HomePage -string 'about:blank'
  fi

  if ask "Prevent Safari from opening 'safe' files automatically after downloading" 'Y'; then
    defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
  fi

  if ask 'Allow hitting the Backspace key to go to the previous page in history' 'Y'; then
    defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled -bool true
  fi

  if ask "Hide Safari's bookmarks bar by default" 'Y'; then
    defaults write com.apple.Safari ShowFavoritesBar -bool false
    defaults write com.apple.Safari 'ShowFavoritesBar-v2' -bool false
  fi

  if ask "Hide Safari's sidebar in Top Sites" 'Y'; then
    defaults write com.apple.Safari ShowSidebarInTopSites -bool false
  fi

  if ask "Disable Safari's thumbnail cache for History and Top Sites" 'Y'; then
    defaults write com.apple.Safari DebugSnapshotsUpdatePolicy -int 2
  fi

  if ask "Enable Safari's debug menu" 'Y'; then
    defaults write com.apple.Safari IncludeInternalDebugMenu -bool true
  fi

  if ask "Make Safari's search banners default to Contains instead of Starts With" 'Y'; then
    defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly -bool false
  fi

  if ask "Remove useless icons from Safari's bookmarks bar" 'Y'; then
    defaults write com.apple.Safari ProxiesInBookmarksBar "()"
  fi

  if ask 'Warn about fraudulent websites' 'Y'; then
    defaults write com.apple.Safari WarnAboutFraudulentWebsites -bool true
  fi

  if ask 'Block pop-up windows' 'Y'; then
    defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool false
    defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically -bool false
  fi

  if ask 'Disable auto-playing video' 'Y'; then
    defaults write com.apple.Safari WebKitMediaPlaybackAllowsInline -bool false
    defaults write com.apple.SafariTechnologyPreview WebKitMediaPlaybackAllowsInline -bool false
    defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false
    defaults write com.apple.SafariTechnologyPreview com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false
  fi

  if ask "Enable 'Do Not Track'" 'Y'; then
    defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true
  fi

  if ask 'Enable the Develop menu and the Web Inspector in Safari' 'N'; then
    defaults write com.apple.Safari IncludeDevelopMenu -bool true
    defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
    defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
  fi

  if ask "Enable Safari's debug menu" 'Y'; then
    defaults write com.apple.Safari IncludeDebugMenu -bool true
  fi

  # Requires Safari 5.0.1 or later. Feature that is intended to increase the speed at which pages load. DNS (Domain Name System) prefetching kicks in when you load a webpage that contains links to other pages. As soon as the initial page is loaded, Safari 5.0.1 (or later) begins resolving the listed links' domain names to their IP addresses. Prefetching can occasionally result in 'slow performance, partially-loaded pages, or webpage 'cannot be found' messages.
  if ask 'Increase page load speed in Safari' 'Y'; then
    defaults write com.apple.safari WebKitDNSPrefetchingEnabled -bool true
  fi

  if ask 'Disable Data Detectors' 'Y'; then
    defaults write com.apple.Safari WebKitUsesEncodingDetector -bool false
  fi

  if ask 'Google Suggestion' 'Y'; then
    defaults write com.apple.safari DebugSafari4IncludeGoogleSuggest -bool true
  fi

  if ask 'Automatically spell check web forms' 'Y'; then
    defaults write com.apple.safari WebContinuousSpellCheckingEnabled -bool true
  fi

  if ask 'Automatically grammar check web forms' 'Y'; then
    defaults write com.apple.safari WebGrammarCheckingEnabled -bool true
  fi

  if ask 'Include page background colors and images when printing' 'N'; then
    defaults write com.apple.safari WebKitShouldPrintBackgroundsPreferenceKey -bool true
  fi

  # Disable plug-ins
  # defaults write com.apple.Safari WebKitPluginsEnabled -bool false
  # defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2PluginsEnabled -bool false

  # Disable Java
  # defaults write com.apple.Safari WebKitJavaEnabled -bool false
  # defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabled -bool false
  # defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaEnabledForLocalFiles -bool false

  # Block pop-up windows
  # defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool false
  # defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically -bool false

  # Disable auto-playing video
  #   defaults write com.apple.Safari WebKitMediaPlaybackAllowsInline -bool false
  #   defaults write com.apple.SafariTechnologyPreview WebKitMediaPlaybackAllowsInline -bool false
  #   defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false
  #   defaults write com.apple.SafariTechnologyPreview com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false

  # Update extensions automatically
  defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true

  # Mail
  if ask 'Display emails in threaded mode, sorted by date (oldest at the top)' 'Y'; then
    defaults write com.apple.mail DraftsViewerAttributes -dict-add 'DisplayInThreadedMode' -string 'yes'
    defaults write com.apple.mail DraftsViewerAttributes -dict-add 'SortedDescending' -string 'yes'
    defaults write com.apple.mail DraftsViewerAttributes -dict-add 'SortOrder' -string 'received-date'
  fi

  if ask 'Disable automatic spell checking' 'N'; then
    defaults write com.apple.mail SpellCheckingBehavior -string 'NoSpellCheckingEnabled'
  fi

  if ask "Copy email addresses as 'foo@example.com' instead of 'Foo Bar <foo@example.com>'' in Mail.app" 'N'; then
    defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false
  fi

  if ask 'Disable send and reply animations in Mail.app' 'N'; then
    defaults write com.apple.Mail DisableReplyAnimations -bool true
    defaults write com.apple.Mail DisableSendAnimations -bool true
  fi

  if ask 'Set a minimum font size of 14px (affects reading and sending email)' 'N'; then
    defaults write com.apple.mail MinimumHTMLFontSize 14
  fi

  if ask 'Force all Mail messages to display as plain text' 'N'; then
    # For rich text (the default) set it to FALSE
    defaults write com.apple.mail PreferPlainText -bool TRUE
  fi

  if ask 'Disable tracking of Previous Recipients' 'N'; then
    defaults write com.apple.mail SuppressAddressHistory -bool true
  fi

  if ask 'Send Windows friendly attachments' 'N'; then
    defaults write com.apple.mail SendWindowsFriendlyAttachments -bool true
  fi

  # Spotlight
  # Turning off since this causes the system settings pane to break.
  # if ask 'Disable Spotlight indexing for any volume that gets mounted and has not yet been indexed before.' 'Y'; then
  #   sudo defaults write /.Spotlight-V100/VolumeConfiguration Exclusions -array '/Volumes'
  # fi

  if ask 'Change indexing order and disable some search results' 'Y'; then
    defaults write com.apple.spotlight orderedItems -array \
      '{"enabled" = 1;"name" = "APPLICATIONS";}' \
      '{"enabled" = 1;"name" = "SYSTEM_PREFS";}' \
      '{"enabled" = 0;"name" = "DIRECTORIES";}' \
      '{"enabled" = 0;"name" = "PDF";}' \
      '{"enabled" = 0;"name" = "FONTS";}' \
      '{"enabled" = 0;"name" = "DOCUMENTS";}' \
      '{"enabled" = 0;"name" = "MESSAGES";}' \
      '{"enabled" = 0;"name" = "CONTACT";}' \
      '{"enabled" = 0;"name" = "EVENT_TODO";}' \
      '{"enabled" = 0;"name" = "IMAGES";}' \
      '{"enabled" = 0;"name" = "BOOKMARKS";}' \
      '{"enabled" = 0;"name" = "MUSIC";}' \
      '{"enabled" = 0;"name" = "MOVIES";}' \
      '{"enabled" = 0;"name" = "PRESENTATIONS";}' \
      '{"enabled" = 0;"name" = "SPREADSHEETS";}' \
      '{"enabled" = 1;"name" = "SOURCE";}' \
      '{"enabled" = 1;"name" = "MENU_DEFINITION";}' \
      '{"enabled" = 0;"name" = "MENU_OTHER";}' \
      '{"enabled" = 1;"name" = "MENU_CONVERSION";}' \
      '{"enabled" = 1;"name" = "MENU_EXPRESSION";}' \
      '{"enabled" = 0;"name" = "MENU_WEBSEARCH";}' \
      '{"enabled" = 0;"name" = "MENU_SPOTLIGHT_SUGGESTIONS";}'
  fi

  if ask 'Load new settings before rebuilding the index' 'Y'; then
    killall mds &>/dev/null
  fi

  # Terminal
  if ask 'Terminal.app settings' 'Y'; then
    defaults write com.apple.Terminal NewWindowWorkingDirectoryBehavior -int 2
    # (see: https://security.stackexchange.com/a/47786/8918)
    defaults write com.apple.Terminal SecureKeyboardEntry -bool false
    defaults write com.apple.Terminal Shell -string ''
    defaults write com.apple.Terminal 'Default Window Settings' -string 'Clear Dark'
    defaults write com.apple.Terminal 'Startup Window Settings' -string 'Clear Dark'

    # Disable the annoying line marks
    # defaults write com.apple.Terminal ShowLineMarks -int 0

    # Note: To print the values, use this:
    # /usr/libexec/PlistBuddy -c "Print :'Window Settings':'Clear Dark'" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
    local profile_array=('Clear Dark')
    for profile in "${profile_array[@]}"; do
      # Profile names may contain spaces; quote them in PlistBuddy paths using single quotes.
      # Delete before Add is idempotent: suppress errors when the entry doesn't exist yet.
      /usr/libexec/PlistBuddy -c "Delete :'Window Settings':'${profile}':rowCount" "${HOME}/Library/Preferences/com.apple.Terminal.plist" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':rowCount integer 30" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      /usr/libexec/PlistBuddy -c "Delete :'Window Settings':'${profile}':columnCount" "${HOME}/Library/Preferences/com.apple.Terminal.plist" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':columnCount integer 120" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      /usr/libexec/PlistBuddy -c "Delete :'Window Settings':'${profile}':shellExitAction" "${HOME}/Library/Preferences/com.apple.Terminal.plist" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':shellExitAction integer 1" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      /usr/libexec/PlistBuddy -c "Delete :'Window Settings':'${profile}':noWarnProcesses" "${HOME}/Library/Preferences/com.apple.Terminal.plist" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':noWarnProcesses array" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':noWarnProcesses:0:ProcessName string screen" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':noWarnProcesses:1:ProcessName string tmux" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':noWarnProcesses:2:ProcessName string rlogin" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':noWarnProcesses:3:ProcessName string ssh" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':noWarnProcesses:4:ProcessName string slogin" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':noWarnProcesses:5:ProcessName string telnet" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
    done
  fi

  # Focus follows Mouse
  # defaults write com.apple.Terminal FocusFollowsMouse -bool true

  # iTerm 2
  # TODO: Need to set the keyboard overrides for 'back/forward 1 word' AND 'Jobs to Ignore'
  if ask 'iTerm2 settings' 'Y'; then
    defaults write com.googlecode.iterm2 AllowClipboardAccess -bool true
    defaults write com.googlecode.iterm2 AppleAntiAliasingThreshold -bool true
    defaults write com.googlecode.iterm2 AppleScrollAnimationEnabled -bool false
    defaults write com.googlecode.iterm2 AppleSmoothFixedFontsSizeThreshold -bool true
    defaults write com.googlecode.iterm2 AppleWindowTabbingMode -string "manual"
    defaults write com.googlecode.iterm2 AutoCommandHistory -bool false
    defaults write com.googlecode.iterm2 CheckTestRelease -bool true
    defaults write com.googlecode.iterm2 DimBackgroundWindows -bool true
    defaults write com.googlecode.iterm2 HideTab -bool false
    defaults write com.googlecode.iterm2 HotkeyMigratedFromSingleToMulti -bool true
    defaults write com.googlecode.iterm2 IRMemory -int 4
    defaults write com.googlecode.iterm2 NSFontPanelAttributes -string "1, 0"
    defaults write com.googlecode.iterm2 NSNavLastRootDirectory -string "${HOME}/Desktop"
    defaults write com.googlecode.iterm2 NSQuotedKeystrokeBinding -string ""
    defaults write com.googlecode.iterm2 NSScrollAnimationEnabled -bool false
    defaults write com.googlecode.iterm2 NSScrollViewShouldScrollUnderTitlebar -bool false
    defaults write com.googlecode.iterm2 NoSyncCommandHistoryHasEverBeenUsed -bool true
    defaults write com.googlecode.iterm2 NoSyncDoNotWarnBeforeMultilinePaste -bool true
    defaults write com.googlecode.iterm2 NoSyncDoNotWarnBeforeMultilinePaste_selection -bool false
    defaults write com.googlecode.iterm2 NoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt -bool true
    defaults write com.googlecode.iterm2 NoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt_selection -bool true
    defaults write com.googlecode.iterm2 NoSyncHaveRequestedFullDiskAccess -bool true
    defaults write com.googlecode.iterm2 NoSyncHaveWarnedAboutPasteConfirmationChange -bool true
    defaults write com.googlecode.iterm2 NoSyncPermissionToShowTip -bool true
    defaults write com.googlecode.iterm2 NoSyncSuppressBroadcastInputWarning -bool true
    defaults write com.googlecode.iterm2 NoSyncSuppressBroadcastInputWarning_selection -bool false
    defaults write com.googlecode.iterm2 OnlyWhenMoreTabs -bool false
    defaults write com.googlecode.iterm2 OpenArrangementAtStartup -bool false
    defaults write com.googlecode.iterm2 OpenNoWindowsAtStartup -bool false
    defaults write com.googlecode.iterm2 PromptOnQuit -bool false
    defaults write com.googlecode.iterm2 SUAutomaticallyUpdate -bool true
    defaults write com.googlecode.iterm2 SUEnableAutomaticChecks -bool true
    defaults write com.googlecode.iterm2 SUFeedAlternateAppNameKey -string iTerm
    defaults write com.googlecode.iterm2 SUFeedURL -string 'https://iterm2.com/appcasts/final.xml?shard=69'
    defaults write com.googlecode.iterm2 SUHasLaunchedBefore -bool true
    defaults write com.googlecode.iterm2 SUUpdateRelaunchingMarker -bool false
    defaults write com.googlecode.iterm2 SavePasteHistory -bool false
    defaults write com.googlecode.iterm2 ShowBookmarkName -bool false
    defaults write com.googlecode.iterm2 SplitPaneDimmingAmount -string '0.4070612980769232'
    defaults write com.googlecode.iterm2 StatusBarPosition -integer 1
    defaults write com.googlecode.iterm2 SuppressRestartAnnouncement -bool true
    defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -integer 4
    defaults write com.googlecode.iterm2 TraditionalVisualBell -bool true
    defaults write com.googlecode.iterm2 UseBorder -bool true
    defaults write com.googlecode.iterm2 WordCharacters -string "/-+\\~-integer."
    defaults write com.googlecode.iterm2 findMode_iTerm -bool false
    defaults write com.googlecode.iterm2 kCPKSelectionViewPreferredModeKey -bool false
    defaults write com.googlecode.iterm2 kCPKSelectionViewShowHSBTextFieldsKey -bool false

    # TODO: Need to set up the font settings for font in iTerm2
    # TODO: Need to set up the 'Natural text editing' preset in Profiles > Keys preference pane for iTerm2
    # TODO: Need to set up the status bar layout and prefs in iTerm2

    # Note: To print the values, use this:
    # /usr/libexec/PlistBuddy -c "Print :'New Bookmarks':0:'Jobs to Ignore'" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    # Ensure the array exists; suppress error if it already does (idempotent).
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks' array" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:Rows" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:Rows integer 48" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:Columns" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:Columns integer 160" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Silence Bell'" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Silence Bell' bool false" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Unlimited Scrollback'" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Unlimited Scrollback' bool true" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Use Cursor Guide'" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Use Cursor Guide' bool true" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Visual Bell'" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Visual Bell' bool true" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Jobs to Ignore'" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore' array" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':0 string screen" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':1 string tmux" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':2 string rlogin" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':3 string ssh" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':4 string slogin" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':5 string telnet" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':5 string zsh" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Minimum Contrast'" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Minimum Contrast' integer 0" "${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
  fi

  # TODO: Need to add these - stopping due to time constraints
  # {
  #     'New Bookmarks' =     (
  #                 {
  #             // Same level as 'Jobs to Ignore'
  #             "Character Encoding" -integer 4;
  #             "Mouse Reporting" -integer 1;
  #             "Close Sessions On End" -bool true
  #             Command -string ""
  #             Description -string Default
  #             "Flashing Bell" -bool true
  #             "Idle Code" -bool false
  #             Name -string Default
  #             "Non Ascii Font" = "Monaco 12";
  #             "Non-ASCII Anti Aliased" = 1;
  #             "Normal Font" = "MenloForPowerline-Regular 14";
  #             "Option Key Sends" -integer 0
  #             "Prompt Before Closing 2" -integer 2
  #             "Right Option Key Sends" -integer 0
  #             Screen -string "-1"
  #             "Scrollback Lines" -integer 0
  #             "Send Code When Idle" -bool false
  #             "Show Status Bar" = 1;
  #             "Sync Title" -bool false
  #             Transparency -string "0.1610584549492386"
  #             "Use Bold Font" -bool true
  #             "Use Bright Bold" -bool true
  #             "Use Italic Font" -bool true
  #             "Use Non-ASCII Font" -bool false
  #             "Window Type" -integer 0
  #             "Working Directory" -string "${HOME}"
  #         }
  #     );
  # }

  # Hour - World Clock
  # TODO: Capture all settings

  # Firefox-nightly
  if ask 'Firefox settings' 'Y'; then
    defaults write -app 'Firefox Nightly' NSFullScreenMenuItemEverywhere -bool false
    defaults write -app 'Firefox Nightly' NSNavLastRootDirectory -string "${HOME}/Downloads"
    defaults write -app 'Firefox Nightly' NSNavLastUserSetHideExtensionButtonState -bool false
    defaults write -app 'Firefox Nightly' NSTreatUnknownArgumentsAsOpen -bool false
    defaults write -app 'Firefox Nightly' PMPrintingExpandedStateForPrint2 -bool false
  fi

  # Google Chrome & Google Chrome Canary
  if ask 'Chrome settings' 'Y'; then
    defaults write com.google.Chrome AppleEnableMouseSwipeNavigateWithScrolls -bool false
    defaults write com.google.Chrome AppleEnableSwipeNavigateWithScrolls -bool false
    defaults write com.google.Chrome.canary AppleEnableSwipeNavigateWithScrolls -bool false
    defaults write com.google.Chrome.canary AppleEnableMouseSwipeNavigateWithScrolls -bool false
    defaults write com.google.Chrome KeychainReauthorizeInAppSpring2017 -int 2
    defaults write com.google.Chrome KeychainReauthorizeInAppSpring2017Success -bool true

    # Allow installing user scripts via GitHub or Userscripts.org
    # defaults write com.google.Chrome ExtensionInstallSources -array 'https://*.github.com/*' 'http://userscripts.org/*'
    # defaults write com.google.Chrome.canary ExtensionInstallSources -array 'https://*.github.com/*' 'http://userscripts.org/*'
  fi

  # KeepassXC
  if ask 'KeepassXC settings' 'Y'; then
    defaults write org.keepassxc.keepassxc 'NSNavLastRootDirectory' -string "${HOME}/personal/${USER}"
  fi

  # Monolingual
  if ask 'Monolingual settings' 'Y'; then
    defaults write net.sourceforge.Monolingual SUAutomaticallyUpdate -bool true
    defaults write net.sourceforge.Monolingual SUEnableAutomaticChecks -bool true
    defaults write net.sourceforge.Monolingual SUSendProfileInfo -bool false
    defaults write net.sourceforge.Monolingual Strip -bool true
  fi

  # ProtonVpn
  if ask 'ProtonVpn settings' 'Y'; then
    defaults write ch.protonvpn.mac ConnectOnDemand -bool true
    defaults write ch.protonvpn.mac EarlyAccess -bool true
    defaults write ch.protonvpn.mac NSInitialToolTipDelay -int 500
    defaults write ch.protonvpn.mac RememberLoginAfterUpdate -bool true
    defaults write ch.protonvpn.mac SUAutomaticallyUpdate -bool true
    defaults write ch.protonvpn.mac SUEnableAutomaticChecks -bool false
    defaults write ch.protonvpn.mac SecureCoreToggle -bool false
    defaults write ch.protonvpn.mac StartMinimized -bool true
    defaults write ch.protonvpn.mac StartOnBoot -bool true
    defaults write ch.protonvpn.mac SystemNotifications -bool true
  fi

  # Thunderbird-beta
  if ask 'Thunderbird settings' 'Y'; then
    defaults write org.mozilla.thunderbird NSFullScreenMenuItemEverywhere -bool false
    defaults write org.mozilla.thunderbird NSTreatUnknownArgumentsAsOpen -bool false
  fi

  # Zoomus
  if ask 'Zoomus settings' 'Y'; then
    defaults write us.zoom.xos BounceApplicationSetting -int 2
    defaults write us.zoom.xos NSInitialToolTipDelay -int 100
    defaults write us.zoom.xos NSQuitAlwaysKeepsWindows -bool false
    defaults write us.zoom.xos kZPSettingShowCodeSnippet -bool true
    defaults write us.zoom.xos kZPSettingShowLinkPreview -bool true

    defaults write ZoomChat ZMEnableShowUserName -bool true
    defaults write ZoomChat ZoomAutoCopyInvitationURL -bool true
    defaults write ZoomChat ZoomEnableShow49WallViewKey -bool true
    defaults write ZoomChat ZoomEnterFullscreenWhenViewShare -bool false
    defaults write ZoomChat ZoomEnterMaxWndWhenViewShare -bool true
    defaults write ZoomChat ZoomFitDock -bool true
    defaults write ZoomChat ZoomFitXPos -int 727
    defaults write ZoomChat ZoomFitYPos -int 1023
    defaults write ZoomChat ZoomRememberPhoneKey -bool true
  fi

  # Activity Monitor

  if ask 'Show the main window when launching Activity Monitor' 'Y'; then
    defaults write com.apple.ActivityMonitor OpenMainWindow -bool true
  fi

  if ask 'Visualize CPU usage in the Dock icon' 'Y'; then
    defaults write com.apple.ActivityMonitor IconType -int 5
  fi

  if ask 'Show all processes hierarchically' 'Y'; then
    defaults write com.apple.ActivityMonitor ShowCategory -int 101
  fi

  if ask 'Sort Activity Monitor results by CPU usage' 'Y'; then
    defaults write com.apple.ActivityMonitor SortColumn -string 'CPUUsage'
    defaults write com.apple.ActivityMonitor SortDirection -int 0
  fi

  if ask 'Default to showing the Network tab' 'Y'; then
    defaults write com.apple.ActivityMonitor SelectedTab -int 4
  fi

  # Photos
  if ask 'Prevent Photos from opening automatically when devices are plugged in' 'Y'; then
    defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true
  fi

  # Messages
  # Disable automatic emoji substitution (i.e. use plain text smileys)
  # defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add 'automaticEmojiSubstitutionEnablediMessage' -bool false

  # Disable smart quotes as it's annoying for messages that contain code
  # defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add 'automaticQuoteSubstitutionEnabled' -bool false

  # Disable continuous spell checking
  # defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add 'continuousSpellCheckingEnabled' -bool false

  # Software Update
  if ask 'Automatically check for updates (required for any downloads)' 'Y'; then
    defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
  fi

  if ask 'Download updates automatically in the background' 'Y'; then
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
  fi

  if ask 'Install app updates automatically' 'Y'; then
    defaults write com.apple.commerce AutoUpdate -bool true
  fi

  if ask 'Install macos updates automatically' 'Y'; then
    defaults write com.apple.commerce AutoUpdateRestartRequired -bool true
  fi

  if ask 'Install system data file updates automatically' 'Y'; then
    defaults write com.apple.SoftwareUpdate ConfigDataInstall -bool true
  fi

  if ask 'Install critical security updates automatically' 'Y'; then
    defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -bool true
  fi

  if ask 'Check for software updates daily, not just once per week' 'Y'; then
    defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1
  fi

  # Mac App Store
  # Disable smart quotes as they're annoying when typing code
  # defaults write -g NSAutomaticQuoteSubstitutionEnabled -bool false

  # Disable smart dashes as they're annoying when typing code
  # defaults write -g NSAutomaticDashSubstitutionEnabled -bool false

  # Enable the WebKit Developer Tools in the Mac App Store
  defaults write com.apple.appstore WebKitDeveloperExtras -bool true

  # Enable Debug Menu in the Mac App Store
  defaults write com.apple.appstore ShowDebugMenu -bool true

  # Add a context menu item for showing the Web Inspector in web views
  defaults write -g WebKitDeveloperExtras -bool true

  # Time Machine
  # Prevent Time Machine from prompting to use new hard drives as backup volume
  defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

  # Disable local Time Machine backups
  # TODO: This causes an error to be printed to stdout - need to investigate if this is deprecated
  # hash tmutil 2> /dev/null && sudo tmutil disablelocal

  # Auto backup:
  # defaults write com.apple.TimeMachine AutoBackup =1

  # Backup frequency default= 3600 seconds (every hour) 1800 = 1/2 hour, 7200=2 hours
  # sudo defaults write /System/Library/Launch Daemons/com.apple.backupd-auto StartInterval -int 1800

  # Screen
  # Require password immediately after sleep or screen saver begins
  defaults write com.apple.screensaver askForPassword -bool true
  defaults write com.apple.screensaver askForPasswordDelay -int 0

  # Enable subpixel font rendering on non-Apple LCDs (0=off, 1=light, 2=Medium/flat panel, 3=strong/blurred)
  # This is mostly needed for non-Apple displays.
  defaults write -g AppleFontSmoothing -int 2

  # Enable HiDPI display modes (requires restart)
  sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true

  # Screen capture
  # Save screenshots to the desktop
  defaults write com.apple.screencapture location -string "${HOME}/Desktop"

  # Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)
  defaults write com.apple.screencapture type -string 'png'

  # Disable shadow in screenshots
  defaults write com.apple.screencapture disable-shadow -bool true

  # Screenshot thumbnail expires in 15 secs
  defaults write com.apple.screencaptureui thumbnailExpiration -float 15

  # iCal
  # Log HTTP Activity:
  # defaults write com.apple.iCal LogHTTPActivity -bool true

  # Address Book

  # Show Contact Reflection:
  # defaults write com.apple.AddressBook reflection -boolean
  # com.apple.AddressBook is sandbox-restricted on modern macOS; writes fail with
  # "Could not write domain" even as the file owner. Suppress the error — the
  # settings are effectively read-only via this path on current OS versions.
  defaults write com.apple.AddressBook ABBirthDayVisible -bool true 2>/dev/null || true
  defaults write com.apple.AddressBook ABDefaultAddressCountryCode -string in 2>/dev/null || true

  # iTunes 10
  # Make the arrows next to artist & album jump to local iTunes library folders instead of Store:
  # defaults write com.apple.iTunes show-store-link-arrows -bool true
  # defaults write com.apple.iTunes invertStoreLinks -bool true

  # Restore the standard close/minimise buttons:
  # defaults write com.apple.iTunes full-window -1

  # Hide the iTunes Genre list:
  # defaults write com.apple.iTunes show-genre-when-browsing -bool false

  # OmniGraffle
  # Allow scroll wheel zooming:
  # defaults write com.omnigroup.OmniGraffle DisableScrollWheelZooming -bool false

  # Allow scroll wheel zooming in OmniGrafflePro:
  # defaults write com.omnigroup.OmniGrafflePro DisableScrollWheelZooming -bool false

  # Quick Time Player
  # Automatically show Closed Captions (CC) when opening a Movie:
  # defaults -currentHost write com.apple.QuickTimePlayerX.plist MGEnableCCAndSubtitlesOnOpen -boolean

  # Spaces
  # When switching applications, switch to respective space
  defaults write -g AppleSpacesSwitchOnActivate -bool true

  # Kill affected applications
  local app_array=(
    'Activity Monitor'
    'Address Book'
    'Calendar'
    'cfprefsd'
    'Contacts'
    'Dock'
    'Finder'
    'Google Chrome Beta'
    'Google Chrome Canary'
    'Google Chrome'
    'iCal'
    'Mail'
    'Safari'
    'SizeUp'
    'SystemUIServer'
  )
  for app in "${app_array[@]}"; do
    killall "${app}" &>/dev/null
  done

  sudo softwareupdate --schedule ON

  # Turn off spotlight indexing for all volumes (to pre-empt any issues with the system settings pane)
  sudo mdutil -Eda &>/dev/null  && sudo mdutil -ai off &>/dev/null

  warn "Need to manually quit and restart 'Terminal' and 'iTerm' - since one of these might be running this script."
  success 'Done. Note that some of these changes require a logout/restart to take effect.'
}

main "$@"
