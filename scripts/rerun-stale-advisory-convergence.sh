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
# `idd-advisory-convergence`-named check-run instance produced by the
# GitHub Actions app (`gh api --paginate --slurp
# repos/{owner}/{repo}/commits/{sha}/check-runs?...&filter=all`; `gh
# api`'s own auto-templated `{owner}`/`{repo}` placeholders, same
# convention as idd-merge.instructions.md F4). For each `failure`/
# `cancelled` instance:
#
#   1. Resolves the candidate's own workflow run
#      (`gh api repos/{owner}/{repo}/actions/runs/{run-id}`) and
#      requires both its `path` equal
#      `.github/workflows/idd-advisory-convergence.yml` exactly *and*
#      its `event` equal `pull_request_target`. The GitHub Actions app
#      id alone is not proof of origin: every Actions-produced check
#      run in the repository shares it, including one from a workflow a
#      PR branch itself adds (a fork PR, or any branch with
#      workflow-file write access) -- a branch could otherwise define
#      its own job literally named `idd-advisory-convergence` that
#      fails and prints the exact stale-rollup reason string naming the
#      PR's current head. The path check alone is not enough either:
#      this repository's own idd-advisory-convergence.yml still
#      registers `pull_request` alongside `pull_request_target` during
#      a documented migration window, and `pull_request` resolves the
#      workflow *definition* from the PR branch itself, so a
#      same-repository PR could edit that exact file to spoof a run at
#      the same path. Only `pull_request_target` resolves the workflow
#      from the base branch, immune to PR-branch tampering. No match on
#      either condition -> skip, never rerun.
#   2. Reads that specific check-run's own job log via
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
#   3. Searches that log (unanchored -- each line carries its own
#      timestamp prefix) for the exact reason string
#      `latest copilot review (commit <old-sha>) does not cover
#      current HEAD <new-sha>` (byte-for-byte confirmed against this
#      repository's own recent stale-rollup incidents). No match, a
#      log-fetch failure, or a parsed `<new-sha>` that does not equal
#      the PR's actual current head -> skip, never rerun (acceptance
#      criterion 7 -- this must never become a blanket
#      retry-any-failing-check hammer).
#   4. Confirms, via `gh pr view --json reviews`, that the *latest*
#      `copilot-pull-request-reviewer` (or `copilot-pull-request-reviewer[bot]`)
#      review already covers the PR's actual current head (not the
#      stale run's own parsed `<new-sha>`, which is only ever asserted
#      equal to it above) -- the latest review specifically, since the
#      convergence gate itself only ever evaluates the latest one; an
#      earlier review for the current head completing before a
#      later-submitted review for an older commit must not be accepted
#      as covering. No covering review -> skip, never rerun.
#   5. Re-fetches the PR's live head and requires it still equal the
#      head read at startup, immediately before authorizing the rerun
#      -- deliberately *after* the review lookup above, since that
#      lookup is itself a network round-trip a new commit could land
#      during. A commit pushed at any point up to this exact instant
#      must never let this candidate act on an already-obsolete head.
#      Any change -> skip, never rerun.
#   6. Otherwise, resolves the pre-rerun `run_attempt` via
#      `gh api repos/{owner}/{repo}/actions/runs/{run-id}` -- not
#      `gh run view --json attempt`, which does not expose this field
#      on every `gh` client version, mirroring this repository's own
#      established CI-helper convention (docs/idd-helper-scripts.md).
#      A lookup that fails or returns anything other than a positive
#      integer aborts before rerunning (never a rerun with an
#      unvalidated baseline). Then `gh run rerun <run-id>` (the *run*
#      id, parsed from `details_url` -- distinct from the job id used
#      for the log fetch above) and polls the same run-API endpoint
#      until `run_attempt` has advanced past that pre-rerun value *and*
#      `status` is `completed` -- checking `status` alone races a
#      genuinely transient window where GitHub still reports the
#      *previous* attempt's terminal `status`/`conclusion` for a few
#      seconds after the rerun call returns. `conclusion == cancelled`
#      (this repository has observed this happen, apparently
#      deduplicated against a concurrently triggered sibling rerun)
#      retries exactly once more, same wait; anything else terminal, or
#      the poll bound being exhausted, counts as a failed remediation
#      attempt. A `gh run rerun` invocation that itself fails to even
#      start never counts as a triggered attempt or advances the poll.
#
# Output contract (stdout): one `OLD_SHA=<sha>` line per candidate
# whose reason string parsed successfully, one
# `SKIPPED=<job-id>:<reason>` or `ACTED=<run-id>:<conclusion-or-
# timeout-or-rerun-failed-or-attempt-lookup-failed>` line per
# candidate, and a final `RERUN_COUNT=<n>` line. Exits 0 when every
# candidate was a no-op or skip, or every attempted rerun resolved to
# `success`; exits 1 when any attempted rerun did not resolve to
# `success` (including a second `cancelled`, a `failure`, a
# `rerun-failed`, an `attempt-lookup-failed`, or a poll timeout).
#
# Poll bounds are overridable via RERUN_STALE_ADVISORY_MAX_POLLS
# (default 30) and RERUN_STALE_ADVISORY_POLL_INTERVAL seconds (default
# 5), so tests can drive them down to run near-instantly.
set -euo pipefail

