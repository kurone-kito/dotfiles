#!/usr/bin/env bats
# Tests for the git profile generator chezmoi template
# (run_onchange_after_generate-git-profiles.sh.tmpl). Renders the
# real template via chezmoi execute-template (mirrors
# tests/bash/signing-resolve.bats) instead of a hand-copied fixture,
# so SSH-signing profiles get real runtime coverage too — the old
# static fixture only ever exercised the GPG/no-signing shapes and
# had drifted from the template's SSH-signing branch.
# Exercises: directory creation, profile file content (GPG and SSH
# signing), orphan removal, preservation of valid files, and
# idempotency.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  REPO_HOME="$BATS_TEST_DIRNAME/../../home"
  PROFILES_TMPL="$REPO_HOME/run_onchange_after_generate-git-profiles.sh.tmpl"

  # Isolate every test from the real HOME. Set before rendering so
  # chezmoi's .chezmoi.homeDir (baked into SSH signingkey paths at
  # render time) and the rendered script's own runtime ${HOME} agree.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export PROFILES_DIR="$HOME/.config/git/profiles"

  TMP_CFG="$BATS_TEST_TMPDIR/cfg.json"
  RENDERED="$BATS_TEST_TMPDIR/generate-git-profiles.sh"
}

_default_config() {
  cat > "$TMP_CFG" <<'JSON'
{ "data": { "git": { "profiles": {
  "personal": { "name": "Personal User", "email": "personal@example.com" },
  "work": { "name": "Work User", "email": "work@example.com", "signingkey": "ABCD1234ABCD1234" }
} } } }
JSON
}

_render() {
  chezmoi execute-template --file "$PROFILES_TMPL" \
    --config "$TMP_CFG" --config-format json \
    --source "$REPO_HOME" --destination "$HOME" \
    > "$RENDERED"
}

# ---------------------------------------------------------------------------
# Directory creation
# ---------------------------------------------------------------------------

@test "creates profiles directory when absent" {
  _default_config
  _render
  assert_dir_not_exist "$PROFILES_DIR"
  run bash "$RENDERED"
  assert_success
  assert_dir_exists "$PROFILES_DIR"
}

@test "succeeds when profiles directory already exists" {
  _default_config
  _render
  mkdir -p "$PROFILES_DIR"
  run bash "$RENDERED"
  assert_success
}

# ---------------------------------------------------------------------------
# Profile file creation
# ---------------------------------------------------------------------------

@test "creates personal profile with name and email" {
  _default_config
  _render
  run bash "$RENDERED"
  assert_success
  assert_file_exists "$PROFILES_DIR/personal"
  run grep -F 'email = "personal@example.com"' "$PROFILES_DIR/personal"
  assert_success
  run grep -F 'name = "Personal User"'          "$PROFILES_DIR/personal"
  assert_success
}

@test "personal profile has no GPG signing fields" {
  _default_config
  _render
  run bash "$RENDERED"
  assert_success
  run grep -F 'gpgsign' "$PROFILES_DIR/personal"
  assert_failure
}

@test "creates work profile with name, email and GPG fields" {
  _default_config
  _render
  run bash "$RENDERED"
  assert_success
  assert_file_exists "$PROFILES_DIR/work"
  run grep -F 'email = "work@example.com"'    "$PROFILES_DIR/work"
  assert_success
  run grep -F 'name = "Work User"'            "$PROFILES_DIR/work"
  assert_success
  run grep -F 'signingkey = "ABCD1234ABCD1234"' "$PROFILES_DIR/work"
  assert_success
  run grep -F 'gpgsign = true'                "$PROFILES_DIR/work"
  assert_success
}

@test "creates an SSH-signing profile with gpg.format ssh and a commit-ssh alias" {
  cat > "$TMP_CFG" <<'JSON'
{ "data": {
  "git": { "profiles": { "oss": { "name": "OSS User", "email": "oss@example.com" } } },
  "secret": { "ssh": { "keys": {
    "p": { "item": "i", "filename": "id_oss", "signing_profiles": ["oss"] }
  } } }
} }
JSON
  _render
  run bash "$RENDERED"
  assert_success
  assert_file_exists "$PROFILES_DIR/oss"
  run grep -F 'format = ssh'                            "$PROFILES_DIR/oss"
  assert_success
  run grep -F "signingkey = \"$HOME/.ssh/id_oss.pub\""  "$PROFILES_DIR/oss"
  assert_success
  run grep -F 'commit-ssh ='                            "$PROFILES_DIR/oss"
  assert_success
}

# ---------------------------------------------------------------------------
# Orphan removal
# ---------------------------------------------------------------------------

@test "removes orphaned profile files" {
  _default_config
  _render
  mkdir -p "$PROFILES_DIR"
  touch "$PROFILES_DIR/orphan"
  run bash "$RENDERED"
  assert_success
  assert_file_not_exists "$PROFILES_DIR/orphan"
}

@test "does not remove valid profile files" {
  _default_config
  _render
  run bash "$RENDERED"
  assert_success
  assert_file_exists "$PROFILES_DIR/personal"
  assert_file_exists "$PROFILES_DIR/work"
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

@test "is idempotent: running twice produces identical results" {
  _default_config
  _render
  run bash "$RENDERED"
  assert_success
  local content_personal_1
  local content_work_1
  content_personal_1="$(cat "$PROFILES_DIR/personal")"
  content_work_1="$(cat "$PROFILES_DIR/work")"

  run bash "$RENDERED"
  assert_success

  assert_equal "$(cat "$PROFILES_DIR/personal")" "$content_personal_1"
  assert_equal "$(cat "$PROFILES_DIR/work")"     "$content_work_1"
  assert_file_not_exists "$PROFILES_DIR/orphan"
}

@test "is idempotent: no leftover files after running twice with a prior orphan" {
  _default_config
  _render
  mkdir -p "$PROFILES_DIR"
  touch "$PROFILES_DIR/stale"
  bash "$RENDERED"
  run bash "$RENDERED"
  assert_success
  assert_file_not_exists "$PROFILES_DIR/stale"
}
