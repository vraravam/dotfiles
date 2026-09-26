{ pkgs, lib, username, keybaseEnabled, ... }:
let
  homeDir = "/Users/${username}";
  # Homebrew's 'postinstall' is a literal shell command string (passed to the system
  # shell as-is, not further interpreted as Ruby) -- '\$' escapes a literal '$' so
  # '${DOTFILES_DIR}' survives into the generated Brewfile for the shell (whichever
  # invoked 'darwin-rebuild switch', already having sourced '.shellrc') to expand at
  # postinstall-run time, rather than nix-interpolating a value captured at eval time.
  setupLoginItem = app: "\"\${DOTFILES_DIR}/scripts/setup-login-item.rb\" -a '${app}'";
in
{
  # ---------------------------------------------------------------------------
  # Nix settings
  # ---------------------------------------------------------------------------

  # Enable flakes and the unified 'nix' CLI. Both are required for nix-darwin
  # and home-manager to function -- they use flake-based evaluation internally.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Deduplicate identical store objects automatically. This significantly reduces
  # disk usage when multiple profiles or generations share the same derivations.
  nix.settings.auto-optimise-store = true;

  # Weekly GC on Sunday. The 30-day retention window keeps enough generations
  # to roll back through a month of darwin-rebuild switches without accumulating
  # unbounded store growth.
  nix.gc = {
    automatic = true;
    interval   = { Weekday = 0; };
    options    = "--delete-older-than 30d";
  };

  # nix-darwin must own zsh management so it writes /etc/zshrc. That file
  # prepends /run/current-system/sw/bin and ~/.nix-profile/bin to PATH, which
  # is what makes nix-installed binaries visible in every new shell.
  programs.zsh.enable = true;

  # Increment when making backwards-incompatible nix-darwin state changes.
  system.stateVersion = 5;

  # Required by nix-darwin for 'system.defaults.*' user-level writes (run via
  # 'launchctl asuser "$(id -u -- <user>)" sudo --user=<user> -- defaults write ...',
  # see nix-darwin's defaults-write.nix) and by its homebrew module (brew commands
  # run as this user, not root). Also what nix-darwin's home-manager integration
  # uses to auto-derive 'osConfig.users.users.<name>.home' for
  # 'home-manager.users.<name>.home.homeDirectory' -- without this, that option
  # resolves to null and evaluation fails with a type error.
  system.primaryUser = username;

  # Declares the pre-existing macOS user account to nix-darwin (this setup never
  # creates the account itself -- it already exists from the OS install). Purely
  # informational for home-manager's benefit here: home-manager's nix-darwin
  # integration (nixos/common.nix) auto-derives
  # 'home-manager.users.<name>.home.homeDirectory' from
  # 'config.users.users.<name>.home' -- without this, that option resolves to
  # null and evaluation fails with a type error.
  users.users.${username}.home = homeDir;

  # font-meslo-lg-nerd-font (formerly a Homebrew cask): nix-darwin's own fonts
  # module symlinks these into '/Library/Fonts/Nix Fonts', declaratively, no
  # Homebrew involvement needed for something nixpkgs already packages.
  fonts.packages = [ pkgs.nerd-fonts.meslo-lg ];

  # ---------------------------------------------------------------------------
  # Homebrew -- GUI casks only; zero CLI formulae (see modules/packages.nix)
  # ---------------------------------------------------------------------------
  # nix-darwin invokes 'brew bundle' on every 'darwin-rebuild switch'.
  # Homebrew itself must be pre-installed; nix-darwin does not install it.
  # See fresh-install-of-osx.sh's _install_homebrew for the bootstrap step.
  #
  # TODO(FIRST_INSTALL optimisation): currently all casks are installed on the
  # first darwin-rebuild switch, which is slower than the old Brewfile approach
  # of installing only the base set (keybase, iterm2, font-meslo-lg-nerd-font)
  # synchronously and deferring the rest to a background process. A future
  # optimisation could split this into a minimal first-install configuration
  # and the full configuration, switching between them based on FIRST_INSTALL.

  homebrew.enable = true;

  homebrew.onActivation = {
    # Never auto-update Homebrew itself during a switch -- it is slow and can
    # pull in unexpected formula changes mid-activation.
    autoUpdate = false;
    # Upgrade all listed casks on every switch so 'darwin-rebuild switch' is
    # the single command that keeps both nix packages and Homebrew casks current.
    upgrade = true;
    # Remove casks that are no longer listed. "uninstall" is used rather than
    # "zap" so that app support files (preferences, caches) are preserved when a
    # cask is removed from the config -- matching the previous 'brew bundle
    # cleanup' behaviour without the more destructive zap semantics.
    cleanup = "uninstall";
  };

  # 'adopt' has no typed nix-darwin caskArgs option (only appdir/fontdir/language/
  # require_sha/no_quarantine/no_binaries/ignore_dependencies/colorpickerdir/etc. are
  # typed -- 'adopt' is absent), so the whole 'cask_args' line is declared as raw
  # Ruby in homebrew.extraConfig below instead, rather than splitting appdir/fontdir
  # into a typed homebrew.caskArgs block with 'adopt' bolted on separately (avoids
  # any ambiguity about which of two separate 'cask_args' calls Homebrew's own Bundle
  # DSL would apply).

  homebrew.taps = [
    "vorssaint/tap"
  ];

  # No 'homebrew.brews' -- every former CLI formula now has a nixpkgs
  # equivalent (see modules/packages.nix's nixpkgs name mapping notes).

  # TODO: Need to find a cask for:
  #   Tinkertool
  #   TypeWhisper (start on login)
  #   ZoomHider

  homebrew.casks = [
    # --- Base: required before backup restoration on a fresh install ---
    { name = "iterm2@beta"; }
  ]
  # Keybase is a proprietary, closed-source GUI app with no nixpkgs package --
  # mirrors the former Brewfile's identically-gated 'keybase_enabled' cask.
  # See modules/packages.nix's home.nix caller for how keybaseEnabled is derived
  # (reads '.shellrc' directly, same rationale as encryptedBackupEnabled there).
  ++ lib.optionals keybaseEnabled [
    { name = "keybase"; postinstall = setupLoginItem "Keybase"; }
  ]
  ++ [
    # --- Advanced ---
    { name = "clocker";           postinstall = setupLoginItem "Clocker"; }
    { name = "dbeaver-community"; }
    { name = "drawio"; }
    { name = "firefox@nightly"; }
    { name = "google-chrome@beta"; }
    { name = "keepassxc@beta"; }
    { name = "keycastr";          postinstall = setupLoginItem "Keycastr"; }
    { name = "mechvibes";         postinstall = setupLoginItem "Mechvibes"; }
    { name = "onlyoffice"; }
    { name = "protonvpn"; }
    { name = "rancher"; }
    { name = "shortcat";          postinstall = setupLoginItem "Shortcat"; }
    { name = "vorssaint/tap/vorssaint"; postinstall = setupLoginItem "Vorssaint"; }
    { name = "qlmarkdown"; }
    {
      name = "vscodium@insiders";
      # No nixpkgs equivalent (VSCodium binaries are not separately packaged from
      # the .app bundle) -- CLI symlinks are handled declaratively instead, in
      # home.nix's mkOutOfStoreSymlink entries, rather than a postinstall hook here.
    }
    { name = "zen@twilight"; }
    { name = "zoom"; }
    { name = "windows-app"; } # replacement for microsoft-remote-desktop
  ]
  # KeyClu is arm-only. Unlike Thaw/Onyx below, nix already knows the target
  # architecture statically per darwinConfiguration (arm/intel), so this is
  # expressed as native nix rather than a Ruby conditional in extraConfig.
  ++ lib.optionals pkgs.stdenv.hostPlatform.isAarch64 [
    { name = "keyclu"; postinstall = setupLoginItem "KeyClu"; }
  ];

  # Casks that require Ruby DSL conditionals unsupported by the typed options above
  # (arch/OS-version guards Nix cannot resolve statically the way Homebrew's own
  # Ruby evaluation can via ::Hardware::CPU/::OS::Mac at *cask-install* time -- not
  # to be confused with nix's own hostPlatform, which IS known statically per
  # darwinConfiguration (arm/intel) and is used directly for KeyClu below instead
  # of an extraConfig conditional).
  homebrew.extraConfig = ''
    # Global cask install-location/behavior args -- see the comment above
    # homebrew.taps for why this whole line lives here rather than in a typed
    # homebrew.caskArgs block.
    cask_args appdir: '/Applications', fontdir: '/Library/Fonts', adopt: true

    # macOS 14+ and < 27 only (Thaw does not support macOS 27's design changes yet).
    cask "thaw", postinstall: "\"#{ENV['DOTFILES_DIR']}/scripts/setup-login-item.rb\" -a 'Thaw'" if ::OS::Mac::version >= 14 && ::OS::Mac::version < 27

    # Onyx has separate stable/beta cask names depending on whether the running
    # macOS release is still in beta.
    cask ::OS::Mac::full_version.unsupported_release? ? "onyx@beta" : "onyx"

    # local AI coding tools
    # tap "jundot/omlx", "git@github.com/jundot/omlx"
    # reference: https://www.agileguy.ca/opencode-fully-local/
    # to start ollama: ollama launch opencode --model gpt-oss-20b-MXFP4-Q8 -- #{ENV['DOTFILES_DIR']}
    # brew "jundot/omlx/omlx", trusted: true, restart_service: :changed if ::Hardware::CPU.arm?

    # brew "mas"
    # mas "PDFgear", id: 6469021132

    # VSCode extensions -- guarded on 'code' being in PATH (symlinked from
    # home.nix's vscodium@insiders mkOutOfStoreSymlink entries) so brew does not
    # silently install VS Code itself when 'code' is absent. Marketplace redirect
    # mirrors the '.aliases' block guarded on 'codium' being in PATH.
    ENV['VSCODE_GALLERY_SERVICE_URL'] = 'https://marketplace.visualstudio.com/_apis/public/gallery'
    ENV['VSCODE_GALLERY_CACHE_URL'] = 'https://vscode.blob.core.windows.net/gallery/index'
    ENV['VSCODE_GALLERY_ITEM_URL'] = 'https://marketplace.visualstudio.com/items'
    ENV['VSCODE_GALLERY_CONTROL_URL'] = '''
    ENV['VSCODE_GALLERY_RECOMMENDATIONS_URL'] = '''
    is_vscode_installed = !`PATH="#{ENV['HOME']}/.local/bin:#{ENV['PATH']}" which code`.chomp.empty?
    if is_vscode_installed
      vscode 'britesnow.vscode-toggle-quotes'
      vscode 'codezombiech.gitignore'
      vscode 'davidanson.vscode-markdownlint'
      vscode 'dbaeumer.vscode-eslint'
      vscode 'digitalbrainstem.javascript-ejs-support'
      vscode 'drcika.apc-extension'
      vscode 'editorconfig.editorconfig'
      vscode 'esbenp.prettier-vscode'
      vscode 'genuitecllc.codetogether'
      vscode 'github.vscode-github-actions'
      vscode 'google.geminicodeassist'
      vscode 'ibm.output-colorizer'
      vscode 'mechatroner.rainbow-csv'
      vscode 'mikestead.dotenv'
      vscode 'mkhl.direnv'
      vscode 'ms-azuretools.vscode-containers'
      vscode 'ms-azuretools.vscode-docker'
      vscode 'ms-vscode.atom-keybindings'
      vscode 'ms-vscode.vscode-typescript-next'
      vscode 'oderwat.indent-rainbow'
      vscode 'orta.vscode-jest'
      vscode 'redhat.vscode-yaml'
      vscode 'richie5um2.vscode-sort-json'
      vscode 'shopify.ruby-lsp'
      vscode 'tchayen.markdown-links'
      vscode 'tyriar.sort-lines'
      vscode 'vscode-icons-team.vscode-icons'
      vscode 'wayou.vscode-todo-highlight'
      vscode 'wmaurer.change-case'
      vscode 'yzhang.markdown-all-in-one'
    end

    # ---------------------------------------------------------------------------
    # Commented-out formulae and casks -- retained as a reference for future use
    # (verbatim from the pre-nix Brewfile's own "Miscellaneous" section)
    # ---------------------------------------------------------------------------

    # --- standalone encrypted local backup tool (unrelated to the encrypted-backup mechanism)
    # cask "Picocrypt/picocrypt/picocrypt", trusted: true if ::Hardware::CPU.arm?

    # ---- docker utilities
    # brew "dive"          # docker layers inspection on steroids
    # brew "docker-diff"
    # brew "docker-slim"   # TODO: investigate if the http-probe is a deal-breaker
    # brew "hadolint"      # lint Dockerfiles (similar to shellcheck or shfmt for shell scripts)
    # brew "kubernetes-cli", link: true if ::Hardware::CPU.arm?
    # brew "kubernetes-helm"

    # ---- git utilities
    # brew "git-crypt"

    # ---- tmux utilities
    # brew "reattach-to-user-namespace"
    # brew "tmux"

    # ---- general utilities
    # brew "container", restart_service: :changed if ::OS::Mac::version >= 26
    # brew "dua-cli"
    # brew "fzy"
    # brew "gradle-completion"
    # brew "gs"         # used for compressing PDFs
    # brew "libressl", link: true
    # brew "localstack"
    # brew "shellcheck" # Not using since this only supports bash
    # brew "speedtest-cli"
    # brew "watch"
    # brew "wifi-password"

    # ---- casks
    # cask "boring-notch", postinstall: "\"#{ENV['DOTFILES_DIR']}/scripts/setup-login-item.rb\" -a 'boringNotch'" if ::OS::Mac::version >= 14
    # cask "brave-browser"
    # cask "claude-code"
    # cask "cloudflare-warp"
    # cask "codeql"
    # cask "fliqlo"
    # cask "floorp"
    # cask "ghostty@tip"
    # cask "git-credential-manager"
    # cask "grayjay"
    # cask "intellij-idea-ce"
    # cask "kdiff3"
    # cask "knockknock"
    # cask "licecap"
    # cask "lulu"
    # cask "microsoft-teams"
    # cask "monolingual"
    # cask "netspot"
    # cask "ngrok"
    # cask "notunes"
    # cask "silicon" if ::Hardware::CPU.arm?
    # cask "tempbox"
    # cask "the-unarchiver"
    # cask "thunderbird@daily"
    # cask "tor-browser@alpha"
    # cask "utm"
    # cask "visual-studio-code"
  '';

  # ---------------------------------------------------------------------------
  # macOS system defaults -- migrated from osx-defaults.sh
  # ---------------------------------------------------------------------------
  # Applied unconditionally on every darwin-rebuild switch. Settings that require
  # sudo, PlistBuddy, systemsetup, pmset, scutil, -currentHost, -dict-add,
  # interactive 'ask'-gated prompts, or write to a file (Firefox/Zen user.js)
  # remain in osx-defaults.sh -- see .ai/domains/ (or TechnicalDeepDive.md) for the
  # exact two-phase preference architecture policy this split follows.

  # This list was derived by an exhaustive line-by-line classification of the
  # current osx-defaults.sh (584 'defaults write' calls total): only the 61 that
  # are unconditional (no interactive 'ask' gate), non-sudo, non-'-currentHost',
  # non-PlistBuddy, and non-'-dict-add' qualify. Everything else -- including
  # settings that look similar but are currently behind an 'ask' prompt -- stays
  # in osx-defaults.sh. Do not add a domain/key here without re-verifying against
  # the actual current script; a stale WIP draft of this exact file previously
  # carried over dock/trackpad/ActivityMonitor/SoftwareUpdate/NSGlobalDomain
  # entries that were nix-eligible months ago but have since moved behind 'ask'
  # gates in osx-defaults.sh -- none of those belong here anymore.

  # menuExtraClock: nix-darwin's typed option writes to the regular
  # 'com.apple.menuextra.clock' user domain (not ByHost), matching what
  # osx-defaults.sh itself does -- safe to use directly. 'DateFormat' has no
  # typed option, so it is set via CustomUserPreferences below instead.
  system.defaults.menuExtraClock = {
    FlashDateSeparators = true;
    IsAnalog = true;    # using The Clocker app -- turned analog so the two are visually distinct
    Show24Hour = false;
    ShowAMPM = true;
    # ShowDate is a tristate int in nix-darwin's typed option (0 = when space
    # allows, 1 = always, 2 = never), not the plain bool osx-defaults.sh writes
    # ('-bool false'). 2 ("never") is the closest equivalent to that boolean
    # false's intent -- verify against actual behavior after the first switch.
    ShowDate = 2;
    ShowDayOfMonth = true;
    ShowDayOfWeek = false;
    ShowSeconds = true;
  };

  # NSGlobalDomain: only AppleFontSmoothing/AppleSpacesSwitchOnActivate have typed
  # options (both write to '-g', identical to 'com.apple.controlcenter'-style
  # regular domain writes). WebKitDeveloperExtras has no typed option -- set via
  # CustomUserPreferences."NSGlobalDomain" below (equivalent domain: 'defaults
  # write -g' and 'defaults write NSGlobalDomain' are the same preference file).
  system.defaults.NSGlobalDomain = {
    AppleFontSmoothing = 2;
    AppleSpacesSwitchOnActivate = true;
  };

  # screensaver/screencapture: typed options exist for every key osx-defaults.sh
  # sets unconditionally, so no CustomUserPreferences fallback is needed for
  # either domain.
  system.defaults.screensaver = {
    askForPassword = true;
    askForPasswordDelay = 0;
  };

  system.defaults.screencapture = {
    disable-shadow = true;
    location = "${homeDir}/Desktop";
    type = "png";
  };

  # com.apple.finder: only 6 of the 18 nix-eligible keys have typed options
  # (ShowExternalHardDrivesOnDesktop, ShowMountedServersOnDesktop,
  # ShowRemovableMediaOnDesktop, FXRemoveOldTrashItems,
  # _FXEnableColumnAutoSizing, FXPreferredViewStyle) -- the rest are set via
  # CustomUserPreferences."com.apple.finder" below. Both target the same
  # regular (non-ByHost) user domain, so mixing the two is safe.
  system.defaults.finder = {
    ShowExternalHardDrivesOnDesktop = true;
    ShowMountedServersOnDesktop = false;
    ShowRemovableMediaOnDesktop = true;
    FXRemoveOldTrashItems = true;
    _FXEnableColumnAutoSizing = true;
    FXPreferredViewStyle = "clmv";
  };

  system.defaults.CustomUserPreferences = {
    # com.apple.controlcenter: deliberately NOT using nix-darwin's typed
    # 'system.defaults.controlcenter' option here -- that option writes to a
    # ByHost preference path (~<user>/Library/Preferences/ByHost/...), whereas
    # osx-defaults.sh writes the regular (non-ByHost) 'com.apple.controlcenter'
    # domain. Using the typed option would silently change this from a
    # global to a per-machine (host-keyed) preference -- exactly the kind of
    # behavior change the two-phase policy's '-currentHost'/ByHost exclusion
    # exists to prevent. It also only covers 6 of the 13 keys needed here.
    "com.apple.controlcenter" = {
      "NSStatusItem Visible Bluetooth" = 1;
      "NSStatusItem Visible WiFi" = true;
      "NSStatusItem Visible Battery" = 0;
      "NSStatusItem VisibleCC Clock" = false;    # use Clocker instead
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

    # No typed nix-darwin module exists for this domain.
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

    # DateFormat has no typed menuExtraClock option -- see system.defaults.menuExtraClock above.
    "com.apple.menuextra.clock" = {
      DateFormat = "EEE d MMM hh:mm:ss a";
    };

    # No typed nix-darwin module exists for this domain.
    "com.apple.desktopservices" = {
      DSDontWriteNetworkStores = true;
    };

    # No typed nix-darwin module exists for this domain.
    "com.apple.Safari" = {
      InstallExtensionUpdatesAutomatically = true;
    };

    # No typed nix-darwin module exists for this domain.
    "com.apple.appstore" = {
      WebKitDeveloperExtras = true;
      ShowDebugMenu = true;
    };

    # See system.defaults.NSGlobalDomain above for the 2 keys that do have typed
    # options ('-g' and the literal 'NSGlobalDomain' domain name are the same
    # preference file, so mixing both mechanisms here is safe).
    "NSGlobalDomain" = {
      WebKitDeveloperExtras = true;
    };

    # No typed nix-darwin module exists for this domain.
    "com.apple.TimeMachine" = {
      DoNotOfferNewDisksForBackup = true;
    };

    # No typed nix-darwin module exists for this domain (distinct from
    # 'com.apple.screencapture', which does have one -- see above).
    "com.apple.screencaptureui" = {
      thumbnailExpiration = 15.0;
    };

    # See system.defaults.finder above for the 6 keys that do have typed options.
    "com.apple.finder" = {
      ShowRecentTags = false;
      ShowSidebar = true;
      SidebarDevicesSectionDisclosedState = true;
      SidebarPlacesSectionDisclosedState = true;
      SidebarShowingSignedIntoiCloud = true;
      SidebarShowingiCloudDesktop = true;
      # Verbatim typo from osx-defaults.sh ('Sctio' instead of 'Section') --
      # preserve exactly; this is the actual key name macOS reads, and fixing
      # the spelling would silently stop applying it.
      SidebarTagsSctionDisclosedState = true;
      SidebarWidth = 172;
      SidebariCloudDriveSectionDisclosedState = true;
      WarnOnEmptyTrash = false;
      OpenWindowForNewRemovableDisk = true;
      RestoreWindowState = true;
    };
  };
}
