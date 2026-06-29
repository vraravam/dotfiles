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
if [[ -n "${DEBUG:-}" ]]; then echo "loading ${0}"; fi

# .shellrc was already sourced by .zshrc (which runs before .zlogin).
# The re-source guard makes this a no-op, but checking the guard itself adds
# overhead. Skip the source call entirely -- .zlogin only uses utilities
# (is_directory, is_file, ensure_dir_exists, recompile_zsh_script) that are
# already loaded from .zshrc's earlier source.

# recompile_zsh_script is defined in .shellrc and used by both .zshrc (for cache
# file compilation) and .zlogin (for bulk script recompilation). See .shellrc for
# implementation details (symlink resolution, .zwc.old cleanup, mtime checking).

recompile_zsh_autoload_dir() {
  # Compile extensionless zsh autoload function files (files with no suffix).
  # find_in_folder_and_recompile only picks up *.sh / *.zsh; autoloaded functions
  # under e.g. XDG_CONFIG_HOME/zsh/ have no extension and would be missed without
  # this dedicated helper.
  # NOTE: Do NOT replace this call with find_in_folder_and_recompile -- that function
  # matches only '*.sh' and '*.zsh' patterns, so it would silently skip every
  # extensionless autoload file (cc, count, pull, push, st, etc.) in this directory.
  local dir_to_scan="${1:-}"

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
      # Skip files that already have an extension -- those are handled elsewhere.
      if is_file "${f}" && [[ "${f:e}" == "" ]]; then
        recompile_zsh_script "${f}"
      fi
    done
  }
}

find_in_folder_and_recompile() {
  local dir_to_scan="${1:-}"
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
  if ! is_file_older_than "${sentinel}" "${dir_to_scan}"; then
    # Bare echo -- same reasoning as above: inline to avoid .shellrc load-order dependency.
    if [[ -n "${DEBUG:-}" ]]; then echo "skipping recompile scan (unchanged): '${dir_to_scan//${HOME}/~}'"; fi
    return
  fi

  find "${dir_to_scan}" -maxdepth 5 \
    \( \( -name 'node_modules' -o -name '.pnpm' \) -type d -prune \) -o \
    \( \( -name '*.sh' -o -name '*.zsh' \) -type f -print0 \) |
    while IFS= read -r -d $'\0' f; do
      recompile_zsh_script "${f}"
    done

  # Ensure XDG_CACHE_HOME exists before touching the sentinel file.
  # On vanilla OS during fresh-install, the directory may not exist yet when
  # load_zsh_configs is first called (before _ensure_directories_exist runs).
  ensure_dir_exists "${XDG_CACHE_HOME}"
  touch "${sentinel}"
}

# zrecompile is already autoloaded in .zshrc (which runs before .zlogin).

# zsh config files can be compiled to improve performance
# Based from: https://github.com/romkatv/zsh-bench/blob/master/configs/ohmyzsh%2B/setup
# Core startup files -- grouped together regardless of whether they live in
# ZDOTDIR or HOME; all are sourced on every shell start and benefit equally
# from bytecode compilation.
recompile_zsh_script "${ZDOTDIR}/.zshenv"
recompile_zsh_script "${ZDOTDIR}/.zshrc"
recompile_zsh_script "${ZDOTDIR}/.zlogin"
recompile_zsh_script "${HOME}/.shellrc"
recompile_zsh_script "${HOME}/.aliases"

# zcompdump has no extension so find_in_folder_and_recompile's *.sh/*.zsh glob
# misses it. Compile it explicitly so compinit loads bytecode on subsequent
# startups instead of parsing from source (~2-4ms savings per shell start).
recompile_zsh_script "${XDG_CACHE_HOME}/zcompdump"

# The antidote static bundle lives in ZDOTDIR (not ANTIDOTE_HOME or XDG_CACHE_HOME),
# so it is not picked up by any of the find_in_folder_and_recompile scans below.
# Compile it explicitly so every shell startup sources bytecode, not raw zsh text.
recompile_zsh_script "${ANTIDOTE_PLUGIN_ZSH}"

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
recompile_zsh_script "${HOMEBREW_PREFIX}/opt/git-extras/share/git-extras/git-extras-completion.zsh"

# Compile extensionless autoload function files under XDG_CONFIG_HOME/zsh/.
# These are not *.sh / *.zsh so find_in_folder_and_recompile misses them.
recompile_zsh_autoload_dir "${XDG_CONFIG_HOME}/zsh"

# Compile all *.zsh cache files under XDG_CACHE_HOME (brew shellenv, starship init,
# repo aliases, fast-syntax-highlighting theme, etc.).  A directory scan is used
# rather than listing individual files so any new cache files added in future are
# picked up automatically without needing to update this file.
#
# Note: XDG_CACHE_HOME is NOT guarded by the mtime sentinel in practice -- .zshrc
# always writes (or touches) cache files before .zlogin runs, so the sentinel check
# never passes and 'find' always executes. Running this in the background avoids
# blocking the first prompt on login shells.
#
# Performance optimization: Order these from smallest to largest scope to maximize
# early completion of fast scans. DOTFILES_DIR and PERSONAL_BIN_DIR are small and
# finish quickly; XDG_CACHE_HOME is medium; PROJECTS_BASE_DIR and Homebrew paths
# are largest. The sentinel mechanism in find_in_folder_and_recompile already
# short-circuits unchanged directories, but ordering still helps when changes exist.
{
  find_in_folder_and_recompile "${XDG_CACHE_HOME}"
  find_in_folder_and_recompile "${DOTFILES_DIR}"
  find_in_folder_and_recompile "${PERSONAL_BIN_DIR}"
  find_in_folder_and_recompile "${PROJECTS_BASE_DIR}"
  # Only scan the active Homebrew prefix (not both /opt/homebrew and /usr/local).
  # HOMEBREW_PREFIX is set by the brew shellenv cache in .zshrc and points to
  # the actual installation (/opt/homebrew on Apple Silicon, /usr/local on Intel).
  # Scanning the inactive prefix wastes time -- it either doesn't exist or contains
  # no actively-sourced scripts. find handles nonexistent paths gracefully (warns
  # but continues), but the wasted fork+stat overhead adds up across login shells.
  if is_non_zero_string "${HOMEBREW_PREFIX:-}"; then
    find_in_folder_and_recompile "${HOMEBREW_PREFIX}"
  fi
} &|

if [[ -n "${DEBUG:-}" ]]; then echo "Finished recompiling zsh scripts."; fi
