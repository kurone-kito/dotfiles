#!/bin/sh
# mise (polyglot runtime manager) initialization
# https://mise.jdx.dev/
# Requires: mise installed via Homebrew, curl, or package manager

command -v mise >/dev/null 2>&1 || return 0

# This file is sourced into the caller's shell (bash or zsh). Every helper
# that can run there declares the scratch names it assigns `local`, and
# assigns them on a line of their own so a `$(...)` status is not masked.
# Helpers that only ever run inside `$(...)` keep plain names: their
# assignments die with the subshell. The `_DOTFILES_MISE_*` globals and
# `_dotfiles_mise_hook_out` are deliberate state shared between calls.

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

# Print the mtime of the trust directory in $1, or `missing`.
_dotfiles_mise_trust_dir_mtime() {
  if [ -d "$1" ]; then
    stat -c %Y "$1" 2>/dev/null && return 0
  fi
  printf '%s\n' missing
}

# Skip mise trust only when this exact path and content were trusted
# while the same trust directory was unchanged. A row is
# path, hash, size, directory, mtime; an older row without the
# directory never matches. Any miss falls open.
# The path, hash and directory reach awk through the environment: -v
# would expand a backslash and never match the raw stamp text. The hash
# needs it too: sha256sum prefixes it with a backslash when the file
# name contains one.
_dotfiles_mise_trust_if_needed() {
  local _cfg _hash _size _mtime _stamp _tmp _trust_dir
  _cfg=$1
  [ -f "$_cfg" ] || return 0
  if ! _dotfiles_mise_is_wsl; then
    mise trust "$_cfg" 2>/dev/null || true
    return 0
  fi
  _trust_dir="${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}/trusted-configs"
  _hash=$(_dotfiles_mise_sha256_file "$_cfg") || _hash=
  _size=$(wc -c < "$_cfg" | tr -d '[:space:]')
  _mtime=$(_dotfiles_mise_trust_dir_mtime "$_trust_dir")
  _stamp=$(_dotfiles_mise_trust_stamp_file)
  if [ -n "$_hash" ] && [ -f "$_stamp" ]; then
    if DOTFILES_MISE_STAMP_PATH=$_cfg DOTFILES_MISE_STAMP_HASH=$_hash \
      DOTFILES_MISE_STAMP_DIR=$_trust_dir \
      awk -F '\t' -v s="$_size" -v m="$_mtime" '
        $1 == ENVIRON["DOTFILES_MISE_STAMP_PATH"] &&
          $2 == ENVIRON["DOTFILES_MISE_STAMP_HASH"] && $3 == s &&
          $4 == ENVIRON["DOTFILES_MISE_STAMP_DIR"] && $5 == m { found = 1 }
        END { exit found ? 0 : 1 }' \
      "$_stamp"; then
      return 0
    fi
  fi
  if ! mise trust "$_cfg" 2>/dev/null; then
    return 0
  fi
  [ -n "$_hash" ] || return 0
  _mtime=$(_dotfiles_mise_trust_dir_mtime "$_trust_dir")
  mkdir -p "$(dirname "$_stamp")" || return 0
  _tmp="${_stamp}.tmp.$$"
  if [ -f "$_stamp" ]; then
    DOTFILES_MISE_STAMP_PATH=$_cfg \
      awk -F '\t' '$1 != ENVIRON["DOTFILES_MISE_STAMP_PATH"] { print }' \
      "$_stamp" > "$_tmp" || true
  else
    : > "$_tmp"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$_cfg" "$_hash" "$_size" "$_trust_dir" "$_mtime" >> "$_tmp"
  mv "$_tmp" "$_stamp"
}

