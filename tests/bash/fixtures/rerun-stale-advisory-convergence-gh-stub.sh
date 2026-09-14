#!/usr/bin/env bash
# Stub `gh` binary for tests/bash/rerun-stale-advisory-convergence.bats.
# Records every invocation (one line per call, verbatim argv) to the
# file at $GH_CALL_LOG, mirroring
# tests/bash/fixtures/ruleset-drift-escalation-gh-stub.sh's own
# call-log convention, and returns canned fixture content for the
# read-only lookups the real script depends on:
#
#   - `gh pr view <pr> --json headRefOid` -> cats
#     $GH_STUB_PR_HEAD_FIXTURE on its first call; on every call after
#     the first, cats $GH_STUB_PR_HEAD_FIXTURE_2 instead when that
#     variable is set (simulating a commit landing on the PR while the
#     real script is mid-run), otherwise repeats
#     $GH_STUB_PR_HEAD_FIXTURE unchanged. Call count is derived from
#     this stub's own `CALL: pr view <pr> --json headRefOid` lines
#     already in $GH_CALL_LOG, mirroring the `run view`
#     attempt-derivation convention below.
#   - `gh pr view <pr> --json reviews` -> cats
#     $GH_STUB_PR_REVIEWS_FIXTURE.
#   - `gh api --paginate --slurp
#     repos/{owner}/{repo}/commits/<sha>/check-runs?...` -> cats
#     $GH_STUB_CHECK_RUNS_FIXTURE (a JSON array of one object per
#     simulated page, matching real `--paginate --slurp` output
#     shape).
#   - `gh api repos/{owner}/{repo}/actions/jobs/<id>/logs` -> cats
#     $GH_STUB_LOG_FIXTURE, or exits 1 with a 404-shaped stderr message
#     when $GH_STUB_LOG_FETCH_FAIL=1 (simulating a real log-fetch
#     failure -- expired logs, API error -- so a test can assert the
#     real script treats that as a skip, never a rerun). Exits 1 with
#     an "unknown flag" message if the invocation still carries the
#     unsupported `--allow-escape-sequences` flag `gh api` never
#     actually accepted -- this stub deliberately does NOT accept that
#     flag, so a regression reintroducing it fails every log-fetch
#     call instead of silently passing.
#   - `gh run rerun <run-id>` -> pure recording no-op, exit 0 (or exit 1
#     with no side effect when $GH_STUB_RERUN_FAIL=1, simulating the
#     rerun call itself failing to start). Never talks to GitHub, so
#     these tests never trigger a real workflow rerun.
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
      head_call_count=$(grep -c "^CALL: pr view .* --json headRefOid\$" "$GH_CALL_LOG" || true)
      if [ "$head_call_count" -gt 1 ] && [ -n "${GH_STUB_PR_HEAD_FIXTURE_2:-}" ]; then
        cat "$GH_STUB_PR_HEAD_FIXTURE_2"
      else
        cat "${GH_STUB_PR_HEAD_FIXTURE:?GH_STUB_PR_HEAD_FIXTURE must be set}"
      fi
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
    if [ "${GH_STUB_RERUN_FAIL:-0}" = '1' ]; then
      echo 'gh-stub: simulated run rerun failure' >&2
      exit 1
    fi
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

# Real `gh api` never supported this flag; assert it stays gone rather
# than silently accepting it the way an earlier version of this stub
# did (the fixed script no longer passes it -- see the header comment
# above).
if printf '%s\n' "$*" | grep -q -- '--allow-escape-sequences'; then
  echo 'gh-stub: unknown flag: --allow-escape-sequences' >&2
  exit 1
fi

if [ "${1:-}" = 'api' ]; then
  if printf '%s\n' "$*" | grep -q -- '/check-runs'; then
    cat "${GH_STUB_CHECK_RUNS_FIXTURE:?GH_STUB_CHECK_RUNS_FIXTURE must be set}"
    exit 0
  fi
  if printf '%s\n' "$*" | grep -q -- '/actions/jobs/.*/logs'; then
    if [ "${GH_STUB_LOG_FETCH_FAIL:-0}" = '1' ]; then
      echo 'gh: Not Found (HTTP 404)' >&2
      exit 1
    fi
    cat "${GH_STUB_LOG_FIXTURE:?GH_STUB_LOG_FIXTURE must be set}"
    exit 0
  fi
fi

echo "gh-stub: unrecognized invocation: $*" >&2
exit 1
