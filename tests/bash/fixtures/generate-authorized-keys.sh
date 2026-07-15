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

has_valid_block=false
markers_present=false
if [ -f "${authorized}" ]; then
  begin_count=$(grep -cF "${begin_marker}" "${authorized}" || true)
  end_count=$(grep -cF "${end_marker}" "${authorized}" || true)
  if [ "${begin_count}" -gt 0 ] || [ "${end_count}" -gt 0 ]; then
    markers_present=true
  fi
  if [ "${begin_count}" -eq 1 ] && [ "${end_count}" -eq 1 ]; then
    begin_line=$(grep -nF "${begin_marker}" "${authorized}" | cut -d: -f1)
    end_line=$(grep -nF "${end_marker}" "${authorized}" | cut -d: -f1)
    if [ "${begin_line}" -lt "${end_line}" ]; then
      has_valid_block=true
    fi
  fi
fi

if [ "${markers_present}" = true ] && [ "${has_valid_block}" = false ]; then
  echo "  WARNING: malformed managed-key markers found in ${authorized}; appending a fresh block instead of editing in place. Remove the stale/duplicate markers manually to stop new blocks from accumulating."
fi

if [ "${has_valid_block}" = true ]; then
  awk -v begin="${begin_marker}" -v end="${end_marker}" -v keysfile="${managed_keys}" '
    $0 == begin {
      print
      while ((getline line < keysfile) > 0) print line
      in_block = 1
      next
    }
    $0 == end { in_block = 0 }
    !in_block { print }
  ' "${authorized}" > "${new_file}"
else
  if [ -f "${authorized}" ]; then
    cat "${authorized}" > "${new_file}"
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
