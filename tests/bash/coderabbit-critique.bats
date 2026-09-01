#!/usr/bin/env bats
#
# Tests for the coderabbit-critique standalone helper: a read-only C1
# critiqueLoop.delegate findings adapter wrapping CodeRabbit CLI.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_coderabbit-critique"
  _ORIG_PATH="$PATH"
  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export CODERABBIT_CRITIQUE_LOG="$BATS_TEST_TMPDIR/coderabbit-critique.log"
}

teardown() {
  export PATH="$_ORIG_PATH"
  unset CODERABBIT_CRITIQUE_LOG CODERABBIT_CRITIQUE_TIMEOUT CODERABBIT_CRITIQUE_BASE
}

make_mock() {
  cat > "$BATS_TEST_TMPDIR/bin/$1" << EOF
#!/bin/sh
$2
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

make_git_call_recorder() {
  make_mock git '
printf "git:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
exit 0
'
}

assert_no_git_calls() {
  if [ -f "$CODERABBIT_CRITIQUE_LOG" ]; then
    run grep -c '^git:' "$CODERABBIT_CRITIQUE_LOG"
    assert_output "0"
  fi
}

# The script probes `timeout`/`gtimeout --help` for --kill-after support
# before selecting either as TIMEOUT_CMD (same probe-before-trust pattern
# as ~/.gnupg/pinentry-auto's `timeout_cmd_is_compatible`). A GNU/uutils
# mock must answer that probe itself, on top of its normal behavior, or
# every test below would silently fail closed on the "no compatible
# timeout" path instead of exercising the path it means to test.
make_mock_timeout() {
  cat > "$BATS_TEST_TMPDIR/bin/$1" << EOF
#!/bin/sh
if [ "\$1" = "--help" ]; then
  printf -- '--kill-after\n'
  exit 0
fi
$2
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

make_default_mocks() {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
if [ "$1" = "review" ]; then
  printf "review:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
  echo "{\"type\":\"finding\",\"message\":\"example issue\"}"
  exit 0
fi
exit 1
'
  # Bypass git-based base-branch auto-detection in tests that are not
  # about that feature -- it is covered separately below.
  export CODERABBIT_CRITIQUE_BASE=master
}

# A passthrough logging shim (not a stub): the script's own base-branch
# auto-detection legitimately needs a real, working git to resolve against
# the fixture repo set up by setup_git_repo_with_base below, so this must
# forward to the real binary rather than fake one like make_git_call_recorder
# does. Create only after fixture setup so it logs solely the SCRIPT's own
# git calls, not the fixture's own init/commit/push/remote-set-head calls.
make_git_passthrough_logger() {
  real_git="$(command -v git)"
  cat > "$BATS_TEST_TMPDIR/bin/git" << EOF
#!/bin/sh
printf "gitcall:%s\n" "\$1" >> "$CODERABBIT_CRITIQUE_LOG"
exec "$real_git" "\$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/git"
}

assert_only_readonly_git_subcommands_and_at_least_one() {
  run grep -c '^gitcall:' "$CODERABBIT_CRITIQUE_LOG"
  refute_output "0"
  # Isolate gitcall: lines first -- otherwise -v's inversion would also
  # match unrelated log lines (e.g. this file's own "review:..." entries),
  # which never start with "gitcall:" and would falsely fail this check.
  run sh -c "grep '^gitcall:' \"$CODERABBIT_CRITIQUE_LOG\" | grep -vE '^gitcall:(symbolic-ref|rev-parse)\$'"
  assert_failure
}

setup_git_repo_with_base() {
  # $1: "symref" (origin/HEAD symref present, on master),
  #     "main-only" (no symref, only origin/main resolvable),
  #     "master-only" (no symref, only origin/master resolvable),
  #     "both" (no symref, both origin/main and origin/master resolvable),
  #     "none" (no origin remote at all)
  mode="$1"
  bare="$BATS_TEST_TMPDIR/remote.git"
  work="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$bare"
  git init -q "$work"
  git -C "$work" config user.email test@example.com
  git -C "$work" config user.name test
  git -C "$work" config commit.gpgsign false
  branch=master
  if [ "$mode" = "main-only" ]; then branch=main; fi
  git -C "$work" checkout -q -b "$branch"
  git -C "$work" commit -q --allow-empty -m init

  if [ "$mode" != "none" ]; then
    git -C "$work" remote add origin "$bare"
    git -C "$work" push -q origin "$branch"
    if [ "$mode" = "symref" ]; then
      git -C "$work" remote set-head origin "$branch"
    fi
    if [ "$mode" = "both" ]; then
      git -C "$work" checkout -q -b main
      git -C "$work" push -q origin main
    fi
  fi
  printf '%s' "$work"
}

@test "fails when coderabbit is not in PATH" {
  make_git_call_recorder

  run "$SCRIPT"

  assert_failure
  assert_output --partial "coderabbit not found in PATH"
  assert_no_git_calls
}

@test "fails closed when no compatible timeout/gtimeout is found" {
  make_mock coderabbit 'exit 1'

  # Scope PATH to only the mock bin dir (no real system timeout) for the
  # script invocation itself, mirroring pinentry-auto.bats's technique --
  # export'ing this into the whole test shell would also starve bats' own
  # `run` machinery.
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/bin" "$SCRIPT"

  assert_failure
  assert_stderr --partial "no timeout/gtimeout"
}

@test "fails closed when timeout exists but lacks --kill-after (BusyBox-style)" {
  make_mock coderabbit 'exit 1'
  make_mock timeout '
if [ "$1" = "--help" ]; then
  echo "Usage: timeout DURATION COMMAND"
  exit 0
fi
shift 1; exec "$@"
'

  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/bin" "$SCRIPT"

  assert_failure
  assert_stderr --partial "no timeout/gtimeout"
}

@test "resolves to gtimeout when timeout is absent" {
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
exit 1
'
  make_mock_timeout gtimeout 'shift 3; exec "$@"'

  # Scope PATH so the real system timeout cannot mask the gtimeout-only
  # branch; the mock gtimeout remains available.
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/bin" CODERABBIT_CRITIQUE_BASE=master "$SCRIPT"

  refute_output --partial "no timeout/gtimeout"
}

@test "fails closed when jq is not found" {
  make_mock coderabbit 'exit 1'
  make_mock_timeout timeout 'shift 3; exec "$@"'

  # Scope PATH to only the mock bin dir (mocked coderabbit/timeout, no
  # real jq) -- the jq preflight check runs before auth_status or review,
  # so nothing past it (mktemp, cat, coderabbit auth/review) is ever
  # reached in this test.
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/bin" "$SCRIPT"

  assert_failure
  assert_stderr --partial "jq not found"
}

@test "fails without calling review when auth status reports signed out" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  printf "auth:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
  echo "Status       : signed out"
  exit 0
fi
printf "review:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
exit 0
'

  run "$SCRIPT"

  assert_failure
  assert_output --partial "not authenticated"
  run grep -c '^review:' "$CODERABBIT_CRITIQUE_LOG"
  assert_output "0"
  assert_no_git_calls
}

@test "passes through a clean structured-findings response" {
  make_default_mocks

  run "$SCRIPT"

  assert_success
  assert_output --partial '"type":"finding"'
  assert_no_git_calls
}

@test "fails closed when mktemp fails" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
exit 1
'
  # A failing (not merely absent) mktemp mirrors a real-world failure mode
  # -- e.g. a full or unwritable TMPDIR -- distinct from the grep-absent
  # test above. The broken mock lives in its OWN directory, never added
  # to this test's own exported PATH, and is prepended only for the
  # script's scoped subprocess below: dropping it into the shared mock
  # bin dir (already on this whole test process's PATH via setup())
  # would also break bats-core's own `run --separate-stderr` machinery,
  # which needs a working mktemp of its own.
  broken_mktemp_dir="$BATS_TEST_TMPDIR/broken-mktemp-bin"
  mkdir -p "$broken_mktemp_dir"
  cat > "$broken_mktemp_dir/mktemp" << 'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$broken_mktemp_dir/mktemp"

  run --separate-stderr env PATH="$broken_mktemp_dir:$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" CODERABBIT_CRITIQUE_BASE=master "$SCRIPT"

  assert_failure
  assert_stderr --partial "mktemp failed"
  assert_no_git_calls
}

