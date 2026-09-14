#!/usr/bin/env bash
# Mechanizes the manual "diagnose a stale idd-advisory-convergence
# check-run instance, confirm a fresh Copilot review already covers
# the current HEAD, then rerun it" sequence this repository's
# maintainer applied by hand across roadmap #419 (see issue #433 for
# the incident history: at least 15 stale FAILURE/CANCELLED instances
# across 6 of 7 merged PRs, each caused by the check evaluating before
# a later Copilot review landed on the exact HEAD it should have
# checked).
#
# Usage: scripts/rerun-stale-advisory-convergence.sh <pr-number>
#
# For the PR's current head commit, fetches every
# `idd-advisory-convergence` check-run instance
# (`gh api repos/{owner}/{repo}/commits/{sha}/check-runs`; `gh api`'s
# own auto-templated `{owner}`/`{repo}` placeholders, same convention
# as idd-merge.instructions.md F4). For each `failure`/`cancelled`
# instance:
#
#   1. Reads that specific check-run's own job log via
#      `gh api repos/{owner}/{repo}/actions/jobs/{job-id}/logs` --
#      *not* `gh run view <run-id> --log`, which only ever returns the
#      run's *current* (latest) attempt: once a stale instance's own
#      run has since been rerun to a newer attempt, `--log` no longer
#      surfaces the older attempt's content at all, silently hiding
#      the exact reason string this script depends on (confirmed
#      empirically against this repository's own historical runs
#      while authoring this script). A check-run's own `id` field is
#      the same job id embedded in its `details_url`
#      (`.../runs/<run-id>/job/<job-id>`), so no separate lookup is
#      needed to resolve it.
#   2. Searches that log (unanchored -- each line carries its own
#      timestamp prefix) for the exact reason string
#      `latest copilot review (commit <old-sha>) does not cover
#      current HEAD <new-sha>` (byte-for-byte confirmed against this
#      repository's own recent stale-rollup incidents). No match, a
#      log-fetch failure, or a parsed `<new-sha>` that does not equal
#      the PR's actual current head -> skip, never rerun (acceptance
#      criterion 7 -- this must never become a blanket
#      retry-any-failing-check hammer).
#   3. Confirms, via `gh pr view --json reviews`, that a
#      `copilot-pull-request-reviewer` review already covers the PR's
#      actual current head (not the stale run's own parsed
#      `<new-sha>`, which is only ever asserted equal to it above --
#      checked against the freshly re-fetched head defensively). No
#      covering review -> skip, never rerun.
#   4. Otherwise, `gh run rerun <run-id>` (the *run* id, parsed from
#      `details_url` -- distinct from the job id used for the log
#      fetch above) and polls until that run's `attempt` counter has
#      advanced past its pre-rerun value *and* `status` is
#      `completed` -- checking `status` alone races a genuinely
#      transient window where GitHub still reports the *previous*
#      attempt's terminal `status`/`conclusion` for a few seconds
#      after the rerun call returns. `conclusion == cancelled` (this
#      repository has observed this happen, apparently deduplicated
#      against a concurrently triggered sibling rerun) retries exactly
#      once more, same wait; anything else terminal, or the poll bound
#      being exhausted, counts as a failed remediation attempt.
#
# Output contract (stdout): one `OLD_SHA=<sha>` line per candidate
# whose reason string parsed successfully, one
# `SKIPPED=<job-id>:<reason>` or `ACTED=<run-id>:<conclusion-or-
# timeout>` line per candidate, and a final `RERUN_COUNT=<n>` line.
# Exits 0 when every candidate was a no-op or skip, or every attempted
# rerun resolved to `success`; exits 1 when any attempted rerun did not
# resolve to `success` (including a second `cancelled`, a `failure`, or
# a poll timeout).
#
# Poll bounds are overridable via RERUN_STALE_ADVISORY_MAX_POLLS
# (default 30) and RERUN_STALE_ADVISORY_POLL_INTERVAL seconds (default
# 5), so tests can drive them down to run near-instantly.
set -euo pipefail

