#!/usr/bin/env bats
#
# Tests for idd-critique-telemetry-report: summarizes the JSONL log
# written by idd-critique-telemetry.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_idd-critique-telemetry-report"
  APPENDER="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_idd-critique-telemetry"

  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  LOG_FILE="$XDG_STATE_HOME/idd-critique/log.jsonl"
}

teardown() {
  unset XDG_STATE_HOME
}

append() {
  printf '%s' "$1" | "$APPENDER"
}

@test "reports all-zero stats when the log file does not exist yet" {
  assert [ ! -e "$LOG_FILE" ]

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 0"
  assert_line "Total findings: 0"
  assert_line "Total accepted: 0"
  assert_line "Total rejected: 0"
  assert_line "Average rounds per loop: 0"
}

@test "reports all-zero stats when the log file exists but is empty" {
  mkdir -p "$(dirname "$LOG_FILE")"
  : > "$LOG_FILE"

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 0"
  assert_line "Average rounds per loop: 0"
}

@test "aggregates findings/accepted/rejected and computes average rounds per loop across two loops" {
  append '{"round":1,"findingsCount":3,"acceptedCount":2,"rejectedCount":1}'
  append '{"round":2,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
  append '{"round":1,"findingsCount":0,"acceptedCount":0,"rejectedCount":0}'

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 3"
  assert_line "Total findings: 4"
  assert_line "Total accepted: 3"
  assert_line "Total rejected: 1"
  assert_line "Average rounds per loop: 1.5"
}

@test "tolerates a syntactically malformed line by skipping it" {
  append '{"round":1,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
  mkdir -p "$(dirname "$LOG_FILE")"
  printf 'not json at all\n' >> "$LOG_FILE"
  append '{"round":2,"findingsCount":2,"acceptedCount":1,"rejectedCount":1}'

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 2"
  assert_line "Total findings: 3"
}

@test "tolerates a line that is valid JSON but not an object (regression: bare scalar must not crash the report)" {
  append '{"round":1,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
  mkdir -p "$(dirname "$LOG_FILE")"
  printf '12345\n' >> "$LOG_FILE"
  append '{"round":2,"findingsCount":2,"acceptedCount":2,"rejectedCount":0}'

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 2"
  assert_line "Total findings: 3"
  assert_line "Total accepted: 3"
}

@test "treats a payload with no round-1 entry as a single loop (no divide-by-zero)" {
  append '{"round":2,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'
  append '{"round":3,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 2"
  assert_line "Average rounds per loop: 2"
}

@test "defaults missing findingsCount/acceptedCount/rejectedCount fields to 0" {
  append '{"round":1}'

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 1"
  assert_line "Total findings: 0"
  assert_line "Total accepted: 0"
  assert_line "Total rejected: 0"
}

@test "rejects a telemetry object with no round field (regression: must not inflate totals)" {
  append '{}'
  append '{"round":1,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 1"
}

@test "rejects a telemetry object with a nonpositive or nonnumeric round" {
  append '{"round":0,"findingsCount":1}'
  append '{"round":"x","findingsCount":1}'
  append '{"round":1,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 1"
}

@test "an array-wrapped single object is not accepted as a bare object (jq type check is array-safe)" {
  append '[{"round":1}]'
  append '{"round":1,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 1"
}

@test "defaults a nonnumeric counter value to 0 instead of aborting (regression)" {
  # `// 0` alone only substitutes for null/false, so a present-but-
  # nonnumeric field (e.g. a string) would otherwise reach `add`, which
  # errors on a mixed string/number list and aborts the whole report.
  append '{"round":1,"findingsCount":1,"acceptedCount":"oops","rejectedCount":0}'
  append '{"round":2,"findingsCount":2,"acceptedCount":2,"rejectedCount":0}'

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 2"
  assert_line "Total findings: 3"
  assert_line "Total accepted: 2"
}

@test "fails clearly when jq is not found in PATH" {
  no_jq_bin="$BATS_TEST_TMPDIR/no-jq-bin"
  mkdir -p "$no_jq_bin"
  for tool in cat mkdir tr printf sh dirname basename rm mv cp wc bash; do
    tool_path=$(command -v "$tool" 2>/dev/null) || continue
    ln -sf "$tool_path" "$no_jq_bin/$tool"
  done

  run env PATH="$no_jq_bin" XDG_STATE_HOME="$XDG_STATE_HOME" HOME="$HOME" "$SCRIPT"

  assert_failure
  assert_output --partial "jq is required"
}

@test "fails clearly when neither XDG_STATE_HOME nor HOME is set" {
  run env -u XDG_STATE_HOME -u HOME PATH="$PATH" "$SCRIPT"

  assert_failure
  assert_output --partial "cannot locate the telemetry log"
}

@test "fails clearly when the log path exists but is not a regular file (regression)" {
  # Distinguish "exists but wrong type" (this script cannot do its job)
  # from "genuinely absent" (a valid all-zero state) -- both used to
  # report all-zero stats via the same `[ ! -f ]` check.
  mkdir -p "$XDG_STATE_HOME/idd-critique/log.jsonl"

  run "$SCRIPT"

  assert_failure
  assert_output --partial "exists but is not a regular file"
}

@test "rejects an array-valued round via jq's own type check (regression)" {
  # jq's `.round | type` for an array value is "array", not "number",
  # so this is already correctly rejected -- covered here for parity
  # with the PowerShell twin's equivalent regression test.
  append '{"round":[1],"findingsCount":[7]}'
  append '{"round":1,"findingsCount":1,"acceptedCount":1,"rejectedCount":0}'

  run "$SCRIPT"

  assert_success
  assert_line "Total rounds: 1"
  assert_line "Total findings: 1"
}
