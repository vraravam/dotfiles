#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# Sets macOS system and application preferences via 'defaults write'.
# Run with -s to seed a baseline on a fresh machine; run with -i to import
# preferences on top of that baseline (see osx-defaults.sh -h for full usage).
# Originally inspired by: https://gist.github.com/DAddYE/2108403

# set -euo pipefail is intentionally omitted: many 'defaults write' and 'killall'
# calls return non-zero when a setting is unsupported on the current OS version,
# which is expected and must not abort the script.

# This script handles settings that cannot be managed by capture-prefs.sh alone,
# or that require mechanisms other than a plain 'defaults write':
#   - sudo / pmset / systemsetup / scutil calls
#   - defaults -currentHost writes (host-specific pref domain)
#   - PlistBuddy nested plist edits (Terminal/iTerm2 profiles, Finder icon view,
#     Spotlight symbolic hotkeys)
#   - defaults -dict-add patterns (Mail DraftsViewerAttributes,
#     Finder FXInfoPanesExpanded)
#   - com.apple.AddressBook (sandbox-restricted; writes suppressed with || true)
#   - Firefox / Zen Browser user.js file writes
#   - Interactive ask-N settings (intentionally left to user choice)

_SCRIPT_NAME="${0:t}"
source "${HOME}/.aliases"

