#!/usr/bin/env bats
#
# Regression test: the two new idd-critique-telemetry(-report).cmd
# Windows launchers must be excluded from non-Windows chezmoi applies,
# mirroring the existing coderabbit-critique.cmd exclusion -- a
# platform-specific .cmd batch file is useless clutter on Linux/macOS.
# On this test host (non-Windows), .chezmoiignore.tmpl's default
# `.chezmoi.os` renders the non-Windows branch, so the first case is a direct
# regression check. The idd-activation.cmd case overrides chezmoi.os to cover
# the Windows branch as well, so both branches are rendered.
# The ignore list reads data.coderabbit (the CodeRabbit opt-in), so the render
# passes an explicit empty --config: the maintainer's own chezmoi data must not
# be able to fail or change this test.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  REPO_HOME="$BATS_TEST_DIRNAME/../../home"
  IGNORE_TEMPLATE="$REPO_HOME/.chezmoiignore.tmpl"
}

# $1: chezmoi.os (linux or windows)
# $2: data.coderabbit as JSON, or "absent" to omit it
_render_ignore() {
  local config="$BATS_TEST_TMPDIR/chezmoi-config.json"
  if [ "$2" = absent ]; then
    printf '%s\n' '{ "data": {} }' > "$config"
  else
    printf '{ "data": { "coderabbit": %s } }\n' "$2" > "$config"
  fi
  chezmoi execute-template --file "$IGNORE_TEMPLATE" \
    --config "$config" --config-format json \
    --override-data "{\"chezmoi\": {\"os\": \"$1\"}}" \
    --source "$REPO_HOME" --destination "$BATS_TEST_TMPDIR/destination"
}

@test ".chezmoiignore.tmpl excludes both idd-critique-telemetry .cmd launchers on non-Windows" {
  printf '%s\n' '{ "data": {} }' > "$BATS_TEST_TMPDIR/chezmoi-config.json"

  run --separate-stderr chezmoi execute-template --file "$REPO_ROOT/home/.chezmoiignore.tmpl" \
    --config "$BATS_TEST_TMPDIR/chezmoi-config.json" --config-format json \
    --source "$REPO_ROOT" --destination "$BATS_TEST_TMPDIR"

  assert_success
  assert_line '.local/bin/idd-critique-telemetry.cmd'
  assert_line '.local/bin/idd-critique-telemetry-report.cmd'
  # The existing sibling exclusion this fix mirrors; regresses this
  # test's own premise if it ever disappears from the same branch.
  assert_line '.local/bin/coderabbit-critique.cmd'
}

@test "idd-activation.cmd is deployed on Windows and ignored on Linux" {
  run --separate-stderr _render_ignore windows absent

  assert_success
  refute_line '.local/bin/idd-activation.cmd'

  run --separate-stderr _render_ignore linux absent

  assert_success
  assert_line '.local/bin/idd-activation.cmd'
}
