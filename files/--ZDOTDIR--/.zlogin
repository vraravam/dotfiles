#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# This file is sourced only for login shells. It should contain commands that
# should be executed only in login shells. It should be used to set the terminal
# type and run a series of external commands (fortune, msgs, from, etc.)
# Note that using zprofile and zlogin, you are able to run commands for login
# shells before and after zshrc.
#
# file location: ${ZDOTDIR}/.zlogin
# load order: .zshenv [.shellrc], .zshrc [.shellrc, .aliases [.shellrc]], .zlogin
################################################################################

# execute 'DEBUG=true zsh' to debug the load order of the custom zsh configuration files
[[ -n "${DEBUG:-}" ]] && echo "loading ${0}"

# Re-source guard is inside .shellrc itself — safe to call unconditionally.
source "${HOME}/.shellrc"

recompile_zsh_scripts() {
  # Resolve symlinks for the mtime check: zsh's -nt operator compares symlink mtime
  # (not target mtime), so edits to the dotfiles target never trigger recompilation
  # without resolving to the real path first.
  # The .zwc file lives next to the symlink (${1}.zwc), not next to the real file.
  local real="${1:A}"
  if is_non_empty_file "${real}" && (! is_file "${1}.zwc" || [[ "${real}" -nt "${1}.zwc" ]]); then
    # Bare echo — not routed through a color function, so tilde sub must be explicit.
    # Inline ${1//${HOME}/~} rather than replace_home_with_tilde: .shellrc is already
    # sourced above (line 20), so replace_home_with_tilde is available here. The inline
    # form is kept as a belt-and-suspenders measure against any future reordering.
    [[ -n "${DEBUG:-}" ]] && echo "recompiling '${1//${HOME}/~}'"
    # Remove any stale .zwc.old left by a previously failed zrecompile run before
    # attempting recompilation. zrecompile writes .zwc files read-only; if zcompile
    # fails mid-write the .zwc.old backup is left behind — clean it up unconditionally.
    rm -f "${1}.zwc.old" || true
    zrecompile -pq "${1}" &>/dev/null || true
    # Remove .zwc.old again in case this run moved the old file there before failing.
    rm -f "${1}.zwc.old" || true
  fi
}

