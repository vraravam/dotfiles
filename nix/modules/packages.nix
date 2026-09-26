{ config, pkgs, lib, encryptedBackupEnabled, git-remote-gpg-encrypt, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  # All CLI tools formerly managed by Homebrew formulae are declared here -- nix is
  # now the *only* CLI package manager for this setup (see AGENTS.md/TechnicalDeepDive.md
  # "no hodge-podge of package managers"). Homebrew (via nix-darwin's homebrew module,
  # see darwin-configuration.nix) is retained solely for GUI casks that have no nixpkgs
  # equivalent -- it installs zero CLI formulae.
  #
  # nixpkgs name mapping notes (differs from the former Homebrew formula name):
  #   brew grep        -> pkgs.gnugrep
  #   brew sqlite3     -> pkgs.sqlite
  #   brew gnu-tar     -> pkgs.gnutar
  #   brew git + git-gui -> pkgs.gitFull  (includes git-gui via tcl/tk)
  #   brew mole        -> pkgs.mole-cleaner (same upstream, tw93/Mole; installs a
  #                       'mo' binary -- nixpkgs' own unrelated 'mole' package is an
  #                       SSH-tunnel tool, broken on Darwin, and NOT the same tool)
  #   brew git-tools   -> pkgs.git-tools (same upstream, MestreLion/git-tools)
  #   brew anomalyco/tap/opencode -> pkgs.opencode (same upstream, confirmed via
  #                       nixpkgs' meta.homepage)
  #   brew vraravam/tap/git-remote-gpg-encrypt -> packaged by its own repo's flake
  #                       (see flake.nix's git-remote-gpg-encrypt input), not nixpkgs
  home.packages = with pkgs; [
    # --- System-level replacements (updated versions of macOS-bundled tools) ---
    # These override the macOS-bundled equivalents; nix-darwin's /etc/zshrc
    # ensures ~/.nix-profile/bin is prepended to PATH in every shell.
    bash
    curl
    gitFull     # includes git-gui (provides 'git gui' sub-command via tcl/tk)
    gnugrep
    jemalloc    # used for faster ruby
    less
    libyaml     # used for faster ruby
    openssl     # used for faster ruby
    rsync
    sqlite
    vim
    wget
    zsh

    # --- Base configuration tooling ---
    antidote
    delta
    direnv
    eza
    git-extras
    git-tools
    git-trim
    mise
    starship
    terminal-notifier
    zsh-patina  # Rust-based syntax highlighter for cli; see home.activation below

    # --- Advanced / recommended tooling ---
    bat
    btop
    git-sizer
    jaq
    mole-cleaner  # provides the 'mo' binary -- see nixpkgs name mapping notes above
    ncdu
    pandoc
    prettyping
    ripgrep
    shfmt
    syncthing
    tlrc

    # --- Zen browser development dependencies ---
    cairo
    gnutar
    mercurial
    sccache
    watchman

    # --- opencode: nixpkgs' own package (homepage confirmed as
    # github.com/anomalyco/opencode, the same fork the former
    # 'anomalyco/tap/opencode' Homebrew tap tracked) ---
    opencode
  ]
  # Optional: only pulled in when either KEYBASE_*_REPO_NAME or ENCRYPTED_*_REPO_URL
  # is set in '.shellrc' (see home.nix's encryptedBackupEnabled) -- mirrors the former
  # Brewfile's identically-gated 'vraravam/tap/git-remote-gpg-encrypt' formula.
  ++ lib.optionals encryptedBackupEnabled [
    git-remote-gpg-encrypt.packages.${system}.default
  ];

  # ollama: home-manager's cross-platform services.ollama module registers a
  # launchd agent on Darwin (equivalent to the former Brewfile's
  # 'restart_service: :changed') and pulls in the package itself -- no separate
  # 'home.packages' entry needed.
  services.ollama.enable = true;

  # Runs after every 'darwin-rebuild switch' that (re)links these packages into the
  # nix profile -- replicates the former Brewfile postinstall hooks that only fired
  # on an actual (re)install, not on 'brew bundle check' finding nothing to do.
  home.activation.postNixSwitchHooks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # antidote: regenerate the static plugin bundle so newly-added/updated plugins
    # take effect immediately, without waiting for the next interactive shell start.
    # '.config/zsh' is ZDOTDIR's well-documented default (see .shellrc) -- hardcoded
    # here since this activation script has no access to the user's actual shell
    # environment (only whatever '--impure' Nix evaluation itself already reads).
    _aliases_file="${config.home.homeDirectory}/.config/zsh/.aliases"
    if [ -f "$_aliases_file" ]; then
      $DRY_RUN_CMD zsh -c "source '$_aliases_file' && update_antidote_and_regenerate_plugin_bundle" || true
    fi

    # zsh-patina: restart the running highlighter process so it picks up a newly
    # installed/upgraded binary immediately, mirroring the former Brewfile postinstall.
    $DRY_RUN_CMD ${pkgs.zsh-patina}/bin/zsh-patina restart >/dev/null 2>&1 || true
  '';

  # Note: terminal-notifier's former Homebrew postinstall (clearing the
  # com.apple.quarantine xattr on its bundled .app) does not need a nix equivalent --
  # nixpkgs builds terminal-notifier.app from source via xcodebuild inside the nix
  # sandbox rather than fetching a pre-built, quarantine-flagged bottle, so the
  # xattr this worked around is never present in the first place.
}
