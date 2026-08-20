#!/usr/bin/env bats
# Tests for scripts/check-ruleset-drift.sh, the drift-comparison logic
# extracted from .github/workflows/ruleset-required-checks-guard.yml.
# Exercises: matching contexts, a missing context, an unexpected extra
# context, and the zero-rule case -- all against fixture JSON, never
# against the real `master` ruleset.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/check-ruleset-drift.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
}

@test "reports a match and exits 0 when all expected contexts are present" {
  run bash "$SCRIPT" "$FIXTURES/ruleset-drift-check-match.json"
  assert_success
  assert_output --partial 'contexts match the expected set'
  assert_output --partial 'RULE_COUNT=1'
}

@test "reports the missing context and exits non-zero when a context is missing" {
  run bash "$SCRIPT" "$FIXTURES/ruleset-drift-check-missing-context.json"
  assert_failure
  assert_output --partial 'Missing context(s): lint'
  assert_output --partial 'MISSING_CONTEXTS=lint'
  assert_output --partial 'EXTRA_CONTEXTS='
  refute_output --partial 'Unexpected extra context(s)'
}

@test "reports the unexpected extra context and exits non-zero when one is present" {
  run bash "$SCRIPT" "$FIXTURES/ruleset-drift-check-extra-context.json"
  assert_failure
  assert_output --partial 'Unexpected extra context(s): totally-unexpected-check'
  assert_output --partial 'EXTRA_CONTEXTS=totally-unexpected-check'
  assert_output --partial 'MISSING_CONTEXTS='
  refute_output --partial 'Missing context(s)'
}

@test "reports the zero-rule case and exits non-zero when no required_status_checks rule exists" {
  run bash "$SCRIPT" "$FIXTURES/ruleset-drift-check-zero-rule.json"
  assert_failure
  assert_output --partial 'has no required_status_checks rule'
  assert_output --partial 'RULE_COUNT=0'
}

@test "names every expected context as missing when the whole rule is absent" {
  # The zero-rule case is the exact "rule vanished entirely" incident
  # this guard exists to catch -- MISSING_CONTEXTS must still be
  # populated here (not just RULE_COUNT=0), or a caller building an
  # escalation issue body from this output (see
  # scripts/escalate-ruleset-drift.sh) would report an empty diff.
  run bash "$SCRIPT" "$FIXTURES/ruleset-drift-check-zero-rule.json"
  assert_failure
  assert_output --partial 'MISSING_CONTEXTS=Bash tests (bats),Lua syntax check,PowerShell tests (Pester),idd-advisory-convergence,lint'
  assert_output --partial 'EXTRA_CONTEXTS='
}

@test "reads from stdin when no file argument is given" {
  run bash -c "cat '$FIXTURES/ruleset-drift-check-match.json' | bash '$SCRIPT'"
  assert_success
  assert_output --partial 'contexts match the expected set'
}

@test "honors an EXPECTED_CONTEXTS override instead of the built-in default" {
  export EXPECTED_CONTEXTS=$'lint\nBash tests (bats)\nLua syntax check\nPowerShell tests (Pester)\nidd-advisory-convergence'
  run bash "$SCRIPT" "$FIXTURES/ruleset-drift-check-missing-context.json"
  assert_failure
  assert_output --partial 'Missing context(s): lint'
}
