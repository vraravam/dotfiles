#!/usr/bin/env bash

# This is a script with useful tips taken from: https://gist.github.com/DAddYE/2108403
# Please, share your tips by forking the repo and adding your customizations
# Thanks to: @erikh, @DAddYE, @mathiasbynens

case "${1}" in
  "-s" | "--silent" )
    echo "Running in silent mode..."
    auto=Y
    shift 1
    ;;
  * )
    auto=N
    if [ ! -t 0 ]; then
      echo "Interactive mode needs terminal!" >&2
      exit 1
    fi
    ;;
esac

# Source helpers only once if any required function is missing
type keep_sudo_alive &> /dev/null 2>&1 || source "${HOME}/.shellrc"

###############################################################################################
# Ask for the administrator password upfront and keep it alive until this script has finished #
###############################################################################################
keep_sudo_alive

ask() {
  while true; do
    if [ "${2}" == "Y" ]; then
      prompt="$(green 'Y')/n"
      default=Y
    elif [ "${2}" == "N" ]; then
      prompt="y/$(green 'N')"
      default=N
    else
      prompt="y/n"
      default=
    fi

    printf "${1} [$prompt] "

    if [ "$auto" == "Y" ]; then
      echo
    else
      read yn
    fi

    if [ -z "$yn" ]; then
      yn=$default
    fi

    case $yn in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
    esac
  done
}

# Close any open System Preferences panes, to prevent them from overriding
# settings we're about to change
osascript -e 'tell application "System Preferences" to quit'

# While applying any changes to SoftwareUpdate defaults, set software update to OFF to avoid any conflict with the defaults system cache. (Also close the System Preferences app)
sudo softwareupdate --schedule OFF

###############################################################################
# Couldn't find the following settings in macOS Mojave (10.14.3)              #
###############################################################################

# Expand "save as..." dialog by default
# defaults write -g NSNavPanelExpandedStateForSaveMode -bool true
# defaults write -g NSNavPanelExpandedStateForSaveMode2 -bool true

# Expand print panel by default
# defaults write -g PMPrintingExpandedStateForPrint -bool true
# defaults write -g PMPrintingExpandedStateForPrint2 -bool true

# Automatically quit printer app once the print jobs complete
# defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

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

###############################################################################
# Login Window                                                                #
###############################################################################

if ask "Disable guest login" Y; then
  sudo defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false
fi

###############################################################################
# MenuBar                                                                     #
###############################################################################

# Disable menu bar transparency - Couldn't find this in mac OS Mojave
# defaults write -g AppleEnableMenuBarTransparency -bool false

if ask "Show remaining battery time" N; then
  defaults write com.apple.menuextra.battery ShowTime -string "YES"
fi

if ask "Show remaining battery percentage" Y; then
  defaults write com.apple.menuextra.battery ShowPercent -string "YES"
fi

if ask "Show remaining battery percentage" Y; then
  defaults -currentHost write com.apple.controlcenter BatteryShowPercentage -bool true
fi

if ask "Turn off Battery in menubar" Y; then
  defaults write com.apple.controlcenter "NSStatusItem Visible Battery" 0
fi

if ask "Show bluetooth in menubar" Y; then
  defaults write com.apple.controlcenter "NSStatusItem Visible Bluetooth" 1
fi

if ask "Keep keyboard brightness at max value" Y; then
  defaults -currentHost write com.apple.controlcenter KeyboardBrightness 8
fi

# TODO: Doesn't seem to work (tried in sequoia 15.5)
# if ask "Turn off keyboard backlight auto-dim" Y; then
#   defaults write com.apple.CoreBrightness KeyboardBacklightAutoDim -bool false
# fi

###############################################################################
# General UI/UX                                                               #
###############################################################################

if ask "Set computer name (as done via System Preferences → Sharing)" Y; then
  userNameInCamelCase=$(echo "$(whoami)" | awk '{$1=toupper(substr($1,0,1))substr($1,2)}1')

  sudo scutil --set ComputerName "IND-CHN-${userNameInCamelCase}'s MBP-$(date)"
  sudo scutil --set HostName "${userNameInCamelCase}"
  sudo scutil --set LocalHostName "${userNameInCamelCase}"
  sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "${userNameInCamelCase}"
fi

if ask "Set standby delay to 6 hours (default: 1 hour)" Y; then
  sudo pmset -a standbydelay 21600
fi

# Disable the sound effects on boot
# sudo nvram SystemAudioVolume=" "

# Disable transparency in the menu bar and elsewhere on Yosemite
# defaults write com.apple.universalaccess reduceTransparency -bool true

# Set highlight color to green
# defaults write NSGlobalDomain AppleHighlightColor -string "0.764700 0.976500 0.568600"

for domain in "${HOME}"/Library/Preferences/ByHost/com.apple.systemuiserver.*; do
  defaults write "${domain}" dontAutoLoad -array \
    "/System/Library/CoreServices/Menu Extras/TimeMachine.menu" \
    "/System/Library/CoreServices/Menu Extras/Volume.menu" \
    "/System/Library/CoreServices/Menu Extras/User.menu"
done
defaults write com.apple.systemuiserver menuExtras -array \
  "/System/Library/CoreServices/Menu Extras/Bluetooth.menu" \
  "/System/Library/CoreServices/Menu Extras/AirPort.menu" \
  "/System/Library/CoreServices/Menu Extras/Battery.menu" \
  "/System/Library/CoreServices/Menu Extras/Clock.menu" \
  "/System/Library/CoreServices/Menu Extras/User.menu" \
  "/System/Library/CoreServices/Menu Extras/Volume.menu"

defaults write com.apple.systemuiserver "NSStatusItem Visible Siri" -bool false
defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.airport" -bool true
defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.appleuser" -bool true
defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.battery" -bool true
defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.bluetooth" -bool true
defaults write com.apple.systemuiserver "NSStatusItem Visible com.apple.menuextra.volume" -bool true

defaults write com.apple.menuextra.clock DateFormat -string "EEE d MMM  h:mm:ss a"
defaults write com.apple.menuextra.clock FlashDateSeparators -bool true
defaults write com.apple.menuextra.clock IsAnalog -bool true  # Since I am using `The Clocker` app, turning this to analog
defaults write com.apple.menuextra.clock Show24Hour -bool false
defaults write com.apple.menuextra.clock ShowAMPM -bool true
defaults write com.apple.menuextra.clock ShowDate -bool false
defaults write com.apple.menuextra.clock ShowDayOfMonth -bool true
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool false
defaults write com.apple.menuextra.clock ShowSeconds -bool true

if ask "Remove duplicates in the 'Open With' menu (also see 'lscleanup' alias)" Y; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
fi

# Display ASCII control characters using caret notation in standard text views
# Try e.g. `cd /tmp; unidecode "\x{0000}" > cc.txt; open -e cc.txt`
# defaults write -g NSTextShowsControlCharacters -bool true

# if ask "Enable multitouch trackpad auto orientation sensing (for all users)" Y; then
#   defaults write /Library/Preferences/com.apple.MultitouchSupport ForceAutoOrientation -boolean
# fi

if ask "Enable Resume applications on reboot (system-wide)" Y; then
  defaults write -g NSQuitAlwaysKeepsWindows -bool true
fi

if ask "Restart automatically if the computer freezes" Y; then
  sudo systemsetup -setrestartfreeze on
fi

if ask "Set the timezone" Y; then
  # see 'sudo systemsetup -listtimezones' for other values
  sudo systemsetup -settimezone "Asia/Calcutta"
fi

if ask "Set the time using the network time" Y; then
  sudo systemsetup -setusingnetworktime on
fi