@test "keeps stderr out of a successful findings response" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
if [ "$1" = "review" ]; then
  echo "{\"type\":\"finding\",\"message\":\"stdout text\"}"
  echo "diagnostic noise on stderr" >&2
  exit 0
fi
exit 1
'
  export CODERABBIT_CRITIQUE_BASE=master

  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output --partial "stdout text"
  refute_output --partial "diagnostic noise on stderr"
  # Diagnostics are kept out of findings, not silently dropped -- they
  # still reach the delegate's own stderr.
  assert_stderr --partial "diagnostic noise on stderr"
  assert_no_git_calls
}

@test "rejects an action_required response" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
if [ "$1" = "review" ]; then
  echo "{\"type\":\"action_required\",\"phase\":\"billing\"}"
  exit 0
fi
exit 1
'
  export CODERABBIT_CRITIQUE_BASE=master

  run "$SCRIPT"

  assert_failure
  assert_output --partial "requires operator action"
  assert_no_git_calls
}

@test "rejects a pretty-printed action_required response with whitespace around the marker" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
if [ "$1" = "review" ]; then
  printf "{\n  \"type\" : \"action_required\",\n  \"phase\": \"billing\"\n}\n"
  exit 0
fi
exit 1
'
  export CODERABBIT_CRITIQUE_BASE=master

  run "$SCRIPT"

  assert_failure
  assert_output --partial "requires operator action"
  assert_no_git_calls
}

