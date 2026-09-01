#!/usr/bin/env bats
# Tests for scripts/escalate-ruleset-drift.sh, the tracking-issue
# find/escalate/recover logic extracted from
# .github/workflows/ruleset-required-checks-guard.yml. Runs entirely
# against a stubbed `gh` binary (tests/bash/fixtures/ruleset-drift-
# escalation-gh-stub.sh) prepended onto PATH, so no test here ever
# creates, comments on, or closes an issue in the live repository.
# Exercises the de-duplication behavior directly: escalating while a
# tracking issue is already open must comment, never create a second
# issue.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/escalate-ruleset-drift.sh"
  GH_STUB="$BATS_TEST_DIRNAME/fixtures/ruleset-drift-escalation-gh-stub.sh"

  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  cp "$GH_STUB" "$STUB_BIN/gh"
  chmod +x "$STUB_BIN/gh"
  PATH="$STUB_BIN:$PATH"

  export GH_CALL_LOG="$BATS_TEST_TMPDIR/gh-calls.log"
  : > "$GH_CALL_LOG"

  export GH_BODY_LOG="$BATS_TEST_TMPDIR/gh-body.log"

  TRACKING_TITLE='ci: master ruleset required_status_checks drift detected'
}

@test "find-tracking-issue returns the number of an exact title match from this workflow's own author" {
  export GH_STUB_ISSUE_LIST_JSON='[{"number":42,"title":"ci: master ruleset required_status_checks drift detected","author":{"login":"github-actions[bot]"}}]'
  run bash "$SCRIPT" find-tracking-issue --title "$TRACKING_TITLE"
  assert_success
  assert_output '42'
}

@test "find-tracking-issue ignores a title that only contains the search phrase" {
  export GH_STUB_ISSUE_LIST_JSON='[{"number":7,"title":"unrelated: mentions ci: master ruleset required_status_checks drift detected in passing","author":{"login":"github-actions[bot]"}}]'
  run bash "$SCRIPT" find-tracking-issue --title "$TRACKING_TITLE"
  assert_success
  assert_output ''
}

@test "find-tracking-issue ignores an exact-title match opened by someone other than this workflow" {
  # The tracking-issue title is public and fixed, so anyone could open
  # an unrelated issue with that exact title. Without this author check
  # the workflow would adopt a stranger's issue as its own tracker --
  # closing it as "recovered" on the next passing run, or commenting on
  # it as if it were the real drift record.
  export GH_STUB_ISSUE_LIST_JSON='[{"number":99,"title":"ci: master ruleset required_status_checks drift detected","author":{"login":"some-random-user"}}]'
  run bash "$SCRIPT" find-tracking-issue --title "$TRACKING_TITLE"
  assert_success
  assert_output ''
}

@test "find-tracking-issue returns nothing when no open issue matches" {
  export GH_STUB_ISSUE_LIST_JSON='[]'
  run bash "$SCRIPT" find-tracking-issue --title "$TRACKING_TITLE"
  assert_success
  assert_output ''
}

@test "escalate creates a tracking issue with the bug label when none is open" {
  export GH_STUB_EXISTING_LABELS='enhancement'
  run bash "$SCRIPT" escalate --title "$TRACKING_TITLE" --issue "" \
    --missing "lint" --extra "" --run-url "https://example.test/run/1"
  assert_success

  run cat "$GH_CALL_LOG"
  assert_output --partial 'CALL: api repos/{owner}/{repo}/labels/bug'
  assert_output --partial 'CALL: label create bug'
  assert_output --partial "CALL: issue create --title $TRACKING_TITLE --label bug --body-file -"
  refute_output --partial 'CALL: issue comment'

  # Assert on the actual piped body content, not just the gh argv above --
  # a regression that silently dropped the missing/extra contexts or the
  # run URL from build_drift_body would still pass an argv-only check.
  run cat "$GH_BODY_LOG"
  assert_output --partial 'Missing context(s): lint'
  assert_output --partial 'https://example.test/run/1'
  refute_output --partial 'Unexpected extra context(s)'
}

@test "escalate fails instead of misreading a non-404 label lookup failure as absent" {
  # A rate limit, permission error, or transient network failure must
  # not be treated the same as "label genuinely absent" -- that
  # misclassification would attempt `label create` on a label that may
  # still exist, fail there instead, and silently lose the escalation
  # for a real drift under set -e.
  export GH_STUB_LABEL_LOOKUP_ERROR='gh: API rate limit exceeded (HTTP 403)'
  run bash "$SCRIPT" escalate --title "$TRACKING_TITLE" --issue "" \
    --missing "lint" --extra "" --run-url "https://example.test/run/1"
  assert_failure
  assert_output --partial 'not a 404'
  assert_output --partial 'API rate limit exceeded'

  run cat "$GH_CALL_LOG"
  refute_output --partial 'CALL: label create'
  refute_output --partial 'CALL: issue create'
}