if ask "Set the computer sleep time to 10 minutes" Y; then
  # To never go into computer sleep mode, use 'Never' or 'Off'
  sudo systemsetup -setcomputersleep 10
fi

if ask "Set the display sleep time to 10 minutes" Y; then
  # To never go into display sleep mode, use 'Never' or 'Off'
  sudo systemsetup -setdisplaysleep 10
fi

if ask "Set the harddisk sleep time to 15 minutes" Y; then
  # To never go into harddisk sleep mode, use 'Never' or 'Off'
  sudo systemsetup -setharddisksleep 15
fi

# TODO: This causes terminal.app to run in an interactive loop
# if ask "Set the remote login to off" Y; then
#   sudo systemsetup -setremotelogin off
# fi

# Disable Notification Center and remove the menu bar icon
# launchctl unload -w /System/Library/LaunchAgents/com.apple.notificationcenterui.plist 2> /dev/null

if ask "Disable automatic capitalization as it's annoying when typing code" Y; then
  defaults write -g NSAutomaticCapitalizationEnabled -bool false
fi

if ask "Set the languages present" Y; then
  defaults write -g NSLinguisticDataAssetsRequested -array "en_IN" "en_US" "en"
  defaults delete NSGlobalDomain NSNavRecentPlaces
fi

# TODO: defaults write -g NSPreferredWebServices NSWebServicesProviderWebSearch

if ask "Set the some english acronyms/short forms for ease of typing" Y; then
  defaults write -g NSUserDictionaryReplacementItems -array \
    '{ on = 1; replace = dfdm; with = "dropping off for different meeting"; }' \
    '{ on = 1; replace = ntd; with = "need to drop"; }' \
    '{ on = 1; replace = cyl; with = "Cya later!"; }' \
    '{ on = 1; replace = ttyl; with = "Talk to you later!"; }' \
    '{ on = 1; replace = omw; with = "On my way!"; }' \
    '{ on = 1; replace = omg; with = "Oh my God!"; }'
fi

if ask "Disable automatic period substitution as it's annoying when typing code" Y; then
  defaults write -g NSAutomaticPeriodSubstitutionEnabled -bool false
fi

# TODO: This is not working yet
# Set a custom wallpaper image. `DefaultDesktop.jpg` is already a symlink, and
# all wallpapers are in `/Library/Desktop Pictures/`. The default is `Wave.jpg`.
#rm -rf ${HOME}/Library/Application Support/Dock/desktoppicture.db
#sudo rm -rf /System/Library/CoreServices/DefaultDesktop.jpg
#sudo ln -s /path/to/your/image /System/Library/CoreServices/DefaultDesktop.jpg

###############################################################################
# TextEdit                                                                    #
###############################################################################

###############################################################################
# SSD-specific tweaks                                                         #
###############################################################################

if ask "Disable hibernation (speeds up entering sleep mode)" Y; then
  sudo pmset -a hibernatemode 0
fi

if ask "Disable the sudden motion sensor as it's not useful for SSDs" Y; then
  sudo pmset -a sms 0
fi

###############################################################################
# Trackpad, mouse, keyboard, Bluetooth accessories, and input                 #
###############################################################################

if ask "Enable Trackpad Gestures" Y; then
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
fi

if ask "Enable full keyboard access for all controls (e.g. enable Tab in modal dialogs)" Y; then
  defaults write -g AppleKeyboardUIMode -int 2
fi

if ask "Set language and text formats" Y; then
  # Note: if you're in the US, replace `EUR` with `USD`, `Centimeters` with
  # `Inches`, `en_GB` with `en_US`, and `true` with `false`.
  defaults write -g AppleLanguages -array "en-IN" "en"
  defaults write -g AppleLocale -string "en_IN@currency=INR"
  defaults write -g AppleMeasurementUnits -string "Centimeters"
  defaults write -g AppleMetricUnits -bool true
  defaults write -g AppleActionOnDoubleClick -string "Maximize"
fi

# Stop iTunes from responding to the keyboard media keys
# launchctl unload -w /System/Library/LaunchAgents/com.apple.rcd.plist 2> /dev/null

# Use scroll gesture with the Ctrl (^) modifier key to zoom
# defaults write com.apple.universalaccess closeViewScrollWheelToggle -bool true
# defaults write com.apple.universalaccess HIDScrollZoomModifierMask -int 262144
# Follow the keyboard focus while zoomed in
# defaults write com.apple.universalaccess closeViewZoomFollowsFocus -bool true


###############################################################################
# Finder                                                                      #
###############################################################################

if ask "Allow quitting Finder via ⌘ + Q; doing so will also hide desktop icons" Y; then
  defaults write com.apple.finder QuitMenuItem -bool true
fi

# if ask "Disable window animations and Get Info animations" Y; then
  # defaults write com.apple.finder DisableAllAnimations -bool true
# fi

if ask "Set Desktop as the default location for new Finder windows" Y; then
  # For other paths, use `PfLo` and `file:///full/path/here/`
  defaults write com.apple.finder NewWindowTarget -string "PfHm"
  defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"
fi

if ask "Show icons for hard drives, servers, and removable media on the desktop" Y; then
  defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
fi

# if ask "Show hidden files by default" N; then
  # defaults write com.apple.finder AppleShowAllFiles -bool false
# fi

if ask "Show all filename extensions" Y; then
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
fi

if ask "Display full POSIX path as Finder window title" Y; then
  defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
fi

if ask "Show status bar" Y; then
  defaults write com.apple.finder ShowStatusBar -bool true
fi

if ask "Start the status bar Path at ${HOME} (instead of Hard drive)" N; then
  defaults write /Library/Preferences/com.apple.finder PathBarRootAtHome -bool true
fi

if ask "Show path (breadcrumb) bar" Y; then
  defaults write com.apple.finder ShowPathbar -bool true
fi

if ask "Show preview pane" Y; then
  defaults write com.apple.finder ShowPreviewPane -bool false
fi

defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
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

if ask "Allowing text selection in Quick Look/Preview in Finder by default" Y; then
  defaults write com.apple.finder QLEnableTextSelection -bool true
fi

# if ask "Keep folders on top when sorting by name" Y; then
  # defaults write com.apple.finder _FXSortFoldersFirst -bool true
# fi

if ask "When performing a search, search the current folder by default (the default 'This Mac' is 'SCev')" Y; then
  defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
fi

if ask "Disable the warning when changing a file extension" Y; then
  defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
fi

# if ask "Enable spring loading for directories" Y; then
  # defaults write -g com.apple.springing.enabled -bool true
# fi

# if ask "Remove the delay for spring loading for directories" Y; then
  # defaults write -g com.apple.springing.delay -float 0
# fi

if ask "Enable snap-to-grid for icons on the desktop and in other icon views" Y; then
  /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" ${HOME}/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid" ${HOME}/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" ${HOME}/Library/Preferences/com.apple.finder.plist
fi

if ask "Increase grid spacing for icons on the desktop and in other icon views" Y; then
  /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:gridSpacing 54" ${HOME}/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:gridSpacing 54" ${HOME}/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:gridSpacing 54" ${HOME}/Library/Preferences/com.apple.finder.plist
fi

if ask "Increase the size of icons on the desktop and in other icon views" Y; then
  /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:iconSize 64" ${HOME}/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:iconSize 64" ${HOME}/Library/Preferences/com.apple.finder.plist
  /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:iconSize 64" ${HOME}/Library/Preferences/com.apple.finder.plist
fi

# Show item info near icons on the desktop and in other icon views
# /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:showItemInfo true" ${HOME}/Library/Preferences/com.apple.finder.plist
# /usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:showItemInfo true" ${HOME}/Library/Preferences/com.apple.finder.plist
# /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:showItemInfo true" ${HOME}/Library/Preferences/com.apple.finder.plist

