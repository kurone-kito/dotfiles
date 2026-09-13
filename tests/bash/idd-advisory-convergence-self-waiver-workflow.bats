#!/usr/bin/env bats
# Structural assertions against
# .github/workflows/idd-advisory-convergence.yml's
# idd-advisory-convergence-self-waiver job and its trust-boundary wiring
# with the idd-advisory-convergence verdict job (#424,
# kurone-kito/idd-skill#2657). Both jobs are pull-request-family
# triggered, so PR CI does exercise them, but a same-repository PR could
# still silently weaken the trust boundary itself (drop the
# pull_request_target-only gate, downgrade the pinned-SHA checkout back
# to a floating tag, or de-sequence the verdict job from the self-waiver
# job) without any test noticing until a live spoofing attempt succeeds
# or the bootstrap path silently races. These checks are the only
# automated coverage of that wiring, mirroring
# tests/bash/ruleset-drift-guard-workflow.bats's approach for a
# different workflow's step-level wiring.
#
# Uses `yq` (mikefarah/yq) to query the YAML structurally instead of
# grepping the raw text, so these assertions survive reformatting. `yq`
# ships preinstalled on the `ubuntu-latest` GitHub-hosted runner image
# this suite's own CI job runs on (.github/workflows/test.yml's Bash
# tests (bats) job) -- note this is the TEST job's own runner, distinct
# from the `ubuntu-slim` default the workflow under test resolves for
# its own `runs-on:` (Copilot review, PR #429); skip locally if yq is
# unavailable.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  command -v yq > /dev/null 2>&1 || skip "yq not available"

  WORKFLOW="$BATS_TEST_DIRNAME/../../.github/workflows/idd-advisory-convergence.yml"
}

checkout_step() {
  local job="$1" field="$2"
  yq "(.jobs[\"${job}\"].steps[] | select(.uses != null and (.uses | test(\"checkout\")))) as \$s | \$s.${field}" "$WORKFLOW"
}

@test "the self-waiver job only ever runs for pull_request_target, never pull_request" {
  run yq '.jobs["idd-advisory-convergence-self-waiver"].if' "$WORKFLOW"
  assert_success
  assert_output "github.event_name == 'pull_request_target'"
}

@test "the self-waiver job carries issues: write, not a broader permission set" {
  # Assert the complete permission map, not just one key -- checking
  # `.permissions.issues` alone would still pass if a future edit added
  # e.g. `actions: write` or `contents: write` alongside it, silently
  # widening this job's already-elevated trust boundary (Copilot
  # review, PR #429).
  run yq -o=json -I=0 '.jobs["idd-advisory-convergence-self-waiver"].permissions' "$WORKFLOW"
  assert_success
  assert_output '{"contents":"read","pull-requests":"read","issues":"write"}'
}

@test "the self-waiver job checks out master, not the PR head" {
  run checkout_step "idd-advisory-convergence-self-waiver" "with.ref"
  assert_success
  assert_output 'master'
}

@test "the self-waiver job pins its checkout action to a commit SHA, not a floating tag" {
  run checkout_step "idd-advisory-convergence-self-waiver" "uses"
  assert_success
  assert_output --regexp '^actions/checkout@[0-9a-f]{40}$'
}

@test "the verdict job also pins its checkout action to a commit SHA (#424)" {
  # The verdict job's output IS the required check -- a compromised
  # floating tag here would undermine every trigger-level spoofing
  # closure above it, so the read-only-permissions exemption
  # (docs/idd-policy.md "Post-Merge Cleanup Automation") does not cover
  # it even though this job itself stays read-only.
  run checkout_step "idd-advisory-convergence" "uses"
  assert_success
  assert_output --regexp '^actions/checkout@[0-9a-f]{40}$'
}

@test "the verdict job pins its setup-node action to a commit SHA (#424)" {
  run yq '(.jobs["idd-advisory-convergence"].steps[] | select(.uses != null and (.uses | test("setup-node")))) as $s | $s.uses' "$WORKFLOW"
  assert_success
  assert_output --regexp '^actions/setup-node@[0-9a-f]{40}$'
}

@test "the self-waiver job pins its upload-artifact step to a commit SHA" {
  # This job carries issues: write; a future floating or retargeted
  # upload-artifact reference could execute third-party code under that
  # write token while the checkout/setup-node pin tests above still pass
  # (Copilot review, PR #429).
  run yq '(.jobs["idd-advisory-convergence-self-waiver"].steps[] | select(.uses != null and (.uses | test("upload-artifact")))) as $s | $s.uses' "$WORKFLOW"
  assert_success
  assert_output --regexp '^actions/upload-artifact@[0-9a-f]{40}$'
}