@test "rejects an action_required response arriving only on stderr" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
if [ "$1" = "review" ]; then
  echo "{\"type\":\"action_required\",\"phase\":\"billing\"}" >&2
  exit 0
fi
exit 1
'
  export CODERABBIT_CRITIQUE_BASE=master

  run "$SCRIPT"

  assert_failure
  assert_output --partial "requires operator action"
  assert_no_git_calls
}

@test "does not trip on an unescaped nested action_required type field inside a finding" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
if [ "$1" = "review" ]; then
  echo "{\"type\":\"finding\",\"message\":\"example\",\"example\":{\"type\":\"action_required\",\"phase\":\"billing\"}}"
  exit 0
fi
exit 1
'
  export CODERABBIT_CRITIQUE_BASE=master

  run "$SCRIPT"

  assert_success
  assert_output --partial '"type":"finding"'
  assert_no_git_calls
}

@test "does not trip when the top-level key differs from \"type\" only by case" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
if [ "$1" = "review" ]; then
  echo "{\"Type\":\"action_required\",\"phase\":\"billing\"}"
  exit 0
fi
exit 1
'
  export CODERABBIT_CRITIQUE_BASE=master

  run "$SCRIPT"

  assert_success
  assert_no_git_calls
}

@test "fails when review exits non-zero" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
if [ "$1" = "review" ]; then
  echo "boom" >&2
  exit 1
fi
exit 1
'
  export CODERABBIT_CRITIQUE_BASE=master

  run "$SCRIPT"

  assert_failure
  assert_output --partial "coderabbit review failed"
  assert_no_git_calls
}

@test "fails when review times out" {
  make_git_call_recorder
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
if [ "$1" = "review" ]; then
  sleep 5
  exit 0
fi
exit 1
'
  export CODERABBIT_CRITIQUE_TIMEOUT=1
  export CODERABBIT_CRITIQUE_BASE=master

  # Use the real system timeout here (not a mock) so the timeout/kill
  # behavior itself is genuinely exercised, not simulated.
  run "$SCRIPT"

  assert_failure
  assert_output --partial "coderabbit review failed"
  assert_no_git_calls
}

@test "uses CODERABBIT_CRITIQUE_BASE for the review base branch, skipping auto-detection" {
  make_default_mocks
  export CODERABBIT_CRITIQUE_BASE=develop

  run "$SCRIPT"

  assert_success
  run grep -c -- "--base develop" "$CODERABBIT_CRITIQUE_LOG"
  assert_output "1"
}

@test "auto-detects the base branch from origin/HEAD when set" {
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
if [ "$1" = "review" ]; then
  printf "review:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
  echo "{\"type\":\"finding\"}"
  exit 0
fi
exit 1
'
  work="$(setup_git_repo_with_base symref)"
  make_git_passthrough_logger

  run --separate-stderr sh -c 'cd "$1" && shift && exec "$@"' -- "$work" "$SCRIPT"

  assert_success
  run grep -c -- "--base master" "$CODERABBIT_CRITIQUE_LOG"
  assert_output "1"
  assert_only_readonly_git_subcommands_and_at_least_one
}

@test "falls back to origin/main when no origin/HEAD symref is set" {
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "Account      : test-user"
  exit 0
fi
if [ "$1" = "review" ]; then
  printf "review:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
  echo "{\"type\":\"finding\"}"
  exit 0
fi
exit 1
'
  work="$(setup_git_repo_with_base main-only)"
  make_git_passthrough_logger

  run --separate-stderr sh -c 'cd "$1" && shift && exec "$@"' -- "$work" "$SCRIPT"

  assert_success
  run grep -c -- "--base main" "$CODERABBIT_CRITIQUE_LOG"
  assert_output "1"
  assert_only_readonly_git_subcommands_and_at_least_one
}

@test "fails closed when both origin/main and origin/master exist without a symref" {
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit 'exit 1'
  work="$(setup_git_repo_with_base both)"
  make_git_passthrough_logger

  run --separate-stderr sh -c 'cd "$1" && shift && exec "$@"' -- "$work" "$SCRIPT"

  assert_failure
  assert_stderr --partial "could not determine the default base branch"
}

@test "fails closed when the base branch cannot be determined" {
  make_mock_timeout timeout 'shift 3; exec "$@"'
  make_mock coderabbit 'exit 1'
  work="$(setup_git_repo_with_base none)"
  make_git_passthrough_logger

  run --separate-stderr sh -c 'cd "$1" && shift && exec "$@"' -- "$work" "$SCRIPT"

  assert_failure
  assert_stderr --partial "could not determine the default base branch"
  assert_only_readonly_git_subcommands_and_at_least_one
}
