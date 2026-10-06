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
    r'end(?:s|ed|ing)?.{0,180}only.{0,40}PID.{0,40}process group.{0,40}record(?:ed|ing)?.{0,40}(?:launch|start)',
    site,
    re.I | re.S,
), 'critique site does not end a process using only a PID or process group recorded at launch'
assert re.search(
    r'(?:never|do not|must not|does not).{0,80}(?:'
    r'name.{0,80}working directory.{0,80}command-?line|'
    r'working directory.{0,80}name.{0,80}command-?line)',
    site,
    re.I | re.S,
), 'critique site does not forbid selection by name, working directory, and command line together'
assert re.search(r'pgrep -P.{0,80}recorded PID', site, re.I | re.S), (
    'critique site does not limit pgrep -P to a recorded PID'
)
assert re.search(r'gpgconf --kill gpg-agent.{0,80}exception', site, re.I | re.S), (
    'critique site does not keep gpgconf --kill gpg-agent as the exception'
)
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

assert re.search(
    r'record.{0,80}child\s+PID.{0,120}process group.{0,180}before waiting',
    site,
    re.I | re.S,
), 'Claude site does not record the child PID and process group before waiting'
assert re.search(
    r'(?:never|do not|must not|does not).{0,80}(?:'
    r'working directory.{0,80}(?:process )?name.{0,80}command-?line|'
    r'(?:process )?name.{0,80}working directory.{0,80}command-?line)',
    site,
    re.I | re.S,
), 'Claude site does not forbid discovery by working directory, name, and command line together'
assert re.search(r'pgrep -P.{0,80}recorded PID', site, re.I | re.S), (
    'Claude site does not limit pgrep -P to a recorded PID'
)
assert re.search(
    r'no recorded\s+identity.{0,80}(?:leave|leaves|left).{0,40}running.{0,80}residual',
    low,
    re.S,
), 'Claude site does not leave a process with no recorded identity running as residual risk'
assert 'gpgconf' not in low, 'Claude site must not require the gpgconf exception'
" "$WORKFLOW_DOC"
}
