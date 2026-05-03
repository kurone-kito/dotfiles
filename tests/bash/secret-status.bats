#!/usr/bin/env bats
# Tests for the secret-status bash command.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  SCRIPT_PATH="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_secret-status"
  TMP_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TMP_HOME/.ssh" "$TMP_HOME/.config/chezmoi"
  chmod 700 "$TMP_HOME/.ssh"
  export HOME="$TMP_HOME"
  export NO_COLOR=1   # tests assert plain text
  MANIFEST="$TMP_HOME/.config/chezmoi/secret-deploy-manifest.json"
}

# Write a manifest from the given JSON snippet into MANIFEST.
_manifest() {
  printf '%s' "$1" > "$MANIFEST"
}

# Build a minimal manifest skeleton with given category arrays.
_skeleton() {
  cat > "$MANIFEST" <<JSON
{
  "version": 1,
  "manager": "bitwarden",
  "os": "linux",
  "homeDir": "$TMP_HOME",
  "ghqRoot": "",
  "categories": $1
}
JSON
}

@test "exits 2 when manifest file is missing" {
  rm -f "$MANIFEST"
  run "$SCRIPT_PATH"
  assert_failure 2
  assert_output --partial "manifest not found"
}

@test "exits 2 when manifest is invalid JSON" {
  printf 'not json' > "$MANIFEST"
  run "$SCRIPT_PATH"
  assert_failure 2
  assert_output --partial "not valid JSON"
}

@test "exits 0 when no deploy targets configured" {
  _skeleton '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[]}'
  run "$SCRIPT_PATH"
  assert_success
  assert_output --partial "no deploy targets configured"
}

@test "summary mode prints one line with counts" {
  _skeleton '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[]}'
  run "$SCRIPT_PATH" --summary
  assert_success
  assert_output --partial "secret-status:"
  assert_output --partial "OK 0"
  assert_output --partial "total 0"
}

@test "json mode emits parseable JSON" {
  _skeleton '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
    {"label":"x","item":"X","target":"x.txt","absPath":"/nonexistent/x.txt","attachment":""}
  ],"envFiles":[]}'
  run "$SCRIPT_PATH" --json
  echo "$output" | python3 -c "
import json, sys
m = json.load(sys.stdin)
assert m['manager'] == 'bitwarden'
assert any(r['status'] == 'MISSING' for r in m['rows'])
"
}

@test "secret file present with correct mode is OK" {
  install -m 600 /dev/null "$TMP_HOME/secret.txt"
  printf 'secret\n' > "$TMP_HOME/secret.txt"
  chmod 600 "$TMP_HOME/secret.txt"
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[
    {\"label\":\"s\",\"item\":\"S\",\"target\":\"secret.txt\",\"absPath\":\"$TMP_HOME/secret.txt\",\"attachment\":\"\"}
  ],\"envFiles\":[]}"
  run "$SCRIPT_PATH"
  assert_success
  assert_output --partial "OK"
}

@test "secret file with wrong mode is WARN" {
  printf 'secret\n' > "$TMP_HOME/secret.txt"
  chmod 644 "$TMP_HOME/secret.txt"
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[
    {\"label\":\"s\",\"item\":\"S\",\"target\":\"secret.txt\",\"absPath\":\"$TMP_HOME/secret.txt\",\"attachment\":\"\"}
  ],\"envFiles\":[]}"
  run "$SCRIPT_PATH"
  assert_failure 1
  assert_output --partial "WARN"
  assert_output --partial "mode 644, want 600"
}

@test "secret file missing is MISSING" {
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[
    {\"label\":\"s\",\"item\":\"S\",\"target\":\"none.txt\",\"absPath\":\"$TMP_HOME/none.txt\",\"attachment\":\"\"}
  ],\"envFiles\":[]}"
  run "$SCRIPT_PATH"
  assert_failure 1
  assert_output --partial "MISSING"
}

@test "gpg without fingerprint is UNKNOWN" {
  _skeleton '{"gpg":[
    {"label":"x","item":"X","fingerprint":""}
  ],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[]}'
  run "$SCRIPT_PATH"
  assert_failure 1
  assert_output --partial "UNKNOWN"
  assert_output --partial "no expected fingerprint"
}

@test "ssh key OK when private and public files present with correct modes" {
  printf 'priv\n' > "$TMP_HOME/.ssh/id_test"
  chmod 600 "$TMP_HOME/.ssh/id_test"
  printf 'pub\n' > "$TMP_HOME/.ssh/id_test.pub"
  chmod 644 "$TMP_HOME/.ssh/id_test.pub"
  _skeleton "{\"gpg\":[],\"sshKeys\":[
    {\"label\":\"t\",\"item\":\"T\",\"filename\":\"id_test\",
     \"privatePath\":\"$TMP_HOME/.ssh/id_test\",
     \"publicPath\":\"$TMP_HOME/.ssh/id_test.pub\"}
  ],\"sshHosts\":[],\"secretFiles\":[],\"envFiles\":[]}"
  run "$SCRIPT_PATH"
  assert_success
  assert_output --partial "OK"
}

@test "env file UNKNOWN when ghq root unresolved" {
  _skeleton '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[
    {"label":"e","item":"E","repo":"github.com/me/x","filename":".env",
     "subpath":"","absPath":"","attachment":""}
  ]}'
  run "$SCRIPT_PATH"
  assert_failure 1
  assert_output --partial "UNKNOWN"
  assert_output --partial "ghq root unresolved"
}

