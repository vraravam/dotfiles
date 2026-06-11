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
[[ -n "${DEBUG:-}" ]] && echo "loading ${0}"

# for profiling zsh, see: https://unix.stackexchange.com/a/329719/27109
# execute 'ZSH_PROFILE=true zsh -i -c exit' and run 'zprof' to get the details
[[ -n "${ZSH_PROFILE:-}" ]] && zmodload zsh/zprof

# Re-source guard is inside .shellrc itself -- safe to call unconditionally.
source "${HOME}/.shellrc"

# ──────────────────────────────────────────────────────────────────────────────
# Antidote -- static plugin bundle
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

# Plugin option variables must be set before the bundle is sourced.
# Pre-set iterm2_hostname to zsh's native $HOST (set from uname -n at shell init -- no subprocess).
# The iterm2 shell integration checks [ -z "${iterm2_hostname:-}" ] and forks `hostname -f` if unset.
# $HOST equals `hostname -f` on macOS and avoids the ~4ms subprocess cost on every shell start.
iterm2_hostname="${HOST}"

# zsh-autosuggestions -- all options must be set before the antidote bundle is
# sourced; the plugin reads them at load time.
#
# USE_ASYNC: fetch suggestions in a background zpty process so ZLE never blocks
# while waiting for a history/completion lookup -- directly reduces first-keystroke
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
# matching cost on large history files -- long entries (URLs, one-liners) are
# almost never the intended suggestion target.
#
# STRATEGY=(history): use only the history strategy. The 'completion' strategy
# spawns a zpty (pseudoterminal) on every suggestion request -- ~10-30ms overhead
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

# Ensure XDG_CACHE_HOME exists before any cache writes below.  When delete_caches removes ~/.cache,
# the subsequent cache-write redirections (>|) silently fail and leave caches empty -- breaking fpath
# updates and other lazy-loaded config that only runs through the cache file.
ensure_dir_exists "${XDG_CACHE_HOME}"

# Cache architecture detection to avoid uname -m fork on every shell startup.
# The cache is invalidated when the kernel version changes (e.g. macOS upgrade).
# Caching saves ~2-3ms per shell startup -- minor per-shell but accumulates over
# 50-100 shells per day.
() {
  setopt localoptions NULL_GLOB
  local arch_cache="${XDG_CACHE_HOME}/arch-cache.zsh"
  local kernel_version kern_cache_ver

  # Get current kernel version (still a fork, but only on cache miss)
  kernel_version="$(uname -r)"

  # If cache exists, source it and extract cached kernel version
  if is_file "${arch_cache}"; then
    source "${arch_cache}"
    kern_cache_ver="$(sed -n 's/^# kernel: //p' "${arch_cache}" 2>/dev/null)"
  fi

  # Regenerate cache if missing or kernel version changed
  if ! is_file "${arch_cache}" || [[ "${kern_cache_ver}" != "${kernel_version}" ]]; then
    {
      echo "export ARCH='$(uname -m)'"
      echo "# kernel: ${kernel_version}"
    } >|"${arch_cache}"
    source "${arch_cache}"
  fi
}

# Cache brew shellenv to avoid running the brew binary on every shell startup (it's slow due to Ruby startup).
# The cache is invalidated when the brew binary itself changes (i.e. after brew upgrades).
# The cache pre-evaluates path_helper so sourcing it is a pure-zsh operation (no subprocesses).
# Anonymous function scopes variables to avoid polluting global namespace; this is a pure zsh
# file (never bash-sourced), so () syntax is idiomatic and correct here.
() {
  local brew_bin="${HOMEBREW_PREFIX}/bin/brew"
  local brew_shellenv_cache="${XDG_CACHE_HOME}/brew-shellenv-cache.zsh"
  # Use the brew binary's modification time as cache key (no need to run brew at all for the check)
  if is_file_older_than "${brew_shellenv_cache}" "${brew_bin}"; then
    # Skip cache generation if brew is not yet installed (e.g. vanilla OS first-install)
    if ! is_executable "${brew_bin}"; then
      load_file_if_exists "${brew_shellenv_cache}"
      return
    fi
    # Run brew shellenv in a subshell to get brew vars + path_helper result without polluting current PATH
    local brew_cellar brew_repo brew_infopath brew_manpath brew_prefix
    eval "$("${brew_bin}" shellenv 2>/dev/null)"
    brew_prefix="${HOMEBREW_PREFIX}"
    brew_cellar="${HOMEBREW_CELLAR:-}"
    brew_repo="${HOMEBREW_REPOSITORY:-}"
    brew_infopath="${INFOPATH:-}"
    brew_manpath="${MANPATH:-}"
    # Write a static cache: static exports + fpath update (no subprocess calls when cache is sourced)
    {
      echo "export HOMEBREW_PREFIX='${brew_prefix}';"
      echo "export HOMEBREW_CELLAR='${brew_cellar}';"
      echo "export HOMEBREW_REPOSITORY='${brew_repo}';"
      echo "export INFOPATH='${brew_infopath}';"
      echo "export MANPATH='${brew_manpath}';"
      # fpath assignment is sufficient -- zsh keeps fpath and FPATH in sync automatically.
      # Exporting FPATH leaks it into child processes and launchd user-session environment;
      # typeset +x at the bottom of this file strips the export flag after all sources.
      echo "fpath=('${brew_prefix}/share/zsh/site-functions' \"\${fpath[@]}\");"
    } >|"${brew_shellenv_cache}" 2>/dev/null
  fi
  load_file_if_exists "${brew_shellenv_cache}"
}

