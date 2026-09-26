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
# convention as idd-merge.instructions.md F4). `filter=all` can return
# more than one check-run record for different attempts of the very
# same underlying workflow run (each attempt has its own job id/log),
# so every GitHub Actions-produced record for the head commit --
# *every* conclusion, not only `failure`/`cancelled` -- is first
# grouped by the workflow *run* id parsed from each one's own
# `details_url`, keeping only the most recent attempt in each group (by
# `completed_at`, falling back to `started_at`, then the check-run's
# own numeric `id` as a final deterministic tiebreaker -- see
# select_latest_attempt_job_ids below). Every other, superseded record
# in a group is skipped (`superseded-attempt`) without ever fetching
# its log -- including when the group's own latest attempt turns out to
# be a `success` (or still `in_progress`/`timed_out`): grouping across
# every conclusion, not just the failure/cancelled subset, is what
# lets an older failure be recognized as superseded once the run has
# already resolved (or is still resolving) some other way, rather than
# being crowned "latest" purely because the actually-latest record was
# filtered out before grouping ever saw it. This is deliberate, not
# merely an optimization:
# `gh run rerun <run-id>` always operates on that run's *current*
# (latest) attempt, so the latest attempt's own log is the only one
# that reflects what a rerun would actually re-execute. Picking any
# other attempt's record to justify eligibility is actively unsafe --
# an older attempt's log can carry the exact stale-reason match this
# script looks for while the run's current attempt has since failed for
# a genuinely different, unrelated reason (e.g. a prior manual rerun
# that surfaced a real bug); authorizing a rerun from the older
# attempt's stale match would then rerun that unrelated current failure
# under false pretenses, defeating the exact-reason safety guard
# (acceptance criterion 7 -- this must never become a blanket
# retry-any-failing-check hammer). Grouping by recency rather than by
# array position also avoids the opposite failure mode: an eligible
# latest attempt must never be discarded just because some other,
# unrelated record for the same run id happens to sort earlier. For
# each remaining (latest-attempt) `failure`/`cancelled` instance:
#
#   1. Resolves the candidate's own workflow run
#      (`gh api repos/{owner}/{repo}/actions/runs/{run-id}`) and
#      requires its `path` equal
#      `.github/workflows/idd-advisory-convergence.yml` exactly, its
#      `event` equal `pull_request_target`, *and* its `pull_requests[]`
#      array include this exact PR number. The GitHub Actions app id
#      alone is not proof of origin: every Actions-produced check run in
#      the repository shares it, including one from a workflow a PR
#      branch itself adds (a fork PR, or any branch with workflow-file
#      write access) -- a branch could otherwise define its own job
#      literally named `idd-advisory-convergence` that fails and prints
#      the exact stale-rollup reason string naming the PR's current
#      head. The path check alone is not enough either: this
#      repository's own idd-advisory-convergence.yml registered
#      `pull_request` alongside `pull_request_target` during a
#      migration window that #501 closed, and `pull_request` resolves the
#      workflow *definition* from the PR branch itself, so a
#      same-repository PR could edit that exact file to spoof a run at
#      the same path. Only `pull_request_target` resolves the workflow
#      from the base branch, immune to PR-branch tampering. Finally, the
#      check-runs lookup below is scoped only by commit SHA, and the
#      same SHA can be associated with more than one open PR -- without
#      the `pull_requests[]` check, this could rerun a genuine
#      `pull_request_target` run created for a *different* PR (see
#      docs/customization.md's run-attribution guidance); an empty
#      `pull_requests[]` (always true for a fork-originated PR) fails
#      closed rather than being treated as an unverifiable pass. No
#      match on any condition -> skip, never rerun.
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
#   4. Confirms, via the paginated REST reviews endpoint
#      (`gh api repos/{owner}/{repo}/pulls/{pr}/reviews --paginate`,
#      not `gh pr view --json reviews`, whose bounded connection can
#      omit the true latest review on a PR with enough reviews), that
#      the *latest* `copilot-pull-request-reviewer` (or
#      `copilot-pull-request-reviewer[bot]`) review already covers the
#      PR's actual current head (not the stale run's own parsed
#      `<new-sha>`, which is only ever asserted equal to it above) --
#      the latest review specifically, since the convergence gate
#      itself only ever evaluates the latest one; an earlier review for
#      the current head completing before a later-submitted review for
#      an older commit must not be accepted as covering. No covering
#      review -> skip, never rerun.
#   5. Resolves the pre-rerun `run_attempt` via
#      `gh api repos/{owner}/{repo}/actions/runs/{run-id}` -- not
#      `gh run view --json attempt`, which does not expose this field
#      on every `gh` client version, mirroring this repository's own
#      established CI-helper convention (docs/idd-helper-scripts.md).
#      A lookup that fails or returns anything other than a positive
#      integer aborts before rerunning (never a rerun with an
#      unvalidated baseline). *Then*, immediately afterward, re-fetches
#      the PR's live head and requires it still equal the head read at
#      startup, immediately before **each** `gh run rerun` call in step
#      6 below (both the first attempt and the cancelled-retry
#      attempt) -- not once here after the review lookup, and
#      deliberately *after* the `run_attempt` lookup rather than
#      before it: that lookup is itself a network round-trip a new
#      commit could land during, so placing the head check after it
#      leaves `gh run rerun` as the very next call with nothing else
#      in between, the tightest ordering these two independent reads
#      allow. Any head change -> skip, never rerun (see
#      rerun_and_wait's own comment for how the first attempt and the
#      cancelled-retry attempt each report this differently).
#   6. Otherwise, calls `gh run rerun <run-id>` (the *run* id, parsed
#      from `details_url` -- distinct from the job id used for the log
#      fetch above; the command itself returns no attempt identifier
#      on success) and polls the same run-API endpoint until
#      `run_attempt` equals *exactly* the pre-rerun value plus one --
#      not merely "greater than" -- so a different actor's own
#      concurrent rerun of the same run id is never misattributed as
#      this invocation's result. `status` is also required to be
#      `completed` -- checking it alone races a genuinely transient
#      window where GitHub still reports the *previous* attempt's
#      terminal `status`/`conclusion` for a few seconds after the rerun
#      call returns. `conclusion == cancelled` retries exactly once
#      more, same wait, but only if the live head *still* matches --
#      this repository has observed a rerun resolve to `cancelled`,
#      apparently deduplicated against a concurrently triggered sibling
#      rerun; a head change discovered at this point aborts the retry
#      and reports the first attempt's own `cancelled` conclusion
#      rather than silently treating an already-triggered-but-
#      unresolved rerun as a benign skip. A `success` conclusion is
#      re-verified against the live head one more time before being
#      reported: the poll above can itself run long enough for a push
#      to land after the exact-attempt match already resolved, and a
#      caller must not treat a success that covered a now-superseded
#      head as remediation for the *current* one -- this reports
#      `stale-success` instead. Anything else terminal, or the poll
#      bound being exhausted, counts as a failed remediation attempt. A
#      `gh run rerun` invocation that itself fails to even start never
#      counts as a triggered attempt or advances the poll.
#
#      **Known, accepted limitation**: the exact-attempt binding above
#      narrows but cannot fully close a genuinely concurrent second
#      actor rerunning the same run id between this invocation's
#      baseline read and its own `gh run rerun` call -- `gh`/the
#      Actions REST API expose no per-caller attempt identity to
#      disambiguate whose call produced a given attempt number. Closing
#      this fully would need external coordination (locking, serialized
#      rerun dispatch) this script deliberately does not implement,
#      matching its actual single-maintainer, low-concurrency operating
#      context. With the `run_attempt` lookup ordered *before* the live
#      head recheck (step 5 above), the `gh run rerun` call itself is
#      the only remaining network round-trip between the last check and
#      the mutation it guards -- an irreducible residual given the
#      Actions API offers no atomic "rerun only if head is still X"
#      primitive. Further narrowing is not possible without such a
#      primitive; this is the final position, not a step toward one.
#
# Output contract (stdout): one `OLD_SHA=<sha>` line per candidate
# whose reason string parsed successfully, one
# `SKIPPED=<job-id>:<reason>` (reasons include `invalid-run-id`,
# `superseded-attempt`, `wrong-workflow`, `log-fetch-failed`,
# `reason-not-matched`, `stale-head-mismatch`, `no-covering-review`,
# and `head-changed`) or `ACTED=<run-id>:<conclusion-or-
# timeout-or-rerun-failed-or-attempt-lookup-failed-or-stale-success>`
# line per candidate, and a final `RERUN_COUNT=<n>` line. Exits 0 when
# every candidate was a no-op or skip, or every attempted rerun
# resolved to `success` against the still-current head; exits 1 when
# any attempted rerun did not resolve that way (including a second
# `cancelled`, a `failure`, a `rerun-failed`, an
# `attempt-lookup-failed`, a `stale-success`, or a poll timeout).
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
# (https://…/actions/runs/<run-id>/job/<job-id>[...]), or prints
# nothing (empty) when the URL does not carry that exact shape.
# Distinct from the check-run's own `id` field (the *job* id), which is
# used separately for the per-attempt log fetch.
#
# Fails closed rather than falling through to the unmatched input: a
# check-run's `details_url` is set by whatever created it via the
# Checks API, reachable from a workflow run using `GITHUB_TOKEN` --
# including one triggered from a PR branch, and sharing this script's
# own `GITHUB_ACTIONS_APP_ID` pre-filter -- so it is attacker-
# influenced, not a trusted GitHub-internal value. A plain `sed`
# substitution with no match guarantee passes non-matching input
# straight through unchanged; a crafted `details_url` would then flow
# as `run_id` into `gh api "repos/{owner}/{repo}/actions/runs/${run_id}"`
# and `gh run rerun "$run_id"`, both of which accept either a bare id
# or a full run URL, so an unvalidated non-numeric value could redirect
# either call to an arbitrary run in an arbitrary repository under this
# invocation's own authenticated credentials. Validating the result
# against `^[0-9]+$` before ever returning it closes that off; callers
# must treat an empty result as an invalid candidate and skip it.
run_id_from_details_url() {
  local url="$1" run_id
  run_id=$(printf '%s' "$url" | sed -E 's#.*/actions/runs/([0-9]+)/job/[0-9]+.*#\1#')
  case "$run_id" in
    '' | *[!0-9]*) return 0 ;;
  esac
  printf '%s' "$run_id"
}

