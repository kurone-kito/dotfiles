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
_wt_command=$(command -v wt 2>/dev/null || :)
_git_wt_command=$(command -v git-wt 2>/dev/null || :)
_batcat_command=$(command -v batcat 2>/dev/null || :)
_bat_command=$(command -v bat 2>/dev/null || :)

if [ -n "$_wt_command" ]; then
  _wt_path=$(printf '%s' "$_wt_command" | tr '[:upper:]' '[:lower:]' || true)
  case "$_wt_path" in
    *windowsapps*/wt|*windowsapps*/wt.exe|*windowsapps*\\wt|*windowsapps*\\wt.exe|\
    *microsoft.windowsterminal*/wt|*microsoft.windowsterminal*/wt.exe|\
    *microsoft.windowsterminal*\\wt|*microsoft.windowsterminal*\\wt.exe)
      _wt_is_windows_terminal=true
      ;;
  esac
fi

if [ -z "$_wt_command" ] && [ -n "$_git_wt_command" ]; then
  alias wt='git-wt'
fi

if [ -z "$_git_wt_command" ] && [ -n "$_wt_command" ]; then
  if [ "$_wt_is_windows_terminal" != true ]; then
    alias git-wt='wt'
  fi
fi

if [ -z "$_batcat_command" ] && [ -n "$_bat_command" ]; then
  alias batcat='bat'
fi

if [ -z "$_bat_command" ] && [ -n "$_batcat_command" ]; then
  alias bat='batcat'
fi

unset _wt_path _wt_is_windows_terminal
unset _wt_command _git_wt_command _batcat_command _bat_command
