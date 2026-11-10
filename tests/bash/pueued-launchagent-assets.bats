#!/usr/bin/env bats
# Tests for the macOS LaunchAgent template that runs pueued in the
# foreground under launchd. The assertions read the rendered text, so
# they run on Linux. Nothing here loads the agent with launchctl.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PLIST_TEMPLATE="$REPO_ROOT/home/Library/LaunchAgents/com.kurone-kito.pueued.plist.tmpl"
  TMP_HOME="$BATS_TEST_TMPDIR/home"
  RENDERED="$BATS_TEST_TMPDIR/com.kurone-kito.pueued.plist"
  mkdir -p "$TMP_HOME"
}

# Renders the template with every home and XDG directory under a temporary
# path, and with an empty source tree and an empty chezmoi config, so neither
# the maintainer's data nor the real home can leak into the output. The output
# is written to $RENDERED.
_render() {
  local config="$BATS_TEST_TMPDIR/chezmoi.json"
  local source="$BATS_TEST_TMPDIR/source"
  printf '%s\n' '{}' > "$config"
  mkdir -p "$source"
  HOME="$TMP_HOME" \
    XDG_CONFIG_HOME="$TMP_HOME/.config" \
    XDG_CACHE_HOME="$TMP_HOME/.cache" \
    XDG_DATA_HOME="$TMP_HOME/.local/share" \
    XDG_STATE_HOME="$TMP_HOME/.local/state" \
    chezmoi execute-template --file "$PLIST_TEMPLATE" \
    --config "$config" --config-format json \
    --source "$source" --destination "$TMP_HOME" > "$RENDERED"
}

# $1: a top-level key of the rendered plist. Prints its parsed value as JSON.
_plist_key() {
  python3 - "$RENDERED" "$1" << 'PY'
import json
import plistlib
import sys

with open(sys.argv[1], "rb") as handle:
    plist = plistlib.load(handle)
print(json.dumps(plist[sys.argv[2]], sort_keys=True))
PY
}

@test "starts with the XML declaration and has a plist root element" {
  _render

  assert_equal "$(head -n 1 "$RENDERED")" '<?xml version="1.0" encoding="UTF-8"?>'
  run grep -cF '<plist version="1.0">' "$RENDERED"
  assert_output "1"
}

@test "dict open and close tags occur the same number of times" {
  _render

  local opens closes
  opens="$(grep -o '<dict>' "$RENDERED" | wc -l | tr -d ' ')"
  closes="$(grep -o '</dict>' "$RENDERED" | wc -l | tr -d ' ')"
  assert_equal "$opens" "$closes"
  assert_equal "$opens" "2"
}

@test "label is com.kurone-kito.pueued" {
  _render

  run _plist_key Label
  assert_success
  assert_output '"com.kurone-kito.pueued"'
}

@test "RunAtLoad is true" {
  _render

  run _plist_key RunAtLoad
  assert_success
  assert_output 'true'
}

@test "ThrottleInterval is 2" {
  _render

  run _plist_key ThrottleInterval
  assert_success
  assert_output '2'
}

@test "KeepAlive is a dictionary whose SuccessfulExit is false" {
  _render

  run _plist_key KeepAlive
  assert_success
  assert_output '{"SuccessfulExit": false}'
}

@test "ProgramArguments is one string: the home directory plus the mise pueued shim" {
  _render

  run _plist_key ProgramArguments
  assert_success
  assert_output "[\"$TMP_HOME/.local/share/mise/shims/pueued\"]"
}