load_file_if_exists "${HOMEBREW_PREFIX}/opt/git-extras/share/git-extras/git-extras-completion.zsh"

# compinit is deferred to after the antidote bundle and .aliases load (see
# _deferred_compinit below). Deferring achieves two things:
#   1. Saves ~10ms from time-to-first-prompt (compinit runs after the first
#      ZLE idle event, before any keypress -- invisible to the user).
#   2. Fixes a fpath ordering bug: the antidote bundle adds zsh-completions/src
#      and plugin fpath entries AFTER this point. Running compinit here means
#      those entries are absent from both the staleness check and the dump,
#      so zsh-completions functions are never registered.
#
# Plugins loaded synchronously or via zsh-defer may call compdef before
# compinit defines the real one. The stub below captures those calls in
# _compdef_queue; _deferred_compinit replays them after compinit runs.
export ZSH_COMPDUMP="${XDG_CACHE_HOME}/zcompdump"
typeset -ga _compdef_queue=()
compdef() { _compdef_queue+=("$*"); }

# Pre-set git_version to skip the `git version` subprocess fork inside the OMZ git plugin.
# git.plugin.zsh line 3 runs: git_version="${${(As: :)$(git version 2>/dev/null)}[3]}"
# and uses it for 4 conditional alias decisions (thresholds 2.8, 2.13, 2.30).
# Since git is always well above those thresholds on this machine, we cache the version
# string keyed on the git binary mtime -- the same mtime-invalidation pattern used for
# brew shellenv, mise activate, and starship init. Saves ~14ms on every shell startup.
# (($+commands[git])) is a single O(1) hash probe; command_exists does 4.
# .zshrc is zsh-only so the zsh arithmetic syntax is always safe here.
if (($+commands[git])); then
  # Anonymous function scopes git version cache locals; pure zsh file, () is idiomatic here.
  () {
    local git_bin="${commands[git]}"
    local git_version_cache="${XDG_CACHE_HOME}/git-version-cache.zsh"
    if is_file_older_than "${git_version_cache}" "${git_bin}"; then
      local ver="${${(As: :)$(git version 2>/dev/null)}[3]}"
      echo "git_version=\"${ver}\"" >|"${git_version_cache}" 2>/dev/null
    fi
    load_file_if_exists "${git_version_cache}"
  }
fi

# Warn if plugins.txt is newer than the generated bundle -- a reminder to run
# update_antidote_and_regenerate_plugin_bundle. Uses zsh's -nt (newer-than)
# file test: pure built-in, no subprocess fork. Only fires when the user has
# edited plugins.txt and not yet regenerated; silent on every normal startup.
is_file_older_than "${ANTIDOTE_PLUGIN_ZSH}" "${ANTIDOTE_PLUGIN_TXT}" &&
  warn "antidote: '$(yellow "${ANTIDOTE_PLUGIN_TXT}")' is newer than the bundle -- run '$(cyan 'update_antidote_and_regenerate_plugin_bundle')' manually to regenerate it."

# Source the pre-generated antidote static bundle.
# On a vanilla OS (before brew installs antidote) this file is present because
# it is checked into the home repo. No antidote binary is needed during the
# shell startup.
#
# Some bundled plugins (e.g. OMZ eza) reference bare positional parameters like
# $3 without a default, which crashes under NOUNSET (set -u). The fresh-install
# script runs with `set -euo pipefail`, so NOUNSET is active when load_zsh_configs
# sources this file. Suspend NOUNSET for the duration of the bundle source only.
# Anonymous function scopes the LOCAL_OPTIONS change; this is a pure zsh file
# (never bash-sourced), so () syntax is idiomatic and correct here.
() {
  setopt LOCAL_OPTIONS
  unsetopt NOUNSET
  load_file_if_exists "${ANTIDOTE_PLUGIN_ZSH}"
}

