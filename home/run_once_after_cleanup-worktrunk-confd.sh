#!/bin/sh
# One-time cleanup: remove the old shared conf.d worktrunk script.
# The init line has moved into each shell's RC file (.bashrc, .zshrc)
# so worktrunk's detection can find it. The old script also used an
# invalid 'sh' shell argument, making it a silent no-op.

target="$HOME/.config/shell/conf.d/75-worktrunk.sh"
if [ -f "$target" ]; then
  rm -f "$target"
fi