CHECK_NAME='idd-advisory-convergence'
REASON_REGEX='latest copilot review \(commit [0-9a-f]{40}\) does not cover current HEAD [0-9a-f]{40}'

MAX_POLLS="${RERUN_STALE_ADVISORY_MAX_POLLS:-30}"
POLL_INTERVAL="${RERUN_STALE_ADVISORY_POLL_INTERVAL:-5}"

die() {
  echo "rerun-stale-advisory-convergence.sh: $*" >&2
  exit 1
}

usage() {
  echo "Usage: $(basename "$0") <pr-number>" >&2
}

# run_id_from_details_url -- extracts the workflow *run* id from a
# check-run's details_url
# (https://…/actions/runs/<run-id>/job/<job-id>[...]). Distinct from
# the check-run's own `id` field (the *job* id), which is used
# separately for the per-attempt log fetch.
run_id_from_details_url() {
  printf '%s' "$1" | sed -E 's#.*/actions/runs/([0-9]+)/job/[0-9]+.*#\1#'
}

# parse_reason -- prints "<old-sha> <new-sha>" (space-separated) to
# stdout when the exact reason string is found anywhere in the given
# log text (the last match wins, in case a retried step logged it more
# than once), or nothing when it is absent.
parse_reason() {
  local log="$1" match
  match=$(printf '%s' "$log" | grep -oE "$REASON_REGEX" | tail -n1) || true
  [ -n "$match" ] || return 0
  printf '%s' "$match" | sed -E 's/^latest copilot review \(commit ([0-9a-f]{40})\) does not cover current HEAD ([0-9a-f]{40})$/\1 \2/'
}

# has_covering_review -- true (exit 0) when a
# copilot-pull-request-reviewer review already covers the given head
# sha for the given PR.
has_covering_review() {
  local pr="$1" head_sha="$2" reviews_json count
  reviews_json=$(gh pr view "$pr" --json reviews)
  count=$(printf '%s' "$reviews_json" | jq --arg sha "$head_sha" \
    '[.reviews[] | select(.author.login == "copilot-pull-request-reviewer" and .commit.oid == $sha)] | length')
  [ "$count" -gt 0 ]
}

# wait_for_rerun_conclusion -- polls the given run id until its
# `attempt` counter has advanced past prior_attempt *and* `status` is
# `completed`, then prints the resulting `conclusion`. Checking
# `status` alone is not sufficient: for a few seconds after `gh run
# rerun` returns, GitHub can still report the *previous* attempt's
# terminal status/conclusion, which would otherwise be misread as the
# rerun's own result. Prints `timeout` if the poll bound is exhausted
# first.
wait_for_rerun_conclusion() {
  local run_id="$1" prior_attempt="$2" polls=0 json status attempt conclusion
  while [ "$polls" -lt "$MAX_POLLS" ]; do
    json=$(gh run view "$run_id" --json status,conclusion,attempt)
    status=$(printf '%s' "$json" | jq -r '.status')
    attempt=$(printf '%s' "$json" | jq -r '.attempt')
    conclusion=$(printf '%s' "$json" | jq -r '.conclusion')
    if [ "$attempt" -gt "$prior_attempt" ] && [ "$status" = 'completed' ]; then
      printf '%s' "$conclusion"
      return 0
    fi
    polls=$((polls + 1))
    sleep "$POLL_INTERVAL"
  done
  printf 'timeout'
}