# Activate mise -- the OMZ mise plugin referenced $ZSH_CACHE_DIR (undefined without OMZ)
# so it has been removed from $ANTIDOTE_PLUGIN_TXT and replaced with a direct activation here.
#
# Performance optimisation -- cache `mise activate zsh` output to avoid forking the mise
# binary on every shell start (~5-10ms saving). Same pattern as the starship init cache
# below. The cache is keyed on the mise binary mtime and regenerated only when mise itself
# is updated (e.g. after `brew upgrade`).
if (($+commands[mise])); then
  # Anonymous function scopes cache-related locals; pure zsh file, () is idiomatic here.
  () {
    local mise_bin="${commands[mise]}"
    local mise_activate_cache="${XDG_CACHE_HOME}/mise-activate-cache.zsh"
    if is_file_older_than "${mise_activate_cache}" "${mise_bin}"; then
      # Generate the activation cache, but replace the bare '_mise_hook' call at the end
      # (which forks the mise binary once at startup to seed the environment) with a
      # deferred version via zsh-defer. zsh-defer fires after the first idle ZLE event --
      # before any command can be typed -- so tools are active before the first keypress
      # while saving ~25ms from time-to-first-prompt. Falls back to a synchronous call
      # when zsh-defer is not available (e.g. a vanilla OS before antidote is installed).
      # grep -v filters only the bare '_mise_hook' line; the function definition
      # (_mise_hook() { ... }) and indented references are multi-line/indented and do not match.
      {
        mise activate zsh 2>/dev/null | \grep -v '^_mise_hook$'
        printf '%s\n' 'if (( $+functions[zsh-defer] )); then zsh-defer _mise_hook; else _mise_hook; fi'
      } >|"${mise_activate_cache}"
    fi
    load_file_if_exists "${mise_activate_cache}"
  }
fi

# Initialize starship prompt (must be after plugins so it wins the PROMPT setup).
#
# Performance optimisation -- cache `starship init zsh` output to avoid forking a
# subprocess on every shell start (~10-15ms saving).  The cache is keyed on the
# starship binary mtime and regenerated only when starship itself is updated
# (e.g. after `brew upgrade`).
#
# NOTE: Deferring the source of the cache (via zsh-defer or a precmd hook) was
# attempted but left PROMPT as a literal unexpanded string after the first
# command. Starship's init output registers precmd hooks and sets promptsubst --
# both require file-scope application to interact correctly with zsh's startup
# sequence. The cache is therefore sourced directly at the top level; the ~5ms
# cost of sourcing the pre-parsed .zwc bytecode is acceptable.
if (($+commands[starship])); then
  # Anonymous function scopes starship cache locals; pure zsh file, () is idiomatic here.
  () {
    # $commands[] is an O(1) zsh hash lookup - no subprocess fork needed.
    local starship_bin="${commands[starship]}"
    local starship_init_cache="${XDG_CACHE_HOME}/starship-init-cache.zsh"
    # Regenerate the cache only when the starship binary is newer than the cache file.
    if is_file_older_than "${starship_init_cache}" "${starship_bin}"; then
      # Strip the eager PROMPT2="$(...)" line that starship emits (double-quoted, forks
      # the binary at source time, ~9-15ms). Replace it with a lazy single-quoted form
      # so the fork only happens when the continuation prompt is actually displayed.
      # PROMPT and RPROMPT are already lazy in starship's output; PROMPT2 is the only
      # outlier. The single-quoted form uses the same pattern as PROMPT/RPROMPT.
      starship init zsh 2>/dev/null | \grep -v '^PROMPT2=' >|"${starship_init_cache}"
      printf "PROMPT2='\$(%s prompt --continuation)'\n" "${starship_bin}" >>"${starship_init_cache}"
    fi
    # Source directly at the top level (not deferred) so that 'setopt promptsubst'
    # emitted by the cache takes effect globally and is not scoped to a function.
    load_file_if_exists "${starship_init_cache}"
  }
fi

# User configuration
# export MANPATH="/usr/local/man${MANPATH+:$MANPATH}"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

