#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to run some commands at the end of the 'brew bundle' command. They are not inlined into the Brewfile due to the need to escape quoted strings.

type section_header &> /dev/null 2>&1 || source "${HOME}/.shellrc"

setup_login_item() {
  local app_path="/Applications/${1}.app"
  if is_directory "${app_path}"; then
    local found=$(osascript -e 'tell application "System Events" to get the name of every login item' | \grep -i "${1}")
    if ! is_non_zero_string "${found}"; then
      osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"${app_path}\", hidden:false}" 2>&1 > /dev/null
      success "Successfully setup '$(yellow "${1}")' as a login item"
    fi
    unset found
  else
    warn "Couldn't find application '$(yellow "${app_path}")' and so skipping setting up as a login item"
  fi
  unset app_path
}

replace_executable_if_exists_and_is_not_symlinked() {
  is_executable "${2}" && return

  if is_executable "${1}"; then
    rm -rf "${2}"
    ln -sf "${1}" "${2}"
  else
    warn "skipping symlinking since executable '$(yellow "${1}")' not found"
  fi
}

# This removal is required for completions from other plugins to work (for eg git-extras)
rm -rfv "${HOMEBREW_REPOSITORY}/share/zsh/site-functions/_git" &> /dev/null 2>&1

# Link programs to open from the cmd-line
section_header 'Linking keybase for command-line invocation'
if is_directory '/Applications/Keybase.app'; then
  replace_executable_if_exists_and_is_not_symlinked '/Applications/Keybase.app/Contents/SharedSupport/bin/keybase' "${HOMEBREW_PREFIX}/bin/keybase"
  replace_executable_if_exists_and_is_not_symlinked '/Applications/Keybase.app/Contents/SharedSupport/bin/git-remote-keybase' "${HOMEBREW_PREFIX}/bin/git-remote-keybase"
  success 'Successfully linked keybase into PATH'
else
  warn 'skipping symlinking keybase for command-line invocation'
fi

section_header 'Linking VSCode/VSCodium for command-line invocation'
if is_directory '/Applications/VSCodium - Insiders.app'; then
  # Symlink from the embedded executable for codium-insiders
  replace_executable_if_exists_and_is_not_symlinked '/Applications/VSCodium - Insiders.app/Contents/Resources/app/bin/codium-insiders' "${HOMEBREW_PREFIX}/bin/codium-insiders"
  # if we are using 'vscodium-insiders' only, symlink it to 'codium' for ease of typing
  replace_executable_if_exists_and_is_not_symlinked "${HOMEBREW_PREFIX}/bin/codium-insiders" "${HOMEBREW_PREFIX}/bin/codium"
  # extra: also symlink for 'code'
  replace_executable_if_exists_and_is_not_symlinked "${HOMEBREW_PREFIX}/bin/codium" "${HOMEBREW_PREFIX}/bin/code"
  success 'Successfully linked vscodium-insiders into PATH'
elif is_directory '/Applications/VSCodium.app'; then
  # Symlink from the embedded executable for codium
  replace_executable_if_exists_and_is_not_symlinked '/Applications/VSCodium.app/Contents/Resources/app/bin/codium' "${HOMEBREW_PREFIX}/bin/codium"
  # extra: also symlink for 'code'
  replace_executable_if_exists_and_is_not_symlinked "${HOMEBREW_PREFIX}/bin/codium" "${HOMEBREW_PREFIX}/bin/code"
  success 'Successfully linked vscodium into PATH'
elif is_directory '/Applications/VSCode.app'; then
  # Symlink from the embedded executable for code
  replace_executable_if_exists_and_is_not_symlinked '/Applications/VSCode.app/Contents/Resources/app/bin/code' "${HOMEBREW_PREFIX}/bin/code"
  success 'Successfully linked vscode into PATH'
else
  warn 'skipping symlinking vscode/vscodium for command-line invocation'
fi

section_header 'Linking rider for command-line invocation'
if is_directory '/Applications/Rider.app'; then
  replace_executable_if_exists_and_is_not_symlinked '/Applications/Rider.app/Contents/MacOS/rider' "${HOMEBREW_PREFIX}/bin/rider"
  success 'Successfully linked rider into PATH'
else
  warn 'skipping symlinking rider for command-line invocation'
fi

section_header 'Linking idea/idea-ce for command-line invocation'
if is_directory '/Applications/IntelliJ IDEA CE.app'; then
  replace_executable_if_exists_and_is_not_symlinked '/Applications/IntelliJ IDEA CE.app/Contents/MacOS/idea' "${HOMEBREW_PREFIX}/bin/idea"
  success 'Successfully linked idea-ce into PATH'
elif is_directory '/Applications/IntelliJ IDEA.app'; then
  replace_executable_if_exists_and_is_not_symlinked '/Applications/IntelliJ IDEA.app/Contents/MacOS/idea' "${HOMEBREW_PREFIX}/bin/idea"
  success 'Successfully linked idea into PATH'
else
  warn 'skipping symlinking idea/idea-ce for command-line invocation'
fi

# Setup the login items once the full list of applications has been installed on the machine
setup_login_item 'AlDente'
setup_login_item 'Clocker'
setup_login_item 'Ice'
setup_login_item 'KeepingYouAwake'
setup_login_item 'Keybase'
setup_login_item 'Raycast'
setup_login_item 'Stats'
setup_login_item 'ZoomHider'

# Cleanup temp functions, etc
unfunction setup_login_item
unfunction replace_executable_if_exists_and_is_not_symlinked
