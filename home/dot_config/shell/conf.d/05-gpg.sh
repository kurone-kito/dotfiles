#!/bin/sh
# GPG agent: set current TTY so pinentry-curses can find the terminal,
# and inform the running agent of the new session.

export GPG_TTY="$(tty)"

if command -v gpg-connect-agent >/dev/null 2>&1; then
  gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
fi