unset GIT_EDITOR
# SSH sessions fall back to vi; local sessions prefer GUI editors.
# EDITOR always delegates to wait-editor, which re-execs $GIT_EDITOR via POSIX
# word-splitting -- so '--wait' flags are passed correctly to GUI editors, and
# vi (which blocks naturally) works without any special casing.
if is_non_zero_string "${SSH_CONNECTION:-}"; then
  preferred_editors=('vi')
else
  preferred_editors=('zed --wait' 'code --wait' 'vi')
fi
for editor in "${preferred_editors[@]}"; do
  # ${editor%% *} strips everything after the first space -- pure zsh, no fork.
  # (($+commands[...])) is a single O(1) hash probe; command_exists does 4.
  # Safe here: .zshrc is zsh-only; all three candidates (zed, code, vi) are
  # external binaries -- $+commands is the right table to probe.
  if (($+commands[${editor%% *}])); then
    export GIT_EDITOR="${editor}"
    break
  fi
done
unset preferred_editors editor
# Safety net: if no editor was found in PATH (e.g. a stripped environment
# where even vi is absent), fall back to vi unconditionally so GIT_EDITOR is
# never left unset. wait-editor will fail clearly if vi is truly missing.
if is_zero_string "${GIT_EDITOR:-}"; then
  export GIT_EDITOR='vi'
fi
# EDITOR is always the wait-editor wrapper regardless of which editor was
# selected -- set once here rather than repeating it in every branch above.
export EDITOR='wait-editor'

# For a full list of active aliases, run `alias`.

# setup paths in the beginning so that all other conditions work correctly
append_to_path_if_dir_exists "${PERSONAL_BIN_DIR}"
append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"
# Note: Not sure if its a bug, but the first iterm tab alone has all the paths, but these are missing in subsequent tabs and new windows
append_to_path_if_dir_exists '/usr/local/bin'
append_to_path_if_dir_exists "${HOME}/.rd/bin"
append_to_path_if_dir_exists "${HOME}/.cargo/bin"

# Defer .aliases (963 lines of function/alias definitions -- no ZLE hooks or setopts)
# to after the first idle ZLE event. zsh-defer fires before any keypress, so all
# aliases are available before the user can type. The same reasoning applies here
# as for the deferred git plugin (431 lines), which was already the largest single
# startup win. Falls back to synchronous load when zsh-defer is not available
# (e.g. vanilla OS before antidote is installed).
# Caveat: autoload functions in ${XDG_CONFIG_HOME}/zsh/ call dispatch_or_fallback
# (defined in .aliases). In practice zsh-defer fires well before any keypress;
# the risk only exists for scripted terminals that send input before ZLE is idle.
if (($+functions[zsh-defer])); then
  zsh-defer load_file_if_exists "${HOME}/.aliases"
else
  load_file_if_exists "${HOME}/.aliases"
fi

# Run compinit after all plugins and .aliases have loaded so the fpath staleness
# check sees the full fpath (including zsh-completions/src and plugin dirs added
# by the antidote bundle above). Removes the compdef stub, runs real compinit,
# then replays any compdef calls captured by the stub during plugin loading.
# Named function required (not anonymous ()) -- zsh-defer needs a function name.
# Unfunctioned at the end to avoid polluting the global function table.
_deferred_compinit() {
  # Remove stub; compinit will define the real compdef.
  unfunction compdef 2>/dev/null
  autoload -Uz compinit
  local stale=0 dir
  if ! is_file "${ZSH_COMPDUMP}"; then
    stale=1
  else
    # fpath now includes bundle entries -- staleness check is accurate.
    for dir in "${fpath[@]}"; do
      if [[ -d "${dir}" && "${dir}" -nt "${ZSH_COMPDUMP}" ]]; then
        stale=1
        break
      fi
    done
  fi
  if ((stale)); then
    compinit -d "${ZSH_COMPDUMP}"
  else
    compinit -C -d "${ZSH_COMPDUMP}"
  fi
  # Replay compdef calls captured by the stub (e.g. from the deferred git plugin).
  # ${(z)call} splits the stored string back into words respecting shell quoting.
  local _call
  for _call in "${_compdef_queue[@]}"; do
    compdef ${(z)_call}
  done
  unset _compdef_queue
  # Re-bind zsh-autosuggestions after compinit redefines completion widgets.
  # compinit calls 'zle -C complete-word ...' (and similar) which replaces the
  # ZLE widget wrappers that autosuggestions installed during its first precmd.
  # With ZSH_AUTOSUGGEST_MANUAL_REBIND=1, autosuggestions never re-wraps on
  # subsequent precmds -- calling bind_widgets here restores the wrapping so
  # that the suggestion region_highlight runs after fast-syntax-highlighting
  # and ghost text appears in the correct dim colour, not FSH's syntax colour.
  if (($+functions[_zsh_autosuggest_bind_widgets])); then
    _zsh_autosuggest_bind_widgets
  fi
  unfunction _deferred_compinit
}
if (($+functions[zsh-defer])); then
  zsh-defer _deferred_compinit
