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

# execute 'FIRST_INSTALL=true zsh' to debug the load order of the custom zsh configuration files
[[ -n "${FIRST_INSTALL+1}" ]] && echo "loading ${0}"

# for profiling zsh, see: https://unix.stackexchange.com/a/329719/27109
# execute 'ZSH_PROFILE_RC=true zsh -i -c exit' and run 'zprof' to get the details
[[ -n "${ZSH_PROFILE_RC+1}" ]] && zmodload zsh/zprof

type load_file_if_exists &> /dev/null 2>&1 || source "${HOME}/.shellrc"

# Enable Powerlevel10k instant prompt. Should stay close to the top of ${ZDOTDIR}/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
load_file_if_exists "${XDG_CACHE_HOME}/p10k-instant-prompt-$(whoami).zsh"

# To customize prompt, run `p10k configure` or edit ${HOME}/.p10k.zsh.
load_file_if_exists "${HOME}/.p10k.zsh"
load_file_if_exists "${HOMEBREW_PREFIX}/share/powerlevel10k/powerlevel10k.zsh-theme"

# Path to your Oh My Zsh installation.
export ZSH="${ZDOTDIR:-${HOME}}/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
# ZSH_THEME="robbyrussell"
# ZSH_THEME="powerlevel10k/powerlevel10k"
# ZSH_THEME="agnoster"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in ${ZSH}/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
zstyle ':omz:update' frequency 1

# Set plugin options that are needed before each plugin is loaded
zstyle ':omz:plugins:eza' 'icons' yes
# zstyle ':omz:plugins:eza' 'git-status' no
# zstyle ':omz:plugins:eza' 'header' no
zstyle :omz:plugins:iterm2 shell-integration yes

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
export ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than ${ZSH}/custom?
export ZSH_CUSTOM="${ZSH_CUSTOM:-"${ZSH:-"${HOME}/.oh-my-zsh"}/custom"}"

# https://github.com/zsh-users/zsh-autosuggestions?tab=readme-ov-file#suggestion-strategy
export ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Which plugins would you like to load?
# Standard plugins can be found in ${ZSH}/plugins/
# Custom plugins may be added to ${ZSH_CUSTOM}/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(brew direnv eza fast-syntax-highlighting git iterm2 mise sudo zbell zsh-autosuggestions)

# according to https://github.com/zsh-users/zsh-completions/issues/603#issue-373185486, this can't be added as a plugin to omz for the fpath to work correctly
append_to_fpath_if_dir_exists "${ZSH_CUSTOM}/plugins/zsh-completions/src"

load_file_if_exists "${ZSH}/oh-my-zsh.sh"

# User configuration
# export MANPATH="/usr/local/man${MANPATH+:$MANPATH}"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for remote sessions
is_non_zero_string "${SSH_CONNECTION}" && export EDITOR="vi"
# Use code if its installed (both Mac OSX and Linux)
command_exists code && ! is_non_zero_string "${EDITOR}" && export EDITOR="code --wait"
# If neither of the above works, then fall back to vi
command_exists vi && ! is_non_zero_string "${EDITOR}" && export EDITOR="vi"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the ${ZSH_CUSTOM} folder, with .zsh extension. Examples:
# - ${ZSH_CUSTOM}/aliases.zsh
# - ${ZSH_CUSTOM}/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="${EDITOR} ${ZDOTDIR}/.zshrc"
# alias ohmyzsh="${EDITOR} ${ZSH}"

# setup paths in the beginning so that all other conditions work correctly
append_to_path_if_dir_exists "${PERSONAL_BIN_DIR}"
append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"
append_to_path_if_dir_exists "${PROJECTS_BASE_DIR}/oss/git_scripts"
# Note: Not sure if its a bug, but the first iterm tab alone has all the paths, but these are missing in subsequent tabs and new windows
append_to_path_if_dir_exists '/usr/local/bin'
append_to_path_if_dir_exists "${HOME}/.rd/bin"

# Note: can't defer this since the first time install fails
load_file_if_exists "${HOME}/.aliases"

# erlang history in iex
# export ERL_AFLAGS="-kernel shell_history enabled -kernel shell_history_file_bytes 1024000"

