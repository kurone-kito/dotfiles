#!/bin/sh
# zoxide (smarter cd command) initialization
# https://github.com/ajeetdsouza/zoxide
# Requires: zoxide installed via Homebrew, cargo, or package manager

command -v zoxide >/dev/null 2>&1 || return 0

if [ -n "${ZSH_VERSION:-}" ]; then
  eval "$(zoxide init zsh 2>/dev/null)"
elif [ -n "${BASH_VERSION:-}" ]; then
  eval "$(zoxide init bash 2>/dev/null)"
fi