else
  _deferred_compinit
fi

# erlang history in iex
# export ERL_AFLAGS="-kernel shell_history enabled -kernel shell_history_file_bytes 1024000"

# setopt always_to_end            # move cursor to end if word had one match
# setopt auto_menu                # automatically use menu completion
# setopt correct_all              # autocorrect commands
# setopt glob_dots                # no special treatment for file names with a leading dot
# setopt list_beep
# setopt no_auto_menu             # require an extra TAB press to open the completion menu
# setopt no_clobber               # Prevent overwriting existing files with '> filename', use '>| filename' (or >!) instead.

setopt append_history   # append history list to the history file
# Set HISTSIZE and SAVEHIST symmetrically. Without explicit values zsh uses its
# built-in defaults (HISTSIZE=50000, SAVEHIST=10000). The asymmetry silently
# truncates the in-memory list when replaying a large history file -- the extra
# entries are read from disk then immediately discarded. Matching values prevent
# this; 50000 covers several years of typical usage without noticeable memory cost.
export HISTSIZE=50000
export SAVEHIST=50000
setopt auto_cd          # cd into directory if the name is not an alias or function, but matches a directory
setopt auto_list        # automatically list choices on an ambiguous completion.
setopt auto_pushd       # make cd push the old directory onto the directory stack
setopt beep             # beep on error or on completion of long commands
setopt extended_glob    # Enable zsh's extended glob abilities.
setopt extended_history # save each command's beginning timestamp and the duration to the history file
setopt hist_allow_clobber
setopt hist_expire_dups_first # expire duplicates first
setopt hist_find_no_dups      # ignore duplicates when searching
setopt hist_ignore_all_dups   # do not put duplicated command into history list
setopt hist_ignore_dups       # do not store duplications
setopt hist_reduce_blanks     # remove unnecessary blanks
setopt hist_save_no_dups      # do not save duplicated command
# inc_append_history is intentionally omitted: share_history (below) implies it.
# Setting both is redundant and the zsh manual states share_history subsumes
# inc_append_history -- keep only the stronger option.
setopt list_ambiguous
setopt list_types             # if the file being listed is a directory, show a trailing slash
setopt local_options
setopt no_case_glob           # case-insensitive globbing
# null_glob is disabled: it causes commands that behave differently with zero
# arguments (ls, rm, grep) to silently receive no args instead of a clear
# "no matches found" error. Use the (N) per-glob qualifier where nullglob
# behaviour is genuinely needed (e.g. rm -f *.bak(N)).
# setopt null_glob
setopt pushd_ignore_dups # don’t push multiple copies of the same directory
setopt pushd_silent      # do not print the directory stack after pushd or popd
setopt share_history     # share history between different instances of the shell

# Note: 'autoload -Uz colors && colors' was removed -- none of the active plugins
# use $fg/$bg/$color from the colors function. Our own color vars ($BLUE, $RED, etc.)
# are defined as $'\e[...' literals in .shellrc and don't depend on colors.

# colorize completion
# zstyle ':completion:*:*:kill:*:processes' list-colors "=(#b) #([0-9]#)*=$color[cyan]=$color[red]"
# zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
# zstyle ':completion:*' select-prompt '%SScrolling active: current selection at %p%s'
# case insensitive path-completion -- 2-tier matcher list:
#   tier 1: case-insensitive exact match
#   tier 2: case-insensitive with left/right anchored prefix matching
# The original 4-tier list had tiers 2-4 all identical (l:|=* r:|=*), adding
# cost without benefit when neither tier 1 nor tier 2 matches. 2 distinct tiers
# cover all practical cases; extra tiers only fire when both fail (rare).
zstyle ':completion:*' matcher-list \
  'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' \
  'm:{[:lower:][:upper:]}={[:upper:][:lower:]} l:|=* r:|=*'
