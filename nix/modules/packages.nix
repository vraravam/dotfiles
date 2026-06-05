{ pkgs, ... }:
{
  # All CLI tools formerly managed by Homebrew formulae are declared here.
  # Homebrew is kept only for GUI casks and formulae not in nixpkgs
  # (git-tools, mole from xykong/tap, opencode).
  #
  # nixpkgs name mapping notes:
  #   brew grep      -> pkgs.gnugrep
  #   brew sqlite3   -> pkgs.sqlite
  #   brew gnu-tar   -> pkgs.gnutar
  #   brew git +
  #   brew git-gui   -> pkgs.gitFull  (gitFull includes git-gui via tcl/tk)
  #
  # Packages with uncertain nixpkgs availability are kept in the Brewfile
  # until confirmed: mole (xykong/tap), opencode, git-tools.
  home.packages = with pkgs; [
    # --- System-level replacements (updated versions of macOS bundled tools) ---
    # These override the macOS-bundled equivalents; nix-darwin's /etc/zshrc
    # ensures ~/.nix-profile/bin is prepended to PATH in every shell.
    bash
    curl
    gitFull     # includes git-gui (provides 'git gui' sub-command via tcl/tk)
    gmp
    gnugrep
    less
    libyaml
    openssl
    readline
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
    git-trim
    mise
    starship

    # --- Advanced / recommended tooling ---
    bat
    btop
    jaq
    moreutils
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
  ];
}
