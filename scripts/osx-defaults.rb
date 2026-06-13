#!/usr/bin/env ruby
# frozen_string_literal: true

# file location: ~/.config/dotfiles/scripts/osx-defaults.rb
#
# Sets macOS system defaults and application preferences.
# Based on: https://gist.github.com/DAddYE/2108403
# Thanks to: @erikh, @DAddYE, @mathiasbynens
#
# system() calls that return non-zero are silently ignored -- many `defaults write`
# and `killall` calls return non-zero when a setting is unsupported on the current
# OS version, which is expected.
#
# This script handles settings that cannot be managed by capture-prefs.rb alone,
# or that require mechanisms other than a plain 'defaults write':
#   - sudo / pmset / systemsetup / scutil calls
#   - defaults -currentHost writes (host-specific pref domain)
#   - PlistBuddy nested plist edits (Terminal/iTerm2 profiles, Finder icon view,
#     Spotlight symbolic hotkeys)
#   - defaults -dict-add patterns (Mail DraftsViewerAttributes,
#     Finder FXInfoPanesExpanded)
#   - com.apple.AddressBook (sandbox-restricted; non-zero returns silently ignored)
#   - Firefox / Zen Browser user.js file writes
#   - Interactive ask-N settings (intentionally left to user choice)
#
# Usage: osx-defaults.rb [-s]

$LOAD_PATH.unshift(File.join(__dir__, 'utilities'))

require 'cli_parser'
require 'env_vars'
require 'logging'
require 'macos'
require 'path_utils'

include Logging

# ---------------------------------------------------------------------------
# Constants

FINDER_PLIST = EnvVars::HOME.join('Library', 'Preferences', 'com.apple.finder.plist').to_s.freeze
TERMINAL_PLIST = EnvVars::HOME.join('Library', 'Preferences', 'com.apple.Terminal.plist').to_s.freeze
ITERM_PLIST = EnvVars::HOME.join('Library', 'Preferences', 'com.googlecode.iterm2.plist').to_s.freeze
HOTKEYS_PLIST = EnvVars::HOME.join('Library', 'Preferences', 'com.apple.symbolichotkeys.plist').to_s.freeze
PLISTBUDDY = PathUtils::ROOT.join('usr', 'libexec', 'PlistBuddy').to_s.freeze

# Written to Firefox and Zen Browser profile dirs.
# user.js is the correct idempotent mechanism: Firefox overwrites prefs.js on
# every launch but sources user.js at startup and re-applies it over prefs.js.
FIREFOX_USER_JS = <<~JS
  // Written by osx-defaults.rb -- do not edit by hand; re-run the script to update.
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
JS

# ---------------------------------------------------------------------------
# Helpers

# Interactive y/n prompt. In silent mode ($auto=true) the default is accepted
# without user input. Returns true for 'y', false for 'n'.
def _ask(prompt, default = nil)
  if $auto
    # Silent mode: accept the default. 'Y' default -> true, 'N' default -> false.
    return default != 'N'
  end

  loop do
    indicator = case default
      when 'Y' then "[\e[32mY\e[0m/n]"
      when 'N' then "[y/\e[32mN\e[0m]"
      else '[y/n]'
      end
    print "#{prompt} #{indicator} "
    answer = $stdin.gets&.strip
    answer = default if nil_or_empty?(answer)
    case answer&.upcase
    when 'Y' then return true
    when 'N' then return false
    end
  end
end

# Runs: defaults write <domain> <key> [type] <value> ...
# Return value is ignored -- unsupported keys on the current OS are non-fatal.
def _d(*args)
  system('defaults', 'write', *args.map(&:to_s))
end

# Runs: defaults -currentHost write <domain> <key> [type] <value> ...
def _dh(*args)
  system('defaults', '-currentHost', 'write', *args.map(&:to_s))
end

# Runs: sudo defaults write <domain> <key> [type] <value> ...
def _ds(*args)
  system('sudo', 'defaults', 'write', *args.map(&:to_s))
end

# Runs a PlistBuddy command. Return value indicates success/failure (used for
# the Set-or-Add pattern in the Spotlight hotkeys section).
def _pb(cmd, file)
  system(PLISTBUDDY, '-c', cmd, file)
end

# Runs a PlistBuddy command suppressing all output. Used for Delete operations
# that are expected to fail when the key does not yet exist (idempotent Delete
# before Add pattern).
def _pbd(cmd, file)
  system(PLISTBUDDY, '-c', cmd, file, out: File::NULL, err: File::NULL)
end

private :_ask, :_d, :_dh, :_ds, :_pb, :_pbd

# ---------------------------------------------------------------------------
# CLI argument parsing

options = {}
CliParser.parse('[options]') do |opts|
  opts.separator 'Sets macOS system defaults and application preferences.'
  opts.separator ''
  opts.separator 'Options:'.purple
  opts.on('-s', '--silent', 'Run in silent/auto mode without interactive prompts') do
    options[:silent] = true
  end
  opts.separator ''
  opts.separator "  eg: #{File.basename(__FILE__).cyan} -s"
end

$auto = options[:silent] || false

# ---------------------------------------------------------------------------
# Entry-point guards

unless $auto || $stdin.tty? || EnvVars.force_color?
  error('Interactive mode requires a terminal. Use -s for silent mode.')
  exit 1
end

# ---------------------------------------------------------------------------
# Script preamble

Logging.section_header('osx-defaults')
increment_script_depth
start_time = print_script_start

# Prompt for and cache sudo credentials upfront. The keep_sudo_alive background
# thread is started inside MacOS.suspend_softwareupdate_schedule below -- it keeps
# credentials alive for all subsequent sudo calls in this script.
system('sudo', '-v') unless $auto

# Close System Preferences to prevent it from overriding settings we are about
# to change.
system('osascript', '-e', 'tell application "System Preferences" to quit')

# Login-item apps are killed upfront (SIGTERM -- graceful shutdown) so their
# running instance cannot overwrite our defaults writes when it quits.
# The at_exit hook restarts them on any exit path (normal or error), ensuring
# the user is never left with login-item apps dead.
# The canonical app list lives in MacOS::LOGIN_ITEM_APPS (utilities/macos.rb).
MacOS.kill_login_item_apps
at_exit do
  success('Done. Note that some of these changes require a logout/restart to take effect.')
  print_script_summary(start_time)
  MacOS.restart_login_item_apps
  MacOS.resume_softwareupdate_schedule
end

# Suspend the automatic software update schedule while writing defaults so
# background update activity cannot conflict with the defaults system cache.
# resume_softwareupdate_schedule is called from the at_exit hook above, covering
# both normal and error exits. suspend_softwareupdate_schedule also starts the
# keep_sudo_alive background thread that refreshes credentials every 60 seconds.
MacOS.suspend_softwareupdate_schedule

# ---------------------------------------------------------------------------
# Login Window

if _ask('Disable guest login', 'Y')
  system('sudo', 'defaults', 'write',
         '/Library/Preferences/com.apple.loginwindow', 'GuestEnabled', '-bool', 'false')
end

# ---------------------------------------------------------------------------
# MenuBar / Control Center

d('com.apple.controlcenter', 'NSStatusItem Visible Bluetooth', '1')
d('com.apple.controlcenter', 'NSStatusItem Visible WiFi', '-bool', 'true')
d('com.apple.controlcenter', 'NSStatusItem Visible Battery', '0')
d('com.apple.controlcenter', 'NSStatusItem VisibleCC Clock', '-bool', 'false')
d('com.apple.controlcenter', 'NSStatusItem Visible Spotlight', '-bool', 'false')
d('com.apple.controlcenter', 'NSStatusItem Visible AirDrop', '-bool', 'false')
d('com.apple.controlcenter', 'NSStatusItem Visible TextInput', '-bool', 'false')
d('com.apple.controlcenter', 'NSStatusItem Visible KeyboardBrightness', '-bool', 'false')
d('com.apple.controlcenter', 'NSStatusItem Visible Weather', '-bool', 'false')
# Focus = show when active (8=when active, 16=always, 24=never)
d('com.apple.controlcenter', 'FocusModes', '-int', '8')
d('com.apple.controlcenter', 'AirPlayDisplay', '-int', '8')
d('com.apple.controlcenter', 'Display', '-int', '8')
d('com.apple.controlcenter', 'Sound', '-int', '8')
d('com.apple.controlcenter', 'NowPlaying', '-int', '8')

# Keep keyboard brightness at maximum via -currentHost write; cannot be
# expressed as a plain defaults write (host-specific pref domain).
if _ask('Keep keyboard brightness at maximum', 'Y')
  _dh('com.apple.controlcenter', 'KeyboardBrightness', '8')
end

if _ask('Disable automatic keyboard brightness adjustment in low light', 'Y')
  # com.apple.BezelServices dAuto controls "Adjust keyboard brightness in low light"
  # (System Settings > Keyboard). CoreBrightness KeyboardBacklightAutoDim does not
  # work on modern macOS; dAuto is the correct key.
  _d('com.apple.BezelServices', 'dAuto', '-bool', 'false')
end

# ---------------------------------------------------------------------------
# General UI/UX

if _ask('Set computer name (as done via System Preferences → Sharing)', 'Y')
  # ${(C)USER} in zsh is title-case; split on word boundaries and capitalise each part.
  username_in_camel_case = USER.split(/[-_\s]/).map(&:capitalize).join
  human_date = Time.now.strftime('%Y-%m-%d')
  system('sudo', 'scutil', '--set', 'ComputerName',
         "IND-CHN-#{username_in_camel_case}'s MBP-#{human_date}")
  system('sudo', 'scutil', '--set', 'HostName', "#{username_in_camel_case}-#{human_date}")
  system('sudo', 'scutil', '--set', 'LocalHostName', "#{username_in_camel_case}-#{human_date}")
  system('sudo', 'defaults', 'write',
         '/Library/Preferences/SystemConfiguration/com.apple.smb.server',
         'NetBIOSName', '-string', "#{username_in_camel_case}-#{human_date}")
end

if _ask('Set standby delay to 6 hours (default: 1 hour)', 'Y')
  system('sudo', 'pmset', '-a', 'standbydelay', '21600')
end

# dontAutoLoad must be written to the ByHost preference file (identified by
# hardware UUID) -- not to the regular com.apple.systemuiserver domain. The
# ByHost path is what SystemUIServer reads on startup to skip certain menu
# extras regardless of which user is logged in.
# ByHost glob (zsh (N.) qualifier) translated to PathUtils.glob_pathnames + Pathname.file? filter.
PathUtils.glob_pathnames(EnvVars::HOME.join('Library', 'Preferences', 'ByHost', 'com.apple.systemuiserver.*'))
         .select(&:file?)
         .each do |domain_path_pn|
  system('defaults', 'write', domain_path_pn.to_s, 'dontAutoLoad', '-array',
         '/System/Library/CoreServices/Menu Extras/TimeMachine.menu',
         '/System/Library/CoreServices/Menu Extras/Volume.menu',
         '/System/Library/CoreServices/Menu Extras/User.menu')
end

