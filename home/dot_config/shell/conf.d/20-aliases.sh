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
_wt_path=''
_wt_is_windows_terminal=false
if command -v wt >/dev/null 2>&1; then
  _wt_path=$(command -v wt 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
  case "$_wt_path" in
    *windowsapps*/wt|*windowsapps*/wt.exe|*windowsapps*\\wt|*windowsapps*\\wt.exe|\
    *microsoft.windowsterminal*/wt|*microsoft.windowsterminal*/wt.exe|\
    *microsoft.windowsterminal*\\wt|*microsoft.windowsterminal*\\wt.exe)
      _wt_is_windows_terminal=true
      ;;
  esac
fi

if ! command -v wt >/dev/null 2>&1 && command -v git-wt >/dev/null 2>&1; then
  alias wt='git-wt'
fi

if ! command -v git-wt >/dev/null 2>&1 && command -v wt >/dev/null 2>&1; then
  if [ "$_wt_is_windows_terminal" != true ]; then
    alias git-wt='wt'
  fi
fi

if ! command -v batcat >/dev/null 2>&1 && command -v bat >/dev/null 2>&1; then
  alias batcat='bat'
fi

if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
  alias bat='batcat'
fi

unset _wt_path _wt_is_windows_terminal