CHECK_NAME='idd-advisory-convergence'
REASON_REGEX='latest copilot review \(commit [0-9a-f]{40}\) does not cover current HEAD [0-9a-f]{40}'

# The GitHub Actions app's own integration id (confirmed against this
# repository's required-check identity in docs/idd-policy.md, "New
# 0.5.0/0.6.0 Schema Keys" -> ciGate.trustSourcePinnedRequiredChecks).
# A cheap pre-filter only -- every Actions-produced check run in the
# repository shares this same app id, so it narrows out non-Actions
# integrations early but does not by itself prove which *workflow*
# produced a candidate. is_advisory_convergence_workflow_run below is
# the actual identity proof.
GITHUB_ACTIONS_APP_ID=15368

# The exact workflow file this repository's real
# idd-advisory-convergence check runs from -- see
# is_advisory_convergence_workflow_run below for why the app id alone
# does not prove this.
ADVISORY_CONVERGENCE_WORKFLOW_PATH='.github/workflows/idd-advisory-convergence.yml'

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

# has_covering_review -- true (exit 0) when the *latest* (by
# `submittedAt`) copilot-pull-request-reviewer review for the given PR
# covers the given head sha. Accepts both the bare login and its
# `[bot]` suffix form, matching this repository's established
# Copilot-review matching contract
# (docs/idd-advisory-wait-shell-fallback.md), which itself sorts by
# submission time and selects the last entry. Checking only the latest
# review -- not "any review whose commit matches" -- matters because
# the advisory-convergence gate itself only ever evaluates the latest
# review: with overlapping asynchronous review requests, an earlier
# review for the current head can complete before a later-submitted
# review for an older commit, and accepting the earlier one alone
# would authorize a rerun the gate will still fail immediately after.
has_covering_review() {
  local pr="$1" head_sha="$2" reviews_json
  reviews_json=$(gh pr view "$pr" --json reviews)
  printf '%s' "$reviews_json" | jq -e --arg sha "$head_sha" \
    '[.reviews[] | select(.author.login == "copilot-pull-request-reviewer" or .author.login == "copilot-pull-request-reviewer[bot]")]
     | sort_by(.submittedAt) | last // empty | .commit.oid == $sha' >/dev/null
}

# current_head -- prints the PR's live current head commit sha.
# Called both at startup and again immediately before authorizing each
# rerun, since a commit pushed while this script is running (log
# fetch, review check, or an earlier candidate's rerun-and-poll) must
# never let a later candidate act on an already-obsolete head.
current_head() {
  local pr="$1"
  gh pr view "$pr" --json headRefOid | jq -r '.headRefOid'
}