d('com.apple.systemuiserver', 'menuExtras', '-array',
  '/System/Library/CoreServices/Menu Extras/Bluetooth.menu',
  '/System/Library/CoreServices/Menu Extras/AirPort.menu',
  '/System/Library/CoreServices/Menu Extras/Battery.menu',
  '/System/Library/CoreServices/Menu Extras/Clock.menu',
  '/System/Library/CoreServices/Menu Extras/User.menu',
  '/System/Library/CoreServices/Menu Extras/Volume.menu')

d('com.apple.systemuiserver', 'NSStatusItem Visible Siri', '-bool', 'false')
d('com.apple.systemuiserver', 'NSStatusItem Visible com.apple.menuextra.airport', '-bool', 'true')
d('com.apple.systemuiserver', 'NSStatusItem Visible com.apple.menuextra.appleuser', '-bool', 'true')
d('com.apple.systemuiserver', 'NSStatusItem Visible com.apple.menuextra.battery', '-bool', 'true')
d('com.apple.systemuiserver', 'NSStatusItem Visible com.apple.menuextra.bluetooth', '-bool', 'true')
d('com.apple.systemuiserver', 'NSStatusItem Visible com.apple.menuextra.volume', '-bool', 'true')

d('com.apple.menuextra.clock', 'DateFormat', '-string', 'EEE d MMM hh:mm:ss a')
d('com.apple.menuextra.clock', 'FlashDateSeparators', '-bool', 'true')
# IsAnalog=true because The Clocker app is used for the menu bar clock display.
d('com.apple.menuextra.clock', 'IsAnalog', '-bool', 'true')
d('com.apple.menuextra.clock', 'Show24Hour', '-bool', 'false')
d('com.apple.menuextra.clock', 'ShowAMPM', '-bool', 'true')
d('com.apple.menuextra.clock', 'ShowDate', '-bool', 'false')
d('com.apple.menuextra.clock', 'ShowDayOfMonth', '-bool', 'true')
d('com.apple.menuextra.clock', 'ShowDayOfWeek', '-bool', 'false')
d('com.apple.menuextra.clock', 'ShowSeconds', '-bool', 'true')

if _ask("Remove duplicates in the 'Open With' menu", 'Y')
  system('/System/Library/Frameworks/CoreServices.framework/Frameworks/' \
  'LaunchServices.framework/Support/lsregister',
         '-kill', '-r', '-domain', 'local', '-domain', 'system', '-domain', 'user')
end

if _ask('Keep windows open when quitting and re-opening apps (Resume)', 'Y')
  _d('-g', 'NSQuitAlwaysKeepsWindows', '-bool', 'true')
end

if _ask('Restart automatically if the computer freezes', 'Y')
  # systemsetup emits a harmless Error:-99 to stderr on modern macOS (SIP restriction
  # on the InternetServices subsystem); the command still applies the setting correctly.
  system('sudo', 'systemsetup', '-setrestartfreeze', 'on', err: File::NULL)
end

if _ask('Set the timezone to Asia/Calcutta', 'Y')
  system('sudo', 'systemsetup', '-settimezone', 'Asia/Calcutta', err: File::NULL)
end

if _ask('Sync time automatically using network time servers', 'Y')
  system('sudo', 'systemsetup', '-setusingnetworktime', 'on', err: File::NULL)
end

if _ask('Set the computer sleep time to 10 minutes', 'Y')
  system('sudo', 'systemsetup', '-setcomputersleep', '10', err: File::NULL)
end

if _ask('Set the display sleep time to 10 minutes', 'Y')
  system('sudo', 'systemsetup', '-setdisplaysleep', '10', err: File::NULL)
end

if _ask('Set the hard disk sleep time to 15 minutes', 'Y')
  system('sudo', 'systemsetup', '-setharddisksleep', '15', err: File::NULL)
end

if _ask('Disable automatic capitalization', 'Y')
  _d('-g', 'NSAutomaticCapitalizationEnabled', '-bool', 'false')
end

if _ask('Set preferred languages to English (India, US) and clear recent places', 'Y')
  _d('-g', 'NSLinguisticDataAssetsRequested', '-array', 'en_IN', 'en_US', 'en')
  # Suppress error when the key doesn't exist -- delete is a no-op in that case.
  system('defaults', 'delete', 'NSGlobalDomain', 'NSNavRecentPlaces', err: File::NULL)
end

if _ask('Set text shortcuts for common phrases (dfdm, ntd, cyl, ttyl, omw, omg)', 'Y')
  _d('-g', 'NSUserDictionaryReplacementItems', '-array',
     '{ on = 1; replace = dfdm; with = "dropping off for different meeting"; }',
     '{ on = 1; replace = ntd; with = "need to drop"; }',
     '{ on = 1; replace = cyl; with = "Cya later!"; }',
     '{ on = 1; replace = ttyl; with = "Talk to you later!"; }',
     '{ on = 1; replace = omw; with = "On my way!"; }',
     '{ on = 1; replace = omg; with = "Oh my God!"; }')
end

if _ask('Disable automatic period substitution (double-space → period)', 'Y')
  _d('-g', 'NSAutomaticPeriodSubstitutionEnabled', '-bool', 'false')
end

if _ask('Disable adding apps to the Services contextual menu (reduces right-click clutter)', 'Y')
  # com.apple.SetupAssistant domain is machine-specific overall, but this single key
  # is a portable user preference controlling whether apps populate the Services submenu.
  _d('com.apple.SetupAssistant', 'NSAddServicesToContextMenus', '-bool', 'false')
end

# ---------------------------------------------------------------------------
# SSD-specific tweaks

if _ask('Disable hibernation (speeds up entering sleep mode)', 'Y')
  system('sudo', 'pmset', '-a', 'hibernatemode', '0')
end

if _ask('Disable the sudden motion sensor (not useful for SSDs)', 'Y')
  system('sudo', 'pmset', '-a', 'sms', '0')
end

# ---------------------------------------------------------------------------
# Trackpad, mouse, keyboard, Bluetooth accessories, and input

if _ask('Enable trackpad gestures (tap-to-click, three-finger drag, etc.)', 'Y')
  # Bluetooth trackpad and built-in trackpad share the same gesture keys -- both
  # domains must be written to keep wired and wireless behaviour in sync.
  {
    'com.apple.driver.AppleBluetoothMultitouch.trackpad' => {
      'Clicking' => ['-int', '1'],
      'DragLock' => ['-int', '0'],
      'Dragging' => ['-int', '0'],
      'TrackpadCornerSecondaryClick' => ['-int', '0'],
      'TrackpadFiveFingerPinchGesture' => ['-int', '2'],
      'TrackpadFourFingerHorizSwipeGesture' => ['-int', '2'],
      'TrackpadFourFingerPinchGesture' => ['-int', '2'],
      'TrackpadFourFingerVertSwipeGesture' => ['-int', '2'],
      'TrackpadHandResting' => ['-int', '1'],
      'TrackpadHorizScroll' => ['-int', '1'],
      'TrackpadMomentumScroll' => ['-int', '1'],
      'TrackpadPinch' => ['-int', '1'],
      'TrackpadRightClick' => ['-int', '1'],
      'TrackpadRotate' => ['-int', '1'],
      'TrackpadScroll' => ['-int', '1'],
      'TrackpadThreeFingerDrag' => ['-int', '0'],
      'TrackpadThreeFingerHorizSwipeGesture' => ['-int', '2'],
      'TrackpadThreeFingerTapGesture' => ['-int', '0'],
      'TrackpadThreeFingerVertSwipeGesture' => ['-int', '2'],
      'TrackpadTwoFingerDoubleTapGesture' => ['-int', '1'],
      'TrackpadTwoFingerFromRightEdgeSwipeGesture' => ['-int', '3'],
      'USBMouseStopsTrackpad' => ['-int', '0'],
      'UserPreferences' => ['-int', '1']
    },
    'com.apple.AppleMultitouchTrackpad' => {
      'Clicking' => ['-bool', 'true'],
      'DragLock' => ['-int', '0'],
      'Dragging' => ['-int', '0'],
      'FirstClickThreshold' => ['-int', '1'],
      'ForceSuppressed' => ['-int', '0'],
      'SecondClickThreshold' => ['-int', '1'],
      'TrackpadCornerSecondaryClick' => ['-int', '0'],
      'TrackpadFiveFingerPinchGesture' => ['-int', '2'],
      'TrackpadFourFingerHorizSwipeGesture' => ['-int', '2'],
      'TrackpadFourFingerPinchGesture' => ['-int', '2'],
      'TrackpadFourFingerVertSwipeGesture' => ['-int', '2'],
      'TrackpadHandResting' => ['-int', '1'],
      'TrackpadHorizScroll' => ['-int', '1'],
      'TrackpadMomentumScroll' => ['-int', '1'],
      'TrackpadPinch' => ['-int', '1'],
      'TrackpadRightClick' => ['-int', '1'],
      'TrackpadRotate' => ['-int', '1'],
      'TrackpadScroll' => ['-int', '1'],
      'TrackpadThreeFingerDrag' => ['-int', '0'],
      'TrackpadThreeFingerHorizSwipeGesture' => ['-int', '2'],
      'TrackpadThreeFingerTapGesture' => ['-int', '2'],
      'TrackpadThreeFingerVertSwipeGesture' => ['-int', '2'],
      'TrackpadTwoFingerDoubleTapGesture' => ['-int', '1'],
      'TrackpadTwoFingerFromRightEdgeSwipeGesture' => ['-int', '3'],
      'USBMouseStopsTrackpad' => ['-int', '0'],
      'UserPreferences' => ['-int', '1']
    }
  }.each { |dom, keys| keys.each { |key, args| d(dom, key, *args) } }
  # System Settings > Trackpad > Tap to click: the UI reads this host-level key.
  # All three writes are required: the two domain writes above configure the hardware
  # drivers; this one tells the UI the user has enabled tap-to-click.
  _dh('-g', 'com.apple.mouse.tapBehavior', '-int', '1')
end

if _ask('Apple Multitouch mouse features', 'Y')
  {
    'MouseButtonMode' => ['-string', 'OneButton'],
    'MouseHorizontalScroll' => ['-int', '1'],
    'MouseMomentumScroll' => ['-int', '1'],
    'MouseOneFingerDoubleTapGesture' => ['-int', '0'],
    'MouseTwoFingerDoubleTapGesture' => ['-int', '3'],
    'MouseTwoFingerHorizSwipeGesture' => ['-int', '2'],
    'MouseVerticalScroll' => ['-int', '1'],
    'UserPreferences' => ['-int', '1']
  }.each { |key, args| d('com.apple.AppleMultitouchMouse', key, *args) }
end

if _ask('Enable full keyboard access for all controls (e.g. Tab in modal dialogs)', 'Y')
  _d('-g', 'AppleKeyboardUIMode', '-int', '2')
end

if _ask('Set language to English (India), locale to INR currency, metric units, double-click titlebar to maximise', 'Y')
  _d('-g', 'AppleLanguages', '-array', 'en-IN', 'en')
  _d('-g', 'AppleLocale', '-string', 'en_IN@currency=INR')
  _d('-g', 'AppleMeasurementUnits', '-string', 'Centimeters')
  _d('-g', 'AppleMetricUnits', '-bool', 'true')
  _d('-g', 'AppleActionOnDoubleClick', '-string', 'Maximize')
end