# partial completion suggestions
zstyle ':completion:*' list-suffixes
zstyle ':completion:*' expand prefix suffix
# prevent CVS and SVN from being completed
zstyle ':completion:*:(all-|)files' ignored-patterns '(|*/)CVS'
zstyle ':completion:*:cd:*' ignored-patterns '(*/)#CVS'
# ignore completion functions
zstyle ':completion:*:functions' ignored-patterns '_*'
# ignore what's already selected on line
zstyle ':completion:*:(rm|kill|diff):*' ignore-line yes
# hosts completion for some commands
# local knownhosts
# knownhosts=( ${${${${(f)"$(<${HOME}/.ssh/known_hosts)"}:#[0-9]*}%%\ *}%%,*} )
# zstyle ':completion:*:(ssh|scp|sftp):*' hosts $knownhosts
#
# compctl (old pre-compsys completion system) calls were removed:
#   compctl -k hosts ftp lftp ncftp ssh ...  -- $hosts array was never defined (see above);
#   compctl -K man_glob ... -- man           -- custom man_glob function
# These conflicted silently with the compsys (_ssh, _man) completers loaded via
# zsh-completions. compsys takes full ownership of all completions.
# fuzzy matching
zstyle ':completion:*' completer _complete _match _approximate
zstyle ':completion:*:match:*' original only
zstyle ':completion:*:approximate:*' max-errors 1 numeric
# Short-circuit the full matcher-list evaluation when Tab is pressed on a string
# that exactly matches one candidate -- avoids walking all tiers unnecessarily.
zstyle ':completion:*' accept-exact '(N)'
# completion cache
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME}/zsh"
# remove trailing slash in directory names, useful for ln
zstyle ':completion:*' squeeze-slashes true
# docker completion
zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes

autoload -Uz _git

# Option+arrow word navigation for Terminal.app. Terminal.app's "Use Option as Meta key" covers
# Option+B/F but arrow keys still send \033[1;9D/C -- map them explicitly to ZLE word motion.
# In iTerm2 the Natural Text Editing preset remaps these at the terminal level to \033b/\033f,
# so zsh never receives \033[1;9D/C from iTerm2 -- these bindings are safely inert there.
bindkey '\033[1;9D' backward-word
bindkey '\033[1;9C' forward-word

# predict-on (Ctrl+Xp) and incremental-complete-word (Ctrl+Xi) are disabled.
# predict-on: aggressively fills the command line from history on every keystroke
# when toggled on -- overlaps with zsh-autosuggestions which already does this
# non-destructively via ghost text with no toggle required.
# incremental-complete-word (Ctrl+Xi): narrows completions in real time as you type;
# superseded by fzf-based tab completion. Neither adds startup overhead, but
# predict-on adds per-keystroke cost whenever active.
# autoload -Uz incremental-complete-word predict-on
# zle -N incremental-complete-word
# zle -N predict-on
# zle -N predict-off
# bindkey '^Xi' incremental-complete-word
# bindkey '^Xp' predict-on
# bindkey '^X^P' predict-off

