#!/bin/sh
# mise (polyglot runtime manager) initialization
# https://mise.jdx.dev/
# Requires: mise installed via Homebrew, curl, or package manager

command -v mise >/dev/null 2>&1 || return 0

# DOTFILES_MISE_ASSUME_WSL=1 forces the WSL branch and =0 forces the
# non-WSL branch so tests do not depend on the host.
_dotfiles_mise_is_wsl() {
  case "${DOTFILES_MISE_ASSUME_WSL:-}" in
    1 | true | yes) return 0 ;;
    0 | false | no) return 1 ;;
  esac
  [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null
}

_dotfiles_mise_sha256_file() {
  _sum=
  if command -v sha256sum >/dev/null 2>&1; then
    _sum=$(sha256sum "$1" 2>/dev/null) || return 1
  elif command -v shasum >/dev/null 2>&1; then
    _sum=$(shasum -a 256 "$1" 2>/dev/null) || return 1
  else
    return 1
  fi
  printf '%s\n' "$_sum" | awk 'NR == 1 { print $1 }'
}

_dotfiles_mise_sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk 'NR == 1 { print $1 }'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk 'NR == 1 { print $1 }'
    return 0
  fi
  return 1
}

_dotfiles_mise_trust_stamp_file() {
  if [ -n "${DOTFILES_MISE_TRUST_STAMP:-}" ]; then
    printf '%s\n' "$DOTFILES_MISE_TRUST_STAMP"
    return 0
  fi
  printf '%s\n' "${HOME}/.cache/dotfiles/mise-trust-stamp"
}

_dotfiles_mise_trust_dir_mtime() {
  _trust_dir="${MISE_STATE_DIR:-$HOME/.local/state/mise}/trusted-configs"
  if [ -d "$_trust_dir" ]; then
    stat -c %Y "$_trust_dir" 2>/dev/null && return 0
  fi
  printf '%s\n' missing
}

# Skip mise trust only when this exact path and content were trusted
# while mise's trust directory was unchanged. Any miss falls open.
_dotfiles_mise_trust_if_needed() {
  _cfg=$1
  [ -f "$_cfg" ] || return 0
  if ! _dotfiles_mise_is_wsl; then
    mise trust "$_cfg" 2>/dev/null || true
    return 0
  fi
  _hash=$(_dotfiles_mise_sha256_file "$_cfg") || _hash=
  _size=$(wc -c < "$_cfg" | tr -d '[:space:]')
  _mtime=$(_dotfiles_mise_trust_dir_mtime)
  _stamp=$(_dotfiles_mise_trust_stamp_file)
  if [ -n "$_hash" ] && [ -f "$_stamp" ]; then
    if awk -F '\t' -v p="$_cfg" -v h="$_hash" -v s="$_size" -v m="$_mtime" \
      '$1 == p && $2 == h && $3 == s && $4 == m { found = 1 } END { exit found ? 0 : 1 }' \
      "$_stamp"; then
      return 0
    fi
  fi
  if ! mise trust "$_cfg" 2>/dev/null; then
    return 0
  fi
  [ -n "$_hash" ] || return 0
  _mtime=$(_dotfiles_mise_trust_dir_mtime)
  mkdir -p "$(dirname "$_stamp")" || return 0
  _tmp="${_stamp}.tmp.$$"
  if [ -f "$_stamp" ]; then
    awk -F '\t' -v p="$_cfg" '$1 != p { print }' "$_stamp" > "$_tmp" || true
  else
    : > "$_tmp"
  fi
  printf '%s\t%s\t%s\t%s\n' "$_cfg" "$_hash" "$_size" "$_mtime" >> "$_tmp"
  mv "$_tmp" "$_stamp"
}

# In-memory identity of the configs hook-env would read. A hash failure
# prints HASH_FAIL so the caller refuses to skip.
_dotfiles_mise_fp_add_file() {
  [ -n "$1" ] || return 0
  [ -f "$1" ] || return 0
  _file_hash=$(_dotfiles_mise_sha256_file "$1") || {
    printf '%s\n' HASH_FAIL
    return 0
  }
  printf 'file\t%s\t%s\n' "$1" "$_file_hash"
  if grep -q -e '{{cwd' -e '{{ cwd' -e '{{config_root' -e '{{ config_root' "$1" 2>/dev/null; then
    printf '%s\n' NEED_PWD
  fi
}