# ---------------------------------------------------------------------------
# Finder

if _ask('Allow quitting Finder via ⌘Q (also hides desktop icons)', 'Y')
  _d('com.apple.finder', 'QuitMenuItem', '-bool', 'true')
end

if _ask('Set Home folder as the default location for new Finder windows', 'Y')
  _d('com.apple.finder', 'NewWindowTarget', '-string', 'PfHm')
  _d('com.apple.finder', 'NewWindowTargetPath', '-string', "file://#{EnvVars::HOME}/")
end

if _ask('Hide hard drive icons on the desktop', 'N')
  _d('com.apple.finder', 'ShowHardDrivesOnDesktop', '-bool', 'false')
end

if _ask('Hide hidden files by default in Finder', 'N')
  _d('com.apple.finder', 'AppleShowAllFiles', '-bool', 'false')
end

if _ask('Show all filename extensions', 'Y')
  _d('-g', 'AppleShowAllExtensions', '-bool', 'true')
end

if _ask('Display full POSIX path as Finder window title', 'Y')
  _d('com.apple.finder', '_FXShowPosixPathInTitle', '-bool', 'true')
end

if _ask('Show status bar in Finder windows', 'Y')
  _d('com.apple.finder', 'ShowStatusBar', '-bool', 'true')
end

if _ask("Start the status bar path at #{EnvVars::HOME} (instead of 'Hard drive')", 'Y')
  system('sudo', 'defaults', 'write',
         '/Library/Preferences/com.apple.finder', 'PathBarRootAtHome', '-bool', 'true')
end

if _ask('Show path (breadcrumb) bar in Finder windows', 'Y')
  _d('com.apple.finder', 'ShowPathbar', '-bool', 'true')
end

if _ask('Hide the preview pane in Finder', 'Y')
  _d('com.apple.finder', 'ShowPreviewPane', '-bool', 'false')
end

d('com.apple.finder', 'ShowExternalHardDrivesOnDesktop', '-bool', 'true')
d('com.apple.finder', 'ShowMountedServersOnDesktop', '-bool', 'false')
d('com.apple.finder', 'ShowRecentTags', '-bool', 'false')
d('com.apple.finder', 'ShowRemovableMediaOnDesktop', '-bool', 'true')
d('com.apple.finder', 'ShowSidebar', '-bool', 'true')
d('com.apple.finder', 'SidebarDevicesSectionDisclosedState', '-bool', 'true')
d('com.apple.finder', 'SidebarPlacesSectionDisclosedState', '-bool', 'true')
d('com.apple.finder', 'SidebarShowingSignedIntoiCloud', '-bool', 'true')
d('com.apple.finder', 'SidebarShowingiCloudDesktop', '-bool', 'true')
d('com.apple.finder', 'SidebarTagsSctionDisclosedState', '-bool', 'true')
d('com.apple.finder', 'SidebarWidth', '172')
d('com.apple.finder', 'SidebariCloudDriveSectionDisclosedState', '-bool', 'true')
d('com.apple.finder', 'FXRemoveOldTrashItems', '-bool', 'true')
d('com.apple.finder', '_FXEnableColumnAutoSizing', '-bool', 'true')
# Default view style: clmv=column, icnv=icon, Nlsv=list, glyv=gallery.
d('com.apple.finder', 'FXPreferredViewStyle', '-string', 'clmv')
d('com.apple.finder', 'WarnOnEmptyTrash', '-bool', 'false')
d('com.apple.finder', 'OpenWindowForNewRemovableDisk', '-bool', 'true')
d('com.apple.finder', 'RestoreWindowState', '-bool', 'true')

if _ask('Enable iCloud Drive Optimize Mac Storage', 'Y')
  # com.apple.bird is the iCloud Drive daemon. The optimize-storage key is the only
  # portable user preference in this domain; all other keys are runtime/account state.
  _d('com.apple.bird', 'optimize-storage', '-bool', 'true')
end

if _ask('Allow text selection in Quick Look / Preview', 'Y')
  _d('com.apple.finder', 'QLEnableTextSelection', '-bool', 'true')
end

if _ask('Keep folders on top when sorting by name (Finder and Desktop)', 'Y')
  _d('com.apple.finder', '_FXSortFoldersFirst', '-bool', 'true')
  _d('com.apple.finder', '_FXSortFoldersFirstOnDesktop', '-bool', 'true')
end

if _ask('When performing a search, search the current folder by default (not This Mac)', 'Y')
  _d('com.apple.finder', 'FXDefaultSearchScope', '-string', 'SCcf')
end

if _ask('Disable the warning when changing a file extension', 'N')
  _d('com.apple.finder', 'FXEnableExtensionChangeWarning', '-bool', 'false')
end

if _ask('Enable snap-to-grid for icons on the desktop and in other icon views', 'Y')
  _pb('Set :DesktopViewSettings:IconViewSettings:arrangeBy grid', FINDER_PLIST)
  _pb('Set :FK_StandardViewSettings:IconViewSettings:arrangeBy grid', FINDER_PLIST)
  _pb('Set :StandardViewSettings:IconViewSettings:arrangeBy grid', FINDER_PLIST)
end

if _ask('Increase grid spacing for icons on the desktop and in other icon views', 'Y')
  _pb('Set :DesktopViewSettings:IconViewSettings:gridSpacing 54', FINDER_PLIST)
  _pb('Set :FK_StandardViewSettings:IconViewSettings:gridSpacing 54', FINDER_PLIST)
  _pb('Set :StandardViewSettings:IconViewSettings:gridSpacing 54', FINDER_PLIST)
end

if _ask('Increase the size of icons on the desktop and in other icon views', 'Y')
  _pb('Set :DesktopViewSettings:IconViewSettings:iconSize 64', FINDER_PLIST)
  _pb('Set :FK_StandardViewSettings:IconViewSettings:iconSize 64', FINDER_PLIST)
  _pb('Set :StandardViewSettings:IconViewSettings:iconSize 64', FINDER_PLIST)
end

if _ask('Use column view in all Finder windows by default', 'Y')
  # FXPreferredViewStyle is also set unconditionally above with the same value.
  # SearchRecentsSavedViewStyle applies only to search-results windows.
  _d('com.apple.finder', 'SearchRecentsSavedViewStyle', '-string', 'clmv')
end

if _ask('Empty Trash securely by default', 'Y')
  _d('com.apple.finder', 'EmptyTrashSecurely', '-bool', 'true')
end

if _ask('Show app-centric sidebar', 'Y')
  _d('com.apple.finder', 'FK_AppCentricShowSidebar', '-bool', 'true')
end

if _ask("Show the #{EnvVars::HOME}/Library folder", 'Y')
  system('chflags', 'nohidden', EnvVars::HOME.join('Library').to_s)
end

if _ask('Enable the MacBook Air SuperDrive on any Mac', 'N')
  system('sudo', 'nvram', 'boot-args=mbasd=1')
end

if _ask("Show the '/Volumes' folder", 'Y')
  system('sudo', 'chflags', 'nohidden', '/Volumes')
end

if _ask("Expand File Info panes: 'General', 'Open with', 'Sharing & Permissions', 'Comments', 'Name', 'Metadata'", 'Y')
  _d('com.apple.finder', 'FXInfoPanesExpanded', '-dict-add', 'Comments', '-bool', 'true')
  _d('com.apple.finder', 'FXInfoPanesExpanded', '-dict-add', 'General', '-bool', 'true')
  _d('com.apple.finder', 'FXInfoPanesExpanded', '-dict-add', 'MetaData', '-bool', 'true')
  _d('com.apple.finder', 'FXInfoPanesExpanded', '-dict-add', 'Name', '-bool', 'true')
  _d('com.apple.finder', 'FXInfoPanesExpanded', '-dict-add', 'OpenWith', '-bool', 'true')
  _d('com.apple.finder', 'FXInfoPanesExpanded', '-dict-add', 'Privileges', '-bool', 'true')
end

# Avoiding the creation of .DS_Store files on network volumes.
d('com.apple.desktopservices', 'DSDontWriteNetworkStores', '-bool', 'true')

# ---------------------------------------------------------------------------
# Energy saving

# Enable lid wakeup.
system('sudo', 'pmset', '-a', 'lidwake', '1')
# Restart automatically on power loss.
system('sudo', 'pmset', '-a', 'autorestart', '1')

# ---------------------------------------------------------------------------
# Keychain

if _ask('Keychain shows expired certificates', 'Y')
  _d('com.apple.keychainaccess', 'Show Expired Certificates', '-bool', 'true')
end

if _ask('Makes Keychain Access display *unsigned* ACL entries in italics', 'Y')
  _d('com.apple.keychainaccess', 'Distinguish Legacy ACLs', '-bool', 'true')
end

# ---------------------------------------------------------------------------
# Remote Desktop

if _ask('Show the Debug menu in Remote Desktop', 'Y')
  _d('com.apple.remotedesktop', 'IncludeDebugMenu', '-bool', 'true')
end

if _ask('Define user name display behavior', 'Y')
  _d('com.apple.remotedesktop', 'showShortUserName', '-bool', 'true')
end

# ---------------------------------------------------------------------------
# Dock

if _ask('Set the icon size of Dock items to 35 pixels', 'Y')
  _d('com.apple.dock', 'tilesize', '-int', '35')
end

if _ask('Move the dock to the right side of the screen', 'Y')
  _d('com.apple.dock', 'orientation', '-string', 'right')
end

if _ask("Minimize windows into their application's icon", 'Y')
  _d('com.apple.dock', 'minimize-to-application', '-bool', 'true')
end

if _ask('Show only active apps in Dock', 'Y')
  _d('com.apple.dock', 'static-only', '-bool', 'true')
end

if _ask('Enable highlight hover effect for the grid view of a stack (Dock)', 'Y')
  _d('com.apple.dock', 'mouse-over-hilite-stack', '-bool', 'true')
end

if _ask('Show indicator lights for open applications in the Dock', 'Y')
  _d('com.apple.dock', 'show-process-indicators', '-bool', 'true')
end

if _ask('Animate opening applications from the Dock', 'Y')
  _d('com.apple.dock', 'launchanim', '-bool', 'true')
end

if _ask('Change minimize/maximize window effect', 'Y')
  _d('com.apple.dock', 'mineffect', '-string', 'suck')
end

if _ask('Speed up Mission Control animations', 'Y')
  _d('com.apple.dock', 'expose-animation-duration', '-float', '0.5')
end

if _ask('Show image for notifications', 'Y')
  _d('com.apple.dock', 'notification-always-show-image', '-bool', 'true')
end

if _ask('Enable Bouncing dock icons', 'Y')
  _d('com.apple.dock', 'no-bouncing', '-bool', 'false')
end

if _ask('Remove the animation when hiding or showing the dock', 'Y')
  _d('com.apple.dock', 'autohide-time-modifier', '-float', '0')
end

if _ask('In Expose, only show windows from the current space', 'N')
  _d('com.apple.dock', 'wvous-show-windows-in-other-spaces', '-bool', 'false')
end

if _ask('Automatically rearrange Spaces based on most recent use', 'Y')
  _d('com.apple.dock', 'mru-spaces', '-bool', 'true')
end

