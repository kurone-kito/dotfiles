#!/usr/bin/env bats
# Tests for data.pueue.parallelism: the rendered one-line file
# home/dot_config/dotfiles/pueue-parallelism.tmpl and the re-emit in
# .chezmoi.toml.tmpl. Both carry the same inline validation, so one case
# table drives both. Every render passes an explicit --config, so the
# maintainer's own chezmoi data can never leak into a test.
# cspell:words pueue tomllib

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  FILE_TEMPLATE="$REPO_ROOT/home/dot_config/dotfiles/pueue-parallelism.tmpl"
  CONFIG_TEMPLATE="$REPO_ROOT/.chezmoi.toml.tmpl"
  TMP_CONFIG="$BATS_TEST_TMPDIR/chezmoi.json"
  TMP_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TMP_HOME"
}

# $1: the value of the data table as JSON.
_write_config() {
  CONFIG_FORMAT=json
  printf '{ "data": %s }\n' "$1" > "$TMP_CONFIG"
}

# $1: the raw TOML value of data.pueue.parallelism (inf and nan cannot be
# written in JSON).
_write_toml_config() {
  CONFIG_FORMAT=toml
  printf '[data.pueue]\nparallelism = %s\n' "$1" > "$TMP_CONFIG"
}

_render_file() {
  chezmoi execute-template --file "$FILE_TEMPLATE" \
    --config "$TMP_CONFIG" --config-format "$CONFIG_FORMAT" \
    --source "$REPO_ROOT" --destination "$TMP_HOME"
}

# What `chezmoi init` writes back, without the trailing comment block whose
# prose names these keys too. The render goes to a file first so that this
# function's status is chezmoi's, not the status of the filter after it.
_render_config() {
  chezmoi execute-template --init --file "$CONFIG_TEMPLATE" \
    --config "$TMP_CONFIG" --config-format "$CONFIG_FORMAT" \
    --promptString git.name="Test User" \
    --promptString git.email="test@example.com" \
    --promptString git.signingkey="" \
    --promptString secret.manager="none" \
    --source "$REPO_ROOT" --destination "$TMP_HOME" > "$BATS_TEST_TMPDIR/init.out" || return $?
  grep -v '^#' "$BATS_TEST_TMPDIR/init.out"
}

# data|rendered integer; an omitted key, 2 and a float64 2 all render as 2.
valid_rows() {
  cat << 'ROWS'
{}|2
{"pueue":{}}|2
{"pueue":{"parallelism":2}}|2
{"pueue":{"parallelism":2.0}}|2
{"pueue":{"parallelism":1}}|1
{"pueue":{"parallelism":4}}|4
{"pueue":{"parallelism":3.0}}|3
{"pueue":{"parallelism":12}}|12
{"pueue":{"parallelism":100}}|100
{"pueue":{"parallelism":9007199254740991}}|9007199254740991
{"pueue":{"parallelism":9007199254740993}}|9007199254740993
{"pueue":{"parallelism":9223372036854775807}}|9223372036854775807
ROWS
}

invalid_rows() {
  cat << 'ROWS'
{"pueue":{"parallelism":0}}
{"pueue":{"parallelism":0.0}}
{"pueue":{"parallelism":-1}}
{"pueue":{"parallelism":-2.0}}
{"pueue":{"parallelism":"3"}}
{"pueue":{"parallelism":""}}
{"pueue":{"parallelism":true}}
{"pueue":{"parallelism":false}}
{"pueue":{"parallelism":2.5}}
{"pueue":{"parallelism":0.5}}
{"pueue":{"parallelism":1e30}}
{"pueue":{"parallelism":1.5e19}}
{"pueue":{"parallelism":9007199254740993.5}}
{"pueue":{"parallelism":null}}
{"pueue":{"parallelism":[2]}}
{"pueue":{"parallelism":{"n":2}}}
{"pueue":"3"}
ROWS
}

@test "the rendered file is the integer and exactly one newline" {
  local data expected
  while IFS='|' read -r data expected; do
    _write_config "$data"
    _render_file > "$BATS_TEST_TMPDIR/rendered"
    printf '%s\n' "$expected" > "$BATS_TEST_TMPDIR/expected"
    cmp -s "$BATS_TEST_TMPDIR/rendered" "$BATS_TEST_TMPDIR/expected" ||
      fail "$data: rendered $(od -An -c "$BATS_TEST_TMPDIR/rendered" | tr -d ' ') instead of ${expected}\\n"
  done < <(valid_rows)
}

@test "the rendered file never uses a float or an exponent form" {
  local data
  for data in '{"pueue":{"parallelism":3.0}}' '{"pueue":{"parallelism":1e1}}' '{"pueue":{"parallelism":2000000.0}}'; do
    _write_config "$data"
    run --separate-stderr _render_file
    assert_success
    [[ "$output" =~ ^[1-9][0-9]*$ ]] || fail "$data: '$output' is not a plain decimal integer"
  done
}

