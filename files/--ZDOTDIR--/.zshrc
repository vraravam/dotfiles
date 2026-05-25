#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# This file is sourced only for interactive shells. It should contain commands
# to set up aliases, functions, options, key bindings, etc.
#
# file location: ${ZDOTDIR}/.zshrc
# load order: .zshenv [.shellrc], .zshrc [.shellrc, .aliases [.shellrc]], .zlogin
################################################################################

# Optimizing zsh:
# https://htr3n.github.io/2018/07/faster-zsh/
# https://blog.mattclemente.com/2020/06/26/oh-my-zsh-slow-to-load/

# execute 'DEBUG=true zsh' to debug the load order of the custom zsh configuration files
[[ -n "${DEBUG+1}" ]] && echo "loading ${0}"

# for profiling zsh, see: https://unix.stackexchange.com/a/329719/27109
# execute 'ZSH_PROFILE_RC=true zsh -i -c exit' and run 'zprof' to get the details
[[ -n "${ZSH_PROFILE_RC+1}" ]] && zmodload zsh/zprof

# Faster than 'type is_shellrc_sourced &>/dev/null': no subshell, pure zsh builtin check.
(( $+functions[is_shellrc_sourced] )) || source "${HOME}/.shellrc"

# ──────────────────────────────────────────────────────────────────────────────
# Antidote — static plugin bundle
#
# antidote is a zsh plugin manager distributed as a zsh script (not a binary).
# It is sourced from the brew-installed path to make the 'antidote' function
# available for 'antidote update' and 'antidote bundle' commands.
# ──────────────────────────────────────────────────────────────────────────────

# Source antidote itself so the 'antidote' function is available (for update/bundle).
# Guarded so a vanilla OS (before brew installs antidote) still works fine.
#
# Unset $ZSH and $ZSH_CUSTOM before sourcing so that the OMZ lib files loaded
# via antidote can self-initialise them to their actual locations in the antidote
# cache.
# Without this, stale values left over from a prior OMZ install (e.g.
# $ZSH=~/.oh-my-zsh, $ZSH_CUSTOM=~/.oh-my-zsh/custom) would be kept and OMZ
# internals would silently break.
unset ZSH ZSH_CUSTOM
load_file_if_exists "${ANTIDOTE_ZSH}"

# zsh-autosuggestions — all options must be set before the antidote bundle is
# sourced; the plugin reads them at load time.
#
# USE_ASYNC: fetch suggestions in a background zpty process so ZLE never blocks
# while waiting for a history/completion lookup — directly reduces first-keystroke
# and mid-typing latency.
#
# MANUAL_REBIND: skip the full ZLE widget rebind that autosuggestions performs on
# every precmd call. Without this, every prompt incurs ~10-20ms of widget
# re-registration. Widgets are bound once at plugin load and never touched again.
#
# BUFFER_MAX_SIZE: skip suggestion lookups when the command line exceeds this
# length. Avoids expensive history DB scans for long one-liners where a
# suggestion is rarely useful anyway.
#
# HISTORY_IGNORE: skip history entries longer than 100 chars. Reduces regex
# matching cost on large history files — long entries (URLs, one-liners) are
# almost never the intended suggestion target.
#
# STRATEGY=(history): use only the history strategy. The 'completion' strategy
# spawns a zpty (pseudoterminal) on every suggestion request — ~10-30ms overhead
# per lookup. History alone is faster and covers the vast majority of useful
# suggestions; completion suggestions are better served by pressing Tab explicitly.
export ZSH_AUTOSUGGEST_USE_ASYNC=1
export ZSH_AUTOSUGGEST_MANUAL_REBIND=1
export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
export ZSH_AUTOSUGGEST_HISTORY_IGNORE="?(#c100,)"
export ZSH_AUTOSUGGEST_STRATEGY=(history)
# eza plugin: enable icons
zstyle ':omz:plugins:eza' 'icons' yes
# iterm2 plugin: enable shell integration
zstyle ':omz:plugins:iterm2' shell-integration yes
# correction: activated by lib/correction.zsh when ENABLE_CORRECTION is set
export ENABLE_CORRECTION='true'