if _ask('Remove the auto-hiding Dock delay', 'N')
  _d('com.apple.dock', 'autohide-delay', '-float', '0')
end

if _ask('Automatically hide and show the Dock', 'Y')
  _d('com.apple.dock', 'autohide', '-bool', 'true')
end

if _ask('Automatically magnify the Dock', 'Y')
  _d('com.apple.dock', 'magnification', '-bool', 'true')
end

if _ask('Make Dock icons of hidden applications translucent', 'Y')
  _d('com.apple.dock', 'showhidden', '-bool', 'true')
end

if _ask("Enable the 'reopen windows when logging back in' option", 'N')
  _d('com.apple.loginwindow', 'TALLogoutSavesState', '-bool', 'true')
  _d('com.apple.loginwindow', 'LoginwindowLaunchesRelaunchApps', '-bool', 'true')
end

# Launchpad
if _ask('Number of columns and rows in the dock springboard set to 10', 'Y')
  _d('com.apple.dock', 'springboard-rows', '-int', '10')
  _d('com.apple.dock', 'springboard-columns', '-int', '10')
end

if _ask('Disable the Launchpad gesture (pinch with thumb and three fingers)', 'N')
  _d('com.apple.dock', 'showLaunchpadGestureEnabled', '-int', '0')
end

if _ask('Hot corners', 'Y')
  # Possible values: 0=no-op, 2=Mission Control, 3=Show application windows,
  # 4=Desktop, 5=Start screen saver, 6=Disable screen saver, 7=Dashboard,
  # 10=Put display to sleep, 11=Launchpad, 12=Notification Center.
  _d('com.apple.dock', 'wvous-tl-corner', '-int', '4') # Top left -> Desktop
  _d('com.apple.dock', 'wvous-tl-modifier', '-int', '0')
  _d('com.apple.dock', 'wvous-bl-corner', '-int', '0') # Bottom left -> No-op
  _d('com.apple.dock', 'wvous-bl-modifier', '-int', '0')
  _d('com.apple.dock', 'wvous-tr-corner', '-int', '2') # Top right -> Mission Control
  _d('com.apple.dock', 'wvous-tr-modifier', '-int', '0')
  _d('com.apple.dock', 'wvous-br-corner', '-int', '5') # Bottom right -> Start screen saver
  _d('com.apple.dock', 'wvous-br-modifier', '-int', '0')
end

# ---------------------------------------------------------------------------
# Safari & WebKit

if _ask("Privacy: don't send search queries to Apple", 'Y')
  _d('com.apple.Safari', 'UniversalSearchEnabled', '-bool', 'false')
  _d('com.apple.Safari', 'SuppressSearchSuggestions', '-bool', 'true')
end

if _ask('Show the full URL in the address bar', 'Y')
  _d('com.apple.Safari', 'ShowFullURLInSmartSearchField', '-bool', 'true')
end

if _ask("Set Safari's home page to 'about:blank' for faster loading", 'N')
  _d('com.apple.Safari', 'HomePage', '-string', 'about:blank')
end

if _ask("Prevent Safari from opening 'safe' files automatically after downloading", 'Y')
  _d('com.apple.Safari', 'AutoOpenSafeDownloads', '-bool', 'false')
end

if _ask('Allow hitting the Backspace key to go to the previous page in history', 'Y')
  _d('com.apple.Safari',
     'com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled',
     '-bool', 'true')
end

if _ask("Hide Safari's bookmarks bar by default", 'Y')
  _d('com.apple.Safari', 'ShowFavoritesBar', '-bool', 'false')
  _d('com.apple.Safari', 'ShowFavoritesBar-v2', '-bool', 'false')
end

if _ask("Hide Safari's sidebar in Top Sites", 'Y')
  _d('com.apple.Safari', 'ShowSidebarInTopSites', '-bool', 'false')
end

if _ask("Disable Safari's thumbnail cache for History and Top Sites", 'Y')
  _d('com.apple.Safari', 'DebugSnapshotsUpdatePolicy', '-int', '2')
end

if _ask("Enable Safari's debug menu", 'Y')
  _d('com.apple.Safari', 'IncludeInternalDebugMenu', '-bool', 'true')
  _d('com.apple.Safari', 'IncludeDebugMenu', '-bool', 'true')
end

if _ask("Make Safari's search banners default to Contains instead of Starts With", 'Y')
  _d('com.apple.Safari', 'FindOnPageMatchesWordStartsOnly', '-bool', 'false')
end

if _ask("Remove useless icons from Safari's bookmarks bar", 'Y')
  _d('com.apple.Safari', 'ProxiesInBookmarksBar', '()')
end

if _ask('Warn about fraudulent websites', 'Y')
  _d('com.apple.Safari', 'WarnAboutFraudulentWebsites', '-bool', 'true')
end

if _ask('Block pop-up windows', 'Y')
  _d('com.apple.Safari', 'WebKitJavaScriptCanOpenWindowsAutomatically', '-bool', 'false')
  _d('com.apple.Safari',
     'com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically',
     '-bool', 'false')
end

if _ask('Disable auto-playing video', 'Y')
  _d('com.apple.Safari', 'WebKitMediaPlaybackAllowsInline', '-bool', 'false')
  _d('com.apple.SafariTechnologyPreview', 'WebKitMediaPlaybackAllowsInline', '-bool', 'false')
  _d('com.apple.Safari',
     'com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback',
     '-bool', 'false')
  _d('com.apple.SafariTechnologyPreview',
     'com.apple.Safari.ContentPageGroupIdentifier.WebKit2AllowsInlineMediaPlayback',
     '-bool', 'false')
end

if _ask("Enable 'Do Not Track'", 'Y')
  _d('com.apple.Safari', 'SendDoNotTrackHTTPHeader', '-bool', 'true')
end

if _ask('Enable the Develop menu and the Web Inspector in Safari', 'N')
  _d('com.apple.Safari', 'IncludeDevelopMenu', '-bool', 'true')
  _d('com.apple.Safari', 'WebKitDeveloperExtrasEnabledPreferenceKey', '-bool', 'true')
  _d('com.apple.Safari',
     'com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled',
     '-bool', 'true')
end

if _ask('Increase page load speed in Safari (DNS prefetching)', 'Y')
  _d('com.apple.safari', 'WebKitDNSPrefetchingEnabled', '-bool', 'true')
end

if _ask('Disable Data Detectors', 'Y')
  _d('com.apple.Safari', 'WebKitUsesEncodingDetector', '-bool', 'false')
end

if _ask('Google Suggestion', 'Y')
  _d('com.apple.safari', 'DebugSafari4IncludeGoogleSuggest', '-bool', 'true')
end

if _ask('Automatically spell check web forms', 'Y')
  _d('com.apple.safari', 'WebContinuousSpellCheckingEnabled', '-bool', 'true')
end

if _ask('Automatically grammar check web forms', 'Y')
  _d('com.apple.safari', 'WebGrammarCheckingEnabled', '-bool', 'true')
end

if _ask('Include page background colors and images when printing', 'N')
  _d('com.apple.safari', 'WebKitShouldPrintBackgroundsPreferenceKey', '-bool', 'true')
end

d('com.apple.Safari', 'InstallExtensionUpdatesAutomatically', '-bool', 'true')

# ---------------------------------------------------------------------------
# Mail

if _ask('Display emails in threaded mode, sorted by date (oldest at the top)', 'Y')
  _d('com.apple.mail', 'DraftsViewerAttributes', '-dict-add', 'DisplayInThreadedMode', '-string', 'yes')
  _d('com.apple.mail', 'DraftsViewerAttributes', '-dict-add', 'SortedDescending', '-string', 'yes')
  _d('com.apple.mail', 'DraftsViewerAttributes', '-dict-add', 'SortOrder', '-string', 'received-date')
end

if _ask('Disable automatic spell checking', 'N')
  _d('com.apple.mail', 'SpellCheckingBehavior', '-string', 'NoSpellCheckingEnabled')
end

if _ask("Copy email addresses as 'foo@example.com' instead of 'Foo Bar <foo@example.com>' in Mail.app", 'N')
  _d('com.apple.mail', 'AddressesIncludeNameOnPasteboard', '-bool', 'false')
end

if _ask('Disable send and reply animations in Mail.app', 'N')
  _d('com.apple.Mail', 'DisableReplyAnimations', '-bool', 'true')
  _d('com.apple.Mail', 'DisableSendAnimations', '-bool', 'true')
end

if _ask('Set a minimum font size of 14px (affects reading and sending email)', 'N')
  _d('com.apple.mail', 'MinimumHTMLFontSize', '14')
end

if _ask('Force all Mail messages to display as plain text', 'N')
  _d('com.apple.mail', 'PreferPlainText', '-bool', 'TRUE')
end

if _ask('Disable tracking of Previous Recipients', 'N')
  _d('com.apple.mail', 'SuppressAddressHistory', '-bool', 'true')
end

if _ask('Send Windows friendly attachments', 'N')
  _d('com.apple.mail', 'SendWindowsFriendlyAttachments', '-bool', 'true')
end

# ---------------------------------------------------------------------------
# Spotlight

# Initial default seeded here. The user may enable/disable categories via
# System Settings > Spotlight afterward -- re-running osx-defaults.rb will
# reset them.
if _ask('Configure Spotlight search category ordering', 'Y')
  _d('com.apple.spotlight', 'orderedItems', '-array',
     '{"enabled" = 1;"name" = "APPLICATIONS";}',
     '{"enabled" = 1;"name" = "SYSTEM_PREFS";}',
     '{"enabled" = 0;"name" = "DIRECTORIES";}',
     '{"enabled" = 0;"name" = "PDF";}',
     '{"enabled" = 0;"name" = "FONTS";}',
     '{"enabled" = 0;"name" = "DOCUMENTS";}',
     '{"enabled" = 0;"name" = "MESSAGES";}',
     '{"enabled" = 0;"name" = "CONTACT";}',
     '{"enabled" = 0;"name" = "EVENT_TODO";}',
     '{"enabled" = 0;"name" = "IMAGES";}',
     '{"enabled" = 0;"name" = "BOOKMARKS";}',
     '{"enabled" = 0;"name" = "MUSIC";}',
     '{"enabled" = 0;"name" = "MOVIES";}',
     '{"enabled" = 0;"name" = "PRESENTATIONS";}',
     '{"enabled" = 0;"name" = "SPREADSHEETS";}',
     '{"enabled" = 1;"name" = "SOURCE";}',
     '{"enabled" = 1;"name" = "MENU_DEFINITION";}',
     '{"enabled" = 0;"name" = "MENU_OTHER";}',
     '{"enabled" = 1;"name" = "MENU_CONVERSION";}',
     '{"enabled" = 1;"name" = "MENU_EXPRESSION";}',
     '{"enabled" = 0;"name" = "MENU_WEBSEARCH";}',
     '{"enabled" = 0;"name" = "MENU_SPOTLIGHT_SUGGESTIONS";}')
end

if _ask('Load new settings before rebuilding the Spotlight index', 'Y')
  system('killall', 'mds', out: File::NULL, err: File::NULL)
end

