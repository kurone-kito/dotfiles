#!/usr/bin/env bats
# Tests for the SSH-signing schema rendering of git/config.tmpl and
# the per-profile generator templates. Exercises validate/resolve
# helpers indirectly, the GPG-only backward-compatibility contract,
# and the explicit fail paths for misconfiguration.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_HOME="$BATS_TEST_DIRNAME/../../home"
  CONFIG_TMPL="$REPO_HOME/dot_config/git/config.tmpl"
  PROFILES_TMPL="$REPO_HOME/run_onchange_after_generate-git-profiles.sh.tmpl"
  TMP_HOME="$BATS_TEST_TMPDIR/home"
  TMP_CFG="$BATS_TEST_TMPDIR/cfg.json"
  mkdir -p "$TMP_HOME"
}

_render() {
  local tmpl="$1"
  chezmoi execute-template --file "$tmpl" \
    --config "$TMP_CFG" --config-format json \
    --source "$REPO_HOME" --destination "$TMP_HOME"
}

# ---------------------------------------------------------------------------
# git/config.tmpl
# ---------------------------------------------------------------------------

@test "config: no signing config emits no signing blocks" {
  echo '{ "data": {} }' > "$TMP_CFG"
  run _render "$CONFIG_TMPL"
  assert_success
  refute_output --partial 'signingkey'
  refute_output --partial '[commit]'
  refute_output --partial '[tag]'
}

@test "config: GPG-only renders legacy GPG signing blocks" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": { "git": { "signingkey": "DEADBEEF1234" } } }
JSON
  run _render "$CONFIG_TMPL"
  assert_success
  assert_output --partial 'signingkey = "DEADBEEF1234"'
  assert_output --partial 'gpgsign = if-asked'
  refute_output --partial 'format = ssh'
}

@test "config: SSH-only signing_fallback emits ssh format and absolute path key" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": { "secret": { "ssh": { "keys": {
  "personal": { "item": "i", "filename": "id_ed25519_personal", "signing_fallback": true }
} } } } }
JSON
  run _render "$CONFIG_TMPL"
  assert_success
  assert_output --partial 'format = ssh'
  assert_output --partial '/.ssh/id_ed25519_personal.pub'
  assert_output --partial 'gpgsign = true'
  refute_output --partial 'gpgsign = if-asked'
  assert_output --partial 'commit-ssh ='
  assert_output --partial 'tag-ssh ='
  assert_output --partial 'rebase-ssh ='
}

@test "config: GPG fpr + signing_fallback keeps GPG primary, adds SSH aliases" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": {
  "git": { "signingkey": "FPR" },
  "secret": { "ssh": { "keys": {
    "p": { "item": "i", "filename": "id", "signing_fallback": true }
  } } }
} }
JSON
  run _render "$CONFIG_TMPL"
  assert_success
  assert_output --partial 'signingkey = "FPR"'
  assert_output --partial 'gpgsign = if-asked'
  refute_output --partial 'format = ssh'
  assert_output --partial 'commit-ssh ='
  assert_output --partial "user.signingkey=$HOME/.ssh/id.pub"
}

@test "config: explicit signing_format=ssh forces SSH primary" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": {
  "git": { "signingkey": "FPR", "signing_format": "ssh" },
  "secret": { "ssh": { "keys": {
    "p": { "item": "i", "filename": "id", "signing_fallback": true }
  } } }
} }
JSON
  run _render "$CONFIG_TMPL"
  assert_success
  assert_output --partial 'format = ssh'
  assert_output --partial '/.ssh/id.pub"'
  refute_output --partial 'signingkey = "FPR"'
}

@test "config: no excludesfile key (relative or otherwise) is emitted" {
  echo '{ "data": {} }' > "$TMP_CFG"
  run _render "$CONFIG_TMPL"
  assert_success
  run tr '[:upper:]' '[:lower:]' <<< "$output"
  refute_output --partial 'excludesfile'
}

@test "config: legacy primary_signing field is rejected with rename hint" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": { "secret": { "ssh": { "keys": {
  "p": { "item": "i", "filename": "id", "primary_signing": true }
} } } } }
JSON
  run _render "$CONFIG_TMPL"
  assert_failure
  assert_output --partial 'primary_signing was renamed to signing_fallback'
}

@test "config: multiple signing_fallback keys fail" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": { "secret": { "ssh": { "keys": {
  "a": { "item": "i", "filename": "a", "signing_fallback": true },
  "b": { "item": "i", "filename": "b", "signing_fallback": true }
} } } } }
JSON
  run _render "$CONFIG_TMPL"
  assert_failure
  assert_output --partial 'multiple'
}

@test "config: signing_format=ssh without a fallback key fails" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": { "git": { "signing_format": "ssh" } } }
JSON
  run _render "$CONFIG_TMPL"
  assert_failure
  assert_output --partial 'requires exactly one'
}

@test "config: signing_profiles referencing unknown profile fails" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": { "secret": { "ssh": { "keys": {
  "p": { "item": "i", "filename": "id", "signing_profiles": ["nope"] }
} } } } }
JSON
  run _render "$CONFIG_TMPL"
  assert_failure
  assert_output --partial 'unknown profile'
}

# ---------------------------------------------------------------------------
# generate-git-profiles.sh.tmpl
# ---------------------------------------------------------------------------

@test "profiles: GPG profile + signing_profiles keeps GPG primary, adds SSH aliases" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": {
  "git": { "profiles": { "work": { "name": "W", "email": "w@e", "gitdir": "~/w/", "signingkey": "WORKFPR" } } },
  "secret": { "ssh": { "keys": {
    "p": { "item": "i", "filename": "id_work", "signing_profiles": ["work"] }
  } } }
} }
JSON
  run _render "$PROFILES_TMPL"
  assert_success
  assert_output --partial 'signingkey = "WORKFPR"'
  refute_output --partial 'format = ssh'
  assert_output --partial 'commit-ssh ='
  assert_output --partial '/.ssh/id_work.pub'
}

@test "profiles: SSH-only profile (no GPG signingkey) emits ssh format + aliases" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": {
  "git": { "profiles": { "work": { "name": "W", "email": "w@e", "gitdir": "~/w/" } } },
  "secret": { "ssh": { "keys": {
    "p": { "item": "i", "filename": "id_work", "signing_profiles": ["work"] }
  } } }
} }
JSON
  run _render "$PROFILES_TMPL"
  assert_success
  assert_output --partial 'format = ssh'
  assert_output --partial 'signingkey = "'"$HOME"'/.ssh/id_work.pub"'
  assert_output --partial 'commit-ssh ='
}

@test "profiles: GPG-only profile preserves legacy block (no aliases)" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": { "git": { "profiles": { "work": {
  "name": "W", "email": "w@e", "gitdir": "~/w/", "signingkey": "FPR2"
} } } } }
JSON
  run _render "$PROFILES_TMPL"
  assert_success
  assert_output --partial 'signingkey = "FPR2"'
  refute_output --partial 'format = ssh'
  refute_output --partial 'commit-ssh'
}