# Cache brew shellenv to avoid running the brew binary on every shell startup (it's slow due to Ruby startup).
# The cache is invalidated when the brew binary itself changes (i.e. after brew upgrades).
# The cache pre-evaluates path_helper so sourcing it is a pure-zsh operation (no subprocesses).
() {
  local brew_bin="${HOMEBREW_PREFIX}/bin/brew"
  local cache_file="${XDG_CACHE_HOME}/brew-shellenv-cache.zsh"
  # Use the brew binary's modification time as cache key (no need to run brew at all for the check)
  if ! is_file "${cache_file}" || [[ "${brew_bin}" -nt "${cache_file}" ]]; then
    # Run brew shellenv in a subshell to get brew vars + path_helper result without polluting current PATH
    local brew_cellar brew_repo brew_infopath brew_manpath brew_prefix
    eval "$("${brew_bin}" shellenv 2>/dev/null)"
    brew_prefix="${HOMEBREW_PREFIX}"
    brew_cellar="${HOMEBREW_CELLAR}"
    brew_repo="${HOMEBREW_REPOSITORY}"
    brew_infopath="${INFOPATH}"
    brew_manpath="${MANPATH}"
    # Write a static cache: static exports + fpath update (no subprocess calls when cache is sourced)
    {
      echo "export HOMEBREW_PREFIX='${brew_prefix}';"
      echo "export HOMEBREW_CELLAR='${brew_cellar}';"
      echo "export HOMEBREW_REPOSITORY='${brew_repo}';"
      echo "export INFOPATH='${brew_infopath}';"
      echo "export MANPATH='${brew_manpath}';"
      # fpath assignment is sufficient — zsh keeps fpath and FPATH in sync automatically.
      # Exporting FPATH leaks it into child processes and launchd user-session environment;
      # typeset +x at the bottom of this file strips the export flag after all sources.
      echo "fpath=('${brew_prefix}/share/zsh/site-functions' \"\${fpath[@]}\");"
    } >| "${cache_file}" 2>/dev/null
  fi
  load_file_if_exists "${cache_file}"
}

load_file_if_exists "${HOMEBREW_PREFIX}/opt/git-extras/share/git-extras/git-extras-completion.zsh"

# compinit: use -C (skip compaudit scan) when the dump file already exists,
# saving ~11ms per startup. Safe on a personal machine where we control all
# fpath directories. ZSH_COMPDUMP is set to XDG_CACHE_HOME to keep ~ clean.
export ZSH_COMPDUMP="${XDG_CACHE_HOME}/zcompdump"
() {
  autoload -Uz compinit
  if is_file "${ZSH_COMPDUMP}"; then
    compinit -C -d "${ZSH_COMPDUMP}"
  else
    compinit -d "${ZSH_COMPDUMP}"
  fi
}

# Source the pre-generated antidote static bundle.
# On a vanilla OS (before brew installs antidote) this file is present because
# it is checked into the home repo. No antidote binary is needed during the
# shell startup.
load_file_if_exists "${ANTIDOTE_PLUGIN_ZSH}"

# Activate mise — the OMZ mise plugin referenced $ZSH_CACHE_DIR (undefined without OMZ)
# so it has been removed from .zsh_plugins.txt and replaced with a direct activation here.
#
# Performance optimisation — cache `mise activate zsh` output to avoid forking the mise
# binary on every shell start (~5-10ms saving). Same pattern as the starship init cache
# below. The cache is keyed on the mise binary mtime and regenerated only when mise itself
# is updated (e.g. after `brew upgrade`).
if command_exists mise; then
  () {
    local mise_bin="${commands[mise]}"
    local cache="${XDG_CACHE_HOME}/mise-activate-cache.zsh"
    if ! is_file "${cache}" || [[ "${mise_bin}" -nt "${cache}" ]]; then
      mise activate zsh >| "${cache}" 2>/dev/null
    fi
    load_file_if_exists "${cache}"
  }
fi

