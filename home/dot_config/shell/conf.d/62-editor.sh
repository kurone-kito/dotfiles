#!/bin/sh
# Default editor configuration
#
# Runs after 60-mise.sh so that an nvim which mise puts on PATH is found.
# Picks the first of nvim, vim and vi that exists and exports it as both
# EDITOR and VISUAL. When none exists, an inherited value is left untouched.

for _editor in nvim vim vi; do
  if command -v "$_editor" >/dev/null 2>&1; then
    export EDITOR="$_editor"
    export VISUAL="$_editor"
    break
  fi
done
unset _editor
