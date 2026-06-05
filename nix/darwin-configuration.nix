{ pkgs, username, ... }:
let
  homeDir     = "/Users/${username}";
  dotfilesDir = builtins.getEnv "DOTFILES_DIR";
   # DOTFILES_DIR is set by .shellrc. During a vanilla OS first-install it may be
   # empty if nix-darwin is bootstrapped before .shellrc has been sourced into the
   # calling environment. In that case postinstall scripts that reference
   # setup-login-item.sh will silently no-op — acceptable on first install since
   # the apps may not be installed yet anyway.
  setupLoginItem = app: "\"${dotfilesDir}/scripts/setup-login-item.sh\" -a '${app}'";
in
{
  # ---------------------------------------------------------------------------
  # Nix settings
  # ---------------------------------------------------------------------------

  # Enable flakes and the unified 'nix' CLI. Both are required for nix-darwin
  # and home-manager to function — they use flake-based evaluation internally.
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

  # ---------------------------------------------------------------------------
  # Homebrew — GUI casks and formulae not available in nixpkgs
  # ---------------------------------------------------------------------------
  # nix-darwin invokes 'brew bundle' on every 'darwin-rebuild switch'.
  # Homebrew itself must be pre-installed; nix-darwin does not install it.
  # See fresh-install-of-osx.sh _install_homebrew for the bootstrap step.
  #
  # TODO(FIRST_INSTALL optimisation): currently all casks are installed on the
  # first darwin-rebuild switch, which is slower than the old Brewfile approach
  # of installing only the base set (keybase, iterm2, font-meslo-lg-nerd-font)
  # synchronously and deferring the rest to a background process. A future
  # optimisation could split this into a minimal first-install configuration
  # and the full configuration, switching between them based on FIRST_INSTALL.

  homebrew.enable = true;

  homebrew.onActivation = {
    # Never auto-update Homebrew itself during a switch — it is slow and can
    # pull in unexpected formula changes mid-activation.
    autoUpdate = false;
    # Upgrade all listed packages on every switch so 'darwin-rebuild switch'
    # is the single command that keeps both nix and brew packages current.
    upgrade = true;
    # Remove packages that are no longer listed. "uninstall" is used rather than
    # "zap" so that app support files (preferences, caches) are preserved when a
    # cask is removed from the config — matching the previous 'brew bundle cleanup'
    # behaviour without the more destructive zap semantics.
    cleanup = "uninstall";
  };

  homebrew.caskArgs = {
    appdir  = "/Applications";
    fontdir = "/Library/Fonts";
    adopt   = true;
  };

  homebrew.taps = [
    "xykong/tap"
  ];

  homebrew.brews = [
    # Formulae not available in nixpkgs — all other CLI tools are in nix/modules/packages.nix
    { name = "git-tools"; }
    { name = "mole"; }
    { name = "opencode"; }
  ];

  homebrew.casks = [
    # --- Base: required before backup restoration on a fresh install ---
    { name = "font-meslo-lg-nerd-font"; }
    { name = "keybase"; postinstall = setupLoginItem "Keybase"; }
    { name = "iterm2"; }

    # --- Advanced ---
    { name = "clocker";          postinstall = setupLoginItem "Clocker"; }
    { name = "dbeaver-community"; }
    { name = "dockdoor";         postinstall = setupLoginItem "Dockdoor"; }
    { name = "drawio"; }
    { name = "firefox@nightly"; }
    { name = "flux-markdown";    postinstall = "qlmanage -r"; }
    { name = "google-chrome@beta"; }
    { name = "keepassxc@beta"; }
    { name = "keycastr";         postinstall = setupLoginItem "Keycastr"; }
    { name = "mechvibes";        postinstall = setupLoginItem "Mechvibes"; }
    { name = "onlyoffice"; }
    { name = "protonvpn";        postinstall = setupLoginItem "ProtonVPN"; }
    { name = "rancher"; }
    { name = "sol";              postinstall = setupLoginItem "Sol"; }
    { name = "shortcat";         postinstall = setupLoginItem "Shortcat"; }
    { name = "stats";            postinstall = setupLoginItem "Stats"; }
    { name = "zed@preview"; }
    { name = "zen@twilight"; }
    { name = "zoom"; }
    { name = "windows-app"; }
  ];

  # ---------------------------------------------------------------------------
  # macOS system defaults — migrated from osx-defaults.sh
  # ---------------------------------------------------------------------------
  # Applied unconditionally on every darwin-rebuild switch, replacing the
  # interactive ask-Y prompts from the script. Settings that require sudo,
  # PlistBuddy, systemsetup, pmset, scutil, or defaults -currentHost remain
  # in osx-defaults.sh.

  system.defaults.dock = {
    autohide = true;
    # Zero modifier removes the animation delay entirely so the dock
    # appears/disappears immediately.
    autohide-time-modifier = 0.0;
    expose-animation-duration = 0.5;
    launchanim = true;
    magnification = true;
    mineffect = "suck";
    minimize-to-application = true;
    mouse-over-hilite-stack = true;
    mru-spaces = true;
    # Key name is inverted: false means bouncing IS enabled.
    no-bouncing = false;
    orientation = "right";
    show-process-indicators = true;
    showhidden = true;
    static-only = true;
    tilesize = 35;
    # Hot corners — possible values:
    #  0: no-op  2: Mission Control  4: Desktop  5: Start screen saver
    wvous-tl-corner = 4;    # top-left     → Desktop
    wvous-tl-modifier = 0;
    wvous-tr-corner = 2;    # top-right    → Mission Control
    wvous-tr-modifier = 0;
    wvous-bl-corner = 0;    # bottom-left  → no-op
    wvous-bl-modifier = 0;
    wvous-br-corner = 5;    # bottom-right → Start screen saver
    wvous-br-modifier = 0;
  };

  system.defaults.finder = {
    FXDefaultSearchScope = "SCcf";        # search current folder by default
    FXPreferredViewStyle = "clmv";        # column view
    NewWindowTarget = "PfHm";
    NewWindowTargetPath = "file://${homeDir}/";
    QuitMenuItem = true;
    ShowPathbar = true;
    ShowStatusBar = true;
    WarnOnEmptyTrash = false;
    _FXShowPosixPathInTitle = true;
    _FXSortFoldersFirst = true;
    _FXSortFoldersFirstOnDesktop = true;
  };

  system.defaults.NSGlobalDomain = {
    # 2 = enable full keyboard access for all controls (Tab in modal dialogs).
    AppleKeyboardUIMode = 2;
    AppleLanguages = [ "en-IN" "en" ];
    AppleLocale = "en_IN@currency=INR";
    AppleMeasurementUnits = "Centimeters";
    AppleMetricUnits = true;
    AppleShowAllExtensions = true;
    # 2 = medium subpixel anti-aliasing; primarily useful on non-Apple LCDs.
    AppleFontSmoothing = 2;
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticPeriodSubstitutionEnabled = false;
    NSQuitAlwaysKeepsWindows = true;
  };

  system.defaults.screencapture = {
    disable-shadow = true;
    location = "${homeDir}/Desktop";
    type = "png";
  };

  # Require password immediately after sleep or screen saver begins.
  system.defaults.screensaver = {
    askForPassword = 1;
    askForPasswordDelay = 0;
  };

  system.defaults.ActivityMonitor = {
    IconType = 5;         # CPU usage graph in Dock icon
    OpenMainWindow = true;
    ShowCategory = 101;   # all processes hierarchically
    SortColumn = "CPUUsage";
    SortDirection = 0;
  };

  system.defaults.SoftwareUpdate = {
    AutomaticCheckEnabled = true;
    ConfigDataInstall = true;    # install system data files automatically
    CriticalUpdateInstall = true;
    ScheduleFrequency = 1;       # check daily rather than weekly
  };

  system.defaults.TimeMachine.DoNotOfferNewDisksForBackup = true;

  system.defaults.trackpad = {
    Clicking = true;
    TrackpadThreeFingerDrag = false;
  };

  # Casks that require Ruby DSL conditionals unsupported by the typed options above.
  # Also contains commented-out casks retained as a reference for future use.
  homebrew.extraConfig = ''
    # --- Conditional casks (platform / OS version guards) ---

    # arm-only: no equivalent on Intel Macs.
    cask "keyclu", postinstall: "\"${dotfilesDir}/scripts/setup-login-item.sh\" -a 'KeyClu'" if ::Hardware::CPU.arm?

    # macOS 14+ only
    cask "thaw", postinstall: "\"${dotfilesDir}/scripts/setup-login-item.sh\" -a 'Thaw'" if ::OS::Mac::version >= 14

    # ---------------------------------------------------------------------------
    # Commented-out formulae and casks — retained as a reference for future use
    # ---------------------------------------------------------------------------

    # --- encrypted backup in case keybase is shut down in the future
    # tap "Picocrypt/picocrypt" if ::Hardware::CPU.arm?
    # cask "picocrypt" if ::Hardware::CPU.arm?

    # --- docker utilities
    # brew "dive"          # docker layers inspection on steroids
    # brew "docker-diff"
    # brew "docker-slim"   # TODO: investigate if the http-probe is a deal-breaker
    # brew "hadolint"      # lint Dockerfiles (similar to shellcheck or shfmt for shell scripts)
    # brew "kubernetes-cli", link: true
    # brew "kubernetes-helm"

    # --- git utilities
    # brew "git-crypt"

    # --- tmux utilities
    # brew "reattach-to-user-namespace"
    # brew "tmux"

    # --- general utilities
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

    # --- casks
    # tap "TheBoredTeam/boring-notch"
    # cask "boring-notch", postinstall: "\"${dotfilesDir}/scripts/setup-login-item.sh\" -a 'boringNotch'" if ::OS::Mac::version >= 14
    # cask "brave-browser"
    # cask "claude-code"
    # cask "cloudflare-warp"
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
    # cask "ollama-app", restart_service: :changed
    # cask "onyx"
    # cask "silicon" if ::Hardware::CPU.arm?
    # cask "tempbox"
    # cask "the-unarchiver"
    # cask "thunderbird@daily"
    # cask "tor-browser@alpha"
    # cask "utm"
    # cask "visual-studio-code"
  '';
}
