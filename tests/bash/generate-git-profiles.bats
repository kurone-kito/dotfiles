#!/usr/bin/env bats
# Tests for the Bash git profile generator script.
# Exercises: directory creation, profile file content, GPG sections,
# orphan removal, preservation of valid files, and idempotency.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  # Isolate every test from the real HOME by redirecting to a temp dir.
  export HOME="$BATS_TEST_TMPDIR"
  export PROFILES_DIR="$HOME/.config/git/profiles"

  FIXTURE="$BATS_TEST_DIRNAME/fixtures/generate-git-profiles.sh"
}

# ---------------------------------------------------------------------------
# Directory creation
# ---------------------------------------------------------------------------

@test "creates profiles directory when absent" {
  assert_dir_not_exist "$PROFILES_DIR"
  run bash "$FIXTURE"
  assert_success
  assert_dir_exists "$PROFILES_DIR"
}

@test "succeeds when profiles directory already exists" {
  mkdir -p "$PROFILES_DIR"
  run bash "$FIXTURE"
  assert_success
}

# ---------------------------------------------------------------------------
# Profile file creation
# ---------------------------------------------------------------------------

@test "creates personal profile with name and email" {
  run bash "$FIXTURE"
  assert_success
  assert_file_exists "$PROFILES_DIR/personal"
  run grep -F 'email = "personal@example.com"' "$PROFILES_DIR/personal"
  assert_success
  run grep -F 'name = "Personal User"'          "$PROFILES_DIR/personal"
  assert_success
}

@test "personal profile has no GPG signing fields" {
  run bash "$FIXTURE"
  assert_success
  run grep -F 'gpgsign' "$PROFILES_DIR/personal"
  assert_failure
}

@test "creates work profile with name, email and GPG fields" {
  run bash "$FIXTURE"
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

# ---------------------------------------------------------------------------
# Orphan removal
# ---------------------------------------------------------------------------

@test "removes orphaned profile files" {
  mkdir -p "$PROFILES_DIR"
  touch "$PROFILES_DIR/orphan"
  run bash "$FIXTURE"
  assert_success
  assert_file_not_exists "$PROFILES_DIR/orphan"
}

@test "does not remove valid profile files" {
  run bash "$FIXTURE"
  assert_success
  assert_file_exists "$PROFILES_DIR/personal"
  assert_file_exists "$PROFILES_DIR/work"
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

@test "is idempotent: running twice produces identical results" {
  run bash "$FIXTURE"
  assert_success
  local content_personal_1
  local content_work_1
  content_personal_1="$(cat "$PROFILES_DIR/personal")"
  content_work_1="$(cat "$PROFILES_DIR/work")"

  run bash "$FIXTURE"
  assert_success

  assert_equal "$(cat "$PROFILES_DIR/personal")" "$content_personal_1"
  assert_equal "$(cat "$PROFILES_DIR/work")"     "$content_work_1"
  assert_file_not_exists "$PROFILES_DIR/orphan"
}

@test "is idempotent: no leftover files after running twice with a prior orphan" {
  mkdir -p "$PROFILES_DIR"
  touch "$PROFILES_DIR/stale"
  bash "$FIXTURE"
  run bash "$FIXTURE"
  assert_success
  assert_file_not_exists "$PROFILES_DIR/stale"
}
