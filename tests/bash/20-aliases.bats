#!/usr/bin/env bats
# Tests for the shared POSIX aliases configuration.
# Validates conditional compatibility aliases and skip behavior.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  ALIASES_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/20-aliases.sh"
  _ORIG_PATH="$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # Symlink tr so case-insensitive path matching works under restricted PATH
  ln -sf "$(command -v tr)" "$BATS_TEST_TMPDIR/bin/tr"
  export PATH="$BATS_TEST_TMPDIR/bin"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

make_mock_command() {
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/$1"
  /bin/chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

make_mock_command_at() {
  if [ "${1%/*}" != "$1" ]; then
    /bin/mkdir -p "$BATS_TEST_TMPDIR/bin/${1%/*}"
  fi
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/$1"
  /bin/chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

@test "creates wt alias when git-wt exists and wt is missing" {
  make_mock_command git-wt

  . "$ALIASES_PATH"

  run alias wt
  assert_success
  assert_output "alias wt='git-wt'"
}

@test "skips wt alias when wt already exists" {
  make_mock_command git-wt
  make_mock_command wt

  . "$ALIASES_PATH"

  run alias wt
  assert_failure
}

@test "creates git-wt alias when wt exists and git-wt is missing" {
  make_mock_command wt

  . "$ALIASES_PATH"

  run alias git-wt
  assert_success
  assert_output "alias git-wt='wt'"
}

@test "skips git-wt alias when wt resolves to Windows Terminal" {
  make_mock_command_at 'WindowsApps/wt'
  export PATH="$BATS_TEST_TMPDIR/bin/WindowsApps:$BATS_TEST_TMPDIR/bin"

  . "$ALIASES_PATH"

  run alias git-wt
  assert_failure
}

@test "skips git-wt alias when wt resolves to lowercase windowsapps" {
  make_mock_command_at 'windowsapps/wt'
  export PATH="$BATS_TEST_TMPDIR/bin/windowsapps:$BATS_TEST_TMPDIR/bin"

  . "$ALIASES_PATH"

  run alias git-wt
  assert_failure
}

@test "skips git-wt alias when wt resolves to Microsoft.WindowsTerminal path" {
  make_mock_command_at 'Microsoft.WindowsTerminal_8wekyb3d8bbwe/wt'
  export PATH="$BATS_TEST_TMPDIR/bin/Microsoft.WindowsTerminal_8wekyb3d8bbwe:$BATS_TEST_TMPDIR/bin"

  . "$ALIASES_PATH"

  run alias git-wt
  assert_failure
}

@test "creates batcat alias when bat exists and batcat is missing" {
  make_mock_command bat

  . "$ALIASES_PATH"

  run alias batcat
  assert_success
  assert_output "alias batcat='bat'"
}

@test "creates bat alias when batcat exists and bat is missing" {
  make_mock_command batcat

  . "$ALIASES_PATH"

  run alias bat
  assert_success
  assert_output "alias bat='batcat'"
}

@test "skips bat alias when bat already exists" {
  make_mock_command bat
  make_mock_command batcat

  . "$ALIASES_PATH"

  run alias bat
  assert_failure
}
