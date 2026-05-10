#!/usr/bin/env bats
# Tests for the secret-deploy-state bash helper.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  SCRIPT="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_secret-deploy-state"
  TMP_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TMP_HOME/.config/chezmoi"
  export HOME="$TMP_HOME"
  STATE="$TMP_HOME/.config/chezmoi/secret-deploy-state.json"
}

# Create a small file to record. Echo its absolute path.
_make_file() {
  local rel="$1" content="${2:-hello}"
  local abs="$TMP_HOME/$rel"
  mkdir -p "$(dirname "$abs")"
  printf '%s' "$content" > "$abs"
  chmod 600 "$abs"
  printf '%s' "$abs"
}

@test "no args prints usage and exits 2" {
  run "$SCRIPT"
  assert_failure 2
  assert_output --partial "Usage:"
}

@test "--help prints usage and exits 0" {
  run "$SCRIPT" --help
  assert_success
  assert_output --partial "Usage:"
}

@test "path subcommand prints default state path" {
  run "$SCRIPT" path
  assert_success
  assert_output "$STATE"
}

@test "SECRET_DEPLOY_STATE override is honored" {
  alt="$BATS_TEST_TMPDIR/alt.json"
  SECRET_DEPLOY_STATE="$alt" run "$SCRIPT" path
  assert_success
  assert_output "$alt"
}

@test "record creates state file with mode 600" {
  f="$(_make_file ".secret/api.txt" "hello")"
  run "$SCRIPT" record secretFile api "$f"
  assert_success
  assert_file_exists "$STATE"
  mode="$(stat -c '%a' "$STATE" 2>/dev/null || stat -f '%A' "$STATE")"
  [ "$mode" = "600" ]
}

@test "record stores sha256 matching sha256sum output" {
  f="$(_make_file ".secret/x.txt" "abc")"
  expected="$(printf 'abc' | sha256sum | awk '{print $1}')"
  run "$SCRIPT" record secretFile x "$f"
  assert_success
  got="$(jq -r --arg p "$f" '.entries[] | select(.path==$p) | .sha256' "$STATE")"
  [ "$got" = "$expected" ]
}

@test "record upserts existing entry by path (no duplicates)" {
  f="$(_make_file ".secret/y.txt" "v1")"
  "$SCRIPT" record secretFile y "$f"
  printf 'v2' > "$f"
  run "$SCRIPT" record secretFile y "$f"
  assert_success
  count="$(jq --arg p "$f" '[.entries[] | select(.path==$p)] | length' "$STATE")"
  [ "$count" = "1" ]
  sha="$(jq -r --arg p "$f" '.entries[] | select(.path==$p) | .sha256' "$STATE")"
  expected="$(printf 'v2' | sha256sum | awk '{print $1}')"
  [ "$sha" = "$expected" ]
}

@test "record preserves entries for other paths" {
  f1="$(_make_file ".secret/a.txt" "A")"
  f2="$(_make_file ".secret/b.txt" "B")"
  "$SCRIPT" record secretFile a "$f1"
  "$SCRIPT" record secretFile b "$f2"
  count="$(jq '.entries | length' "$STATE")"
  [ "$count" = "2" ]
}

@test "record on missing file is best-effort (exit 0, state untouched)" {
  run "$SCRIPT" record secretFile gone "$TMP_HOME/.secret/nope.txt"
  assert_success
  assert_output --partial "file not found"
  [ ! -f "$STATE" ]
}

@test "record with relative path is best-effort skip" {
  run "$SCRIPT" record secretFile rel "relative/path"
  assert_success
  assert_output --partial "must be absolute"
  [ ! -f "$STATE" ]
}

@test "record with too few args exits 2" {
  run "$SCRIPT" record only-one
  assert_failure 2
}

@test "record stores category, name, mode and deployedAt" {
  f="$(_make_file ".secret/m.txt" "m")"
  run "$SCRIPT" record sshKey id_ed25519 "$f"
  assert_success
  category="$(jq -r '.entries[0].category' "$STATE")"
  name="$(jq -r '.entries[0].name' "$STATE")"
  mode="$(jq -r '.entries[0].mode' "$STATE")"
  ts="$(jq -r '.entries[0].deployedAt' "$STATE")"
  [ "$category" = "sshKey" ]
  [ "$name" = "id_ed25519" ]
  [ "$mode" = "600" ]
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "record uses atomic write (no .XXXXXX leftovers on success)" {
  f="$(_make_file ".secret/n.txt" "n")"
  run "$SCRIPT" record secretFile n "$f"
  assert_success
  leftovers="$(find "$(dirname "$STATE")" -name '*.XXXXXX*' -o -name 'secret-deploy-state.json.*' 2>/dev/null | wc -l)"
  [ "$leftovers" = "0" ]
}

@test "unknown subcommand exits 2" {
  run "$SCRIPT" gibberish
  assert_failure 2
  assert_output --partial "unknown subcommand"
}
