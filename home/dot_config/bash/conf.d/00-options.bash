#!/bin/bash
# Bash-specific shell options

shopt -s checkwinsize
shopt -s histappend
shopt -s globstar 2>/dev/null

HISTCONTROL=ignoreboth
HISTSIZE=10000
HISTFILESIZE=20000