if _ask('Disable Spotlight keyboard shortcut (Cmd+Space)', 'Y')
  # Key 64 in AppleSymbolicHotKeys controls "Show Spotlight search" (Cmd+Space).
  # Disabling it prevents Spotlight from stealing Cmd+Space, which is typically
  # reassigned to another launcher. Try Set first (key exists); fall back to Add.
  unless _pb('Set :AppleSymbolicHotKeys:64:enabled false', HOTKEYS_PLIST)
    _pb('Add :AppleSymbolicHotKeys:64:enabled bool false', HOTKEYS_PLIST)
  end
end

if _ask('Disable Spotlight Finder search window keyboard shortcut (Cmd+Option+Space)', 'Y')
  # Key 65 in AppleSymbolicHotKeys controls "Show Finder search window".
  unless _pb('Set :AppleSymbolicHotKeys:65:enabled false', HOTKEYS_PLIST)
    _pb('Add :AppleSymbolicHotKeys:65:enabled bool false', HOTKEYS_PLIST)
  end
end

# ---------------------------------------------------------------------------
# Terminal

if _ask('Terminal.app settings', 'Y')
  # Top-level Terminal.app defaults -- initial defaults seeded here so the user
  # can change them via the UI afterward without osx-defaults.rb resetting them.
  _d('com.apple.Terminal', 'NewWindowWorkingDirectoryBehavior', '-int', '2')
  _d('com.apple.Terminal', 'SecureKeyboardEntry', '-bool', 'false')
  _d('com.apple.Terminal', 'Shell', '-string', '')
  _d('com.apple.Terminal', 'Default Window Settings', '-string', 'Clear Dark')
  _d('com.apple.Terminal', 'Startup Window Settings', '-string', 'Clear Dark')

  ['Clear Dark'].each do |profile|
    # Profile names may contain spaces; quote them in PlistBuddy paths with single quotes.
    # Delete before Add is idempotent: suppress errors when the entry doesn't exist yet.
    _pbd("Delete :'Window Settings':'#{profile}':rowCount", TERMINAL_PLIST)
    _pb("Add :'Window Settings':'#{profile}':rowCount integer 30", TERMINAL_PLIST)
    _pbd("Delete :'Window Settings':'#{profile}':columnCount", TERMINAL_PLIST)
    _pb("Add :'Window Settings':'#{profile}':columnCount integer 120", TERMINAL_PLIST)
    # Profiles > Text > Font. Terminal stores Font as NSArchiver binary data, so osascript
    # is used to set font name/size as first-class properties on the settings set.
    # PostScript name: MesloLGSNF-Italic (from MesloLGS Nerd Font Italic).
    system('osascript', '-e',
           "tell application \"Terminal\" to set font name of settings set \"#{profile}\" to \"MesloLGSNF-Italic\"")
    system('osascript', '-e',
           "tell application \"Terminal\" to set font size of settings set \"#{profile}\" to 12")
    # Profiles > Keyboard > "Use Option as Meta key": makes Option+B/F send readline
    # word navigation escape sequences. Option+arrow keys still need bindkey in .zshrc.
    _pbd("Delete :'Window Settings':'#{profile}':useOptionAsMetaKey", TERMINAL_PLIST)
    _pb("Add :'Window Settings':'#{profile}':useOptionAsMetaKey bool true", TERMINAL_PLIST)
    # Profiles > Shell > "When the shell exits": 0=don't close, 1=close if exited cleanly.
    _pbd("Delete :'Window Settings':'#{profile}':shellExitAction", TERMINAL_PLIST)
    _pb("Add :'Window Settings':'#{profile}':shellExitAction integer 1", TERMINAL_PLIST)
    _pbd("Delete :'Window Settings':'#{profile}':noWarnProcesses", TERMINAL_PLIST)
    _pb("Add :'Window Settings':'#{profile}':noWarnProcesses array", TERMINAL_PLIST)
    _pb("Add :'Window Settings':'#{profile}':noWarnProcesses:0:ProcessName string screen", TERMINAL_PLIST)
    _pb("Add :'Window Settings':'#{profile}':noWarnProcesses:1:ProcessName string tmux", TERMINAL_PLIST)
    _pb("Add :'Window Settings':'#{profile}':noWarnProcesses:2:ProcessName string rlogin", TERMINAL_PLIST)
    _pb("Add :'Window Settings':'#{profile}':noWarnProcesses:3:ProcessName string ssh", TERMINAL_PLIST)
    _pb("Add :'Window Settings':'#{profile}':noWarnProcesses:4:ProcessName string slogin", TERMINAL_PLIST)
    _pb("Add :'Window Settings':'#{profile}':noWarnProcesses:5:ProcessName string telnet", TERMINAL_PLIST)
  end
end

# ---------------------------------------------------------------------------
# iTerm2

