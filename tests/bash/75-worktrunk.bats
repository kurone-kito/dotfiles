#!/usr/bin/env bats
# Tests for the worktrunk shell integration in RC files.
# Validates: detection patterns for both wt and git-wt binary names
# in dot_bashrc and dot_zshrc, correct shell args, eval behavior,
# and graceful skip when neither binary is available.

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

@test "dot_bashrc contains wt config shell init for default binary detection" {
  run grep -E '^if command -v wt ' "$BASHRC_PATH"
  assert_success
}

@test "dot_bashrc contains git-wt config shell init for Windows binary detection" {
  run grep -E '^if command -v git-wt ' "$BASHRC_PATH"
  assert_success
}

@test "dot_bashrc uses 'bash' as the shell argument for wt" {
  run grep -E 'wt config shell init bash' "$BASHRC_PATH"
  assert_success
}

@test "dot_bashrc uses 'bash' as the shell argument for git-wt" {
  run grep -E 'git-wt config shell init bash' "$BASHRC_PATH"
  assert_success
}

@test "dot_zshrc contains wt config shell init for default binary detection" {
  run grep -E '^if command -v wt ' "$ZSHRC_PATH"
  assert_success
}

@test "dot_zshrc contains git-wt config shell init for Windows binary detection" {
  run grep -E '^if command -v git-wt ' "$ZSHRC_PATH"
  assert_success
}

@test "dot_zshrc uses 'zsh' as the shell argument for wt" {
  run grep -E 'wt config shell init zsh' "$ZSHRC_PATH"
  assert_success
}

@test "dot_zshrc uses 'zsh' as the shell argument for git-wt" {
  run grep -E 'git-wt config shell init zsh' "$ZSHRC_PATH"
  assert_success
}

# ---------------------------------------------------------------------------
# Functional — extract and eval the init lines (bash)
# ---------------------------------------------------------------------------

@test "evaluates wt shell init output when wt is available" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/wt" << 'MOCK'
#!/bin/sh
if [ "$1" = "config" ] && [ "$2" = "shell" ] && [ "$3" = "init" ] && [ "$4" = "bash" ]; then
  echo 'export WORKTRUNK_TEST=loaded_wt'
fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/wt"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  eval "$(grep '^if command -v wt ' "$BASHRC_PATH")"

  assert_equal "$WORKTRUNK_TEST" "loaded_wt"
}

@test "evaluates git-wt shell init output when git-wt is available" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/git-wt" << 'MOCK'
#!/bin/sh
if [ "$1" = "config" ] && [ "$2" = "shell" ] && [ "$3" = "init" ] && [ "$4" = "bash" ]; then
  echo 'export WORKTRUNK_TEST=loaded_gitwt'
fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/git-wt"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  eval "$(grep '^if command -v git-wt ' "$BASHRC_PATH")"

  assert_equal "$WORKTRUNK_TEST" "loaded_gitwt"
}

@test "skips without error when neither wt nor git-wt is in PATH" {
  eval "$(grep '^if command -v wt ' "$BASHRC_PATH")"
  eval "$(grep '^if command -v git-wt ' "$BASHRC_PATH")"
  assert_equal "${WORKTRUNK_TEST:-}" ""
}

