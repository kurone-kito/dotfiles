#!/usr/bin/env bats
# Tests for the interactive Bitwarden shell helper.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  CONF_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/06-bitwarden.sh"
  _ORIG_PATH="$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
  export BW_UNLOCK_CONF_LOG="$BATS_TEST_TMPDIR/bw-unlock-conf.log"
}

teardown() {
  export PATH="$_ORIG_PATH"
  unset BW_UNLOCK_CONF_LOG
}

make_mock_command() {
  cat > "$BATS_TEST_TMPDIR/bin/$1" << EOF
#!/bin/sh
$2
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

setup_standard_mocks() {
  make_mock_command bw '
if [ "$1" = "sync" ]; then
  printf "bw sync\n" >> "$BW_UNLOCK_CONF_LOG"
  exit 0
fi
if [ "$1" = "unlock" ] && [ "$2" = "--raw" ]; then
  printf "bw unlock\n" >> "$BW_UNLOCK_CONF_LOG"
  printf "test-session\n"
  exit 0
fi
echo "unexpected bw args: $*" >&2
exit 1
'

  make_mock_command stty '
printf "stty:%s\n" "$*" >> "$BW_UNLOCK_CONF_LOG"
'
}

@test "defines bw_unlock function when sourced" {
  run bash -c '. "$1"; declare -F bw_unlock' _ "$CONF_PATH"
  assert_success
  assert_output --partial "bw_unlock"
}

@test "defines bw-unlock alias when sourced" {
  run bash -c '. "$1"; alias bw-unlock' _ "$CONF_PATH"
  assert_success
  assert_output "alias bw-unlock='bw_unlock'"
}

@test "bw_unlock prints help" {
  run bash -c '. "$1"; bw_unlock --help' _ "$CONF_PATH"
  assert_success
  assert_output --partial "Usage: bw_unlock"
  assert_output --partial "--sync"
  assert_output --partial "Do not chain"
}

@test "bw_unlock errors when bw is missing" {
  run -127 bash -c '. "$1"; bw_unlock' _ "$CONF_PATH"
  assert_failure
  assert_output --partial "bw not found"
}

@test "bw_unlock exports BW_SESSION and repairs tty in the current shell" {
  setup_standard_mocks
  run bash -c '. "$1"; bw_unlock; printf "session=%s\n" "$BW_SESSION"' _ "$CONF_PATH"
  assert_success
  assert_output --partial "session=test-session"
  assert_output --partial "run chezmoi apply from the next prompt"

  run cat "$BW_UNLOCK_CONF_LOG"
  assert_output "bw unlock
stty:sane"
}

@test "bw_unlock runs bw sync before unlock when requested" {
  setup_standard_mocks
  run bash -c '. "$1"; bw_unlock --sync; printf "session=%s\n" "$BW_SESSION"' _ "$CONF_PATH"
  assert_success
  assert_output --partial "session=test-session"
  assert_output --partial "run chezmoi apply from the next prompt"

  run cat "$BW_UNLOCK_CONF_LOG"
  assert_output "bw sync
bw unlock
stty:sane"
}
