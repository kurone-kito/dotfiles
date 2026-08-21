#!/usr/bin/env bats
# Tests for the pinentry-auto bounded-timeout wrapper.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../../home/private_dot_gnupg/executable_pinentry-auto"
  _ORIG_PATH="$PATH"
  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
  export TIMEOUT_LOG="$BATS_TEST_TMPDIR/timeout.log"
  export GTIMEOUT_LOG="$BATS_TEST_TMPDIR/gtimeout.log"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # A leaked DISPLAY/WAYLAND_DISPLAY would silently divert the
  # terminal-fallback tests below into the GUI branch instead.
  unset DISPLAY
  unset WAYLAND_DISPLAY
  unset PINENTRY_AUTO_TIMEOUT
}

teardown() {
  export PATH="$_ORIG_PATH"
  unset DISPLAY
  unset WAYLAND_DISPLAY
  unset PINENTRY_AUTO_TIMEOUT
}

make_mock_command() {
  cat > "$BATS_TEST_TMPDIR/bin/$1" << EOF
#!/bin/sh
$2
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

@test "instant-responding pinentry exits 0 with no stderr message" {
  make_mock_command pinentry-curses "exit 0"

  run --separate-stderr /bin/sh "$SCRIPT_PATH"

  assert_success
  assert_equal "$stderr" ""
}

@test "mock timeout exiting 124 prints the gpg-cache message and propagates the exit code" {
  make_mock_command pinentry-curses "exit 0"
  make_mock_command timeout "printf '%s\n' \"\$*\" >> \"${TIMEOUT_LOG}\"; exit 124"

  run --separate-stderr /bin/sh "$SCRIPT_PATH"

  assert_equal "$status" 124
  assert_stderr --partial "did not respond within"
  assert_stderr --partial "gpg-cache"
  assert_file_contains "$TIMEOUT_LOG" "pinentry-curses"
}

@test "mock timeout exiting 137 (SIGKILL via -k grace period) prints the same message" {
  make_mock_command pinentry-curses "exit 0"
  make_mock_command timeout "printf '%s\n' \"\$*\" >> \"${TIMEOUT_LOG}\"; exit 137"

  run --separate-stderr /bin/sh "$SCRIPT_PATH"

  assert_equal "$status" 137
  assert_stderr --partial "did not respond within"
  assert_stderr --partial "gpg-cache"
}

@test "a genuine pinentry cancel/error (other non-zero exit) propagates without the timeout message" {
  make_mock_command pinentry-curses "exit 0"
  make_mock_command timeout "exit 2"

  run --separate-stderr /bin/sh "$SCRIPT_PATH"

  assert_equal "$status" 2
  refute_stderr --partial "did not respond"
  refute_stderr --partial "gpg-cache"
}

@test "uses PINENTRY_AUTO_TIMEOUT default of 5 when unset" {
  make_mock_command pinentry-curses "exit 0"
  make_mock_command timeout "printf '%s\n' \"\$*\" >> \"${TIMEOUT_LOG}\"; exit 0"

  run --separate-stderr /bin/sh "$SCRIPT_PATH"

  assert_success
  assert_file_contains "$TIMEOUT_LOG" "\-k 2 5 pinentry-curses"
}

@test "honors PINENTRY_AUTO_TIMEOUT override from the environment" {
  make_mock_command pinentry-curses "exit 0"
  make_mock_command timeout "printf '%s\n' \"\$*\" >> \"${TIMEOUT_LOG}\"; exit 0"
  export PINENTRY_AUTO_TIMEOUT=30

  run --separate-stderr /bin/sh "$SCRIPT_PATH"

  assert_success
  assert_file_contains "$TIMEOUT_LOG" "\-k 2 30 pinentry-curses"
}

@test "the macOS pinentry-mac branch is timeout-wrapped, not a bare exec" {
  make_mock_command pinentry-mac "exit 0"
  make_mock_command timeout "printf '%s\n' \"\$*\" >> \"${TIMEOUT_LOG}\"; exit 124"

  run --separate-stderr /bin/sh "$SCRIPT_PATH"

  assert_equal "$status" 124
  assert_stderr --partial "did not respond within"
  assert_file_contains "$TIMEOUT_LOG" "pinentry-mac"
}

@test "the GUI pinentry-gnome3 branch is timeout-wrapped, not a bare exec" {
  export DISPLAY=":0"
  make_mock_command pinentry-gnome3 "exit 0"
  make_mock_command timeout "printf '%s\n' \"\$*\" >> \"${TIMEOUT_LOG}\"; exit 124"

  run --separate-stderr /bin/sh "$SCRIPT_PATH"

  assert_equal "$status" 124
  assert_stderr --partial "did not respond within"
  assert_file_contains "$TIMEOUT_LOG" "pinentry-gnome3"
}

@test "prefers timeout over gtimeout when both are present" {
  make_mock_command pinentry-curses "exit 0"
  make_mock_command timeout "printf '%s\n' \"\$*\" >> \"${TIMEOUT_LOG}\"; exit 0"
  make_mock_command gtimeout "printf '%s\n' \"\$*\" >> \"${GTIMEOUT_LOG}\"; exit 0"

  run --separate-stderr /bin/sh "$SCRIPT_PATH"

  assert_success
  assert_file_exists "$TIMEOUT_LOG"
  assert_file_not_exists "$GTIMEOUT_LOG"
}

@test "resolves to gtimeout when timeout is absent" {
  make_mock_command pinentry-curses "exit 0"
  make_mock_command gtimeout "printf '%s\n' \"\$*\" >> \"${GTIMEOUT_LOG}\"; exit 124"

  # Scope PATH to only the mock bin directory (same `env`-on-the-child
  # technique as the neither-found fallback test below) so the real
  # system `timeout` cannot be found and mask the gtimeout-only branch;
  # the mock gtimeout remains available.
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/bin" /bin/sh "$SCRIPT_PATH"

  assert_equal "$status" 124
  assert_stderr --partial "did not respond within"
  assert_file_contains "$GTIMEOUT_LOG" "pinentry-curses"
}

@test "falls back to the old unbounded exec when neither timeout nor gtimeout is found" {
  # A distinctive exit code: if a real timeout binary were found despite
  # the PATH scoping below, the wrapped call would behave differently
  # (e.g. fail to find "sh"/lose the mock, or exit non-distinctively)
  # rather than coincidentally also exiting 42.
  make_mock_command pinentry-curses "exit 42"

  # Scope PATH to only the mock bin directory for the script invocation
  # itself (via `env`, not `export`): unlike this repo's other bats
  # setups, /usr/bin:/bin must be excluded here so the real system
  # `timeout` cannot mask this fallback path and produce a false pass.
  # `export`ing this into the whole test shell would also starve bats'
  # own `run --separate-stderr` machinery of `mktemp`, so it is scoped
  # to the child process only.
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/bin" /bin/sh "$SCRIPT_PATH"

  assert_equal "$status" 42
  assert_equal "$stderr" ""
}
