#!/usr/bin/env bats
# Tests for the worktrunk shell integration in RC files.
# Validates: detection patterns for both wt and git-wt binary names
# in dot_bashrc and dot_zshrc, correct shell args, fallback behavior,
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
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

extract_bash_worktrunk_block() {
  awk '
    /^# Worktrunk shell integration/ { in_block = 1 }
    in_block && /^# Plugin manager/ { exit }
    in_block { print }
  ' "$BASHRC_PATH"
}

extract_zsh_worktrunk_block() {
  awk '
    /^# Worktrunk shell integration/ { in_block = 1 }
    in_block && /^# Plugin manager/ { exit }
    in_block { print }
  ' "$ZSHRC_PATH"
}

make_worktrunk_mock() {
  mkdir -p "$BATS_TEST_TMPDIR/bin/$(dirname "$1")"
  cat > "$BATS_TEST_TMPDIR/bin/$1" << MOCK
#!/bin/sh
if [ "\$1" = "config" ] && [ "\$2" = "shell" ] && [ "\$3" = "init" ] && [ "\$4" = "$2" ]; then
  echo 'export WORKTRUNK_TEST=$3'
fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

# ---------------------------------------------------------------------------
# Static validation — patterns must satisfy worktrunk's detection
# ---------------------------------------------------------------------------

@test "dot_bashrc contains wt config shell init for default binary detection" {
  run grep -E 'wt config shell init bash' "$BASHRC_PATH"
  assert_success
}

@test "dot_bashrc contains git-wt config shell init for Windows binary detection" {
  run grep -E 'git-wt config shell init bash' "$BASHRC_PATH"
  assert_success
}

@test "dot_zshrc contains wt config shell init for default binary detection" {
  run grep -E 'wt config shell init zsh' "$ZSHRC_PATH"
  assert_success
}

@test "dot_zshrc contains git-wt config shell init for Windows binary detection" {
  run grep -E 'git-wt config shell init zsh' "$ZSHRC_PATH"
  assert_success
}

# ---------------------------------------------------------------------------
# Functional — extract and eval the init lines (bash)
# ---------------------------------------------------------------------------

@test "evaluates git-wt shell init output when git-wt is available" {
  make_worktrunk_mock git-wt bash git-wt
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  eval "$(extract_bash_worktrunk_block)"

  assert_equal "$WORKTRUNK_TEST" "git-wt"
}

@test "evaluates wt shell init output when wt is available" {
  make_worktrunk_mock wt bash wt
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  eval "$(extract_bash_worktrunk_block)"

  assert_equal "$WORKTRUNK_TEST" "wt"
}

@test "skips wt shell init when wt resolves to Windows Terminal path" {
  make_worktrunk_mock WindowsApps/wt bash wt
  export PATH="$BATS_TEST_TMPDIR/bin/WindowsApps:$PATH"

  eval "$(extract_bash_worktrunk_block)"

  assert_equal "${WORKTRUNK_TEST:-}" ""
}

@test "skips wt shell init when wt resolves to lowercase windowsapps path" {
  make_worktrunk_mock windowsapps/wt bash wt
  export PATH="$BATS_TEST_TMPDIR/bin/windowsapps:$PATH"

  eval "$(extract_bash_worktrunk_block)"

  assert_equal "${WORKTRUNK_TEST:-}" ""
}

@test "skips wt shell init when wt resolves to Microsoft.WindowsTerminal path" {
  make_worktrunk_mock Microsoft.WindowsTerminal_8wekyb3d8bbwe/wt bash wt
  export PATH="$BATS_TEST_TMPDIR/bin/Microsoft.WindowsTerminal_8wekyb3d8bbwe:$PATH"

  eval "$(extract_bash_worktrunk_block)"

  assert_equal "${WORKTRUNK_TEST:-}" ""
}

@test "prefers git-wt shell init when both git-wt and wt are available" {
  make_worktrunk_mock git-wt bash git-wt
  make_worktrunk_mock wt bash wt
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  eval "$(extract_bash_worktrunk_block)"

  assert_equal "$WORKTRUNK_TEST" "git-wt"
}

@test "falls back to wt shell init when git-wt is not in PATH" {
  make_worktrunk_mock wt bash wt
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  eval "$(extract_bash_worktrunk_block)"

  assert_equal "$WORKTRUNK_TEST" "wt"
}

@test "zsh falls back to wt shell init when git-wt is not in PATH" {
  make_worktrunk_mock wt zsh wt
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  run zsh -fc "$(extract_zsh_worktrunk_block); print -r -- \${WORKTRUNK_TEST:-}"
  assert_success
  assert_output "wt"
}

@test "zsh skips wt shell init when wt resolves to Windows Terminal path" {
  make_worktrunk_mock WindowsApps/wt zsh wt
  export PATH="$BATS_TEST_TMPDIR/bin/WindowsApps:$PATH"

  run zsh -fc "$(extract_zsh_worktrunk_block); print -r -- \${WORKTRUNK_TEST:-}"
  assert_success
  assert_output ""
}

@test "zsh skips wt shell init when wt resolves to lowercase windowsapps path" {
  make_worktrunk_mock windowsapps/wt zsh wt
  export PATH="$BATS_TEST_TMPDIR/bin/windowsapps:$PATH"

  run zsh -fc "$(extract_zsh_worktrunk_block); print -r -- \${WORKTRUNK_TEST:-}"
  assert_success
  assert_output ""
}

@test "skips without error when neither wt nor git-wt is in PATH" {
  eval "$(extract_bash_worktrunk_block)"
  assert_equal "${WORKTRUNK_TEST:-}" ""
}
