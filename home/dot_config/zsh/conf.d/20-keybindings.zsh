#!/bin/zsh
# Zsh keybindings

# Use emacs keybindings as base
bindkey -e

# History search with up/down arrows
bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward
