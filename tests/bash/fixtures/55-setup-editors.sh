#!/bin/bash
# Pre-rendered test fixture for run_onchange_after_55-setup-editors.sh.tmpl.
# Hash comments are replaced with dummy values since tests don't use chezmoi.
#
# This script is intentionally NOT a chezmoi template.
# It simulates what chezmoi would render with fixed hash values.
#
# vimrc hash: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
# nvim init hash: a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
# nvim plugins hash:
#   colorscheme.lua: 0000000000000000000000000000000000000000000000000000000000000001
#   completion.lua: 0000000000000000000000000000000000000000000000000000000000000002
set -euo pipefail

found_editor=false

# ---------------------------------------------------------------------------
# vim — vim-plug
# ---------------------------------------------------------------------------
if command -v vim &>/dev/null; then
  found_editor=true
  echo "Setting up vim plugins..."

  # Bootstrap vim-plug if missing (mirrors the auto-bootstrap in .vimrc)
  plug_vim="${HOME}/.vim/autoload/plug.vim"
  if [ ! -f "$plug_vim" ]; then
    if command -v curl &>/dev/null; then
      echo "  Bootstrapping vim-plug..."
      curl -fLo "$plug_vim" --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim \
        2>&1 || { echo "  WARNING: vim-plug bootstrap failed; skipping vim."; }
    else
      echo "  WARNING: curl not found; cannot bootstrap vim-plug. Skipping vim."
    fi
  fi

  # Install / update / clean plugins (non-interactive ex mode)
  if [ -f "$plug_vim" ]; then
    if vim -es -u "${HOME}/.vimrc" \
      -c 'PlugInstall --sync' \
      -c 'PlugClean!' \
      -c 'qa!' \
      </dev/null 2>&1; then
      echo "  vim plugin sync complete."
    else
      echo "  WARNING: vim plugin sync reported errors."
    fi
  fi
else
  echo "vim not found; skipping vim plugin setup."
fi

# ---------------------------------------------------------------------------
# nvim — lazy.nvim
# ---------------------------------------------------------------------------
if command -v nvim &>/dev/null; then
  found_editor=true
  echo "Setting up nvim plugins..."

  # Phase 1: Bootstrap — let init.lua clone lazy.nvim on first run.
  # A separate invocation ensures the Lazy command is registered in a
  # clean session for phase 2.
  # Stdin is redirected from /dev/null because nvim, even with
  # --headless, may put the controlling TTY in raw mode briefly during
  # startup; if chezmoi's stdin is the TTY, that can leave the terminal
  # in a state where chezmoi's later prompts (e.g. "X has changed since
  # chezmoi last wrote it") swallow keypresses.
  nvim --headless +qa </dev/null 2>&1 || true

  lazydir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim"
  if [ ! -d "$lazydir" ]; then
    echo "  WARNING: lazy.nvim bootstrap failed; skipping nvim plugin sync."
  else
    # Phase 2: Sync plugins — Lazy command available from fresh session
    if nvim --headless "+Lazy! sync" +qa </dev/null 2>&1; then
      echo "  nvim plugin sync complete."
    else
      echo "  WARNING: nvim plugin sync reported errors."
    fi
  fi
else
  echo "nvim not found; skipping nvim plugin setup."
fi

if [ "$found_editor" = false ]; then
  echo "No editors found; skipping editor plugin setup."
fi
