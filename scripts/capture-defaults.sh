#!/usr/bin/env zsh

# file location: <anywhere; but advisable in the PATH>

# This script will capture (export) the settings or import the settings from the location specified in the $TARGET_DIR env var defined down below. You can back the files up to any cloud storage and retrieve into the new laptop to then get back all settings as per the original machine. The only word of caution is to use it with the same OS version (I haven't tried in any situations where the old and new machines had different OS versions - so I cannot guarantee if that might break the system in any way)

# A trick to find the name of the app:
# Run `defaults read` in an empty window of a terminal app, then use the search functionality to search for a known word related to that app (like eg app visible name, author, some setting that's unique to that app, etc). Once you find this, trace back to the left-most child (1st of the top-level parent) in the printed JSON to then get the real unique name of the app where its settings are stored.

type warn &> /dev/null 2>&1 || source "${HOME}/.shellrc"

usage() {
  echo "$(red "Usage"): $(yellow "${0} <e/i>")"
  echo "  $(yellow "e")  --> Export from system"
  echo "  $(yellow "i")  --> Import into system"
  exit 1
}

[ $# -ne 1 ] && usage

TARGET_DIR="${PERSONAL_CONFIGS_DIR}/defaults"

case "${1}" in
  "e" )
    operation="export"
    git_cleanup="git -C ${HOME} rm -rf ${TARGET_DIR}/*"
    git_stage="git -C ${HOME} add ${TARGET_DIR}"
    ;;
  "i" )
    operation="import"
    # shellcheck disable=SC2089
    git_cleanup="warn 'Skipping git cleanup'"
    # shellcheck disable=SC2089
    git_stage="warn 'Skipping git staging'"
    ;;
  * )
    echo "Unknown value entered: ${1}"
    usage
    ;;
esac

# shellcheck disable=SC2090
eval "${git_cleanup}"
mkdir -p "${TARGET_DIR}"

