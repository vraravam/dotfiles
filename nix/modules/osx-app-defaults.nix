{ config, ... }:
# User-level macOS defaults applied via `defaults write` on every darwin-rebuild switch.
#
# POLICY SETTINGS ONLY — see two-phase preference architecture rule in
# .github/copilot-instructions.md § "osx-defaults.sh and capture-prefs".
#
# Only settings the user would NEVER want reverted to a declared value after
# changing them in the app UI belong here. The test: "Would I want this reset
# on every bupc even if I changed it yesterday?" If no → osx-defaults.sh.
#
# Not included here:
#   - Initial defaults (user-configurable app prefs) → osx-defaults.sh
#   - Ephemeral state (NSNavLastRootDirectory, window coords, migration
#     sentinels, A/B test shards) → neither file; apps manage these
#   - Settings requiring sudo / systemsetup / pmset / scutil → osx-defaults.sh
#   - defaults -currentHost writes → osx-defaults.sh
#   - PlistBuddy writes (Terminal/iTerm2 profiles, Finder icon view, Spotlight
#     hotkeys) → osx-defaults.sh
#   - defaults -dict-add patterns (Mail DraftsViewerAttributes,
#     Finder FXInfoPanesExpanded) → osx-defaults.sh
#   - Firefox / Zen Browser user.js file writes → osx-defaults.sh
#   - ask-N defaults (intentionally left interactive) → osx-defaults.sh
{
  targets.darwin.defaults = {

    # -------------------------------------------------------------------------
    # macOS system daemons / Control Center / Menu Bar
    # -------------------------------------------------------------------------

    # NSStatusItem values: 0/false = hidden, 1/true = shown, 8 = when active.
    "com.apple.controlcenter" = {
      "NSStatusItem Visible Bluetooth" = 1;
      "NSStatusItem Visible WiFi" = true;
      "NSStatusItem Visible Battery" = 0;
      "NSStatusItem VisibleCC Clock" = false;   # use Clocker instead
      "NSStatusItem Visible Spotlight" = false; # use Sol instead
      "NSStatusItem Visible AirDrop" = false;
      "NSStatusItem Visible TextInput" = false;
      "NSStatusItem Visible KeyboardBrightness" = false;
      "NSStatusItem Visible Weather" = false;
      # 8 = show when active; 16 = always; 24 = never
      FocusModes = 8;
      AirPlayDisplay = 8;
      Display = 8;
      Sound = 8;
      NowPlaying = 8;
    };

    "com.apple.systemuiserver" = {
      menuExtras = [
        "/System/Library/CoreServices/Menu Extras/Bluetooth.menu"
        "/System/Library/CoreServices/Menu Extras/AirPort.menu"
        "/System/Library/CoreServices/Menu Extras/Battery.menu"
        "/System/Library/CoreServices/Menu Extras/Clock.menu"
        "/System/Library/CoreServices/Menu Extras/User.menu"
        "/System/Library/CoreServices/Menu Extras/Volume.menu"
      ];
      "NSStatusItem Visible Siri" = false;
      "NSStatusItem Visible com.apple.menuextra.airport" = true;
      "NSStatusItem Visible com.apple.menuextra.appleuser" = true;
      "NSStatusItem Visible com.apple.menuextra.battery" = true;
      "NSStatusItem Visible com.apple.menuextra.bluetooth" = true;
      "NSStatusItem Visible com.apple.menuextra.volume" = true;
    };

    "com.apple.menuextra.clock" = {
      DateFormat = "EEE d MMM hh:mm:ss a";
      FlashDateSeparators = true;
      # Using The Clocker app — show analog so the two clocks are visually distinct.
      IsAnalog = true;
      Show24Hour = false;
      ShowAMPM = true;
      ShowDate = false;
      ShowDayOfMonth = true;
      ShowDayOfWeek = false;
      ShowSeconds = true;
    };

    # -------------------------------------------------------------------------
    # macOS system daemons — policy (never user-configurable via UI)
    # -------------------------------------------------------------------------

    "com.apple.desktopservices" = {
      DSDontWriteNetworkStores = true;
    };

    "com.apple.bird" = {
      # iCloud Drive: keep full copies in iCloud, evict local when space needed.
      optimize-storage = true;
    };

    # -------------------------------------------------------------------------
    # Dock — keys not covered by system.defaults.dock typed options
    # -------------------------------------------------------------------------

    "com.apple.dock" = {
      # notification-always-show-image and springboard-* are not in nix-darwin
      # system.defaults.dock typed options.
      "notification-always-show-image" = true;
      "springboard-rows" = 10;
      "springboard-columns" = 10;
    };

    # -------------------------------------------------------------------------
    # NSGlobalDomain — keys not covered by system.defaults.NSGlobalDomain
    # -------------------------------------------------------------------------

    "NSGlobalDomain" = {
      # These keys have no nix-darwin typed option — written to the global domain
      # in addition to the typed system.defaults.NSGlobalDomain writes above.
      AppleSpacesSwitchOnActivate = true;
      # Double-clicking a window title maximises the window.
      AppleActionOnDoubleClick = "Maximize";
      # Enables the Inspect Element context menu in all WKWebView-based apps.
      WebKitDeveloperExtras = true;
    };

    # -------------------------------------------------------------------------
    # Screen capture (thumbnailExpiration is not in system.defaults.screencapture)
    # -------------------------------------------------------------------------

    "com.apple.screencaptureui" = {
      # Float seconds — thumbnail lingers for 15 s before auto-dismissing.
      thumbnailExpiration = 15.0;
    };

    # -------------------------------------------------------------------------
    # Software Update — Mac App Store keys not in system.defaults.SoftwareUpdate
    # -------------------------------------------------------------------------

    "com.apple.commerce" = {
      AutoUpdate = true;
      AutoUpdateRestartRequired = true;
    };

    "com.apple.appstore" = {
      WebKitDeveloperExtras = true;
      ShowDebugMenu = true;
    };

    # -------------------------------------------------------------------------
    # Keychain Access
    # -------------------------------------------------------------------------

    "com.apple.keychainaccess" = {
      "Show Expired Certificates" = true;
      "Distinguish Legacy ACLs" = true;
    };

    # -------------------------------------------------------------------------
    # Remote Desktop
    # -------------------------------------------------------------------------

    "com.apple.remotedesktop" = {
      IncludeDebugMenu = true;
      showShortUserName = true;
    };

    # -------------------------------------------------------------------------
    # iTerm2 — policy keys only (initial defaults and visual prefs in osx-defaults.sh)
    # -------------------------------------------------------------------------

    "com.googlecode.iterm2" = {
      AllowClipboardAccess = true;
      PromptOnQuit = false;
      SavePasteHistory = false;
      SUAutomaticallyUpdate = true;
      SUEnableAutomaticChecks = true;
    };

    # -------------------------------------------------------------------------
    # Safari — security, privacy, and debug policy only
    # (visual and behavioural prefs in osx-defaults.sh)
    # -------------------------------------------------------------------------

    "com.apple.Safari" = {
      AutoOpenSafeDownloads = false;
      DebugSnapshotsUpdatePolicy = 2;
      IncludeDebugMenu = true;
      IncludeInternalDebugMenu = true;
      InstallExtensionUpdatesAutomatically = true;
      SendDoNotTrackHTTPHeader = true;
      SuppressSearchSuggestions = true;
      UniversalSearchEnabled = false;
      WarnAboutFraudulentWebsites = true;
      WebKitDNSPrefetchingEnabled = true;
      WebKitJavaScriptCanOpenWindowsAutomatically = false;
      WebKitUsesEncodingDetector = false;
      "com.apple.Safari.ContentPageGroupIdentifier.WebKit2BackspaceKeyNavigationEnabled" = true;
      "com.apple.Safari.ContentPageGroupIdentifier.WebKit2JavaScriptCanOpenWindowsAutomatically" = false;
    };

    # -------------------------------------------------------------------------
    # Google Chrome
    # -------------------------------------------------------------------------

    "com.google.Chrome" = {
      AppleEnableMouseSwipeNavigateWithScrolls = false;
      AppleEnableSwipeNavigateWithScrolls = false;
      KeychainReauthorizeInAppSpring2017 = 2;
      KeychainReauthorizeInAppSpring2017Success = true;
    };

    "com.google.Chrome.beta" = {
      AppleEnableMouseSwipeNavigateWithScrolls = false;
      AppleEnableSwipeNavigateWithScrolls = false;
    };

    "com.google.Chrome.canary" = {
      AppleEnableMouseSwipeNavigateWithScrolls = false;
      AppleEnableSwipeNavigateWithScrolls = false;
    };

    # -------------------------------------------------------------------------
    # ProtonVPN — startup and update policy only
    # (connection settings in osx-defaults.sh)
    # -------------------------------------------------------------------------

    "ch.protonvpn.mac" = {
      EarlyAccess = true;
      RememberLoginAfterUpdate = true;
      StartMinimized = true;
      StartOnBoot = true;
      SUAutomaticallyUpdate = true;
      SUEnableAutomaticChecks = false;
      SystemNotifications = true;
    };

    # -------------------------------------------------------------------------
    # Zoom — policy keys only (UI layout prefs in osx-defaults.sh)
    # -------------------------------------------------------------------------

    "us.zoom.xos" = {
      BounceApplicationSetting = 2;
      NSQuitAlwaysKeepsWindows = false;
      kZPSettingShowCodeSnippet = true;
      kZPSettingShowLinkPreview = true;
    };

    # -------------------------------------------------------------------------
    # Clocker — login item policy only (display prefs in osx-defaults.sh)
    # -------------------------------------------------------------------------

    "com.abhishek.Clocker" = {
      startAtLogin = true;
    };

    # -------------------------------------------------------------------------
    # DBeaver
    # -------------------------------------------------------------------------

    "org.jkiss.dbeaver.core.product" = {
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSInitialToolTipDelay = 300;
      NSScrollAnimationEnabled = false;
    };

    # -------------------------------------------------------------------------
    # DockDoor
    # -------------------------------------------------------------------------

    "com.ethanbills.DockDoor" = {
      # Login item: registered via postinstall in darwin-configuration.nix
      # (osascript/System Events). DockDoor has no defaults key for this.
      SUAutomaticallyUpdate = true;
      SUEnableAutomaticChecks = true;
      SUSendProfileInfo = false;
      cmdTabEnabledTrafficLightButtons = [ "maximize" "quit" "close" "minimize" ];
      enableCmdTabEnhancements = true;
      enabledTrafficLightButtons = [ "quit" "close" "maximize" "minimize" ];
      reopenSettingsAfterRestart = false;
    };

    # -------------------------------------------------------------------------
    # Drawio
    # -------------------------------------------------------------------------

    "com.jgraph.drawio.desktop" = {
      AppleTextDirection = true;
      NSForceRightToLeftWritingDirection = false;
      NSTreatUnknownArgumentsAsOpen = false;
    };

    # -------------------------------------------------------------------------
    # Firefox family (NS* macOS keys only; user.js written by osx-defaults.sh)
    # NSNavLastRootDirectory omitted — ephemeral last-used path managed by the app.
    # -------------------------------------------------------------------------

    "org.mozilla.firefox" = {
      NSFullScreenMenuItemEverywhere = false;
      NSNavLastUserSetHideExtensionButtonState = false;
      NSTreatUnknownArgumentsAsOpen = false;
      PMPrintingExpandedStateForPrint2 = false;
    };

    "org.mozilla.nightly" = {
      NSFullScreenMenuItemEverywhere = false;
      NSNavLastUserSetHideExtensionButtonState = false;
      NSTreatUnknownArgumentsAsOpen = false;
      PMPrintingExpandedStateForPrint2 = false;
    };

    "org.mozilla.floorp" = {
      NSFullScreenMenuItemEverywhere = false;
      NSNavLastUserSetHideExtensionButtonState = false;
      NSTreatUnknownArgumentsAsOpen = false;
      PMPrintingExpandedStateForPrint2 = false;
    };

    "org.mozilla.thunderbird.betterbird" = {
      NSFullScreenMenuItemEverywhere = false;
      NSNavLastUserSetHideExtensionButtonState = false;
      NSTreatUnknownArgumentsAsOpen = false;
      PMPrintingExpandedStateForPrint2 = false;
    };

    # -------------------------------------------------------------------------
    # Thunderbird
    # -------------------------------------------------------------------------

    "org.mozilla.thunderbird" = {
      NSFullScreenMenuItemEverywhere = false;
      NSTreatUnknownArgumentsAsOpen = false;
    };

    # -------------------------------------------------------------------------
    # Keybase
    # -------------------------------------------------------------------------

    "keybase.Electron" = {
      AppleTextDirection = true;
      NSForceRightToLeftWritingDirection = false;
      NSFullScreenMenuItemEverywhere = false;
      NSTreatUnknownArgumentsAsOpen = false;
    };

    # -------------------------------------------------------------------------
    # MechVibes
    # -------------------------------------------------------------------------

    "com.electron.mechvibes" = {
      # Skip: NSStatusItem Preferred Position Item-0 — menu bar pixel coordinate.
      NSFullScreenMenuItemEverywhere = false;
      NSTreatUnknownArgumentsAsOpen = false;
    };

    # -------------------------------------------------------------------------
    # KeyCastr — update policy only (visual settings in osx-defaults.sh)
    # -------------------------------------------------------------------------

    "io.github.keycastr" = {
      SUEnableAutomaticChecks = true;
      SUSendProfileInfo = false;
    };

    # -------------------------------------------------------------------------
    # KeyClu
    # -------------------------------------------------------------------------

    "com.0804Team.KeyClu" = {
      SUAutomaticallyUpdate = true;
      SUEnableAutomaticChecks = true;
      SUSendProfileInfo = false;
      activationKeyId = 0;
      activationKeyType = 1;
      activationPersistentKeyType = 0;
      appearance = "system";
      applyLimitToTitles = false;
      hideMenuIcon = false;
      launchAtLogin = true;
      limitTitles = 75;
      makeItBloom = true;
      makeItRainbow = false;
      shortcutColors = "1BBFF9FF,28CD41FF,FFCC00FF,FF9500FF,FF3930FF,AF52DDFF,FF2D53FF";
      showAppIcon = false;
      showHighlight = true;
      showUserHiddenElements = true;
      silentLaunchQuit = true;
    };

    # -------------------------------------------------------------------------
    # Monolingual
    # -------------------------------------------------------------------------

    "net.sourceforge.Monolingual" = {
      SUAutomaticallyUpdate = true;
      SUEnableAutomaticChecks = true;
      SUSendProfileInfo = false;
      Strip = true;
    };

    # -------------------------------------------------------------------------
    # OnlyOffice
    # -------------------------------------------------------------------------

    "asc.onlyoffice.ONLYOFFICE" = {
      # Skip: asc_save_path (machine-specific path) and asc_user_name_app.
      AppleLanguages = [ "en-US" ];
      AppleLocale = "en-US";
      NSDisabledCharacterPaletteMenuItem = false;
      NSDisabledDictationMenuItem = true;
      NSForceLeftToRightWritingDirection = true;
      SUAutomaticallyUpdate = true;
      SUEnableAutomaticChecks = true;
      SUSendProfileInfo = false;
      "asc_user_docOpenMode" = "edit";
      "asc_user_ui_lang" = "en-US";
      "asc_user_ui_theme" = "theme-light";
    };

    # -------------------------------------------------------------------------
    # Rancher Desktop
    # -------------------------------------------------------------------------

    "io.rancherdesktop.app" = {
      AppleTextDirection = true;
      NSForceRightToLeftWritingDirection = false;
      NSFullScreenMenuItemEverywhere = false;
      NSTreatUnknownArgumentsAsOpen = false;
    };

    # -------------------------------------------------------------------------
    # Shortcat
    # -------------------------------------------------------------------------

    "com.sproutcube.Shortcat" = {
      # Skip: telemetryIdentifier — device UUID.
      # KeyboardShortcuts_* values encode key codes and modifiers as JSON strings.
      "KeyboardShortcuts_click" = ''{"carbonModifiers":0,"carbonKeyCode":36}'';
      "KeyboardShortcuts_debugElement" = ''{"carbonModifiers":256,"carbonKeyCode":119}'';
      "KeyboardShortcuts_reloadUI" = ''{"carbonModifiers":768,"carbonKeyCode":15}'';
      "KeyboardShortcuts_toggleLockUI" = ''{"carbonKeyCode":115,"carbonModifiers":256}'';
      "KeyboardShortcuts_toggleShortcat" = ''{"carbonModifiers":2304,"carbonKeyCode":49}'';
      downKeycode = 38;
      leftKeycode = 4;
      rightKeycode = 37;
      upKeycode = 40;
    };

    # -------------------------------------------------------------------------
    # Sol
    # -------------------------------------------------------------------------

    "com.ospfranco.sol" = {
      # Skip: NSWindow Frame * (display geometry), SUHasLaunchedBefore (sentinel),
      # SULastCheckTime (ephemeral timestamp), SUUpdateGroupIdentifier.
      RCTI18nUtil_makeRTLFlipLeftAndRightStyles = true;
      SUAutomaticallyUpdate = true;
      SUEnableAutomaticChecks = true;
      SUSendProfileInfo = false;
    };

    # -------------------------------------------------------------------------
    # Thaw (Ice fork — menu bar manager) — core behaviour policy only
    # (display/timing prefs in osx-defaults.sh)
    # -------------------------------------------------------------------------

    "com.stonerl.Thaw" = {
      # Skip: Hotkeys (all values are null — PlistBuddy cannot write NSNull
      # portably), MenuBarAppearanceConfigurationV2, MenuBarItemManager.*,
      # DisplayIceBarConfigurations (contain per-display UUIDs), hasMigrated* flags.
      AutoRehide = true;
      EnableAlwaysHiddenSection = true;
      EnableDiagnosticLogging = false;
      EnableSecondaryContextMenu = true;
      HideApplicationMenus = true;
      RehideStrategy = 0;
      ShowAllSectionsOnUserDrag = true;
      ShowIceIcon = true;
      SUAutomaticallyUpdate = true;
      SUEnableAutomaticChecks = true;
      UseIceBar = true;
    };

    # -------------------------------------------------------------------------
    # Zen Browser (NS* macOS keys only; user.js written by osx-defaults.sh)
    # Two bundle IDs are in use across Zen versions.
    # -------------------------------------------------------------------------

    "app.zen-browser.zen" = {
      NSFullScreenMenuItemEverywhere = false;
      NSTreatUnknownArgumentsAsOpen = false;
    };

    "org.mozilla.com.zen.browser" = {
      NSFullScreenMenuItemEverywhere = false;
      NSTreatUnknownArgumentsAsOpen = false;
    };

  };
}
