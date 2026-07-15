#!/usr/bin/env bats
# Tests for the Linux systemd user unit template for zellij-web.
# ExecStart must launch through a login shell so the oneshot inherits
# a non-minimal PATH (systemd's default user PATH doesn't include
# mise/cargo/homebrew install locations, which makes `command -v
# zellij` fail and aborts chezmoi apply via the restart under
# set -euo pipefail).

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  UNIT="$BATS_TEST_DIRNAME/../../home/dot_config/systemd/user/zellij-web.service.tmpl"
}

@test "ExecStart launches through a login shell to inherit a non-minimal PATH" {
  run grep -F 'ExecStart=' "$UNIT"
  assert_success
  assert_output "ExecStart=/bin/sh -lc 'exec \"%h/.local/bin/ensure-zellij-web\"'"
}

@test "unit stays otherwise well-formed" {
  run cat "$UNIT"
  assert_success
  assert_output --partial 'Type=oneshot'
  assert_output --partial 'RemainAfterExit=yes'
  assert_output --partial 'WantedBy=default.target'
}

@test "unit passes systemd-analyze verify" {
  if ! command -v systemd-analyze > /dev/null 2>&1; then
    skip "systemd-analyze not available"
  fi

  # systemd-analyze verify infers the unit type from the filename
  # extension, so the .tmpl suffix must be dropped first.
  local unit_copy="$BATS_TEST_TMPDIR/zellij-web.service"
  cp "$UNIT" "$unit_copy"

  run systemd-analyze verify --user "$unit_copy"
  assert_success
}