# Initialize starship prompt (must be after plugins so it wins the PROMPT setup).
#
# Performance optimisation — cache `starship init zsh` output to avoid forking a
# subprocess on every shell start (~10-15ms saving).  The cache is keyed on the
# starship binary mtime and regenerated only when starship itself is updated
# (e.g. after `brew upgrade`).
#
# NOTE: Deferring the source of the cache via a precmd hook was attempted but
# causes 'setopt promptsubst' (emitted by starship's init) to be scoped to the
# precmd function and unset on return (due to 'setopt local_options' in .zshrc),
# which leaves PROMPT as an unexpanded literal string after the first command.
# The cache is therefore sourced directly at startup; the ~5ms cost of sourcing
# the pre-parsed .zwc bytecode is acceptable.
if command_exists starship; then
  () {
    # $commands[] is an O(1) zsh hash lookup — no subprocess fork needed.
    local starship_bin="${commands[starship]}"
    local cache="${XDG_CACHE_HOME}/starship-init-cache.zsh"
    # Regenerate the cache only when the starship binary is newer than the cache file.
    if ! is_file "${cache}" || [[ "${starship_bin}" -nt "${cache}" ]]; then
      starship init zsh >| "${cache}" 2>/dev/null
    fi
    # Source directly at the top level (not deferred) so that 'setopt promptsubst'
    # emitted by the cache takes effect globally and is not scoped to a function.
    load_file_if_exists "${cache}"
  }
fi

# User configuration
# export MANPATH="/usr/local/man${MANPATH+:$MANPATH}"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

unset EDITOR
# Preferred editor for remote sessions
if is_non_zero_string "${SSH_CONNECTION}"; then
  export EDITOR='vi'
else
  # Preferred editor for local sessions
  local preferred_editors=('zed --wait' 'code --wait' 'vi')
  for editor in "${preferred_editors[@]}"; do
    # ${editor%% *} strips everything after the first space — pure zsh, no fork.
    # Equivalent to extract_first_word but avoids a subshell invocation.
    if command_exists "${editor%% *}"; then
      export EDITOR="${editor}"
      break
    fi
  done
  unset preferred_editors
fi

# For a full list of active aliases, run `alias`.

# setup paths in the beginning so that all other conditions work correctly
append_to_path_if_dir_exists "${PERSONAL_BIN_DIR}"
append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"
# Note: Not sure if its a bug, but the first iterm tab alone has all the paths, but these are missing in subsequent tabs and new windows
append_to_path_if_dir_exists '/usr/local/bin'
append_to_path_if_dir_exists "${HOME}/.rd/bin"
append_to_path_if_dir_exists "${HOME}/.cargo/bin"

# Note: can't defer this since the first time install fails
load_file_if_exists "${HOME}/.aliases"

# erlang history in iex
# export ERL_AFLAGS="-kernel shell_history enabled -kernel shell_history_file_bytes 1024000"

