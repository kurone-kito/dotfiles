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
#     already in $GH_CALL_LOG.
#   - `gh api repos/{owner}/{repo}/pulls/<pr>/reviews --paginate --jq
#     '<filter>'` -> actually runs the real `jq` binary with the exact
#     `--jq` filter argument the script passed (extracted from "$@" by
#     position, not string-matched, since the filter itself contains
#     spaces) against $GH_STUB_REVIEWS_FIXTURE -- a raw JSON array of
#     REST-shaped review objects (`user.login` / `submitted_at` /
#     `commit_id`) -- so this stub exercises the script's own real
#     `select()` login-matching logic end-to-end instead of
#     pre-filtering it away, matching real `gh api --jq`'s per-page
#     streamed-output behavior closely enough for this single-page
#     fixture shape.
#   - `gh api --paginate --slurp
#     repos/{owner}/{repo}/commits/<sha>/check-runs?...` -> cats
#     $GH_STUB_CHECK_RUNS_FIXTURE (a JSON array of one object per
#     simulated page, matching real `--paginate --slurp` output
#     shape).
#   - `gh api repos/{owner}/{repo}/actions/runs/<run-id>` (no `/job/`
#     or `/logs` suffix) -> prints a single JSON object carrying every
#     field the real script reads from this endpoint, so both call
#     sites (the pre-log-fetch workflow-identity check and the
#     pre-/post-rerun attempt poll) share one stub response shape:
#       - `path`: `$GH_STUB_WORKFLOW_PATH` when set, or this
#         repository's real
#         `.github/workflows/idd-advisory-convergence.yml` otherwise --
#         so every existing test that never sets this variable
#         exercises the genuine-workflow path by default, and a test
#         can override it to simulate a spoofed same-named run from a
#         different workflow file.
#       - `event`: `$GH_STUB_WORKFLOW_EVENT` when set, or
#         `pull_request_target` otherwise -- overridable the same way
#         to simulate a spoofed `pull_request`-triggered run.
#       - `pull_requests`: `[{"number": 426}]` (every test invokes the
#         script against PR 426) unless `$GH_STUB_WORKFLOW_PR_NUMBER` is
#         set, in which case `[{"number": <that value>}]` -- so a test
#         can simulate a run genuinely associated with a *different*
#         PR; set it to the empty string to simulate a fork-originated
#         PR's empty `pull_requests` array instead.
#       - `run_attempt`: stateful, derived entirely from how many
#         `CALL: run rerun <run-id>` lines this run id already has in
#         $GH_CALL_LOG at query time (call it N): reports `N + 1`.
#       - `status` / `conclusion`: `status` is always `completed`
#         unless $GH_STUB_STAY_INCOMPLETE=1 (always `queued`, for
#         exercising the poll-bound timeout path); `conclusion` comes
#         from $GH_STUB_CONCLUSION_ATTEMPT_<run_attempt> (default
#         `failure`, i.e. the original stale conclusion, for the
#         pre-rerun attempt 1) -- so a test drives the whole
#         rerun-then-poll sequence deterministically by pre-exporting
#         one env var per attempt number it expects the real script to
#         reach, with no real waiting or GitHub calls involved.
#     $GH_STUB_RUN_LOOKUP_FAIL=1 makes every call to this endpoint exit
#     1 instead (simulating a transient Actions-API failure across all
#     call sites); $GH_STUB_RUN_LOOKUP_FAIL_AFTER_FIRST_CALL=1 instead
#     lets the first call for a given run id succeed (the
#     pre-log-fetch workflow-identity check) and fails every call
#     after it (the pre-/post-rerun attempt poll) -- so a test can
#     exercise the `attempt-lookup-failed` conclusion specifically,
#     distinct from the `wrong-workflow` skip.
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
set -euo pipefail

: "${GH_CALL_LOG:?GH_CALL_LOG must be set by the test}"
printf 'CALL: %s\n' "$*" >>"$GH_CALL_LOG"

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
  if printf '%s\n' "$*" | grep -qE -- '/pulls/[0-9]+/reviews'; then
    jq_filter=''
    prev=''
    for a in "$@"; do
      if [ "$prev" = '--jq' ]; then
        jq_filter="$a"
        break
      fi
      prev="$a"
    done
    [ -n "$jq_filter" ] || {
      echo 'gh-stub: expected --jq on the reviews endpoint' >&2
      exit 1
    }
    jq -c "$jq_filter" "${GH_STUB_REVIEWS_FIXTURE:?GH_STUB_REVIEWS_FIXTURE must be set}"
    exit 0
  fi
  if printf '%s\n' "$*" | grep -q -- '/check-runs'; then
    cat "${GH_STUB_CHECK_RUNS_FIXTURE:?GH_STUB_CHECK_RUNS_FIXTURE must be set}"
    exit 0
  fi
  if printf '%s\n' "$*" | grep -qE -- '/actions/runs/[0-9]+$'; then
    run_id=$(printf '%s\n' "$*" | grep -oE '/actions/runs/[0-9]+' | grep -oE '[0-9]+')
    lookup_call_count=$(grep -c "^CALL: api repos/{owner}/{repo}/actions/runs/${run_id}\$" "$GH_CALL_LOG" || true)
    if [ "${GH_STUB_RUN_LOOKUP_FAIL:-0}" = '1' ] ||
      { [ "$lookup_call_count" -gt 1 ] && [ "${GH_STUB_RUN_LOOKUP_FAIL_AFTER_FIRST_CALL:-0}" = '1' ]; }; then
      echo 'gh-stub: simulated actions/runs lookup failure' >&2
      exit 1
    fi
    rerun_count=$(grep -c "^CALL: run rerun ${run_id}\$" "$GH_CALL_LOG" || true)
    run_attempt=$((rerun_count + 1))
    if [ "${GH_STUB_STAY_INCOMPLETE:-0}" = '1' ]; then
      status='queued'
      conclusion='null'
    else
      status='completed'
      conclusion_var="GH_STUB_CONCLUSION_ATTEMPT_${run_attempt}"
      conclusion="\"${!conclusion_var:-failure}\""
    fi
    pr_number="${GH_STUB_WORKFLOW_PR_NUMBER-426}"
    if [ -n "$pr_number" ]; then
      pull_requests="[{\"number\": ${pr_number}}]"
    else
      pull_requests='[]'
    fi
    printf '{"path": "%s", "event": "%s", "pull_requests": %s, "run_attempt": %d, "status": "%s", "conclusion": %s}\n' \
      "${GH_STUB_WORKFLOW_PATH:-.github/workflows/idd-advisory-convergence.yml}" \
      "${GH_STUB_WORKFLOW_EVENT:-pull_request_target}" \
      "$pull_requests" "$run_attempt" "$status" "$conclusion"
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
