#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script runs post-bundle cleanup and plugin setup that cannot live in the
# Brewfile itself because they require a full shell environment (.aliases functions).
#
# Symlinks for Brewfile-managed casks (keybase, zed) live directly on their
# 'cask' declarations via 'postinstall:' in the Brewfile — keeping each cask's
# setup co-located with its installation.
#
# Symlinks for apps installed outside Homebrew (VSCodium, Rider, IntelliJ) are
# intentionally NOT managed here. Those apps provide their own CLI-install
# commands (JetBrains Toolbox, 'codium --install-shell-commands', etc.) and are
# not tracked by brew bundle, so there is no reliable trigger point for them.

set -euo pipefail

# Re-source guard is inside .aliases itself — safe to call unconditionally.
source "${HOME}/.aliases"

main() {
  # Required for completions from other plugins (e.g. git-extras) to work
  rm -rf "${HOMEBREW_REPOSITORY}/share/zsh/site-functions/_git" &>/dev/null || true

  section_header "$(yellow 'Updating antidote plugins and regenerating antidote plugin bundle')"
  update_antidote_and_regenerate_plugin_bundle
}

main "$@"