if (($+commands[brew])); then
  # Cache Homebrew bin/sbin and keg-only PATH/LDFLAGS/CPPFLAGS/PKG_CONFIG_PATH/MANPATH
  # to avoid ~42 stat syscalls per interactive startup. Keyed on the mtime of
  # ${HOMEBREW_PREFIX}/opt/ -- which changes on every brew install/remove -- so new
  # keg-only installs are automatically reflected on the next shell start.
  #
  # All entries are built directly from the filesystem -- never derived from the current
  # environment. This makes regeneration idempotent: running inside a shell that already
  # has keg-only vars set (e.g. OpenCode inheriting the user's PATH) produces the same
  # cache as running in a clean shell. The snapshot-and-delta approach this replaced was
  # broken: a pre-populated PATH caused an empty delta (keg-only bins missing from cache)
  # and inherited LDFLAGS caused doubled flags.
  #
  # Safe in all contexts: (($+commands[brew])) is zsh-only, but .zshrc is never
  # sourced by bash. On vanilla OS, this runs during fresh-install after brew is
  # installed -- the guard passes and keg-only paths are cached normally.
  # Anonymous function scopes keg-only path computation locals; pure zsh file, () is idiomatic here.
  () {
    local keg_cache="${XDG_CACHE_HOME}/keg-only-paths-cache.zsh"
    local opt_dir="${HOMEBREW_PREFIX}/opt"

    # Cache hit: source pre-computed static exports -- zero stat calls.
    # Inverted logic: is_file_older_than returns true when regeneration needed, so negate it.
    if ! is_file_older_than "${keg_cache}" "${opt_dir}"; then
      load_file_if_exists "${keg_cache}"
      return
    fi

    # Cache absent or stale: enumerate each keg-only package's directories directly.
    # keg_paths/keg_manpath are built with prepend semantics so the last-processed
    # package's entries appear first (highest PATH priority). Within each package,
    # gnubin is prepended last so it wins over libexec/bin which wins over bin.
    # ldflags_new/cppflags_new/pkgconfig_new accumulate only keg-only contributions
    # (not inherited environment values) -- the keg-only block is their sole setter
    # during startup, so these can be safely overwritten in the cache.
    local -a keg_paths=()
    local -a keg_manpath=()
    local ldflags_new=''
    local cppflags_new=''
    local pkgconfig_new=''

    # Named function required -- anonymous () cannot be called repeatedly in a loop.
    # Unfunctioned immediately after use to prevent global namespace pollution
    # (named functions defined inside () persist in the global table after return).
    _keg_collect() {
      local d="${HOMEBREW_PREFIX}/opt/${1}"
      if ! is_directory "${d}"; then return 0; fi
      if is_directory "${d}/bin"; then keg_paths=("${d}/bin" "${keg_paths[@]}"); fi
      if is_directory "${d}/libexec/bin"; then keg_paths=("${d}/libexec/bin" "${keg_paths[@]}"); fi
      if is_directory "${d}/libexec/gnubin"; then keg_paths=("${d}/libexec/gnubin" "${keg_paths[@]}"); fi
      if is_directory "${d}/libexec/gnuman"; then keg_manpath=("${d}/libexec/gnuman" "${keg_manpath[@]}"); fi
      if is_directory "${d}/lib"; then ldflags_new="-L${d}/lib${ldflags_new:+ ${ldflags_new}}"; fi
      if is_directory "${d}/include"; then cppflags_new="-I${d}/include${cppflags_new:+ ${cppflags_new}}"; fi
      if is_directory "${d}/lib/pkgconfig"; then pkgconfig_new="${d}/lib/pkgconfig${pkgconfig_new:+:${pkgconfig_new}}"; fi
    }
    local pkg
    for pkg in 'curl' 'gnu-tar' 'grep' 'sqlite' 'zlib'; do
      _keg_collect "${pkg}"
    done
    if is_directory "${HOMEBREW_PREFIX}/opt/openssl@3"; then
      _keg_collect 'openssl@3'
      export RUBY_CONFIGURE_OPTS="--with-openssl-dir=${HOMEBREW_PREFIX}/opt/openssl@3"
    fi
    unfunction _keg_collect

    # Homebrew base bin/sbin appended after keg-only entries so keg-only tools take
    # priority. sbin is placed before bin to match the original prepend sequence
    # (bin prepended first, sbin prepended second → sbin ends up in front of bin).
    # /etc/paths.d/homebrew pre-populates /opt/homebrew/bin at a low priority position;
    # it is re-added here at the front. typeset -gU path at the bottom removes the dup.
    # Desired order: mise (_mise_hook via zsh-defer) > keg-only > homebrew base > system.
    local -a hb_base=()
    if is_directory "${HOMEBREW_PREFIX}/bin"; then hb_base+=("${HOMEBREW_PREFIX}/bin"); fi
    if is_directory "${HOMEBREW_PREFIX}/sbin"; then hb_base=("${HOMEBREW_PREFIX}/sbin" "${hb_base[@]}"); fi

    # homebrew share/man after keg-only gnuman entries.
    if is_directory "${HOMEBREW_PREFIX}/share/man"; then keg_manpath+=("${HOMEBREW_PREFIX}/share/man"); fi

    local -a all_path_entries=("${keg_paths[@]}" "${hb_base[@]}")

    # Apply to the current session.
    if is_non_empty_array all_path_entries; then path=("${all_path_entries[@]}" "${path[@]}"); fi
    if is_non_empty_array keg_manpath; then manpath=("${keg_manpath[@]}" "${manpath[@]}"); fi
    if is_non_zero_string "${ldflags_new}"; then export LDFLAGS="${ldflags_new}"; fi
    if is_non_zero_string "${cppflags_new}"; then export CPPFLAGS="${cppflags_new}"; fi
    if is_non_zero_string "${pkgconfig_new}"; then export PKG_CONFIG_PATH="${pkgconfig_new}"; fi

    # Write static cache. Path/manpath entries are quoted for safe embedding.
    # LDFLAGS/CPPFLAGS/PKG_CONFIG_PATH are written as plain overwrites (no
    # ${LDFLAGS} expansion) -- they contain only keg-only contributions and are
    # safe to overwrite because nothing else in the startup sequence sets them.
    {
      local -a qpaths=() qmanpath=()
      local entry
      for entry in "${all_path_entries[@]}"; do qpaths+=("${(q)entry}"); done
      for entry in "${keg_manpath[@]}"; do qmanpath+=("${(q)entry}"); done
      if is_non_empty_array qpaths; then
        printf 'path=(%s "${path[@]}")\n' "${qpaths[*]}"
      fi
      if is_non_empty_array qmanpath; then
        printf 'manpath=(%s "${manpath[@]}")\n' "${qmanpath[*]}"
      fi
      if is_non_zero_string "${ldflags_new}"; then
        printf 'export LDFLAGS=%s\n' "${(q)ldflags_new}"
      fi
      if is_non_zero_string "${cppflags_new}"; then
        printf 'export CPPFLAGS=%s\n' "${(q)cppflags_new}"
      fi
      if is_non_zero_string "${pkgconfig_new}"; then
        printf 'export PKG_CONFIG_PATH=%s\n' "${(q)pkgconfig_new}"
      fi
      if is_non_zero_string "${RUBY_CONFIGURE_OPTS:-}"; then
        printf 'export RUBY_CONFIGURE_OPTS=%s\n' "${(q)RUBY_CONFIGURE_OPTS}"
      fi
    } >|"${keg_cache}" 2>/dev/null
  }