@test "the rendered file refuses a value that is not a positive whole number, naming parallelism" {
  local data
  while IFS= read -r data; do
    _write_config "$data"
    run --separate-stderr _render_file
    [ "$status" -ne 0 ] || fail "$data: rendered '$output' instead of failing"
    [[ "$stderr" == *parallelism* ]] || fail "$data: the error does not name parallelism: $stderr"
  done < <(invalid_rows)
}

@test "the configuration template omits parallelism for an omitted key, 2 and float64 2" {
  local data
  for data in '{}' '{"pueue":{}}' '{"pueue":{"parallelism":2}}' '{"pueue":{"parallelism":2.0}}'; do
    _write_config "$data"
    run --separate-stderr _render_config
    assert_success
    refute_output --partial 'parallelism'
    refute_output --partial '[data.pueue]'
  done
}

@test "the configuration template re-emits any other positive whole number as an integer" {
  local data expected
  while IFS='|' read -r data expected; do
    [ "$expected" != 2 ] || continue
    _write_config "$data"
    run --separate-stderr _render_config
    [ "$status" -eq 0 ] || fail "$data: exit $status: $stderr"
    printf '%s\n' "$output" | grep -qx '\[data.pueue\]' || fail "$data: no [data.pueue] section"
    printf '%s\n' "$output" | grep -qx "parallelism = $expected" || fail "$data: missing 'parallelism = $expected'"
  done < <(valid_rows)
}

@test "the configuration template fails on an invalid value instead of dropping it, naming parallelism" {
  local data
  while IFS= read -r data; do
    _write_config "$data"
    run --separate-stderr _render_config
    [ "$status" -ne 0 ] || fail "$data: rendered instead of failing"
    [[ "$stderr" == *parallelism* ]] || fail "$data: the error does not name parallelism: $stderr"
  done < <(invalid_rows)
}

# TOML-only values: inf and nan parse as float64 and a large integer as
# int64, neither of which the JSON test config can express. A TOML float
# beyond 2^53 - 1 is refused; a TOML integer is not limited that way.
toml_invalid_values() {
  cat << 'ROWS'
inf
+inf
-inf
nan
+nan
1e30
1.5e19
0
-3
0.5
"3"
true
ROWS
}

@test "both templates refuse TOML inf, nan, huge and mistyped values, naming parallelism" {
  local value
  while IFS= read -r value; do
    _write_toml_config "$value"
    run --separate-stderr _render_file
    [ "$status" -ne 0 ] || fail "file template accepted $value as '$output'"
    [[ "$stderr" == *parallelism* ]] || fail "$value: the file template's error does not name parallelism: $stderr"
    run --separate-stderr _render_config
    [ "$status" -ne 0 ] || fail "configuration template accepted $value"
    [[ "$stderr" == *parallelism* ]] || fail "$value: the configuration template's error does not name parallelism: $stderr"
  done < <(toml_invalid_values)
}

@test "both templates render any TOML integer exactly, with no upper bound below int64" {
  local value
  for value in 9007199254740992 9007199254740993 123456789012345678 9223372036854775807; do
    _write_toml_config "$value"
    run --separate-stderr _render_file
    assert_success
    assert_output "$value"
    run --separate-stderr _render_config
    assert_success
    assert_line "parallelism = $value"
  done
}

@test "both templates keep the largest exact integer and render it unchanged from TOML" {
  _write_toml_config 9007199254740991
  run --separate-stderr _render_file
  assert_success
  assert_output "9007199254740991"
  run --separate-stderr _render_config
  assert_success
  assert_line "parallelism = 9007199254740991"
}

@test "the configuration template output is valid TOML that round-trips the value" {
  command -v python3 > /dev/null || skip "python3 is not available"
  _write_config '{"pueue":{"parallelism":6}}'
  run --separate-stderr _render_config
  assert_success
  run python3 -I -c 'import sys, tomllib; print(tomllib.loads(sys.stdin.read())["data"]["pueue"]["parallelism"])' <<< "$output"
  if [ "$status" -eq 1 ] && [[ "$output" == *"No module named tomllib"* ]]; then
    skip "tomllib needs Python 3.11"
  fi
  assert_success
  assert_output "6"
}

@test "nothing in the source tree writes a pueue.yml or touches the default group" {
  run find "$REPO_ROOT/home" -iname '*pueue.y*ml*'
  assert_success
  assert_output ""
  run grep -rn -i 'pueue.yml' "$REPO_ROOT/home" "$REPO_ROOT/scripts"
  # Mentions are allowed only as statements that the file is left alone.
  if [ "$status" -eq 0 ]; then
    refute_output --regexp 'cat > .*pueue\.yml|tee .*pueue\.yml|> *"?[^ ]*pueue\.yml'
  fi
}
