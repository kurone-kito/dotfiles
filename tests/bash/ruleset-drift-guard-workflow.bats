#!/usr/bin/env bats
# Structural assertions against
# .github/workflows/ruleset-required-checks-guard.yml's step-level
# failure-handling wiring (#317). This workflow has no `pull_request`
# trigger, so PR CI never actually executes the job -- these checks are
# the only automated coverage of the `if:`/`continue-on-error`/outcome
# wiring itself (as opposed to scripts/escalate-ruleset-drift.sh's own
# logic, covered by tests/bash/ruleset-drift-escalation.bats). Without
# them, a future edit that reintroduces a bare `if:` or drops a step id
# would go undetected until the next real scheduled failure.
#
# Uses `yq` (mikefarah/yq) to query the YAML structurally instead of
# grepping the raw text, so these assertions survive reformatting.
# `yq` ships preinstalled on the `ubuntu-latest` GitHub-hosted runner
# image this suite's own CI job runs on; skip locally if unavailable.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  command -v yq > /dev/null 2>&1 || skip "yq not available"

  WORKFLOW="$BATS_TEST_DIRNAME/../../.github/workflows/ruleset-required-checks-guard.yml"
}

step_field() {
  local step_name="$1" field="$2"
  yq ".jobs.guard.steps[] | select(.name == \"${step_name}\") | ${field}" "$WORKFLOW"
}

@test "Fetch ruleset rules and Find open tracking issue both carry continue-on-error: true" {
  run step_field "Fetch ruleset rules" '.["continue-on-error"]'
  assert_success
  assert_output 'true'

  run step_field "Find open tracking issue" '.["continue-on-error"]'
  assert_success
  assert_output 'true'
}

@test "Check drift only runs after Fetch ruleset rules succeeded" {
  run step_field "Check drift" '.if'
  assert_success
  assert_output "steps.fetch.outcome == 'success'"
}

@test "Escalate on failure and the job-failure step react to any of the three checked steps' outcomes" {
  for step_name in "Escalate on failure" "Fail the job on any check failure"; do
    run step_field "$step_name" '.if'
    assert_success
    assert_output --partial 'always()'
    assert_output --partial "steps.fetch.outcome == 'failure'"
    assert_output --partial "steps.check.outcome == 'failure'"
    assert_output --partial "steps.find-issue.outcome == 'failure'"
  done
}

@test "Recover on success still only fires when Check drift itself succeeded" {
  run step_field "Recover on success" '.if'
  assert_success
  assert_output --partial "steps.check.outcome == 'success'"
}

@test "the workflow file has no remaining step literally named 'Fail the job on drift'" {
  # Renamed to "Fail the job on any check failure" since it now covers
  # every failure class, not only drift -- guard against a stale
  # duplicate/leftover from a future partial revert.
  run yq '.jobs.guard.steps[] | select(.name == "Fail the job on drift") | .name' "$WORKFLOW"
  assert_success
  assert_output ''
}