# Show item info to the right of the icons on the desktop
# /usr/libexec/PlistBuddy -c "Set DesktopViewSettings:IconViewSettings:labelOnBottom false" ${HOME}/Library/Preferences/com.apple.finder.plist

# Enable snap-to-grid for icons on the desktop and in other icon views
# /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" ${HOME}/Library/Preferences/com.apple.finder.plist
# /usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid" ${HOME}/Library/Preferences/com.apple.finder.plist
# /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" ${HOME}/Library/Preferences/com.apple.finder.plist

# Increase grid spacing for icons on the desktop and in other icon views
# /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:gridSpacing 100" ${HOME}/Library/Preferences/com.apple.finder.plist
# /usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:gridSpacing 100" ${HOME}/Library/Preferences/com.apple.finder.plist
# /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:gridSpacing 100" ${HOME}/Library/Preferences/com.apple.finder.plist

# Increase the size of icons on the desktop and in other icon views
# /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:iconSize 80" ${HOME}/Library/Preferences/com.apple.finder.plist
# /usr/libexec/PlistBuddy -c "Set :FK_StandardViewSettings:IconViewSettings:iconSize 80" ${HOME}/Library/Preferences/com.apple.finder.plist
# /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:iconSize 80" ${HOME}/Library/Preferences/com.apple.finder.plist


if ask "Use list view in all Finder windows by default" Y; then
  # Four-letter codes for the other view modes: `icnv` (icon), `Nlsv` (list), `Flwv` (cover flow)
  defaults write com.apple.finder FXPreferredViewStyle -string "clmv"
  defaults write com.apple.finder SearchRecentsSavedViewStyle -string "clmv"
fi

if ask "Disable the warning before emptying the Trash" Y; then
  defaults write com.apple.finder WarnOnEmptyTrash -bool false
fi

if ask "Empty Trash securely by default" Y; then
  defaults write com.apple.finder EmptyTrashSecurely -bool true
fi

if ask "Show app-centric sidebar" Y; then
  defaults write com.apple.finder FK_AppCentricShowSidebar -bool true
fi

if ask "Automatically open a new Finder window when a volume is mounted" Y; then
  defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true
fi

if ask "Show the ${HOME}/Library folder" Y; then
  chflags nohidden ${HOME}/Library
fi

if ask "Enable the MacBook Air SuperDrive on any Mac" N; then
  sudo nvram boot-args="mbasd=1"
fi

if ask "Show the '/Volumes' folder" Y; then
  chflags nohidden /Volumes
fi

# Remove Dropbox's green checkmark icons in Finder
# file=/Applications/Dropbox.app/Contents/Resources/emblem-dropbox-uptodate.icns
# [ -e "${file}" ] && mv -fv "${file}" "${file}.bak"

if ask "Expand the following File Info panes: 'General', 'Open with', and 'Sharing & Permissions'" Y; then
  defaults write com.apple.finder FXInfoPanesExpanded -dict-add "General" -bool true
  defaults write com.apple.finder FXInfoPanesExpanded -dict-add "MetaData" -bool false
  defaults write com.apple.finder FXInfoPanesExpanded -dict-add "OpenWith" -bool true
  defaults write com.apple.finder FXInfoPanesExpanded -dict-add "Privileges" -bool true
fi

if ask "Windows which were open prior to logging out are re-opened after logging in" Y; then
  defaults write com.apple.finder RestoreWindowState -bool true
fi

# if ask "Location and style of scrollbar arrows" N; then
  # Applications often need to be relaunched to see the change.
  # defaults write -g AppleScrollBarVariant -string "DoubleBoth" true
# fi

# if ask "Disable window animations" N; then
  # defaults write -g NSAutomaticWindowAnimationsEnabled -bool false && killall Finder
# fi

# Avoiding the creation of .DS_Store files on network volumes
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

###############################################################################
# Energy saving                                                               #
###############################################################################

# Enable lid wakeup
sudo pmset -a lidwake 1

# Restart automatically on power loss
sudo pmset -a autorestart 1

# Restart automatically if the computer freezes
sudo systemsetup -setrestartfreeze on

# Sleep the display after 15 minutes
# sudo pmset -a displaysleep 15

# Disable machine sleep while charging
# sudo pmset -c sleep 0

# Set machine sleep to 5 minutes on battery
# sudo pmset -b sleep 5

# Set standby delay to 24 hours (default is 1 hour)
# sudo pmset -a standbydelay 86400

# Never go into computer sleep mode
# sudo systemsetup -setcomputersleep Off > /dev/null

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

###############################################################################
# Preview                                                                     #
###############################################################################
# if ask "Scale images by default when printing" N; then
  # defaults write com.apple.Preview PVImagePrintingScaleMode -bool true
# fi

# if ask "Preview Auto-rotate by default when printing" N; then
  # defaults write com.apple.Preview PVImagePrintingAutoRotate -bool true
# fi

# if ask "Quit Always Keeps Windows" Y; then
  # defaults write com.apple.Preview NSQuitAlwaysKeepsWindows -bool true
# fi

###############################################################################
# Keychain                                                                    #
###############################################################################

if ask "Keychain shows expired certificates" N; then
  defaults write com.apple.keychainaccess "Show Expired Certificates" -bool true
fi

if ask "Makes Keychain Access display *unsigned* ACL entries in italics" Y; then
  defaults write com.apple.keychainaccess "Distinguish Legacy ACLs" -bool true
fi

###############################################################################
# Remote Desktop                                                              #
###############################################################################

# if ask "Admin Console Allows Remote Control" N; then
#   defaults delete /Library/Preferences/com.apple.RemoteManagement AdminConsoleAllowsRemoteControl
# fi

# if ask "Disable Multicast" N; then
#   defaults write /Library/Preferences/com.apple.RemoteManagement ARD_MulticastAllowed -bool true
# fi

# if ask "Prevents system keys like command-tab from being sent" N; then
#   defaults write com.apple.RemoteDesktop DoNotSendSystemKeys -bool true
# fi

if ask "Show the Debug menu Remote Desktop" Y; then
  defaults write com.apple.remotedesktop IncludeDebugMenu -bool true
fi

if ask "Define user name display behavior" Y; then
  defaults write com.apple.remotedesktop showShortUserName -bool true
fi

# if ask "Set the maximum number of computers that can be observed: (up to 50 opposed to the default of 9)" Y; then
#   defaults write com.apple.RemoteDesktop multiObserveMaxPerScreen -int 9
# fi

###############################################################################
# Screen Sharing                                                              #
###############################################################################

# if ask "Prevent protection when attempting to remotely control this computer" N; then
#   defaults write com.apple.ScreenSharing skipLocalAddressCheck -bool true
# fi

# if ask "Disables system-level key combos like command-option-esc (Force Quit), command-tab (App switcher) to be used on the remote machine" N; then
#   defaults write com.apple.ScreenSharing DoNotSendSystemKeys -bool true
# fi

# if ask "Debug (To Show Bonjour)" N; then
#   defaults write com.apple.ScreenSharing debug -bool true
# fi

# if ask "Do Not Send Special Keys to Remote Machine" N; then
#   defaults write com.apple.ScreenSharing DoNotSendSystemKeys -bool true
# fi

# if ask "Skip local address check" N; then
#   defaults write com.apple.ScreenSharing skipLocalAddressCheck -bool true
# fi

# if ask "Screen sharing image quality" N; then
#   defaults write com.apple.ScreenSharing controlObserveQuality -int
# fi