fi

# Make VSCodium use the VS Code marketplace
if (($+commands[codium])); then
  export VSCODE_GALLERY_SERVICE_URL='https://marketplace.visualstudio.com/_apis/public/gallery'
  export VSCODE_GALLERY_CACHE_URL='https://vscode.blob.core.windows.net/gallery/index'
  export VSCODE_GALLERY_ITEM_URL='https://marketplace.visualstudio.com/items'
  export VSCODE_GALLERY_CONTROL_URL=''
  export VSCODE_GALLERY_RECOMMENDATIONS_URL=''
fi

# Use bat to colorize man pages
if (($+commands[bat])); then
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

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
  # :t extracts the basename -- autoload expects the function name, not the full
  # path; passing the full path would define a function named e.g.
  # '~/.config/zsh/myfunc' which can never be invoked by short name.
  # Anonymous function scopes NULL_GLOB (no error when directory is empty) and
  # keeps func_file local -- no unset needed after the loop.
  # Only extensionless files are registered -- .zwc bytecode files share the same
  # glob but are not function names; autoloading them would create useless entries
  # named 'cc.zwc' etc. in the function table.
  # Anonymous function scopes NULL_GLOB and loop variable; pure zsh file, () is idiomatic here.
  () {
    setopt localoptions NULL_GLOB
    local func_file
    for func_file in "${XDG_CONFIG_HOME}"/zsh/*; do
      if [[ "${func_file:e}" == "" ]]; then
        autoload -Uz "${func_file:t}"
      fi
    done
  }
fi

# Mole shell completion
# TODO: Disabled since it causes a significant slowdown in shell startup time. Need to investigate if this can be optimized by caching the completion results or some other way.
# if command_exists mole; then
#   eval_shellenv mole completion zsh
# fi

# remove empty components to avoid '::' ending up + resulting in './' being in $PATH, etc
path=("${path[@]:#}")
fpath=("${fpath[@]:#}")
# zsh does not auto-tie INFOPATH<->infopath (unlike PATH<->path); ensure the tie exists
# so that the array form is available. typeset -T is safe to call even if already tied.
typeset -gT INFOPATH infopath ':'
infopath=("${infopath[@]:#}")
manpath=("${manpath[@]:#}")

# remove duplicates from some env vars
typeset -gU cdpath CPPFLAGS cppflags FPATH fpath infopath LDFLAGS ldflags MANPATH manpath PATH path PKG_CONFIG_PATH

# fpath/FPATH and cdpath/CDPATH must NOT be exported -- both are zsh-internal variables
# (autoload search path and cd search path respectively). Exporting them causes their
# contents to leak into child processes and persist in the macOS launchd user-session
# environment, where they are inherited by every new shell before any rc file runs.
# All other *path vars in the typeset -gU line above (PATH, MANPATH, INFOPATH, CPPFLAGS,
# LDFLAGS, PKG_CONFIG_PATH) are intentionally exported -- child processes need them.
typeset +x FPATH fpath cdpath CDPATH

# for profiling zsh, see: https://unix.stackexchange.com/a/329719/27109
# execute 'ZSH_PROFILE=true zsh' and run 'zprof' to get the details
if [[ -n "${ZSH_PROFILE:-}" ]]; then zprof; fi