@test "escalate does not create the bug label when it already exists" {
  export GH_STUB_EXISTING_LABELS='bug enhancement'
  run bash "$SCRIPT" escalate --title "$TRACKING_TITLE" --issue "" \
    --missing "lint" --extra "" --run-url "https://example.test/run/1"
  assert_success

  run cat "$GH_CALL_LOG"
  assert_output --partial 'CALL: api repos/{owner}/{repo}/labels/bug'
  refute_output --partial 'CALL: label create'
  assert_output --partial 'CALL: issue create'
}

@test "escalate comments on an already-open tracking issue instead of creating a duplicate" {
  run bash "$SCRIPT" escalate --title "$TRACKING_TITLE" --issue "42" \
    --missing "" --extra "totally-unexpected-check" --run-url "https://example.test/run/2"
  assert_success

  run cat "$GH_CALL_LOG"
  assert_output --partial 'CALL: issue comment 42 --body-file -'
  refute_output --partial 'CALL: issue create'
  refute_output --partial 'CALL: label'

  # Same body-content check as the create path above, using the extra-
  # context field this time so both fields get covered across the suite.
  run cat "$GH_BODY_LOG"
  assert_output --partial 'Unexpected extra context(s): totally-unexpected-check'
  assert_output --partial 'https://example.test/run/2'
  refute_output --partial 'Missing context(s)'
}

@test "escalate reports an infrastructure-failure reason instead of a drift diff when --reason is given" {
  # #317: a failure in the caller's own ruleset-fetch or tracking-issue-
  # lookup step must be escalated too, distinguishably from a genuine
  # required_status_checks drift finding -- not silently skipped, and
  # not misreported as an empty drift diff.
  run bash "$SCRIPT" escalate --title "$TRACKING_TITLE" --issue "" \
    --missing "" --extra "" --reason "Fetch ruleset rules step failed" \
    --run-url "https://example.test/run/4"
  assert_success

  run cat "$GH_BODY_LOG"
  assert_output --partial 'infrastructure error: Fetch ruleset rules step failed'
  assert_output --partial 'https://example.test/run/4'
  refute_output --partial 'has drifted from the expected context set'
  refute_output --partial 'Missing context(s)'
  refute_output --partial 'Unexpected extra context(s)'
}

@test "escalate reports both the infra reason and a real drift diff when both occur in the same run" {
  # PR #338 review (CodeRabbit): a prior wording ("...not a
  # required_status_checks drift finding") was factually wrong in this
  # exact combined case -- Check drift can find a real drift in the
  # same run where Find open tracking issue also fails, so the body
  # must never claim no drift was found while still listing one.
  run bash "$SCRIPT" escalate --title "$TRACKING_TITLE" --issue "" \
    --missing "lint" --extra "" \
    --reason "Find open tracking issue step failed" \
    --run-url "https://example.test/run/6"
  assert_success

  run cat "$GH_BODY_LOG"
  assert_output --partial 'infrastructure error: Find open tracking issue step failed'
  assert_output --partial 'Missing context(s): lint'
  refute_output --partial 'not a required_status_checks drift finding'
}

@test "escalate keeps the drift wording and appends missing/extra lines when --reason is empty" {
  # Omitting --reason (the default) must render byte-identical to the
  # pre-#317 drift-only body -- existing callers/behavior are
  # unaffected by the new optional flag.
  run bash "$SCRIPT" escalate --title "$TRACKING_TITLE" --issue "" \
    --missing "lint" --extra "" --run-url "https://example.test/run/5"
  assert_success

  run cat "$GH_BODY_LOG"
  assert_output --partial 'has drifted from the expected context set'
  assert_output --partial 'Missing context(s): lint'
  refute_output --partial 'infrastructure error'
}

@test "recover closes the tracking issue with an explanatory comment" {
  run bash "$SCRIPT" recover --issue 42 --run-url "https://example.test/run/3"
  assert_success

  run cat "$GH_CALL_LOG"
  assert_output --partial 'CALL: issue close 42 --comment'
  assert_output --partial 'matches the expected context set again'
  assert_output --partial 'https://example.test/run/3'
}

@test "escalate fails fast when --run-url is missing" {
  run bash "$SCRIPT" escalate --title "$TRACKING_TITLE" --issue "42" --missing "lint" --extra ""
  assert_failure
  assert_output --partial 'missing required --run-url'
}