# if ask "Number of recent hosts on ScreenSharingMenulet" N; then
#   defaults write com.klieme.ScreenSharingMenulet maxHosts -int
# fi

# if ask "Display IP-Addresses of the local hosts on ScreenSharingMenulet" N; then
#   defaults write com.klieme.ScreenSharingMenulet showIPAddresses -bool true
# fi

###############################################################################
# Dock, Dashboard, and hot corners                                            #
###############################################################################

if ask "Set the icon size of Dock items to 35 pixels" Y; then
  defaults write com.apple.dock tilesize -int 35
fi

if ask "Move the dock to the right side of the screen" Y; then
  defaults write com.apple.dock orientation -string "right"
fi

if ask "Minimize windows into their application's icon" Y; then
  defaults write com.apple.dock "minimize-to-application" -bool true
fi

if ask "Show only active apps in Dock" Y; then
  defaults write com.apple.dock "static-only" -bool true
fi

# if ask "Enable spring loading for all Dock items" Y; then
#   defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true
# fi

if ask "Enable highlight hover effect for the grid view of a stack (Dock)" Y; then
  defaults write com.apple.dock "mouse-over-hilte-stack" -bool true
fi

if ask "Show indicator lights for open applications in the Dock" Y; then
  defaults write com.apple.dock "show-process-indicators" -bool true
fi

if ask "Animate opening applications from the Dock" Y; then
  defaults write com.apple.dock launchanim -bool true
fi

if ask "Change minimize/maximize window effect" Y; then
  defaults write com.apple.dock mineffect -string "suck"
fi

if ask "Speed up Mission Control animations" Y; then
  defaults write com.apple.dock "expose-animation-duration" -float 0.5
fi

if ask "Don't group windows by application in Mission Control (i.e. use the old Exposé behavior instead)" N; then
  defaults write com.apple.dock "expose-group-by-app" -bool false
fi

if ask "Enable Mission Control" N; then
  defaults write com.apple.Dock "mcx-expose-disabled" -bool false
fi

if ask "Don't show Dashboard as a Space" N; then
  defaults write com.apple.dock "dashboard-in-overlay" -bool true
fi

if ask "Show image for notifications" Y; then
  defaults write com.apple.dock "notification-always-show-image" -bool true
fi

if ask "Enable the 2D Dock" N; then
  defaults write com.apple.dock "no-glass" -bool true
fi

if ask "Ensable Bouncing dock icons" Y; then
  defaults write com.apple.dock "no-bouncing" -bool false
fi

if ask "Disable multi-display swoosh animations" N; then
  defaults write com.apple.dock "workspaces-swoosh-animation-off" -bool false
fi

if ask "Remove the animation when hiding or showing the dock" Y; then
  defaults write com.apple.dock "autohide-time-modifier" -float 0
fi

if ask "Enable iTunes pop-up notifications" N; then
  defaults write com.apple.dock "itunes-notifications" -boolean false
fi

# if ask "Add a 'Recent Applications' stack to the Dock" N; then
  # defaults write com.apple.dock persistent-others -array-add '{ "tile-data" = { "list-type" = 1; }; "tile-type" = "recents-tile"; }'
# fi

if ask "In Expose, only show windows from the current space" N; then
  defaults write com.apple.dock "wvous-show-windows-in-other-spaces" -bool false
fi

if ask "Automatically rearrange Spaces based on most recent use" Y; then
  defaults write com.apple.dock "mru-spaces" -bool true
fi

if ask "Remove the auto-hiding Dock delay" N; then
  defaults write com.apple.dock "autohide-delay" -float 0
fi

if ask "Automatically hide and show the Dock" Y; then
  defaults write com.apple.dock autohide -bool true
fi

if ask "Automatically magnify the Dock" Y; then
  defaults write com.apple.dock magnification -bool true
fi

if ask "Make Dock icons of hidden applications translucent" Y; then
  defaults write com.apple.dock showhidden -bool true
fi

if ask "Enable highlight hover effect for the grid view of a stack (Dock)" Y; then
  defaults write com.apple.dock mouse-over-hilite-stack -bool true
fi

if ask "Enable the 'reopen windows when logging back in' option" Y; then
  # This works, although the checkbox will still appear to be checked.
  defaults write com.apple.loginwindow TALLogoutSavesState -bool true
  defaults write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -bool true
fi

###############################################################################
# Launchpad                                                                   #
###############################################################################
if ask "Number of columns and rows in the dock springboard set to 10" Y; then
  defaults write com.apple.dock springboard-rows -int 10
  defaults write com.apple.dock springboard-columns -int 10
fi
# defaults write com.apple.dock ResetLaunchPad -bool true

if ask "Disable the Launchpad gesture (pinch with thumb and three fingers)" N; then
  defaults write com.apple.dock showLaunchpadGestureEnabled -int 0
fi

# Add iOS & Watch Simulator to Launchpad
# sudo ln -sf "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app" "/Applications/Simulator.app"
# sudo ln -sf "/Applications/Xcode.app/Contents/Developer/Applications/Simulator (Watch).app" "/Applications/Simulator (Watch).app"

# Add a spacer to the left side of the Dock (where the applications are)
# defaults write com.apple.dock persistent-apps -array-add '{tile-data={}; tile-type="spacer-tile";}'
# Add a spacer to the right side of the Dock (where the Trash is)
# defaults write com.apple.dock persistent-others -array-add '{tile-data={}; tile-type="spacer-tile";}'

if ask "Hot corners" Y; then
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

###############################################################################
# Safari & WebKit                                                             #
###############################################################################

if ask "Privacy: don't send search queries to Apple" Y; then
  defaults write com.apple.Safari UniversalSearchEnabled -bool false
  defaults write com.apple.Safari SuppressSearchSuggestions -bool true
fi

# if ask "Press Tab to highlight each item on a web page" N; then
#   defaults write com.apple.Safari WebKitTabToLinksPreferenceKey -bool true
#   defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2TabsToLinks -bool true
# fi

if ask "Show the full URL in the address bar (note: this still hides the scheme)" Y; then
  defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
fi

if ask "Set Safari's home page to 'about:blank' for faster loading" Y; then
  defaults write com.apple.Safari HomePage -string "about:blank"
fi

if ask "Prevent Safari from opening 'safe' files automatically after downloading" Y; then
  defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
fi

if ask "Allow hitting the Backspace key to go to the previous page in history" Y; then
  defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled -bool true
fi

if ask "Hide Safari's bookmarks bar by default" Y; then
  defaults write com.apple.Safari ShowFavoritesBar -bool false
  defaults write com.apple.Safari "ShowFavoritesBar-v2" -bool false
fi

if ask "Hide Safari's sidebar in Top Sites" Y; then
  defaults write com.apple.Safari ShowSidebarInTopSites -bool false
fi

if ask "Disable Safari's thumbnail cache for History and Top Sites" Y; then
  defaults write com.apple.Safari DebugSnapshotsUpdatePolicy -int 2
fi

if ask "Enable Safari's debug menu" Y; then
  defaults write com.apple.Safari IncludeInternalDebugMenu -bool true
fi

if ask "Make Safari's search banners default to Contains instead of Starts With" Y; then
  defaults write com.apple.Safari FindOnPageMatchesWordStartsOnly -bool false
fi

if ask "Remove useless icons from Safari's bookmarks bar" Y; then
  defaults write com.apple.Safari ProxiesInBookmarksBar "()"
fi

if ask "Warn about fraudulent websites" Y; then
  defaults write com.apple.Safari WarnAboutFraudulentWebsites -bool true
fi

if ask "Block pop-up windows" Y; then
  defaults write com.apple.Safari WebKitJavaScriptCanOpenWindowsAutomatically -bool false
  defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically -bool false
