#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# Sets macOS system and application preferences via 'defaults write'.
# Run with -s to seed a baseline on a fresh machine; run with -i to import
# preferences on top of that baseline (see osx-defaults.sh -h for full usage).
# Originally inspired by: https://gist.github.com/DAddYE/2108403

# set -euo pipefail is intentionally omitted: many 'defaults write' and 'killall'
# calls return non-zero when a setting is unsupported on the current OS version,
# which is expected and must not abort the script.

# Most macOS defaults are now applied declaratively via nix-darwin system.defaults.*
# (darwin-configuration.nix) and targets.darwin.defaults (nix/modules/osx-app-defaults.nix),
# applied on every 'darwin-rebuild switch'. This script handles only the settings that
# cannot be expressed declaratively:
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

  # Login-item apps are killed upfront (SIGTERM — graceful shutdown) so their
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

  # Keep keyboard brightness at maximum via -currentHost write; cannot be
  # expressed as a plain defaults write (host-specific pref domain).
  if ask 'Keep keyboard brightness at maximum' 'Y'; then
    defaults -currentHost write com.apple.controlcenter KeyboardBrightness 8
  fi

  if ask 'Disable automatic keyboard brightness adjustment in low light' 'Y'; then
    # com.apple.BezelServices dAuto controls "Adjust keyboard brightness in low light"
    # (System Settings > Keyboard). CoreBrightness KeyboardBacklightAutoDim does not
    # work on modern macOS; dAuto is the correct key.
    defaults write com.apple.BezelServices dAuto -bool false
  fi

  # dontAutoLoad must be written to the ByHost preference file (identified by
  # hardware UUID) — not to the regular com.apple.systemuiserver domain. The
  # ByHost path is what SystemUIServer reads on startup to skip certain menu
  # extras regardless of which user is logged in. The remaining systemuiserver
  # and menuextra.clock writes are handled declaratively by osx-app-defaults.nix.
  for domain in "${HOME}"/Library/Preferences/ByHost/com.apple.systemuiserver.*(N.); do
    defaults write "${domain}" dontAutoLoad -array \
      '/System/Library/CoreServices/Menu Extras/TimeMachine.menu' \
      '/System/Library/CoreServices/Menu Extras/Volume.menu' \
      '/System/Library/CoreServices/Menu Extras/User.menu'
  done

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

  if ask "Remove duplicates in the 'Open With' menu (also see 'lscleanup' alias)" 'Y'; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
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

  if ask 'Set preferred languages to English (India, US) and clear recent places' 'Y'; then
    defaults write -g NSLinguisticDataAssetsRequested -array 'en_IN' 'en_US' 'en'
    # Suppress error when the key doesn't exist — delete is a no-op in that case.
    defaults delete NSGlobalDomain NSNavRecentPlaces 2>/dev/null || true
  fi

  if ask 'Set text shortcuts for common phrases (dfdm, ntd, cyl, ttyl, omw, omg)' 'Y'; then
    defaults write -g NSUserDictionaryReplacementItems -array \
      '{ on = 1; replace = dfdm; with = "dropping off for different meeting"; }' \
      '{ on = 1; replace = ntd; with = "need to drop"; }' \
      '{ on = 1; replace = cyl; with = "Cya later!"; }' \
      '{ on = 1; replace = ttyl; with = "Talk to you later!"; }' \
      '{ on = 1; replace = omw; with = "On my way!"; }' \
      '{ on = 1; replace = omg; with = "Oh my God!"; }'
  fi

  if ask 'Disable adding apps to the Services contextual menu (reduces right-click clutter)' 'Y'; then
    # com.apple.SetupAssistant domain is machine-specific overall, but this single key
    # is a portable user preference controlling whether apps populate the Services submenu.
    defaults write com.apple.SetupAssistant NSAddServicesToContextMenus -bool false
  fi

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

  # ---------------------------------------------------------------------------
  # Finder
  # ---------------------------------------------------------------------------

  if ask 'Hide hard drive icons on the desktop' 'N'; then
    defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
  fi

  if ask 'Hide hidden files by default in Finder' 'N'; then
    defaults write com.apple.finder AppleShowAllFiles -bool false
  fi

  if ask "Start the status bar path at \${HOME} (instead of 'Hard drive')" 'Y'; then
    sudo defaults write /Library/Preferences/com.apple.finder PathBarRootAtHome -bool true
  fi

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

  if ask 'Disable the warning when changing a file extension' 'N'; then
    defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
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

  if ask "Expand File Info panes: 'General', 'Open with', 'Sharing & Permissions', 'Comments', 'Name', 'Metadata'" 'Y'; then
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'Comments' -bool true
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'General' -bool true
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'MetaData' -bool true
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'Name' -bool true
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'OpenWith' -bool true
    defaults write com.apple.finder FXInfoPanesExpanded -dict-add 'Privileges' -bool true
  fi

  # ---------------------------------------------------------------------------
  # Dock
  # ---------------------------------------------------------------------------

  if ask 'In Expose, only show windows from the current space' 'N'; then
    defaults write com.apple.dock 'wvous-show-windows-in-other-spaces' -bool false
  fi

  if ask 'Remove the auto-hiding Dock delay' 'N'; then
    defaults write com.apple.dock 'autohide-delay' -float 0
  fi

  if ask "Enable the 'reopen windows when logging back in' option" 'N'; then
    # This works, although the checkbox will still appear to be checked.
    defaults write com.apple.loginwindow TALLogoutSavesState -bool true
    defaults write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -bool true
  fi

  if ask 'Disable the Launchpad gesture (pinch with thumb and three fingers)' 'N'; then
    defaults write com.apple.dock showLaunchpadGestureEnabled -int 0
  fi

  # ---------------------------------------------------------------------------
  # Energy saving
  # ---------------------------------------------------------------------------

  # Enable lid wakeup
  sudo pmset -a lidwake 1

  # Restart automatically on power loss
  sudo pmset -a autorestart 1

  # Enable HiDPI display modes (requires restart)
  sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true

  # ---------------------------------------------------------------------------
  # Safari & WebKit
  # ---------------------------------------------------------------------------

  if ask "Set Safari's home page to 'about:blank' for faster loading" 'N'; then
    defaults write com.apple.Safari HomePage -string 'about:blank'
  fi

  if ask 'Enable the Develop menu and the Web Inspector in Safari' 'N'; then
    defaults write com.apple.Safari IncludeDevelopMenu -bool true
    defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
    defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
  fi

  if ask 'Include page background colors and images when printing' 'N'; then
    defaults write com.apple.safari WebKitShouldPrintBackgroundsPreferenceKey -bool true
  fi

  # ---------------------------------------------------------------------------
  # Mail
  # ---------------------------------------------------------------------------

  if ask 'Display emails in threaded mode, sorted by date (oldest at the top)' 'Y'; then
    # targets.darwin.defaults does not support -dict-add (incremental dict building);
    # these three keys must be written here with individual dict-add calls.
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
  # The orderedItems search category list is applied declaratively via
  # targets.darwin.defaults in nix/modules/osx-app-defaults.nix.

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
    # Top-level Terminal.app defaults — initial defaults seeded here so the user
    # can change them via the UI afterward without bupc reverting them.
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
      # instead of PlistBuddy — it sets font name/size as first-class properties on the settings set.
      # PostScript name: MesloLGSNF-Italic (from MesloLGS Nerd Font Italic).
      osascript -e "tell application \"Terminal\" to set font name of settings set \"${profile}\" to \"MesloLGSNF-Italic\""
      osascript -e "tell application \"Terminal\" to set font size of settings set \"${profile}\" to 13"
      # Profiles > Keyboard > "Use Option as Meta key": makes Option+B/F send \033b/\033f for readline
      # word navigation. Option+arrow keys still send \033[1;9D/C — those need bindkey in .zshrc.
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
    # Profiles > Text > Font. Stored as "PostScriptName Size" plain string — no binary encoding needed.
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

    # Profiles > Keys — modifier key behavior for Option keys
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
    # not session/account state — safe to codify.
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
    # Skip: SelectedCalendars (iCloud Calendar UUIDs — denial criterion #2) and
    # defaultPreferences (binary NSData blobs — not portably expressible).
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
  # Login item: registered via nix/darwin-configuration.nix postinstall: (SMAppService).
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
  # NS* macOS-level defaults for all Firefox-family bundles are applied declaratively
  # via targets.darwin.defaults in nix/modules/osx-app-defaults.nix.
  local _firefox_user_js_content
  _firefox_user_js_content='// Written by osx-defaults.sh — do not edit by hand; re-run the script to update.
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
  # Zen Browser
  # ---------------------------------------------------------------------------

  # NS* macOS-level defaults for Zen bundle IDs are applied declaratively via
  # targets.darwin.defaults in nix/modules/osx-app-defaults.nix.
  if ask 'Zen Browser settings' 'Y'; then
    # user.js written to the Zen profile dir (same mechanism as Firefox — see comment there).
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

  if ask 'Default to showing the Network tab' 'Y'; then
    # SelectedTab is not covered by system.defaults.ActivityMonitor in nix-darwin.
    defaults write com.apple.ActivityMonitor SelectedTab -int 4
  fi

  # ---------------------------------------------------------------------------
  # Photos
  # ---------------------------------------------------------------------------

  if ask 'Prevent Photos from opening automatically when devices are plugged in' 'Y'; then
    defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true
  fi

  # ---------------------------------------------------------------------------
  # Software Update
  # ---------------------------------------------------------------------------

  if ask 'Download updates automatically in the background' 'Y'; then
    sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
  fi

  # ---------------------------------------------------------------------------
  # Address Book
  # ---------------------------------------------------------------------------

  # com.apple.AddressBook is sandbox-restricted on modern macOS; writes fail with
  # "Could not write domain" even as the file owner. Suppress the error — the
  # settings are effectively read-only via this path on current OS versions.
  defaults write com.apple.AddressBook ABBirthDayVisible -bool true 2>/dev/null || true
  defaults write com.apple.AddressBook ABDefaultAddressCountryCode -string in 2>/dev/null || true

  # ---------------------------------------------------------------------------
  # Finder — sidebar, view and display settings
  # ---------------------------------------------------------------------------
  # Initial defaults seeded here. Finder updates many of these during normal
  # use (sidebar width, section disclosure states, etc.) — bupc must not reset
  # them, so they do not live in targets.darwin.defaults.

  if ask 'Configure Finder sidebar and view settings' 'Y'; then
    defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
    defaults write com.apple.finder ShowMountedServersOnDesktop -bool false
    defaults write com.apple.finder ShowRecentTags -bool false
    defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
    defaults write com.apple.finder ShowSidebar -bool true
    defaults write com.apple.finder SidebarDevicesSectionDisclosedState -bool true
    defaults write com.apple.finder SidebarPlacesSectionDisclosedState -bool true
    defaults write com.apple.finder SidebarShowingSignedIntoiCloud -bool true
    defaults write com.apple.finder SidebarShowingiCloudDesktop -bool true
    # Note: typo "Sction" is intentional — that is the actual key name.
    defaults write com.apple.finder SidebarTagsSctionDisclosedState -bool true
    defaults write com.apple.finder SidebarWidth -int 172
    defaults write com.apple.finder SidebariCloudDriveSectionDisclosedState -bool true
    defaults write com.apple.finder FXRemoveOldTrashItems -bool true
    defaults write com.apple.finder _FXEnableColumnAutoSizing -bool true
    defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true
    defaults write com.apple.finder RestoreWindowState -bool true
    defaults write com.apple.finder ShowPreviewPane -bool false
    defaults write com.apple.finder QLEnableTextSelection -bool true
    defaults write com.apple.finder EmptyTrashSecurely -bool true
    defaults write com.apple.finder FK_AppCentricShowSidebar -bool true
    # Ensures column view is applied to search results windows too.
    defaults write com.apple.finder SearchRecentsSavedViewStyle -string 'clmv'
  fi

  # ---------------------------------------------------------------------------
  # Spotlight — search category ordering
  # ---------------------------------------------------------------------------
  # Initial default seeded here. The user may enable/disable categories via
  # System Settings > Spotlight afterward — bupc must not reset them.

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

  # ---------------------------------------------------------------------------
  # Safari — visual and behavioural preferences
  # ---------------------------------------------------------------------------
  # Initial defaults seeded here. Security/privacy/debug policy keys are
  # enforced declaratively in nix/modules/osx-app-defaults.nix.

  if ask 'Configure Safari visual and browsing preferences' 'Y'; then
    defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly -bool false
    defaults write com.apple.Safari 'ProxiesInBookmarksBar' -string '()'
    defaults write com.apple.Safari ShowFavoritesBar -bool false
    defaults write com.apple.Safari 'ShowFavoritesBar-v2' -bool false
    defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
    defaults write com.apple.Safari ShowSidebarInTopSites -bool false
    defaults write com.apple.Safari WebKitMediaPlaybackAllowsInline -bool false
    defaults write com.apple.Safari \
      'com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback' -bool false
    # Safari Technology Preview — parallel settings
    defaults write com.apple.SafariTechnologyPreview WebKitMediaPlaybackAllowsInline -bool false
    defaults write com.apple.SafariTechnologyPreview \
      'com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback' -bool false
    # Lowercase bundle ID used for these specific keys (as in original script).
    defaults write com.apple.safari DebugSafari4IncludeGoogleSuggest -bool true
    defaults write com.apple.safari WebContinuousSpellCheckingEnabled -bool true
    defaults write com.apple.safari WebGrammarCheckingEnabled -bool true
  fi

  # ---------------------------------------------------------------------------
  # ProtonVPN — connection preferences
  # ---------------------------------------------------------------------------
  # Initial defaults seeded here. The user may toggle connect-on-demand,
  # alternative routing, etc. during sessions — bupc must not reset them.

  if ask 'Configure ProtonVPN connection preferences' 'Y'; then
    defaults write ch.protonvpn.mac ConnectOnDemand -bool true
    defaults write ch.protonvpn.mac Firewall -bool false
    defaults write ch.protonvpn.mac NSInitialToolTipDelay -int 500
    defaults write ch.protonvpn.mac SecureCoreToggle -bool false
    defaults write ch.protonvpn.mac alternativeRouting -bool true
  fi

  # ---------------------------------------------------------------------------
  # Zoom — chat and display preferences
  # ---------------------------------------------------------------------------
  # Initial defaults seeded here. Window layout (ZoomFit*) is ephemeral and
  # not set — Zoom updates it on every window move.

  if ask 'Configure Zoom chat and display preferences' 'Y'; then
    defaults write ZoomChat ZMEnableShowUserName -bool true
    defaults write ZoomChat ZoomAutoCopyInvitationURL -bool true
    defaults write ZoomChat ZoomEnableShow49WallViewKey -bool true
    defaults write ZoomChat ZoomEnterFullscreenWhenViewShare -bool false
    defaults write ZoomChat ZoomEnterMaxWndWhenViewShare -bool true
    defaults write ZoomChat ZoomRememberPhoneKey -bool true
  fi

  # ---------------------------------------------------------------------------
  # Clocker — display preferences
  # ---------------------------------------------------------------------------
  # Initial defaults seeded here. The user configures timezone list, format,
  # etc. in Clocker's UI — bupc must not reset them.
  # startAtLogin is enforced declaratively in nix/modules/osx-app-defaults.nix.

  if ask 'Configure Clocker display preferences' 'Y'; then
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
    defaults write com.abhishek.Clocker userFontSize -int 7
  fi

  # ---------------------------------------------------------------------------
  # Thaw — display and timing preferences
  # ---------------------------------------------------------------------------
  # Initial defaults seeded here. Core behaviour (AutoRehide, HideApplicationMenus,
  # etc.) is enforced declaratively in nix/modules/osx-app-defaults.nix.

  if ask 'Configure Thaw menu bar manager display preferences' 'Y'; then
    # CustomIceIconIsTemplate = false: render the IceBar icon in full colour, not as
    # a monochrome template (which macOS would tint to match the menu bar style).
    defaults write com.stonerl.Thaw CustomIceIconIsTemplate -bool false
    defaults write com.stonerl.Thaw IceBarLocation -int 0
    defaults write com.stonerl.Thaw IceBarLocationOnHotkey -int 0
    # JSON string stored as NSString — Thaw reads it correctly.
    defaults write com.stonerl.Thaw IceIcon \
      -string '{"hidden":{"catalog":{"_0":"IceCubeStroke"}},"visible":{"catalog":{"_0":"IceCubeFill"}},"name":"Ice Cube"}'
    # Stored as NSString (not float) in Thaw's plist.
    defaults write com.stonerl.Thaw IconRefreshInterval -string '0.5'
    defaults write com.stonerl.Thaw ItemSpacingOffset -int 0
    defaults write com.stonerl.Thaw RehideInterval -int 15
    defaults write com.stonerl.Thaw SectionDividerStyle -int 1
    defaults write com.stonerl.Thaw ShowMenuBarTooltips -bool false
    defaults write com.stonerl.Thaw ShowOnClick -bool true
    defaults write com.stonerl.Thaw ShowOnDoubleClick -bool true
    defaults write com.stonerl.Thaw ShowOnHover -bool true
    # Stored as NSString (not float) in Thaw's plist.
    defaults write com.stonerl.Thaw ShowOnHoverDelay -string '0.2'
    defaults write com.stonerl.Thaw ShowOnScroll -bool true
    # Stored as NSString (not float) in Thaw's plist.
    defaults write com.stonerl.Thaw TooltipDelay -string '0.5'
    defaults write com.stonerl.Thaw UseIceBarOnlyOnNotchedDisplay -bool false
  fi

  # ---------------------------------------------------------------------------
  # KeyCastr — visual settings
  # ---------------------------------------------------------------------------
  # Initial defaults seeded here. The user adjusts font size, fade delay, etc.
  # in KeyCastr's UI — bupc must not reset them.
  # SU* policy keys are enforced declaratively in nix/modules/osx-app-defaults.nix.

  if ask 'Configure KeyCastr visual settings' 'Y'; then
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
  # Stats — menu bar widget configuration
  # ---------------------------------------------------------------------------
  # Initial defaults seeded here. The user customises which modules and widget
  # types are shown — bupc must not reset their layout.

  if ask 'Configure Stats menu bar widget settings' 'Y'; then
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

  user_action "Grant Full Disk Access to 'Terminal' and 'iTerm': System Settings → Privacy & Security → Full Disk Access → add 'Terminal.app' and 'iTerm.app' (cannot be automated — TCC is SIP-protected)."
  user_action "Manually adjust the Finder sidebar content (which folders appear in Favorites): stored in LSSharedFileList binary files — not scriptable via defaults."
  user_action "The following apps have to be manually quit and restarted for their settings to be reloaded:
  'Terminal' and 'iTerm' (since one of these might be running this script),
  'ProtonVPN' (force-quitting may drop the VPN connection),
  'Zoom' (force-quitting during a call would disconnect it),
  'Thunderbird',
  'KeePassXC'"
  print_script_summary '' 'Done. Note that some of these changes require a logout/restart to take effect.'
}

main "$@"
