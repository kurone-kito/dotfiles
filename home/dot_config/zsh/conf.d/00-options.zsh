#!/bin/zsh
# Zsh-specific shell options

setopt AUTO_CD
setopt EXTENDED_GLOB
setopt NO_BEEP
setopt INTERACTIVE_COMMENTS

# History
HISTFILE="${ZDOTDIR:-$HOME/.config/zsh}/.zsh_history"
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