fi

if ask "Disable auto-playing video" Y; then
  defaults write com.apple.Safari WebKitMediaPlaybackAllowsInline -bool false
  defaults write com.apple.SafariTechnologyPreview WebKitMediaPlaybackAllowsInline -bool false
  defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false
  defaults write com.apple.SafariTechnologyPreview com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false
fi

if ask "Enable 'Do Not Track'" Y; then
  defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true
fi

if ask "Enable the Develop menu and the Web Inspector in Safari" Y; then
  defaults write com.apple.Safari IncludeDevelopMenu -bool true
  defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
  defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
fi

# Requires Safari 5.0.1 or later. Feature that is intended to increase the speed at which pages load. DNS (Domain Name System) prefetching kicks in when you load a webpage that contains links to other pages. As soon as the initial page is loaded, Safari 5.0.1 (or later) begins resolving the listed links' domain names to their IP addresses. Prefetching can occasionally result in 'slow performance, partially-loaded pages, or webpage 'cannot be found' messages.”
if ask "Increase page load speed in Safari" Y; then
  defaults write com.apple.safari WebKitDNSPrefetchingEnabled -bool true
fi

if ask "Disable Data Detectors" Y; then
  defaults write com.apple.Safari WebKitUsesEncodingDetector -bool false
fi

if ask "Google Suggestion" Y; then
  defaults write com.apple.safari DebugSafari4IncludeGoogleSuggest -bool true
fi

if ask "Automatically spell check web forms" Y; then
  defaults write com.apple.safari WebContinuousSpellCheckingEnabled -bool true
fi

if ask "Automatically grammar check web forms" Y; then
  defaults write com.apple.safari WebGrammarCheckingEnabled -bool true
fi

if ask "Include page background colors and images when printing" N; then
  defaults write com.apple.safari WebKitShouldPrintBackgroundsPreferenceKey -bool true
fi

if ask "Enable developer menu in Safari" Y; then
  defaults write com.apple.Safari IncludeDebugMenu -bool true
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
#defaults write com.apple.Safari WebKitMediaPlaybackAllowsInline -bool false
#defaults write com.apple.SafariTechnologyPreview WebKitMediaPlaybackAllowsInline -bool false
#defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false
#defaults write com.apple.SafariTechnologyPreview com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback -bool false

# Enable “Do Not Track”
# defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true

# Update extensions automatically
# defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true

###############################################################################
# Mail                                                                        #
###############################################################################

# Disable send and reply animations in Mail.app
# defaults write com.apple.mail DisableReplyAnimations -bool true
# defaults write com.apple.mail DisableSendAnimations -bool true

# Copy email addresses as `foo@example.com` instead of `Foo Bar <foo@example.com>` in Mail.app
# defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false

# Add the keyboard shortcut ⌘ + Enter to send an email in Mail.app
# defaults write com.apple.mail NSUserKeyEquivalents -dict-add "Send" "@\U21a9"

# Display emails in threaded mode, sorted by date (oldest at the top)
# defaults write com.apple.mail DraftsViewerAttributes -dict-add "DisplayInThreadedMode" -string "yes"
# defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortedDescending" -string "yes"
# defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortOrder" -string "received-date"

# Disable inline attachments (just show the icons)
# defaults write com.apple.mail DisableInlineAttachmentViewing -bool true

# Disable automatic spell checking
# defaults write com.apple.mail SpellCheckingBehavior -string "NoSpellCheckingEnabled"

###############################################################################
# iMessage                                                                    #
###############################################################################

if ask "Automatically go away after the specified time period" N; then
  defaults write com.apple.ichat AutoAway -bool true
fi

if ask "Disable iChat Data Detectors which help locate e-mails, dates, and other data tidbits" N; then
  defaults write com.apple.ichat EnableDataDetectors -bool false
fi

###############################################################################
# Parallels                                                                   #
###############################################################################

if ask "Disable Advertisments" Y; then
  defaults write com.parallels.Parallels\ Desktop ProductPromo.ForcePromoOff -bool true
fi

###############################################################################
# Mail                                                                        #
###############################################################################

if ask "Display emails in threaded mode, sorted by date (oldest at the top)" Y; then
  defaults write com.apple.mail DraftsViewerAttributes -dict-add "DisplayInThreadedMode" -string "yes"
  defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortedDescending" -string "yes"
  defaults write com.apple.mail DraftsViewerAttributes -dict-add "SortOrder" -string "received-date"
fi

if ask "Disable automatic spell checking" N; then
  defaults write com.apple.mail SpellCheckingBehavior -string "NoSpellCheckingEnabled"
fi

if ask "Copy email addresses as 'foo@example.com' instead of 'Foo Bar <foo@example.com>'' in Mail.app" N; then
  defaults write com.apple.mail AddressesIncludeNameOnPasteboard -bool false
fi

if ask "Disable send and reply animations in Mail.app" N; then
  defaults write com.apple.Mail DisableReplyAnimations -bool true
  defaults write com.apple.Mail DisableSendAnimations -bool true
fi

if ask "Set a minimum font size of 14px (affects reading and sending email)" N; then
  defaults write com.apple.mail MinimumHTMLFontSize 14
fi

if ask "Force all Mail messages to display as plain text" N; then
  # For rich text (the default) set it to FALSE
  defaults write com.apple.mail PreferPlainText -bool TRUE
fi

if ask "Disable tracking of Previous Recipients" N; then
  defaults write com.apple.mail SuppressAddressHistory -bool true
fi

if ask "Send Windows friendly attachments" N; then
  defaults write com.apple.mail SendWindowsFriendlyAttachments -bool true
fi

###############################################################################
# Spotlight                                                                   #
###############################################################################

if ask "Disable Spotlight indexing for any volume that gets mounted and has not yet been indexed before." N; then
  # Use `sudo mdutil -i off "/Volumes/foo"` to stop indexing any volume.
  sudo defaults write /.Spotlight-V100/VolumeConfiguration Exclusions -array "/Volumes"
fi

if ask "Change indexing order and disable some search results" Y; then
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

if ask "Load new settings before rebuilding the index" Y; then
  killall mds > /dev/null 2>&1
fi

if ask "Make sure indexing is enabled for the main volume" Y; then
  sudo mdutil -i on / > /dev/null
fi

if ask "Rebuild the index from scratch" Y; then
  sudo mdutil -E / > /dev/null
fi

###############################################################################
# Apple Multitouch Mouse                                                      #
###############################################################################
if ask "Apple Multitouch mouse features" Y; then
  defaults write com.apple.AppleMultitouchMouse MouseButtonMode -string "OneButton"
  defaults write com.apple.AppleMultitouchMouse MouseHorizontalScroll -int 1
  defaults write com.apple.AppleMultitouchMouse MouseMomentumScroll -int 1
  defaults write com.apple.AppleMultitouchMouse MouseOneFingerDoubleTapGesture -int 0
  defaults write com.apple.AppleMultitouchMouse MouseTwoFingerDoubleTapGesture -int 3
  defaults write com.apple.AppleMultitouchMouse MouseTwoFingerHorizSwipeGesture -int 2
  defaults write com.apple.AppleMultitouchMouse MouseVerticalScroll -int 1
  defaults write com.apple.AppleMultitouchMouse UserPreferences -int 1
fi

###############################################################################
# Apple Multitouch Trackpad                                                   #
###############################################################################
if ask "Apple Multitouch trackpad features" Y; then
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
fi

###############################################################################
# Terminal                                                                    #
###############################################################################

if ask "New window opens in the same directory as the current window" Y; then
  defaults write com.apple.Terminal NewWindowWorkingDirectoryBehavior -int 2