app_array=(
  'ch.protonvpn.mac'
  'cn.better365.iBar'
  'com.abhishek.Clocker'
  'com.apphousekitchen.aldente-pro'
  'com.apple.Accessibility-Settings.extension'
  'com.apple.Accessibility.Assets'
  'com.apple.accessibility.heard'
  'com.apple.Accessibility'
  'com.apple.AppleMultitouchMouse'
  'com.apple.AppleMultitouchTrackpad'
  'com.apple.Battery-Settings.extension'
  'com.apple.BluetoothSettings'
  'com.apple.ControlCenter-Settings.extension'
  'com.apple.controlcenter.helper'
  'com.apple.controlcenter'
  'com.apple.corespotlightui'
  'com.apple.Date-Time-Settings.extension'
  'com.apple.Displays-Settings.extension'
  'com.apple.dock.external.extra.arm64'
  'com.apple.dock.extra'
  'com.apple.dock'
  'com.apple.donotdisturbd'
  'com.apple.driver.AppleBluetoothMultitouch.mouse'
  'com.apple.driver.AppleBluetoothMultitouch.trackpad'
  'com.apple.driver.AppleHIDMouse'
  'com.apple.finder'
  'com.apple.findmy.findmylocateagent'
  'com.apple.findmy'
  'com.apple.iclouddrive.features'
  'com.apple.Keyboard-Settings.extension'
  'com.apple.keyboardservicesd'
  'com.apple.Lock-Screen-Settings.extension'
  'com.apple.LoginItems-Settings.extension'
  'com.apple.loginwindow'
  'com.apple.menuextra.battery'
  'com.apple.menuextra.clock'
  'com.apple.Notifications-Settings.extension'
  'com.apple.preferences.softwareupdate'
  'com.apple.print.add'
  'com.apple.print.custompresets.forprinter._10_134_3_151'
  'com.apple.printcenter'
  'com.apple.Profiles-Settings.extension'
  'com.apple.screencapture'
  'com.apple.screencaptureui'
  'com.apple.screensaver'
  'com.apple.ServicesMenu.Services'
  'com.apple.Software-Update-Settings.extension'
  'com.apple.SoftwareUpdate'
  'com.apple.SoftwareUpdateNotificationManager'
  'com.apple.sound.beep.feedback'
  'com.apple.sound.beep.flash'
  'com.apple.sound.beep.sound'
  'com.apple.spaces'
  'com.apple.Spotlight'
  'com.apple.springing.delay'
  'com.apple.springing.enabled'
  'com.apple.swipescrolldirection'
  'com.apple.systempreferences'
  'com.apple.systemsettings.extensions'
  'com.apple.systemuiserver'
  'com.apple.Terminal'
  'com.apple.textInput.keyboardServices.textReplacement'
  'com.apple.Touch-ID-Settings.extension'
  'com.apple.Trackpad-Settings.extension'
  'com.apple.trackpad.enableSecondaryClick'
  'com.apple.trackpad.fiveFingerPinchSwipeGesture'
  'com.apple.trackpad.forceClick'
  'com.apple.trackpad.fourFingerHorizSwipeGesture'
  'com.apple.trackpad.fourFingerPinchSwipeGesture'
  'com.apple.trackpad.fourFingerVertSwipeGesture'
  'com.apple.trackpad.momentumScroll'
  'com.apple.trackpad.pinchGesture'
  'com.apple.trackpad.rotateGesture'
  'com.apple.trackpad.scaling'
  'com.apple.trackpad.scrollBehavior'
  'com.apple.trackpad.threeFingerDragGesture'
  'com.apple.trackpad.threeFingerHorizSwipeGesture'
  'com.apple.trackpad.threeFingerTapGesture'
  'com.apple.trackpad.threeFingerVertSwipeGesture'
  'com.apple.trackpad.twoFingerDoubleTapGesture'
  'com.apple.trackpad.twoFingerFromRightEdgeSwipeGesture'
  'com.apple.universalaccessAuthWarning'
  'com.apple.Wallpaper-Settings.extension'
  'com.apple.wallpaper'
  'com.apple.wifi-settings-extension'
  'com.apple.wifi.WiFiAgent'
  'com.brave.Browser.beta'
  'com.brave.Browser.nightly'
  'com.cloudflare.1dot1dot1dot1.macos'
  'com.docker.docker'
  'com.github.Electron'
  'com.google.Chrome.beta'
  'com.google.Chrome.canary'
  'com.google.Chrome'
  'com.googlecode.iterm2'
  'com.knollsoft.Rectangle'
  'com.lowtechguys.ZoomHider'
  'com.macpaw.site.theunarchiver'
  'com.microsoft.VSCodeInsiders'
  'com.mowglii.ItsycalApp'
  'com.piriform.ccleaner'
  'com.raycast.macos'
  'com.sindresorhus.Command-X'
  'com.sindresorhus.Velja'
  'com.titanium.OnyX'
  'com.visualstudio.code.oss'
  'com.vscodium.VSCodiumInsiders'
  'company.thebrowser.Browser'
  'eu.exelban.Stats'
  'info.marcel-dierkes.KeepingYouAwake'
  'io.github.keycastr'
  'io.rancherdesktop.app'
  'keybase.Electron'
  'loginwindow'
  'net.freemacsoft.AppCleaner'
  'net.pornel.ImageOptim'
  'net.sourceforge.Monolingual'
  'NSGlobalDomain'
  'org.cups.PrintingPrefs'
  'org.ferdium.ferdium-app'
  'org.keepassxc.keepassxc'
  'org.libreoffice.script'
  'org.mozilla.firefox'
  'org.mozilla.nightly'
  'org.mozilla.thunderbird-daily'
  'org.mozilla.thunderbird'
  'us.zoom.xos'
  'us.zoom.ZoomClips'
  'ZoomChat'
)

echo "Running operation: $(green ${operation})"
for app_pref in "${app_array[@]}"; do
  echo "Processing $(cyan ${app_pref})"
  TARGET_FILE="${TARGET_DIR}/${app_pref}.defaults"
  is_file "${TARGET_FILE}" || touch "${TARGET_FILE}"
  /usr/bin/defaults "${operation}" "${app_pref}" "${TARGET_FILE}"
done

# shellcheck disable=SC2090
eval "${git_stage}"