# is_advisory_convergence_workflow_run -- true (exit 0) only when the
# given run id's own workflow file path is exactly
# ADVISORY_CONVERGENCE_WORKFLOW_PATH *and* its triggering `event` is
# `pull_request_target`. `GITHUB_ACTIONS_APP_ID` alone is not
# sufficient producer-identity proof: every GitHub Actions-produced
# check run in the repository -- including one from a workflow a PR
# branch itself adds (a fork PR, or any branch with workflow-file write
# access) -- shares that same app id. A branch could otherwise define
# its own job literally named `idd-advisory-convergence` that fails
# and prints the exact stale-rollup reason string naming the PR's
# current head, and app-id filtering alone would accept it as genuine.
# The workflow-path check alone is *also* not sufficient: this
# repository's own idd-advisory-convergence.yml still registers
# `pull_request` alongside `pull_request_target` during a documented
# migration window (see that file's own header comment), and
# `pull_request` resolves the workflow *definition* from the PR branch
# itself, so a same-repository PR could edit that exact file to spoof
# a run at the same path. Only `pull_request_target` resolves the
# workflow from the base branch, immune to PR-branch tampering -- the
# same trust boundary this repository's own run-bound checks already
# rely on -- so both conditions together are required before a
# candidate is accepted.
is_advisory_convergence_workflow_run() {
  local run_id="$1" run_json
  run_json=$(gh api "repos/{owner}/{repo}/actions/runs/${run_id}")
  [ "$(printf '%s' "$run_json" | jq -r '.path')" = "$ADVISORY_CONVERGENCE_WORKFLOW_PATH" ] &&
    [ "$(printf '%s' "$run_json" | jq -r '.event')" = 'pull_request_target' ]
}

# run_attempt -- prints the given run id's current `run_attempt`
# (a positive integer) via the Actions run API, or prints nothing and
# returns non-zero if the lookup fails or the field is missing/not a
# positive integer. `gh run view --json` does not expose this as
# `attempt` on every `gh` version -- this repository's own existing CI
# helpers already read `.run_attempt` from
# `gh api repos/{owner}/{repo}/actions/runs/<id>` instead
# (docs/idd-helper-scripts.md), so this mirrors that established
# convention rather than depending on a `gh run view` JSON field whose
# availability varies by client version.
run_attempt() {
  local run_id="$1" json attempt
  json=$(gh api "repos/{owner}/{repo}/actions/runs/${run_id}" 2>/dev/null) || return 1
  attempt=$(printf '%s' "$json" | jq -r '.run_attempt // empty')
  case "$attempt" in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "$attempt" -gt 0 ] || return 1
  printf '%s' "$attempt"
}

