#!/bin/sh
# Default editor configuration
#
# Runs after 60-mise.sh so that an nvim which mise puts on PATH is found.
# Picks the first of nvim, vim and vi that exists and exports it as both
# EDITOR and VISUAL. When none exists, an inherited value is left untouched.
#
# This file is sourced into the user's shell, so it uses no scratch variable
# that could clobber one the caller already has.

if command -v nvim >/dev/null 2>&1; then
  export EDITOR='nvim'
  export VISUAL='nvim'
elif command -v vim >/dev/null 2>&1; then
  export EDITOR='vim'
  export VISUAL='vim'
elif command -v vi >/dev/null 2>&1; then
  export EDITOR='vi'
  export VISUAL='vi'
fi
