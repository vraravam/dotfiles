{
  description = "vijay's macOS system configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, home-manager }:
    let
      # Single source of truth for the macOS username. Referenced in specialArgs
      # so darwin-configuration.nix and home.nix never hardcode this value.
      username = "vijay";

      # Two named configurations avoid hostname-based conditionals in the modules.
      # Use 'arm' on Apple Silicon and 'intel' on x86_64 Macs.
      # Bootstrap (first run): nix run nix-darwin -- switch --flake "${DOTFILES_DIR}/nix#arm"
      # Subsequent runs:       darwin-rebuild switch --flake "${DOTFILES_DIR}/nix#arm"
      # Interactive shortcut:  nixup  (defined in .aliases, selects the key via is_arm)
      # DOTFILES_DIR is set by .shellrc (default: ~/.config/dotfiles) and available in
      # all contexts where these commands are run.
      mkDarwinSystem = system: nix-darwin.lib.darwinSystem {
        # specialArgs propagates username into darwin-configuration.nix modules so
        # they can reference the home directory without hardcoding /Users/<name>.
        specialArgs = { inherit username; };
        modules = [
          { nixpkgs.hostPlatform = system; }
          ./darwin-configuration.nix
          home-manager.darwinModules.home-manager
          {
            # useGlobalPkgs: home-manager uses the same nixpkgs instance as nix-darwin,
            # avoiding a second nixpkgs evaluation and ensuring consistent package versions.
            home-manager.useGlobalPkgs = true;
            # useUserPackages: packages land at ~/.nix-profile/ so their binaries and share
            # files are reachable without any extra PATH or XDG_DATA_DIRS manipulation.
            home-manager.useUserPackages = true;
            home-manager.users.${username} = import ./home.nix;
            # extraSpecialArgs propagates username into home.nix so home.username and
            # home.homeDirectory are derived rather than hardcoded.
            home-manager.extraSpecialArgs = { inherit username; };
          }
        ];
      };
    in
    {
      darwinConfigurations = {
        arm   = mkDarwinSystem "aarch64-darwin";
        intel = mkDarwinSystem "x86_64-darwin";
      };
    };
}
