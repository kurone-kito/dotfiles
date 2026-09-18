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

@test ".github/idd/config.json declares the v0.12.0 iddVersion and its adopted schema keys" {
  assert_file_exists "$CONFIG_PATH"

  python3 -c "
import json
import sys
with open(sys.argv[1], encoding='utf-8') as f:
    config = json.load(f)

assert config.get('iddVersion') == '0.12.0', config.get('iddVersion')

package_spec = config.get('helperRuntime', {}).get('packageSpec')
assert package_spec == (
    'https://codeload.github.com/kurone-kito/idd-skill/tar.gz/'
    '11105d705820e50be0a14fcc174587abbaf62b30'
), package_spec

assert 'deferAfterRounds' not in config.get('critiqueLoop', {}), \
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
" "$CONFIG_PATH"
}
