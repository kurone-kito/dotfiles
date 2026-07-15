#!/usr/bin/env bats
# Tests for the env file deploy script.
# Exercises: graceful skip when mise/ghq are unavailable or ghq root
# fails (instead of aborting chezmoi apply under set -euo pipefail),
# and the anchored .gitignore membership check.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  FIXTURE="$BATS_TEST_DIRNAME/fixtures/70-deploy-env-files.sh"

  BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN_DIR"
  _ORIG_PATH="$PATH"
  export PATH="$BIN_DIR:$PATH"

  GHQ_ROOT_DIR="$BATS_TEST_TMPDIR/ghqroot"
  PROJECT_DIR="$GHQ_ROOT_DIR/github.com/user/sample-project"
  mkdir -p "$PROJECT_DIR"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

write_working_mise_and_ghq() {
  cat > "$BIN_DIR/mise" << MOCK
#!/bin/bash
if [ "\$1" = "which" ] && [ "\$2" = "ghq" ]; then
  echo "$BIN_DIR/ghq"
  exit 0
fi
exit 1
MOCK
  chmod +x "$BIN_DIR/mise"

  cat > "$BIN_DIR/ghq" << MOCK
#!/bin/bash
if [ "\$1" = "root" ]; then
  echo "$GHQ_ROOT_DIR"
  exit 0
fi
exit 1
MOCK
  chmod +x "$BIN_DIR/ghq"
}

@test "skips gracefully when mise is not available" {
  export PATH="/usr/bin:/bin"

  run bash "$FIXTURE"
  assert_success
  assert_output --partial "mise not found; skipping."
}

@test "skips gracefully when ghq is not found via mise" {
  cat > "$BIN_DIR/mise" << 'MOCK'
#!/bin/bash
exit 1
MOCK
  chmod +x "$BIN_DIR/mise"

  run bash "$FIXTURE"
  assert_success
  assert_output --partial "ghq not found via mise; skipping."
}

@test "skips gracefully when ghq root fails, without aborting" {
  cat > "$BIN_DIR/mise" << MOCK
#!/bin/bash
if [ "\$1" = "which" ] && [ "\$2" = "ghq" ]; then
  echo "$BIN_DIR/ghq"
  exit 0
fi
exit 1
MOCK
  chmod +x "$BIN_DIR/mise"

  cat > "$BIN_DIR/ghq" << 'MOCK'
#!/bin/bash
exit 1
MOCK
  chmod +x "$BIN_DIR/ghq"

  run bash "$FIXTURE"
  assert_success
  assert_output --partial "ghq root failed; skipping."
}

@test "warns when .gitignore lists only a different filename (.env.local, not .env)" {
  write_working_mise_and_ghq
  echo ".env.local" > "$PROJECT_DIR/.gitignore"

  run bash "$FIXTURE"
  assert_success
  assert_output --partial "warn: .env not found in .gitignore"
}

@test "does not warn when .gitignore has an exact .env line" {
  write_working_mise_and_ghq
  echo ".env" > "$PROJECT_DIR/.gitignore"

  run bash "$FIXTURE"
  assert_success
  refute_output --partial "warn: .env not found in .gitignore"
}

@test "deploys the file with mode 600 when the target directory exists" {
  write_working_mise_and_ghq
  echo ".env" > "$PROJECT_DIR/.gitignore"

  run bash "$FIXTURE"
  assert_success
  assert_output --partial "done: deployed (mode 600)"
  assert_file_exists "$PROJECT_DIR/.env"
}