fi

if ask "Disable Secure Keyboard Entry in Terminal.app" Y; then
  # (see: https://security.stackexchange.com/a/47786/8918)
  defaults write com.apple.Terminal SecureKeyboardEntry -bool false
  defaults write com.apple.Terminal Shell -string ""
  defaults write com.apple.Terminal "Default Window Settings" -string Basic
  defaults write com.apple.Terminal "Startup Window Settings" -string Basic
fi

# Disable the annoying line marks
# defaults write com.apple.Terminal ShowLineMarks -int 0

# Note: To print the values, use this:
# /usr/libexec/PlistBuddy -c "Print :'Window Settings':Basic" ${HOME}/Library/Preferences/com.apple.Terminal.plist
profile_array=(Basic Pro)
for profile in "${profile_array[@]}"; do
  # Close the window if the shell exited cleanly - TODO: These error out and stop the whole file from being executed - need to fix
  # /usr/libexec/PlistBuddy -c "Delete :'Window Settings':$profile:shellExitAction" ${HOME}/Library/Preferences/com.apple.Terminal.plist
  # /usr/libexec/PlistBuddy -c "Add :'Window Settings':$profile:shellExitAction integer 1" ${HOME}/Library/Preferences/com.apple.Terminal.plist

  if ask "Set window size in Terminal.app" Y; then
    /usr/libexec/PlistBuddy -c "Delete :'Window Settings':$profile:rowCount" ${HOME}/Library/Preferences/com.apple.Terminal.plist
    /usr/libexec/PlistBuddy -c "Add :'Window Settings':$profile:rowCount integer 48" ${HOME}/Library/Preferences/com.apple.Terminal.plist
    /usr/libexec/PlistBuddy -c "Delete :'Window Settings':$profile:columnCount" ${HOME}/Library/Preferences/com.apple.Terminal.plist
    /usr/libexec/PlistBuddy -c "Add :'Window Settings':$profile:columnCount integer 160" ${HOME}/Library/Preferences/com.apple.Terminal.plist
  fi

  if ask "do not close the window if these programs are running" Y; then
    /usr/libexec/PlistBuddy -c "Delete :'Window Settings':$profile:noWarnProcesses" ${HOME}/Library/Preferences/com.apple.Terminal.plist
    /usr/libexec/PlistBuddy -c "Add :'Window Settings':$profile:noWarnProcesses array" ${HOME}/Library/Preferences/com.apple.Terminal.plist
    /usr/libexec/PlistBuddy -c "Add :'Window Settings':$profile:noWarnProcesses:0:ProcessName string screen" ${HOME}/Library/Preferences/com.apple.Terminal.plist
    /usr/libexec/PlistBuddy -c "Add :'Window Settings':$profile:noWarnProcesses:1:ProcessName string tmux" ${HOME}/Library/Preferences/com.apple.Terminal.plist
    /usr/libexec/PlistBuddy -c "Add :'Window Settings':$profile:noWarnProcesses:2:ProcessName string rlogin" ${HOME}/Library/Preferences/com.apple.Terminal.plist
    /usr/libexec/PlistBuddy -c "Add :'Window Settings':$profile:noWarnProcesses:3:ProcessName string ssh" ${HOME}/Library/Preferences/com.apple.Terminal.plist
    /usr/libexec/PlistBuddy -c "Add :'Window Settings':$profile:noWarnProcesses:4:ProcessName string slogin" ${HOME}/Library/Preferences/com.apple.Terminal.plist
    /usr/libexec/PlistBuddy -c "Add :'Window Settings':$profile:noWarnProcesses:5:ProcessName string telnet" ${HOME}/Library/Preferences/com.apple.Terminal.plist
  fi
done

# Focus follows Mouse
# defaults write com.apple.Terminal FocusFollowsMouse -bool true

###############################################################################
# iTerm 2                                                                     #
###############################################################################

# TODO: Need to set the keyboard overrides for "back/forward 1 word" AND "Jobs to Ignore"
if ask "iTerm2 settings" Y; then
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
  defaults write com.googlecode.iterm2 SUFeedAlternateAppNameKey -string iTerm;
  defaults write com.googlecode.iterm2 SUFeedURL -string "https://iterm2.com/appcasts/final.xml?shard=69"
  defaults write com.googlecode.iterm2 SUHasLaunchedBefore -bool true
  defaults write com.googlecode.iterm2 SUUpdateRelaunchingMarker -bool false
  defaults write com.googlecode.iterm2 SavePasteHistory -bool false
  defaults write com.googlecode.iterm2 ShowBookmarkName -bool false
  defaults write com.googlecode.iterm2 SplitPaneDimmingAmount -string "0.4070612980769232"
  defaults write com.googlecode.iterm2 StatusBarPosition -integer 1
  defaults write com.googlecode.iterm2 SuppressRestartAnnouncement -bool true
  defaults write com.googlecode.iterm2 TabStyleWithAutomaticOption -integer 4
  defaults write com.googlecode.iterm2 TraditionalVisualBell -bool true
  defaults write com.googlecode.iterm2 UseBorder -bool true
  defaults write com.googlecode.iterm2 WordCharacters -string "/-+\\\\~-integer."
  defaults write com.googlecode.iterm2 findMode_iTerm -bool false
  defaults write com.googlecode.iterm2 kCPKSelectionViewPreferredModeKey -bool false
  defaults write com.googlecode.iterm2 kCPKSelectionViewShowHSBTextFieldsKey -bool false

  # TODO: Need to set up the font settings for font in iTerm2
  # TODO: Need to set up the "Natural text editing" preset in Profiles > Keys preference pane for iTerm2
  # TODO: Need to set up the status bar layout and prefs in iTerm2

  # Note: To print the values, use this:
  # /usr/libexec/PlistBuddy -c "Print :'New Bookmarks':0:'Jobs to Ignore'" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks' array" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist # Note: This is a naive way to ensure that the array is present on newly images OS
  /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:Rows" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:Rows integer 48" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist

  /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:Columns" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:Columns integer 160" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist

  /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Silence Bell'" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Silence Bell' bool false" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist

  /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Unlimited Scrollback'" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Unlimited Scrollback' bool true" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist

  /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Use Cursor Guide'" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Use Cursor Guide' bool true" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist

  /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Visual Bell'" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Visual Bell' bool true" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist

  /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Jobs to Ignore'" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore' array" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':0 string screen" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':1 string tmux" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':2 string rlogin" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':3 string ssh" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':4 string slogin" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':5 string telnet" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Jobs to Ignore':5 string zsh" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist

  /usr/libexec/PlistBuddy -c "Delete :'New Bookmarks':0:'Minimum Contrast'" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
  /usr/libexec/PlistBuddy -c "Add :'New Bookmarks':0:'Minimum Contrast' integer 0" ${HOME}/Library/Preferences/com.googlecode.iterm2.plist
fi

# TODO: Need to add these - stopping due to time constraints
# {
#     "New Bookmarks" =     (
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


###############################################################################
# AppCleaner                                                                  #
###############################################################################
if ask "AppCleaner settings" Y; then
  defaults write net.freemacsoft.AppCleaner SUAutomaticallyUpdate -bool true
  defaults write net.freemacsoft.AppCleaner SUEnableAutomaticChecks -bool true
  defaults write net.freemacsoft.AppCleaner SUSendProfileInfo -bool false
fi

###############################################################################
# Hour - World Clock                                                          #
###############################################################################
# TODO: Capture all settings

