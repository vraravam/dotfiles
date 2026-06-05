#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script runs post-bundle cleanup and plugin setup that cannot run as part
# of the nix-darwin activation or the brew bundle lifecycle.
#
# Symlinks for casks (keybase, zed) and login-item registrations live on their
# 'postinstall:' entries in nix/darwin-configuration.nix's homebrew.casks
# declarations — keeping each app's setup co-located with its installation.
#
# Symlinks for apps installed outside Homebrew (VSCodium, Rider, IntelliJ) are
# intentionally NOT managed here. Those apps provide their own CLI-install
# commands (JetBrains Toolbox, 'codium --install-shell-commands', etc.) and are
# not tracked by the nix-darwin homebrew module.

set -euo pipefail

# Re-source guard is inside .aliases itself — safe to call unconditionally.
source "${HOME}/.aliases"

main() {
  section_header "$(yellow 'Updating antidote plugins and regenerating antidote plugin bundle')"
  update_antidote_and_regenerate_plugin_bundle
}

main "$@"
