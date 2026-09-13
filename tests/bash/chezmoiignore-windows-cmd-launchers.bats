#!/usr/bin/env bats
#
# Regression test: the two new idd-critique-telemetry(-report).cmd
# Windows launchers must be excluded from non-Windows chezmoi applies,
# mirroring the existing coderabbit-critique.cmd exclusion -- a
# platform-specific .cmd batch file is useless clutter on Linux/macOS.
# On this test host (non-Windows), .chezmoiignore.tmpl's default
# `.chezmoi.os` renders the non-Windows branch, so this is a direct
# regression check rather than a simulated cross-platform render.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
}

@test ".chezmoiignore.tmpl excludes both idd-critique-telemetry .cmd launchers on non-Windows" {
  run chezmoi execute-template --file "$REPO_ROOT/home/.chezmoiignore.tmpl" \
    --source "$REPO_ROOT" --destination "$BATS_TEST_TMPDIR"

  assert_success
  assert_line '.local/bin/idd-critique-telemetry.cmd'
  assert_line '.local/bin/idd-critique-telemetry-report.cmd'
  # The existing sibling exclusion this fix mirrors; regresses this
  # test's own premise if it ever disappears from the same branch.
  assert_line '.local/bin/coderabbit-critique.cmd'
}