usage() {
  print_usage "${_SCRIPT_NAME}" \
    "$(yellow '[-s]') --> $(purple '-s') (optional) Run in silent/auto mode without interactive prompts"
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

# Writes a trackpad gesture setting to both Bluetooth and built-in trackpad domains.
# Bluetooth trackpad (com.apple.driver.AppleBluetoothMultitouch.trackpad) and
# built-in trackpad (com.apple.AppleMultitouchTrackpad) share the same gesture
# keys -- both domains must be written to keep wired and wireless behaviour in sync.
#
# Arguments:
#   $1 - key name (e.g., 'Clicking', 'TrackpadPinch')
#   $2 - value to write
#   $3 - type flag (default: -int), can be -bool, -string, etc.
_set_trackpad_gesture() {
  local key="${1:?_set_trackpad_gesture: key required}"
  local value="${2:?_set_trackpad_gesture: value required}"
  local type="${3:--int}"
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad "${key}" "${type}" "${value}"
  defaults write com.apple.AppleMultitouchTrackpad "${key}" "${type}" "${value}"
}

main() {
  auto='N'
  local _current_section='(init)'
  local -a _step_warnings=()
  local -a _step_errors=()
  export _DOTFILES_SCRIPT_DEPTH=$((${_DOTFILES_SCRIPT_DEPTH:-0} + 1))
  # Minimal trap ensures depth is restored on early-return paths (arg-parse failure,
  # non-TTY check) before kill_login_item_apps and the full EXIT trap are registered.
  trap '_decrement_script_depth' EXIT
  while getopts ':s' opt; do
    case ${opt} in
      s)
        debug 'Running in silent mode...'
        auto='Y'
        ;;
      \?)
        warn "-${OPTARG} is not a valid option"
        usage
        return 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if [[ "${auto}" == 'N' ]] && ! is_running_in_tty; then
    _record_error 'Interactive mode needs terminal!'
    print_script_summary
    return 1
  fi

  # Ask for the administrator password upfront and keep it alive until this script has finished
  keep_sudo_alive

  # Close any open System Preferences panes, to prevent them from overriding
  # settings we're about to change
  osascript -e 'tell application "System Preferences" to quit'

  # Login-item apps are killed upfront (SIGTERM -- graceful shutdown) so their
  # running instance cannot overwrite our defaults writes when it quits.
  # The EXIT trap restarts them on any exit path (normal or error), ensuring
  # the user is never left with login-item apps dead.
  # Only apps explicitly set as login items are handled here; apps that cannot
  # be safely force-quit (Terminal, iTerm, Zoom, ProtonVPN) are left to the
  # user_action prompts at the end.
  # The canonical app list lives in _MACOS_LOGIN_ITEM_APPS (.aliases § 3n).
  kill_login_item_apps
  trap 'restart_login_item_apps; resume_softwareupdate_schedule; _decrement_script_depth' EXIT

  # Suspend the automatic software update schedule while writing defaults so
  # background update activity cannot conflict with the defaults system cache.
  # resume_softwareupdate_schedule is called from the EXIT trap above, covering
  # both normal and error exits. Both functions guard with sudo -n (no prompt).
  suspend_softwareupdate_schedule

  # ---------------------------------------------------------------------------
  # Login Window
  # ---------------------------------------------------------------------------

  if ask 'Disable guest login' 'Y'; then
    sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
  fi

  # ---------------------------------------------------------------------------
  # Menu Bar
  # ---------------------------------------------------------------------------

  # System Settings > Control Center > Menu Bar Only items
  # Bluetooth = on
  defaults write com.apple.controlcenter 'NSStatusItem Visible Bluetooth' 1
  # WiFi = on
  defaults write com.apple.controlcenter 'NSStatusItem Visible WiFi' -bool true
  # Battery = off
  defaults write com.apple.controlcenter 'NSStatusItem Visible Battery' 0
  # Clock = off (use a dedicated clock app such as Clocker instead)
  defaults write com.apple.controlcenter 'NSStatusItem VisibleCC Clock' -bool false
  # Spotlight = off (use Sol instead)
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

  # Keep keyboard brightness at maximum via -currentHost write; cannot be
  # expressed as a plain defaults write (host-specific pref domain).
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

  # ---------------------------------------------------------------------------
  # General UI/UX
  # ---------------------------------------------------------------------------

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

  # dontAutoLoad must be written to the ByHost preference file (identified by
  # hardware UUID) -- not to the regular com.apple.systemuiserver domain. The
  # ByHost path is what SystemUIServer reads on startup to skip certain menu
  # extras regardless of which user is logged in.
  local domain
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
    # Suppress error when the key doesn't exist -- delete is a no-op in that case.
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

  # ---------------------------------------------------------------------------
  # TextEdit
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # SSD-specific tweaks
  # ---------------------------------------------------------------------------

  if ask 'Disable hibernation (speeds up entering sleep mode)' 'Y'; then
    sudo pmset -a hibernatemode 0
  fi

  if ask "Disable the sudden motion sensor (not useful for SSDs)" 'Y'; then
    sudo pmset -a sms 0
  fi

  # ---------------------------------------------------------------------------
  # Trackpad, mouse, keyboard, Bluetooth accessories, and input
  # ---------------------------------------------------------------------------

  if ask 'Enable trackpad gestures (tap-to-click, three-finger drag, etc.)' 'Y'; then
    # Settings shared between Bluetooth and built-in trackpads
    _set_trackpad_gesture Clicking 1
    _set_trackpad_gesture DragLock 0
    _set_trackpad_gesture Dragging 0
    _set_trackpad_gesture TrackpadCornerSecondaryClick 0
    _set_trackpad_gesture TrackpadFiveFingerPinchGesture 2
    _set_trackpad_gesture TrackpadFourFingerHorizSwipeGesture 2
    _set_trackpad_gesture TrackpadFourFingerPinchGesture 2
    _set_trackpad_gesture TrackpadFourFingerVertSwipeGesture 2
    _set_trackpad_gesture TrackpadHandResting 1
    _set_trackpad_gesture TrackpadHorizScroll 1
    _set_trackpad_gesture TrackpadMomentumScroll 1
    _set_trackpad_gesture TrackpadPinch 1
    _set_trackpad_gesture TrackpadRightClick 1
    _set_trackpad_gesture TrackpadRotate 1
    _set_trackpad_gesture TrackpadScroll 1
    _set_trackpad_gesture TrackpadThreeFingerDrag 0
    _set_trackpad_gesture TrackpadThreeFingerHorizSwipeGesture 2
    _set_trackpad_gesture TrackpadThreeFingerVertSwipeGesture 2
    _set_trackpad_gesture TrackpadTwoFingerDoubleTapGesture 1
    _set_trackpad_gesture TrackpadTwoFingerFromRightEdgeSwipeGesture 3
    _set_trackpad_gesture USBMouseStopsTrackpad 0
    _set_trackpad_gesture UserPreferences 1

    # Built-in trackpad-only settings (not applicable to Bluetooth trackpad)
    defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
    defaults write com.apple.AppleMultitouchTrackpad FirstClickThreshold -int 1
    defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -int 0
    defaults write com.apple.AppleMultitouchTrackpad SecondClickThreshold -int 1
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 2

    # System Settings > Trackpad > Tap to click: this host-level key is what the
    # Settings UI reads to show the toggle state. All three writes are required:
    # the helper writes above configure the hardware drivers; this one tells
    # the UI the user has enabled tap-to-click.
    defaults -currentHost write -g com.apple.mouse.tapBehavior -int 1
  fi

  # ---------------------------------------------------------------------------
  # Apple Multitouch Mouse
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Finder
  # ---------------------------------------------------------------------------

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
  # Default view style: clmv=column, icnv=icon, Nlsv=list, glyv=gallery.
  defaults write com.apple.finder FXPreferredViewStyle -string 'clmv'
  defaults write com.apple.finder WarnOnEmptyTrash -bool false
  defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true
  defaults write com.apple.finder RestoreWindowState -bool true

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

  # if ask 'Disable window animations' 'N'; then
  #   defaults write -g NSAutomaticWindowAnimationsEnabled -bool false && killall Finder
  #fi

  # Avoiding the creation of .DS_Store files on network volumes
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

  # ---------------------------------------------------------------------------
  # Energy saving
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Keychain
  # ---------------------------------------------------------------------------
  if ask 'Keychain shows expired certificates' 'Y'; then
    defaults write com.apple.keychainaccess 'Show Expired Certificates' -bool true
  fi

  if ask 'Makes Keychain Access display *unsigned* ACL entries in italics' 'Y'; then
    defaults write com.apple.keychainaccess 'Distinguish Legacy ACLs' -bool true
  fi

  # ---------------------------------------------------------------------------
  # Remote Desktop
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Screen Sharing
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Dock, Dashboard, and hot corners
  # ---------------------------------------------------------------------------

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

  if ask 'Show image for notifications' 'Y'; then
    defaults write com.apple.dock 'notification-always-show-image' -bool true
  fi

  if ask 'Enable Bouncing dock icons' 'Y'; then
    defaults write com.apple.dock 'no-bouncing' -bool false
  fi

  if ask 'Remove the animation when hiding or showing the dock' 'Y'; then
    defaults write com.apple.dock 'autohide-time-modifier' -float 0
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

  # ---------------------------------------------------------------------------
  # Launchpad
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Safari & WebKit
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Mail
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Spotlight
  # ---------------------------------------------------------------------------
  # Initial default seeded here. The user may enable/disable categories via
  # System Settings > Spotlight afterward -- re-running osx-defaults.sh will
  # reset them.

  if ask 'Configure Spotlight search category ordering' 'Y'; then
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

  # Keyboard Shortcuts > Spotlight: disable "Show Spotlight search" (Cmd+Space).
  # Key 64 in AppleSymbolicHotKeys controls this shortcut. Disabling it prevents
  # Spotlight from stealing Cmd+Space, which is typically reassigned to another launcher.
  if ask 'Disable Spotlight keyboard shortcut (Cmd+Space)' 'Y'; then
    /usr/libexec/PlistBuddy \
      -c 'Set :AppleSymbolicHotKeys:64:enabled false' \
      "${HOME}/Library/Preferences/com.apple.symbolichotkeys.plist" 2>/dev/null ||
      /usr/libexec/PlistBuddy \
        -c 'Add :AppleSymbolicHotKeys:64:enabled bool false' \
        "${HOME}/Library/Preferences/com.apple.symbolichotkeys.plist"
  fi

  # Keyboard Shortcuts > Spotlight: disable "Show Finder search window" (Cmd+Option+Space).
  # Key 65 in AppleSymbolicHotKeys controls this shortcut.
  if ask 'Disable Spotlight Finder search window keyboard shortcut (Cmd+Option+Space)' 'Y'; then
    /usr/libexec/PlistBuddy \
      -c 'Set :AppleSymbolicHotKeys:65:enabled false' \
      "${HOME}/Library/Preferences/com.apple.symbolichotkeys.plist" 2>/dev/null ||
      /usr/libexec/PlistBuddy \
        -c 'Add :AppleSymbolicHotKeys:65:enabled bool false' \
        "${HOME}/Library/Preferences/com.apple.symbolichotkeys.plist"
  fi

  # ---------------------------------------------------------------------------
  # Terminal
  # ---------------------------------------------------------------------------

  if ask 'Terminal.app settings' 'Y'; then
    # Top-level Terminal.app defaults -- initial defaults seeded here so the user
    # can change them via the UI afterward without osx-defaults.sh resetting them.
    defaults write com.apple.Terminal NewWindowWorkingDirectoryBehavior -int 2
    defaults write com.apple.Terminal SecureKeyboardEntry -bool false
    defaults write com.apple.Terminal Shell -string ''
    defaults write com.apple.Terminal 'Default Window Settings' -string 'Clear Dark'
    defaults write com.apple.Terminal 'Startup Window Settings' -string 'Clear Dark'
    #
    # Note: To print the values, use this:
    # /usr/libexec/PlistBuddy -c "Print :'Window Settings':'Clear Dark'" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
    local profile_array=('Clear Dark')
    local profile
    for profile in "${profile_array[@]}"; do
      # Profile names may contain spaces; quote them in PlistBuddy paths using single quotes.
      # Delete before Add is idempotent: suppress errors when the entry doesn't exist yet.
      /usr/libexec/PlistBuddy -c "Delete :'Window Settings':'${profile}':rowCount" "${HOME}/Library/Preferences/com.apple.Terminal.plist" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':rowCount integer 30" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      /usr/libexec/PlistBuddy -c "Delete :'Window Settings':'${profile}':columnCount" "${HOME}/Library/Preferences/com.apple.Terminal.plist" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':columnCount integer 120" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      # Profiles > Text > Font. Terminal stores Font as NSArchiver binary data, so osascript is used
      # instead of PlistBuddy -- it sets font name/size as first-class properties on the settings set.
      # PostScript name: MesloLGSNF-Italic (from MesloLGS Nerd Font Italic).
      osascript -e "tell application \"Terminal\" to set font name of settings set \"${profile}\" to \"MesloLGSNF-Italic\""
      osascript -e "tell application \"Terminal\" to set font size of settings set \"${profile}\" to 13"
      # Profiles > Keyboard > "Use Option as Meta key": makes Option+B/F send \033b/\033f for readline
      # word navigation. Option+arrow keys still send \033[1;9D/C -- those need bindkey in .zshrc.
      /usr/libexec/PlistBuddy -c "Delete :'Window Settings':'${profile}':useOptionAsMetaKey" "${HOME}/Library/Preferences/com.apple.Terminal.plist" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :'Window Settings':'${profile}':useOptionAsMetaKey bool true" "${HOME}/Library/Preferences/com.apple.Terminal.plist"
      # Profiles > Shell > "When the shell exits": 0=don't close, 1=close if exited cleanly, 2=always close.
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

  # ---------------------------------------------------------------------------
  # iTerm2
  # ---------------------------------------------------------------------------

  # TODO: Need to set the keyboard overrides for 'back/forward 1 word' AND 'Jobs to Ignore'
  if ask 'iTerm2 settings' 'Y'; then
    defaults write com.googlecode.iterm2 AllowClipboardAccess -bool true
    # Enables alternate scrolling (scroll wheel scrolls in alt-screen apps like less/man).
    defaults write com.googlecode.iterm2 AlternateMouseScroll -bool true
    defaults write com.googlecode.iterm2 AppleAntiAliasingThreshold -bool true
    # Disables press-and-hold for accent characters; enables key repeat instead.
    defaults write com.googlecode.iterm2 ApplePressAndHoldEnabled -bool false
    defaults write com.googlecode.iterm2 AppleScrollAnimationEnabled -bool false
    defaults write com.googlecode.iterm2 AppleSmoothFixedFontsSizeThreshold -bool true
    defaults write com.googlecode.iterm2 AppleWindowTabbingMode -string 'manual'
    defaults write com.googlecode.iterm2 AutoCommandHistory -bool false
    defaults write com.googlecode.iterm2 CheckTestRelease -bool true
    # Copies trailing newline when selecting to end of line.
    defaults write com.googlecode.iterm2 CopyLastNewline -bool true
    defaults write com.googlecode.iterm2 DefaultTabBarHeight -float 28
    defaults write com.googlecode.iterm2 DimBackgroundWindows -bool true
    defaults write com.googlecode.iterm2 DisableTmuxWindowResizing -bool false
    defaults write com.googlecode.iterm2 DisableWindowSizeSnap -bool false
    defaults write com.googlecode.iterm2 DoubleClickPerformsSmartSelection -bool true
    # Enables the Python API server for shell integration and scripts.
    defaults write com.googlecode.iterm2 EnableAPIServer -bool true
    # Shows tab bar briefly when entering full-screen.
    defaults write com.googlecode.iterm2 FlashTabBarInFullscreen -bool true
    defaults write com.googlecode.iterm2 HapticFeedbackForEsc -bool false
    defaults write com.googlecode.iterm2 HideTab -bool false
    defaults write com.googlecode.iterm2 IRMemory -int 4
    # Prefs are stored locally (not in a custom folder or cloud-synced path).
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool false
    defaults write com.googlecode.iterm2 NSAutoFillHeuristicControllerEnabled -bool false
    defaults write com.googlecode.iterm2 NSFontPanelAttributes -string "1, 0"
    defaults write com.googlecode.iterm2 NSNavLastRootDirectory -string "${HOME}/Desktop"
    defaults write com.googlecode.iterm2 NSOverlayScrollersFallBackForAccessoryViews -bool false
    defaults write com.googlecode.iterm2 NSQuotedKeystrokeBinding -string ""
    defaults write com.googlecode.iterm2 NSRepeatCountBinding -string ""
    defaults write com.googlecode.iterm2 NSScrollAnimationEnabled -bool false
    defaults write com.googlecode.iterm2 NSScrollViewShouldScrollUnderTitlebar -bool false
    # NoSync keys: suppress one-time dialogs, warnings, and migration markers so
    # a fresh install does not show prompts that have already been acknowledged.
    defaults write com.googlecode.iterm2 NoSyncBrowserUpsell -bool true
    defaults write com.googlecode.iterm2 NoSyncBrowserUpsell_selection -int 1
    defaults write com.googlecode.iterm2 NoSyncClaudeCodeDiffModeBackfilled -bool true
    defaults write com.googlecode.iterm2 NoSyncClaudeCodeReviewSystemPromptCommandBackfilled -bool true
    defaults write com.googlecode.iterm2 NoSyncClearAllBroadcast -bool true
    defaults write com.googlecode.iterm2 NoSyncClearAllBroadcast_selection -int 0
    defaults write com.googlecode.iterm2 NoSyncCommandHistoryHasEverBeenUsed -bool true
    defaults write com.googlecode.iterm2 NoSyncConfirmRunOpenFile -bool true
    defaults write com.googlecode.iterm2 NoSyncConfirmRunOpenFile_selection -int 0
    defaults write com.googlecode.iterm2 NoSyncDoNotWarnBeforeMultilinePaste -bool true
    defaults write com.googlecode.iterm2 NoSyncDoNotWarnBeforeMultilinePaste_selection -bool false
    defaults write com.googlecode.iterm2 NoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt -bool true
    defaults write com.googlecode.iterm2 NoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt_selection -bool true
    defaults write com.googlecode.iterm2 NoSyncEnableAPIServer -bool true
    defaults write com.googlecode.iterm2 NoSyncEnableAPIServer_selection -int 0
    defaults write com.googlecode.iterm2 NoSyncHaveRequestedFullDiskAccess -bool true
    defaults write com.googlecode.iterm2 NoSyncHaveUsedCopyMode -bool true
    defaults write com.googlecode.iterm2 NoSyncHaveWarnedAboutPasteConfirmationChange -bool true
    defaults write com.googlecode.iterm2 NoSyncIgnoreSystemWindowRestoration -bool true
    defaults write com.googlecode.iterm2 NoSyncKeyCode0MitigationDisabled_Global -bool true
    defaults write com.googlecode.iterm2 NoSyncMigratedDynamicProfileTagToFlag -bool true
    defaults write com.googlecode.iterm2 NoSyncNeverRemindPrefsChangesLostForFile -bool true
    defaults write com.googlecode.iterm2 NoSyncNeverRemindPrefsChangesLostForFile_selection -int 1
    defaults write com.googlecode.iterm2 NoSyncOnboardingWindowHasBeenShown -bool true
    defaults write com.googlecode.iterm2 NoSyncOnboardingWindowHasBeenShown34 -bool true
    defaults write com.googlecode.iterm2 NoSyncOpenLinksInApp -bool true
    defaults write com.googlecode.iterm2 NoSyncOpenLinksInApp_selection -int 0
    defaults write com.googlecode.iterm2 NoSyncPermissionToShowTip -bool true
    defaults write com.googlecode.iterm2 NoSyncRemoveDeprecatedKeyMappings -int 2
    defaults write com.googlecode.iterm2 NoSyncRestoreIconAndWindowNameOnHostChange -bool true
    defaults write com.googlecode.iterm2 NoSyncSuppressBadPWDInArrangementWarning -bool true
    defaults write com.googlecode.iterm2 NoSyncSuppressBroadcastInputWarning -bool true
    defaults write com.googlecode.iterm2 NoSyncSuppressBroadcastInputWarning_selection -bool false
    defaults write com.googlecode.iterm2 NoSyncSuppressMissingProfileInArrangementWarning -bool true
    defaults write com.googlecode.iterm2 NoSyncTipsDisabled -bool true
    defaults write com.googlecode.iterm2 NoSyncUserHasSelectedCommand -bool true
    defaults write com.googlecode.iterm2 NoSyncWindowRestoresWorkspaceAtLaunch -bool false
    defaults write com.googlecode.iterm2 NoSyncWorkgroupShortcutsBackfilled -bool true
    defaults write com.googlecode.iterm2 OnlyWhenMoreTabs -bool false
    defaults write com.googlecode.iterm2 OpenArrangementAtStartup -bool false
    defaults write com.googlecode.iterm2 OpenBookmark -bool false
    defaults write com.googlecode.iterm2 OpenNoWindowsAtStartup -bool false
    # 0 = open tmux windows in tabs of the current window.
    defaults write com.googlecode.iterm2 OpenTmuxWindowsIn -int 0
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string ""
    defaults write com.googlecode.iterm2 PreserveWindowSizeWhenTabBarVisibilityChanges -bool false
    defaults write com.googlecode.iterm2 PreventEscapeSequenceFromClearingHistory -bool false
    defaults write com.googlecode.iterm2 'Print In Black And White' -bool true
    defaults write com.googlecode.iterm2 PromptOnQuit -bool false
    defaults write com.googlecode.iterm2 SUAutomaticallyUpdate -bool true
    defaults write com.googlecode.iterm2 SUEnableAutomaticChecks -bool true
    defaults write com.googlecode.iterm2 SUFeedAlternateAppNameKey -string iTerm
    defaults write com.googlecode.iterm2 SUFeedURL -string 'https://iterm2.com/appcasts/final.xml?shard=69'
    defaults write com.googlecode.iterm2 SUHasLaunchedBefore -bool true
    defaults write com.googlecode.iterm2 SUSendProfileInfo -bool false
    defaults write com.googlecode.iterm2 SUUpdateRelaunchingMarker -bool false
    defaults write com.googlecode.iterm2 SavePasteHistory -bool false
    # Each pane gets its own status bar rather than one shared bar per window.
    defaults write com.googlecode.iterm2 SeparateStatusBarsPerPane -bool false
    defaults write com.googlecode.iterm2 ShowBookmarkName -bool false
    defaults write com.googlecode.iterm2 ShowFullScreenTabBar -bool true
    defaults write com.googlecode.iterm2 ShowPaneTitles -bool true
    defaults write com.googlecode.iterm2 SoundForEsc -bool false
    defaults write com.googlecode.iterm2 SplitPaneDimmingAmount -string '0.4070612980769232'
    defaults write com.googlecode.iterm2 StartDebugLoggingAutomatically -bool false
    # 1 = status bar at bottom of terminal (not top).
    defaults write com.googlecode.iterm2 StatusBarPosition -integer 1
    defaults write com.googlecode.iterm2 StretchTabsToFillBar -bool true
    defaults write com.googlecode.iterm2 SuppressRestartAnnouncement -bool true
    # 1 = use Option key to switch panes.
    defaults write com.googlecode.iterm2 SwitchPaneModifier -int 1
    # 4 = minimal tab style (auto-adapts to light/dark mode).
    defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -integer 4
    defaults write com.googlecode.iterm2 TraditionalVisualBell -bool true
    defaults write com.googlecode.iterm2 UseBorder -bool true
    defaults write com.googlecode.iterm2 VisualIndicatorForEsc -bool false
    defaults write com.googlecode.iterm2 WordCharacters -string "/-+\\~-integer."
    # 2 = regex find mode (not case-insensitive plain text = 0, or smart case = 1).
    defaults write com.googlecode.iterm2 findMode_iTerm -int 2
    defaults write com.googlecode.iterm2 kCPKSelectionViewPreferredModeKey -bool false
    defaults write com.googlecode.iterm2 kCPKSelectionViewShowHSBTextFieldsKey -bool false

    # All PlistBuddy calls in this block write to the same plist; capture path once.
    local _iterm_plist="${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    # Profiles > Text > Font. Stored as "PostScriptName Size" plain string -- no binary encoding needed.
    # PostScript name: MesloLGSNF-Italic (from MesloLGS Nerd Font Italic).
    /usr/libexec/PlistBuddy -c "Set :'New Bookmarks':0:'Normal Font' 'MesloLGSNF-Italic 13'" "${_iterm_plist}"
    # Profiles > General > Command > Login shell. The 'Custom Command' key defaults to 'Custom Shell'
    # on a fresh iTerm2 install; 'No' means "Login shell", which is required for .zlogin to run on
    # every new window/tab and for the full zsh startup sequence to execute correctly.
    /usr/libexec/PlistBuddy -c "Set :'New Bookmarks':0:'Custom Command' 'No'" "${_iterm_plist}"
    # Profiles > Keys > Key Bindings > Presets > Natural Text Editing.
    # Action 10 = send escape sequence; Action 11 = send hex code.
    # Key format: hex-keycode-modifierflags (0x80000=Option, 0x100000=Cmd, 0x280000=Option+Shift(?), 0x300000=Ctrl+Shift(?)).
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Keyboard Map'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map' dict" "${_iterm_plist}"
    # Cmd+Delete → send Ctrl+U (delete to beginning of line)
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x100000' dict" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x100000':Action integer 11" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x100000':Text string '0x15'" "${_iterm_plist}"
    # Option+Delete → send Esc+Backspace (delete word backward)
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x80000' dict" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x80000':Action integer 11" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x80000':Text string '0x1b 0x7f'" "${_iterm_plist}"
    # Option+Left → send Esc+b (move back one word)
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f702-0x280000' dict" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f702-0x280000':Action integer 10" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f702-0x280000':Text string b" "${_iterm_plist}"
    # Ctrl+Left → send Ctrl+A (move to beginning of line)
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f702-0x300000' dict" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f702-0x300000':Action integer 11" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f702-0x300000':Text string '0x1'" "${_iterm_plist}"
    # Option+Right → send Esc+f (move forward one word)
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f703-0x280000' dict" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f703-0x280000':Action integer 10" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f703-0x280000':Text string f" "${_iterm_plist}"
    # Ctrl+Right → send Ctrl+E (move to end of line)
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f703-0x300000' dict" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f703-0x300000':Action integer 11" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f703-0x300000':Text string '0x5'" "${_iterm_plist}"
    # Forward Delete → send Ctrl+D (delete character under cursor)
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f728-0x0' dict" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f728-0x0':Action integer 11" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f728-0x0':Text string '0x4'" "${_iterm_plist}"
    # Option+Forward Delete → send Esc+d (delete word forward)
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f728-0x80000' dict" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f728-0x80000':Action integer 10" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Keyboard Map':'f728-0x80000':Text string d" "${_iterm_plist}"

    # Note: To print the values, use this:
    # /usr/libexec/PlistBuddy -c "Print :'New Bookmarks':0:'Jobs to Ignore'" "${_iterm_plist}"
    # Ensure the array exists; suppress error if it already does (idempotent).
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks' array" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:Rows" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:Rows integer 48" "${_iterm_plist}"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:Columns" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:Columns integer 160" "${_iterm_plist}"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Silence Bell'" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Silence Bell' bool false" "${_iterm_plist}"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Unlimited Scrollback'" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Unlimited Scrollback' bool true" "${_iterm_plist}"

    # Profiles > General > Initial directory: 'Recycle' = reuse previous session's directory.
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Custom Directory'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Custom Directory' string 'Recycle'" "${_iterm_plist}"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Enable Progress Bars'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Enable Progress Bars' bool true" "${_iterm_plist}"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Show Status Bar'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Show Status Bar' bool true" "${_iterm_plist}"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Use Cursor Guide'" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Use Cursor Guide' bool true" "${_iterm_plist}"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Visual Bell'" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Visual Bell' bool true" "${_iterm_plist}"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Jobs to Ignore'" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore' array" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':0 string screen" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':1 string tmux" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':2 string rlogin" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':3 string ssh" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':4 string slogin" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':5 string telnet" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':5 string zsh" "${_iterm_plist}"

    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Minimum Contrast'" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Minimum Contrast' integer 0" "${_iterm_plist}"

    # Profiles > Text
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'ASCII Anti Aliased'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'ASCII Anti Aliased' bool true" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Allow Title Setting'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Allow Title Setting' bool true" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Ambiguous Double Width'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Ambiguous Double Width' bool false" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Background Image Location'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Background Image Location' string ''" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Blinking Cursor'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Blinking Cursor' bool false" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Blur'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Blur' bool false" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Draw Powerline Glyphs'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Draw Powerline Glyphs' bool true" "${_iterm_plist}"
    # Horizontal and Vertical Spacing: multipliers relative to font's natural spacing (1.0 = default).
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Horizontal Spacing'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Horizontal Spacing' real 1" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Non Ascii Font'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Non Ascii Font' string 'Monaco 12'" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Non-ASCII Anti Aliased'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Non-ASCII Anti Aliased' bool true" "${_iterm_plist}"
    # Keeps background color opaque when transparency > 0; only cursor/text area is affected.
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Only The Default BG Color Uses Transparency'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Only The Default BG Color Uses Transparency' bool true" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Transparency'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Transparency' real 0" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Use Bold Font'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Use Bold Font' bool true" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Use Bright Bold'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Use Bright Bold' bool true" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Use Italic Font'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Use Italic Font' bool true" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Use Non-ASCII Font'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Use Non-ASCII Font' bool false" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Vertical Spacing'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Vertical Spacing' real 1" "${_iterm_plist}"

    # Profiles > Terminal
    # 4 = UTF-8 encoding.
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Character Encoding'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Character Encoding' integer 4" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Custom Locale'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Custom Locale' string 'en_US.UTF-8'" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Disable Printing'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Disable Printing' bool true" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Idle Code'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Idle Code' integer 0" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Load Shell Integration Automatically'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Load Shell Integration Automatically' bool true" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Mouse Reporting'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Mouse Reporting' bool true" "${_iterm_plist}"
    # 0 scrollback lines with Unlimited Scrollback = true means no hard cap.
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Scrollback Lines'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Scrollback Lines' integer 0" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Send Code When Idle'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Send Code When Idle' bool false" "${_iterm_plist}"
    # 2 = set locale environment variables automatically.
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Set Local Environment Vars'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Set Local Environment Vars' integer 2" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Terminal Type'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Terminal Type' string 'xterm-256color'" "${_iterm_plist}"

    # Profiles > Window
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Disable Window Resizing'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Disable Window Resizing' bool true" "${_iterm_plist}"
    # 1 = use profile name as window/tab icon label.
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Icon'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Icon' integer 1" "${_iterm_plist}"
    # -1 = open new sessions on the screen the window is currently on.
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Screen'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Screen' integer -1" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Sync Title'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Sync Title' bool false" "${_iterm_plist}"
    # 1 = show profile name as the title component.
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Title Components'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Title Components' integer 1" "${_iterm_plist}"
    # 0 = normal (non-fullscreen, non-maximized) window type.
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Window Type'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Window Type' integer 0" "${_iterm_plist}"

    # Profiles > General / Session
    # BM Growl: post a notification-center alert when bell fires in a background tab.
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'BM Growl'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'BM Growl' bool true" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Close Sessions On End'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Close Sessions On End' bool true" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Command'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Command' string ''" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Custom Tab Title'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Custom Tab Title' string ''" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Default Bookmark'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Default Bookmark' string 'No'" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Description'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Description' string 'Default'" "${_iterm_plist}"
    # Flashing Bell: flash the screen on bell (distinct from Visual Bell which uses a badge).
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Flashing Bell'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Flashing Bell' bool true" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Name'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Name' string 'Default'" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Open Toolbelt'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Open Toolbelt' bool false" "${_iterm_plist}"
    # 2 = always prompt before closing if a job other than those in 'Jobs to Ignore' is running.
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Prompt Before Closing 2'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Prompt Before Closing 2' integer 2" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Shortcut'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Shortcut' string ''" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Use Custom Tab Title'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Use Custom Tab Title' bool false" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Working Directory'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Working Directory' string '${HOME}'" "${_iterm_plist}"

    # Profiles > Keys -- modifier key behavior for Option keys
    # 0 = normal (do not send escape sequences for Option key combos; rely on Keyboard Map).
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Option Key Sends'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Option Key Sends' integer 0" "${_iterm_plist}"
    /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Right Option Key Sends'" "${_iterm_plist}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Right Option Key Sends' integer 0" "${_iterm_plist}"
  fi

  # ---------------------------------------------------------------------------
  # Hour - World Clock
  # ---------------------------------------------------------------------------
  # TODO: Capture all settings

  # ---------------------------------------------------------------------------
  # Google Chrome & Google Chrome Canary
  # ---------------------------------------------------------------------------
  if ask 'Chrome settings' 'Y'; then
    defaults write com.google.Chrome AppleEnableMouseSwipeNavigateWithScrolls -bool false
    defaults write com.google.Chrome AppleEnableSwipeNavigateWithScrolls -bool false
    defaults write com.google.Chrome KeychainReauthorizeInAppSpring2017 -int 2
    defaults write com.google.Chrome KeychainReauthorizeInAppSpring2017Success -bool true
    defaults write com.google.Chrome.beta AppleEnableMouseSwipeNavigateWithScrolls -bool false
    defaults write com.google.Chrome.beta AppleEnableSwipeNavigateWithScrolls -bool false
    defaults write com.google.Chrome.canary AppleEnableMouseSwipeNavigateWithScrolls -bool false
    defaults write com.google.Chrome.canary AppleEnableSwipeNavigateWithScrolls -bool false

    # Allow installing user scripts via GitHub or Userscripts.org
    # defaults write com.google.Chrome ExtensionInstallSources -array 'https://*.github.com/*' 'http://userscripts.org/*'
    # defaults write com.google.Chrome.canary ExtensionInstallSources -array 'https://*.github.com/*' 'http://userscripts.org/*'
  fi

  # ---------------------------------------------------------------------------
  # KeepassXC
  # ---------------------------------------------------------------------------
  if ask 'KeepassXC settings' 'Y'; then
    defaults write org.keepassxc.keepassxc 'NSNavLastRootDirectory' -string "${HOME}/personal/${USER}"
  fi

  # ---------------------------------------------------------------------------
  # Monolingual
  # ---------------------------------------------------------------------------
  if ask 'Monolingual settings' 'Y'; then
    defaults write net.sourceforge.Monolingual SUAutomaticallyUpdate -bool true
    defaults write net.sourceforge.Monolingual SUEnableAutomaticChecks -bool true
    defaults write net.sourceforge.Monolingual SUSendProfileInfo -bool false
    defaults write net.sourceforge.Monolingual Strip -bool true
  fi

  # ---------------------------------------------------------------------------
  # ProtonVpn
  # ---------------------------------------------------------------------------
  if ask 'ProtonVpn settings' 'Y'; then
    defaults write ch.protonvpn.mac ConnectOnDemand -bool true
    defaults write ch.protonvpn.mac EarlyAccess -bool true
    # Firewall and alternativeRouting are user-configurable network preferences,
    # not session/account state -- safe to codify.
    defaults write ch.protonvpn.mac Firewall -bool false
    defaults write ch.protonvpn.mac NSInitialToolTipDelay -int 500
    defaults write ch.protonvpn.mac RememberLoginAfterUpdate -bool true
    defaults write ch.protonvpn.mac SUAutomaticallyUpdate -bool true
    defaults write ch.protonvpn.mac SUEnableAutomaticChecks -bool false
    defaults write ch.protonvpn.mac SecureCoreToggle -bool false
    defaults write ch.protonvpn.mac StartMinimized -bool true
    defaults write ch.protonvpn.mac StartOnBoot -bool true
    defaults write ch.protonvpn.mac SystemNotifications -bool true
    defaults write ch.protonvpn.mac alternativeRouting -bool true
  fi

  # ---------------------------------------------------------------------------
  # Thunderbird-beta
  # ---------------------------------------------------------------------------
  if ask 'Thunderbird settings' 'Y'; then
    defaults write org.mozilla.thunderbird NSFullScreenMenuItemEverywhere -bool false
    defaults write org.mozilla.thunderbird NSTreatUnknownArgumentsAsOpen -bool false
  fi

  # ---------------------------------------------------------------------------
  # Zoomus
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Clocker
  # ---------------------------------------------------------------------------
  if ask 'Clocker settings' 'Y'; then
    # Skip: SelectedCalendars (iCloud Calendar UUIDs -- denial criterion #2) and
    # defaultPreferences (binary NSData blobs -- not portably expressible).
    defaults write com.abhishek.Clocker 'com.abhishek.menubarCompactMode' -int 0
    defaults write com.abhishek.Clocker 'com.abhishek.shouldDefaultToCompactMode' -bool true
    defaults write com.abhishek.Clocker defaultTheme -int 2
    defaults write com.abhishek.Clocker displayAppAsForegroundApp -bool false
    defaults write com.abhishek.Clocker is24HourFormatSelected -int 6
    defaults write com.abhishek.Clocker relativeDate -bool true
    defaults write com.abhishek.Clocker showDate -bool false
    defaults write com.abhishek.Clocker showSeconds -bool false
    defaults write com.abhishek.Clocker showSunriseSetTime -bool false
    defaults write com.abhishek.Clocker sliderDayRange -int 4
    defaults write com.abhishek.Clocker startAtLogin -bool true
    defaults write com.abhishek.Clocker userFontSize -int 7
  fi

  # ---------------------------------------------------------------------------
  # DBeaver
  # ---------------------------------------------------------------------------
  if ask 'DBeaver settings' 'Y'; then
    defaults write org.jkiss.dbeaver.core.product NSAutomaticDashSubstitutionEnabled -bool false
    defaults write org.jkiss.dbeaver.core.product NSAutomaticQuoteSubstitutionEnabled -bool false
    defaults write org.jkiss.dbeaver.core.product NSInitialToolTipDelay -int 300
    defaults write org.jkiss.dbeaver.core.product NSScrollAnimationEnabled -bool false
  fi

  # ---------------------------------------------------------------------------
  # DockDoor
  # ---------------------------------------------------------------------------
  # Login item: registered via Brewfile's setup_login_items_script (SMAppService).
  # DockDoor has no defaults key for login-item status.
  if ask 'DockDoor settings' 'Y'; then
    defaults write com.ethanbills.DockDoor SUAutomaticallyUpdate -bool true
    defaults write com.ethanbills.DockDoor SUEnableAutomaticChecks -bool true
    defaults write com.ethanbills.DockDoor SUSendProfileInfo -bool false
    defaults write com.ethanbills.DockDoor cmdTabEnabledTrafficLightButtons -array maximize quit close minimize
    defaults write com.ethanbills.DockDoor enableCmdTabEnhancements -bool true
    defaults write com.ethanbills.DockDoor enabledTrafficLightButtons -array quit close maximize minimize
    defaults write com.ethanbills.DockDoor reopenSettingsAfterRestart -bool false
  fi

  # ---------------------------------------------------------------------------
  # Drawio
  # ---------------------------------------------------------------------------
  if ask 'Drawio settings' 'Y'; then
    defaults write com.jgraph.drawio.desktop AppleTextDirection -bool true
    defaults write com.jgraph.drawio.desktop NSForceRightToLeftWritingDirection -bool false
    defaults write com.jgraph.drawio.desktop NSTreatUnknownArgumentsAsOpen -bool false
  fi

  # _firefox_user_js_content is defined here (outside the Firefox ask block) so that
  # the Zen Browser section can reference it even if the user skips Firefox settings.
  # user.js is the correct idempotent mechanism: Firefox overwrites prefs.js on every
  # launch, but sources user.js at startup and re-applies it over prefs.js each time.
  # Written to each profile dir that exists at the time the script runs. Nightly and
  # other profiles are skipped if they have not been created yet.
  local _firefox_user_js_content
  _firefox_user_js_content='// Written by osx-defaults.sh -- do not edit by hand; re-run the script to update.
