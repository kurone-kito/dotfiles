#!/usr/bin/env bats
#
# Tests for the home/dot_config/idd-skill/config.json.tmpl chezmoi
# template: the rendered user-global critiqueLoop.delegate and
# critiqueLoop.telemetryHook config. The delegate is opt-in through
# data.coderabbit.review, so every render passes an explicit --config (the
# maintainer's own chezmoi data must never leak into a test) and the tests
# that exercise the delegate run in the "lite" mode.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  REPO_HOME="$BATS_TEST_DIRNAME/../../home"
  TEMPLATE_PATH="$REPO_HOME/dot_config/idd-skill/config.json.tmpl"
}

# $1: HOME for the render
# $2: data.coderabbit as JSON (default: review "lite"), or "absent" to omit it
# The helper behind the opt-in is found through --source.
_render() {
  local coderabbit=${2:-'{"review": "lite"}'}
  local config="$BATS_TEST_TMPDIR/chezmoi-config.json"
  if [ "$coderabbit" = absent ]; then
    printf '%s\n' '{ "data": {} }' > "$config"
  else
    printf '{ "data": { "coderabbit": %s } }\n' "$coderabbit" > "$config"
  fi
  HOME="$1" chezmoi execute-template --init \
    --config "$config" --config-format json \
    --source "$REPO_HOME" --destination "$BATS_TEST_TMPDIR/destination" \
    < "$TEMPLATE_PATH"
}

@test "renders valid JSON with mode combined" {
  run _render "$BATS_TEST_TMPDIR/home"

  assert_success
  echo "$output" | python3 -c "
import json, sys
c = json.load(sys.stdin)
assert c['critiqueLoop']['delegate']['mode'] == 'combined', c
"
}

@test "single-quotes the POSIX command path" {
  run _render "$BATS_TEST_TMPDIR/home"

  assert_success
  command=$(echo "$output" | python3 -c "
import json, sys
print(json.load(sys.stdin)['critiqueLoop']['delegate']['command'])
")
  case "$command" in
    "'"*"'") ;;
    *) fail "command is not single-quoted: $command" ;;
  esac
  assert [ "${command#*coderabbit-critique}" != "$command" ]
}

@test "the rendered command parses as a single shell token even with a space and a quote in HOME" {
  run _render "$BATS_TEST_TMPDIR/it's a home"

  assert_success
  command=$(echo "$output" | python3 -c "
import json, sys
print(json.load(sys.stdin)['critiqueLoop']['delegate']['command'])
")
  # If quoting is correct, eval'ing "set -- $command" leaves exactly one
  # positional argument -- the whole path -- not multiple words split on
  # the embedded space, and not a syntax error from the embedded quote.
  eval "set -- $command"
  assert_equal "$#" 1
  case "$1" in
    *"it's a home"*"coderabbit-critique") ;;
    *) fail "unexpected single token: $1" ;;
  esac
}

@test "renders both delegate and telemetryHook.command, each correctly quoted" {
  run _render "$BATS_TEST_TMPDIR/home"

  assert_success
  echo "$output" | python3 -c "
import json, sys
c = json.load(sys.stdin)
loop = c['critiqueLoop']
delegate_command = loop['delegate']['command']
telemetry_command = loop['telemetryHook']['command']
assert delegate_command.startswith(\"'\") and delegate_command.endswith(\"'\"), delegate_command
assert telemetry_command.startswith(\"'\") and telemetry_command.endswith(\"'\"), telemetry_command
assert 'coderabbit-critique' in delegate_command, delegate_command
assert 'idd-critique-telemetry' in telemetry_command, telemetry_command
# telemetryHook has no mode field -- it is never a delegate substitute.
assert 'mode' not in loop['telemetryHook'], loop['telemetryHook']
"
}

@test "single-quotes the telemetryHook POSIX command path" {
  run _render "$BATS_TEST_TMPDIR/home"

  assert_success
  command=$(echo "$output" | python3 -c "
import json, sys
print(json.load(sys.stdin)['critiqueLoop']['telemetryHook']['command'])
")
  case "$command" in
    "'"*"'") ;;
    *) fail "command is not single-quoted: $command" ;;
  esac
  assert [ "${command#*idd-critique-telemetry}" != "$command" ]
}

@test "the rendered telemetryHook command parses as a single shell token even with a space and a quote in HOME" {
  run _render "$BATS_TEST_TMPDIR/it's a home"

  assert_success
  command=$(echo "$output" | python3 -c "
import json, sys
print(json.load(sys.stdin)['critiqueLoop']['telemetryHook']['command'])
")
  # Same single-token property as the delegate command above.
  eval "set -- $command"
  assert_equal "$#" 1
  case "$1" in
    *"it's a home"*"idd-critique-telemetry") ;;
    *) fail "unexpected single token: $1" ;;
  esac
}

# ---------------------------------------------------------------------------
# The opt-in: data.coderabbit.review
# ---------------------------------------------------------------------------

@test "off renders no delegate but keeps the telemetry hook" {
  for coderabbit in absent '{}' '{"review": false}' '{"deepReview": false}'; do
    run --separate-stderr _render "$BATS_TEST_TMPDIR/home" "$coderabbit"

    assert_success
    echo "$output" | python3 -c "
import json, sys
c = json.load(sys.stdin)
loop = c['critiqueLoop']
assert 'delegate' not in loop, loop
assert sorted(loop) == ['telemetryHook'], loop
assert 'idd-critique-telemetry' in loop['telemetryHook']['command'], loop
"
  done
}

@test "lite, deep and the legacy alias render the same delegate" {
  run --separate-stderr _render "$BATS_TEST_TMPDIR/home" '{"review": "lite"}'
  assert_success
  lite_output=$output

  for coderabbit in '{"review": true}' '{"review": "deep"}' '{"deepReview": true}' \
    '{"review": "deep", "deepReview": true}'; do
    run --separate-stderr _render "$BATS_TEST_TMPDIR/home" "$coderabbit"

    assert_success
    assert_equal "$output" "$lite_output"
  done
}

@test "the telemetry hook is identical in every mode" {
  run --separate-stderr _render "$BATS_TEST_TMPDIR/home" '{"review": false}'
  assert_success
  off_hook=$(echo "$output" | python3 -c "
import json, sys
print(json.dumps(json.load(sys.stdin)['critiqueLoop']['telemetryHook'], sort_keys=True))
")

  for coderabbit in '{"review": "lite"}' '{"review": "deep"}'; do
    run --separate-stderr _render "$BATS_TEST_TMPDIR/home" "$coderabbit"

    assert_success
    hook=$(echo "$output" | python3 -c "
import json, sys
print(json.dumps(json.load(sys.stdin)['critiqueLoop']['telemetryHook'], sort_keys=True))
")
    assert_equal "$hook" "$off_hook"
  done
}

@test "an invalid review value fails the render" {
  run --separate-stderr _render "$BATS_TEST_TMPDIR/home" '{"review": "bogus"}'

  assert_failure
  assert_regex "$stderr" 'data\.coderabbit\.review'
}
