#!/bin/sh

if command -v git-wt >/dev/null 2>&1; then
  SHELL_NAME="$(ps -p $$ -o comm=)"
  eval "$(git-wt config shell init sh)"
fi
