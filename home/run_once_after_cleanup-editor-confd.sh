#!/bin/sh
# One-time cleanup: remove the old conf.d editor script.
# The editor defaults moved from 30-editor.sh to 62-editor.sh so that they
# run after 60-mise.sh and can find an nvim that mise installs. chezmoi does
# not delete a target whose source file was renamed, so the old deployed file
# would keep exporting vim before mise has put nvim on PATH.

# Close stdin so chezmoi's overwrite prompts cannot be starved.
exec </dev/null

target="$HOME/.config/shell/conf.d/30-editor.sh"
if [ -f "$target" ]; then
  rm -f "$target"
fi