if is_macos; then
  # setopt always_to_end            # move cursor to end if word had one match
  # setopt auto_menu                # automatically use menu completion
  # setopt correct_all              # autocorrect commands
  # setopt glob_dots                # no special treatment for file names with a leading dot
  # setopt list_beep
  # setopt no_auto_menu             # require an extra TAB press to open the completion menu
  # setopt no_clobber               # Prevent overwriting existing files with '> filename', use '>| filename' (or >!) instead.

  setopt append_history           # append history list to the history file
  setopt auto_cd                  # cd into directory if the name is not an alias or function, but matches a directory
  setopt auto_list                # automatically list choices on an ambiguous completion.
  setopt auto_pushd               # make cd push the old directory onto the directory stack
  setopt beep                     # beep on error or on completion of long commands
  setopt extended_glob            # Enable zsh's extended glob abilities.
  setopt extended_history         # save each command's beginning timestamp and the duration to the history file
  setopt hist_allow_clobber
  setopt hist_expire_dups_first   # expire duplicates first
  setopt hist_find_no_dups        # ignore duplicates when searching
  setopt hist_ignore_all_dups     # do not put duplicated command into history list
  setopt hist_ignore_dups         # do not store duplications
  setopt hist_reduce_blanks       # remove unnecessary blanks
  setopt hist_save_no_dups        # do not save duplicated command
  setopt inc_append_history       # append command to history file immediately after execution
  setopt list_ambiguous
  setopt list_types               # if the file being listed is a directory, show a trailing slash
  setopt local_options
  setopt no_case_glob             # case-insensitive globbing
  setopt null_glob                # ignore errors when file globs don't match anything
  setopt pushd_ignore_dups        # don’t push multiple copies of the same directory
  setopt pushd_silent             # do not print the directory stack after pushd or popd
  setopt share_history            # share history between different instances of the shell

  # Note: 'autoload -Uz colors && colors' was removed — none of the active plugins
  # use $fg/$bg/$color from the colors function. Our own color vars ($BLUE, $RED, etc.)
  # are defined as $'\e[...' literals in .shellrc and don't depend on colors.

  # colorize completion
  # zstyle ':completion:*:*:kill:*:processes' list-colors "=(#b) #([0-9]#)*=$color[cyan]=$color[red]"
  # zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
  # zstyle ':completion:*' select-prompt '%SScrolling active: current selection at %p%s'
  # case insensitive path-completion
  zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*' 'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*'
  # partial completion suggestions
  zstyle ':completion:*' list-suffixeszstyle ':completion:*' expand prefix suffix
  # prevent CVS and SVN from being completed
  zstyle ':completion:*:(all-|)files' ignored-patterns '(|*/)CVS'
  zstyle ':completion:*:cd:*' ignored-patterns '(*/)#CVS'
  # ignore completion functions
  zstyle ':completion:*:functions' ignored-patterns '_*'
  # ignore what's already selected on line
  zstyle ':completion:*:(rm|kill|diff):*' ignore-line yes
  # hosts completion for some commands
  # local knownhosts
  # knownhosts=( ${${${${(f)"$(<${SSH_CONFIGS_DIR}/known_hosts)"}:#[0-9]*}%%\ *}%%,*} )
  # zstyle ':completion:*:(ssh|scp|sftp):*' hosts $knownhosts
  compctl -k hosts ftp lftp ncftp ssh w3m lynx links elinks nc telnet rlogin host
  compctl -k hosts -P '@' finger

  # manpage completion
  man_glob() {
    local a
    read -cA a
    if [[ $a[2] = -s ]]; then
      reply=( ${^manpath}/man$a[3]/${1}*${2}(N:t:r) )
    else
      reply=( ${^manpath}/man*/${1}*${2}(N:t:r) )
    fi
  }

  compctl -K man_glob -x 'C[-1,-P]' -m - 'R[-*l*,;]' -g '*.(man|[0-9nlpo](|[a-z]))' + -g '*(-/)' -- man
  # fuzzy matching
  zstyle ':completion:*' completer _complete _match _approximate
  zstyle ':completion:*:match:*' original only
  zstyle ':completion:*:approximate:*' max-errors 1 numeric
  # completion cache
  zstyle ':completion:*' use-cache on
  zstyle ':completion:*' cache-path "${XDG_CACHE_HOME}/zsh"
  # remove trailing slash in directory names, useful for ln
  zstyle ':completion:*' squeeze-slashes true
  # docker completion
  zstyle ':completion:*:*:docker:*' option-stacking yes
  zstyle ':completion:*:*:docker-*:*' option-stacking yes

  autoload -Uz _git

  # Turn on autocomplete predictions
  autoload -Uz incremental-complete-word predict-on
  zle -N incremental-complete-word
  zle -N predict-on
  zle -N predict-off
  bindkey '^Xi' incremental-complete-word
  bindkey '^Xp' predict-on
  bindkey '^X^P' predict-off

  if command_exists brew; then
    prepend_to_path_if_dir_exists "${HOMEBREW_PREFIX}/bin"
    prepend_to_path_if_dir_exists "${HOMEBREW_PREFIX}/sbin"
    prepend_to_manpath_if_dir_exists "${HOMEBREW_PREFIX}/share/man"

    use_homebrew_installation_for() {
      installation_dir="${HOMEBREW_PREFIX}/opt/${1}"
      ! is_directory "${installation_dir}" && return 0 # Success, nothing to do

      prepend_to_path_if_dir_exists "${installation_dir}/bin"
      prepend_to_path_if_dir_exists "${installation_dir}/libexec/bin"
      prepend_to_path_if_dir_exists "${installation_dir}/libexec/gnubin"
      # For compilers to find this installation you may need to set:
      prepend_to_ldflags_if_dir_exists "${installation_dir}/lib"
      prepend_to_cppflags_if_dir_exists "${installation_dir}/include"
      # For pkg-config to find this installation you may need to set:
      prepend_to_pkg_config_path_if_dir_exists "${installation_dir}/lib/pkgconfig"
      prepend_to_manpath_if_dir_exists "${installation_dir}/libexec/gnuman"
    }

    # Note: These are the tools that are brought in from Homebrew but are "keg-only" and should override the default ones that come with macOS.
    for pkg in 'curl' 'gnu-tar' 'grep' 'sqlite' 'zlib' ; do
      use_homebrew_installation_for "${pkg}"
    done

    # override default openssl and use from homebrew installation
    if is_directory "${HOMEBREW_PREFIX}/opt/openssl@3"; then
      use_homebrew_installation_for 'openssl@3'
      export RUBY_CONFIGURE_OPTS="--with-openssl-dir=${HOMEBREW_PREFIX}/opt/openssl@3"
    fi
  fi
