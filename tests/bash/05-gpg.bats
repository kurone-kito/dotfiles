#!/usr/bin/env bats
# Tests for the GPG shell/session helpers.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  CONF_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/05-gpg.sh"
  CACHE_PATH="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_gpg-cache"
  _ORIG_PATH="$PATH"
  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
  export GPG_HELPER_LOG="$BATS_TEST_TMPDIR/gpg-helper.log"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  unset GPG_TTY
}

teardown() {
  export PATH="$_ORIG_PATH"
  unset GPG_TTY
}

make_mock_command() {
  cat > "$BATS_TEST_TMPDIR/bin/$1" << EOF
#!/bin/sh
$2
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

@test "sets GPG_TTY from tty when tty succeeds" {
  make_mock_command tty "printf '/dev/pts/42\n'"

  . "$CONF_PATH"

  assert_equal "$GPG_TTY" "/dev/pts/42"
}

@test "does not export GPG_TTY when tty fails" {
  make_mock_command tty "exit 1"

  . "$CONF_PATH"

  assert [ -z "${GPG_TTY+x}" ]
}

@test "calls gpg-connect-agent reloadagent then updatestartuptty" {
  make_mock_command tty "printf '/dev/pts/42\n'"
  make_mock_command gpg-connect-agent "printf '%s\n' \"\$*\" >> \"${GPG_HELPER_LOG}\""

  . "$CONF_PATH"

  assert_file_exists "$GPG_HELPER_LOG"
  run head -1 "$GPG_HELPER_LOG"
  assert_output "reloadagent /bye"
  run sed -n '2p' "$GPG_HELPER_LOG"
  assert_output "updatestartuptty /bye"
}

@test "gpg-cache exits with an error when gpg is not in PATH" {
  export PATH="$BATS_TEST_TMPDIR/bin"

  run /bin/sh "$CACHE_PATH"

  assert_failure
  assert_output --partial "gpg not found in PATH"
}

@test "gpg-cache primes default key when no signing keys configured" {
  make_mock_command tty "printf '/dev/pts/55\n'"
  make_mock_command gpg-connect-agent "printf 'agent:%s\n' \"\$*\" >> \"${GPG_HELPER_LOG}\""
  make_mock_command gpg "printf 'gpg:%s\n' \"\$*\" >> \"${GPG_HELPER_LOG}\"; exit 0"

  run /bin/sh "$CACHE_PATH"

  assert_success
  assert_output --partial "Prompting GPG passphrase"
  assert_output --partial "Passphrase cached successfully"
  assert_file_contains "$GPG_HELPER_LOG" "agent:reloadagent /bye"
  assert_file_contains "$GPG_HELPER_LOG" "gpg:--clearsign --yes"
  # Should NOT contain --local-user when no keys configured
  run grep -- '--local-user' "$GPG_HELPER_LOG"
  assert_failure
}

@test "gpg-cache primes specific key with --local-user from git config" {
  make_mock_command tty "printf '/dev/pts/55\n'"
  make_mock_command gpg-connect-agent "printf 'agent:%s\n' \"\$*\" >> \"${GPG_HELPER_LOG}\""
  make_mock_command gpg "printf 'gpg:%s\n' \"\$*\" >> \"${GPG_HELPER_LOG}\"; exit 0"
  make_mock_command git \
    "if [ \"\$1\" = 'config' ] && [ \"\$2\" = 'user.signingkey' ]; then printf 'AAAA1111BBBB2222\n'; exit 0; fi; exit 1"

  run /bin/sh "$CACHE_PATH"

  assert_success
  assert_output --partial "Prompting GPG passphrase for key AAAA1111BBBB2222"
  assert_output --partial "Passphrase cached successfully"
  assert_file_contains "$GPG_HELPER_LOG" "gpg:--local-user AAAA1111BBBB2222 --clearsign --yes"
}

@test "gpg-cache primes multiple keys from git config and profiles" {
  make_mock_command tty "printf '/dev/pts/55\n'"
  make_mock_command gpg-connect-agent "printf 'agent:%s\n' \"\$*\" >> \"${GPG_HELPER_LOG}\""
  make_mock_command gpg "printf 'gpg:%s\n' \"\$*\" >> \"${GPG_HELPER_LOG}\"; exit 0"
  make_mock_command git \
    "if [ \"\$1\" = 'config' ] && [ \"\$2\" = 'user.signingkey' ]; then printf 'KEY1\n'; exit 0; fi; exit 1"

  mkdir -p "$HOME/.config/git/profiles"
  printf '[user]\n  signingkey = "KEY2"\n' > "$HOME/.config/git/profiles/work"

  run /bin/sh "$CACHE_PATH"

  assert_success
  assert_output --partial "Prompting GPG passphrase for key KEY1"
  assert_output --partial "Prompting GPG passphrase for key KEY2"
  assert_file_contains "$GPG_HELPER_LOG" "gpg:--local-user KEY1 --clearsign --yes"
  assert_file_contains "$GPG_HELPER_LOG" "gpg:--local-user KEY2 --clearsign --yes"
}

@test "gpg-cache returns failure when gpg exits nonzero" {
  make_mock_command tty "printf '/dev/pts/77\n'"
  make_mock_command gpg-connect-agent "true"
  make_mock_command gpg "exit 1"

  run /bin/sh "$CACHE_PATH"

  assert_failure
  assert_output --partial "GPG passphrase caching failed."
}
