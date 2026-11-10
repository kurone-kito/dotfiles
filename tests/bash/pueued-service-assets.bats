#!/usr/bin/env bats
# cspell:ignore optionxform
# Tests for the Linux user unit template that runs pueued in the foreground
# under systemd. Most assertions read the rendered text; the systemd-analyze
# test parses it with verify, which neither loads it into a manager nor starts
# the unit.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  UNIT_TEMPLATE="$REPO_ROOT/home/dot_config/systemd/user/pueued.service.tmpl"
  TMP_HOME="$BATS_TEST_TMPDIR/home"
  RENDERED="$BATS_TEST_TMPDIR/pueued.service"
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
    chezmoi execute-template --file "$UNIT_TEMPLATE" \
    --config "$config" --config-format json \
    --source "$source" --destination "$TMP_HOME" > "$RENDERED"
  # An empty render would make every absence check pass vacuously.
  [ -s "$RENDERED" ]
}

# Queries the rendered unit with configparser. The parser settings are
# deliberate: strict=True (the default) rejects a duplicated key or section,
# so a second ExecStart cannot slip through; interpolation=None keeps the
# literal %h specifier, which default interpolation would reject; and
# optionxform=str keeps the key case that systemd requires.
#   $1: sections            -> the section names, sorted, as a JSON array
#   $1: keys, $2: section   -> the key names of one section, sorted, as JSON
#   $1: value, $2: section, $3: key -> the raw value of one key
_unit_query() {
  python3 - "$RENDERED" "$@" << 'PY'
import configparser
import json
import sys

parser = configparser.ConfigParser(interpolation=None)
parser.optionxform = str
with open(sys.argv[1], encoding="utf-8") as handle:
    parser.read_file(handle)

mode = sys.argv[2]
if mode == "sections":
    print(json.dumps(sorted(parser.sections())))
elif mode == "keys":
    print(json.dumps(sorted(parser.options(sys.argv[3]))))
elif mode == "value":
    print(parser.get(sys.argv[3], sys.argv[4]))
else:
    sys.exit(f"unknown mode: {mode}")
PY
}

@test "has exactly the Unit, Service and Install sections" {
  _render

  run _unit_query sections
  assert_success
  assert_output '["Install", "Service", "Unit"]'
}

@test "has exactly three section headers, so no empty [DEFAULT] header slips through" {
  _render

  # configparser hides the DEFAULT section, so count the raw headers instead.
  run grep -c '^\[' "$RENDERED"
  assert_output '3'
}

@test "contains no carriage returns and no trailing blanks" {
  _render

  # configparser strips whitespace silently, so these checks read the raw text.
  run grep -c $'\r' "$RENDERED"
  assert_output '0'

  run grep -c '[[:blank:]]$' "$RENDERED"
  assert_output '0'
}

@test "[Unit] has exactly the expected keys" {
  _render

  run _unit_query keys Unit
  assert_success
  assert_output '["Description", "StartLimitBurst", "StartLimitIntervalSec"]'
}

@test "[Service] has exactly the expected keys" {
  _render

  run _unit_query keys Service
  assert_success
  assert_output '["ExecStart", "Restart", "RestartSec", "Type"]'
}

@test "[Install] has exactly the expected keys" {
  _render

  run _unit_query keys Install
  assert_success
  assert_output '["WantedBy"]'
}

@test "[Service] Type is simple" {
  _render

  run _unit_query value Service Type
  assert_success
  assert_output 'simple'
}

@test "[Install] WantedBy is default.target" {
  _render

  run _unit_query value Install WantedBy
  assert_success
  assert_output 'default.target'
}

@test "[Unit] StartLimitIntervalSec is 60 and StartLimitBurst is 5" {
  _render

  run _unit_query value Unit StartLimitIntervalSec
  assert_success
  assert_output '60'

  run _unit_query value Unit StartLimitBurst
  assert_success
  assert_output '5'
}

@test "[Service] Restart is on-failure and RestartSec is 2" {
  _render

  run _unit_query value Service Restart
  assert_success
  assert_output 'on-failure'

  run _unit_query value Service RestartSec
  assert_success
  assert_output '2'
}

@test "ExecStart is exactly the mise pueued shim with no shell and no -d" {
  _render

  run _unit_query value Service ExecStart
  assert_success
  assert_output '%h/.local/share/mise/shims/pueued'

  # Raw-text check: it also rejects trailing spaces and CR, which configparser
  # would strip silently.
  run grep -Fxc 'ExecStart=%h/.local/share/mise/shims/pueued' "$RENDERED"
  assert_output '1'
}

@test "has no ExecStop line, in any case and including comments" {
  _render

  # Raw-text check: configparser drops comment lines, so a commented-out
  # ExecStop would pass a parser-only check.
  run grep -ci 'execstop' "$RENDERED"
  assert_output '0'
}

@test "contains no pueue shutdown text, including comments" {
  _render

  run grep -cF 'pueue shutdown' "$RENDERED"
  assert_output '0'
}

@test "systemd-analyze reports no diagnostic for this unit under --user" {
  command -v systemd-analyze >/dev/null 2>&1 || skip "systemd-analyze is not installed"
  _render

  # --user checks the unit in the user-manager context, as the zellij sibling
  # test does. verify also loads every other user unit on the host, so its
  # output can carry unrelated diagnostics. The checks below therefore look
  # only for lines that name this unit. A stub shim under the temporary home
  # makes ExecStart executable, so a missing mise shim cannot hide a parser
  # diagnostic behind a "not executable" message.
  mkdir -p "$TMP_HOME/.local/share/mise/shims"
  printf '#!/bin/sh\nexit 0\n' > "$TMP_HOME/.local/share/mise/shims/pueued"
  chmod +x "$TMP_HOME/.local/share/mise/shims/pueued"

  run env HOME="$TMP_HOME" LC_ALL=C systemd-analyze verify --user "$RENDERED"
  # A parser diagnostic for this unit carries file:line.
  refute_output --regexp 'pueued\.service:[0-9]+: '
  # Any other message about this unit, such as a dependency or executable
  # error, names it as "pueued.service: ".
  refute_output --partial 'pueued.service: '
}