if _ask('iTerm2 settings', 'Y')
  {
    'AllowClipboardAccess' => ['-bool', 'true'],
    'AppleAntiAliasingThreshold' => ['-bool', 'true'],
    'AppleScrollAnimationEnabled' => ['-bool', 'false'],
    'AppleSmoothFixedFontsSizeThreshold' => ['-bool', 'true'],
    'AppleWindowTabbingMode' => ['-string', 'manual'],
    'AutoCommandHistory' => ['-bool', 'false'],
    'CheckTestRelease' => ['-bool', 'true'],
    'DimBackgroundWindows' => ['-bool', 'true'],
    'HideTab' => ['-bool', 'false'],
    'IRMemory' => ['-int', '4'],
    'NSFontPanelAttributes' => ['-string', '1, 0'],
    'NSNavLastRootDirectory' => ['-string', EnvVars::HOME.join('Desktop').to_s],
    'NSQuotedKeystrokeBinding' => ['-string', ''],
    'NSScrollAnimationEnabled' => ['-bool', 'false'],
    'NSScrollViewShouldScrollUnderTitlebar' => ['-bool', 'false'],
    'NoSyncCommandHistoryHasEverBeenUsed' => ['-bool', 'true'],
    'NoSyncDoNotWarnBeforeMultilinePaste' => ['-bool', 'true'],
    'NoSyncDoNotWarnBeforeMultilinePaste_selection' => ['-bool', 'false'],
    'NoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt' => ['-bool', 'true'],
    'NoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt_selection' => ['-bool', 'true'],
    'NoSyncHaveRequestedFullDiskAccess' => ['-bool', 'true'],
    'NoSyncHaveWarnedAboutPasteConfirmationChange' => ['-bool', 'true'],
    'NoSyncPermissionToShowTip' => ['-bool', 'true'],
    'NoSyncSuppressBroadcastInputWarning' => ['-bool', 'true'],
    'NoSyncSuppressBroadcastInputWarning_selection' => ['-bool', 'false'],
    'OnlyWhenMoreTabs' => ['-bool', 'false'],
    'OpenArrangementAtStartup' => ['-bool', 'false'],
    'OpenNoWindowsAtStartup' => ['-bool', 'false'],
    'PromptOnQuit' => ['-bool', 'false'],
    'SUAutomaticallyUpdate' => ['-bool', 'true'],
    'SUEnableAutomaticChecks' => ['-bool', 'true'],
    'SUFeedAlternateAppNameKey' => ['-string', 'iTerm'],
    'SUFeedURL' => ['-string', 'https://iterm2.com/appcasts/final.xml?shard=69'],
    'SUHasLaunchedBefore' => ['-bool', 'true'],
    'SUUpdateRelaunchingMarker' => ['-bool', 'false'],
    'SavePasteHistory' => ['-bool', 'false'],
    'ShowBookmarkName' => ['-bool', 'false'],
    'SplitPaneDimmingAmount' => ['-string', '0.4070612980769232'],
    'StatusBarPosition' => ['-integer', '1'],
    'SuppressRestartAnnouncement' => ['-bool', 'true'],
    'TabStyleWithAutomaticOption' => ['-integer', '4'],
    'TraditionalVisualBell' => ['-bool', 'true'],
    'UseBorder' => ['-bool', 'true'],
    'WordCharacters' => ['-string', '/-+\\~-integer.'],
    'findMode_iTerm' => ['-bool', 'false'],
    'kCPKSelectionViewPreferredModeKey' => ['-bool', 'false'],
    'kCPKSelectionViewShowHSBTextFieldsKey' => ['-bool', 'false']
  }.each { |key, args| d('com.googlecode.iterm2', key, *args) }

  # Profiles > Text > Font. Stored as "PostScriptName Size" plain string -- no binary encoding needed.
  # PostScript name: MesloLGSNF-Italic (from MesloLGS Nerd Font Italic).
  _pb("Set :'New Bookmarks':0:'Normal Font' 'MesloLGSNF-Italic 12'", ITERM_PLIST)

  # Profiles > Keys > Key Bindings -- Natural Text Editing.
  # Action 10 = send escape sequence; Action 11 = send hex code.
  # Key format: hex-keycode-modifierflags (0x80000=Option, 0x100000=Cmd,
  # 0x280000=Option+Shift, 0x300000=Ctrl+Shift).
  _pbd("Delete :'New Bookmarks':0:'Keyboard Map'", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map' dict", ITERM_PLIST)
  # Cmd+Delete -> send Ctrl+U (delete to beginning of line)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x100000' dict", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x100000':Action integer 11", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x100000':Text string '0x15'", ITERM_PLIST)
  # Option+Delete -> send Esc+Backspace (delete word backward)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x80000' dict", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x80000':Action integer 11", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'0x7f-0x80000':Text string '0x1b 0x7f'", ITERM_PLIST)
  # Option+Left -> send Esc+b (move back one word)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f702-0x280000' dict", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f702-0x280000':Action integer 10", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f702-0x280000':Text string b", ITERM_PLIST)
  # Ctrl+Left -> send Ctrl+A (move to beginning of line)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f702-0x300000' dict", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f702-0x300000':Action integer 11", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f702-0x300000':Text string '0x1'", ITERM_PLIST)
  # Option+Right -> send Esc+f (move forward one word)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f703-0x280000' dict", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f703-0x280000':Action integer 10", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f703-0x280000':Text string f", ITERM_PLIST)
  # Ctrl+Right -> send Ctrl+E (move to end of line)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f703-0x300000' dict", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f703-0x300000':Action integer 11", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f703-0x300000':Text string '0x5'", ITERM_PLIST)
  # Forward Delete -> send Ctrl+D (delete character under cursor)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f728-0x0' dict", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f728-0x0':Action integer 11", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f728-0x0':Text string '0x4'", ITERM_PLIST)
  # Option+Forward Delete -> send Esc+d (delete word forward)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f728-0x80000' dict", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f728-0x80000':Action integer 10", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Keyboard Map':'f728-0x80000':Text string d", ITERM_PLIST)

  # Ensure the New Bookmarks array exists; suppress error if already present (idempotent).
  system(PLISTBUDDY, '-c', "Add :'New Bookmarks' array", ITERM_PLIST, out: File::NULL, err: File::NULL)
  _pbd("Delete :'New Bookmarks':0:Rows", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:Rows integer 48", ITERM_PLIST)
  _pbd("Delete :'New Bookmarks':0:Columns", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:Columns integer 160", ITERM_PLIST)
  _pbd("Delete :'New Bookmarks':0:'Silence Bell'", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Silence Bell' bool false", ITERM_PLIST)
  _pbd("Delete :'New Bookmarks':0:'Unlimited Scrollback'", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Unlimited Scrollback' bool true", ITERM_PLIST)
  _pbd("Delete :'New Bookmarks':0:'Use Cursor Guide'", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Use Cursor Guide' bool true", ITERM_PLIST)
  _pbd("Delete :'New Bookmarks':0:'Visual Bell'", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Visual Bell' bool true", ITERM_PLIST)
  _pbd("Delete :'New Bookmarks':0:'Jobs to Ignore'", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Jobs to Ignore' array", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Jobs to Ignore':0 string screen", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Jobs to Ignore':1 string tmux", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Jobs to Ignore':2 string rlogin", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Jobs to Ignore':3 string ssh", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Jobs to Ignore':4 string slogin", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Jobs to Ignore':5 string telnet", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Jobs to Ignore':5 string zsh", ITERM_PLIST)
  _pbd("Delete :'New Bookmarks':0:'Minimum Contrast'", ITERM_PLIST)
  _pb("Add :'New Bookmarks':0:'Minimum Contrast' integer 0", ITERM_PLIST)
end

# ---------------------------------------------------------------------------
# Google Chrome

if _ask('Chrome settings', 'Y')
  %w[com.google.Chrome com.google.Chrome.beta com.google.Chrome.canary].each do |bundle|
    _d(bundle, 'AppleEnableMouseSwipeNavigateWithScrolls', '-bool', 'false')
    _d(bundle, 'AppleEnableSwipeNavigateWithScrolls', '-bool', 'false')
  end
  _d('com.google.Chrome', 'KeychainReauthorizeInAppSpring2017', '-int', '2')
  _d('com.google.Chrome', 'KeychainReauthorizeInAppSpring2017Success', '-bool', 'true')
end

# ---------------------------------------------------------------------------
# KeepassXC

if _ask('KeepassXC settings', 'Y')
  _d('org.keepassxc.keepassxc', 'NSNavLastRootDirectory', '-string',
     EnvVars::HOME.join('personal', USER).to_s)
end

# ---------------------------------------------------------------------------
# Monolingual

if _ask('Monolingual settings', 'Y')
  _d('net.sourceforge.Monolingual', 'SUAutomaticallyUpdate', '-bool', 'true')
  _d('net.sourceforge.Monolingual', 'SUEnableAutomaticChecks', '-bool', 'true')
  _d('net.sourceforge.Monolingual', 'SUSendProfileInfo', '-bool', 'false')
  _d('net.sourceforge.Monolingual', 'Strip', '-bool', 'true')
end

# ---------------------------------------------------------------------------
# ProtonVPN

if _ask('ProtonVpn settings', 'Y')
  {
    'ConnectOnDemand' => ['-bool', 'true'],
    'EarlyAccess' => ['-bool', 'true'],
    # Firewall and alternativeRouting are user-configurable network preferences,
    # not session/account state -- safe to codify.
    'Firewall' => ['-bool', 'false'],
    'NSInitialToolTipDelay' => ['-int', '500'],
    'RememberLoginAfterUpdate' => ['-bool', 'true'],
    'SUAutomaticallyUpdate' => ['-bool', 'true'],
    'SUEnableAutomaticChecks' => ['-bool', 'false'],
    'SecureCoreToggle' => ['-bool', 'false'],
    'StartMinimized' => ['-bool', 'true'],
    'StartOnBoot' => ['-bool', 'true'],
    'SystemNotifications' => ['-bool', 'true'],
    'alternativeRouting' => ['-bool', 'true']
  }.each { |key, args| d('ch.protonvpn.mac', key, *args) }
end

# ---------------------------------------------------------------------------
# Thunderbird

if _ask('Thunderbird settings', 'Y')
  _d('org.mozilla.thunderbird', 'NSFullScreenMenuItemEverywhere', '-bool', 'false')
  _d('org.mozilla.thunderbird', 'NSTreatUnknownArgumentsAsOpen', '-bool', 'false')
end

# ---------------------------------------------------------------------------
# Zoom

if _ask('Zoomus settings', 'Y')
  {
    'BounceApplicationSetting' => ['-int', '2'],
    'NSInitialToolTipDelay' => ['-int', '100'],
    'NSQuitAlwaysKeepsWindows' => ['-bool', 'false'],
    'kZPSettingShowCodeSnippet' => ['-bool', 'true'],
    'kZPSettingShowLinkPreview' => ['-bool', 'true']
  }.each { |key, args| d('us.zoom.xos', key, *args) }
  {
    'ZMEnableShowUserName' => ['-bool', 'true'],
    'ZoomAutoCopyInvitationURL' => ['-bool', 'true'],
    'ZoomEnableShow49WallViewKey' => ['-bool', 'true'],
    'ZoomEnterFullscreenWhenViewShare' => ['-bool', 'false'],
    'ZoomEnterMaxWndWhenViewShare' => ['-bool', 'true'],
    'ZoomFitDock' => ['-bool', 'true'],
    'ZoomFitXPos' => ['-int', '727'],
    'ZoomFitYPos' => ['-int', '1023'],
    'ZoomRememberPhoneKey' => ['-bool', 'true']
  }.each { |key, args| d('ZoomChat', key, *args) }
end

# ---------------------------------------------------------------------------
# Clocker

if _ask('Clocker settings', 'Y')
  # Skip: SelectedCalendars (iCloud Calendar UUIDs -- denial criterion #2) and
  # defaultPreferences (binary NSData blobs -- not portably expressible).
  {
    'com.abhishek.menubarCompactMode' => ['-int', '0'],
    'com.abhishek.shouldDefaultToCompactMode' => ['-bool', 'true'],
    'defaultTheme' => ['-int', '2'],
    'displayAppAsForegroundApp' => ['-bool', 'false'],
    'is24HourFormatSelected' => ['-int', '6'],
    'relativeDate' => ['-bool', 'true'],
    'showDate' => ['-bool', 'false'],
    'showSeconds' => ['-bool', 'false'],
    'showSunriseSetTime' => ['-bool', 'false'],
    'sliderDayRange' => ['-int', '4'],
    'startAtLogin' => ['-bool', 'true'],
    'userFontSize' => ['-int', '7']
  }.each { |key, args| d('com.abhishek.Clocker', key, *args) }
end

# ---------------------------------------------------------------------------
# DBeaver

if _ask('DBeaver settings', 'Y')
  {
    'NSAutomaticDashSubstitutionEnabled' => ['-bool', 'false'],
    'NSAutomaticQuoteSubstitutionEnabled' => ['-bool', 'false'],
    'NSInitialToolTipDelay' => ['-int', '300'],
    'NSScrollAnimationEnabled' => ['-bool', 'false']
  }.each { |key, args| d('org.jkiss.dbeaver.core.product', key, *args) }
end

# ---------------------------------------------------------------------------
# DockDoor
# Login item: registered via Brewfile's setup_login_items_script (SMAppService).
# DockDoor has no defaults key for login-item status.

if _ask('DockDoor settings', 'Y')
  {
    'SUAutomaticallyUpdate' => ['-bool', 'true'],
    'SUEnableAutomaticChecks' => ['-bool', 'true'],
    'SUSendProfileInfo' => ['-bool', 'false'],
    'cmdTabEnabledTrafficLightButtons' => ['-array', 'maximize', 'quit', 'close', 'minimize'],
    'enableCmdTabEnhancements' => ['-bool', 'true'],
    'enabledTrafficLightButtons' => ['-array', 'quit', 'close', 'maximize', 'minimize'],
    'reopenSettingsAfterRestart' => ['-bool', 'false']
  }.each { |key, args| d('com.ethanbills.DockDoor', key, *args) }
end

# ---------------------------------------------------------------------------
# Drawio

if _ask('Drawio settings', 'Y')
  _d('com.jgraph.drawio.desktop', 'AppleTextDirection', '-bool', 'true')
  _d('com.jgraph.drawio.desktop', 'NSForceRightToLeftWritingDirection', '-bool', 'false')
  _d('com.jgraph.drawio.desktop', 'NSTreatUnknownArgumentsAsOpen', '-bool', 'false')
end

# ---------------------------------------------------------------------------
# Firefox
# _firefox_user_js_content is defined as FIREFOX_USER_JS constant at the top of
# this file so the Zen Browser section can reference it even if the user skips
# Firefox settings. user.js is the correct idempotent mechanism: Firefox overwrites
# prefs.js on every launch, but sources user.js at startup and re-applies it.

if _ask('Firefox settings', 'Y')
  # macOS-level NS* keys for all Firefox-family bundles.
  %w[org.mozilla.firefox org.mozilla.nightly org.mozilla.floorp org.mozilla.thunderbird.betterbird].each do |bundle|
    _d(bundle, 'NSFullScreenMenuItemEverywhere', '-bool', 'false')
    _d(bundle, 'NSNavLastRootDirectory', '-string', EnvVars::HOME.join('Downloads').to_s)
    _d(bundle, 'NSNavLastUserSetHideExtensionButtonState', '-bool', 'false')
    _d(bundle, 'NSTreatUnknownArgumentsAsOpen', '-bool', 'false')
    _d(bundle, 'PMPrintingExpandedStateForPrint2', '-bool', 'false')
  end

  ff_profiles_root = EnvVars::HOME.join('Library', 'Application Support', 'Firefox', 'Profiles')
  if ff_profiles_root.directory?
    PathUtils.glob_pathnames(ff_profiles_root.join('*')).select(&:directory?).each do |profile_dir_pn|
      profile_dir_pn.join('user.js').write(FIREFOX_USER_JS)
      success("Wrote user.js -> #{profile_dir_pn}")
    end
  end
end

# ---------------------------------------------------------------------------
# Keybase
# Login item: registered via Brewfile's setup_login_items_script (SMAppService).
# Keybase has no defaults key for login-item status.

if _ask('Keybase settings', 'Y')
  _d('keybase.Electron', 'AppleTextDirection', '-bool', 'true')
  _d('keybase.Electron', 'NSForceRightToLeftWritingDirection', '-bool', 'false')
  _d('keybase.Electron', 'NSFullScreenMenuItemEverywhere', '-bool', 'false')
  _d('keybase.Electron', 'NSTreatUnknownArgumentsAsOpen', '-bool', 'false')
end

# ---------------------------------------------------------------------------
# MechVibes
# Login item: registered via Brewfile's setup_login_items_script (SMAppService).
# MechVibes has no defaults key for login-item status.

if _ask('MechVibes settings', 'Y')
  # Skip: NSStatusItem Preferred Position Item-0 -- menu bar pixel coordinate (criterion 4).
  _d('com.electron.mechvibes', 'NSFullScreenMenuItemEverywhere', '-bool', 'false')
  _d('com.electron.mechvibes', 'NSTreatUnknownArgumentsAsOpen', '-bool', 'false')
end

# ---------------------------------------------------------------------------
# KeyCastr
# Login item: registered via Brewfile's setup_login_items_script (SMAppService).
# KeyCastr has no defaults key for login-item status.

if _ask('KeyCastr settings', 'Y')
  # Skip: default.textColor -- binary NSKeyedArchiver blob with embedded ICC profile;
  # not portably expressible as a defaults write argument.
  {
    'SUEnableAutomaticChecks' => ['-bool', 'true'],
    'SUSendProfileInfo' => ['-bool', 'false'],
    'alwaysShowPrefs' => ['-bool', 'false'],
    'default.allKeys' => ['-bool', 'true'],
    'default.allModifiedKeys' => ['-bool', 'false'],
    'default.commandKeysOnly' => ['-bool', 'false'],
    'default.fadeDelay' => ['-float', '2.576526409646739'],
    'default.fadeDuration' => ['-bool', 'true'],
    'default.fontSize' => ['-float', '47.2836277173913'],
    'default.keystrokeDelay' => ['-bool', 'true'],
    'default_displayModifiedCharacters' => ['-bool', 'true'],
    'displayIcon' => ['-bool', 'true'],
    'mouse.displayOption' => ['-bool', 'true'],
    'selectedVisualizer' => ['-string', 'Default']
  }.each { |key, args| d('io.github.keycastr', key, *args) }
end

# ---------------------------------------------------------------------------
# KeyClu

if _ask('KeyClu settings', 'Y')
  {
    'SUAutomaticallyUpdate' => ['-bool', 'true'],
    'SUEnableAutomaticChecks' => ['-bool', 'true'],
    'SUSendProfileInfo' => ['-bool', 'false'],
    'activationKeyId' => ['-int', '0'],
    'activationKeyType' => ['-int', '1'],
    'activationPersistentKeyType' => ['-int', '0'],
    'appearance' => ['-string', 'system'],
    'applyLimitToTitles' => ['-bool', 'false'],
    'hideMenuIcon' => ['-bool', 'false'],
    'launchAtLogin' => ['-bool', 'true'],
    'limitTitles' => ['-int', '75'],
    'makeItBloom' => ['-bool', 'true'],
    'makeItRainbow' => ['-bool', 'false'],
    'shortcutColors' => ['-string', '1BBFF9FF,28CD41FF,FFCC00FF,FF9500FF,FF3930FF,AF52DDFF,FF2D53FF'],
    'showAppIcon' => ['-bool', 'false'],
    'showHighlight' => ['-bool', 'true'],
    'showUserHiddenElements' => ['-bool', 'true'],
    'silentLaunchQuit' => ['-bool', 'true']
  }.each { |key, args| d('com.0804Team.KeyClu', key, *args) }
end

# ---------------------------------------------------------------------------
# OnlyOffice

if _ask('OnlyOffice settings', 'Y')
  # Skip: asc_save_path (machine-specific path) and asc_user_name_app (personal name).
  {
    'AppleLanguages' => ['-array', 'en-US'],
    'AppleLocale' => ['-string', 'en-US'],
    'NSDisabledCharacterPaletteMenuItem' => ['-bool', 'false'],
    'NSDisabledDictationMenuItem' => ['-bool', 'true'],
    'NSForceLeftToRightWritingDirection' => ['-bool', 'true'],
    'SUAutomaticallyUpdate' => ['-bool', 'true'],
    'SUEnableAutomaticChecks' => ['-bool', 'true'],
    'SUSendProfileInfo' => ['-bool', 'false'],
    'asc_user_docOpenMode' => ['-string', 'edit'],
    'asc_user_ui_lang' => ['-string', 'en-US'],
    'asc_user_ui_theme' => ['-string', 'theme-light']
  }.each { |key, args| d('asc.onlyoffice.ONLYOFFICE', key, *args) }
end

# ---------------------------------------------------------------------------
# Rancher Desktop

if _ask('Rancher Desktop settings', 'Y')
  _d('io.rancherdesktop.app', 'AppleTextDirection', '-bool', 'true')
  _d('io.rancherdesktop.app', 'NSForceRightToLeftWritingDirection', '-bool', 'false')
  _d('io.rancherdesktop.app', 'NSFullScreenMenuItemEverywhere', '-bool', 'false')
  _d('io.rancherdesktop.app', 'NSTreatUnknownArgumentsAsOpen', '-bool', 'false')
end

# ---------------------------------------------------------------------------
# Shortcat
# Login item: registered via Brewfile's setup_login_items_script (SMAppService).
# Shortcat has no defaults key for login-item status.

if _ask('Shortcat settings', 'Y')
  # Skip: telemetryIdentifier -- device UUID (denial criterion #1).
  # KeyboardShortcuts_* keys are plain JSON strings encoding key codes and modifiers.
  {
    'KeyboardShortcuts_click' => ['-string', '{"carbonModifiers":0,"carbonKeyCode":36}'],
    'KeyboardShortcuts_debugElement' => ['-string', '{"carbonModifiers":256,"carbonKeyCode":119}'],
    'KeyboardShortcuts_reloadUI' => ['-string', '{"carbonModifiers":768,"carbonKeyCode":15}'],
    'KeyboardShortcuts_toggleLockUI' => ['-string', '{"carbonKeyCode":115,"carbonModifiers":256}'],
    'KeyboardShortcuts_toggleShortcat' => ['-string', '{"carbonModifiers":2304,"carbonKeyCode":49}'],
    'downKeycode' => ['-int', '38'],
    'leftKeycode' => ['-int', '4'],
    'rightKeycode' => ['-int', '37'],
    'upKeycode' => ['-int', '40']
  }.each { |key, args| d('com.sproutcube.Shortcat', key, *args) }
end

# ---------------------------------------------------------------------------
# Sol
# Login item: registered via Brewfile's setup_login_items_script (SMAppService).
# Sol has no defaults key for login-item status.

if _ask('Sol settings', 'Y')
  # Skip: NSWindow Frame * (display geometry -- denial criterion #4),
  # SUHasLaunchedBefore (one-time setup sentinel -- denial criterion #5),
  # SULastCheckTime (ephemeral timestamp -- denial criterion #3),
  # SUUpdateGroupIdentifier (internal Sparkle grouping ID, not user-configurable).
  _d('com.ospfranco.sol', 'RCTI18nUtil_makeRTLFlipLeftAndRightStyles', '-bool', 'true')
  _d('com.ospfranco.sol', 'SUAutomaticallyUpdate', '-bool', 'true')
  _d('com.ospfranco.sol', 'SUEnableAutomaticChecks', '-bool', 'true')
  _d('com.ospfranco.sol', 'SUSendProfileInfo', '-bool', 'false')
end

# ---------------------------------------------------------------------------
# Stats

if _ask('Stats settings', 'Y')
  # Skip: id, remote_id (device UUIDs -- denial criterion #1), ble_*, sensor_*, *_ts
  # (ephemeral sync state -- denial criterion #3), remote_tokens_migrated_to_keychain,
  # Clock_list (per-entry UUIDs -- denial criterion #1), version, NSStatusItem
  # Preferred/Restore Position (display geometry -- denial criterion #4).
  {
    'BAT_mini_alignment' => ['-string', 'right'],
    'BAT_mini_color' => ['-string', 'system'],
    'BAT_mini_label' => ['-bool', 'true'],
    'Battery_barChart_position' => ['-int', '3'],
    'Battery_bar_chart_label' => ['-bool', 'true'],
    'Battery_battery_additional' => ['-string', 'percentage'],
    'Battery_battery_color' => ['-bool', 'true'],
    'Battery_battery_position' => ['-int', '1'],
    'Battery_color' => ['-bool', 'true'],
    'Battery_label_position' => ['-int', '2'],
    'Battery_mini_position' => ['-int', '0'],
    'Battery_notifications_high' => ['-string', ''],
    'Battery_notifications_low' => ['-string', 'low'],
    'Battery_state' => ['-bool', 'true'],
    'Battery_widget' => ['-string', 'mini'],
    'Bluetooth_label_position' => ['-int', '1'],
    'Bluetooth_sensors_position' => ['-int', '1'],
    'Bluetooth_stack_position' => ['-int', '0'],
    'Bluetooth_state' => ['-bool', 'false'],
    'Bluetooth_widget' => ['-string', 'sensors'],
    'CPU_barChart_position' => ['-int', '3'],
    'CPU_label_position' => ['-int', '1'],
    'CPU_lineChart_position' => ['-int', '0'],
    'CPU_line_chart_box' => ['-bool', 'false'],
    'CPU_line_chart_color' => ['-string', 'system'],
    'CPU_line_chart_frame' => ['-bool', 'false'],
    'CPU_line_chart_label' => ['-bool', 'true'],
    'CPU_line_chart_value' => ['-bool', 'true'],
    'CPU_line_chart_valueColor' => ['-bool', 'true'],
    'CPU_mini_color' => ['-string', 'Monochrome accent'],
    'CPU_mini_position' => ['-int', '2'],
    'CPU_notifications_totalLoad' => ['-string', 'Disabled'],
    'CPU_pieChart_position' => ['-int', '4'],
    'CPU_state' => ['-bool', 'false'],
    'CPU_tachometer_position' => ['-int', '5'],
    'CPU_widget' => ['-string', 'line_chart'],
    'Clock_label_position' => ['-int', '1'],
    'Clock_stack_position' => ['-int', '0'],
    'Clock_state' => ['-bool', 'false'],
    'Clock_widget' => ['-string', 'sensors'],
    'CombinedModules' => ['-bool', 'false'],
    'Disk_removable' => ['-bool', 'false'],
    'Disk_state' => ['-bool', 'true'],
    'Disk_widget' => ['-string', 'mini'],
    'Fans_state' => ['-bool', 'false'],
    'GPU_notifications_usage_state' => ['-bool', 'true'],
    'GPU_notifications_usage_value' => ['-int', '80'],
    'GPU_state' => ['-bool', 'false'],
    'LaunchAtLoginNext' => ['-bool', 'true'],
    'NSStatusItem Visible Battery' => ['-bool', 'true'],
    'NSStatusItem Visible CPU_Bar chart' => ['-bool', 'false'],
    'NSStatusItem Visible CPU_Line chart' => ['-bool', 'true'],
    'NSStatusItem Visible CPU_Mini' => ['-bool', 'false'],
    'NSStatusItem Visible CPU_Pie chart' => ['-bool', 'false'],
    'NSStatusItem Visible Disk_Bar chart' => ['-bool', 'false'],
    'NSStatusItem Visible Disk_Memory' => ['-bool', 'false'],
    'NSStatusItem Visible Disk_Speed' => ['-bool', 'false'],
    'NSStatusItem Visible Fans' => ['-bool', 'false'],
    'NSStatusItem Visible Fans_Text' => ['-bool', 'false'],
    'NSStatusItem Visible GPU' => ['-bool', 'false'],
    'NSStatusItem Visible GPU_Bar chart' => ['-bool', 'false'],
    'NSStatusItem Visible GPU_Line chart' => ['-bool', 'false'],
    'NSStatusItem Visible GPU_Mini' => ['-bool', 'false'],
    'NSStatusItem Visible Network_Network chart' => ['-bool', 'false'],
    'NSStatusItem Visible Network_Speed' => ['-bool', 'true'],
    'NSStatusItem Visible RAM_Bar chart' => ['-bool', 'false'],
    'NSStatusItem Visible RAM_Line chart' => ['-bool', 'true'],
    'NSStatusItem Visible RAM_Memory' => ['-bool', 'false'],
    'NSStatusItem Visible RAM_Mini' => ['-bool', 'false'],
    'NSStatusItem Visible RAM_Pie chart' => ['-bool', 'false'],
    'NSStatusItem Visible Sensors' => ['-bool', 'false'],
    'NSStatusItem Visible Sensors_Text' => ['-bool', 'false'],
    'Network_speed_base' => ['-string', 'byte'],
    'Network_speed_icon' => ['-string', 'arrows'],
    'Network_speed_valueColor' => ['-bool', 'true'],
    'RAM_line_chart_box' => ['-bool', 'false'],
    'RAM_line_chart_color' => ['-string', 'utilization'],
    'RAM_line_chart_frame' => ['-bool', 'false'],
    'RAM_line_chart_label' => ['-bool', 'true'],
    'RAM_line_chart_value' => ['-bool', 'true'],
    'RAM_line_chart_valueColor' => ['-bool', 'true'],
    'RAM_notifications_totalUsage' => ['-string', 'Disabled'],
    'RAM_widget' => ['-string', 'line_chart'],
    'SSD_mini_color' => ['-string', 'utilization'],
    'Sensors_speed' => ['-bool', 'true'],
    'dockIcon' => ['-bool', 'false'],
    'telemetry' => ['-bool', 'false'],
    'update-interval' => ['-string', 'Once per day']
  }.each { |key, args| d('eu.exelban.Stats', key, *args) }
end

# ---------------------------------------------------------------------------
# Thaw (Ice fork)
# Login item: registered via Brewfile's setup_login_items_script (SMAppService).
# Thaw has no defaults key for login-item status.

if _ask('Thaw settings', 'Y')
  # Skip: Hotkeys (all values are null -- PlistBuddy cannot write NSNull portably),
  # MenuBarAppearanceConfigurationV2, MenuBarItemManager.*, DisplayIceBarConfigurations
  # (all contain per-display UUIDs -- denial criterion #4), hasMigrated* flags
  # (one-time migration sentinels). IceIcon is stored as raw bytes but the JSON
  # content is fully portable; writing as -string causes macOS to store it as
  # NSString, which Thaw reads correctly.
  {
    'AutoRehide' => ['-bool', 'true'],
    'CustomIceIconIsTemplate' => ['-bool', 'false'],
    'EnableAlwaysHiddenSection' => ['-bool', 'true'],
    'EnableDiagnosticLogging' => ['-bool', 'false'],
    'EnableSecondaryContextMenu' => ['-bool', 'true'],
    'HideApplicationMenus' => ['-bool', 'true'],
    'IceBarLocation' => ['-int', '0'],
    'IceBarLocationOnHotkey' => ['-int', '0'],
    'IceIcon' => ['-string', '{"hidden":{"catalog":{"_0":"IceCubeStroke"}},"visible":{"catalog":{"_0":"IceCubeFill"}},"name":"Ice Cube"}'],
    'IconRefreshInterval' => ['-string', '0.5'],
    'ItemSpacingOffset' => ['-int', '0'],
    'RehideInterval' => ['-int', '15'],
    'RehideStrategy' => ['-int', '0'],
    'SUAutomaticallyUpdate' => ['-bool', 'true'],
    'SUEnableAutomaticChecks' => ['-bool', 'true'],
    'SectionDividerStyle' => ['-int', '1'],
    'ShowAllSectionsOnUserDrag' => ['-bool', 'true'],
    'ShowIceIcon' => ['-bool', 'true'],
    'ShowMenuBarTooltips' => ['-bool', 'false'],
    'ShowOnClick' => ['-bool', 'true'],
    'ShowOnDoubleClick' => ['-bool', 'true'],
    'ShowOnHover' => ['-bool', 'true'],
    'ShowOnHoverDelay' => ['-string', '0.2'],
    'ShowOnScroll' => ['-bool', 'true'],
    'TooltipDelay' => ['-string', '0.5'],
    'UseIceBar' => ['-bool', 'true'],
    'UseIceBarOnlyOnNotchedDisplay' => ['-bool', 'false']
  }.each { |key, args| d('com.stonerl.Thaw', key, *args) }
end

# ---------------------------------------------------------------------------
# Zen Browser

if _ask('Zen Browser settings', 'Y')
  # Two bundle IDs in use across Zen versions.
  %w[app.zen-browser.zen org.mozilla.com.zen.browser].each do |bundle|
    _d(bundle, 'NSFullScreenMenuItemEverywhere', '-bool', 'false')
    _d(bundle, 'NSTreatUnknownArgumentsAsOpen', '-bool', 'false')
  end

  # user.js written to the Zen profile dir (same mechanism as Firefox -- see comment there).
  zen_profiles_root = EnvVars::HOME.join('Library', 'Application Support', 'Zen', 'Profiles')
  if zen_profiles_root.directory?
    PathUtils.glob_pathnames(zen_profiles_root.join('*')).select(&:directory?).each do |profile_dir_pn|
      profile_dir_pn.join('user.js').write(FIREFOX_USER_JS)
      success("Wrote user.js -> #{profile_dir_pn}")
    end
  end
end

# ---------------------------------------------------------------------------
# Activity Monitor

if _ask('Show the main window when launching Activity Monitor', 'Y')
  _d('com.apple.ActivityMonitor', 'OpenMainWindow', '-bool', 'true')
end

if _ask('Visualize CPU usage in the Dock icon', 'Y')
  _d('com.apple.ActivityMonitor', 'IconType', '-int', '5')
end

if _ask('Show all processes hierarchically', 'Y')
  _d('com.apple.ActivityMonitor', 'ShowCategory', '-int', '101')
end

if _ask('Sort Activity Monitor results by CPU usage', 'Y')
  _d('com.apple.ActivityMonitor', 'SortColumn', '-string', 'CPUUsage')
  _d('com.apple.ActivityMonitor', 'SortDirection', '-int', '0')
end

if _ask('Default to showing the Network tab', 'Y')
  _d('com.apple.ActivityMonitor', 'SelectedTab', '-int', '4')
end

# ---------------------------------------------------------------------------
# Photos

if _ask('Prevent Photos from opening automatically when devices are plugged in', 'Y')
  _dh('com.apple.ImageCapture', 'disableHotPlug', '-bool', 'true')
end

# ---------------------------------------------------------------------------
# Software Update

if _ask('Automatically check for updates (required for any downloads)', 'Y')
  _d('com.apple.SoftwareUpdate', 'AutomaticCheckEnabled', '-bool', 'true')
end

if _ask('Download updates automatically in the background', 'Y')
  system('sudo', 'defaults', 'write',
         '/Library/Preferences/com.apple.SoftwareUpdate', 'AutomaticDownload', '-bool', 'true')
end

if _ask('Install app updates automatically', 'Y')
  _d('com.apple.commerce', 'AutoUpdate', '-bool', 'true')
end

if _ask('Install macOS updates automatically', 'Y')
  _d('com.apple.commerce', 'AutoUpdateRestartRequired', '-bool', 'true')
end

if _ask('Install system data file updates automatically', 'Y')
  _d('com.apple.SoftwareUpdate', 'ConfigDataInstall', '-bool', 'true')
end

if _ask('Install critical security updates automatically', 'Y')
  _d('com.apple.SoftwareUpdate', 'CriticalUpdateInstall', '-bool', 'true')
end

if _ask('Check for software updates daily, not just once per week', 'Y')
  _d('com.apple.SoftwareUpdate', 'ScheduleFrequency', '-int', '1')
end

# Mac App Store
d('com.apple.appstore', 'WebKitDeveloperExtras', '-bool', 'true')
d('com.apple.appstore', 'ShowDebugMenu', '-bool', 'true')
d('-g', 'WebKitDeveloperExtras', '-bool', 'true')

# Time Machine
d('com.apple.TimeMachine', 'DoNotOfferNewDisksForBackup', '-bool', 'true')

# ---------------------------------------------------------------------------
# Screen

# Require password immediately after sleep or screen saver begins.
d('com.apple.screensaver', 'askForPassword', '-bool', 'true')
d('com.apple.screensaver', 'askForPasswordDelay', '-int', '0')

# Enable subpixel font rendering on non-Apple LCDs (0=off, 1=light, 2=Medium/flat panel, 3=strong/blurred).
d('-g', 'AppleFontSmoothing', '-int', '2')
system('sudo', 'defaults', 'write',
       '/Library/Preferences/com.apple.windowserver', 'DisplayResolutionEnabled', '-bool', 'true')

# Screen capture
d('com.apple.screencapture', 'location', '-string', EnvVars::HOME.join('Desktop').to_s)
d('com.apple.screencapture', 'type', '-string', 'png')
d('com.apple.screencapture', 'disable-shadow', '-bool', 'true')
d('com.apple.screencaptureui', 'thumbnailExpiration', '-float', '15')

# Address Book
# com.apple.AddressBook is sandbox-restricted on modern macOS; writes fail with
# "Could not write domain" even as the file owner. Suppress the error -- the
# settings are effectively read-only via this path on current OS versions.
system('defaults', 'write', 'com.apple.AddressBook', 'ABBirthDayVisible',
       '-bool', 'true', out: File::NULL, err: File::NULL)
system('defaults', 'write', 'com.apple.AddressBook', 'ABDefaultAddressCountryCode',
       '-string', 'in', out: File::NULL, err: File::NULL)

# Spaces: when switching applications, switch to respective space.
d('-g', 'AppleSpacesSwitchOnActivate', '-bool', 'true')

# ---------------------------------------------------------------------------
# Kill affected applications

[
  'Activity Monitor',
  'Address Book',
  'App Store',
  'Calendar',
  'cfprefsd',
  'Contacts',
  'Dock',
  'Finder',
  'Google Chrome Beta',
  'Google Chrome Canary',
  'Google Chrome',
  'iCal',
  'Mail',
  'Safari',
  'ScreenSaverEngine',
  'SizeUp',
  'SystemUIServer'
].each { |app| system('killall', app, out: File::NULL, err: File::NULL) }

# Re-activate symbolic hotkey settings so changes to AppleSymbolicHotKeys
# (e.g. disabling the Spotlight shortcuts) take effect immediately without a
# logout. activateSettings is the only supported way to flush this plist.
system(
  '/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings',
  '-u'
)

# Turn off Spotlight indexing for all volumes.
system('sudo', 'mdutil', '-Eda', out: File::NULL, err: File::NULL)
system('sudo', 'mdutil', '-ai', 'off', out: File::NULL, err: File::NULL)

user_action("Grant Full Disk Access to 'Terminal' and 'iTerm': System Settings → Privacy & Security → Full Disk Access → add 'Terminal.app' and 'iTerm.app' (cannot be automated -- TCC is SIP-protected).")
user_action('Manually adjust the Finder sidebar content (which folders appear in Favorites): stored in LSSharedFileList binary files -- not scriptable via defaults.')
user_action("The following apps have to be manually quit and restarted for their settings to be reloaded:
  'Terminal' and 'iTerm' (since one of these might be running this script),
  'ProtonVPN' (force-quitting may drop the VPN connection),
  'Zoom' (force-quitting during a call would disconnect it),
  'Thunderbird',
  'KeePassXC'")

# at_exit hook (registered above) prints success + summary, restarts login-item
# apps, and resumes the software update schedule on any exit path.
