#!/usr/bin/env bats
#
# Tests for the bw-unlock-env standalone helper.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_bw-unlock-env"
  _ORIG_PATH="$PATH"
  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export BW_UNLOCK_ENV_LOG="$BATS_TEST_TMPDIR/bw-unlock-env.log"
}

teardown() {
  export PATH="$_ORIG_PATH"
  unset BW_UNLOCK_ENV_LOG
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
  printf "bw sync\n" >> "$BW_UNLOCK_ENV_LOG"
  exit 0
fi
if [ "$1" = "unlock" ] && [ "$2" = "--raw" ]; then
  printf "bw unlock\n" >> "$BW_UNLOCK_ENV_LOG"
  printf "test-session\n"
  exit 0
fi
echo "unexpected bw args: $*" >&2
exit 1
'

  make_mock stty '
printf "stty:%s\n" "$*" >> "$BW_UNLOCK_ENV_LOG"
'
}

@test "prints help with --help" {
  setup_standard_mocks

  run bash "$SCRIPT" --help

  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "eval \"\$(bw-unlock-env"
}

@test "exits with error when bw is not in PATH" {
  run bash "$SCRIPT"

  assert_failure
  assert_output --partial "bw not found"
}

@test "prints shell commands to export BW_SESSION and repair tty" {
  setup_standard_mocks

  run bash "$SCRIPT"

  assert_success
  assert_output --partial "export BW_SESSION='test-session'"
  assert_output --partial "stty sane"
  assert_output --partial "printf '\\033[0m\\033[?25h\\r\\n' > /dev/tty"
}

@test "runs bw sync before unlock when --sync is given" {
  setup_standard_mocks

  run bash -c 'eval "$("$1" --sync)"; printf "session=%s\n" "$BW_SESSION"' _ "$SCRIPT"

  assert_success
  assert_output "session=test-session"
  run cat "$BW_UNLOCK_ENV_LOG"
  assert_output "bw sync
bw unlock
stty:sane"
}
