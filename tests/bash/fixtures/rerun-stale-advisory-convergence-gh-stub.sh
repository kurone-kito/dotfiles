#!/usr/bin/env bash
# Stub `gh` binary for tests/bash/rerun-stale-advisory-convergence.bats.
# Records every invocation (one line per call, verbatim argv) to the
# file at $GH_CALL_LOG, mirroring
# tests/bash/fixtures/ruleset-drift-escalation-gh-stub.sh's own
# call-log convention, and returns canned fixture content for the
# read-only lookups the real script depends on:
#
#   - `gh pr view <pr> --json headRefOid` -> cats
#     $GH_STUB_PR_HEAD_FIXTURE.
#   - `gh pr view <pr> --json reviews` -> cats
#     $GH_STUB_PR_REVIEWS_FIXTURE.
#   - `gh api repos/{owner}/{repo}/commits/<sha>/check-runs?...` -> cats
#     $GH_STUB_CHECK_RUNS_FIXTURE.
#   - `gh api repos/{owner}/{repo}/actions/jobs/<id>/logs
#     --allow-escape-sequences` -> cats $GH_STUB_LOG_FIXTURE, or exits 1
#     with a 404-shaped stderr message when $GH_STUB_LOG_FETCH_FAIL=1
#     (simulating a real log-fetch failure -- expired logs, API error
#     -- so a test can assert the real script treats that as a skip,
#     never a rerun).
#   - `gh run rerun <run-id>` -> pure recording no-op, exit 0. Never
#     talks to GitHub, so these tests never trigger a real workflow
#     rerun.
#   - `gh run view <run-id> --json attempt` and
#     `gh run view <run-id> --json status,conclusion,attempt` ->
#     stateful, derived entirely from how many
#     `CALL: run rerun <run-id>` lines this run id already has in
#     $GH_CALL_LOG at query time (call it N): reports `attempt =
#     N + 1`. `status,conclusion,attempt` additionally reports
#     `conclusion` from $GH_STUB_CONCLUSION_ATTEMPT_<N+1> (default
#     `failure`, i.e. the original stale conclusion, for the
#     pre-rerun attempt 1) -- so a test drives the whole
#     rerun-then-poll sequence deterministically by pre-exporting one
#     env var per attempt number it expects the real script to reach,
#     with no real waiting or GitHub calls involved. Setting
#     $GH_STUB_STAY_INCOMPLETE=1 instead always reports `status:
#     queued` (never `completed`), for exercising the poll-bound
#     timeout path.
set -euo pipefail

: "${GH_CALL_LOG:?GH_CALL_LOG must be set by the test}"
printf 'CALL: %s\n' "$*" >>"$GH_CALL_LOG"

run_id="${3:-}"

case "${1:-} ${2:-}" in
  "pr view")
    if printf '%s\n' "$*" | grep -q -- '--json headRefOid'; then
      cat "${GH_STUB_PR_HEAD_FIXTURE:?GH_STUB_PR_HEAD_FIXTURE must be set}"
      exit 0
    fi
    if printf '%s\n' "$*" | grep -q -- '--json reviews'; then
      cat "${GH_STUB_PR_REVIEWS_FIXTURE:?GH_STUB_PR_REVIEWS_FIXTURE must be set}"
      exit 0
    fi
    echo "gh-stub: unrecognized pr view invocation: $*" >&2
    exit 1
    ;;
  "run rerun")
    exit 0
    ;;
  "run view")
    rerun_count=$(grep -c "^CALL: run rerun ${run_id}\$" "$GH_CALL_LOG" || true)
    attempt=$((rerun_count + 1))
    if printf '%s\n' "$*" | grep -q -- '--json status,conclusion,attempt'; then
      if [ "${GH_STUB_STAY_INCOMPLETE:-0}" = '1' ]; then
        printf '{"status":"queued","conclusion":null,"attempt":%d}\n' "$attempt"
        exit 0
      fi
      conclusion_var="GH_STUB_CONCLUSION_ATTEMPT_${attempt}"
      conclusion="${!conclusion_var:-failure}"
      printf '{"status":"completed","conclusion":"%s","attempt":%d}\n' "$conclusion" "$attempt"
      exit 0
    fi
    if printf '%s\n' "$*" | grep -q -- '--json attempt'; then
      printf '{"attempt":%d}\n' "$attempt"
      exit 0
    fi
    echo "gh-stub: unrecognized run view invocation: $*" >&2
    exit 1
    ;;
esac

if [ "${1:-}" = 'api' ]; then
  case "${2:-}" in
    */check-runs*)
      cat "${GH_STUB_CHECK_RUNS_FIXTURE:?GH_STUB_CHECK_RUNS_FIXTURE must be set}"
      exit 0
      ;;
    */actions/jobs/*/logs)
      if [ "${GH_STUB_LOG_FETCH_FAIL:-0}" = '1' ]; then
        echo 'gh: Not Found (HTTP 404)' >&2
        exit 1
      fi
      cat "${GH_STUB_LOG_FIXTURE:?GH_STUB_LOG_FIXTURE must be set}"
      exit 0
      ;;
  esac
fi

echo "gh-stub: unrecognized invocation: $*" >&2
exit 1
