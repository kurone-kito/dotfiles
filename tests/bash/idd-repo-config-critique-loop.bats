#!/usr/bin/env bats
#
# Regression test for .github/idd/config.json's optional-but-adopted
# policy keys: schema/idd-doctor validation alone would still pass if a
# future re-import silently removed or altered one of these -- the
# exact regression this file guards against -- since every key here is
# optional at the schema level.
#
# - critiqueLoop.delegate (issue #407): requested by a Copilot review
#   on PR #408.
# - iddVersion, critiqueLoop.telemetryHook, worktreeGuard's
#   refuseBaseBranchCommits, issueAuthoring.journalIssue,
#   labels.untrustedLabelerLogins, and upstreamEscalation.enabled
#   (issue #420, roadmap #419 Track A): requested by a Copilot review
#   on PR #427.
# - iddVersion 0.12.0 plus helperRuntime.packageSpec, with
#   critiqueLoop.deferAfterRounds still absent (issue #447, roadmap
#   #446 Track A): the same lockstep pin, updated when Track A bumped
#   the config. The issue's Candidate files named only config.json and
#   docs/idd-policy.md; this test is the required companion so the
#   version bump cannot land while still asserting 0.11.0.
# - iddVersion 0.12.2 plus helperRuntime.packageSpec,
#   critiqueLoop.deferAfterRounds == 5, and the adopted advisoryWait
#   (convergenceScope/convergenceDeadline/secondaryQuietWindow),
#   discover.selectionDesync, and forcedHandoff (mode/authorityPolicy)
#   values (issue #470): the 2026-09-22 hearing's (roadmap #469)
#   config update. Same lockstep-companion rationale as the 0.12.0 row
#   above.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  CONFIG_PATH="$BATS_TEST_DIRNAME/../../.github/idd/config.json"
}

@test ".github/idd/config.json declares the repository-local critiqueLoop.delegate" {
  assert_file_exists "$CONFIG_PATH"

  python3 -c "
import json
import sys
with open(sys.argv[1], encoding='utf-8') as f:
    config = json.load(f)
delegate = config.get('critiqueLoop', {}).get('delegate')
assert delegate is not None, 'critiqueLoop.delegate is missing from .github/idd/config.json'
assert delegate.get('command') == 'coderabbit-critique', delegate
assert delegate.get('mode') == 'combined', delegate
" "$CONFIG_PATH"
}

@test ".github/idd/config.json declares the v0.12.2 iddVersion and its adopted schema keys" {
  assert_file_exists "$CONFIG_PATH"

  python3 -c "
import json
import sys
with open(sys.argv[1], encoding='utf-8') as f:
    config = json.load(f)

assert config.get('iddVersion') == '0.12.2', config.get('iddVersion')

package_spec = config.get('helperRuntime', {}).get('packageSpec')
assert package_spec == (
    'https://codeload.github.com/kurone-kito/idd-skill/tar.gz/'
    'c11c3642319b3283293e4e681861bf7899c32ed3'
), package_spec

assert config.get('critiqueLoop', {}).get('deferAfterRounds') == 5, \
    config.get('critiqueLoop')

telemetry_hook = config.get('critiqueLoop', {}).get('telemetryHook')
assert telemetry_hook is not None, 'critiqueLoop.telemetryHook is missing'
assert telemetry_hook.get('command') == 'idd-critique-telemetry', telemetry_hook

worktree_guard = config.get('worktreeGuard', {})
# refuseBaseBranchCommits is inert unless worktreeGuard.enabled is also
# true -- the guard's runtime gates all enforcement on that flag first
# (Copilot review, PR #427) -- so assert both, not refuseBaseBranchCommits
# alone, or a future re-import could silently drop 'enabled' unnoticed.
assert worktree_guard.get('enabled') is True, worktree_guard
assert worktree_guard.get('refuseBaseBranchCommits') is True, worktree_guard

assert config.get('issueAuthoring', {}).get('journalIssue') == 'kurone-kito/dotfiles#380', \
    config.get('issueAuthoring')

assert config.get('labels', {}).get('untrustedLabelerLogins') == ['coderabbitai[bot]'], \
    config.get('labels')

assert config.get('upstreamEscalation', {}).get('enabled') is True, \
    config.get('upstreamEscalation')

advisory_wait = config.get('advisoryWait', {})
assert advisory_wait.get('convergenceScope') == 'idd-claimed', advisory_wait
assert advisory_wait.get('convergenceDeadline') == 'PT9H', advisory_wait
assert advisory_wait.get('secondaryQuietWindow') == 'PT1H', advisory_wait
assert advisory_wait.get('secondaryBotLogin') == 'coderabbitai[bot]', advisory_wait

assert config.get('discover', {}).get('selectionDesync') == 'session-offset', \
    config.get('discover')

forced_handoff = config.get('forcedHandoff', {})
assert forced_handoff.get('mode') == 'human-gated', forced_handoff
assert forced_handoff.get('authorityPolicy') == 'owners-and-maintainers-only', \
    forced_handoff

# The three ciGate defaults the hearing made explicit: each equals its
# own schema default, so omitting them would still pass schema/idd-doctor
# validation -- a future re-import could silently drop them back to
# implicit without this assertion catching it (Copilot review, PR #478).
ci_gate = config.get('ciGate', {})
waivable = ci_gate.get('externalChecks', {}).get('waivable', [])
assert len(waivable) == 1 and waivable[0].get('matchMode') == 'exact', waivable

external_check_waivers = ci_gate.get('externalCheckWaivers', {})
assert external_check_waivers.get('authorityPolicy') == 'owners-and-maintainers-only', \
    external_check_waivers
assert external_check_waivers.get('maxValidity') == 'PT24H', external_check_waivers
" "$CONFIG_PATH"
}
