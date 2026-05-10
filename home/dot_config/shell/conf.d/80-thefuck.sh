#!/bin/sh
# thefuck (command correction) initialization
# https://github.com/nvbn/thefuck
# Requires: thefuck installed via Homebrew, pip, or package manager

command -v thefuck >/dev/null 2>&1 || return 0

# thefuck may fail on Python 3.12+ (removed imp module); suppress errors
eval "$(thefuck --alias 2>/dev/null)" 2>/dev/null || true
