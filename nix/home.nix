{ config, pkgs, username, ... }:
{
  home.username      = username;
  home.homeDirectory = "/Users/${username}";

  # Must match the nixpkgs release used in the flake inputs to avoid
  # "state version mismatch" warnings from home-manager on every switch.
  home.stateVersion = "24.05";

  imports = [
    ./modules/packages.nix
    ./modules/osx-app-defaults.nix
  ];

  # ---------------------------------------------------------------------------
  # Out-of-store symlinks for app-bundle CLI binaries
  # ---------------------------------------------------------------------------
  # These apps are installed as Homebrew casks (managed by the nix-darwin
  # homebrew module) but ship their CLI binaries inside the .app bundle rather
  # than via a formula. mkOutOfStoreSymlink creates a symlink to a path outside
  # the nix store — the target does not need to exist at activation time, so a
  # first-install where the cask has not yet been installed is safe (the symlink
  # is briefly dangling until darwin-rebuild's brew bundle pass completes).
  #
  # Symlinks land in XDG_BIN_HOME (~/.local/bin), which .shellrc adds to PATH,
  # so no $HOMEBREW_PREFIX dependency is needed.

  home.file.".local/bin/keybase".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/Keybase.app/Contents/SharedSupport/bin/keybase";

  home.file.".local/bin/git-remote-keybase".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/Keybase.app/Contents/SharedSupport/bin/git-remote-keybase";

  # Zed Preview ships its CLI at 'Contents/MacOS/cli' inside the .app bundle.
  # A single symlink named 'zed' is sufficient — the intermediate 'zed-preview'
  # alias used by the old postinstall approach is not needed.
  home.file.".local/bin/zed".source =
    config.lib.file.mkOutOfStoreSymlink "/Applications/Zed Preview.app/Contents/MacOS/cli";
}
