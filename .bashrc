#!/bin/bash
# -*- mode: sh -*-
# vim: set ft=sh :

if which fnm > /dev/null 2>&1
then
  eval "$(fnm env --use-on-cd)"
  if which cygpath > /dev/null 2>&1
  then
    PATH=$(cygpath -u "$PATH")
  fi
  export PATH
fi
