#!/usr/bin/env bats
#
# Regression for the shared-host process-cleanup prompt contract in
# docs/idd-workflow.md (issue #580). This file checks the documented
# prompt contract, not runtime process cleanup. Assertions read only
# that document, and only the two sites marked
# dotfiles-divergence: subagent-process-cleanup.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  WORKFLOW_DOC="$BATS_TEST_DIRNAME/../../docs/idd-workflow.md"
}

@test "idd-workflow.md has two shared-host cleanup prompt sites" {
  assert_file_exists "$WORKFLOW_DOC"

  python3 -c "
import sys

marker = '<!-- dotfiles-divergence: subagent-process-cleanup -->'
text = open(sys.argv[1], encoding='utf-8').read()
count = text.count(marker)
assert count == 2, 'expected exactly two marked cleanup sites, found %d' % count
" "$WORKFLOW_DOC"
}

@test "critique brief records a PID or process group and keeps gpgconf as the exception" {
  python3 -c "
import re
import sys

marker = '<!-- dotfiles-divergence: subagent-process-cleanup -->'
text = open(sys.argv[1], encoding='utf-8').read()
starts = [i for i in range(len(text)) if text.startswith(marker, i)]
assert len(starts) == 2, len(starts)
site = text[starts[0] + len(marker):].split('\n\n', 1)[0]

assert re.search(
    r'end(?:s|ed|ing)?\b.{0,220}\brecord(?:ed|ing)?\b.{0,60}\b(?:launch|start)',
    site,
    re.I | re.S,
), 'critique site does not end a process with an identity recorded at launch'
assert re.search(r'\bonly\b.{0,40}\bPID\b.{0,40}process group', site, re.I), (
    'critique site does not limit ending to a recorded PID or process group'
)
assert re.search(r'\b(never|not)\b', site, re.I), 'critique site does not forbid unsafe selection'
low = site.lower()
assert 'name' in low, 'critique site does not cover selection by name'
assert 'working directory' in low, 'critique site does not cover selection by working directory'
assert re.search(r'command-line|command line', low), 'critique site does not cover selection by command line'
assert 'pgrep -P' in site, 'critique site does not constrain pgrep -P'
assert re.search(r'recorded PID', site), 'critique site does not limit pgrep -P to a recorded PID'
assert 'gpgconf' in low and 'gpg-agent' in low, 'critique site drops the gpgconf exception'
assert re.search(r'exception', site, re.I), 'critique site does not mark gpgconf as an exception'
" "$WORKFLOW_DOC"
}

@test "Claude recipe records identities before waiting and leaves unrecorded processes running" {
  python3 -c "
import re
import sys

marker = '<!-- dotfiles-divergence: subagent-process-cleanup -->'
text = open(sys.argv[1], encoding='utf-8').read()
starts = [i for i in range(len(text)) if text.startswith(marker, i)]
assert len(starts) == 2, len(starts)
site = text[starts[1] + len(marker):].split('\n\n', 1)[0]
low = site.lower()

record_at = low.find('record')
wait_at = low.find('wait')
assert record_at != -1 and wait_at != -1 and record_at < wait_at, (
    'Claude site does not record an identity before waiting'
)
assert re.search(r'\bPID\b', site), 'Claude site does not name a PID'
assert re.search(r'process group', site, re.I), 'Claude site does not name a process group'
assert re.search(r'\b(never|not)\b', low), 'Claude site does not forbid unsafe discovery'
assert 'working directory' in low, 'Claude site does not cover discovery by working directory'
assert re.search(r'process name|\bname\b', low), 'Claude site does not cover discovery by name'
assert re.search(r'command-line|command line', low), 'Claude site does not cover discovery by command line'
assert 'pgrep -P' in site, 'Claude site does not constrain pgrep -P'
assert re.search(r'recorded PID', site), 'Claude site does not limit pgrep -P to a recorded PID'
assert re.search(r'(?:no|without(?:\s+an?)?|un)\s*recorded', low), (
    'Claude site does not cover a missing recorded identity'
)
assert re.search(r'(leave|leaves|left|stays).{0,80}running', low), (
    'Claude site does not leave an unrecorded process running'
)
assert 'residual' in low, 'Claude site does not report residual risk'
assert 'gpgconf' not in low, 'Claude site must not require the gpgconf exception'
" "$WORKFLOW_DOC"
}
