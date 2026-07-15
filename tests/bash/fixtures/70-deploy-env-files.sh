#!/bin/bash
# Pre-rendered test fixture for run_onchange_after_70-deploy-env-files.sh.tmpl.
# Contains one hardcoded entry:
#   sample-project – deploys to <ghq root>/github.com/user/sample-project/.env
#
# This script is intentionally NOT a chezmoi template. It simulates
# what chezmoi would render when the following config is present:
#
#   [data.env.deploy.sample-project]
#   repo = "github.com/user/sample-project"
#   item = "i"
set -euo pipefail

# See run_after_99-secret-status-summary.sh.tmpl for rationale.
exec </dev/null

command -v mise &>/dev/null || { echo "mise not found; skipping."; exit 0; }
GHQ="$(mise which ghq 2>/dev/null)" || { echo "ghq not found via mise; skipping."; exit 0; }
GHQ_ROOT="$("${GHQ}" root 2>/dev/null)" || { echo "ghq root failed; skipping."; exit 0; }

deploy_state="${HOME}/.local/bin/secret-deploy-state"
record_state() {
  # See run_once_before_20-deploy-ssh-keys.sh.tmpl for the rationale
  # behind closing stdin on the helper invocation.
  [ -x "${deploy_state}" ] || return 0
  "${deploy_state}" record "$1" "$2" "$3" </dev/null || true
}

echo "==> sample-project: github.com/user/sample-project/.env"

target_dir="${GHQ_ROOT}/github.com/user/sample-project"
target_path="${target_dir}/.env"

if [ ! -d "${target_dir}" ]; then
  echo "  skip: directory not found"
else
  # Warn if .gitignore does not list the target filename
  gitignore="${GHQ_ROOT}/github.com/user/sample-project/.gitignore"
  if [ -f "${gitignore}" ]; then
    if ! grep -qxF '.env' "${gitignore}" 2>/dev/null; then
      echo "  warn: .env not found in .gitignore"
    fi
  else
    echo "  warn: .gitignore not found in github.com/user/sample-project"
  fi

  cat > "${target_path}" << 'CHEZMOI_ENV_EOF'
FAKE_SECRET=1
CHEZMOI_ENV_EOF

  chmod 600 "${target_path}"
  echo "  done: deployed (mode 600)"
  record_state envFile "sample-project" "${target_path}"
fi

echo "env deploy complete."
