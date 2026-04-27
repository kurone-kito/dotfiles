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
    vim -es -u "${HOME}/.vimrc" \
      -c 'PlugInstall --sync' \
      -c 'PlugClean!' \
      -c 'qa!' \
      2>&1 || echo "  WARNING: vim plugin sync reported errors."
    echo "  vim plugin sync complete."
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

  nvim --headless "+Lazy! sync" +qa 2>&1 \
    || echo "  WARNING: nvim plugin sync reported errors."
  echo "  nvim plugin sync complete."
else
  echo "nvim not found; skipping nvim plugin setup."
fi

if [ "$found_editor" = false ]; then
  echo "No editors found; skipping editor plugin setup."
fi
