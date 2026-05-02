#!/usr/bin/env bats
#
# Tests for the bw-unlock-exec standalone helper.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_bw-unlock-exec"
  _ORIG_PATH="$PATH"
  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export BW_UNLOCK_EXEC_LOG="$BATS_TEST_TMPDIR/bw-unlock-exec.log"
  export BW_UNLOCK_EXEC_TTY="$BATS_TEST_TMPDIR/tty"
  : > "$BW_UNLOCK_EXEC_TTY"
}

teardown() {
  export PATH="$_ORIG_PATH"
  unset BW_UNLOCK_EXEC_LOG BW_UNLOCK_EXEC_TTY
}

make_mock() {
  cat > "$BATS_TEST_TMPDIR/bin/$1" << EOF
#!/bin/sh
$2
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

setup_standard_mocks() {
  make_mock bw '
if [ "$1" = "sync" ]; then
  printf "bw sync\n" >> "$BW_UNLOCK_EXEC_LOG"
  exit 0
fi
if [ "$1" = "unlock" ] && [ "$2" = "--raw" ]; then
  printf "bw unlock\n" >> "$BW_UNLOCK_EXEC_LOG"
  printf "test-session\n"
  exit 0
fi
echo "unexpected bw args: $*" >&2
exit 1
'

  make_mock stty '
printf "stty:%s\n" "$*" >> "$BW_UNLOCK_EXEC_LOG"
'

  make_mock print-bw-session '
printf "cmd:%s\n" "${BW_SESSION:-}" >> "$BW_UNLOCK_EXEC_LOG"
'
}

@test "prints help with --help" {
  setup_standard_mocks

  run "$SCRIPT" --help

  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--sync"
}

@test "exits with error when command is missing" {
  setup_standard_mocks

  run "$SCRIPT"

  assert_failure
  assert_output --partial "<command> is required"
}

@test "exits with error when bw is not in PATH" {
  run "$SCRIPT" echo hi

  assert_failure
  assert_output --partial "bw not found"
}

@test "unlocks, resets tty, and execs command with BW_SESSION" {
  setup_standard_mocks

  run "$SCRIPT" print-bw-session

  assert_success
  assert_file_exists "$BW_UNLOCK_EXEC_LOG"
  run cat "$BW_UNLOCK_EXEC_LOG"
  assert_output "bw unlock
stty:sane
cmd:test-session"
}

@test "runs bw sync before unlock when --sync is given" {
  setup_standard_mocks

  run "$SCRIPT" --sync print-bw-session

  assert_success
  run cat "$BW_UNLOCK_EXEC_LOG"
  assert_output "bw sync
bw unlock
stty:sane
cmd:test-session"
}
