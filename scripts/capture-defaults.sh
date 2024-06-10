#!/usr/bin/env bash

# file location: Put this anywhere in the path.

# This script will capture (export) the settings or import the settings from the location specified in the $TARGET_DIR env var defined down below. You can back the files up to any cloud storage and retrieve into the new laptop to then get back all settings as per the original machine. The only word of caution is to use it with the same OS version (I haven't tried in any situations where the old and new machines had different OS versions - so I cannot guarantee if that might break the system in any way)

# A trick to find the name of the app:
# Run `defaults read` in an empty window of a terminal app, then use the search functionality to search for a known word related to that app (like eg app visible name, author, some setting that's unique to that app, etc). Once you find this, trace back to the parent in the printed JSON to then get the real unique name of the app where its settings are stored.


usage() {
  echo "Usage: ${0} <e/i>"
  echo "  e  --> Export from system"
  echo "  i  --> Import into system"
  exit 1
}

[ $# -ne 1 ] && usage

PERSONAL_BIN_DIR="${PERSONAL_BIN_DIR:-"${HOME}/.bin"}"
TARGET_DIR="${PERSONAL_BIN_DIR}/macos/defaults"

case "${1}" in
  "e" )
    operation="export"
    git_cleanup="git -C ${HOME} rm -rf ${TARGET_DIR}/*"
    git_stage="git -C ${HOME} add ${TARGET_DIR}"
    ;;
  "i" )
    operation="import"
    # shellcheck disable=SC2089
    git_cleanup="echo 'Skipping git cleanup'"
    # shellcheck disable=SC2089
    git_stage="echo 'Skipping git staging'"
    ;;
  * )
    echo "Unknown value entered: ${1}"
    usage
    ;;
esac

# shellcheck disable=SC2090
$git_cleanup
mkdir -p "${TARGET_DIR}"

app_array=(
  'ch.protonvpn.mac'
  'cn.better365.iBar'
  'com.abhishek.Clocker'
  'com.apphousekitchen.aldente-pro'
  'com.apple.Accessibility'
  'com.apple.AppleMultitouchMouse'
  'com.apple.AppleMultitouchTrackpad'
  'com.apple.controlcenter'
  'com.apple.dock'
  'com.apple.finder'
  'com.apple.iclouddrive.features'
  'com.apple.menuextra.battery'
  'com.apple.menuextra.clock'
  'com.apple.screensaver'
  'com.apple.ServicesMenu.Services'
  'com.apple.SoftwareUpdate'
  'com.apple.sound.beep.feedback'
  'com.apple.sound.beep.flash'
  'com.apple.sound.beep.sound'
  'com.apple.Spotlight'
  'com.apple.springing.delay'
  'com.apple.springing.enabled'
  'com.apple.swipescrolldirection'
  'com.apple.systemuiserver'
  'com.apple.Terminal'
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
  'com.apple.wallpaper'
  'com.bitwarden.desktop'
  'com.brave.Browser.beta'
  'com.brave.Browser.nightly'
  'com.cloudflare.1dot1dot1dot1.macos'
  'com.generalarcade.flycut'
  'com.google.Chrome.beta'
  'com.google.Chrome'
  'com.googlecode.iterm2'
  'com.knollsoft.Rectangle'
  'com.macpaw.site.theunarchiver'
  'com.microsoft.VSCodeInsiders'
  'com.mowglii.ItsycalApp'
  'com.piriform.ccleaner'
  'com.runningwithcrayons.Alfred-Preferences'
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
  'NSGlobalDomain'
  'org.ferdium.ferdium-app'
  'org.keepassxc.keepassxc'
  'org.libreoffice.script'
  'us.zoom.xos'
  'ZoomChat'
)

for app_pref in "${app_array[@]}"
do
  echo "Processing ${app_pref} for ${operation}"
  TARGET_FILE="${TARGET_DIR}/${app_pref}.defaults"
  test -f "${TARGET_FILE}" || touch "${TARGET_FILE}"
  /usr/bin/defaults "${operation}" "${app_pref}" "${TARGET_FILE}"
done

# shellcheck disable=SC2090
$git_stage
