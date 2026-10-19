#!/usr/bin/env bats
#
# Self-test for the coderabbit stub and the suite guard in setup_suite.bash.
# Every case uses the stub by absolute path, or looks up the name only, so no
# case runs a real coderabbit binary. Each stub call gets a private
# BATS_SUITE_TMPDIR, so the real suite record is never touched. Nothing here
# starts a nested bats run.

bats_require_minimum_version 1.7.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'setup_suite'
}

@test "command -v coderabbit resolves to the stub after setup_suite" {
  setup_suite

  run command -v coderabbit

  assert_success
  assert_output "$_CODERABBIT_STUB_DIR/coderabbit"
}

@test "the stub records one line per call in the suite record and exits 127" {
  local suite_dir="$BATS_TEST_TMPDIR/suite"
  mkdir -p "$suite_dir"

  run -127 env -u CODERABBIT_STUB_RECORD BATS_SUITE_TMPDIR="$suite_dir" \
    "$_CODERABBIT_STUB_DIR/coderabbit" review --agent
  assert_equal "$(wc -l < "$suite_dir/coderabbit-calls")" 1

  run -127 env -u CODERABBIT_STUB_RECORD BATS_SUITE_TMPDIR="$suite_dir" \
    "$_CODERABBIT_STUB_DIR/coderabbit"
  assert_equal "$(wc -l < "$suite_dir/coderabbit-calls")" 2
}

@test "a test-local CODERABBIT_STUB_RECORD does not hide a call from the suite" {
  local suite_dir="$BATS_TEST_TMPDIR/suite"
  mkdir -p "$suite_dir"

  run -127 env BATS_SUITE_TMPDIR="$suite_dir" \
    CODERABBIT_STUB_RECORD="$BATS_TEST_TMPDIR/local-calls" \
    "$_CODERABBIT_STUB_DIR/coderabbit" draft

  assert_equal "$(wc -l < "$suite_dir/coderabbit-calls")" 1
  assert_equal "$(wc -l < "$BATS_TEST_TMPDIR/local-calls")" 1
}

@test "teardown_suite fails when the suite record holds a call" {
  export CODERABBIT_SUITE_RECORD="$BATS_TEST_TMPDIR/suite-calls"
  printf 'draft\n' > "$CODERABBIT_SUITE_RECORD"

  run -1 teardown_suite

  assert_output --partial 'coderabbit was called during the suite'
}

@test "teardown_suite passes when the suite record is absent" {
  export CODERABBIT_SUITE_RECORD="$BATS_TEST_TMPDIR/absent"

  run -0 teardown_suite
}

@test "teardown_suite passes when the suite record is empty" {
  export CODERABBIT_SUITE_RECORD="$BATS_TEST_TMPDIR/empty"
  : > "$CODERABBIT_SUITE_RECORD"

  run -0 teardown_suite
}
