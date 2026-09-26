{ config, lib, username, keybaseEnabled, ... }:
let
  homeDir = "/Users/${username}";
in
{
  home.username = username;
  home.homeDirectory = homeDir;

  # Must match the nixpkgs release used in the flake inputs to avoid
  # "state version mismatch" warnings from home-manager on every switch. Bump this
  # to whatever release the first real 'darwin-rebuild switch' warns about --
  # cannot be verified statically without running it (no nix installed in the
  # environment this was authored in).
  home.stateVersion = "24.05";

  imports = [
    ./modules/packages.nix
  ];

  # Note: there is no 'modules/osx-app-defaults.nix' home-manager module -- all
  # nix-eligible macOS defaults are declared once, in darwin-configuration.nix's
  # 'system.defaults'/'CustomUserPreferences' (nix-darwin, system-level, with
  # real per-domain typed/validated options for most of them). A separate
  # home-manager-level 'targets.darwin.defaults' module would just duplicate the
  # same domain/key/value writes through a second, less-typed mechanism.

  # ---------------------------------------------------------------------------
  # Out-of-store symlinks for app-bundle CLI binaries
  # ---------------------------------------------------------------------------
  # These apps are installed as Homebrew casks (managed by the nix-darwin
  # homebrew module, see darwin-configuration.nix) but ship their CLI binaries
  # inside the .app bundle rather than via a formula. mkOutOfStoreSymlink
  # creates a symlink to a path outside the nix store -- the target does not
  # need to exist at activation time, so a first-install where the cask has
  # not yet been installed is safe (the symlink is briefly dangling until
  # darwin-rebuild's brew bundle pass completes).
  #
  # Symlinks land in XDG_BIN_HOME (~/.local/bin), which .shellrc adds to PATH,
  # so no $HOMEBREW_PREFIX dependency is needed.

  # keybaseEnabled-gated to match darwin-configuration.nix's identically-gated
  # 'keybase' cask -- no point creating symlinks to an app that is never installed.
  home.file.".local/bin/keybase" = lib.mkIf keybaseEnabled {
    source = config.lib.file.mkOutOfStoreSymlink "/Applications/Keybase.app/Contents/SharedSupport/bin/keybase";
  };

  home.file.".local/bin/git-remote-keybase" = lib.mkIf keybaseEnabled {
    source = config.lib.file.mkOutOfStoreSymlink "/Applications/Keybase.app/Contents/SharedSupport/bin/git-remote-keybase";
  };

  # VSCodium Insiders ships its CLI at 'Contents/Resources/app/bin/codium-insiders'
  # inside the .app bundle. All three names (codium-insiders/codium/code) point at
  # the same real binary directly -- avoids a fragile symlink-to-symlink chain.
  home.file.".local/bin/codium-insiders".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/VSCodium - Insiders.app/Contents/Resources/app/bin/codium-insiders";

  home.file.".local/bin/codium".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/VSCodium - Insiders.app/Contents/Resources/app/bin/codium-insiders";

  home.file.".local/bin/code".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/VSCodium - Insiders.app/Contents/Resources/app/bin/codium-insiders";
}
