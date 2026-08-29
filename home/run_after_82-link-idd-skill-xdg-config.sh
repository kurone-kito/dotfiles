#!/bin/bash
# chezmoi run_after script: bridge the rendered IDD critique-delegate
# config to a customized XDG_CONFIG_HOME.
#
# idd-skill resolves this file at $XDG_CONFIG_HOME/idd-skill/config.json,
# falling back to $HOME/.config/idd-skill/config.json only when
# XDG_CONFIG_HOME is unset. chezmoi's own dot_config source-path
# convention always deploys home/dot_config/idd-skill/config.json.tmpl to
# the fixed $HOME/.config location regardless of a customized
# XDG_CONFIG_HOME (home/dot_config/shell/conf.d/00-xdg.sh preserves an
# existing custom value rather than overriding it), so a custom
# XDG_CONFIG_HOME would otherwise never see the delegate config at all.
# Runs every apply (not run_once/run_onchange) since it only depends on
# the current process environment, not chezmoi source content.
set -euo pipefail

exec </dev/null

xdg_config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
rendered="${HOME}/.config/idd-skill/config.json"

if [ "${xdg_config_home}" = "${HOME}/.config" ]; then
  exit 0
fi

if [ ! -f "${rendered}" ]; then
  exit 0
fi

target_dir="${xdg_config_home}/idd-skill"
target="${target_dir}/config.json"

if [ -L "${target}" ]; then
  if [ "$(readlink "${target}")" = "${rendered}" ]; then
    exit 0
  fi
  echo "idd-skill config: ${target} is a symlink to a different target; not overwriting." >&2
  exit 0
fi

if [ -e "${target}" ]; then
  echo "idd-skill config: ${target} already exists and is not a symlink; not overwriting." >&2
  exit 0
fi

mkdir -p "${target_dir}"
ln -sf "${rendered}" "${target}"
echo "idd-skill config: linked ${target} -> ${rendered}"
