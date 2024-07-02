#!/usr/bin/env zsh

# vim:syntax=zsh
# vim:filetype=zsh

# file location: ${HOME}/.zshrc
# load order: .zshenv, .zprofile, .shellrc, .zshrc, .zshrc.custom, .aliases, .aliases.custom, .zlogin
test -n "${FIRST_INSTALL+1}" && echo "loading .zshrc"

# Optimizing zsh:
# https://htr3n.github.io/2018/07/faster-zsh/
# https://blog.mattclemente.com/2020/06/26/oh-my-zsh-slow-to-load/

# for profiling zsh, see: https://unix.stackexchange.com/a/329719/27109
# zmodload zsh/zprof

# this file is being sourced in '.zprofile', but for some reason when running the 'time_shell_startup' function, we still get errors. so loading it explicitly once more
type load_file_if_exists &> /dev/null 2>&1 || source "${HOME}/.shellrc"

export NVM_LAZY_LOAD=true
export NVM_COMPLETION=true

# Enable Powerlevel10k instant prompt. Should stay close to the top of ${HOME}/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
load_file_if_exists "${XDG_CACHE_HOME}/p10k-instant-prompt-${USERNAME}.zsh"

# To customize prompt, run `p10k configure` or edit ${HOME}/.p10k.zsh.
load_file_if_exists "${HOME}/.p10k.zsh"
# TODO: the path didn't exist in a newly imaged machine - need to revisit at a later time
load_file_if_exists "${HOMEBREW_PREFIX}/opt/powerlevel10k/powerlevel10k.zsh-theme"
load_file_if_exists "${HOMEBREW_PREFIX}/share/powerlevel10k/powerlevel10k.zsh-theme"

# Path to your oh-my-zsh installation.
export ZSH="${HOME}/.oh-my-zsh"

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

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than ${ZSH}/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in ${ZSH}/plugins/
# Custom plugins may be added to ${ZSH_CUSTOM}/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(evalcache colored-man-pages brew sudo zsh-autosuggestions fast-syntax-highlighting git)

load_file_if_exists "${ZSH}/oh-my-zsh.sh"

# eval "$(direnv hook zsh)"
command_exists direnv && _evalcache direnv hook zsh

# User configuration
# export MANPATH="/usr/local/man${MANPATH+:$MANPATH}"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for remote sessions
[[ -n ${SSH_CONNECTION} ]] && export EDITOR="vim"
# Use code if its installed (both Mac OSX and Linux)
command_exists code
[[ "${EDITOR}" == "" && $? -eq 0 ]] && export EDITOR="code --wait"
# If neither of the above works, then fall back to vi
[[ "${EDITOR}" == "" ]] && export EDITOR="vi"

# Compilation flags
[[ "${ARCH}" =~ "x86" ]] && export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="${EDITOR} ${HOME}/.zshrc"
# alias ohmyzsh="${EDITOR} ${ZSH}"

load_file_if_exists "${HOME}/.zshrc.custom"

# remove duplicates from some env vars
typeset -U cdpath
typeset -U cppflags
typeset -U fpath
typeset -U infopath
typeset -U ldflags
typeset -U manpath
typeset -U path

### MANAGED BY RANCHER DESKTOP START (DO NOT EDIT)
export PATH="${HOME}/.rd/bin:${PATH+:${PATH}}"
### MANAGED BY RANCHER DESKTOP END (DO NOT EDIT)
