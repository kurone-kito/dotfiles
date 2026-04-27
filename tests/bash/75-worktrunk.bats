#!/usr/bin/env bats
# Tests for the worktrunk (git-wt) shell integration in RC files.
# Validates: detection pattern in dot_bashrc and dot_zshrc, correct
# shell args, eval behavior, and graceful skip when git-wt is absent.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  BASHRC_PATH="$BATS_TEST_DIRNAME/../../home/dot_bashrc"
  ZSHRC_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/zsh/dot_zshrc"
  _ORIG_PATH="$PATH"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

# ---------------------------------------------------------------------------
# Static validation — patterns must satisfy worktrunk's detection
# ---------------------------------------------------------------------------

@test "dot_bashrc contains git-wt config shell init for worktrunk detection" {
  run grep -E 'git-wt config shell init' "$BASHRC_PATH"
  assert_success
}

@test "dot_bashrc uses 'bash' as the shell argument (not 'sh')" {
  run grep -E 'git-wt config shell init bash' "$BASHRC_PATH"
  assert_success
}

@test "dot_zshrc contains git-wt config shell init for worktrunk detection" {
  run grep -E 'git-wt config shell init' "$ZSHRC_PATH"
  assert_success
}

@test "dot_zshrc uses 'zsh' as the shell argument (not 'sh')" {
  run grep -E 'git-wt config shell init zsh' "$ZSHRC_PATH"
  assert_success
}

# ---------------------------------------------------------------------------
# Functional — extract and eval the init line (bash)
# ---------------------------------------------------------------------------

@test "evaluates git-wt shell init output when git-wt is available" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/git-wt" << 'MOCK'
#!/bin/sh
if [ "$1" = "config" ] && [ "$2" = "shell" ] && [ "$3" = "init" ] && [ "$4" = "bash" ]; then
  echo 'export WORKTRUNK_TEST=loaded'
fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/git-wt"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  eval "$(grep 'git-wt config shell init bash' "$BASHRC_PATH")"

  assert_equal "$WORKTRUNK_TEST" "loaded"
}

@test "skips without error when git-wt is not in PATH" {
  eval "$(grep 'git-wt config shell init bash' "$BASHRC_PATH")"
  assert_equal "${WORKTRUNK_TEST:-}" ""
}