# In-memory identity of the configs hook-env would read. A hash failure
# prints HASH_FAIL so the caller refuses to skip.
_dotfiles_mise_fp_add_file() {
  local _file_hash
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
  # The path alone misses an in-place edit of an explicit config file
  # that the directory walk does not already name.
  printf 'config_file\t%s\n' "${MISE_CONFIG_FILE-}"
  if [ -n "${MISE_CONFIG_FILE:-}" ]; then
    case $MISE_CONFIG_FILE in
      /*) ;;
      *) printf '%s\n' NEED_PWD ;;
    esac
    _dotfiles_mise_fp_add_file "$MISE_CONFIG_FILE"
  fi
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
      mise/config.toml .config/mise.toml .config/mise/mise.toml \
      .config/mise/config.toml .config/mise/config.local.toml \
      mise/config.local.toml .config/mise.local.toml \
      .config/mise/mise.local.toml \
      .mise/config.toml .mise/config.local.toml \
      .tool-versions .node-version .nvmrc .python-version \
      .ruby-version .go-version .java-version .bun-version \
      .terraform-version; do
      _dotfiles_mise_fp_add_file "${_dir}/${_name}"
    done
    case ${MISE_ENV-} in
      "" | *[!A-Za-z0-9_-]*) ;;
      *)
        _dotfiles_mise_fp_add_file "${_dir}/mise.${MISE_ENV}.toml"
        _dotfiles_mise_fp_add_file "${_dir}/.mise.${MISE_ENV}.toml"
        _dotfiles_mise_fp_add_file "${_dir}/.config/mise/config.${MISE_ENV}.toml"
        ;;
    esac
    for _confd in \
      "${_dir}/.config/mise/conf.d" \
      "${_dir}/mise/conf.d" \
      "${_dir}/.mise/conf.d"; do
      if [ -d "$_confd" ]; then
        for _conf in "$_confd"/*; do
          _dotfiles_mise_fp_add_file "$_conf"
        done
      fi
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
  local _fp
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

# Run one hook-env command and record its status. Bash activate returns
# the prompt's previous status, so a failed hook-env is invisible there.
# Leave a failed run unevaluated; the caller then retries next time.
_dotfiles_mise_eval_hook_env() {
  _dotfiles_mise_hook_out=$("$@") && _DOTFILES_MISE_HOOK_STATUS=0 \
    || _DOTFILES_MISE_HOOK_STATUS=$?
  if [ "$_DOTFILES_MISE_HOOK_STATUS" -eq 0 ]; then
    eval "$_dotfiles_mise_hook_out"
  fi
  return 0
}

# `eval "$(… hook-env …)"` hides the command status. Rewrite that call
# into _dotfiles_mise_eval_hook_env so the wrapper can see it.
_dotfiles_mise_rewrite_hook_env() {
  sed -e 's/eval "\$(\(.*hook-env.*\))";\{0,1\}/_dotfiles_mise_eval_hook_env \1/'
}

# Remember the fingerprint only after hook-env succeeds. A hook that
# does not report status (the test double) still advances it.
_dotfiles_mise_commit_fp_after_hook() {
  if [ "${_DOTFILES_MISE_HOOK_STATUS+x}" = x ]; then
    if [ "$_DOTFILES_MISE_HOOK_STATUS" -eq 0 ] \
      && [ -n "${_DOTFILES_MISE_FP_NEXT:-}" ]; then
      _DOTFILES_MISE_FP=$_DOTFILES_MISE_FP_NEXT
    fi
  elif [ -n "${_DOTFILES_MISE_FP_NEXT:-}" ]; then
    _DOTFILES_MISE_FP=$_DOTFILES_MISE_FP_NEXT
  fi
}

_dotfiles_mise_wrap_bash() {
  local _fn _orig
  _fn=$1
  _orig=$2
  declare -F "$_fn" >/dev/null 2>&1 || return 0
  # Keep the saved exit status visible to the original function. Its
  # first line reads $?, which would otherwise be the fingerprint check.
  eval "$(declare -f "$_fn" \
    | sed -e "1s/^${_fn} /${_orig} /" \
      -e 's/previous_exit_status=\$?/previous_exit_status=${_DOTFILES_MISE_PREV:-$?}/' \
    | _dotfiles_mise_rewrite_hook_env)"
  eval "${_fn}() {
    _DOTFILES_MISE_PREV=\$?
    if _dotfiles_mise_hook_is_unchanged \"\$@\"; then
      if [ \"${_fn}\" = _mise_hook_prompt_command ]; then
        __MISE_BASH_CHPWD_RAN=0
        unset __MISE_BASH_SKIP_FIRST_PROMPT
      fi
      return \$_DOTFILES_MISE_PREV
    fi
    # A stale chpwd flag would make the original prompt hook return
    # before applying a same-directory config change.
    if [ \"${_fn}\" = _mise_hook_prompt_command ]; then
      __MISE_BASH_CHPWD_RAN=0
      unset __MISE_BASH_SKIP_FIRST_PROMPT
    fi
    unset _DOTFILES_MISE_HOOK_STATUS
    ${_orig} \"\$@\"
    _dotfiles_mise_commit_fp_after_hook
  }"
}

_dotfiles_mise_wrap_zsh() {
  local _fn _orig _src _renamed
  _fn=$1
  _orig=$2
  _src=$(whence -f "$_fn" 2>/dev/null) || return 0
  [ -n "$_src" ] || return 0
  _renamed=$(printf '%s\n' "$_src" \
    | sed "1s/^${_fn} /${_orig} /" \
    | _dotfiles_mise_rewrite_hook_env)
  eval "$_renamed"
  # The status is read on the declaration line: a bare `local _prev`
  # first would reset `$?` to 0 before the wrapper could return it.
  eval "${_fn}() {
    local _prev=\$?
    if _dotfiles_mise_hook_is_unchanged \"\$@\"; then
      return \$_prev
    fi
    unset _DOTFILES_MISE_HOOK_STATUS
    ${_orig} \"\$@\"
    _dotfiles_mise_commit_fp_after_hook
  }"
}

_dotfiles_mise_install_hook_cache() {
  local _fp
  if [ -n "${BASH_VERSION:-}" ]; then
    _dotfiles_mise_wrap_bash _mise_hook _dotfiles_mise_orig_hook
    _dotfiles_mise_wrap_bash _mise_hook_chpwd _dotfiles_mise_orig_hook_chpwd
    _dotfiles_mise_wrap_bash _mise_hook_prompt_command _dotfiles_mise_orig_hook_prompt
  elif [ -n "${ZSH_VERSION:-}" ]; then
    _dotfiles_mise_wrap_zsh _mise_hook _dotfiles_mise_orig_hook
  fi
  # A deferred activation hook records the fingerprint itself, and only
  # after hook-env succeeds. Stamping it here would hide that failure.
  if [ "${1:-}" = "--defer-fingerprint" ]; then
    return 0
  fi
  _fp=$(_dotfiles_mise_config_fingerprint) || return 0
  _DOTFILES_MISE_FP=$_fp
}

# Split `_mise_hook --force` out of a generated activate script.
# That call runs before these wrappers exist. Bash's hook returns the
# previous status, so a failed hook-env is invisible and a later prompt
# would skip the retry. The flag stays inside mise's own guard. Lines
# after the call (zsh records PATH there) are printed after the marker
# and run only once the wrapped hook has finished.
_dotfiles_mise_split_activation_hook() {
  awk '
    function is_force(line) {
      return line ~ /^[ \t]*_mise_hook[ \t]+--force[ \t]*;?[ \t]*$/
    }
    function is_closer(line) {
      if (line ~ /^[ \t]*$/) return 1
      if (line ~ /^[ \t]*#/) return 1
      if (line ~ /^[ \t]*(fi|done|esac|})[ \t]*(#.*)?$/) return 1
      return 0
    }
    { lines[++n] = $0 }
    END {
      force = 0
      for (i = 1; i <= n; i++) {
        if (is_force(lines[i])) {
          force = i
          break
        }
      }
      if (force == 0) {
        for (i = 1; i <= n; i++) print lines[i]
        exit
      }
      for (i = 1; i < force; i++) print lines[i]
      print "_DOTFILES_MISE_DEFER_FORCE=1"
      j = force + 1
      while (j <= n && is_closer(lines[j])) {
        print lines[j]
        j++
      }
      print "%%dotfiles-mise-activation-split%%"
      for (i = j; i <= n; i++) print lines[i]
    }
  '
}

_dotfiles_mise_run_activation_hook() {
  if [ -n "${BASH_VERSION:-}" ]; then
    declare -F _mise_hook >/dev/null 2>&1 || return 0
  elif [ -n "${ZSH_VERSION:-}" ]; then
    whence -f _mise_hook >/dev/null 2>&1 || return 0
  else
    return 0
  fi
  _mise_hook --force
}

# Eval a cached activate script, then record the fingerprint only when
# its startup hook-env succeeds. Scripts with no force hook keep the
# previous stamp so an unchanged directory can still skip.
_dotfiles_mise_activate_wsl() {
  local _shell _split _marker _suffix _immediate
  _shell=$1
  _split=$(
    _dotfiles_mise_activate_cached "$_shell" \
      | _dotfiles_mise_split_activation_hook
  )
  _marker='%%dotfiles-mise-activation-split%%'
  _suffix=
  _immediate=$_split
  case "$_split" in
    *"$_marker"*)
      _immediate=${_split%%"$_marker"*}
      _suffix=${_split#*"$_marker"}
      ;;
  esac
  unset _DOTFILES_MISE_DEFER_FORCE
  eval "$_immediate" 2>/dev/null
  if [ "${_DOTFILES_MISE_DEFER_FORCE:-}" = 1 ]; then
    unset _DOTFILES_MISE_DEFER_FORCE
    _dotfiles_mise_install_hook_cache --defer-fingerprint
    _dotfiles_mise_run_activation_hook
  else
    _dotfiles_mise_install_hook_cache
  fi
  eval "$_suffix" 2>/dev/null
}

# Drop frozen PATH snapshots from `mise activate`. Replaying a literal
# assignment would reset PATH to the shell that filled the cache.
# `activate_shims` emits that snapshot with shim directories first;
# rewrite only that prefix into a live prepend, after capturing
# __MISE_ORIG_PATH from this shell. Assignments that already reference
# $PATH (shim mode, or the mise executable directory) stay as written.
_dotfiles_mise_strip_frozen_path() {
  DOTFILES_MISE_SHIM_DIRS=$(
    _data=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}
    printf '%s\n' \
      "${MISE_SHIMS_DIR:-$_data/shims}" \
      "${MISE_SYSTEM_SHIMS_DIR:-${MISE_SYSTEM_DATA_DIR:-/usr/local/share/mise}/shims}" \
      "${HOME}/.local/share/mise/shims"
  ) awk -v q="'" '
    function is_known_shim(entry,    i, e) {
      e = entry
      sub(/\/+$/, "", e)
      if (e ~ /(^|\/)mise\/shims$/) return 1
      for (i = 1; i <= known_n; i++) if (e == known[i]) return 1
      return 0
    }
    function dquote(s,    out, i, c, n) {
      out = ""
      n = length(s)
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (c == "\\" || c == "\"" || c == "`" || c == "$") out = out "\\"
        out = out c
      }
      return out
    }
    function unquote_sq(s,    out, i, c, n, esc) {
      if (substr(s, 1, 1) != q) return ""
      esc = q "\\" q q
      out = ""
      n = length(s)
      i = 2
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == q) {
          if (substr(s, i, 4) == esc) {
            out = out q
            i += 4
            continue
          }
          return out
        }
        out = out c
        i++
      }
      return out
    }
    function leading_shims(value,    n, i, parts, prefix, count, entry) {
      n = split(value, parts, ":")
      prefix = ""
      count = 0
      for (i = 1; i <= n; i++) {
        entry = parts[i]
        sub(/\/+$/, "", entry)
        if (!is_known_shim(entry)) break
        if (count > 0) prefix = prefix ":"
        prefix = prefix entry
        count++
      }
      if (count == 0) return ""
      return prefix
    }
    BEGIN {
      known_n = split(ENVIRON["DOTFILES_MISE_SHIM_DIRS"], _raw, "\n")
      known_n_out = 0
      for (i = 1; i <= known_n; i++) {
        if (_raw[i] == "") continue
        known_n_out++
        known[known_n_out] = _raw[i]
        sub(/\/+$/, "", known[known_n_out])
      }
      known_n = known_n_out
    }
    $0 ~ /^export PATH=/ {
      rest = substr($0, length("export PATH=") + 1)
      if (rest ~ /^"/ && rest ~ /\$(\{PATH\}|PATH)/) {
        print
        next
      }
      value = ""
      if (substr(rest, 1, 1) == q) value = unquote_sq(rest)
      prefix = leading_shims(value)
      if (prefix != "") {
        print "if [ -z \"${__MISE_ORIG_PATH:-}\" ]; then"
        print "export __MISE_ORIG_PATH=\"$PATH\""
        print "fi"
        print "export PATH=\"" dquote(prefix) ":$PATH\""
      }
      next
    }
    $0 ~ /^export __MISE_ORIG_PATH=/ {
      rest = substr($0, length("export __MISE_ORIG_PATH=") + 1)
      if (rest ~ /\$/) print
      next
    }
    { print }
  '
}

# Token for one optional file in the activate-script cache key.
# missing and a hash failure both differ from a real hash, so a new
# or unreadable settings file cannot reuse another shell's script.
_dotfiles_mise_activate_file_token() {
  if [ ! -f "$1" ]; then
    printf '%s\n' missing
    return 0
  fi
  _dotfiles_mise_sha256_file "$1" || printf '%s\n' unavailable
}

# Cache the activate script text. A hit still prints it for eval.
# The caller moves `_mise_hook --force` until after the wrappers exist,
# so the one startup hook-env runs where its status is visible.
_dotfiles_mise_activate_cached() {
  local _shell _ver _bin _mt _cfg_hash _env _key _cache_dir _cache_file
  local _out _tmp
  _shell=$1
  _ver=$(mise --version 2>/dev/null | awk 'NR == 1 { print; exit }')
  if [ -z "$_ver" ]; then
    mise activate "$_shell" --quiet 2>/dev/null
    return 0
  fi
  _bin=$(command -v mise)
  _mt=$(stat -c %Y "$_bin" 2>/dev/null || printf '%s' nomtime)
  # Settings files change the generated script. A path-only key misses
  # an in-place edit of config.local.toml or an explicit config file.
  _cfg_hash=$(
    _dotfiles_mise_activate_file_token "${HOME}/.config/mise/config.toml"
    _dotfiles_mise_activate_file_token "${HOME}/.config/mise/config.local.toml"
    _dotfiles_mise_activate_file_token "${HOME}/.mise/config.toml"
    _dotfiles_mise_activate_file_token "${HOME}/.mise/config.local.toml"
    if [ -n "${MISE_GLOBAL_CONFIG_FILE:-}" ]; then
      _dotfiles_mise_activate_file_token "$MISE_GLOBAL_CONFIG_FILE"
    fi
    if [ -n "${MISE_CONFIG_FILE:-}" ]; then
      _dotfiles_mise_activate_file_token "$MISE_CONFIG_FILE"
    fi
  )
  # Only inputs that can change the generated script. Do not hash every
  # MISE_* variable: activate itself exports some, and a second source
  # in the same shell would miss an otherwise valid cache entry.
  # The last six decide the shim prefix that _dotfiles_mise_strip_frozen_path
  # rewrites, and HOME is the fallback prefix; a shell that changes one of
  # them must not replay the script another shell cached.
  _env=$(printf '%s\n' \
    "${MISE_ENV-}" \
    "${MISE_CONFIG_FILE-}" \
    "${MISE_GLOBAL_CONFIG_FILE-}" \
    "${MISE_TRUSTED_CONFIG_PATHS-}" \
    "${MISE_YES-}" \
    "${MISE_QUIET-}" \
    "${MISE_DATA_DIR-}" \
    "${XDG_DATA_HOME-}" \
    "${HOME-}" \
    "${MISE_SHIMS_DIR-}" \
    "${MISE_SYSTEM_SHIMS_DIR-}" \
    "${MISE_SYSTEM_DATA_DIR-}")
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
  _out=$(printf '%s\n' "$_out" | _dotfiles_mise_strip_frozen_path)
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
    _dotfiles_mise_activate_wsl zsh
  else
    eval "$(mise activate zsh --quiet 2>/dev/null)" 2>/dev/null
  fi
elif [ -n "${BASH_VERSION:-}" ]; then
  if _dotfiles_mise_is_wsl; then
    _dotfiles_mise_activate_wsl bash
  else
    eval "$(mise activate bash --quiet 2>/dev/null)" 2>/dev/null
  fi
fi