_dotfiles_mise_fp_body() {
  printf 'env\t%s\n' "${MISE_ENV-}"
  printf 'config_file\t%s\n' "${MISE_CONFIG_FILE-}"
  _dotfiles_mise_fp_add_file "${HOME}/.config/mise/config.toml"
  _dotfiles_mise_fp_add_file "${HOME}/.config/mise/config.local.toml"
  _dotfiles_mise_fp_add_file "${HOME}/.mise/config.toml"
  _dotfiles_mise_fp_add_file "${HOME}/.mise/config.local.toml"
  if [ -n "${MISE_GLOBAL_CONFIG_FILE:-}" ]; then
    _dotfiles_mise_fp_add_file "$MISE_GLOBAL_CONFIG_FILE"
  fi
  _dir=${PWD:-/}
  while [ -n "$_dir" ]; do
    for _name in \
      mise.toml .mise.toml mise.local.toml .mise.local.toml \
      .config/mise/config.toml .config/mise/config.local.toml \
      .mise/config.toml .mise/config.local.toml \
      .tool-versions .node-version .nvmrc .python-version \
      .ruby-version .go-version .java-version .bun-version \
      .terraform-version; do
      _dotfiles_mise_fp_add_file "${_dir}/${_name}"
    done
    [ "$_dir" = / ] && break
    _next=$(dirname "$_dir")
    [ "$_next" = "$_dir" ] && break
    _dir=$_next
  done
}

_dotfiles_mise_config_fingerprint() {
  _body=$(_dotfiles_mise_fp_body) || return 1
  if printf '%s\n' "$_body" | grep -q '^HASH_FAIL$'; then
    return 1
  fi
  if printf '%s\n' "$_body" | grep -q '^NEED_PWD$'; then
    _body="${_body}
pwd=${PWD:-}"
  fi
  printf '%s\n' "$_body" | _dotfiles_mise_sha256_stdin
}

# Return 0 when the caller should skip hook-env. --force never skips.
# A missing previous fingerprint never skips.
_dotfiles_mise_hook_is_unchanged() {
  _fp=$(_dotfiles_mise_config_fingerprint) || return 1
  [ -n "$_fp" ] || return 1
  _DOTFILES_MISE_FP_NEXT=$_fp
  if [ "${1:-}" = "--force" ]; then
    return 1
  fi
  if [ -n "${_DOTFILES_MISE_FP:-}" ] && [ "$_fp" = "$_DOTFILES_MISE_FP" ]; then
    return 0
  fi
  return 1
}

_dotfiles_mise_wrap_bash() {
  _fn=$1
  _orig=$2
  declare -F "$_fn" >/dev/null 2>&1 || return 0
  eval "$(declare -f "$_fn" | sed "1s/^${_fn} /${_orig} /")"
  eval "${_fn}() {
    _prev=\$?
    if _dotfiles_mise_hook_is_unchanged \"\$@\"; then
      return \$_prev
    fi
    if [ -n \"\${_DOTFILES_MISE_FP_NEXT:-}\" ]; then
      _DOTFILES_MISE_FP=\$_DOTFILES_MISE_FP_NEXT
    fi
    ${_orig} \"\$@\"
  }"
}

_dotfiles_mise_wrap_zsh() {
  _fn=$1
  _orig=$2
  _src=$(whence -f "$_fn" 2>/dev/null) || return 0
  [ -n "$_src" ] || return 0
  _renamed=$(printf '%s\n' "$_src" | sed "1s/^${_fn} /${_orig} /")
  eval "$_renamed"
  eval "${_fn}() {
    _prev=\$?
    if _dotfiles_mise_hook_is_unchanged \"\$@\"; then
      return \$_prev
    fi
    if [ -n \"\${_DOTFILES_MISE_FP_NEXT:-}\" ]; then
      _DOTFILES_MISE_FP=\$_DOTFILES_MISE_FP_NEXT
    fi
    ${_orig} \"\$@\"
  }"
}

_dotfiles_mise_install_hook_cache() {
  if [ -n "${BASH_VERSION:-}" ]; then
    _dotfiles_mise_wrap_bash _mise_hook _dotfiles_mise_orig_hook
    _dotfiles_mise_wrap_bash _mise_hook_chpwd _dotfiles_mise_orig_hook_chpwd
    _dotfiles_mise_wrap_bash _mise_hook_prompt_command _dotfiles_mise_orig_hook_prompt
  elif [ -n "${ZSH_VERSION:-}" ]; then
    _dotfiles_mise_wrap_zsh _mise_hook _dotfiles_mise_orig_hook
  fi
  _fp=$(_dotfiles_mise_config_fingerprint) || return 0
  _DOTFILES_MISE_FP=$_fp
}

