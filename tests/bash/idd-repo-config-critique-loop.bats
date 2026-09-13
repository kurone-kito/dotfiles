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

@test ".github/idd/config.json declares the v0.11.0 iddVersion and its adopted schema keys" {
  assert_file_exists "$CONFIG_PATH"

  python3 -c "
import json
import sys
with open(sys.argv[1], encoding='utf-8') as f:
    config = json.load(f)

assert config.get('iddVersion') == '0.11.0', config.get('iddVersion')

telemetry_hook = config.get('critiqueLoop', {}).get('telemetryHook')
assert telemetry_hook is not None, 'critiqueLoop.telemetryHook is missing'
assert telemetry_hook.get('command') == 'idd-critique-telemetry', telemetry_hook

assert config.get('worktreeGuard', {}).get('refuseBaseBranchCommits') is True, \
    config.get('worktreeGuard')

assert config.get('issueAuthoring', {}).get('journalIssue') == 'kurone-kito/dotfiles#380', \
    config.get('issueAuthoring')

assert config.get('labels', {}).get('untrustedLabelerLogins') == ['coderabbitai[bot]'], \
    config.get('labels')

assert config.get('upstreamEscalation', {}).get('enabled') is True, \
    config.get('upstreamEscalation')
" "$CONFIG_PATH"
}
