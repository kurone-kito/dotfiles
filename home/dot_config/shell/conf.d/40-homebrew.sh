#!/bin/sh
# Homebrew initialization
# Detects Homebrew in standard locations and sets up the shell environment.

find_brew() {
  _brew_path=$(command -v brew 2>/dev/null || :)
  if [ -n "$_brew_path" ]; then
    printf '%s\n' "$_brew_path"
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
