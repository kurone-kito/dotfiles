#!/bin/bash
# Pre-rendered test fixture for generate-authorized-keys.sh.tmpl.
# Contains two hardcoded public key names:
#   primary.pub   - included when present
#   secondary.pub - included when present
#
# This script is intentionally NOT a chezmoi template. It simulates
# what chezmoi would render when two SSH keys named "primary" and
# "secondary" are configured under data.secret.ssh.keys.
set -euo pipefail

ssh_dir="${HOME}/.ssh"
authorized="${ssh_dir}/authorized_keys"
begin_marker="# >>> chezmoi managed keys >>>"
end_marker="# <<< chezmoi managed keys <<<"

mkdir -p "${ssh_dir}"
chmod 700 "${ssh_dir}"

managed_keys="$(mktemp "${ssh_dir}/.authorized_keys.tmp.XXXXXX")"
new_file="$(mktemp "${ssh_dir}/.authorized_keys.tmp.XXXXXX")"
trap 'rm -f "${managed_keys}" "${new_file}"' EXIT

for name in primary secondary; do
  pubfile="${ssh_dir}/${name}.pub"
  if [ -f "${pubfile}" ]; then
    cat "${pubfile}" >> "${managed_keys}"
    echo "" >> "${managed_keys}"
    echo "  Added ${name}.pub"
  else
    echo "  Skipped ${name}.pub (not found)"
  fi
done

if [ ! -s "${managed_keys}" ]; then
  echo "  WARNING: no public keys were found; managed block will be empty."
fi

begin_count=0
end_count=0
if [ -f "${authorized}" ]; then
  begin_count=$(grep -cFx "${begin_marker}" "${authorized}" || true)
  end_count=$(grep -cFx "${end_marker}" "${authorized}" || true)
fi

markers_present=false
if [ "${begin_count}" -gt 0 ] || [ "${end_count}" -gt 0 ]; then
  markers_present=true
fi

block_shape_ok=false
if [ "${begin_count}" -eq 1 ] && [ "${end_count}" -eq 1 ]; then
  block_shape_ok=true
fi

begin_line=""
end_line=""
if [ -f "${authorized}" ]; then
  begin_line=$(grep -nFx "${begin_marker}" "${authorized}" | tail -1 | cut -d: -f1 || true)
  if [ -n "${begin_line}" ]; then
    end_line=$(awk -v b="${begin_line}" -v end="${end_marker}" 'NR > b && $0 == end { print NR; exit }' "${authorized}")
  fi
fi
has_valid_block=false
if [ -n "${begin_line}" ] && [ -n "${end_line}" ]; then
  has_valid_block=true
fi

if [ "${markers_present}" = true ] && [ "${block_shape_ok}" = false ]; then
  echo "  WARNING: malformed managed-key markers found in ${authorized}; remove the stale/duplicate markers manually. A valid block will be updated in place if one can be found, otherwise a fresh block is appended."
fi

if [ "${has_valid_block}" = true ]; then
  awk -v begin_line="${begin_line}" -v end="${end_marker}" -v keysfile="${managed_keys}" '
    NR == begin_line {
      print
      while ((getline line < keysfile) > 0) print line
      in_block = 1
      next
    }
    in_block && $0 == end {
      print
      in_block = 0
      next
    }
    in_block { next }
    { print }
  ' "${authorized}" > "${new_file}"
else
  if [ -f "${authorized}" ]; then
    if [ -s "${managed_keys}" ]; then
      non_empty_managed_keys="$(mktemp "${ssh_dir}/.authorized_keys.tmp.XXXXXX")"
      trap 'rm -f "${managed_keys}" "${new_file}" "${non_empty_managed_keys}"' EXIT
      grep -v '^$' "${managed_keys}" > "${non_empty_managed_keys}" || true
      grep -vFxf "${non_empty_managed_keys}" "${authorized}" > "${new_file}" || true
    else
      cat "${authorized}" > "${new_file}"
    fi
    if [ -s "${new_file}" ] && [ "$(tail -c1 "${new_file}")" != "" ]; then
      printf '\n' >> "${new_file}"
    fi
  else
    : > "${new_file}"
  fi
  {
    echo "${begin_marker}"
    cat "${managed_keys}"
    echo "${end_marker}"
  } >> "${new_file}"
fi

mv "${new_file}" "${authorized}"
chmod 600 "${authorized}"
echo "authorized_keys generated."
