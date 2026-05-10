#!/usr/bin/env bats
# Tests for home/dot_config/shell/conf.d/15-cargo.sh.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/15-cargo.sh"
  _ORIG_PATH="$PATH"
  unset CARGO_HOME
}

teardown() {
  export PATH="$_ORIG_PATH"
}

@test "prepends \$HOME/.cargo/bin when the directory exists" {
  mkdir -p "$HOME/.cargo/bin"
  export PATH="/usr/bin:/bin"

  . "$SCRIPT_PATH"

  assert_equal "$PATH" "$HOME/.cargo/bin:/usr/bin:/bin"
}

@test "no-op when \$HOME/.cargo/bin does not exist" {
  export PATH="/usr/bin:/bin"

  . "$SCRIPT_PATH"

  assert_equal "$PATH" "/usr/bin:/bin"
}

@test "is idempotent across two sources" {
  mkdir -p "$HOME/.cargo/bin"
  export PATH="/usr/bin:/bin"

  . "$SCRIPT_PATH"
  . "$SCRIPT_PATH"

  assert_equal "$PATH" "$HOME/.cargo/bin:/usr/bin:/bin"
}

@test "honors CARGO_HOME override" {
  mkdir -p "$BATS_TEST_TMPDIR/custom-cargo/bin"
  export CARGO_HOME="$BATS_TEST_TMPDIR/custom-cargo"
  export PATH="/usr/bin:/bin"

  . "$SCRIPT_PATH"

  assert_equal "$PATH" "$BATS_TEST_TMPDIR/custom-cargo/bin:/usr/bin:/bin"
}

@test "trailing slash in CARGO_HOME does not duplicate or skew the entry" {
  mkdir -p "$BATS_TEST_TMPDIR/c/bin"
  export CARGO_HOME="$BATS_TEST_TMPDIR/c/"
  export PATH="$BATS_TEST_TMPDIR/c/bin:/usr/bin"

  . "$SCRIPT_PATH"

  # Should match existing entry and be a no-op (no /c//bin appended).
  assert_equal "$PATH" "$BATS_TEST_TMPDIR/c/bin:/usr/bin"
}

@test "leaves helper variables unset after sourcing" {
  mkdir -p "$HOME/.cargo/bin"

  . "$SCRIPT_PATH"

  [ -z "${cargo_home:-}" ]
  [ -z "${cargo_bin:-}" ]
}
