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

# Trim surrounding whitespace, then keep only a qualified root (the rule of
# isQualifiedConfigRoot in upstream src/scripts/idd-config.mts). The trailing
# slash strip mirrors the installer's path normalization, so an equal path
# compares equal to the default below. It also turns a bare "/" into an empty
# value, which is refused here; the installer would accept it, but a data root at
# the filesystem root is not a practical case.
xdg_data_home="$(printf '%s' "${XDG_DATA_HOME:-}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's#/*$##')"
case "${xdg_data_home}" in
  /*) ;;
  *) exit 0 ;;
esac
case "${xdg_data_home}" in
  //*) exit 0 ;;
esac

# The same directory as the deployed default (a string match, or the same file
# through a link), so there is nothing to bridge.
if [ "${xdg_data_home}" = "${default_data_home}" ] || [ "${xdg_data_home}" -ef "${default_data_home}" ]; then
  exit 0
fi

# Inside the deployed tree itself: a link there would point back at its own parent.
case "${xdg_data_home}/" in
  "${rendered}/"*) exit 0 ;;
esac

if [ ! -d "${rendered}" ]; then
  exit 0
fi

target="${xdg_data_home}/idd-skill"

if [ -L "${target}" ]; then
  if [ "${target}" -ef "${rendered}" ] || [ "$(readlink "${target}")" = "${rendered}" ]; then
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
