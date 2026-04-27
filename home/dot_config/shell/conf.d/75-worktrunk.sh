#!/bin/sh

if command -v git-wt >/dev/null 2>&1; then
  eval "$(git-wt config shell init sh)"
fi
