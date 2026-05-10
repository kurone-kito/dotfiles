#!/bin/sh
# Homebrew initialization
# Detects Homebrew in standard locations and sets up the shell environment.

find_brew() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi
  for p in \
    /home/linuxbrew/.linuxbrew/bin/brew \
    /opt/homebrew/bin/brew \
    /usr/local/bin/brew
  do
    [ -x "$p" ] && {
      echo "$p"
      return 0
    }
  done
  return 1
}

BREW=$(find_brew)
if [ -x "$BREW" ]; then
  eval "$("$BREW" shellenv)"
fi
unset -f find_brew
unset BREW
