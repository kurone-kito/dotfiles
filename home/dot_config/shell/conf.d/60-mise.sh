#!/bin/sh
# mise (polyglot runtime manager) initialization
# https://mise.jdx.dev/
# Requires: mise installed via Homebrew, curl, or package manager

command -v mise >/dev/null 2>&1 || return 0

# Build trusted config paths so hooks never show trust errors
_mise_trusted="${HOME}/.mise:${HOME}/.config/mise"

# WSL: include Windows-side config directories (visible via /mnt/c/)
if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
  for _mise_dir in /mnt/c/Users/*/.mise /mnt/c/Users/*/.config/mise; do
    [ -d "${_mise_dir}" ] 2>/dev/null && _mise_trusted="${_mise_trusted}:${_mise_dir}"
  done
fi

export MISE_TRUSTED_CONFIG_PATHS="${_mise_trusted}"
unset _mise_trusted _mise_dir

# Also run mise trust for persistence across sessions
for _mise_cfg in \
  "${HOME}/.mise/config.toml" \
  "${HOME}/.config/mise/config.toml"; do
  [ -f "${_mise_cfg}" ] && mise trust "${_mise_cfg}" 2>/dev/null || true
done

# WSL: also trust Windows-side configs visible via /mnt/c/
if [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; then
  for _mise_cfg in \
    /mnt/c/Users/*/.mise/config.toml \
    /mnt/c/Users/*/.config/mise/config.toml; do
    [ -f "${_mise_cfg}" ] 2>/dev/null && mise trust "${_mise_cfg}" 2>/dev/null || true
  done
fi
unset _mise_cfg

if [ -n "${ZSH_VERSION:-}" ]; then
  eval "$(mise activate zsh --quiet 2>/dev/null)" 2>/dev/null
elif [ -n "${BASH_VERSION:-}" ]; then
  eval "$(mise activate bash --quiet 2>/dev/null)" 2>/dev/null
fi
