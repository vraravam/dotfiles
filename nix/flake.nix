{
  description = "macOS system configuration (nix-darwin + home-manager)";

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

    # Packaged directly by its own repo (see that repo's flake.nix and README.md
    # "Nix flake" section) rather than vendored here -- only meaningful when
    # KEYBASE_*_REPO_NAME or ENCRYPTED_*_REPO_URL is set in '.shellrc' (see
    # encryptedBackupEnabled below / modules/packages.nix). That repo's own
    # flake.nix does not declare 'inputs.nixpkgs.follows' itself (it is a
    # standalone, dependency-light flake with no reason to know about this one) --
    # the override below is declared on this side instead, so its nixpkgs shares
    # the same evaluation as everything else here rather than fetching a second,
    # separately-locked (if incidentally identical) copy.
    git-remote-gpg-encrypt = {
      url = "github:vraravam/git-remote-gpg-encrypt";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, home-manager, git-remote-gpg-encrypt }:
    let
      # Deciphered from the local system's environment rather than hardcoded --
      # mirrors EnvVars::USER's own 'USER, falling back to USERNAME' pattern (see
      # scripts/utilities/env_vars.rb) so this flake works unmodified for whoever
      # actually runs it, not just one specific machine/user. Requires '--impure'
      # (already required below for the same reason as shellrcContent).
      username =
        let
          fromUser = builtins.getEnv "USER";
          fromUsername = builtins.getEnv "USERNAME";
        in
        if fromUser != "" then fromUser
        else if fromUsername != "" then fromUsername
        else throw "Could not determine the local username from $USER or $USERNAME (both empty) -- re-run with '--impure' from a shell where one of these is set.";
      homeDir = "/Users/${username}";

      # Computed once here (not separately in darwin-configuration.nix and home.nix)
      # and threaded into both module trees via specialArgs/extraSpecialArgs below --
      # darwin-configuration.nix's homebrew.casks needs keybaseEnabled just as much as
      # home.nix/modules/packages.nix need it (and encryptedBackupEnabled), and the two
      # module trees do not share '_module.args' with each other. Mirrors the former
      # Brewfile's keybase_enabled/encrypted_backup_enabled Ruby snippet: reads
      # '.shellrc' directly (not an env var) so this reflects whatever the user has
      # actually configured there, regardless of what environment darwin-rebuild
      # happens to be invoked from.
      shellrcContent = builtins.readFile "${homeDir}/.shellrc";
      keybaseEnabled = builtins.match ".*\n[ \t]*export[ \t]+KEYBASE_(HOME|PROFILES)_REPO_NAME=.*" shellrcContent != null;
      encryptedBackupEnabled = builtins.match ".*\n[ \t]*export[ \t]+ENCRYPTED_(HOME|PROFILES)_REPO_URL=.*" shellrcContent != null;

      # Single darwinConfiguration, named 'default' -- Apple Silicon only.
      # nixpkgs dropped x86_64-darwin (Intel Mac) support entirely starting with its
      # 26.11 release ("Nixpkgs 26.11 has dropped support for x86_64-darwin" -- see
      # https://nixos.org/manual/nixpkgs/unstable/release-notes#x86_64-darwin-26.11).
      # Verified by actually evaluating this flake against an x86_64-darwin target: it
      # fails outright, before reaching any of this repo's own modules. An Intel-Mac
      # darwinConfiguration was deliberately dropped rather than worked around (e.g. a
      # second nixpkgs input pinned to nixpkgs-26.05-darwin, the last release still
      # supporting the platform) -- this setup targets Apple Silicon only going forward.
      #
      # Bootstrap (first run): nix run nix-darwin -- switch --flake "${DOTFILES_DIR}/nix#default" --impure
      # Subsequent runs:       darwin-rebuild switch --flake "${DOTFILES_DIR}/nix#default" --impure
      # Interactive shortcut:  nixup  (defined in .aliases)
      # DOTFILES_DIR is set by .shellrc (default: ~/.config/dotfiles) and available in
      # all contexts where these commands are run.
      #
      # '--impure' is required (not optional) every time this flake is evaluated:
      # keybaseEnabled/encryptedBackupEnabled above read '~/.shellrc' via
      # 'builtins.readFile', which Nix's pure evaluation mode disallows for paths
      # outside the flake's own source tree.
      mkDarwinSystem = system: nix-darwin.lib.darwinSystem {
        # specialArgs propagates these into darwin-configuration.nix's modules so they
        # can reference the home directory, keybaseEnabled, and the
        # git-remote-gpg-encrypt flake input without hardcoding /Users/<name> or
        # re-deriving the same booleans a second time.
        specialArgs = { inherit username keybaseEnabled encryptedBackupEnabled git-remote-gpg-encrypt; };
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
            # extraSpecialArgs propagates the same values into home.nix/modules/packages.nix.
            home-manager.extraSpecialArgs = { inherit username keybaseEnabled encryptedBackupEnabled git-remote-gpg-encrypt; };
          }
        ];
      };
    in
    {
      darwinConfigurations.default = mkDarwinSystem "aarch64-darwin";
    };
}
