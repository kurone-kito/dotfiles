#!/bin/sh
# Python venv helper (mise-delegated)
# When mise is active, venv activation is handled automatically.
# This provides a manual fallback for projects not using mise.

# Activate a Python venv in the current directory.
# Searches for .venv/ and venv/ directories.
venv_activate() {
  if [ -n "${VIRTUAL_ENV:-}" ]; then
    echo "Already in venv: $VIRTUAL_ENV" >&2
    return 1
  fi
  for _venv_dir in .venv venv; do
    if [ -f "$_venv_dir/bin/activate" ]; then
      . "$_venv_dir/bin/activate"
      unset _venv_dir
      return 0
    fi
  done
  unset _venv_dir
  echo "No .venv or venv directory found" >&2
  return 1
}
