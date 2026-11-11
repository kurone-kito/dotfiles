#!/usr/bin/env bats
# Tests for docs/pueue-validation-queue.md. The install section and decision
# step 4 describe the supervisor, the managed stops are named, and the
# unmanaged fallback is documented. The document's lines are joined before
# each match, so a sentence that wraps across lines is still found.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  DOC="$REPO_ROOT/docs/pueue-validation-queue.md"
  JOINED="$(tr '\n' ' ' < "$DOC" | tr -s ' ')"
}

# $1: a fixed string. Succeeds when the joined document contains it.
_contains() {
  grep -qF -- "$1" <<< "$JOINED"
}

@test "the install section no longer says there is no service to set up" {
  run _contains 'There is no service to set up'
  assert_failure
}

@test "the install section names the Linux unit and the macOS LaunchAgent" {
  run _contains 'pueued.service'
  assert_success
  run _contains 'com.kurone-kito.pueued'
  assert_success
}

@test "the first call starts the daemon on demand only when no supervisor is enabled" {
  run _contains 'Only when no supervisor is enabled does the first call start the daemon on demand'
  assert_success
}

@test "decision step 4 describes the supervisor and the one-shot pueued -d fallback" {
  run _contains 'it first looks for a supervisor that owns the daemon'
  assert_success
  run _contains 'Only without a supervisor does it start the daemon once with `pueued -d`'
  assert_success
}

@test "the managed stop on Linux is systemctl --user stop pueued.service" {
  run _contains 'systemctl --user stop pueued.service'
  assert_success
}

@test "the managed stop on macOS is launchctl bootout of the LaunchAgent label" {
  run _contains 'launchctl bootout gui/<uid>/com.kurone-kito.pueued'
  assert_success
}

@test "pueue shutdown is documented as the unmanaged fallback" {
  run _contains 'pueue shutdown'
  assert_success
  run _contains 'unmanaged fallback'
  assert_success
}
