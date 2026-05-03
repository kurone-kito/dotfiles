#!/usr/bin/env bats
# Tests for the secret-deploy-manifest.json template rendered by chezmoi
# at apply time and consumed by the secret-status command.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  TEMPLATE_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/chezmoi/private_secret-deploy-manifest.json.tmpl"
  TMP_HOME="$BATS_TEST_TMPDIR/home"
  TMP_SOURCE="$BATS_TEST_TMPDIR/source"
  TMP_CONFIG="$BATS_TEST_TMPDIR/chezmoi.toml"
  mkdir -p "$TMP_HOME" "$TMP_SOURCE"
}

# Render the template using the provided config-format JSON file.
_render() {
  local config_file="$1"
  chezmoi execute-template --file "$TEMPLATE_PATH" \
    --config "$config_file" --config-format json \
    --source "$TMP_SOURCE" --destination "$TMP_HOME"
}

@test "manifest renders valid JSON for empty config" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": {} }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

@test "manifest reports manager and os" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": { "secret": { "manager": "bitwarden" } } }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "
import json,sys
m = json.load(sys.stdin)
assert m['manager'] == 'bitwarden', m['manager']
assert m['version'] == 1
assert 'os' in m
assert 'homeDir' in m
"
}

@test "manifest joins gpg fingerprint from primary signingkey when only one entry" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": {
  "git": { "signingkey": "DEADBEEF1234" },
  "secret": { "gpg": { "personal": { "item": "GPG Personal" } } }
} }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "
import json,sys
m = json.load(sys.stdin)
g = m['categories']['gpg'][0]
assert g['label'] == 'personal', g
assert g['fingerprint'] == 'DEADBEEF1234', g
"
}

@test "manifest does not auto-join primary signingkey when multiple gpg entries" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": {
  "git": { "signingkey": "DEADBEEF1234" },
  "secret": { "gpg": {
    "personal": { "item": "GPG Personal" },
    "work":     { "item": "GPG Work" }
  } }
} }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "
import json,sys
m = json.load(sys.stdin)
for g in m['categories']['gpg']:
  assert g['fingerprint'] == '', g  # ambiguous; do not guess
"
}

@test "manifest uses profile signingkey when label matches profile" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": {
  "git": {
    "signingkey": "DEADBEEF1234",
    "profiles": { "work": { "signingkey": "CAFEBABE9999" } }
  },
  "secret": { "gpg": {
    "personal": { "item": "GPG Personal" },
    "work":     { "item": "GPG Work" }
  } }
} }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "
import json,sys
m = json.load(sys.stdin)
by_label = { g['label']: g for g in m['categories']['gpg'] }
assert by_label['work']['fingerprint'] == 'CAFEBABE9999', by_label
assert by_label['personal']['fingerprint'] == '', by_label
"
}

@test "manifest uses explicit fingerprint override when provided" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": {
  "git": { "signingkey": "DEADBEEF1234" },
  "secret": { "gpg": { "personal": {
    "item": "GPG Personal",
    "fingerprint": "FFFFFFFF0000"
  } } }
} }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "
import json,sys
m = json.load(sys.stdin)
assert m['categories']['gpg'][0]['fingerprint'] == 'FFFFFFFF0000'
"
}

@test "manifest resolves ssh key paths under \$HOME/.ssh" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": { "secret": { "ssh": { "keys": {
  "personal": { "item": "SSH Key", "filename": "id_ed25519_personal" }
} } } } }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "
import json,sys,os
m = json.load(sys.stdin)
k = m['categories']['sshKeys'][0]
home = m['homeDir']
sep = '/' if m['os'] != 'windows' else '\\\\'
assert k['privatePath'] == home + sep + '.ssh' + sep + 'id_ed25519_personal', k
assert k['publicPath'] == k['privatePath'] + '.pub', k
"
}

@test "manifest resolves ssh host identity path" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": { "secret": { "ssh": { "hosts": {
  "github-personal": {
    "hostname": "github.com",
    "user": "git",
    "identity": "id_ed25519_personal",
    "port": 22
  }
} } } } }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "
import json,sys
m = json.load(sys.stdin)
h = m['categories']['sshHosts'][0]
assert h['alias'] == 'github-personal', h
assert h['hostname'] == 'github.com', h
assert h['identity'] == 'id_ed25519_personal', h
assert h['port'] == 22, h
assert h['identityPath'].endswith('id_ed25519_personal'), h
"
}

@test "manifest resolves env file path under ghq root with subpath" {
  # ghq is not on PATH inside the bats sandbox so ghqRoot stays empty;
  # we verify the absPath stays empty (UNKNOWN at status time).
  cat > "$TMP_CONFIG" <<JSON
{ "data": { "env": { "deploy": {
  "myapp": { "repo": "github.com/me/myapp", "filename": ".env",
             "subpath": "config", "item": "MyApp Env" }
} } } }
JSON
  # Build a PATH containing only chezmoi (symlinked) so that ghq is absent.
  local _chezmoi_path
  _chezmoi_path="$(command -v chezmoi)"
  mkdir -p "$BATS_TEST_TMPDIR/chezmoi-only-bin"
  ln -s "$_chezmoi_path" "$BATS_TEST_TMPDIR/chezmoi-only-bin/chezmoi"
  PATH="$BATS_TEST_TMPDIR/chezmoi-only-bin" run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "
import json,sys
m = json.load(sys.stdin)
e = m['categories']['envFiles'][0]
assert e['repo'] == 'github.com/me/myapp', e
assert e['subpath'] == 'config', e
assert e['filename'] == '.env', e
assert e['absPath'] == '', e  # ghqRoot unresolved
"
}

@test "manifest resolves env file path when ghq is available" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/ghq" << 'GHQ'
#!/bin/sh
[ "$1" = "root" ] && echo "/tmp/ghq-root"
GHQ
  chmod +x "$BATS_TEST_TMPDIR/bin/ghq"
  cat > "$TMP_CONFIG" <<JSON
{ "data": { "env": { "deploy": {
  "myapp": { "repo": "github.com/me/myapp", "filename": ".env",
             "item": "MyApp Env" }
} } } }
JSON
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "
import json,sys
m = json.load(sys.stdin)
assert m['ghqRoot'] == '/tmp/ghq-root', m['ghqRoot']
e = m['categories']['envFiles'][0]
assert e['absPath'] == '/tmp/ghq-root/github.com/me/myapp/.env', e
"
}

@test "manifest escapes special characters in labels and items" {
  cat > "$TMP_CONFIG" <<'JSON'
{ "data": { "secret": { "files": {
  "weird": { "item": "Has \"quotes\" and \\backslash", "target": "a/b.txt" }
} } } }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "
import json,sys
m = json.load(sys.stdin)
f = m['categories']['secretFiles'][0]
assert 'quotes' in f['item']
assert '\\\\' in f['item'] or 'backslash' in f['item']
"
}

@test "manifest resolves secret file absolute path under HOME" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": { "secret": { "files": {
  "aws": { "item": "AWS", "target": ".aws/credentials" }
} } } }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  echo "$output" | python3 -c "
import json,sys
m = json.load(sys.stdin)
f = m['categories']['secretFiles'][0]
home = m['homeDir']
assert f['absPath'] == home + '/.aws/credentials', f
"
}
