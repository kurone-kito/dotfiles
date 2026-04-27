#!/usr/bin/env bats
# Tests for the Homebrew shell initialization script.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/40-homebrew.sh"
  _ORIG_PATH="$PATH"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

# ---------------------------------------------------------------------------
# Missing dependency
# ---------------------------------------------------------------------------

@test "completes without error when brew is not available" {
  run bash "$SCRIPT_PATH"
  assert_success
}

# ---------------------------------------------------------------------------
# Brew detection and shellenv evaluation
# ---------------------------------------------------------------------------

@test "evaluates brew shellenv when brew is in PATH" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/brew" << 'MOCK'
#!/bin/sh
if [ "$1" = "shellenv" ]; then
  echo 'export HOMEBREW_TEST=loaded'
fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/brew"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  . "$SCRIPT_PATH"

  assert_equal "$HOMEBREW_TEST" "loaded"
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

@test "find_brew function is cleaned up after sourcing" {
  . "$SCRIPT_PATH"

  run type find_brew
  assert_failure
}

@test "BREW variable is unset after sourcing" {
  . "$SCRIPT_PATH"

  assert [ -z "${BREW+x}" ]
}
