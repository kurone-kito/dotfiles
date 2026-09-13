#!/usr/bin/env bats
# Structural assertions against
# .github/workflows/idd-advisory-convergence-comment.yml's
# pull_request_review handling (#424, kurone-kito/idd-skill#2657): the
# trigger itself, the debounce step's deliberate exclusion of it, and
# the "Rerun required HEAD check" step's review-vs-comment disjunct and
# --refresh-latest flag. This job is triggered by review/comment events
# rather than by a push, so a silent regression in this wiring (e.g. the
# debounce exclusion or the review disjunct quietly dropped) would not
# surface as a failed run on this PR's own CI -- it would only surface
# as a review submission failing to force a fresh required-check
# evaluation, discovered much later. Mirrors
# tests/bash/idd-advisory-convergence-self-waiver-workflow.bats's
# yq-based approach for the sibling required workflow.
#
# `yq` ships preinstalled on the `ubuntu-latest` GitHub-hosted runner
# image this suite's own CI job runs on (.github/workflows/test.yml's
# Bash tests (bats) job); skip locally if yq is unavailable.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  command -v yq > /dev/null 2>&1 || skip "yq not available"

  WORKFLOW="$BATS_TEST_DIRNAME/../../.github/workflows/idd-advisory-convergence-comment.yml"
}

step_field() {
  local step_name="$1" field="$2"
  yq ".jobs[\"refresh-if-idd-originated\"].steps[] | select(.name == \"${step_name}\") | ${field}" "$WORKFLOW"
}

@test "pull_request_review is registered with types: [submitted]" {
  run yq -o=json -I=0 '.on.pull_request_review.types' "$WORKFLOW"
  assert_success
  assert_output '["submitted"]'
}

@test "the job timeout is 55 minutes" {
  run yq '.jobs["refresh-if-idd-originated"]["timeout-minutes"]' "$WORKFLOW"
  assert_success
  assert_output '55'
}

@test "the job does not fall back to ubuntu-slim, whose 15-minute hard cap the 55-minute timeout would silently exceed" {
  # ubuntu-slim is a single-CPU GitHub-hosted runner with a hard,
  # non-overridable 15-minute job timeout (GitHub Actions docs) --
  # incompatible with this job's own declared 55-minute wait budget.
  # Regression guard for the exact bug Copilot's review caught (PR #429).
  run yq '.jobs["refresh-if-idd-originated"]["runs-on"]' "$WORKFLOW"
  assert_success
  refute_output --partial "ubuntu-slim"
}

@test "the debounce step explicitly excludes pull_request_review" {
  run step_field "Check for newer qualifying event" '.if'
  assert_success
  assert_output "steps.origin.outputs.idd_originated == 'true' && github.event_name != 'pull_request_review'"
}

@test "the rerun step fires unconditionally for pull_request_review, else only on a non-debounced originated success" {
  # Exact-match: a future edit that silently dropped the pull_request_review
  # disjunct would leave review submissions unable to force a fresh
  # required-check evaluation, with no other test catching it (this
  # workflow's own CI runs only on review/comment events, never a push).
  run step_field "Rerun required HEAD check" '.if'
  assert_success
  assert_output "github.event_name == 'pull_request_review' || (success() && steps.origin.outputs.idd_originated == 'true' && steps.debounce.outputs.skip != 'true')"
}

@test "REFRESH_FLAG is --refresh-latest only for pull_request_review, empty otherwise" {
  run step_field "Rerun required HEAD check" '.env.REFRESH_FLAG'
  assert_success
  assert_output "\${{ github.event_name == 'pull_request_review' && '--refresh-latest' || '' }}"
}
