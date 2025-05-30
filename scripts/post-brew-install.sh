#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to run some commands at the end of the 'brew bundle' command. They are not inlined into the Brewfile due to the need to escape quoted strings.
# Do not exit immediately if a command exits with a non-zero status since this is run within a cronjob

# Source helpers only once if any required function is missing
type section_header &> /dev/null 2>&1 || source "${HOME}/.shellrc"

replace_symlink_if_needed() {
  if is_executable "${1}"; then
    # Check if target exists and is already the correct symlink
    if [[ -L "${2}" && "$(readlink "${2}")" == "${1}" ]]; then
      warn "Already correctly symlinked from '$(yellow "${1}")' to '$(yellow "${2}")'."
    else
      # Create or update the symlink, force overwrite if needed
      ln -sf "${1}" "${2}" && success "Successfully created symlink from '$(yellow "${1}")' to '$(yellow "${2}")'" || warn "Failed to create symlink from '${1}' to '${2}'"
    fi
  else
    warn "skipping symlinking since executable '$(yellow "${1}")' not found"
  fi
}

# This removal is required for completions from other plugins to work (for eg git-extras)
rm -rf "${HOMEBREW_REPOSITORY}/share/zsh/site-functions/_git" &> /dev/null

# Link programs to open from the cmd-line
section_header 'Linking keybase for command-line invocation'
if is_directory '/Applications/Keybase.app'; then
  replace_symlink_if_needed '/Applications/Keybase.app/Contents/SharedSupport/bin/keybase' "${HOMEBREW_PREFIX}/bin/keybase"
  replace_symlink_if_needed '/Applications/Keybase.app/Contents/SharedSupport/bin/git-remote-keybase' "${HOMEBREW_PREFIX}/bin/git-remote-keybase"
else
  warn 'skipping symlinking keybase for command-line invocation'
fi

section_header 'Linking VSCode/VSCodium for command-line invocation'
if is_directory '/Applications/VSCodium - Insiders.app'; then
  # Symlink from the embedded executable for codium-insiders
  replace_symlink_if_needed '/Applications/VSCodium - Insiders.app/Contents/Resources/app/bin/codium-insiders' "${HOMEBREW_PREFIX}/bin/codium-insiders"
  # if we are using 'vscodium-insiders' only, symlink it to 'codium' for ease of typing
  replace_symlink_if_needed "${HOMEBREW_PREFIX}/bin/codium-insiders" "${HOMEBREW_PREFIX}/bin/codium"
  # extra: also symlink for 'code'
  replace_symlink_if_needed "${HOMEBREW_PREFIX}/bin/codium" "${HOMEBREW_PREFIX}/bin/code"
elif is_directory '/Applications/VSCodium.app'; then
  # Symlink from the embedded executable for codium
  replace_symlink_if_needed '/Applications/VSCodium.app/Contents/Resources/app/bin/codium' "${HOMEBREW_PREFIX}/bin/codium"
  # extra: also symlink for 'code'
  replace_symlink_if_needed "${HOMEBREW_PREFIX}/bin/codium" "${HOMEBREW_PREFIX}/bin/code"
elif is_directory '/Applications/VSCode.app'; then
  # Symlink from the embedded executable for code
  replace_symlink_if_needed '/Applications/VSCode.app/Contents/Resources/app/bin/code' "${HOMEBREW_PREFIX}/bin/code"
else
  warn 'skipping symlinking vscode/vscodium for command-line invocation'
fi

section_header 'Linking rider for command-line invocation'
if is_directory '/Applications/Rider.app'; then
  replace_symlink_if_needed '/Applications/Rider.app/Contents/MacOS/rider' "${HOMEBREW_PREFIX}/bin/rider"
else
  warn 'skipping symlinking rider for command-line invocation'
fi

section_header 'Linking idea/idea-ce for command-line invocation'
if is_directory '/Applications/IntelliJ IDEA CE.app'; then
  replace_symlink_if_needed '/Applications/IntelliJ IDEA CE.app/Contents/MacOS/idea' "${HOMEBREW_PREFIX}/bin/idea"
elif is_directory '/Applications/IntelliJ IDEA.app'; then
  replace_symlink_if_needed '/Applications/IntelliJ IDEA.app/Contents/MacOS/idea' "${HOMEBREW_PREFIX}/bin/idea"
else
  warn 'skipping symlinking idea/idea-ce for command-line invocation'
fi

section_header 'Linking zed for command-line invocation'
if is_directory '/Applications/Zed Preview.app'; then
  replace_symlink_if_needed "${HOMEBREW_PREFIX}/bin/zed-preview" "${HOMEBREW_PREFIX}/bin/zed"
  replace_symlink_if_needed '/Applications/Zed Preview.app/Contents/MacOS/cli' "${HOMEBREW_PREFIX}/bin/zed-preview"
elif is_directory '/Applications/Zed.app'; then
  replace_symlink_if_needed '/Applications/Zed.app/Contents/MacOS/cli' "${HOMEBREW_PREFIX}/bin/zed"
else
  warn 'skipping symlinking zed for command-line invocation'
fi

# Setup the login items once the full list of applications has been installed on the machine
"${DOTFILES_DIR}/scripts/setup-login-item.sh" 'ZoomHider'

# Cleanup temp functions, etc
unfunction replace_symlink_if_needed