# rerun_and_wait -- reruns the given run id once and waits for its
# conclusion, retrying exactly once more if the first attempt resolves
# to `cancelled`. Prints "<attempts-triggered> <final-conclusion>"
# (space-separated) so the caller can fold `<attempts-triggered>` into
# its own running RERUN_COUNT without this function touching any
# caller-scoped variable directly (deliberately avoids bash namerefs,
# which macOS's shipped bash -- 3.2, no `local -n` support -- cannot
# run).
rerun_and_wait() {
  local run_id="$1" attempts=0 prior_attempt conclusion

  prior_attempt=$(gh run view "$run_id" --json attempt | jq -r '.attempt')
  gh run rerun "$run_id" >/dev/null
  attempts=$((attempts + 1))
  conclusion=$(wait_for_rerun_conclusion "$run_id" "$prior_attempt")

  if [ "$conclusion" = 'cancelled' ]; then
    prior_attempt=$(gh run view "$run_id" --json attempt | jq -r '.attempt')
    gh run rerun "$run_id" >/dev/null
    attempts=$((attempts + 1))
    conclusion=$(wait_for_rerun_conclusion "$run_id" "$prior_attempt")
  fi

  printf '%s %s' "$attempts" "$conclusion"
}

main() {
  [ $# -eq 1 ] || {
    usage
    die 'expected exactly one PR number argument'
  }
  case "$1" in
    '' | *[!0-9]*) die "PR number must be numeric: $1" ;;
  esac
  local pr="$1"

  local head_sha
  head_sha=$(gh pr view "$pr" --json headRefOid | jq -r '.headRefOid')
  [ -n "$head_sha" ] || die "could not resolve the current head commit for PR #${pr}"

  local check_runs_json candidates_json candidate_count
  check_runs_json=$(gh api "repos/{owner}/{repo}/commits/${head_sha}/check-runs?check_name=${CHECK_NAME}&per_page=100")
  candidates_json=$(printf '%s' "$check_runs_json" | jq -c '[.check_runs[] | select(.conclusion == "failure" or .conclusion == "cancelled")]')
  candidate_count=$(printf '%s' "$candidates_json" | jq 'length')

  if [ "$candidate_count" -eq 0 ]; then
    echo "nothing to do: no stale ${CHECK_NAME} instance found for PR #${pr} (head ${head_sha})"
    echo 'RERUN_COUNT=0'
    exit 0
  fi

  local rerun_count=0 overall_exit=0 idx=0
  while [ "$idx" -lt "$candidate_count" ]; do
    local item job_id details_url run_id log
    item=$(printf '%s' "$candidates_json" | jq -c ".[$idx]")
    job_id=$(printf '%s' "$item" | jq -r '.id')
    details_url=$(printf '%s' "$item" | jq -r '.details_url')
    run_id=$(run_id_from_details_url "$details_url")

    if ! log=$(gh api "repos/{owner}/{repo}/actions/jobs/${job_id}/logs" --allow-escape-sequences 2>/dev/null); then
      echo "SKIPPED=${job_id}:log-fetch-failed"
      idx=$((idx + 1))
      continue
    fi

    local parsed old_sha new_sha
    parsed=$(parse_reason "$log")
    if [ -z "$parsed" ]; then
      echo "SKIPPED=${job_id}:reason-not-matched"
      idx=$((idx + 1))
      continue
    fi
    old_sha=$(printf '%s' "$parsed" | cut -d' ' -f1)
    new_sha=$(printf '%s' "$parsed" | cut -d' ' -f2)
    echo "OLD_SHA=${old_sha}"

    if [ "$new_sha" != "$head_sha" ]; then
      echo "SKIPPED=${job_id}:stale-head-mismatch"
      idx=$((idx + 1))
      continue
    fi

    if ! has_covering_review "$pr" "$head_sha"; then
      echo "SKIPPED=${job_id}:no-covering-review"
      idx=$((idx + 1))
      continue
    fi

    local result attempts conclusion
    result=$(rerun_and_wait "$run_id")
    attempts=$(printf '%s' "$result" | cut -d' ' -f1)
    conclusion=$(printf '%s' "$result" | cut -d' ' -f2)
    rerun_count=$((rerun_count + attempts))

    if [ "$conclusion" = 'success' ]; then
      echo "ACTED=${run_id}:success"
    else
      echo "ACTED=${run_id}:${conclusion}"
      overall_exit=1
    fi

    idx=$((idx + 1))
  done

  echo "RERUN_COUNT=${rerun_count}"
  exit "$overall_exit"
}

main "$@"
