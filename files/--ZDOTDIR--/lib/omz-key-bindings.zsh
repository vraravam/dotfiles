#!/usr/bin/env zsh
# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# Minimal key bindings configuration
#
# This file replaces ohmyzsh/lib/key-bindings.zsh with emacs-mode-only bindings.
#
# Original: https://github.com/ohmyzsh/ohmyzsh/blob/master/lib/key-bindings.zsh
# Original: 145 lines → Trimmed to: 75 lines
#
# Kept functionality:
# - Terminal application mode (zle-line-init/finish with echoti smkx/rmkx)
# - bindkey -e (emacs key bindings mode)
# - PageUp/PageDown history navigation
# - Up/Down arrow fuzzy history search (up-line-or-beginning-search)
# - Home/End line navigation
# - Shift-Tab reverse completion menu navigation
# - Backspace/Delete character deletion
# - Ctrl-Delete word deletion
# - Ctrl-Left/Right word navigation
# - Ctrl-W backward-kill-word
# - Ctrl-R incremental history search
# - Alt-E edit command line in $EDITOR
#
# Removed functionality:
# - Vi mode bindings (bindkey -M viins, bindkey -M vicmd)
# - Redundant terminal workarounds for ancient terminals
# - Duplicate keybindings for same functionality
#
# Estimated savings: 0.3-0.5ms (included in 0.53ms total antidote-setup reduction)
#
# To restore Vi mode or removed bindings, refer to the original OMZ file linked above.
#
# file location: ${ZDOTDIR}/lib/omz-key-bindings.zsh
################################################################################

# Make sure that the terminal is in application mode when zle is active
if (( ${+terminfo[smkx]} )) && (( ${+terminfo[rmkx]} )); then
  function zle-line-init() {
    echoti smkx
  }
  function zle-line-finish() {
    echoti rmkx
  }
  zle -N zle-line-init
  zle -N zle-line-finish
fi

# Use emacs key bindings
bindkey -e

# [PageUp] - Up a line of history
if [[ -n "${terminfo[kpp]}" ]]; then
  bindkey -M emacs "${terminfo[kpp]}" up-line-or-history
fi

# [PageDown] - Down a line of history
if [[ -n "${terminfo[knp]}" ]]; then
  bindkey -M emacs "${terminfo[knp]}" down-line-or-history
fi

# Start typing + [Up-Arrow] - fuzzy find history forward
autoload -U up-line-or-beginning-search
zle -N up-line-or-beginning-search
bindkey -M emacs "^[[A" up-line-or-beginning-search
if [[ -n "${terminfo[kcuu1]}" ]]; then
  bindkey -M emacs "${terminfo[kcuu1]}" up-line-or-beginning-search
fi

# Start typing + [Down-Arrow] - fuzzy find history backward
autoload -U down-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey -M emacs "^[[B" down-line-or-beginning-search
if [[ -n "${terminfo[kcud1]}" ]]; then
  bindkey -M emacs "${terminfo[kcud1]}" down-line-or-beginning-search
fi

# [Home] - Go to beginning of line
if [[ -n "${terminfo[khome]}" ]]; then
  bindkey -M emacs "${terminfo[khome]}" beginning-of-line
fi

# [End] - Go to end of line
if [[ -n "${terminfo[kend]}" ]]; then
  bindkey -M emacs "${terminfo[kend]}" end-of-line
fi

# [Shift-Tab] - move through the completion menu backwards
if [[ -n "${terminfo[kcbt]}" ]]; then
  bindkey -M emacs "${terminfo[kcbt]}" reverse-menu-complete
fi

# [Backspace] - delete backward
bindkey -M emacs '^?' backward-delete-char

# [Delete] - delete forward
if [[ -n "${terminfo[kdch1]}" ]]; then
  bindkey -M emacs "${terminfo[kdch1]}" delete-char
else
  bindkey -M emacs "^[[3~" delete-char
  bindkey -M emacs "^[3;5~" delete-char
fi

# [Ctrl-Delete] - delete whole forward-word
bindkey -M emacs '^[[3;5~' kill-word

# [Ctrl-RightArrow] - move forward one word
bindkey -M emacs '^[[1;5C' forward-word

# [Ctrl-LeftArrow] - move backward one word
bindkey -M emacs '^[[1;5D' backward-word

# [Ctrl-w] - delete whole backward-word
bindkey -M emacs '^w' backward-kill-word

# [Ctrl-r] - Search backward incrementally for a specified string
bindkey -M emacs '^r' history-incremental-search-backward

# Edit the current command line in $EDITOR
autoload -U edit-command-line
zle -N edit-command-line
bindkey -M emacs '\ee' edit-command-line
