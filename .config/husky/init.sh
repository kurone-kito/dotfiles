# -*- mode: sh -*-
# vim: set ft=sh :
# shellcheck disable=SC2148

if [[ "${OSTYPE}" == "darwin"* ]]; then
  # See: https://github.com/kurone-kito/setup.macos/tree/master/.zsh.d
  EXPORTS_SH="${HOME}/.zsh.d/exports"
  HOMEBREW_SH="${HOME}/.zsh.d/homebrew"
  ASDF_SH="${HOME}/.zsh.d/z-asdf"

  # shellcheck disable=SC1090
  [ -f "${EXPORTS_SH}" ] && . "${EXPORTS_SH}"

  # shellcheck disable=SC1090
  [ -f "${HOMEBREW_SH}" ] && . "${HOMEBREW_SH}"

  # shellcheck disable=SC1090
  [ -f "${ASDF_SH}" ] && . "${ASDF_SH}"
fi
