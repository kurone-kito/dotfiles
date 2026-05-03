#!/usr/bin/env bats
# Tests for the ghq-clone-user standalone script.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_ghq-clone-user"
  _ORIG_PATH="$PATH"
  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BATS_TEST_TMPDIR/ghq-root"
  export GHQ_CLONE_LOG="$BATS_TEST_TMPDIR/ghq-clone.log"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

make_mock() {
  cat > "$BATS_TEST_TMPDIR/bin/$1" << EOF
#!/bin/sh
$2
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

setup_standard_mocks() {
  # ghq root returns our test dir; get logs args and GIT_SSH_COMMAND
  make_mock ghq "
if [ \"\$1\" = 'root' ]; then
  echo '$BATS_TEST_TMPDIR/ghq-root'
elif [ \"\$1\" = 'get' ]; then
  echo \"\$@\" >> '$GHQ_CLONE_LOG'
  echo \"GIT_SSH_COMMAND=\${GIT_SSH_COMMAND:-}\" >> '$BATS_TEST_TMPDIR/ghq-env.log'
fi
"
  # gh repo list returns two repos
  make_mock gh "
if [ \"\$1\" = 'repo' ] && [ \"\$2\" = 'list' ]; then
  printf 'testuser/repo-a\ntestuser/repo-b\n'
fi
"
}

# ── Argument parsing ─────────────────────────────────────────────

@test "prints help with --help" {
  setup_standard_mocks
  run "$SCRIPT" --help
  assert_success
  assert_output --partial "Usage"
}

@test "exits with error when owner is missing" {
  setup_standard_mocks
  run "$SCRIPT"
  assert_failure
  assert_output --partial "owner"
}

@test "exits with error on unknown option" {
  setup_standard_mocks
  run "$SCRIPT" --bogus
  assert_failure
  assert_output --partial "Unknown option"
}

@test "exits with error when --hostname has no value" {
  setup_standard_mocks
  run "$SCRIPT" testuser --hostname
  assert_failure
  assert_output --partial "requires a value"
}

@test "exits with error when --ssh and --https are both given" {
  setup_standard_mocks
  run "$SCRIPT" testuser --ssh --https
  assert_failure
  assert_output --partial "mutually exclusive"
}

@test "exits with error when --limit has no value" {
  setup_standard_mocks
  run "$SCRIPT" testuser --limit
  assert_failure
  assert_output --partial "requires a value"
}

@test "rejects flag as value for --hostname" {
  setup_standard_mocks
  run "$SCRIPT" testuser --hostname --limit
  assert_failure
  assert_output --partial "requires a value"
}

@test "rejects flag as value for --limit" {
  setup_standard_mocks
  run "$SCRIPT" testuser --limit --https
  assert_failure
  assert_output --partial "requires a value"
}

@test "rejects hostname containing path traversal" {
  setup_standard_mocks
  run "$SCRIPT" testuser --hostname "../../etc"
  assert_failure
  assert_output --partial "invalid hostname"
}

@test "rejects hostname containing slashes" {
  setup_standard_mocks
  run "$SCRIPT" testuser --hostname "foo/bar"
  assert_failure
  assert_output --partial "invalid hostname"
}

# ── Tool detection ───────────────────────────────────────────────

@test "exits with error when ghq is not found" {
  make_mock gh "echo ok"
  # Ensure only our mock bin dir + essential coreutils are in PATH
  export PATH="$BATS_TEST_TMPDIR/bin"
  run "$SCRIPT" testuser
  assert_failure
  assert_output --partial "ghq not found"
}

@test "exits with error when gh is not found" {
  make_mock ghq "
if [ \"\$1\" = 'root' ]; then echo '$BATS_TEST_TMPDIR/ghq-root'; fi
"
  export PATH="$BATS_TEST_TMPDIR/bin"
  run "$SCRIPT" testuser
  assert_failure
  assert_output --partial "gh not found"
}

# ── Cloning behaviour ───────────────────────────────────────────

@test "clones repos with SSH by default" {
  setup_standard_mocks
  run "$SCRIPT" testuser
  assert_success
  assert_output --partial "clone: testuser/repo-a"
  assert_output --partial "clone: testuser/repo-b"

  # Verify ghq get was called with -p (SSH)
  assert_file_exists "$GHQ_CLONE_LOG"
  run cat "$GHQ_CLONE_LOG"
  assert_output --partial "get -p github.com/testuser/repo-a"
  assert_output --partial "get -p github.com/testuser/repo-b"
}

@test "clones repos with HTTPS when --https is given" {
  setup_standard_mocks
  run "$SCRIPT" testuser --https
  assert_success

  run cat "$GHQ_CLONE_LOG"
  # No -p flag
  assert_output --partial "get github.com/testuser/repo-a"
  refute_output --partial "get -p"
}

@test "uses custom hostname" {
  # gh mock verifies GH_HOST is set
  make_mock ghq "
if [ \"\$1\" = 'root' ]; then
  echo '$BATS_TEST_TMPDIR/ghq-root'
elif [ \"\$1\" = 'get' ]; then
  echo \"\$@\" >> '$GHQ_CLONE_LOG'
fi
"
  make_mock gh "
if [ \"\$1\" = 'repo' ] && [ \"\$2\" = 'list' ]; then
  if [ \"\$GH_HOST\" = 'github.example.com' ]; then
    printf 'testuser/repo-a\ntestuser/repo-b\n'
  else
    echo 'GH_HOST not set correctly' >&2
    exit 1
  fi
fi
"
  run "$SCRIPT" testuser --hostname github.example.com
  assert_success

  run cat "$GHQ_CLONE_LOG"
  assert_output --partial "get -p github.example.com/testuser/repo-a"
}

@test "passes --limit to gh repo list" {
  make_mock ghq "
if [ \"\$1\" = 'root' ]; then
  echo '$BATS_TEST_TMPDIR/ghq-root'
elif [ \"\$1\" = 'get' ]; then
  echo \"\$@\" >> '$GHQ_CLONE_LOG'
fi
"
  make_mock gh "
if [ \"\$1\" = 'repo' ] && [ \"\$2\" = 'list' ]; then
  echo \"\$@\" >> '$BATS_TEST_TMPDIR/gh-args.log'
  printf 'testuser/repo-a\n'
fi
"
  run "$SCRIPT" testuser --limit 5
  assert_success

  run cat "$BATS_TEST_TMPDIR/gh-args.log"
  assert_output --partial "--limit 5"
}

@test "skips repo with .git file (worktree)" {
  setup_standard_mocks
  # Pre-create a repo dir with .git as a file (worktree style)
  mkdir -p "$BATS_TEST_TMPDIR/ghq-root/github.com/testuser/repo-a"
  echo "gitdir: /somewhere/else" > "$BATS_TEST_TMPDIR/ghq-root/github.com/testuser/repo-a/.git"

  run "$SCRIPT" testuser
  assert_success
  assert_output --partial "skip: testuser/repo-a"
}

@test "skips already-cloned repos" {
  setup_standard_mocks
  # Pre-create a repo dir with .git
  mkdir -p "$BATS_TEST_TMPDIR/ghq-root/github.com/testuser/repo-a/.git"

  run "$SCRIPT" testuser
  assert_success
  assert_output --partial "skip: testuser/repo-a"
  assert_output --partial "clone: testuser/repo-b"

  run cat "$GHQ_CLONE_LOG"
  refute_output --partial "repo-a"
  assert_output --partial "repo-b"
}

@test "removes dir without .git before cloning" {
  setup_standard_mocks
  # Pre-create a repo dir WITHOUT .git (corrupted)
  mkdir -p "$BATS_TEST_TMPDIR/ghq-root/github.com/testuser/repo-a"
  touch "$BATS_TEST_TMPDIR/ghq-root/github.com/testuser/repo-a/stale-file"

  run "$SCRIPT" testuser
  assert_success
  assert_output --partial "clone: testuser/repo-a"

  # Stale dir should have been removed
  assert_file_not_exists "$BATS_TEST_TMPDIR/ghq-root/github.com/testuser/repo-a/stale-file"
}

@test "handles gh returning no repos" {
  make_mock ghq "
if [ \"\$1\" = 'root' ]; then
  echo '$BATS_TEST_TMPDIR/ghq-root'
fi
"
  make_mock gh "true"

  run "$SCRIPT" testuser
  assert_success
  assert_output --partial "Done"
}

@test "exits with error when gh repo list fails" {
  make_mock ghq "
if [ \"\$1\" = 'root' ]; then
  echo '$BATS_TEST_TMPDIR/ghq-root'
fi
"
  make_mock gh "
if [ \"\$1\" = 'repo' ] && [ \"\$2\" = 'list' ]; then
  echo 'authentication required' >&2
  exit 1
fi
"

  run "$SCRIPT" testuser
  assert_failure
  assert_output --partial "failed to list"
}

@test "continues when ghq get fails for one repo" {
  make_mock ghq "
if [ \"\$1\" = 'root' ]; then
  echo '$BATS_TEST_TMPDIR/ghq-root'
elif [ \"\$1\" = 'get' ]; then
  exit 1
fi
"
  make_mock gh "
if [ \"\$1\" = 'repo' ] && [ \"\$2\" = 'list' ]; then
  printf 'testuser/repo-a\ntestuser/repo-b\n'
fi
"

  run "$SCRIPT" testuser
  assert_success
  assert_output --partial "clone: testuser/repo-a"
  assert_output --partial "clone: testuser/repo-b"
}

# ── SSH host key handling ────────────────────────────────────────

@test "sets GIT_SSH_COMMAND with accept-new for SSH clones" {
  setup_standard_mocks
  run "$SCRIPT" testuser
  assert_success

  run cat "$BATS_TEST_TMPDIR/ghq-env.log"
  assert_output --partial "GIT_SSH_COMMAND=ssh -o StrictHostKeyChecking=accept-new"
}

@test "does not set GIT_SSH_COMMAND for HTTPS clones" {
  setup_standard_mocks
  run "$SCRIPT" testuser --https
  assert_success

  # env log should not exist (ghq get mock captures it only when called)
  run cat "$BATS_TEST_TMPDIR/ghq-env.log"
  refute_output --partial "StrictHostKeyChecking"
}

@test "preserves existing GIT_SSH_COMMAND and appends accept-new" {
  setup_standard_mocks
  GIT_SSH_COMMAND="ssh -i ~/.ssh/custom_key" run "$SCRIPT" testuser
  assert_success

  run cat "$BATS_TEST_TMPDIR/ghq-env.log"
  assert_output --partial "GIT_SSH_COMMAND=ssh -i ~/.ssh/custom_key -o StrictHostKeyChecking=accept-new"
}
