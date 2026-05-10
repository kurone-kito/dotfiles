#!/bin/sh
# Default editor configuration

if command -v vim >/dev/null 2>&1; then
  export EDITOR='vim'
  export VISUAL='vim'
fi
