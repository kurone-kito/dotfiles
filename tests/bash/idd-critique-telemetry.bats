#!/usr/bin/env bats
#
# Tests for idd-critique-telemetry: a fire-and-forget JSONL log sink for
# critiqueLoop.telemetryHook.command.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_idd-critique-telemetry"

  # Pin XDG_STATE_HOME explicitly for most tests, rather than letting it
  # leak in from the real environment (00-xdg.sh exports it in an
  # interactive shell, but bats does not source it) -- a test that
  # forgot this could otherwise append into the real
  # ~/.local/state/idd-critique/log.jsonl.
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  LOG_FILE="$XDG_STATE_HOME/idd-critique/log.jsonl"
}

teardown() {
  unset XDG_STATE_HOME
}

@test "appends a well-formed JSON payload as one JSONL line" {
  run bash -c "printf '%s' '{\"phase\":\"C\",\"round\":1,\"findingsCount\":3}' | '$SCRIPT'"

  assert_success
  assert [ -f "$LOG_FILE" ]
  run wc -l "$LOG_FILE"
  assert_output --partial "1 "
  run cat "$LOG_FILE"
  assert_line --index 0 '{"phase":"C","round":1,"findingsCount":3}'
}

@test "compacts a pretty-printed multi-line payload to one JSONL line" {
  run bash -c "printf '{\n  \"round\": 2,\n  \"findingsCount\": 1\n}' | '$SCRIPT'"

  assert_success
  run wc -l "$LOG_FILE"
  assert_output --partial "1 "
  run cat "$LOG_FILE"
  assert_line --index 0 '{"round":2,"findingsCount":1}'
}

@test "appends one line per invocation, in order" {
  run bash -c "printf '{\"round\":1}' | '$SCRIPT'"
  assert_success
  run bash -c "printf '{\"round\":2}' | '$SCRIPT'"
  assert_success

  run cat "$LOG_FILE"
  assert_line --index 0 '{"round":1}'
  assert_line --index 1 '{"round":2}'
}

@test "creates the parent state directory when it does not already exist" {
  assert [ ! -d "$XDG_STATE_HOME/idd-critique" ]

  run bash -c "printf '{\"round\":1}' | '$SCRIPT'"

  assert_success
  assert [ -d "$XDG_STATE_HOME/idd-critique" ]
  assert [ -f "$LOG_FILE" ]
}

@test "writes nothing for empty stdin, but still exits 0" {
  run bash -c "printf '' | '$SCRIPT'"

  assert_success
  assert [ ! -e "$LOG_FILE" ]
}

@test "writes nothing for whitespace-only stdin, but still exits 0" {
  run bash -c "printf '   \n  \t \n' | '$SCRIPT'"

  assert_success
  assert [ ! -e "$LOG_FILE" ]
}

@test "falls back to \$HOME/.local/state when XDG_STATE_HOME is unset" {
  unset XDG_STATE_HOME
  default_log="$HOME/.local/state/idd-critique/log.jsonl"

  run bash -c "printf '{\"round\":1}' | '$SCRIPT'"

  assert_success
  assert [ -f "$default_log" ]
}

@test "always exits 0 even when the state directory cannot be created" {
  # A plain file occupying the directory segment makes mkdir -p fail.
  mkdir -p "$XDG_STATE_HOME"
  : > "$XDG_STATE_HOME/idd-critique"

  run bash -c "printf '{\"round\":1}' | '$SCRIPT'"

  assert_success
  assert_output ""
}

@test "always exits 0 and leaks no diagnostic when log.jsonl itself is unexpectedly a directory (regression)" {
  # Redirections apply left to right, so a bare `cmd >> file
  # 2>/dev/null` still leaks a shell "cannot create" diagnostic to real
  # stderr when `>> file` itself fails to open (e.g. log.jsonl exists
  # as a directory) -- that failure happens before `2>/dev/null` takes
  # effect (empirically confirmed). The append must be grouped so
  # `2>/dev/null` also covers the redirection-setup failure itself, not
  # just an ordinary write failure.
  mkdir -p "$XDG_STATE_HOME/idd-critique/log.jsonl"

  run bash -c "printf '{\"round\":1}' | '$SCRIPT'"

  assert_success
  assert_output ""
}

@test "always exits 0 even when neither XDG_STATE_HOME nor HOME is set" {
  run env -u XDG_STATE_HOME -u HOME PATH="$PATH" bash -c "printf '{\"round\":1}' | '$SCRIPT'"

  assert_success
  assert_output ""
}

@test "falls back to the raw payload, newlines flattened, when the payload is not exactly one JSON value (jq present)" {
  # Regression: plain `jq -c .` emits one output line per top-level
  # value it sees, so two concatenated top-level JSON values in one
  # invocation would otherwise silently split into two telemetry
  # records instead of being treated as one malformed payload.
  run bash -c "printf '{\"round\":1}\n{\"round\":2}' | '$SCRIPT'"

  assert_success
  run wc -l "$LOG_FILE"
  assert_output --partial "1 "
  run cat "$LOG_FILE"
  assert_line --index 0 '{"round":1} {"round":2}'
}

@test "preserves a literal Infinity/NaN token verbatim instead of letting jq launder it to a finite number (regression)" {
  # jq accepts the bare `NaN`/`Infinity` tokens, but its own `-c`
  # serialization turns Infinity into the *finite* value
  # 1.7976931348623157e+308 (JSON has no Infinity literal) -- once
  # that finite text is written to the log, the report's own
  # isnan/isinfinite guard can no longer recognize it as ever having
  # been non-finite. Falling back to the raw-payload path instead
  # preserves the literal token as text, which the report correctly
  # rejects on a fresh parse (empirically confirmed end to end).
  run bash -c "printf '{\"round\":1,\"findingsCount\":Infinity}' | '$SCRIPT'"

  assert_success
  run cat "$LOG_FILE"
  assert_line --index 0 '{"round":1,"findingsCount":Infinity}'
}

@test "falls back to the raw payload, newlines flattened, when jq is unavailable" {
  # Scope PATH to only coreutils-equivalent tools plus sh itself, with
  # no jq -- mirroring coderabbit-critique.bats's "fails closed when jq
  # is not found" technique of scoping PATH for the invocation only.
  no_jq_bin="$BATS_TEST_TMPDIR/no-jq-bin"
  mkdir -p "$no_jq_bin"
  for tool in cat mkdir tr printf sh dirname basename rm mv cp wc bash; do
    tool_path=$(command -v "$tool" 2>/dev/null) || continue
    ln -sf "$tool_path" "$no_jq_bin/$tool"
  done

  run env PATH="$no_jq_bin" XDG_STATE_HOME="$XDG_STATE_HOME" HOME="$HOME" \
    bash -c "printf '{\n  \"round\": 1,\n  \"findingsCount\": 2\n}' | '$SCRIPT'"

  assert_success
  run cat "$LOG_FILE"
  assert_line --index 0 '{   "round": 1,   "findingsCount": 2 }'
}
