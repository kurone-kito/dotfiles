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

@test "decides skip-pester for a nested .ps1 file outside the designated directories" {
  mkdir -p "$REPO/docs"
  echo x >"$REPO/docs/example.ps1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "add unrelated nested ps1"

  run bash -c "cd '$REPO' && bash '$SCRIPT' --dry-run"
  assert_success
  assert_output --partial 'would skip: Pester'
}

@test "decides run-pester for a top-level .ps1 file" {
  echo x >"$REPO/top-level.ps1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "add top-level ps1"

  run bash -c "cd '$REPO' && bash '$SCRIPT' --dry-run"
  assert_success
  assert_output --partial 'would run: bats, Pester'
}

@test "decides run-pester for an unstaged PowerShell change" {
  mkdir -p "$REPO/tests/powershell"
  echo x >"$REPO/tests/powershell/foo.Tests.ps1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "add pwsh test"
  echo y >"$REPO/tests/powershell/foo.Tests.ps1"

  run bash -c "cd '$REPO' && bash '$SCRIPT' --dry-run"
  assert_success
  assert_output --partial 'would run: bats, Pester'
}

@test "decides run-pester for a staged-but-uncommitted PowerShell change" {
  mkdir -p "$REPO/tests/powershell"
  echo x >"$REPO/tests/powershell/bar.Tests.ps1"
  git -C "$REPO" add -A

  run bash -c "cd '$REPO' && bash '$SCRIPT' --dry-run"
  assert_success
  assert_output --partial 'would run: bats, Pester'
}

@test "decides run-pester for an untracked PowerShell file" {
  mkdir -p "$REPO/tests/powershell"
  echo x >"$REPO/tests/powershell/untracked.Tests.ps1"

  run bash -c "cd '$REPO' && bash '$SCRIPT' --dry-run"
  assert_success
  assert_output --partial 'would run: bats, Pester'
}

@test "decides run-pester when a PowerShell file is renamed out of a designated directory" {
  # The file must already exist AT the merge-base for this to exercise
  # rename detection at all: adding and renaming it within the same
  # branch, with no trace at the merge-base, is just a plain add
  # relative to origin/master, not a rename.
  mkdir -p "$REPO/tests/powershell" "$REPO/docs"
  echo x >"$REPO/tests/powershell/foo.Tests.ps1"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "add pwsh test"
  git -C "$REPO" branch -f origin/master master

  # This machine's global git config sets `diff.renames = copies`;
  # without `--no-renames` in changed_files(), this move would be
  # reported under its new (non-PowerShell) name only.
  git -C "$REPO" mv tests/powershell/foo.Tests.ps1 docs/renamed.txt
  git -C "$REPO" commit -q -m "move pwsh test out of tests/powershell"

  run bash -c "cd '$REPO' && bash '$SCRIPT' --dry-run"
  assert_success
  assert_output --partial 'would run: bats, Pester'
}

@test "resolves developmentBranch via gh repo view when the config field is absent" {
  # Stub `gh` on PATH so this depends on neither network access nor a
  # real GitHub remote.
  FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$FAKE_BIN"
  cat >"$FAKE_BIN/gh" <<'EOS'
#!/usr/bin/env bash
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
  echo main
  exit 0
fi
exit 1
EOS
  chmod +x "$FAKE_BIN/gh"

  printf '{}\n' >"$REPO/.github/idd/config.json"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "drop developmentBranch field"
  git -C "$REPO" branch origin/main master

  mkdir -p "$REPO/home/dot_config/mise"
  echo x >"$REPO/home/dot_config/mise/config.toml"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "touch mise config"

  # A non-PowerShell change only decides skip-pester if the merge-base
  # against `origin/main` actually resolved -- proving the stubbed
  # `gh repo view` value was used, not merely that the lookup failed
  # safe (which would decide run-pester instead).
  run bash -c "export PATH='$FAKE_BIN:$PATH'; cd '$REPO'; bash '$SCRIPT' --dry-run"
  assert_success
  assert_output --partial 'would skip: Pester'
}

@test "fails safe to run-pester when .github/idd/config.json is malformed" {
  mkdir -p "$REPO/home/dot_config/mise"
  echo x >"$REPO/home/dot_config/mise/config.toml"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "touch mise config"
  # Malformed JSON makes `jq` fail, which must be treated the same as
  # an undeterminable diff -- never silently default to "master" and
  # risk resolving the wrong origin ref.
  printf 'not valid json' >"$REPO/.github/idd/config.json"
  git -C "$REPO" add -A
  git -C "$REPO" commit -q -m "corrupt config.json"

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
