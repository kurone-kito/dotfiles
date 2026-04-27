#!/bin/sh
# GPG agent: set current TTY so pinentry-curses can find the terminal,
# and inform the running agent of the new session. Use gpg-cache when
# you want to warm the signing cache up front for a long session.

if _dotfiles_gpg_tty="$(tty 2>/dev/null)"; then
  export GPG_TTY="$_dotfiles_gpg_tty"
fi

if command -v gpg-connect-agent >/dev/null 2>&1; then
  gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
fi

unset _dotfiles_gpg_tty