# Cache the activate script text. A hit still prints it for eval, so
# the initial hook-env inside that script still runs.
_dotfiles_mise_activate_cached() {
  _shell=$1
  _ver=$(mise --version 2>/dev/null | awk 'NR == 1 { print; exit }')
  if [ -z "$_ver" ]; then
    mise activate "$_shell" --quiet 2>/dev/null
    return 0
  fi
  _bin=$(command -v mise)
  _mt=$(stat -c %Y "$_bin" 2>/dev/null || printf '%s' nomtime)
  _cfg_hash=noconfig
  if [ -f "${HOME}/.config/mise/config.toml" ]; then
    _cfg_hash=$(_dotfiles_mise_sha256_file "${HOME}/.config/mise/config.toml") || _cfg_hash=unavailable
  fi
  # Only inputs that can change the generated script. Do not hash every
  # MISE_* variable: activate itself exports some, and a second source
  # in the same shell would miss an otherwise valid cache entry.
  _env=$(printf '%s\n' \
    "${MISE_ENV-}" \
    "${MISE_CONFIG_FILE-}" \
    "${MISE_GLOBAL_CONFIG_FILE-}" \
    "${MISE_TRUSTED_CONFIG_PATHS-}" \
    "${MISE_YES-}" \
    "${MISE_QUIET-}")
  _key=$(printf '%s' "${_shell}
${_ver}
${_bin}
${_mt}
${_cfg_hash}
${_env}" | _dotfiles_mise_sha256_stdin) || _key=
  if [ -z "$_key" ]; then
    mise activate "$_shell" --quiet 2>/dev/null
    return 0
  fi
  if [ -n "${DOTFILES_MISE_ACTIVATE_CACHE:-}" ]; then
    _cache_dir=$DOTFILES_MISE_ACTIVATE_CACHE
  else
    _cache_dir=${HOME}/.cache/dotfiles
  fi
  _cache_file="${_cache_dir}/mise-activate-${_shell}-${_key}.sh"
  if [ -s "$_cache_file" ]; then
    cat "$_cache_file"
    return 0
  fi
  _out=$(mise activate "$_shell" --quiet 2>/dev/null)
  _st=$?
  if [ "$_st" -ne 0 ] || [ -z "$_out" ]; then
    [ -n "$_out" ] && printf '%s\n' "$_out"
    return 0
  fi
  mkdir -p "$_cache_dir" || {
    printf '%s\n' "$_out"
    return 0
  }
  chmod 700 "$_cache_dir" 2>/dev/null || true
  _tmp="${_cache_file}.tmp.$$"
  printf '%s\n' "$_out" > "$_tmp" || {
    printf '%s\n' "$_out"
    return 0
  }
  mv "$_tmp" "$_cache_file"
  printf '%s\n' "$_out"
}

# Build trusted config paths so hooks never show trust errors
_mise_trusted="${HOME}/.mise:${HOME}/.config/mise"

# WSL: include Windows-side config directories (visible via /mnt/c/).
# The root is overridable via DOTFILES_MISE_WSL_USERS_ROOT (test-isolation
# hook, mirroring the HOME override above) so tests never depend on the
# real host's Windows-side filesystem contents.
_mise_win_users="${DOTFILES_MISE_WSL_USERS_ROOT:-/mnt/c/Users}"
if _dotfiles_mise_is_wsl; then
  for _mise_dir in "${_mise_win_users}"/*/.mise "${_mise_win_users}"/*/.config/mise; do
    [ -d "${_mise_dir}" ] 2>/dev/null && _mise_trusted="${_mise_trusted}:${_mise_dir}"
  done
fi

# Append ghq-cloned owner directories opted in via mise_trust in chezmoi
_ghq_trust_file="${HOME}/.config/mise/chezmoi-ghq-trusted-paths"
if [ -f "${_ghq_trust_file}" ] && command -v ghq >/dev/null 2>&1; then
  _ghq_root="$(ghq root 2>/dev/null)"
  if [ -n "${_ghq_root}" ]; then
    while IFS= read -r _pair || [ -n "${_pair}" ]; do
      [ -n "${_pair}" ] && _mise_trusted="${_mise_trusted}:${_ghq_root}/${_pair}"
    done < "${_ghq_trust_file}"
  fi
fi
unset _ghq_trust_file _ghq_root _pair

export MISE_TRUSTED_CONFIG_PATHS="${_mise_trusted}"
unset _mise_trusted _mise_dir

# Also run mise trust for persistence across sessions
for _mise_cfg in \
  "${HOME}/.mise/config.toml" \
  "${HOME}/.config/mise/config.toml"; do
  _dotfiles_mise_trust_if_needed "${_mise_cfg}"
done

# WSL: also trust Windows-side configs visible via /mnt/c/ (same
# overridable root as the trusted-paths block above).
if _dotfiles_mise_is_wsl; then
  for _mise_cfg in \
    "${_mise_win_users}"/*/.mise/config.toml \
    "${_mise_win_users}"/*/.config/mise/config.toml; do
    _dotfiles_mise_trust_if_needed "${_mise_cfg}"
  done
fi
unset _mise_cfg _mise_win_users

if [ -n "${ZSH_VERSION:-}" ]; then
  if _dotfiles_mise_is_wsl; then
    eval "$(_dotfiles_mise_activate_cached zsh)" 2>/dev/null
    _dotfiles_mise_install_hook_cache
  else
    eval "$(mise activate zsh --quiet 2>/dev/null)" 2>/dev/null
  fi
elif [ -n "${BASH_VERSION:-}" ]; then
  if _dotfiles_mise_is_wsl; then
    eval "$(_dotfiles_mise_activate_cached bash)" 2>/dev/null
    _dotfiles_mise_install_hook_cache
  else
    eval "$(mise activate bash --quiet 2>/dev/null)" 2>/dev/null
  fi
fi
