#!/usr/bin/env bats
# Tests for scripts/rerun-stale-advisory-convergence.sh (issue #433):
# the diagnose-a-stale-idd-advisory-convergence-instance-and-rerun-it
# sequence the maintainer previously applied by hand across roadmap
# #419. Runs entirely against a stubbed `gh` binary
# (tests/bash/fixtures/rerun-stale-advisory-convergence-gh-stub.sh)
# prepended onto PATH, mirroring
# tests/bash/ruleset-drift-escalation.bats's house style -- no test
# here ever calls the real GitHub API or reruns a real workflow.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/rerun-stale-advisory-convergence.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  GH_STUB="$FIXTURES/rerun-stale-advisory-convergence-gh-stub.sh"

  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  cp "$GH_STUB" "$STUB_BIN/gh"
  chmod +x "$STUB_BIN/gh"
  PATH="$STUB_BIN:$PATH"

  export GH_CALL_LOG="$BATS_TEST_TMPDIR/gh-calls.log"
  : >"$GH_CALL_LOG"

  export GH_STUB_PR_HEAD_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-pr-head.json"

  # Every scenario resolves near-instantly against the stub (see the
  # stub's own header comment: attempt is derived from the call log,
  # not real elapsed time), so a short poll interval keeps even the
  # deliberate poll-timeout test below fast without ever sleeping for
  # real.
  export RERUN_STALE_ADVISORY_POLL_INTERVAL=0

  OLD_SHA='1111111111111111111111111111111111111111'
}

@test "is executable" {
  [ -x "$SCRIPT" ]
}

@test "rejects a missing PR number argument" {
  run bash "$SCRIPT"
  assert_failure
  assert_output --partial 'expected exactly one PR number argument'
}

@test "rejects a non-numeric PR number argument" {
  run bash "$SCRIPT" not-a-number
  assert_failure
  assert_output --partial 'PR number must be numeric: not-a-number'
}

@test "reports nothing to do and exits 0 when no stale check-run instance exists" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-empty.json"

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'nothing to do'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "skips a stale instance whose log does not carry the exact reason string" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-no-match.txt"

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'SKIPPED=1001:reason-not-matched'
  assert_output --partial 'RERUN_COUNT=0'
  refute_output --partial 'OLD_SHA='

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "skips a stale instance whose job log cannot be fetched" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FETCH_FAIL=1

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'SKIPPED=1001:log-fetch-failed'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "parses the old-sha and skips when no covering Copilot review exists yet" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-not-covering.json"

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial "OLD_SHA=${OLD_SHA}"
  assert_output --partial 'SKIPPED=1001:no-covering-review'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "skips when the parsed reason string's HEAD does not match the PR's actual current head" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-mismatched-head.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial "OLD_SHA=${OLD_SHA}"
  assert_output --partial 'SKIPPED=1001:stale-head-mismatch'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "reruns exactly once and succeeds when the reason matches and a covering review exists" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_CONCLUSION_ATTEMPT_2=success

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial "OLD_SHA=${OLD_SHA}"
  assert_output --partial 'ACTED=5001:success'
  assert_output --partial 'RERUN_COUNT=1'

  run bash -c "grep -c '^CALL: run rerun 5001\$' '$GH_CALL_LOG'"
  assert_output '1'
}

@test "deduplicates two check-run records sharing the same run id, reruns only once" {
  # filter=all can surface more than one check-run record for
  # different attempts of the very same underlying workflow run (here:
  # job 1001 and job 1002, both under run 5001's details_url). Both
  # records independently pass their own log/reason/review checks
  # (this stub serves the same log fixture regardless of job id), but
  # the second must be deduplicated at the mutation point rather than
  # triggering a second rerun of the same run id.
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-duplicate-run-id.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_CONCLUSION_ATTEMPT_2=success

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial "OLD_SHA=${OLD_SHA}"
  assert_output --partial 'ACTED=5001:success'
  assert_output --partial 'SKIPPED=1002:duplicate-run-id'
  assert_output --partial 'RERUN_COUNT=1'

  run bash -c "grep -c '^CALL: run rerun 5001\$' '$GH_CALL_LOG'"
  assert_output '1'
}

