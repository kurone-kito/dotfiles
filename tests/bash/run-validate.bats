#!/usr/bin/env bats
# Tests for scripts/run-validate.sh's own skip/run decision logic
# (never for the real bats/Pester suites it delegates to -- that would
# make this file itself as slow as the thing it exists to avoid). Each
# test builds an isolated fixture git repo with its own `origin/master`
# branch (a plain local branch named literally `origin/master`, not a
# real remote) and exercises `--dry-run`, which computes the real
# decision but never invokes either suite.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  SCRIPT="$BATS_TEST_DIRNAME/../../scripts/run-validate.sh"
  REPO="$BATS_TEST_TMPDIR/repo"

  git init -q -b master "$REPO"
  git -C "$REPO" config user.email 'test@example.com'
  git -C "$REPO" config user.name 'test'
  git -C "$REPO" config commit.gpgsign false
  mkdir -p "$REPO/.github/idd"
  printf '{"developmentBranch":"master"}\n' >"$REPO/.github/idd/config.json"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m base
  # No real remote is configured; a plain local branch literally named
  # `origin/master` stands in for the fetched remote-tracking ref the
  # script resolves via `git merge-base HEAD "origin/$dev_branch"`.
  git -C "$REPO" branch origin/master master
}

@test "decides skip-pester when only a non-PowerShell path changed" {
  mkdir -p "$REPO/home/dot_config/mise"
  echo x >"$REPO/home/dot_config/mise/config.toml"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "touch mise config"

  run bash -c "cd '$REPO' && bash '$SCRIPT' --dry-run"
  assert_success
  assert_output --partial 'would skip: Pester'
}

@test "decides run-pester when a tests/powershell path changed" {
  mkdir -p "$REPO/tests/powershell"
  echo x >"$REPO/tests/powershell/foo.Tests.ps1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "add pwsh test"

  run bash -c "cd '$REPO' && bash '$SCRIPT' --dry-run"
  assert_success
  assert_output --partial 'would run: bats, Pester'
}

@test "decides run-pester when a home/dot_config/powershell path changed" {
  mkdir -p "$REPO/home/dot_config/powershell/conf.d"
  echo x >"$REPO/home/dot_config/powershell/conf.d/99-foo.ps1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "add conf.d script"

  run bash -c "cd '$REPO' && bash '$SCRIPT' --dry-run"
  assert_success
  assert_output --partial 'would run: bats, Pester'
}

@test "fails safe to run-pester when the diff cannot be determined" {
  UNDETERMINABLE="$BATS_TEST_TMPDIR/repo-no-origin"
  git init -q -b master "$UNDETERMINABLE"
  git -C "$UNDETERMINABLE" config user.email 'test@example.com'
  git -C "$UNDETERMINABLE" config user.name 'test'
  git -C "$UNDETERMINABLE" config commit.gpgsign false
  echo x >"$UNDETERMINABLE/file.txt"
  git -C "$UNDETERMINABLE" add -A
  git -C "$UNDETERMINABLE" commit -q -m base
  # Deliberately no `origin/master` ref of any kind in this repo.

  run bash -c "cd '$UNDETERMINABLE' && bash '$SCRIPT' --dry-run"
  assert_success
  assert_output --partial 'would run: bats, Pester'
}
