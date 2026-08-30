#!/usr/bin/env bats
#
# Tests for the home/dot_config/idd-skill/config.json.tmpl chezmoi
# template: the rendered user-global critiqueLoop.delegate config.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  TEMPLATE_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/idd-skill/config.json.tmpl"
}

_render() {
  HOME="$1" chezmoi execute-template --init < "$TEMPLATE_PATH"
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