@test "the self-referential trigger-file allowlist covers exactly the three self-referential files" {
  # A future edit that silently added a fourth path (broadening which
  # PRs can auto-post a live waiver) or removed one of these three
  # (narrowing the bootstrap escape hatch below correctness) would still
  # pass every other test in this file (Copilot review, PR #429).
  run yq '.jobs["idd-advisory-convergence-self-waiver"].steps[] | select(.name == "Detect self-referential trigger-file allowlist touch") | .run' "$WORKFLOW"
  assert_success
  assert_output --partial '".github/idd/config.json"'
  assert_output --partial '".github/workflows/idd-advisory-convergence.yml"'
  assert_output --partial '".github/workflows/idd-advisory-convergence-comment.yml"'
  # POSIX [[:space:]], not GNU grep's `\s` extension: this suite is
  # documented to run on macOS too, where BSD grep does not interpret
  # `\s` as whitespace and would silently count zero matches instead of
  # failing loudly (Copilot review, PR #429).
  local count
  count=$(grep -c '^[[:space:]]*"\.[^"]*"[[:space:]]*$' <<< "$output")
  [ "$count" -eq 3 ]
}

@test "the waiver post step binds --check, --reason, and --run-id, and requires --auto-bootstrap" {
  # This job's whole trust model rests on the consumer verifying these
  # exact flags against the run's own provenance -- a future edit that
  # silently dropped --run-id or --auto-bootstrap would still pass every
  # structural test above (job gate, permissions, action pins) while
  # posting a waiver the consumer can no longer bind to this run, or one
  # that is honored without ever having been bootstrap-justified
  # (Copilot review, PR #429).
  run yq '.jobs["idd-advisory-convergence-self-waiver"].steps[] | select(.name == "Post the self-referential-bootstrap-auto waiver") | .run' "$WORKFLOW"
  assert_success
  assert_output --partial 'idd-external-check-waiver'
  assert_output --partial '--check idd-advisory-convergence'
  assert_output --partial '--reason self-referential-bootstrap-auto'
  assert_output --partial '--run-id "$GITHUB_RUN_ID"'
  assert_output --partial '--auto-bootstrap'
}

@test "the verdict job depends on the self-waiver job and still runs when it is skipped or cancelled" {
  run yq '.jobs["idd-advisory-convergence"].needs' "$WORKFLOW"
  assert_success
  assert_output 'idd-advisory-convergence-self-waiver'

  run yq '.jobs["idd-advisory-convergence"].if' "$WORKFLOW"
  assert_success
  assert_output --partial '!cancelled()'
}

@test "the required triggers are exactly pull_request, pull_request_target, workflow_dispatch, and workflow_call" {
  # Exact-match, not --partial: a future silent drop of pull_request (or
  # pull_request_target) -- the whole point of the transitional
  # trust-boundary tradeoff this workflow's header documents -- must be
  # a deliberate edit to this test, not an unnoticed side effect of an
  # unrelated change.
  #
  # Repeatedly flagged in automated review as "yq sorts keys
  # alphabetically" (PR #429) -- false for mikefarah/yq (this repo's
  # `yq`), verified multiple ways: (1) this exact assertion passes both
  # locally and on the actual GitHub-hosted `ubuntu-latest` runner (see
  # this PR's own "Bash tests (bats)" CI run); (2) `keys_unsorted` --
  # cited as yq's order-preserving counterpart to a sorting `keys` --
  # is not even a valid operator in the installed yq (v4.53.6): it
  # errors as unrecognized syntax, not merely "sorts differently". The
  # sort/keys_unsorted split being cited is real, but it describes
  # POSIX `jq` operating on JSON (where object key order is not part of
  # the data model), not `yq` operating on YAML (where yq's internal
  # node tree preserves the mapping's own declared order and `keys`
  # just walks it) -- an understandable conflation given yq deliberately
  # mirrors jq's query syntax, but not the same tool or behavior. Do not
  # "fix" this by resorting the expected array without re-running both
  # checks above first.
  run yq -o=json -I=0 '.on | keys' "$WORKFLOW"
  assert_success
  assert_output '["pull_request","pull_request_target","workflow_dispatch","workflow_call"]'
}

@test "pull_request and pull_request_target both trigger on opened, reopened, and synchronize only" {
  run yq -o=json -I=0 '.on.pull_request.types' "$WORKFLOW"
  assert_success
  assert_output '["opened","reopened","synchronize"]'

  run yq -o=json -I=0 '.on.pull_request_target.types' "$WORKFLOW"
  assert_success
  assert_output '["opened","reopened","synchronize"]'
}