@test "still reruns when an earlier duplicate record for the same run id is ineligible" {
  # The Copilot-flagged failure mode: job 1001 (processed first) has a
  # non-matching log and would be skipped on its own merits, but job
  # 1002 -- a second check-run record for the *same* run id 5001 --
  # has the eligible log. Deduplicating before inspecting logs would
  # have discarded 1002 behind 1001's own ineligibility; the
  # mutation-point dedup must not do that.
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-duplicate-run-id.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-no-match.txt"
  export GH_STUB_LOG_FIXTURE_JOB_1002="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_CONCLUSION_ATTEMPT_2=success

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'SKIPPED=1001:reason-not-matched'
  assert_output --partial 'ACTED=5001:success'
  assert_output --partial 'RERUN_COUNT=1'

  run bash -c "grep -c '^CALL: run rerun 5001\$' '$GH_CALL_LOG'"
  assert_output '1'
}

@test "skips (fail-closed) a candidate whose details_url does not carry a valid run id" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-invalid-run-id.json"

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'SKIPPED=1001:invalid-run-id'
  assert_output --partial 'RERUN_COUNT=0'
  refute_output --partial 'OLD_SHA='

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
  refute_output --partial 'CALL: api repos/{owner}/{repo}/actions/runs/'
}

@test "matches a cancelled starting conclusion too, and reruns it once to success" {
  # The script's own candidate filter matches conclusion == failure OR
  # conclusion == cancelled -- exercised here with a check-run whose
  # *own* stale conclusion (before any rerun) is cancelled, distinct
  # from the cancelled-*rerun-result* case below.
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate-cancelled.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_CONCLUSION_ATTEMPT_2=success

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'ACTED=5002:success'
  assert_output --partial 'RERUN_COUNT=1'
}

@test "reruns a second time when the first rerun resolves to cancelled, then succeeds" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_CONCLUSION_ATTEMPT_2=cancelled
  export GH_STUB_CONCLUSION_ATTEMPT_3=success

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'ACTED=5001:success'
  assert_output --partial 'RERUN_COUNT=2'

  run bash -c "grep -c '^CALL: run rerun 5001\$' '$GH_CALL_LOG'"
  assert_output '2'
}

@test "exits non-zero when an attempted rerun resolves to failure" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_CONCLUSION_ATTEMPT_2=failure

  run bash "$SCRIPT" 426
  assert_failure
  assert_output --partial 'ACTED=5001:failure'
  assert_output --partial 'RERUN_COUNT=1'
}

@test "exits non-zero and reports a timeout when a rerun never completes within the poll bound" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_STAY_INCOMPLETE=1
  export RERUN_STALE_ADVISORY_MAX_POLLS=2

  run bash "$SCRIPT" 426
  assert_failure
  assert_output --partial 'ACTED=5001:timeout'
  assert_output --partial 'RERUN_COUNT=1'
}

@test "never sends the unsupported --allow-escape-sequences flag on the log fetch" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_CONCLUSION_ATTEMPT_2=success

  run bash "$SCRIPT" 426
  assert_success

  run cat "$GH_CALL_LOG"
  refute_output --partial '--allow-escape-sequences'
}

@test "excludes a same-named check-run instance from a different app/integration" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-wrong-app.json"

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'nothing to do'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "flattens every paginated check-runs page before filtering candidates" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-multi-page.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_CONCLUSION_ATTEMPT_2=success

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial "OLD_SHA=${OLD_SHA}"
  assert_output --partial 'ACTED=5001:success'
  assert_output --partial 'RERUN_COUNT=1'

  run cat "$GH_CALL_LOG"
  assert_output --partial -- '--paginate'
  assert_output --partial -- '--slurp'
}

