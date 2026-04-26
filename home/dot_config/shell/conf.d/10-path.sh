#!/bin/sh
# PATH additions
# Prepend user-local directories if they exist.

prepend_path() {
  case ":${PATH}:" in
    *:"$1":*) ;;
    *) [ -d "$1" ] && export PATH="$1:$PATH" ;;
  esac
}

prepend_path "$HOME/.local/bin"
prepend_path "$HOME/bin"

unset -f prepend_path
