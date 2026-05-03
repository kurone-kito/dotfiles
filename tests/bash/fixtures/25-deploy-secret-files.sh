#!/bin/bash
# Pre-rendered test fixture for run_onchange_after_25-deploy-secret-files.sh.tmpl.
# Contains two hardcoded entries:
#   aws-credentials – deploys to .aws/credentials
#   docker-auth     – deploys to .docker/config.json
#
# This script is intentionally NOT a chezmoi template.
# It simulates what chezmoi would render when the following config
# is present in chezmoi.toml:
#
#   [data.secret]
#   manager = "bitwarden"
#
#   [data.secret.files.aws-credentials]
#   item = "AWS Credentials"
#   target = ".aws/credentials"
#   attachment = "credentials"
#
#   [data.secret.files.docker-auth]
#   item = "Docker Registry Auth"
#   target = ".docker/config.json"
#   attachment = "config.json"
set -euo pipefail

# See run_after_99-secret-status-summary.sh.tmpl for rationale.
exec </dev/null

deploy_state="${HOME}/.local/bin/secret-deploy-state"
record_state() {
  # See run_once_before_20-deploy-ssh-keys.sh.tmpl for the rationale
  # behind closing stdin on the helper invocation.
  [ -x "${deploy_state}" ] || return 0
  "${deploy_state}" record "$1" "$2" "$3" </dev/null || true
}

echo "==> aws-credentials: ~/.aws/credentials"

target_path="${HOME}/.aws/credentials"
target_dir="$(dirname "${target_path}")"

(umask 077 && mkdir -p "${target_dir}")

cat > "${target_path}" << 'CHEZMOI_SECRET_EOF'
[default]
aws_access_key_id = AKIAEXAMPLE
aws_secret_access_key = wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
CHEZMOI_SECRET_EOF

chmod 600 "${target_path}"
echo "  done: deployed (mode 600)"
record_state secretFile aws-credentials "${target_path}"

echo "==> docker-auth: ~/.docker/config.json"

target_path="${HOME}/.docker/config.json"
target_dir="$(dirname "${target_path}")"

(umask 077 && mkdir -p "${target_dir}")

cat > "${target_path}" << 'CHEZMOI_SECRET_EOF'
{"auths":{"registry.example.com":{"auth":"dXNlcjpwYXNz"}}}
CHEZMOI_SECRET_EOF

chmod 600 "${target_path}"
echo "  done: deployed (mode 600)"
record_state secretFile docker-auth "${target_path}"

echo "secret file deploy complete."
