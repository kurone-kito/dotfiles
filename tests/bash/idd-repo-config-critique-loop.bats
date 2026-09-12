#!/usr/bin/env bats
#
# Regression test for .github/idd/config.json's repository-local
# critiqueLoop.delegate key (issue #407): schema/idd-doctor validation
# alone would still pass if a future re-import removed this key again
# -- the exact regression this test guards against -- since the key is
# optional at the schema level. Requested by a Copilot review on PR
# #408.
#
# Also covers the sibling critiqueLoop.telemetryHook key (issue #389),
# added for the same reason: it too is schema-optional, so only an
# explicit assertion like this one catches a future re-import silently
# dropping it again.

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

@test ".github/idd/config.json declares the repository-local critiqueLoop.telemetryHook" {
  assert_file_exists "$CONFIG_PATH"

  python3 -c "
import json
import sys
with open(sys.argv[1], encoding='utf-8') as f:
    config = json.load(f)
hook = config.get('critiqueLoop', {}).get('telemetryHook')
assert hook is not None, 'critiqueLoop.telemetryHook is missing from .github/idd/config.json'
assert hook.get('command') == 'idd-critique-telemetry', hook
" "$CONFIG_PATH"
}