###############################################################################
# Docker - TODO: Should we replace this with podman-equivalent?               #
###############################################################################
if ask "Docker settings" Y; then
  defaults write com.docker.docker SUAutomaticallyUpdate -bool true
  defaults write com.docker.docker SUEnableAutomaticChecks -bool true
  defaults write com.docker.docker SUUpdateRelaunchingMarker -bool true
fi

###############################################################################
# Firefox-nightly                                                             #
###############################################################################
if ask "Firefox settings" Y; then
  defaults write -app "Firefox Nightly" NSFullScreenMenuItemEverywhere -bool false
  defaults write -app "Firefox Nightly" NSNavLastRootDirectory -string "${HOME}/Downloads";
  defaults write -app "Firefox Nightly" NSNavLastUserSetHideExtensionButtonState -bool false
  defaults write -app "Firefox Nightly" NSTreatUnknownArgumentsAsOpen -bool false
  defaults write -app "Firefox Nightly" PMPrintingExpandedStateForPrint2 -bool false
fi

###############################################################################
# Flycut                                                                      #
###############################################################################
if ask "Flycut settings" N; then
  defaults write com.generalarcade.flycut loadOnStartup -bool true
  defaults write com.generalarcade.flycut pasteMovesToTop -bool true
  defaults write com.generalarcade.flycut rememberNum -int 60;
  defaults write com.generalarcade.flycut removeDuplicates -bool true
  defaults write com.generalarcade.flycut store -dict-add displayLen -int 40
  defaults write com.generalarcade.flycut store -dict-add displayNum -int 10
  defaults write com.generalarcade.flycut store -dict-add favoritesRememberNum -int 40
  defaults write com.generalarcade.flycut store -dict-add rememberNum -int 60
fi

###############################################################################
# Maccy                                                                       #
###############################################################################
if ask "Maccy settings" Y; then
  defaults write org.p0deje.Maccy historySize -int 300
  defaults write org.p0deje.Maccy ignoredApps -array "org.keepassxc.keepassxc"
  defaults write org.p0deje.Maccy pasteByDefault -bool true
  defaults write org.p0deje.Maccy removeFormattingByDefault -bool true
  defaults write org.p0deje.Maccy showRecentCopyInMenuBar -bool false
  defaults write org.p0deje.Maccy searchMode -string "mixed"
fi

###############################################################################
# Google Chrome & Google Chrome Canary                                        #
###############################################################################
if ask "Chrome settings" Y; then
  defaults write com.google.Chrome AppleEnableMouseSwipeNavigateWithScrolls -bool false
  defaults write com.google.Chrome AppleEnableSwipeNavigateWithScrolls -bool false
  defaults write com.google.Chrome KeychainReauthorizeInAppSpring2017 -int 2
  defaults write com.google.Chrome KeychainReauthorizeInAppSpring2017Success -bool true

  # Disable the all too sensitive backswipe on trackpads
  defaults write com.google.Chrome AppleEnableSwipeNavigateWithScrolls -bool false
  defaults write com.google.Chrome.canary AppleEnableSwipeNavigateWithScrolls -bool false

  # Disable the all too sensitive backswipe on Magic Mouse
  defaults write com.google.Chrome AppleEnableMouseSwipeNavigateWithScrolls -bool false
  defaults write com.google.Chrome.canary AppleEnableMouseSwipeNavigateWithScrolls -bool false

  # Allow installing user scripts via GitHub or Userscripts.org
  # defaults write com.google.Chrome ExtensionInstallSources -array "https://*.github.com/*" "http://userscripts.org/*"
  # defaults write com.google.Chrome.canary ExtensionInstallSources -array "https://*.github.com/*" "http://userscripts.org/*"
fi

###############################################################################
# ImageOptim                                                                  #
###############################################################################
if ask "ImageOptim settings" Y; then
  defaults write net.pornel.ImageOptim AdvPngLevel -int 5
  defaults write net.pornel.ImageOptim JpegOptimMaxQuality -int 85
  defaults write net.pornel.ImageOptim GuetzliEnabled -bool false
  defaults write net.pornel.ImageOptim PngCrush2Enabled -bool true
  defaults write net.pornel.ImageOptim SvgoEnabled -bool true
  defaults write net.pornel.ImageOptim JpegTranStripAll -bool false
  defaults write net.pornel.ImageOptim JpegTranStripAllSetByGuetzli -bool false
fi

###############################################################################
# KeepassXC                                                                   #
###############################################################################
if ask "KeepassXC settings" Y; then
  defaults write org.keepassxc.keepassxc "NSNavLastRootDirectory" -string "${HOME}/personal/$(whoami)"
fi

###############################################################################
# Rectangle                                                                   #
###############################################################################
if ask "Rectangle settings" Y; then
  defaults write com.knollsoft.Rectangle SUEnableAutomaticChecks -bool true
  defaults write com.knollsoft.Rectangle SUHasLaunchedBefore -bool true
  defaults write com.knollsoft.Rectangle alternateDefaultShortcuts -bool true
  defaults write com.knollsoft.Rectangle launchOnLogin -bool true
  defaults write com.knollsoft.Rectangle subsequentExecutionMode -bool true
fi

###############################################################################
# KeepingYouAwake                                                             #
###############################################################################
if ask "KeepingYouAwake settings" Y; then
  defaults write info.marcel-dierkes.KeepingYouAwake "info.marcel-dierkes.KeepingYouAwake.BatteryCapacityThreshold" -int 20
  defaults write info.marcel-dierkes.KeepingYouAwake "info.marcel-dierkes.KeepingYouAwake.BatteryCapacityThresholdEnabled" -bool true
fi

###############################################################################
# Monolingual                                                                 #
###############################################################################
if ask "Monolingual settings" Y; then
  defaults write net.sourceforge.Monolingual SUAutomaticallyUpdate -bool true
  defaults write net.sourceforge.Monolingual SUEnableAutomaticChecks -bool true
  defaults write net.sourceforge.Monolingual SUSendProfileInfo -bool false
  defaults write net.sourceforge.Monolingual Strip -bool true
fi

###############################################################################
# ProtonVpn                                                                   #
###############################################################################
if ask "ProtonVpn settings" Y; then
  defaults write ch.protonvpn.mac ConnectOnDemand -bool true
  defaults write ch.protonvpn.mac EarlyAccess -bool true
  defaults write ch.protonvpn.mac NSInitialToolTipDelay -int 500;
  defaults write ch.protonvpn.mac RememberLoginAfterUpdate -bool true
  defaults write ch.protonvpn.mac SUAutomaticallyUpdate -bool true
  defaults write ch.protonvpn.mac SUEnableAutomaticChecks -bool false
  defaults write ch.protonvpn.mac SecureCoreToggle -bool false
  defaults write ch.protonvpn.mac StartMinimized -bool true
  defaults write ch.protonvpn.mac StartOnBoot -bool true
  defaults write ch.protonvpn.mac SystemNotifications -bool true
fi

###############################################################################
# Rambox                                                                      #
###############################################################################
# if ask "Rambox settings" Y; then
#   defaults write com.grupovrs.ramboxce NSFullScreenMenuItemEverywhere -bool false
#   defaults write com.grupovrs.ramboxce NSNavLastRootDirectory -string "${HOME}/Downloads"
#   defaults write com.grupovrs.ramboxce NSNavLastUserSetHideExtensionButtonState -bool false
#   defaults write com.grupovrs.ramboxce NSTreatUnknownArgumentsAsOpen -bool false
# fi

###############################################################################
# Spectacle                                                                   #
###############################################################################
# if ask "Spectacle settings" Y; then
#   defaults write com.divisiblebyzero.Spectacle SUEnableAutomaticChecks -bool true
# fi

