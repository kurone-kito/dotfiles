#!/usr/bin/env bats
# Tests for docs/pueue-validation-queue.md. The install section and decision
# step 4 describe the supervisor, the managed stops are named, and the
# unmanaged fallback is documented. Each check reads only the section it is
# about, after the section's lines are joined, so a sentence that wraps across
# lines is still found and a sentence elsewhere cannot satisfy the check.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  DOC="$REPO_ROOT/docs/pueue-validation-queue.md"
  # The whole document, joined, for the checks that span it.
  JOINED="$(tr '\n' ' ' < "$DOC" | tr -s ' ')"
  # The "## Installing pueue" section, joined on its own, and the text of
  # decision step 4 alone: from its "4." list item up to the "5." item.
  INSTALL="$(awk '/^## Installing pueue/{f=1; next} /^## /{f=0} f' "$DOC" | tr '\n' ' ' | tr -s ' ')"
  STEP4="$(awk '/^4\. If the pueue daemon/{f=1} /^5\. /{f=0} f' "$DOC" | tr '\n' ' ' | tr -s ' ')"
}

# $1: a fixed string. Succeeds when the joined document contains it.
_contains() {
  grep -qF -- "$1" <<< "$JOINED"
}

# $1: a joined section text. $2: a fixed string. Succeeds when the section
# contains the string.
_in() {
  grep -qF -- "$2" <<< "$1"
}

@test "the install section no longer says there is no service to set up" {
  run _contains 'There is no service to set up'
  assert_failure
}

@test "the install section names the Linux unit and the macOS LaunchAgent" {
  run _in "$INSTALL" 'the systemd user unit `pueued.service`'
  assert_success
  run _in "$INSTALL" 'the LaunchAgent `com.kurone-kito.pueued`'
  assert_success
}

@test "the first call starts the daemon on demand only when no supervisor is enabled" {
  run _in "$INSTALL" 'Only when no supervisor is enabled does the first call start the daemon on demand'
  assert_success
}

@test "the install section says that Linux needs user systemd, and that disabled falls back on demand" {
  run _in "$INSTALL" 'user systemd is not'
  assert_success
  run _in "$INSTALL" 'With `disabled` on Linux, the unit is stopped and disabled'
  assert_success
}

@test "the install section documents the handover when an unmanaged pueued is running" {
  run _in "$INSTALL" 'the script does not enable the unit beside it'
  assert_success
  run _in "$INSTALL" '`pueue shutdown` followed by `systemctl --user enable --now pueued.service`'
  assert_success
}

@test "the install section says that a disabled macOS LaunchAgent keeps its plist and never starts a daemon on demand" {
  run _in "$INSTALL" 'keeps the plist'
  assert_success
  run _in "$INSTALL" 'never starts a daemon on demand'
  assert_success
}

@test "decision step 4 describes the supervisor and the one-shot pueued -d fallback" {
  run _in "$STEP4" 'it first looks for a supervisor that owns the daemon'
  assert_success
  run _in "$STEP4" 'Only without a supervisor does it start the daemon once with `pueued -d`'
  assert_success
}

@test "the managed stop on Linux is systemctl --user stop pueued.service" {
  run _in "$INSTALL" 'systemctl --user stop pueued.service'
  assert_success
}

@test "the managed stop on macOS is launchctl bootout of the LaunchAgent label, with a runnable uid" {
  run _in "$INSTALL" 'launchctl bootout gui/$(id -u)/com.kurone-kito.pueued'
  assert_success
}

@test "pueue shutdown is documented as the unmanaged fallback" {
  run _contains 'pueue shutdown'
  assert_success
  run _contains 'unmanaged fallback'
  assert_success
}