@test "accepts a covering review reported under the [bot]-suffixed login form" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering-bot-suffix.json"
  export GH_STUB_CONCLUSION_ATTEMPT_2=success

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'ACTED=5001:success'
}

@test "skips and never reruns when the PR head changes between the initial fetch and the rerun check" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_PR_HEAD_FIXTURE_2="$FIXTURES/rerun-stale-advisory-convergence-pr-head-changed.json"

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial "OLD_SHA=${OLD_SHA}"
  assert_output --partial 'SKIPPED=1001:head-changed'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "excludes a same-named candidate produced by a different workflow file" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_WORKFLOW_PATH='.github/workflows/some-other-workflow.yml'

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'SKIPPED=1001:wrong-workflow'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
  refute_output --partial 'CALL: api repos/{owner}/{repo}/actions/jobs'
}

@test "requires the latest Copilot review specifically, not merely any matching one" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-latest-not-covering.json"

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'SKIPPED=1001:no-covering-review'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "skips (fail-closed) when the workflow-identity lookup itself fails" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_RUN_LOOKUP_FAIL=1

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'SKIPPED=1001:wrong-workflow'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "excludes a same-named candidate triggered via pull_request instead of pull_request_target" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_WORKFLOW_EVENT='pull_request'

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'SKIPPED=1001:wrong-workflow'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "reports attempt-lookup-failed and exits non-zero when the pre-rerun attempt lookup fails" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_RUN_LOOKUP_FAIL_AFTER_FIRST_CALL=1

  run bash "$SCRIPT" 426
  assert_failure
  assert_output --partial 'ACTED=5001:attempt-lookup-failed'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "excludes a candidate whose run is associated with a different PR" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_WORKFLOW_PR_NUMBER=999

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'SKIPPED=1001:wrong-workflow'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "excludes a candidate with no PR association (fork-originated run)" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_WORKFLOW_PR_NUMBER=''

  run bash "$SCRIPT" 426
  assert_success
  assert_output --partial 'SKIPPED=1001:wrong-workflow'
  assert_output --partial 'RERUN_COUNT=0'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: run rerun'
}

@test "reports stale-success and exits non-zero when the PR head changes during the rerun poll" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_CONCLUSION_ATTEMPT_2=success
  export GH_STUB_PR_HEAD_FIXTURE_3="$FIXTURES/rerun-stale-advisory-convergence-pr-head-changed.json"

  run bash "$SCRIPT" 426
  assert_failure
  assert_output --partial 'ACTED=5001:stale-success'
  assert_output --partial 'RERUN_COUNT=1'
}

@test "reports the first attempt's cancelled conclusion (not a benign skip) when the head changes before the cancelled retry" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_CONCLUSION_ATTEMPT_2=cancelled
  export GH_STUB_PR_HEAD_FIXTURE_3="$FIXTURES/rerun-stale-advisory-convergence-pr-head-changed.json"

  run bash "$SCRIPT" 426
  assert_failure
  assert_output --partial 'ACTED=5001:cancelled'
  assert_output --partial 'RERUN_COUNT=1'

  run bash -c "grep -c '^CALL: run rerun 5001\$' '$GH_CALL_LOG'"
  assert_output '1'
}

@test "reports rerun-failed and exits non-zero when gh run rerun itself fails to start" {
  export GH_STUB_CHECK_RUNS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-check-runs-candidate.json"
  export GH_STUB_LOG_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-log-match.txt"
  export GH_STUB_REVIEWS_FIXTURE="$FIXTURES/rerun-stale-advisory-convergence-reviews-covering.json"
  export GH_STUB_RERUN_FAIL=1

  run bash "$SCRIPT" 426
  assert_failure
  assert_output --partial 'ACTED=5001:rerun-failed'
  assert_output --partial 'RERUN_COUNT=0'
}