@test "env file warns when filename not in .gitignore" {
  local repo="$TMP_HOME/repo"
  mkdir -p "$repo/.git"
  printf 'env\n' > "$repo/.env"
  chmod 600 "$repo/.env"
  printf 'something-else\n' > "$repo/.gitignore"
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[],\"envFiles\":[
    {\"label\":\"e\",\"item\":\"E\",\"repo\":\"github.com/me/x\",\"filename\":\".env\",
     \"subpath\":\"\",\"absPath\":\"$repo/.env\",\"attachment\":\"\"}
  ]}"
  run "$SCRIPT_PATH"
  assert_failure 1
  assert_output --partial "WARN"
  assert_output --partial "not in .gitignore"
}

@test "env file OK when gitignore lists filename" {
  local repo="$TMP_HOME/repo2"
  mkdir -p "$repo/.git"
  printf 'env\n' > "$repo/.env"
  chmod 600 "$repo/.env"
  printf '.env\n' > "$repo/.gitignore"
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[],\"envFiles\":[
    {\"label\":\"e\",\"item\":\"E\",\"repo\":\"github.com/me/x\",\"filename\":\".env\",
     \"subpath\":\"\",\"absPath\":\"$repo/.env\",\"attachment\":\"\"}
  ]}"
  run "$SCRIPT_PATH"
  assert_success
  assert_output --partial "OK"
}

@test "ssh host UNKNOWN when ssh missing from PATH" {
  _skeleton '{"gpg":[],"sshKeys":[],"sshHosts":[
    {"alias":"h","hostname":"example.com","user":"u","identity":"id",
     "identityPath":"/no/where","port":22}
  ],"secretFiles":[],"envFiles":[]}'
  # Strip ssh from PATH while keeping jq/python3 available.
  mkdir -p "$BATS_TEST_TMPDIR/limited"
  for tool in jq python3 bash awk grep stat dirname sed printf; do
    if command -v "$tool" >/dev/null 2>&1; then
      ln -sf "$(command -v "$tool")" "$BATS_TEST_TMPDIR/limited/$tool" 2>/dev/null || true
    fi
  done
  PATH="$BATS_TEST_TMPDIR/limited" run "$SCRIPT_PATH"
  assert_failure 1
  assert_output --partial "UNKNOWN"
  assert_output --partial "ssh not on PATH"
}

@test "--no-color suppresses ANSI even on TTY" {
  _skeleton '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[]}'
  unset NO_COLOR
  run "$SCRIPT_PATH" --no-color
  assert_success
  refute_output --regexp $'\033\\['
}

@test "NO_COLOR env disables ANSI" {
  _skeleton '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[]}'
  NO_COLOR=1 run "$SCRIPT_PATH"
  assert_success
  refute_output --regexp $'\033\\['
}

