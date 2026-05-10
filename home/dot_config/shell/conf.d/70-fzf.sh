#!/bin/sh
# fzf (fuzzy finder) shell integration
# https://github.com/junegunn/fzf
# Sets up key bindings (Ctrl+T, Ctrl+R, Alt+C) and fuzzy completion.

command -v fzf >/dev/null 2>&1 || return 0

# fzf 0.48+ supports --bash/--zsh; older versions use key-bindings/completion scripts
_fzf_version="$(fzf --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+'| head -1)"
_fzf_major="${_fzf_version%%.*}"
_fzf_minor="${_fzf_version#*.}"

if [ "${_fzf_major:-0}" -gt 0 ] 2>/dev/null || [ "${_fzf_minor:-0}" -ge 48 ] 2>/dev/null; then
  # Modern fzf (0.48+)
  if [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(fzf --zsh)"
  elif [ -n "${BASH_VERSION:-}" ]; then
    eval "$(fzf --bash)"
  fi
else
  # Legacy fzf — source bundled scripts if available
  _fzf_dir="${FZF_DIR:-}"
  [ -z "${_fzf_dir}" ] && _fzf_dir="$(dirname "$(command -v fzf)")/../share/fzf" 2>/dev/null
  if [ -d "${_fzf_dir}" ]; then
    [ -f "${_fzf_dir}/key-bindings.bash" ] && [ -n "${BASH_VERSION:-}" ] && . "${_fzf_dir}/key-bindings.bash"
    [ -f "${_fzf_dir}/key-bindings.zsh" ] && [ -n "${ZSH_VERSION:-}" ] && . "${_fzf_dir}/key-bindings.zsh"
    [ -f "${_fzf_dir}/completion.bash" ] && [ -n "${BASH_VERSION:-}" ] && . "${_fzf_dir}/completion.bash"
    [ -f "${_fzf_dir}/completion.zsh" ] && [ -n "${ZSH_VERSION:-}" ] && . "${_fzf_dir}/completion.zsh"
  fi
fi

unset _fzf_version _fzf_major _fzf_minor _fzf_dir
