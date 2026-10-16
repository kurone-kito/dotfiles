#!/bin/bash
# chezmoi run_after script: bridge the vendored IDD payload data root to a
# customized XDG_DATA_HOME.
#
# idd-skill resolves its installed payload at $XDG_DATA_HOME/idd-skill, falling
# back to $HOME/.local/share/idd-skill only when XDG_DATA_HOME is unset or is not
# a qualified root (on POSIX, an absolute path that does not start with //, after
# surrounding whitespace is removed). chezmoi's own dot_local/share source-path
# convention always deploys home/dot_local/share/idd-skill to the fixed
# $HOME/.local/share location, so a custom XDG_DATA_HOME would otherwise never
# see the vendored payload at all. This script links $XDG_DATA_HOME/idd-skill to
# that deployed tree when the root differs from ~/.local/share. Runs every apply
# (not run_once/run_onchange) since it only depends on the current process
# environment, not chezmoi source content.
#
# The link sits at the installer's own data-root path. The installer refuses to
# write through a symlinked data root, so a later installer run under this custom
# root is refused. That run is out of scope here (see #648 and #649).
set -euo pipefail

exec </dev/null

default_data_home="${HOME}/.local/share"
rendered="${default_data_home}/idd-skill"

# The physical (symlink-resolved) form of a path. The longest existing ancestor
# is resolved, and the components below it are appended, so an alias that
# points into the deployed tree is seen through even when the root itself does
# not exist yet.
# Lexical normalization of an absolute path: "." is dropped and ".." removes the
# component before it. It is applied only past the resolved existing prefix, so
# a ".." never climbs through a link the walk has already resolved.
normalize_lexically() {
  local path="$1" out="" comp
  set -f
  local IFS=/
  for comp in ${path}; do
    case "${comp}" in
      ''|.) ;;
      ..) out="${out%/*}" ;;
      *) out="${out}/${comp}" ;;
    esac
  done
  set +f
  if [ -n "${out}" ]; then
    printf '%s' "${out}"
  else
    printf '/'
  fi
}

physical_path() {
  local p="$1" tail="" dir
  while [ ! -d "${p}" ]; do
    # A link that does not resolve to a directory cannot be followed here, so the
    # path cannot be shown to be outside the payload. Fail closed: the caller refuses.
    if [ -L "${p}" ]; then
      return 1
    fi
    tail="/$(basename "${p}")${tail}"
    p="$(dirname "${p}")"
  done
  # A ".." below the existing prefix depends on components that do not exist, so it
  # cannot be resolved the way the OS would resolve it later. Fail closed.
  case "${tail}/" in
    */../*) return 1 ;;
  esac
  dir="$(cd -P "${p}" 2>/dev/null && pwd -P)" || return 1
  normalize_lexically "${dir}${tail}"
}

# Trim surrounding whitespace, then keep only a qualified root (the rule of
# isQualifiedConfigRoot in upstream src/scripts/idd-config.mts). The trailing
# slash strip mirrors the installer's path normalization, but it keeps a lone
# "/" as it is, so a filesystem-root setting is qualified here as it is upstream.
xdg_trimmed="$(printf '%s' "${XDG_DATA_HOME:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
case "${xdg_trimmed}" in
  /*) ;;
  *) exit 0 ;;
esac
case "${xdg_trimmed}" in
  //*) exit 0 ;;
esac
xdg_data_home="$(printf '%s' "${xdg_trimmed}" | sed -e 's#\(.\)/*$#\1#')"

if [ ! -d "${rendered}" ]; then
  exit 0
fi

# True when the path, or one of its ancestors, is the same directory as ref. Two
# spellings that name one directory (a case-insensitive filesystem, a bind mount)
# have the same inode, which -ef compares.
is_same_or_inside() {
  local p="$1" ref="$2"
  while :; do
    if [ -e "${p}" ] && [ "${p}" -ef "${ref}" ]; then
      return 0
    fi
    if [ "${p}" = "/" ]; then
      return 1
    fi
    p="$(dirname "${p}")"
  done
}

# Refuse when the root is the default directory, or is the deployed tree or
# something inside it, under any alias. Comparing physical paths covers both
# plain spellings and symlinks; a link there would point back into the payload.
rendered_physical="$(physical_path "${rendered}")"
xdg_physical="$(physical_path "${xdg_data_home}")" || {
  echo "idd-skill data: ${xdg_data_home} cannot be resolved safely (a dangling link, or a '..' below a missing path); not linking." >&2
  exit 0
}
default_physical="$(physical_path "${default_data_home}")" || exit 0
if [ "${xdg_physical}" = "${default_physical}" ]; then
  exit 0
fi
if [ -e "${xdg_physical}" ] && [ "${xdg_physical}" -ef "${default_data_home}" ]; then
  exit 0
fi
case "${xdg_physical}/" in
  "${rendered_physical}/"*) exit 0 ;;
esac
if is_same_or_inside "${xdg_physical}" "${rendered}"; then
  exit 0
fi

target="${xdg_data_home%/}/idd-skill"

if [ -L "${target}" ]; then
  if [ "$(readlink "${target}")" = "${rendered}" ] || [ "${target}" -ef "${rendered}" ]; then
    exit 0
  fi
  echo "idd-skill data: ${target} is a symlink to a different target; not overwriting." >&2
  exit 0
fi

if [ -e "${target}" ]; then
  echo "idd-skill data: ${target} already exists and is not a symlink; not overwriting." >&2
  exit 0
fi

mkdir -p "${xdg_data_home}"
ln -s "${rendered}" "${target}"
echo "idd-skill data: linked ${target} -> ${rendered}"