@test "summary mode does not consume parent stdin" {
  _skeleton '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[],"envFiles":[]}'
  local probe="$BATS_TEST_TMPDIR/probe.txt"
  # Feed a sentinel line, then run --summary with that pipe as stdin.
  # If --summary consumes the line, the trailing `read` will fail.
  run bash -c "
    { printf 'SENTINEL\n'; } | {
      '$SCRIPT_PATH' --summary >/dev/null
      IFS= read -r line
      printf '%s' \"\$line\"
    }
  "
  assert_success
  assert_output "SENTINEL"
}

@test "json mode does not consume parent stdin" {
  _skeleton '{"gpg":[],"sshKeys":[],"sshHosts":[],"secretFiles":[
    {"label":"x","item":"X","target":"x.txt","absPath":"/nonexistent/x.txt","attachment":""}
  ],"envFiles":[]}'
  run bash -c "
    { printf 'SENTINEL\n'; } | {
      '$SCRIPT_PATH' --json >/dev/null
      IFS= read -r line
      printf '%s' \"\$line\"
    }
  "
  assert_output "SENTINEL"
}

# ---------------------------------------------------------------------------
# DRIFT detection (deploy-state file)
# ---------------------------------------------------------------------------

# Write a deploy-state file with a single entry for $1 (path), $2 (sha).
_state() {
  local path="$1" sha="$2"
  cat > "$TMP_HOME/.config/chezmoi/secret-deploy-state.json" <<JSON
{
  "version": 1,
  "entries": [
    {"category":"secretFile","name":"s","path":"$path","sha256":"$sha","mode":"600","deployedAt":"2026-04-26T00:00:00Z"}
  ]
}
JSON
}

