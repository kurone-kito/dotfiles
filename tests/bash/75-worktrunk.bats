#!/usr/bin/env bats
# Tests for the worktrunk (git-wt) shell initialization script.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/75-worktrunk.sh"
  _ORIG_PATH="$PATH"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

# ---------------------------------------------------------------------------
# Missing dependency
# ---------------------------------------------------------------------------

@test "completes without error when git-wt is not in PATH" {
  run bash "$SCRIPT_PATH"
  assert_success
}

# ---------------------------------------------------------------------------
# Shell init evaluation
# ---------------------------------------------------------------------------

@test "evaluates git-wt shell init output when git-wt is available" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/git-wt" << 'MOCK'
#!/bin/sh
if [ "$1" = "config" ] && [ "$2" = "shell" ] && [ "$3" = "init" ] && [ "$4" = "sh" ]; then
  echo 'export WORKTRUNK_TEST=loaded'
fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/git-wt"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  . "$SCRIPT_PATH"

  assert_equal "$WORKTRUNK_TEST" "loaded"
}