if is_macos; then
  # setopt glob_dots                # no special treatment for file names with a leading dot
  # setopt no_auto_menu             # require an extra TAB press to open the completion menu
  # setopt auto_menu                # automatically use menu completion
  # setopt list_beep
  # setopt correct_all              # autocorrect commands
  # setopt always_to_end            # move cursor to end if word had one match

  setopt append_history           # append history list to the history file
  setopt share_history            # share history between different instances of the shell
  setopt inc_append_history       # append command to history file immediately after execution
  setopt extended_history         # save each command's beginning timestamp and the duration to the history file
  setopt hist_ignore_all_dups     # do not put duplicated command into history list
  setopt hist_ignore_dups         # do not store duplications
  setopt hist_allow_clobber
  setopt hist_reduce_blanks       # remove unnecessary blanks
  setopt hist_save_no_dups        # do not save duplicated command
  setopt auto_cd                  # cd into directory if the name is not an alias or function, but matches a directory
  setopt auto_pushd               # make cd push the old directory onto the directory stack
  setopt pushd_silent             # do not print the directory stack after pushd or popd
  setopt pushd_ignore_dups        # don’t push multiple copies of the same directory
  setopt beep                     # beep on error or on completion of long commands
  setopt extended_glob
  setopt local_options
  setopt auto_list                # automatically list choices on an ambiguous completion.
  setopt list_ambiguous
  setopt list_types               # if the file being listed is a directory, show a trailing slash
  setopt no_case_glob             # case-insensitive globbing
  setopt hist_expire_dups_first   # expire duplicates first
  setopt hist_find_no_dups        # ignore duplicates when searching
  setopt null_glob                # ignore errors when file globs don't match anything

  # console colors
  autoload -Uz colors && colors

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
  # knownhosts=( ${${${${(f)"$(<${HOME}/.ssh/known_hosts)"}:#[0-9]*}%%\ *}%%,*} )
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

  # Use modern completion system (needs to be run AFTER some zstyle defns; usually a good idea to do so after all of them)
  autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump-${ZSH_VERSION}"

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
    prepend_to_manpath_if_dir_exists "${HOMEBREW_PREFIX}/share/man"

    use_homebrew_installation_for() {
      ! is_directory "${1}" && return

      prepend_to_path_if_dir_exists "${1}/bin"
      prepend_to_path_if_dir_exists "${1}/libexec/bin"
      prepend_to_path_if_dir_exists "${1}/libexec/gnubin"
      # For compilers to find this installation you may need to set:
      prepend_to_ldflags_if_dir_exists "${1}/lib"
      prepend_to_cppflags_if_dir_exists "${1}/include"
      # For pkg-config to find this installation you may need to set:
      prepend_to_pkg_config_path_if_dir_exists "${1}/lib/pkgconfig"
      prepend_to_manpath_if_dir_exists "${1}/libexec/gnuman"
    }

    # override default curl and use from homebrew installation
    use_homebrew_installation_for "${HOMEBREW_PREFIX}/opt/curl"

    # zlib - required for installing python via mise
    use_homebrew_installation_for "${HOMEBREW_PREFIX}/opt/zlib"

    # override default Sqlite3 and use from homebrew installation
    use_homebrew_installation_for "${HOMEBREW_PREFIX}/opt/sqlite"

    # override default gnu-tar and use from homebrew installation
    use_homebrew_installation_for "${HOMEBREW_PREFIX}/opt/gnu-tar"

    # override default openssl and use from homebrew installation
    local openssl_dir="${HOMEBREW_PREFIX}/opt/openssl@3"
    is_directory "${openssl_dir}" && use_homebrew_installation_for "${openssl_dir}" && export RUBY_CONFIGURE_OPTS="--with-openssl-dir=${openssl_dir}"
    unset openssl_dir
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

# rspec and cucumber
export CUCUMBER_COLORS="pending_param=magenta:failed_param=magenta:passed_param=magenta:skipped_param=magenta"
export RSPEC="true"

# fzy
# load_file_if_exists "${HOME}/.fzy-key-bindings.zsh"

if is_directory "${XDG_CONFIG_HOME}/zsh"; then
  # register folder for custom zsh functions to be lazy-loaded
  append_to_fpath_if_dir_exists "${XDG_CONFIG_HOME}/zsh"

  # Dynamically autoload all files in the custom zsh functions directory.
  # Assumes the filename is the function name.
  local func_file
  for func_file in "${XDG_CONFIG_HOME}"/zsh/*(N); do
    autoload -Uz "${func_file}"
  done
  unset func_file
fi

# remove empty components to avoid '::' ending up + resulting in './' being in $PATH, etc
path=( "${path[@]:#}" )
fpath=( "${fpath[@]:#}" )
infopath=( "${infopath[@]:#}" )
manpath=( "${manpath[@]:#}" )

# remove duplicates from some env vars
typeset -gU cdpath CPPFLAGS cppflags FPATH fpath infopath LDFLAGS ldflags MANPATH manpath PATH path PKG_CONFIG_PATH

# for profiling zsh, see: https://unix.stackexchange.com/a/329719/27109
# execute 'ZSH_PROFILE_RC=true zsh' and run 'zprof' to get the details
[[ -n "${ZSH_PROFILE_RC+1}" ]] && zprof