# wait_for_rerun_conclusion -- polls the given run id until its
# `run_attempt` counter has advanced past prior_attempt *and* `status`
# is `completed`, then prints the resulting `conclusion`. Checking
# `status` alone is not sufficient: for a few seconds after `gh run
# rerun` returns, GitHub can still report the *previous* attempt's
# terminal status/conclusion, which would otherwise be misread as the
# rerun's own result. Prints `timeout` if the poll bound is exhausted
# first, or if a poll iteration cannot resolve a valid `run_attempt`
# (a transient lookup failure never counts as reaching the new
# attempt).
wait_for_rerun_conclusion() {
  local run_id="$1" prior_attempt="$2" polls=0 json status attempt conclusion
  while [ "$polls" -lt "$MAX_POLLS" ]; do
    json=$(gh api "repos/{owner}/{repo}/actions/runs/${run_id}" 2>/dev/null) || json=''
    if [ -n "$json" ]; then
      status=$(printf '%s' "$json" | jq -r '.status')
      attempt=$(printf '%s' "$json" | jq -r '.run_attempt // empty')
      conclusion=$(printf '%s' "$json" | jq -r '.conclusion')
      case "$attempt" in
        '' | *[!0-9]*) attempt='' ;;
      esac
      if [ -n "$attempt" ] && [ "$attempt" -gt "$prior_attempt" ] && [ "$status" = 'completed' ]; then
        printf '%s' "$conclusion"
        return 0
      fi
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
#
# `gh run rerun`'s own exit status is checked explicitly rather than
# relying on `set -e`: this function runs inside the caller's command
# substitution (`result=$(rerun_and_wait ...)`), where non-POSIX Bash
# clears `errexit`, so a failed rerun call would otherwise be silently
# ignored -- `attempts` would still be incremented and the poll below
# would wait on a rerun that was never actually triggered, misreporting
# an unrelated concurrent attempt's outcome (or a bare timeout) as this
# call's own result. The pre-rerun `run_attempt` lookup is checked the
# same way: if it fails or returns something other than a positive
# integer, this never triggers a rerun -- an empty/zero prior_attempt
# would otherwise let a transient GitHub read of the *previous*
# attempt's already-terminal state be misread as this call's own
# newly-triggered attempt already having completed.
rerun_and_wait() {
  local run_id="$1" attempts=0 prior_attempt conclusion

  if ! prior_attempt=$(run_attempt "$run_id"); then
    printf '%s %s' "$attempts" 'attempt-lookup-failed'
    return 0
  fi
  if ! gh run rerun "$run_id" >/dev/null; then
    printf '%s %s' "$attempts" 'rerun-failed'
    return 0
  fi
  attempts=$((attempts + 1))
  conclusion=$(wait_for_rerun_conclusion "$run_id" "$prior_attempt")

  if [ "$conclusion" = 'cancelled' ]; then
    if ! prior_attempt=$(run_attempt "$run_id"); then
      printf '%s %s' "$attempts" 'attempt-lookup-failed'
      return 0
    fi
    if ! gh run rerun "$run_id" >/dev/null; then
      printf '%s %s' "$attempts" 'rerun-failed'
      return 0
    fi
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
  # `--paginate --slurp` follows every page (the endpoint's own
  # `filter` defaults to `latest`, and `per_page=100` alone only
  # bounds a single page -- either gap would silently omit a stale
  # instance sitting past the first page or outside the "latest"
  # rollup) and wraps each page's response object into a JSON array,
  # so every page's `check_runs` must be flattened with `.[].check_runs[]`
  # rather than the single-page `.check_runs[]`. The `app.id` filter
  # restricts candidates to check runs the GitHub Actions app itself
  # produced (see `GITHUB_ACTIONS_APP_ID` above) -- a same-named,
  # same-conclusion check run from a different integration must never
  # be treated as a genuine stale idd-advisory-convergence instance.
  check_runs_json=$(gh api --paginate --slurp "repos/{owner}/{repo}/commits/${head_sha}/check-runs?check_name=${CHECK_NAME}&filter=all&per_page=100")
  candidates_json=$(printf '%s' "$check_runs_json" | jq -c --argjson app_id "$GITHUB_ACTIONS_APP_ID" \
    '[.[].check_runs[] | select((.conclusion == "failure" or .conclusion == "cancelled") and .app.id == $app_id)]')
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

    if ! is_advisory_convergence_workflow_run "$run_id"; then
      echo "SKIPPED=${job_id}:wrong-workflow"
      idx=$((idx + 1))
      continue
    fi

    if ! log=$(gh api "repos/{owner}/{repo}/actions/jobs/${job_id}/logs" 2>/dev/null); then
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

    # Re-fetch the live head immediately before authorizing a rerun --
    # deliberately *after* has_covering_review above, not before it:
    # that call itself makes a network round-trip, during which a new
    # commit could still land. `head_sha` was read once at startup, so
    # a commit pushed at any point up to this exact instant (log fetch,
    # review lookup, or an earlier candidate's rerun-and-poll cycle)
    # must never let this candidate act against an already-obsolete
    # head. Fail closed (skip, never rerun) on any change rather than
    # re-deriving a new candidate set mid-loop.
    if [ "$(current_head "$pr")" != "$head_sha" ]; then
      echo "SKIPPED=${job_id}:head-changed"
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