// Firefox overwrites prefs.js on every launch; this file is re-applied at startup.
user_pref("browser.contentblocking.category", "strict");
user_pref("browser.ctrlTab.sortByRecentlyUsed", true);
user_pref("browser.download.autohideButton", false);
user_pref("browser.aboutConfig.showWarning", false);
// Disable AI features
user_pref("browser.ml.chat.enabled", false);
user_pref("browser.ml.chat.sidebar", false);
// Enhanced privacy: private IP address protection
user_pref("privacy.webrtc.globalMuteToggles", true);
user_pref("privacy.webrtc.hideGlobalIndicator", false);
// Disable sponsored content in new tab and urlbar
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
'

  # ---------------------------------------------------------------------------
  # Firefox
  # ---------------------------------------------------------------------------
  if ask 'Firefox settings' 'Y'; then
    # macOS-level NS* keys for all Firefox-family bundles.
    local _ff_bundle
    for _ff_bundle in org.mozilla.firefox org.mozilla.nightly org.mozilla.floorp org.mozilla.thunderbird.betterbird; do
      defaults write "${_ff_bundle}" NSFullScreenMenuItemEverywhere -bool false
      defaults write "${_ff_bundle}" NSNavLastRootDirectory -string "${HOME}/Downloads"
      defaults write "${_ff_bundle}" NSNavLastUserSetHideExtensionButtonState -bool false
      defaults write "${_ff_bundle}" NSTreatUnknownArgumentsAsOpen -bool false
      defaults write "${_ff_bundle}" PMPrintingExpandedStateForPrint2 -bool false
    done

    local _ff_profiles_root="${HOME}/Library/Application Support/Firefox/Profiles"
    if is_directory "${_ff_profiles_root}"; then
      local _ff_profile_dir
      for _ff_profile_dir in "${_ff_profiles_root}"/*/; do
        if is_directory "${_ff_profile_dir}"; then
          printf '%s' "${_firefox_user_js_content}" >"${_ff_profile_dir}user.js"
          success "Wrote user.js → ${_ff_profile_dir}"
        fi
      done
    fi
  fi

  # ---------------------------------------------------------------------------
  # Keybase
  # ---------------------------------------------------------------------------
  # Login item: registered via Brewfile's setup_login_items_script (SMAppService).
  # Keybase has no defaults key for login-item status.
  if ask 'Keybase settings' 'Y'; then
    defaults write keybase.Electron AppleTextDirection -bool true
    defaults write keybase.Electron NSForceRightToLeftWritingDirection -bool false
    defaults write keybase.Electron NSFullScreenMenuItemEverywhere -bool false
    defaults write keybase.Electron NSTreatUnknownArgumentsAsOpen -bool false
  fi

  # ---------------------------------------------------------------------------
  # MechVibes
  # ---------------------------------------------------------------------------
  # Login item: registered via Brewfile's setup_login_items_script (SMAppService).
  # MechVibes has no defaults key for login-item status.
  if ask 'MechVibes settings' 'Y'; then
    # Skip: NSStatusItem Preferred Position Item-0 -- menu bar pixel coordinate (criterion 4).
    defaults write com.electron.mechvibes NSFullScreenMenuItemEverywhere -bool false
    defaults write com.electron.mechvibes NSTreatUnknownArgumentsAsOpen -bool false
  fi

  # ---------------------------------------------------------------------------
  # KeyCastr
  # ---------------------------------------------------------------------------
  # Login item: registered via Brewfile's setup_login_items_script (SMAppService).
  # KeyCastr has no defaults key for login-item status.
  if ask 'KeyCastr settings' 'Y'; then
    # Skip: default.textColor -- binary NSKeyedArchiver blob with embedded ICC profile;
    # not portably expressible as a defaults write argument.
    defaults write io.github.keycastr SUEnableAutomaticChecks -bool true
    defaults write io.github.keycastr SUSendProfileInfo -bool false
    defaults write io.github.keycastr alwaysShowPrefs -bool false
    defaults write io.github.keycastr 'default.allKeys' -bool true
    defaults write io.github.keycastr 'default.allModifiedKeys' -bool false
    defaults write io.github.keycastr 'default.commandKeysOnly' -bool false
    defaults write io.github.keycastr 'default.fadeDelay' -float 2.576526409646739
    defaults write io.github.keycastr 'default.fadeDuration' -bool true
    defaults write io.github.keycastr 'default.fontSize' -float 47.2836277173913
    defaults write io.github.keycastr 'default.keystrokeDelay' -bool true
    defaults write io.github.keycastr 'default_displayModifiedCharacters' -bool true
    defaults write io.github.keycastr displayIcon -bool true
    defaults write io.github.keycastr 'mouse.displayOption' -bool true
    defaults write io.github.keycastr selectedVisualizer -string 'Default'
  fi

  # ---------------------------------------------------------------------------
  # KeyClu
  # ---------------------------------------------------------------------------
  if ask 'KeyClu settings' 'Y'; then
    defaults write com.0804Team.KeyClu SUAutomaticallyUpdate -bool true
    defaults write com.0804Team.KeyClu SUEnableAutomaticChecks -bool true
    defaults write com.0804Team.KeyClu SUSendProfileInfo -bool false
    defaults write com.0804Team.KeyClu activationKeyId -int 0
    defaults write com.0804Team.KeyClu activationKeyType -int 1
    defaults write com.0804Team.KeyClu activationPersistentKeyType -int 0
    defaults write com.0804Team.KeyClu appearance -string 'system'
    defaults write com.0804Team.KeyClu applyLimitToTitles -bool false
    defaults write com.0804Team.KeyClu hideMenuIcon -bool false
    defaults write com.0804Team.KeyClu launchAtLogin -bool true
    defaults write com.0804Team.KeyClu limitTitles -int 75
    defaults write com.0804Team.KeyClu makeItBloom -bool true
    defaults write com.0804Team.KeyClu makeItRainbow -bool false
    defaults write com.0804Team.KeyClu shortcutColors -string '1BBFF9FF,28CD41FF,FFCC00FF,FF9500FF,FF3930FF,AF52DDFF,FF2D53FF'
    defaults write com.0804Team.KeyClu showAppIcon -bool false
    defaults write com.0804Team.KeyClu showHighlight -bool true
    defaults write com.0804Team.KeyClu showUserHiddenElements -bool true
    defaults write com.0804Team.KeyClu silentLaunchQuit -bool true
  fi

  # ---------------------------------------------------------------------------
  # OnlyOffice
  # ---------------------------------------------------------------------------
  if ask 'OnlyOffice settings' 'Y'; then
    # Skip: asc_save_path (machine-specific path) and asc_user_name_app (personal name).
    defaults write asc.onlyoffice.ONLYOFFICE AppleLanguages -array 'en-US'
    defaults write asc.onlyoffice.ONLYOFFICE AppleLocale -string 'en-US'
    defaults write asc.onlyoffice.ONLYOFFICE NSDisabledCharacterPaletteMenuItem -bool false
    defaults write asc.onlyoffice.ONLYOFFICE NSDisabledDictationMenuItem -bool true
    defaults write asc.onlyoffice.ONLYOFFICE NSForceLeftToRightWritingDirection -bool true
    defaults write asc.onlyoffice.ONLYOFFICE SUAutomaticallyUpdate -bool true
    defaults write asc.onlyoffice.ONLYOFFICE SUEnableAutomaticChecks -bool true
    defaults write asc.onlyoffice.ONLYOFFICE SUSendProfileInfo -bool false
    defaults write asc.onlyoffice.ONLYOFFICE 'asc_user_docOpenMode' -string 'edit'
    defaults write asc.onlyoffice.ONLYOFFICE 'asc_user_ui_lang' -string 'en-US'
    defaults write asc.onlyoffice.ONLYOFFICE 'asc_user_ui_theme' -string 'theme-light'
  fi

  # ---------------------------------------------------------------------------
  # Rancher Desktop
  # ---------------------------------------------------------------------------
  if ask 'Rancher Desktop settings' 'Y'; then
    defaults write io.rancherdesktop.app AppleTextDirection -bool true
    defaults write io.rancherdesktop.app NSForceRightToLeftWritingDirection -bool false
    defaults write io.rancherdesktop.app NSFullScreenMenuItemEverywhere -bool false
    defaults write io.rancherdesktop.app NSTreatUnknownArgumentsAsOpen -bool false
  fi

  # ---------------------------------------------------------------------------
  # Shortcat
  # ---------------------------------------------------------------------------
  # Login item: registered via Brewfile's setup_login_items_script (SMAppService).
  # Shortcat has no defaults key for login-item status.
  if ask 'Shortcat settings' 'Y'; then
    # Skip: telemetryIdentifier -- device UUID (denial criterion #1).
    # KeyboardShortcuts_* keys are plain JSON strings encoding key codes and modifiers.
    defaults write com.sproutcube.Shortcat 'KeyboardShortcuts_click' -string '{"carbonModifiers":0,"carbonKeyCode":36}'
    defaults write com.sproutcube.Shortcat 'KeyboardShortcuts_debugElement' -string '{"carbonModifiers":256,"carbonKeyCode":119}'
    defaults write com.sproutcube.Shortcat 'KeyboardShortcuts_reloadUI' -string '{"carbonModifiers":768,"carbonKeyCode":15}'
    defaults write com.sproutcube.Shortcat 'KeyboardShortcuts_toggleLockUI' -string '{"carbonKeyCode":115,"carbonModifiers":256}'
    defaults write com.sproutcube.Shortcat 'KeyboardShortcuts_toggleShortcat' -string '{"carbonModifiers":2304,"carbonKeyCode":49}'
    defaults write com.sproutcube.Shortcat downKeycode -int 38
    defaults write com.sproutcube.Shortcat leftKeycode -int 4
    defaults write com.sproutcube.Shortcat rightKeycode -int 37
    defaults write com.sproutcube.Shortcat upKeycode -int 40
  fi

  # ---------------------------------------------------------------------------
  # Sol
  # ---------------------------------------------------------------------------
  # Login item: registered via Brewfile's setup_login_items_script (SMAppService).
  # Sol has no defaults key for login-item status.
  if ask 'Sol settings' 'Y'; then
    # Skip: NSWindow Frame * (display geometry -- denial criterion #4),
    # SUHasLaunchedBefore (one-time setup sentinel -- denial criterion #5),
    # SULastCheckTime (ephemeral timestamp -- denial criterion #3),
    # SUUpdateGroupIdentifier (internal Sparkle grouping ID, not user-configurable).
    defaults write com.ospfranco.sol RCTI18nUtil_makeRTLFlipLeftAndRightStyles -bool true
    defaults write com.ospfranco.sol SUAutomaticallyUpdate -bool true
    defaults write com.ospfranco.sol SUEnableAutomaticChecks -bool true
    defaults write com.ospfranco.sol SUSendProfileInfo -bool false
  fi

  # ---------------------------------------------------------------------------
  # Stats
  # ---------------------------------------------------------------------------
  if ask 'Stats settings' 'Y'; then
    # Skip: id, remote_id (device UUIDs -- denial criterion #1), ble_*, sensor_*, *_ts
    # (ephemeral sync state -- denial criterion #3), remote_tokens_migrated_to_keychain,
    # Clock_list (per-entry UUIDs -- denial criterion #1), version, NSStatusItem
    # Preferred/Restore Position (display geometry -- denial criterion #4).
    defaults write eu.exelban.Stats 'BAT_mini_alignment' -string 'right'
    defaults write eu.exelban.Stats 'BAT_mini_color' -string 'system'
    defaults write eu.exelban.Stats 'BAT_mini_label' -bool true
    defaults write eu.exelban.Stats 'Battery_barChart_position' -int 3
    defaults write eu.exelban.Stats 'Battery_bar_chart_label' -bool true
    defaults write eu.exelban.Stats 'Battery_battery_additional' -string 'percentage'
    defaults write eu.exelban.Stats 'Battery_battery_color' -bool true
    defaults write eu.exelban.Stats 'Battery_battery_position' -int 1
    defaults write eu.exelban.Stats 'Battery_color' -bool true
    defaults write eu.exelban.Stats 'Battery_label_position' -int 2
    defaults write eu.exelban.Stats 'Battery_mini_position' -int 0
    defaults write eu.exelban.Stats 'Battery_notifications_high' -string ''
    defaults write eu.exelban.Stats 'Battery_notifications_low' -string 'low'
    defaults write eu.exelban.Stats 'Battery_state' -bool true
    defaults write eu.exelban.Stats 'Battery_widget' -string 'mini'
    defaults write eu.exelban.Stats 'Bluetooth_label_position' -int 1
    defaults write eu.exelban.Stats 'Bluetooth_sensors_position' -int 1
    defaults write eu.exelban.Stats 'Bluetooth_stack_position' -int 0
    defaults write eu.exelban.Stats 'Bluetooth_state' -bool false
    defaults write eu.exelban.Stats 'Bluetooth_widget' -string 'sensors'
    defaults write eu.exelban.Stats 'CPU_barChart_position' -int 3
    defaults write eu.exelban.Stats 'CPU_label_position' -int 1
    defaults write eu.exelban.Stats 'CPU_lineChart_position' -int 0
    defaults write eu.exelban.Stats 'CPU_line_chart_box' -bool false
    defaults write eu.exelban.Stats 'CPU_line_chart_color' -string 'system'
    defaults write eu.exelban.Stats 'CPU_line_chart_frame' -bool false
    defaults write eu.exelban.Stats 'CPU_line_chart_label' -bool true
    defaults write eu.exelban.Stats 'CPU_line_chart_value' -bool true
    defaults write eu.exelban.Stats 'CPU_line_chart_valueColor' -bool true
    defaults write eu.exelban.Stats 'CPU_mini_color' -string 'Monochrome accent'
    defaults write eu.exelban.Stats 'CPU_mini_position' -int 2
    defaults write eu.exelban.Stats 'CPU_notifications_totalLoad' -string 'Disabled'
    defaults write eu.exelban.Stats 'CPU_pieChart_position' -int 4
    defaults write eu.exelban.Stats 'CPU_state' -bool false
    defaults write eu.exelban.Stats 'CPU_tachometer_position' -int 5
    defaults write eu.exelban.Stats 'CPU_widget' -string 'line_chart'
    defaults write eu.exelban.Stats 'Clock_label_position' -int 1
    defaults write eu.exelban.Stats 'Clock_stack_position' -int 0
    defaults write eu.exelban.Stats 'Clock_state' -bool false
    defaults write eu.exelban.Stats 'Clock_widget' -string 'sensors'
    defaults write eu.exelban.Stats CombinedModules -bool false
    defaults write eu.exelban.Stats 'Disk_removable' -bool false
    defaults write eu.exelban.Stats 'Disk_state' -bool true
    defaults write eu.exelban.Stats 'Disk_widget' -string 'mini'
    defaults write eu.exelban.Stats 'Fans_state' -bool false
    defaults write eu.exelban.Stats 'GPU_notifications_usage_state' -bool true
    defaults write eu.exelban.Stats 'GPU_notifications_usage_value' -int 80
    defaults write eu.exelban.Stats 'GPU_state' -bool false
    defaults write eu.exelban.Stats LaunchAtLoginNext -bool true
    defaults write eu.exelban.Stats 'NSStatusItem Visible Battery' -bool true
    defaults write eu.exelban.Stats 'NSStatusItem Visible CPU_Bar chart' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible CPU_Line chart' -bool true
    defaults write eu.exelban.Stats 'NSStatusItem Visible CPU_Mini' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible CPU_Pie chart' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible Disk_Bar chart' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible Disk_Memory' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible Disk_Speed' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible Fans' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible Fans_Text' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible GPU' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible GPU_Bar chart' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible GPU_Line chart' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible GPU_Mini' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible Network_Network chart' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible Network_Speed' -bool true
    defaults write eu.exelban.Stats 'NSStatusItem Visible RAM_Bar chart' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible RAM_Line chart' -bool true
    defaults write eu.exelban.Stats 'NSStatusItem Visible RAM_Memory' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible RAM_Mini' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible RAM_Pie chart' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible Sensors' -bool false
    defaults write eu.exelban.Stats 'NSStatusItem Visible Sensors_Text' -bool false
    defaults write eu.exelban.Stats 'Network_speed_base' -string 'byte'
    defaults write eu.exelban.Stats 'Network_speed_icon' -string 'arrows'
    defaults write eu.exelban.Stats 'Network_speed_valueColor' -bool true
    defaults write eu.exelban.Stats 'RAM_line_chart_box' -bool false
    defaults write eu.exelban.Stats 'RAM_line_chart_color' -string 'utilization'
    defaults write eu.exelban.Stats 'RAM_line_chart_frame' -bool false
    defaults write eu.exelban.Stats 'RAM_line_chart_label' -bool true
    defaults write eu.exelban.Stats 'RAM_line_chart_value' -bool true
    defaults write eu.exelban.Stats 'RAM_line_chart_valueColor' -bool true
    defaults write eu.exelban.Stats 'RAM_notifications_totalUsage' -string 'Disabled'
    defaults write eu.exelban.Stats 'RAM_widget' -string 'line_chart'
    defaults write eu.exelban.Stats 'SSD_mini_color' -string 'utilization'
    defaults write eu.exelban.Stats 'Sensors_speed' -bool true
    defaults write eu.exelban.Stats dockIcon -bool false
    defaults write eu.exelban.Stats telemetry -bool false
    defaults write eu.exelban.Stats 'update-interval' -string 'Once per day'
  fi

  # Thaw (Ice fork)
  # Login item: registered via Brewfile's setup_login_items_script (SMAppService).
  # Thaw has no defaults key for login-item status.
  if ask 'Thaw settings' 'Y'; then
    # Skip: Hotkeys (all values are null -- app treats missing key identically, and
    # PlistBuddy cannot write NSNull portably), MenuBarAppearanceConfigurationV2,
    # MenuBarItemManager.*, DisplayIceBarConfigurations (all contain per-display UUIDs
    # -- denial criterion #4), hasMigrated* flags (one-time migration sentinels).
    # IceIcon is stored as raw bytes but the JSON content is fully portable; writing
    # as -string causes macOS to store it as NSString, which Thaw reads correctly.
    defaults write com.stonerl.Thaw AutoRehide -bool true
    defaults write com.stonerl.Thaw CustomIceIconIsTemplate -bool false
    defaults write com.stonerl.Thaw EnableAlwaysHiddenSection -bool true
    defaults write com.stonerl.Thaw EnableDiagnosticLogging -bool false
    defaults write com.stonerl.Thaw EnableSecondaryContextMenu -bool true
    defaults write com.stonerl.Thaw HideApplicationMenus -bool true
    defaults write com.stonerl.Thaw IceBarLocation -int 0
    defaults write com.stonerl.Thaw IceBarLocationOnHotkey -int 0
    defaults write com.stonerl.Thaw IceIcon -string '{"hidden":{"catalog":{"_0":"IceCubeStroke"}},"visible":{"catalog":{"_0":"IceCubeFill"}},"name":"Ice Cube"}'
    defaults write com.stonerl.Thaw IconRefreshInterval -string '0.5'
    defaults write com.stonerl.Thaw ItemSpacingOffset -int 0
    defaults write com.stonerl.Thaw RehideInterval -int 15
    defaults write com.stonerl.Thaw RehideStrategy -int 0
    defaults write com.stonerl.Thaw SUAutomaticallyUpdate -bool true
    defaults write com.stonerl.Thaw SUEnableAutomaticChecks -bool true
    defaults write com.stonerl.Thaw SectionDividerStyle -int 1
    defaults write com.stonerl.Thaw ShowAllSectionsOnUserDrag -bool true
    defaults write com.stonerl.Thaw ShowIceIcon -bool true
    defaults write com.stonerl.Thaw ShowMenuBarTooltips -bool false
    defaults write com.stonerl.Thaw ShowOnClick -bool true
    defaults write com.stonerl.Thaw ShowOnDoubleClick -bool true
    defaults write com.stonerl.Thaw ShowOnHover -bool true
    defaults write com.stonerl.Thaw ShowOnHoverDelay -string '0.2'
    defaults write com.stonerl.Thaw ShowOnScroll -bool true
    defaults write com.stonerl.Thaw TooltipDelay -string '0.5'
    defaults write com.stonerl.Thaw UseIceBar -bool true
    defaults write com.stonerl.Thaw UseIceBarOnlyOnNotchedDisplay -bool false
  fi

  # ---------------------------------------------------------------------------
  # Zen Browser
  # ---------------------------------------------------------------------------
  if ask 'Zen Browser settings' 'Y'; then
    # Two bundle IDs in use across Zen versions.
    local _zen_bundle
    for _zen_bundle in app.zen-browser.zen org.mozilla.com.zen.browser; do
      defaults write "${_zen_bundle}" NSFullScreenMenuItemEverywhere -bool false
      defaults write "${_zen_bundle}" NSTreatUnknownArgumentsAsOpen -bool false
    done

    # user.js written to the Zen profile dir (same mechanism as Firefox -- see comment there).
    local _zen_profiles_root="${HOME}/Library/Application Support/Zen/Profiles"
    if is_directory "${_zen_profiles_root}"; then
      local _zen_profile_dir
      for _zen_profile_dir in "${_zen_profiles_root}"/*/; do
        if is_directory "${_zen_profile_dir}"; then
          printf '%s' "${_firefox_user_js_content}" >"${_zen_profile_dir}user.js"
          success "Wrote user.js → ${_zen_profile_dir}"
        fi
      done
    fi
  fi

  # ---------------------------------------------------------------------------
  # Activity Monitor
  # ---------------------------------------------------------------------------

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

  # ---------------------------------------------------------------------------
  # Photos
  # ---------------------------------------------------------------------------
  if ask 'Prevent Photos from opening automatically when devices are plugged in' 'Y'; then
    defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true
  fi

  # ---------------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------------
  # Disable automatic emoji substitution (i.e. use plain text smileys)
  # defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add 'automaticEmojiSubstitutionEnablediMessage' -bool false

  # Disable smart quotes as it's annoying for messages that contain code
  # defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add 'automaticQuoteSubstitutionEnabled' -bool false

  # Disable continuous spell checking
  # defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add 'continuousSpellCheckingEnabled' -bool false

  # ---------------------------------------------------------------------------
  # Software Update
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Mac App Store
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Time Machine
  # ---------------------------------------------------------------------------
  # Prevent Time Machine from prompting to use new hard drives as backup volume
  defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

  # Disable local Time Machine backups
  # TODO: This causes an error to be printed to stdout - need to investigate if this is deprecated
  # hash tmutil 2> /dev/null && sudo tmutil disablelocal

  # Auto backup:
  # defaults write com.apple.TimeMachine AutoBackup =1

  # Backup frequency default= 3600 seconds (every hour) 1800 = 1/2 hour, 7200=2 hours
  # sudo defaults write /System/Library/Launch Daemons/com.apple.backupd-auto StartInterval -int 1800

  # ---------------------------------------------------------------------------
  # Screen
  # ---------------------------------------------------------------------------
  # Require password immediately after sleep or screen saver begins
  defaults write com.apple.screensaver askForPassword -bool true
  defaults write com.apple.screensaver askForPasswordDelay -int 0

  # Enable subpixel font rendering on non-Apple LCDs (0=off, 1=light, 2=Medium/flat panel, 3=strong/blurred)
  # This is mostly needed for non-Apple displays.
  defaults write -g AppleFontSmoothing -int 2

  # Enable HiDPI display modes (requires restart)
  sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true

  # ---------------------------------------------------------------------------
  # Screen capture
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # Address Book
  # ---------------------------------------------------------------------------

  # Show Contact Reflection:
  # defaults write com.apple.AddressBook reflection -boolean
  # com.apple.AddressBook is sandbox-restricted on modern macOS; writes fail with
  # "Could not write domain" even as the file owner. Suppress the error -- the
  # settings are effectively read-only via this path on current OS versions.
  defaults write com.apple.AddressBook ABBirthDayVisible -bool true 2>/dev/null || true
  defaults write com.apple.AddressBook ABDefaultAddressCountryCode -string in 2>/dev/null || true

  # ---------------------------------------------------------------------------
  # OmniGraffle
  # ---------------------------------------------------------------------------
  # Allow scroll wheel zooming:
  # defaults write com.omnigroup.OmniGraffle DisableScrollWheelZooming -bool false

  # Allow scroll wheel zooming in OmniGrafflePro:
  # defaults write com.omnigroup.OmniGrafflePro DisableScrollWheelZooming -bool false

  # ---------------------------------------------------------------------------
  # Quick Time Player
  # ---------------------------------------------------------------------------
  # Automatically show Closed Captions (CC) when opening a Movie:
  # defaults -currentHost write com.apple.QuickTimePlayerX.plist MGEnableCCAndSubtitlesOnOpen -boolean

  # ---------------------------------------------------------------------------
  # Spaces
  # ---------------------------------------------------------------------------
  # When switching applications, switch to respective space
  defaults write -g AppleSpacesSwitchOnActivate -bool true

  # ---------------------------------------------------------------------------
  # Kill affected applications
  # ---------------------------------------------------------------------------
  local app_array=(
    'Activity Monitor'
    'Address Book'
    'App Store'      # com.apple.appstore / com.apple.commerce
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
    'ScreenSaverEngine' # com.apple.screensaver (password-on-wake settings)
    'SizeUp'
    'SystemUIServer'
  )
  local app
  for app in "${app_array[@]}"; do
    killall "${app}" &>/dev/null || true
  done

  # Re-activate symbolic hotkey settings so changes to AppleSymbolicHotKeys
  # (e.g. disabling the Spotlight shortcuts) take effect immediately without a
  # logout. activateSettings is the only supported way to flush this plist.
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u

  # Turn off spotlight indexing for all volumes (to pre-empt any issues with the system settings pane)
  sudo mdutil -Eda &>/dev/null && sudo mdutil -ai off &>/dev/null

  user_action "Grant Full Disk Access to 'Terminal' and 'iTerm': System Settings → Privacy & Security → Full Disk Access → add 'Terminal.app' and 'iTerm.app' (cannot be automated -- TCC is SIP-protected)."
  user_action "Manually adjust the Finder sidebar content (which folders appear in Favorites): stored in LSSharedFileList binary files -- not scriptable via defaults."
  user_action "The following apps have to be manually quit and restarted for their settings to be reloaded:
  'Terminal' and 'iTerm' (since one of these might be running this script),
  'ProtonVPN' (force-quitting may drop the VPN connection),
  'Zoom' (force-quitting during a call would disconnect it),
  'Thunderbird',
  'KeePassXC'"
  print_script_summary '' 'Done. Note that some of these changes require a logout/restart to take effect.'
}

main "$@"