recompile_zsh_autoload_dir() {
  # Compile extensionless zsh autoload function files (files with no suffix).
  # find_in_folder_and_recompile only picks up *.sh / *.zsh; autoloaded functions
  # under e.g. XDG_CONFIG_HOME/zsh/ have no extension and would be missed without
  # this dedicated helper.
  # NOTE: Do NOT replace this call with find_in_folder_and_recompile — that function
  # matches only '*.sh' and '*.zsh' patterns, so it would silently skip every
  # extensionless autoload file (cc, count, pull, push, st, etc.) in this directory.
  local dir_to_scan="${1}"

  if ! is_directory "${dir_to_scan}"; then
    warn "Directory '$(yellow "${dir_to_scan}")' not found for zsh autoload recompilation." >&2
    return
  fi

  # Anonymous function scopes NULL_GLOB so unmatched globs expand to nothing
  # rather than producing an error. is_file filters for regular files, replacing
  # the (.) glob qualifier (avoided: breaks editor syntax highlighting).
  () {
    setopt localoptions NULL_GLOB
    local f
    for f in "${dir_to_scan}"/*; do
      # Skip files that already have an extension — those are handled elsewhere.
      if is_file "${f}" && [[ "${f:e}" == "" ]]; then
        recompile_zsh_scripts "${f}"
      fi
    done
  }
}

find_in_folder_and_recompile() {
  local dir_to_scan="${1}"
  local f # Loop variable

  if ! is_directory "${dir_to_scan}"; then
    warn "Directory '$(yellow "${dir_to_scan}")' not found for zsh script recompilation." >&2
    return
  fi

  # Mtime sentinel: skip the expensive find scan if nothing in the directory has
  # changed since the last recompilation run.  The sentinel file is stored under
  # XDG_CACHE_HOME, keyed by a sanitised form of the directory path.
  # The sentinel is touched after a successful scan so the next login is free.
  local sentinel="${XDG_CACHE_HOME}/zwc-sentinel-${dir_to_scan//\//-}"
  if is_file "${sentinel}" && [[ "${sentinel}" -nt "${dir_to_scan}" ]]; then
    # Bare echo — same reasoning as above: inline to avoid .shellrc load-order dependency.
    [[ -n "${DEBUG:-}" ]] && echo "skipping recompile scan (unchanged): '${dir_to_scan//${HOME}/~}'"
    return
  fi

  find "${dir_to_scan}" -maxdepth 5 \
    \( \( -name 'node_modules' -o -name '.pnpm' \) -type d -prune \) -o \
    \( \( -name '*.sh' -o -name '*.zsh' \) -type f -print0 \) |
    while IFS= read -r -d $'\0' f; do
      recompile_zsh_scripts "${f}"
    done

  touch "${sentinel}"
}

# <https://github.com/zimfw/zimfw/blob/master/login_init.zsh>
autoload -Uz zrecompile

# zsh config files can be compiled to improve performance
# Based from: https://github.com/romkatv/zsh-bench/blob/master/configs/ohmyzsh%2B/setup
# Core startup files — grouped together regardless of whether they live in
# ZDOTDIR or HOME; all are sourced on every shell start and benefit equally
# from bytecode compilation.
recompile_zsh_scripts "${ZDOTDIR}/.zshenv"
recompile_zsh_scripts "${ZDOTDIR}/.zshrc"
recompile_zsh_scripts "${ZDOTDIR}/.zlogin"
recompile_zsh_scripts "${HOME}/.shellrc"
recompile_zsh_scripts "${HOME}/.aliases"

# zcompdump has no extension so find_in_folder_and_recompile's *.sh/*.zsh glob
# misses it. Compile it explicitly so compinit loads bytecode on subsequent
# startups instead of parsing from source (~2-4ms savings per shell start).
recompile_zsh_scripts "${XDG_CACHE_HOME}/zcompdump"

# The antidote static bundle lives in ZDOTDIR (not ANTIDOTE_HOME or XDG_CACHE_HOME),
# so it is not picked up by any of the find_in_folder_and_recompile scans below.
# Compile it explicitly so every shell startup sources bytecode, not raw zsh text.
recompile_zsh_scripts "${ANTIDOTE_PLUGIN_ZSH}"

# antidote.zsh is intentionally NOT compiled to .zwc.
# antidote 2.1.0 detects whether it is being sourced (vs run as a CLI) by checking
# ZSH_EVAL_CONTEXT for the token 'file'. When loaded from .zwc bytecode, zsh sets
# the token to 'filecode' instead, which does not match antidote's '*:file:*' pattern.
# The CLI branch then fires, calls exit 1, and crashes the interactive shell.
# Loading antidote.zsh from raw source on every startup is the only safe approach
# until antidote fixes its source-detection check to also match 'filecode'.

find_in_folder_and_recompile "${ANTIDOTE_HOME}"

# Compile third-party completion scripts that are sourced directly at startup.
# Without a .zwc these are parsed from source on every shell start.
# These live outside DOTFILES_DIR / XDG_CACHE_HOME / ANTIDOTE_HOME, so they are
# not covered by the find_in_folder_and_recompile calls below. Add any new
# third-party sourced completions here rather than extending those scans.
#
# git-extras: nix is the primary install (same probe order as .zshrc). The nix
# profile path is read-only so zrecompile silently no-ops when nix-managed; the
# call is still correct for the brew-fallback path where the file is writable.
if is_file "${HOME}/.nix-profile/share/git-extras/git-extras-completion.zsh"; then
  recompile_zsh_scripts "${HOME}/.nix-profile/share/git-extras/git-extras-completion.zsh"
else
  recompile_zsh_scripts "${HOMEBREW_PREFIX}/opt/git-extras/share/git-extras/git-extras-completion.zsh"
fi

# Compile extensionless autoload function files under XDG_CONFIG_HOME/zsh/.
# These are not *.sh / *.zsh so find_in_folder_and_recompile misses them.
recompile_zsh_autoload_dir "${XDG_CONFIG_HOME}/zsh"

# Compile all *.zsh cache files under XDG_CACHE_HOME (brew shellenv, starship init,
# repo aliases, fast-syntax-highlighting theme, etc.).  A directory scan is used
# rather than listing individual files so any new cache files added in future are
# picked up automatically without needing to update this file.
#
# Note: XDG_CACHE_HOME is NOT guarded by the mtime sentinel in practice — .zshrc
# always writes (or touches) cache files before .zlogin runs, so the sentinel
# ('-nt' check) never passes and 'find' always executes. Running this in the
# background avoids blocking the first prompt on login shells.
{
  find_in_folder_and_recompile "${DOTFILES_DIR}"
  find_in_folder_and_recompile "${PERSONAL_BIN_DIR}"
  find_in_folder_and_recompile "${PROJECTS_BASE_DIR}"
  find_in_folder_and_recompile "${XDG_CACHE_HOME}"
  # explicitly use both intel and arm install locations of homebrew
  find_in_folder_and_recompile /opt/homebrew
  find_in_folder_and_recompile /usr/local
} &|

if [[ -n "${DEBUG:-}" ]]; then echo "Finished recompiling zsh scripts."; fi
