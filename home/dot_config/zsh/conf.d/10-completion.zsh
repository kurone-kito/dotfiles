#!/bin/zsh
# Zsh completion system

autoload -Uz compinit

# Rebuild completion dump once a day
if [[ -n "${ZDOTDIR}/.zcompdump"(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# Case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
# Menu-style selection
zstyle ':completion:*' menu select
# Colorize completion list
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