###############################################################################
# The-unarchiver                                                              #
###############################################################################
if ask "The-unarchiver settings" Y; then
  defaults write com.macpaw.site.theunarchiver SUEnableAutomaticChecks -bool true
  defaults write com.macpaw.site.theunarchiver changeDateOfFiles -bool true
  defaults write com.macpaw.site.theunarchiver deleteExtractedArchive -bool false
  defaults write com.macpaw.site.theunarchiver folderModifiedDate -int 2
  defaults write com.macpaw.site.theunarchiver openExtractedFolder -bool true
  # defaults write com.macpaw.site.theunarchiver userAgreedToNewTOSAndPrivacy -bool true
fi

###############################################################################
# Thunderbird-beta                                                            #
###############################################################################
if ask "Thunderbird settings" Y; then
  defaults write org.mozilla.thunderbird NSFullScreenMenuItemEverywhere -bool false
  defaults write org.mozilla.thunderbird NSTreatUnknownArgumentsAsOpen -bool false
fi

###############################################################################
# Vlc                                                                         #
###############################################################################
if ask "Vlc settings" Y; then
  defaults write org.videolan.vlc.plist AudioEffectSelectedProfile -int 0
  defaults write org.videolan.vlc.plist SUEnableAutomaticChecks -bool true
  defaults write org.videolan.vlc.plist VideoEffectSelectedProfile -int 0
  defaults write org.videolan.vlc.plist language -string auto
fi

###############################################################################
# Zoomus                                                                      #
###############################################################################
if ask "Zoomus settings" Y; then
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

###############################################################################
# Activity Monitor                                                            #
###############################################################################

if ask "Show the main window when launching Activity Monitor" Y; then
  defaults write com.apple.ActivityMonitor OpenMainWindow -bool true
fi

if ask "Visualize CPU usage in the Dock icon" Y; then
  defaults write com.apple.ActivityMonitor IconType -int 5
fi

if ask "Show all processes hierarchically" Y; then
  defaults write com.apple.ActivityMonitor ShowCategory -int 101
fi

if ask "Sort Activity Monitor results by CPU usage" Y; then
  defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
  defaults write com.apple.ActivityMonitor SortDirection -int 0
fi

if ask "default to showing the Memory tab" Y; then
  defaults write com.apple.ActivityMonitor SelectedTab -int 1
fi

###############################################################################
# Photos                                                                      #
###############################################################################

if ask "Prevent Photos from opening automatically when devices are plugged in" Y; then
  defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true
fi

###############################################################################
# Messages                                                                    #
###############################################################################

# Disable automatic emoji substitution (i.e. use plain text smileys)
# defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticEmojiSubstitutionEnablediMessage" -bool false

# Disable smart quotes as it's annoying for messages that contain code
# defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "automaticQuoteSubstitutionEnabled" -bool false

# Disable continuous spell checking
# defaults write com.apple.messageshelper.MessageController SOInputLineSettings -dict-add "continuousSpellCheckingEnabled" -bool false


###############################################################################
# Software Update                                                             #
###############################################################################
if ask "Automatically check for updates (required for any downloads)" Y; then
  defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
fi

if ask "Download updates automatically in the background" Y; then
  sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
fi

if ask "Install app updates automatically" Y; then
  defaults write com.apple.commerce AutoUpdate -bool true
fi

if ask "Install macos updates automatically" Y; then
  defaults write com.apple.commerce AutoUpdateRestartRequired -bool true
fi

if ask "Install system data file updates automatically" Y; then
  defaults write com.apple.SoftwareUpdate ConfigDataInstall -bool true
fi

if ask "Install critical security updates automatically" Y; then
  defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -bool true
fi

if ask "Check for software updates daily, not just once per week" Y; then
  defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1
fi

if ask "Download newly available updates in background" Y; then
  defaults write com.apple.SoftwareUpdate AutomaticDownload -bool true
fi

###############################################################################
# Mac App Store                                                               #
###############################################################################

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

###############################################################################
# Time Machine                                                                #
###############################################################################

# Prevent Time Machine from prompting to use new hard drives as backup volume
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

# Disable local Time Machine backups
# TODO: This causes an error to be printed to stdout - need to investigate if this is deprecated
# hash tmutil &> /dev/null && sudo tmutil disablelocal

# Auto backup:
# defaults write com.apple.TimeMachine AutoBackup =1

# Backup frequency default= 3600 seconds (every hour) 1800 = 1/2 hour, 7200=2 hours
# sudo defaults write /System/Library/Launch Daemons/com.apple.backupd-auto StartInterval -int 1800

###############################################################################
# Screen                                                                      #
###############################################################################
# Require password immediately after sleep or screen saver begins
defaults write com.apple.screensaver askForPassword -bool true
defaults write com.apple.screensaver askForPasswordDelay -int 0

# Enable subpixel font rendering on non-Apple LCDs (0=off, 1=light, 2=Medium/flat panel, 3=strong/blurred)
# This is mostly needed for non-Apple displays.
defaults write -g AppleFontSmoothing -int 2

# Enable HiDPI display modes (requires restart)
sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true

###############################################################################
# Screen capture                                                              #
###############################################################################

# Save screenshots to the desktop
defaults write com.apple.screencapture location -string "${HOME}/Desktop"

# Save screenshots in PNG format (other options: BMP, GIF, JPG, PDF, TIFF)
defaults write com.apple.screencapture type -string "png"

# Disable shadow in screenshots
# defaults write com.apple.screencapture disable-shadow -bool true

# Screenshot thumbnail expires in 15 secs
defaults write com.apple.screencaptureui thumbnailExpiration -float 15

###############################################################################
# iCal                                                                        #
###############################################################################
# Log HTTP Activity:
# defaults write com.apple.iCal LogHTTPActivity -bool true

###############################################################################
# Address Book                                                                #
###############################################################################

# Show Contact Reflection:
# defaults write com.apple.AddressBook reflection -boolean
defaults write com.apple.AddressBook ABBirthDayVisible -bool true
defaults write com.apple.AddressBook ABDefaultAddressCountryCode -string in

###############################################################################
# iTunes 10                                                                   #
###############################################################################
# Make the arrows next to artist & album jump to local iTunes library folders instead of Store:
# defaults write com.apple.iTunes show-store-link-arrows -bool true
# defaults write com.apple.iTunes invertStoreLinks -bool true

# Restore the standard close/minimise buttons:
# defaults write com.apple.iTunes full-window -1

# Hide the iTunes Genre list:
# defaults write com.apple.iTunes show-genre-when-browsing -bool false

###############################################################################
# OmniGraffle                                                                 #
###############################################################################

# Allow scroll wheel zooming:
# defaults write com.omnigroup.OmniGraffle DisableScrollWheelZooming -bool false

# Allow scroll wheel zooming in OmniGrafflePro:
# defaults write com.omnigroup.OmniGrafflePro DisableScrollWheelZooming -bool false

###############################################################################
# Quick Time Player                                                           #
###############################################################################

# Automatically show Closed Captions (CC) when opening a Movie:
# defaults -currentHost write com.apple.QuickTimePlayerX.plist MGEnableCCAndSubtitlesOnOpen -boolean

###############################################################################
## Spaces                                                                     #
###############################################################################

# When switching applications, switch to respective space
defaults write -g AppleSpacesSwitchOnActivate -bool true

###############################################################################
# Kill affected applications                                                  #
###############################################################################

app_array=(
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
  killall "${app}" &> /dev/null
done

sudo softwareupdate --schedule ON

echo "Need to manually quit and restart 'Terminal' and 'iTerm' - since one of these might be running this script."
echo "Done. Note that some of these changes require a logout/restart to take effect."