fi

# Make VSCodium use the VS Code marketplace
if command_exists codium; then
  export VSCODE_GALLERY_SERVICE_URL='https://marketplace.visualstudio.com/_apis/public/gallery'
  export VSCODE_GALLERY_CACHE_URL='https://vscode.blob.core.windows.net/gallery/index'
  export VSCODE_GALLERY_ITEM_URL='https://marketplace.visualstudio.com/items'
  export VSCODE_GALLERY_CONTROL_URL=''
  export VSCODE_GALLERY_RECOMMENDATIONS_URL=''
fi

# Use bat to colorize man pages
command_exists bat && export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# defines word-boundaries: ensures that deleting word on /path/to/file deletes only 'file' and not the directory, this removes the '/' from $WORDCHARS
export WORDCHARS="${WORDCHARS:s#/#}"
export WORDCHARS="${WORDCHARS:s#.#}"

# Enable LSP Tools (used for clause-code)
# export ENABLE_LSP_TOOLS=1

# rspec and cucumber
# export CUCUMBER_COLORS="pending_param=magenta:failed_param=magenta:passed_param=magenta:skipped_param=magenta"
# export RSPEC="true"

# fzy
# load_file_if_exists "${HOME}/.fzy-key-bindings.zsh"

if is_directory "${XDG_CONFIG_HOME}/zsh"; then
  # register folder for custom zsh functions to be lazy-loaded
  append_to_fpath_if_dir_exists "${XDG_CONFIG_HOME}/zsh"

  # Dynamically autoload all files in the custom zsh functions directory.
  # Assumes the filename is the function name.
  # :t extracts the basename — autoload expects the function name, not the full
  # path; passing the full path would define a function named e.g.
  # '~/.config/zsh/myfunc' which can never be invoked by short name.
  local func_file
  for func_file in "${XDG_CONFIG_HOME}"/zsh/*(N); do
    autoload -Uz "${func_file:t}"
  done
  unset func_file
fi

# Mole shell completion
# TODO: Disabled since it causes a significant slowdown in shell startup time. Need to investigate if this can be optimized by caching the completion results or some other way.
# if command_exists mole; then
#   eval_shellenv mole completion zsh
# fi

# remove empty components to avoid '::' ending up + resulting in './' being in $PATH, etc
path=( "${path[@]:#}" )
fpath=( "${fpath[@]:#}" )
infopath=( "${infopath[@]:#}" )
manpath=( "${manpath[@]:#}" )

# remove duplicates from some env vars
typeset -gU cdpath CPPFLAGS cppflags FPATH fpath infopath LDFLAGS ldflags MANPATH manpath PATH path PKG_CONFIG_PATH

# fpath/FPATH and cdpath/CDPATH must NOT be exported — both are zsh-internal variables
# (autoload search path and cd search path respectively). Exporting them causes their
# contents to leak into child processes and persist in the macOS launchd user-session
# environment, where they are inherited by every new shell before any rc file runs.
# All other *path vars on line 367 (PATH, MANPATH, INFOPATH, CPPFLAGS, LDFLAGS,
# PKG_CONFIG_PATH) are intentionally exported — child processes need them.
typeset +x FPATH fpath cdpath CDPATH

# for profiling zsh, see: https://unix.stackexchange.com/a/329719/27109
# execute 'ZSH_PROFILE_RC=true zsh' and run 'zprof' to get the details
[[ -n "${ZSH_PROFILE_RC+1}" ]] && zprof