# select_latest_attempt_job_ids -- given every GitHub Actions-produced
# check-run record for the head commit (every conclusion -- `success`,
# `failure`, `cancelled`, `in_progress`, `timed_out`, etc. -- not just
# the failure/cancelled subset the caller treats as rerun candidates),
# prints a JSON object mapping each workflow *run* id (parsed via
# run_id_from_details_url) present among those records with a valid
# run id to the check-run `id` (job id) of whichever one of its own
# records is the most recent attempt. A record whose own details_url
# does not yield a valid run id is not represented in the output at
# all -- the caller's own invalid-run-id handling covers that case
# separately.
#
# Must be computed from every conclusion, not only failure/cancelled:
# if a run's true latest attempt already succeeded (or is still
# in-progress, or timed out) but an *older* attempt of the same run
# failed with the exact stale-review reason string, restricting this
# lookup to the failure/cancelled subset would filter the successful
# attempt out before grouping ever sees it -- crowning the older
# failure "latest" by default and authorizing a rerun of a run that, in
# reality, has already resolved (or is already in flight). The caller
# still applies the failure/cancelled eligibility test only to
# whichever record this function names as the winner for a run id.
#
# "Most recent" is decided by `completed_at`, falling back to
# `started_at` when null (a `cancelled` conclusion can leave
# `completed_at` unset on some GitHub API responses, and a still
# `in_progress`/`queued` record has neither), then by the check-run's
# own numeric `id` as a final deterministic tiebreaker -- job ids are
# assigned in strictly increasing order over time platform-wide, so
# this never leaves two same-run-id records genuinely tied. All three
# are combined into one lexicographically comparable string (ISO-8601
# timestamps already compare correctly as strings; the numeric id is
# zero-padded to a fixed width so it does too), so plain string
# comparison in jq is enough -- no need for a richer comparator.
#
# See the header comment for *why* only the latest attempt is ever
# treated as a rerun candidate for a given run id: `gh run rerun
# <run-id>` always operates on that run's current attempt, so an older
# attempt's log is never authoritative for deciding whether *this*
# invocation should trigger another rerun.
select_latest_attempt_job_ids() {
  local records="$1" count idx=0 winners='{}'
  count=$(printf '%s' "$records" | jq 'length')
  while [ "$idx" -lt "$count" ]; do
    local item job_id details_url run_id sort_key
    item=$(printf '%s' "$records" | jq -c ".[$idx]")
    job_id=$(printf '%s' "$item" | jq -r '.id')
    details_url=$(printf '%s' "$item" | jq -r '.details_url')
    run_id=$(run_id_from_details_url "$details_url")
    if [ -n "$run_id" ]; then
      sort_key=$(printf '%s' "$item" | jq -r \
        '(.completed_at // .started_at // "") + "|" + (.id | tostring | ("00000000000000000000" + .)[-20:])')
      winners=$(printf '%s' "$winners" | jq -c \
        --arg rid "$run_id" --arg key "$sort_key" --arg jobid "$job_id" \
        'if (.[$rid] == null) or ($key >= .[$rid].key) then . + {($rid): {key: $key, jobId: $jobid}} else . end')
    fi
    idx=$((idx + 1))
  done
  printf '%s' "$winners" | jq -c 'with_entries(.value |= .jobId)'
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
# `submitted_at`) copilot-pull-request-reviewer review for the given PR
# covers the given head sha. Accepts both the bare login and its
# `[bot]` suffix form. Uses the paginated REST reviews endpoint
# (`gh api ... --paginate`), not `gh pr view --json reviews`: the
# latter is `gh`'s own bounded reviews connection and can omit the
# actual latest review on a PR with more than one page of reviews,
# mirroring this repository's established latest-review lookup
# (docs/idd-advisory-wait-shell-fallback.md). Checking only the latest
# review -- not "any review whose commit matches" -- matters because
# the advisory-convergence gate itself only ever evaluates the latest
# review: with overlapping asynchronous review requests, an earlier
# review for the current head can complete before a later-submitted
# review for an older commit, and accepting the earlier one alone
# would authorize a rerun the gate will still fail immediately after.
has_covering_review() {
  local pr="$1" head_sha="$2" latest_json latest_sha
  latest_json=$(
    gh api "repos/{owner}/{repo}/pulls/${pr}/reviews" --paginate \
      --jq '.[] | select(.user.login == "copilot-pull-request-reviewer" or .user.login == "copilot-pull-request-reviewer[bot]") | {sa: .submitted_at, cid: .commit_id}' |
      jq -rs 'sort_by(.sa) | last // {}'
  )
  latest_sha=$(printf '%s' "$latest_json" | jq -r '.cid // empty')
  [ -n "$latest_sha" ] && [ "$latest_sha" = "$head_sha" ]
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
# ADVISORY_CONVERGENCE_WORKFLOW_PATH, its triggering `event` is
# `pull_request_target`, *and* it is actually associated with the given
# PR. `GITHUB_ACTIONS_APP_ID` alone is not sufficient producer-identity
# proof: every GitHub Actions-produced check run in the repository --
# including one from a workflow a PR branch itself adds (a fork PR, or
# any branch with workflow-file write access) -- shares that same app
# id. A branch could otherwise define its own job literally named
# `idd-advisory-convergence` that fails and prints the exact
# stale-rollup reason string naming the PR's current head, and app-id
# filtering alone would accept it as genuine. The workflow-path check
# alone is *also* not sufficient: this repository's own
# idd-advisory-convergence.yml registered `pull_request` alongside
# `pull_request_target` during a migration window that #501 closed (see that
# file's own header comment), and `pull_request` resolves the workflow
# *definition* from the PR branch itself, so a same-repository PR could
# edit that exact file to spoof a run at the same path. Only
# `pull_request_target` resolves the workflow from the base branch,
# immune to PR-branch tampering -- the same trust boundary this
# repository's own run-bound checks already rely on. Finally, the
# check-runs lookup this candidate came from is scoped only by commit
# SHA, and the same SHA can be associated with more than one open PR
# (a shared branch, or a rebase); without also verifying PR
# association, this could rerun a genuine `pull_request_target` run
# created for a *different* PR and report its result as remediation for
# this one. `pull_requests[].number` (see
# docs/customization.md's run-attribution guidance) proves that
# association -- GitHub never populates it for a fork-originated PR, so
# an empty array fails closed (skip) rather than being treated as an
# unverifiable pass. All conditions together are required before a
# candidate is accepted.
is_advisory_convergence_workflow_run() {
  local run_id="$1" pr="$2" run_json
  run_json=$(gh api "repos/{owner}/{repo}/actions/runs/${run_id}")
  [ "$(printf '%s' "$run_json" | jq -r '.path')" = "$ADVISORY_CONVERGENCE_WORKFLOW_PATH" ] &&
    [ "$(printf '%s' "$run_json" | jq -r '.event')" = 'pull_request_target' ] &&
    printf '%s' "$run_json" | jq -e --argjson pr "$pr" '[.pull_requests[]?.number] | index($pr) != null' >/dev/null
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
# `run_attempt` counter equals *exactly* prior_attempt + 1 (the precise
# attempt this invocation's own `gh run rerun` call created) *and*
# `status` is `completed`, then prints the resulting `conclusion`.
# `gh run rerun` itself returns no attempt identifier to bind to (it
# takes only a run id and prints nothing on success), so an
# `attempt > prior_attempt` comparison alone can misattribute a
# *different* actor's own concurrent rerun of the same run id: if
# another actor's rerun creates attempt N+1 between this invocation's
# baseline read and its own rerun call, that N+1 completing would
# satisfy a bare `>` check and be misreported as this call's result
# while the attempt this call actually triggered (N+2) is still
# pending or later fails. Exact equality narrows that window (this
# invocation's own rerun call has to land in the same instant as the
# other actor's for a false match) but does **not** eliminate it: if
# the interleaving above happens to produce exactly N+1 as *this*
# call's own attempt too (both actors racing the same baseline), the
# other actor's completed N+1 still satisfies this exact check.
# `gh`/the Actions REST API expose no per-caller attempt identity to
# close this the rest of the way; a full fix needs external
# coordination (locking, serialized rerun dispatch) this script
# deliberately does not implement -- see the header comment's
# documented scope. Checking
# `status` alone is not sufficient either way: for a few seconds after
# `gh run rerun` returns, GitHub can still report the *previous*
# attempt's terminal status/conclusion. Prints `timeout` if the poll
# bound is exhausted first, or if a poll iteration cannot resolve a
# valid `run_attempt` (a transient lookup failure never counts as
# reaching the new attempt).
wait_for_rerun_conclusion() {
  local run_id="$1" prior_attempt="$2" target_attempt polls=0 json status attempt conclusion
  target_attempt=$((prior_attempt + 1))
  while [ "$polls" -lt "$MAX_POLLS" ]; do
    json=$(gh api "repos/{owner}/{repo}/actions/runs/${run_id}" 2>/dev/null) || json=''
    if [ -n "$json" ]; then
      status=$(printf '%s' "$json" | jq -r '.status')
      attempt=$(printf '%s' "$json" | jq -r '.run_attempt // empty')
      conclusion=$(printf '%s' "$json" | jq -r '.conclusion')
      case "$attempt" in
        '' | *[!0-9]*) attempt='' ;;
      esac
      if [ -n "$attempt" ] && [ "$attempt" -eq "$target_attempt" ] && [ "$status" = 'completed' ]; then
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
#
# Within each attempt (the first, and the cancelled-retry), the
# `run_attempt` baseline lookup runs *before* the live-head recheck,
# not after: both are network round-trips a push can land during, so
# ordering the head check last leaves `gh run rerun` as the very next
# call with nothing else in between -- the tightest bound these two
# independent reads allow (see the header comment's "Known, accepted
# limitation" for why a `gh run rerun`-sized gap is still irreducible).
# The live-head recheck itself runs *inside* this function, immediately
# before **each** `gh run rerun` call (both the first attempt and the
# cancelled-retry attempt) -- not once in the caller before entering
# this function, since the first attempt's own poll (which can take
# `MAX_POLLS * POLL_INTERVAL` seconds) is a further window a push can
# land during before the retry's own mutation.
#
# A head change discovered **before any rerun has been triggered yet**
# (`attempts` still 0) is a true no-op: report `head-changed` and let
# the caller treat it as an ordinary skip, never a failure. A head
# change discovered **after the first attempt already ran** (the
# cancelled-retry recheck) is different -- a rerun genuinely happened
# and resolved `cancelled`, so this must not silently report a benign
# skip and leave the caller's exit status at 0: the retry is simply not
# attempted, and the first attempt's own `cancelled` conclusion falls
# through unchanged, so the caller's existing non-success handling
# (`ACTED=<run-id>:cancelled`, exit 1) reports the true outcome instead
# of inventing a separate token for this case. A `run_attempt` lookup
# failure on the retry path is reported as `attempt-lookup-failed`
# regardless of whether the head has also changed by that point -- the
# lookup is attempted unconditionally (mirroring the first attempt's
# own unconditional lookup), and a failed baseline read is a genuine
# fault this script cannot safely recover a conclusion from either
# way.
#
# A `success` conclusion is also re-verified against the live head
# before being reported: `wait_for_rerun_conclusion`'s own poll can run
# up to `MAX_POLLS * POLL_INTERVAL` seconds, during which a push can
# still land after the exact-attempt binding above already resolved.
# Reporting plain `success` here would let a caller treat the *current*
# PR as remediated even though the successful rerun only ever covered
# the now-superseded head; `stale-success` (attempts already correctly
# counted) tells the caller this candidate needs to be re-evaluated
# against the new head instead.
rerun_and_wait() {
  local pr="$1" head_sha="$2" run_id="$3" attempts=0 prior_attempt conclusion

  if ! prior_attempt=$(run_attempt "$run_id"); then
    printf '%s %s' "$attempts" 'attempt-lookup-failed'
    return 0
  fi
  if [ "$(current_head "$pr")" != "$head_sha" ]; then
    printf '%s %s' "$attempts" 'head-changed'
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
    if [ "$(current_head "$pr")" = "$head_sha" ]; then
      if ! gh run rerun "$run_id" >/dev/null; then
        printf '%s %s' "$attempts" 'rerun-failed'
        return 0
      fi
      attempts=$((attempts + 1))
      conclusion=$(wait_for_rerun_conclusion "$run_id" "$prior_attempt")
    fi
  fi

  if [ "$conclusion" = 'success' ] && [ "$(current_head "$pr")" != "$head_sha" ]; then
    conclusion='stale-success'
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

  local check_runs_json all_actions_records_json candidates_json candidate_count
  # `--paginate --slurp` follows every page (the endpoint's own
  # `filter` defaults to `latest`, and `per_page=100` alone only
  # bounds a single page -- either gap would silently omit a stale
  # instance sitting past the first page or outside the "latest"
  # rollup) and wraps each page's response object into a JSON array,
  # so every page's `check_runs` must be flattened with `.[].check_runs[]`
  # rather than the single-page `.check_runs[]`. The `app.id` filter
  # restricts records to check runs the GitHub Actions app itself
  # produced (see `GITHUB_ACTIONS_APP_ID` above) -- a same-named,
  # same-conclusion check run from a different integration must never
  # be treated as a genuine stale idd-advisory-convergence instance.
  #
  # `all_actions_records_json` deliberately keeps every conclusion
  # (`success`, `in_progress`, `timed_out`, etc.), not just
  # `failure`/`cancelled` -- select_latest_attempt_job_ids (below) must
  # decide which record is *actually* the latest attempt for a given
  # run id across its full history, not merely across its own
  # already-failed/cancelled records. Filtering to failure/cancelled
  # first would let an OLDER failed attempt be crowned "latest" purely
  # because a run's true latest attempt (a `success`, say) had already
  # been filtered out before grouping -- authorizing a rerun of a run
  # that has, in reality, already resolved successfully.
  # `candidates_json` narrows to the failure/cancelled subset only for
  # the loop's own per-record eligibility checks below; the winner
  # lookup (`latest_job_ids_json`) is always computed from the
  # unfiltered set.
  check_runs_json=$(gh api --paginate --slurp "repos/{owner}/{repo}/commits/${head_sha}/check-runs?check_name=${CHECK_NAME}&filter=all&per_page=100")
  all_actions_records_json=$(printf '%s' "$check_runs_json" | jq -c --argjson app_id "$GITHUB_ACTIONS_APP_ID" \
    '[.[].check_runs[] | select(.app.id == $app_id)]')
  candidates_json=$(printf '%s' "$all_actions_records_json" | jq -c \
    '[.[] | select(.conclusion == "failure" or .conclusion == "cancelled")]')
  candidate_count=$(printf '%s' "$candidates_json" | jq 'length')

  if [ "$candidate_count" -eq 0 ]; then
    echo "nothing to do: no stale ${CHECK_NAME} instance found for PR #${pr} (head ${head_sha})"
    echo 'RERUN_COUNT=0'
    exit 0
  fi

  # Resolves, once, which record is the latest attempt for each
  # distinct workflow run id, across *every* conclusion this run id
  # has ever produced (not just the failure/cancelled candidates) --
  # see select_latest_attempt_job_ids's own comment for why only that
  # one record per run id is ever eligible to trigger a rerun, and why
  # it must be computed from the unfiltered record set.
  local latest_job_ids_json
  latest_job_ids_json=$(select_latest_attempt_job_ids "$all_actions_records_json")

  local rerun_count=0 overall_exit=0 idx=0
  while [ "$idx" -lt "$candidate_count" ]; do
    local item job_id details_url run_id log
    item=$(printf '%s' "$candidates_json" | jq -c ".[$idx]")
    job_id=$(printf '%s' "$item" | jq -r '.id')
    details_url=$(printf '%s' "$item" | jq -r '.details_url')
    run_id=$(run_id_from_details_url "$details_url")

    if [ -z "$run_id" ]; then
      echo "SKIPPED=${job_id}:invalid-run-id"
      idx=$((idx + 1))
      continue
    fi

    local latest_job_id
    latest_job_id=$(printf '%s' "$latest_job_ids_json" | jq -r --arg rid "$run_id" '.[$rid] // empty')
    if [ "$latest_job_id" != "$job_id" ]; then
      echo "SKIPPED=${job_id}:superseded-attempt"
      idx=$((idx + 1))
      continue
    fi

    if ! is_advisory_convergence_workflow_run "$run_id" "$pr"; then
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

    # No further per-run-id dedup gate is needed here: the
    # latest_job_ids_json lookup above already guarantees at most one
    # candidate per workflow run id ever reaches this point in a single
    # invocation.
    #
    # The live-head recheck immediately before authorizing a rerun now
    # runs *inside* rerun_and_wait, immediately before each `gh run
    # rerun` call it makes (not once here) -- see that function's own
    # comment for why a single check at this point is not enough.
    local result attempts conclusion
    result=$(rerun_and_wait "$pr" "$head_sha" "$run_id")
    attempts=$(printf '%s' "$result" | cut -d' ' -f1)
    conclusion=$(printf '%s' "$result" | cut -d' ' -f2)
    rerun_count=$((rerun_count + attempts))

    if [ "$conclusion" = 'success' ]; then
      echo "ACTED=${run_id}:success"
    elif [ "$conclusion" = 'head-changed' ]; then
      echo "SKIPPED=${job_id}:head-changed"
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
