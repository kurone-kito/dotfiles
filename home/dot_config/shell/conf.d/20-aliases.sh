#!/bin/sh
# Common aliases shared between bash and zsh

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Colorize by default where supported
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Compatibility aliases for platform-specific package names
if ! command -v wt >/dev/null 2>&1 && command -v git-wt >/dev/null 2>&1; then
  alias wt='git-wt'
fi

if ! command -v git-wt >/dev/null 2>&1 && command -v wt >/dev/null 2>&1; then
  alias git-wt='wt'
fi

if ! command -v batcat >/dev/null 2>&1 && command -v bat >/dev/null 2>&1; then
  alias batcat='bat'
fi

if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
  alias bat='batcat'
fi
