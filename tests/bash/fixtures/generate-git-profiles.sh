#!/bin/bash
# Pre-rendered test fixture for generate-git-profiles.sh.tmpl.
# Contains two hardcoded profiles:
#   personal  – name and email only (no GPG)
#   work      – name, email, and GPG signingkey
#
# This script is intentionally NOT a chezmoi template.
# It simulates what chezmoi would render when the following config
# is present in chezmoi.toml:
#
#   [data.git.profiles.personal]
#     name  = "Personal User"
#     email = "personal@example.com"
#   [data.git.profiles.work]
#     name       = "Work User"
#     email      = "work@example.com"
#     signingkey = "ABCD1234ABCD1234"
set -euo pipefail

profiles_dir="${HOME}/.config/git/profiles"
mkdir -p "${profiles_dir}"

cat > "${profiles_dir}/personal" << 'PROFILE_EOF'
[user]
  email = "personal@example.com"
  name = "Personal User"
PROFILE_EOF

cat > "${profiles_dir}/work" << 'PROFILE_EOF'
[user]
  email = "work@example.com"
  name = "Work User"
  signingkey = "ABCD1234ABCD1234"
[commit]
  gpgsign = true
[tag]
  forceSignAnnotated = true
  gpgsign = true
PROFILE_EOF

# Remove orphaned profile files
for f in "${profiles_dir}"/*; do
  [[ -f "${f}" ]] || continue
  case "$(basename "${f}")" in
    personal) ;;
    work) ;;
    *) rm -f "${f}" ;;
  esac
done