@test "DRIFT: secret file with sha mismatch is promoted to DRIFT" {
  printf 'modified\n' > "$TMP_HOME/secret.txt"
  chmod 600 "$TMP_HOME/secret.txt"
  _state "$TMP_HOME/secret.txt" "0000000000000000000000000000000000000000000000000000000000000000"
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[
    {\"label\":\"s\",\"item\":\"S\",\"target\":\"secret.txt\",\"absPath\":\"$TMP_HOME/secret.txt\",\"attachment\":\"\"}
  ],\"envFiles\":[]}"
  run "$SCRIPT_PATH"
  assert_failure 1
  assert_output --partial "DRIFT"
  assert_output --partial "content changed since deploy"
}

@test "DRIFT: secret file with matching sha stays OK" {
  printf 'expected\n' > "$TMP_HOME/secret.txt"
  chmod 600 "$TMP_HOME/secret.txt"
  local sha; sha="$(sha256sum "$TMP_HOME/secret.txt" | awk '{print $1}')"
  _state "$TMP_HOME/secret.txt" "$sha"
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[
    {\"label\":\"s\",\"item\":\"S\",\"target\":\"secret.txt\",\"absPath\":\"$TMP_HOME/secret.txt\",\"attachment\":\"\"}
  ],\"envFiles\":[]}"
  run "$SCRIPT_PATH"
  assert_success
  refute_output --partial "DRIFT 1"
}

@test "DRIFT: row stays OK when no state record exists for the path" {
  printf 'anything\n' > "$TMP_HOME/secret.txt"
  chmod 600 "$TMP_HOME/secret.txt"
  # deliberately no state file
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[
    {\"label\":\"s\",\"item\":\"S\",\"target\":\"secret.txt\",\"absPath\":\"$TMP_HOME/secret.txt\",\"attachment\":\"\"}
  ],\"envFiles\":[]}"
  run "$SCRIPT_PATH"
  assert_success
  refute_output --partial "DRIFT 1"
}

@test "DRIFT: WARN takes precedence over content drift" {
  printf 'changed\n' > "$TMP_HOME/secret.txt"
  chmod 644 "$TMP_HOME/secret.txt"
  _state "$TMP_HOME/secret.txt" "0000000000000000000000000000000000000000000000000000000000000000"
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[
    {\"label\":\"s\",\"item\":\"S\",\"target\":\"secret.txt\",\"absPath\":\"$TMP_HOME/secret.txt\",\"attachment\":\"\"}
  ],\"envFiles\":[]}"
  run "$SCRIPT_PATH"
  assert_failure 1
  assert_output --partial "WARN"
  refute_output --partial "DRIFT 1"
}

@test "DRIFT: ssh key DRIFT detected when only the public key drifts" {
  install -m 600 /dev/null "$TMP_HOME/.ssh/id_test"
  printf 'priv\n' > "$TMP_HOME/.ssh/id_test"
  chmod 600 "$TMP_HOME/.ssh/id_test"
  printf 'pub-changed\n' > "$TMP_HOME/.ssh/id_test.pub"
  chmod 644 "$TMP_HOME/.ssh/id_test.pub"
  local pshashes; pshashes="$(sha256sum "$TMP_HOME/.ssh/id_test" | awk '{print $1}')"
  cat > "$TMP_HOME/.config/chezmoi/secret-deploy-state.json" <<JSON
{
  "version": 1,
  "entries": [
    {"category":"sshKey","name":"k","path":"$TMP_HOME/.ssh/id_test","sha256":"$pshashes","mode":"600","deployedAt":"2026-04-26T00:00:00Z"},
    {"category":"sshKey","name":"k.pub","path":"$TMP_HOME/.ssh/id_test.pub","sha256":"deadbeef","mode":"644","deployedAt":"2026-04-26T00:00:00Z"}
  ]
}
JSON
  _skeleton "{\"gpg\":[],\"sshKeys\":[
    {\"label\":\"k\",\"item\":\"K\",\"filename\":\"id_test\",\"privatePath\":\"$TMP_HOME/.ssh/id_test\",\"publicPath\":\"$TMP_HOME/.ssh/id_test.pub\"}
  ],\"sshHosts\":[],\"secretFiles\":[],\"envFiles\":[]}"
  run "$SCRIPT_PATH"
  assert_failure 1
  assert_output --partial "DRIFT"
  assert_output --partial "public key content changed"
}

@test "DRIFT: summary mode includes DRIFT counter" {
  printf 'modified\n' > "$TMP_HOME/secret.txt"
  chmod 600 "$TMP_HOME/secret.txt"
  _state "$TMP_HOME/secret.txt" "0000000000000000000000000000000000000000000000000000000000000000"
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[
    {\"label\":\"s\",\"item\":\"S\",\"target\":\"secret.txt\",\"absPath\":\"$TMP_HOME/secret.txt\",\"attachment\":\"\"}
  ],\"envFiles\":[]}"
  run "$SCRIPT_PATH" --summary
  assert_failure 1
  assert_output --partial "DRIFT 1"
}

@test "DRIFT: JSON mode emits status=DRIFT" {
  printf 'modified\n' > "$TMP_HOME/secret.txt"
  chmod 600 "$TMP_HOME/secret.txt"
  _state "$TMP_HOME/secret.txt" "0000000000000000000000000000000000000000000000000000000000000000"
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[
    {\"label\":\"s\",\"item\":\"S\",\"target\":\"secret.txt\",\"absPath\":\"$TMP_HOME/secret.txt\",\"attachment\":\"\"}
  ],\"envFiles\":[]}"
  run "$SCRIPT_PATH" --json
  assert_failure 1
  assert_output --partial '"status": "DRIFT"'
}

@test "DRIFT: SECRET_DEPLOY_STATE env override is honored" {
  printf 'modified\n' > "$TMP_HOME/secret.txt"
  chmod 600 "$TMP_HOME/secret.txt"
  cat > "$TMP_HOME/alt-state.json" <<JSON
{"version":1,"entries":[{"category":"secretFile","name":"s","path":"$TMP_HOME/secret.txt","sha256":"deadbeef","mode":"600","deployedAt":"2026-04-26T00:00:00Z"}]}
JSON
  _skeleton "{\"gpg\":[],\"sshKeys\":[],\"sshHosts\":[],\"secretFiles\":[
    {\"label\":\"s\",\"item\":\"S\",\"target\":\"secret.txt\",\"absPath\":\"$TMP_HOME/secret.txt\",\"attachment\":\"\"}
  ],\"envFiles\":[]}"
  SECRET_DEPLOY_STATE="$TMP_HOME/alt-state.json" run "$SCRIPT_PATH"
  assert_failure 1
  assert_output --partial "DRIFT"
}
