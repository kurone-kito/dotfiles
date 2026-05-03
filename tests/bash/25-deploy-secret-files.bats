#!/usr/bin/env bats
# Tests for the secret file deployment script (25-deploy-secret-files).

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  FIXTURE="$BATS_TEST_DIRNAME/fixtures/25-deploy-secret-files.sh"
  FIXTURE_SKIP="$BATS_TEST_DIRNAME/fixtures/25-deploy-secret-files-skip.sh"
  TEMPLATE="$BATS_TEST_DIRNAME/../../home/run_onchange_after_25-deploy-secret-files.sh.tmpl"

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

# ---------------------------------------------------------------------------
# Template structure — static checks
# ---------------------------------------------------------------------------

@test "template starts with bash shebang" {
  head -1 "$TEMPLATE" | grep -qF '#!/bin/bash'
}

@test "template uses set -euo pipefail" {
  grep -qF 'set -euo pipefail' "$TEMPLATE"
}

@test "template skips when manager is none" {
  grep -q 'eq \$manager "none"' "$TEMPLATE"
}

@test "template validates target has no path traversal" {
  grep -q 'contains "\.\."' "$TEMPLATE"
}

@test "template validates target is not absolute" {
  grep -q 'hasPrefix "/"' "$TEMPLATE"
}

@test "template creates directories with umask 077" {
  grep -qF 'umask 077' "$TEMPLATE"
}

@test "template sets file permissions to 600" {
  grep -qF 'chmod 600' "$TEMPLATE"
}

# ---------------------------------------------------------------------------
# Fixture — skip scenario (no targets / manager=none)
# ---------------------------------------------------------------------------

@test "skip fixture exits with status 0" {
  run bash "$FIXTURE_SKIP"
  assert_success
  assert_output --partial "No secret file targets configured"
}

@test "skip fixture does not create any files" {
  bash "$FIXTURE_SKIP"
  assert [ ! -d "$HOME/.aws" ]
  assert [ ! -d "$HOME/.docker" ]
}

# ---------------------------------------------------------------------------
# Fixture — deploy scenario
# ---------------------------------------------------------------------------

@test "fixture deploys .aws/credentials with correct content" {
  bash "$FIXTURE"
  assert_file_exists "$HOME/.aws/credentials"
  run cat "$HOME/.aws/credentials"
  assert_output --partial "aws_access_key_id = AKIAEXAMPLE"
}

@test "fixture deploys .docker/config.json with correct content" {
  bash "$FIXTURE"
  assert_file_exists "$HOME/.docker/config.json"
  run cat "$HOME/.docker/config.json"
  assert_output --partial '"auths"'
}

@test "fixture sets file permissions to 600" {
  bash "$FIXTURE"
  run stat -c '%a' "$HOME/.aws/credentials"
  assert_output "600"
}

@test "fixture creates parent directory with mode 700" {
  bash "$FIXTURE"
  run stat -c '%a' "$HOME/.aws"
  assert_output "700"
}

@test "fixture outputs deployment status for each entry" {
  run bash "$FIXTURE"
  assert_success
  assert_output --partial "==> aws-credentials:"
  assert_output --partial "==> docker-auth:"
  assert_output --partial "secret file deploy complete."
}

# ---------------------------------------------------------------------------
# Deploy-state recording
# ---------------------------------------------------------------------------

@test "template wires secret-deploy-state record after each write" {
  grep -qF 'record_state secretFile' "$TEMPLATE"
}

@test "template guards record_state when helper is absent" {
  grep -qF '[ -x "${deploy_state}" ] || return 0' "$TEMPLATE"
}

@test "fixture invokes deploy-state helper when present" {
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/secret-deploy-state" <<'EOS'
#!/bin/bash
echo "$@" >> "${HOME}/.record.log"
EOS
  chmod +x "$HOME/.local/bin/secret-deploy-state"

  run bash "$FIXTURE"
  assert_success

  run cat "$HOME/.record.log"
  assert_output --partial "record secretFile aws-credentials ${HOME}/.aws/credentials"
  assert_output --partial "record secretFile docker-auth ${HOME}/.docker/config.json"
}

@test "fixture is best-effort when deploy-state helper is missing" {
  # No helper installed → deployment must still succeed.
  run bash "$FIXTURE"
  assert_success
  assert_file_exists "$HOME/.aws/credentials"
}

@test "record_state does not consume parent stdin" {
  # Regression for the chezmoi 'has changed since chezmoi last wrote
  # it' overwrite prompt being starved when the deploy helper (or any
  # subprocess it spawns) accidentally reads from the controlling TTY.
  mkdir -p "$HOME/.local/bin"
  # A helper that NAIVELY reads from stdin (the worst-case future
  # regression) — the </dev/null guard in record_state must shield
  # the parent shell from it.
  cat > "$HOME/.local/bin/secret-deploy-state" <<'EOS'
#!/bin/bash
cat >/dev/null
EOS
  chmod +x "$HOME/.local/bin/secret-deploy-state"

  run bash -c '
    bash "'"$FIXTURE"'" >/dev/null
    IFS= read -r line
    printf "AFTER:%s\n" "$line"
  ' <<<'sentinel-survives'
  assert_success
  assert_output --partial "AFTER:sentinel-survives"
}

@test "template closes stdin when invoking deploy-state helper" {
  grep -qF '"${deploy_state}" record "$1" "$2" "$3" </dev/null' "$TEMPLATE"
}
