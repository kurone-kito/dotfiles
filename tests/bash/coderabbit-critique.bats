#!/usr/bin/env bats
#
# Tests for the coderabbit-critique standalone helper: a read-only C1
# critiqueLoop.delegate findings adapter wrapping CodeRabbit CLI.

bats_require_minimum_version 1.5.0

# Presence is ${name+x}, not a non-empty test: a set-but-empty value must
# be restored as empty, and an absent value must stay absent. Separate
# variables, not an associative array, so this still runs on bash 3.2.
save_critique_policy_env() {
  _policy_deep_set=0
  _policy_deep_val=
  _policy_base_set=0
  _policy_base_val=
  _policy_timeout_set=0
  _policy_timeout_val=
  if [ "${CODERABBIT_CRITIQUE_DEEP+x}" = x ]; then
    _policy_deep_set=1
    _policy_deep_val=$CODERABBIT_CRITIQUE_DEEP
  fi
  if [ "${CODERABBIT_CRITIQUE_BASE+x}" = x ]; then
    _policy_base_set=1
    _policy_base_val=$CODERABBIT_CRITIQUE_BASE
  fi
  if [ "${CODERABBIT_CRITIQUE_TIMEOUT+x}" = x ]; then
    _policy_timeout_set=1
    _policy_timeout_val=$CODERABBIT_CRITIQUE_TIMEOUT
  fi
  unset CODERABBIT_CRITIQUE_DEEP CODERABBIT_CRITIQUE_BASE CODERABBIT_CRITIQUE_TIMEOUT
}

restore_critique_policy_env() {
  if [ "${_policy_deep_set:-0}" = 1 ]; then
    export CODERABBIT_CRITIQUE_DEEP="$_policy_deep_val"
  else
    unset CODERABBIT_CRITIQUE_DEEP
  fi
  if [ "${_policy_base_set:-0}" = 1 ]; then
    export CODERABBIT_CRITIQUE_BASE="$_policy_base_val"
  else
    unset CODERABBIT_CRITIQUE_BASE
  fi
  if [ "${_policy_timeout_set:-0}" = 1 ]; then
    export CODERABBIT_CRITIQUE_TIMEOUT="$_policy_timeout_val"
  else
    unset CODERABBIT_CRITIQUE_TIMEOUT
  fi
}

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT="$BATS_TEST_DIRNAME/../../home/dot_local/bin/executable_coderabbit-critique"
  _ORIG_PATH="$PATH"
  # Resolve host tools before PATH is narrowed to /usr/bin:/bin. A Homebrew
  # gtimeout lives outside that prefix and would otherwise be invisible.
  _HOST_TIMEOUT="$(command -v timeout 2>/dev/null || true)"
  _HOST_GTIMEOUT="$(command -v gtimeout 2>/dev/null || true)"
  _HOST_SETSID="$(command -v setsid 2>/dev/null || true)"
  save_critique_policy_env
  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  FALLBACK_LOG_FILE="$XDG_STATE_HOME/idd-critique/fallbacks.jsonl"
  export CODERABBIT_CRITIQUE_LOG="$BATS_TEST_TMPDIR/coderabbit-critique.log"
  _TRACKED_WRAPPER_PIDS=
}

teardown() {
  export PATH="$_ORIG_PATH"
  # Before anything else can fail: a test that stopped at an assertion while its
  # wrapper was still running must not leave it, or its mock review, behind.
  stop_tracked_wrappers
  # A test that models an inherited runner replaces setup()'s snapshot. Put the
  # real one back first, so a test that fails part way still restores the
  # values from before it ran, not the ones it injected.
  if [ "${_outer_snapshot_stashed:-0}" = 1 ]; then
    reinstate_critique_policy_snapshot
  fi
  restore_critique_policy_env
  unset XDG_STATE_HOME CODERABBIT_CRITIQUE_LOG
}

# Polls "$@" every 0.1 s until it succeeds or a wall-clock deadline passes, so
# a slow host gets the full time instead of a fixed number of sleeps. SECONDS
# has whole-second resolution, so the extra second guarantees that at least
# the requested time really elapses, and one last try after the deadline keeps
# a condition that turned true during the final sleep from being missed. It
# prints nothing; wait_until adds the failure message.
poll_until() {
  poll_seconds="$1"
  shift
  poll_end=$((SECONDS + poll_seconds + 1))
  while [ "$SECONDS" -lt "$poll_end" ]; do
    if "$@"; then
      return 0
    fi
    sleep 0.1
  done
  "$@"
}

# Like poll_until, but fails the test with a message that names what was being
# awaited, so a timeout reads as "waiting for X" instead of a bare assertion.
wait_until() {
  wait_seconds="$1"
  wait_what="$2"
  shift 2
  poll_until "$wait_seconds" "$@" ||
    fail "timed out after ${wait_seconds}s waiting for ${wait_what}"
}

# wait_for_file <path> <seconds> <what>: waits for a non-empty file.
wait_for_file() {
  wait_until "$2" "$3" test -s "$1"
}

# True once the process has exited, or is only a zombie awaiting its parent.
process_is_gone() {
  if ! kill -0 "$1" 2>/dev/null; then
    return 0
  fi
  gone_state="$(ps -o stat= -p "$1" 2>/dev/null | tr -d '[:space:]')"
  case "$gone_state" in
    '' | Z*) return 0 ;;
  esac
  return 1
}

all_processes_gone() {
  for gone_pid in "$@"; do
    process_is_gone "$gone_pid" || return 1
  done
  return 0
}

# True once the supervisor's first TERM handler has written its deadline marker.
deadline_marker_written() {
  for marker_file in "$BATS_TEST_TMPDIR"/coderabbit-critique-deadline.*; do
    if [ -s "$marker_file" ]; then
      return 0
    fi
  done
  return 1
}

# Prints the PID given and every descendant of it from a single process-table
# snapshot, so children that an earlier kill orphaned are still listed.
process_tree() {
  ps -A -o pid= -o ppid= | awk -v root="$1" '
    { parent[$1] = $2; pids[NR] = $1 }
    END {
      print root
      changed = 1
      while (changed) {
        changed = 0
        for (i = 1; i <= NR; i++) {
          p = pids[i]
          if (p != root && !(p in seen) && (parent[p] == root || parent[p] in seen)) {
            seen[p] = 1
            print p
            changed = 1
          }
        }
      }
    }'
}

# Runs "$@" as a background job with its output in the two given files, records
# its PID in script_pid, and tracks it so teardown can stop it if the test
# returns early. FD 3 is closed for the job: a wrapper left alive by a
# regression would otherwise hold it and stall Bats until that process exits.
start_wrapper_job() {
  job_stdout="$1"
  job_stderr="$2"
  shift 2
  "$@" >"$job_stdout" 2>"$job_stderr" 3>&- &
  script_pid=$!
  _TRACKED_WRAPPER_PIDS="$_TRACKED_WRAPPER_PIDS $script_pid"
}

# Stops every wrapper started through start_wrapper_job, together with its
# whole process tree (the timeout job, the supervisor, the mock review and its
# sleeper), and reaps it. It walks parent links rather than a process group
# because a background job in the non-interactive Bats shell shares Bats' own
# group, so a group kill would hit the runner itself. The tree is captured
# before anything is signalled, since killing the wrapper first would orphan its
# descendants out of reach; a child forked after that snapshot is not reached,
# which is acceptable for the short-lived helpers the wrapper starts while it
# shuts down. Safe under `set -e`: nothing here can fail the test.
stop_tracked_wrappers() {
  for tracked_pid in $_TRACKED_WRAPPER_PIDS; do
    # Already gone and reaped, usually by the test's own `wait`: nothing is left
    # to walk, and a stale PID must never be signalled. A zombie still passes
    # `kill -0` and takes the normal path: its children were reparented when it
    # exited, so the walk finds only the zombie and the `wait` below reaps it.
    if ! kill -0 "$tracked_pid" 2>/dev/null; then
      wait "$tracked_pid" 2>/dev/null || true
      continue
    fi
    tracked_tree="$(process_tree "$tracked_pid" 2>/dev/null)" || tracked_tree=
    for member in $tracked_tree; do
      process_is_gone "$member" || kill -TERM "$member" 2>/dev/null || true
    done
    # shellcheck disable=SC2086 # word splitting of the PID list is intended
    poll_until 5 all_processes_gone $tracked_tree || true
    for member in $tracked_tree; do
      process_is_gone "$member" || kill -KILL "$member" 2>/dev/null || true
    done
    # SIGKILL is delivered asynchronously, so confirm the members are really
    # gone before returning instead of leaving one still exiting. Reap the
    # wrapper only once it is gone too: `wait` would block on a process that
    # survived, and teardown must never hang.
    # shellcheck disable=SC2086 # word splitting of the PID list is intended
    poll_until 5 all_processes_gone $tracked_tree || true
    if process_is_gone "$tracked_pid"; then
      wait "$tracked_pid" 2>/dev/null || true
    fi
  done
  _TRACKED_WRAPPER_PIDS=
  return 0
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

assert_no_command_calls() {
  if [ -f "$CODERABBIT_CRITIQUE_LOG" ]; then
    run grep -c . "$CODERABBIT_CRITIQUE_LOG"
    assert_output "0"
  fi
}

assert_fallback_reason() {
  expected_reason="$1"
  assert [ -f "$FALLBACK_LOG_FILE" ]
  run jq -e -s --arg expected "$expected_reason" \
    'length == 1 and (.[0] | type == "object" and has("timestamp") and (.timestamp | type == "string") and (.timestamp | length > 0) and .reason == $expected)' \
    "$FALLBACK_LOG_FILE"
  assert_success
}

link_system_command() {
  command_path="$(command -v "$1")"
  ln -sf "$command_path" "$BATS_TEST_TMPDIR/bin/$1"
}

# Same --help probe as the wrapper. An incompatible timeout earlier on
# PATH must not hide a compatible gtimeout, including one outside
# /usr/bin:/bin.
host_timer_is_compatible() {
  help_output=$("$1" --help 2>&1) || true
  case "$help_output" in
    *--kill-after*) ;;
    *) return 1 ;;
  esac
  case "$help_output" in
    *--preserve-status*) return 0 ;;
    *) return 1 ;;
  esac
}

compatible_host_timer() {
  if [ -n "${_HOST_TIMEOUT:-}" ] && host_timer_is_compatible "$_HOST_TIMEOUT"; then
    printf '%s\n' "$_HOST_TIMEOUT"
    return 0
  fi
  if [ -n "${_HOST_GTIMEOUT:-}" ] && host_timer_is_compatible "$_HOST_GTIMEOUT"; then
    printf '%s\n' "$_HOST_GTIMEOUT"
    return 0
  fi
  return 1
}

# The fixture PATH starts at the mock bin, then /usr/bin:/bin. Put a
# compatible host timer there as `timeout` so Homebrew gtimeout remains
# visible to tests that invoke the real timer.
require_compatible_host_timer() {
  timer="$(compatible_host_timer)" || return 1
  ln -sf "$timer" "$BATS_TEST_TMPDIR/bin/timeout"
}

# The script probes `timeout`/`gtimeout --help` for --kill-after and
# --preserve-status support before selecting either as TIMEOUT_CMD (same
# probe-before-trust pattern as ~/.gnupg/pinentry-auto's
# `timeout_cmd_is_compatible`). A GNU/uutils mock must answer that probe
# itself, on top of its normal behavior, or every test below would silently
# fail closed on the "no compatible timeout" path instead of exercising the
# path it means to test.
#
# Real GNU timeout also puts itself in its own process group before it
# launches the command. Without `setsid` the wrapper relies on exactly that
# boundary and refuses to run when the group is shared with its caller, so a
# mock that skips it fails every launching test on a host without `setsid`
# (macOS). Emit a prelude that re-executes the mock once as a group leader,
# keeping the same PID. `setpgid` fails harmlessly when the mock already
# leads a group. A host with neither setsid nor perl has no way to give the
# mock that group, so those tests skip there rather than fail.
skip_without_process_group_source() {
  if ! command -v setsid >/dev/null 2>&1 && ! command -v perl >/dev/null 2>&1; then
    skip "requires setsid or perl to give the timeout mock its own process group"
  fi
}

timeout_mock_group_prelude() {
  cat << 'EOF'
if [ -z "$CODERABBIT_MOCK_TIMEOUT_GROUPED" ] && command -v perl >/dev/null 2>&1; then
  CODERABBIT_MOCK_TIMEOUT_GROUPED=1 exec perl -MPOSIX -e 'POSIX::setpgid(0, 0); exec @ARGV or die "exec: $!"' "$0" "$@"
fi
EOF
}

make_mock_timeout() {
  skip_without_process_group_source
  {
    cat << 'EOF'
#!/bin/sh
if [ "$1" = "--help" ]; then
  printf -- '--kill-after --preserve-status\n'
  exit 0
fi
EOF
    timeout_mock_group_prelude
    printf '%s\n' "$2"
  } > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

# Pass "survive" as the second argument for a mock that, like real timeout,
# catches TERM and keeps waiting for its child instead of dying with it.
make_mock_timeout_with_kill() {
  skip_without_process_group_source
  {
    cat << 'EOF'
#!/bin/sh
if [ "$1" = "--help" ]; then
  printf -- '--kill-after --preserve-status\n'
  exit 0
fi
EOF
    timeout_mock_group_prelude
    cat << 'EOF'
if [ "$1" != "--preserve-status" ] || [ "$2" != "--kill-after" ]; then
  exit 2
fi
kill_after=$3
duration=$4
shift 4

EOF
    printf 'survive=%s\n' "${2:-}"
    cat << 'EOF'
if [ "$survive" = survive ]; then
  trap ':' TERM
fi
"$@" &
child=$!
# Real timeout keeps its timer inside its own process (an alarm), never as a
# helper in the group it manages. Start the watcher in a group of its own so
# the wrapper's members sweep of the timeout-created group cannot kill it.
watcher_script='
sleep "$1"
if kill -0 "$2" 2>/dev/null; then
  kill -TERM "$2" 2>/dev/null || true
  sleep "$3"
  kill -KILL "$2" 2>/dev/null || true
fi
'
if command -v perl >/dev/null 2>&1; then
  perl -MPOSIX -e 'POSIX::setpgid(0, 0); exec @ARGV or die "exec: $!"' \
    sh -c "$watcher_script" sh "$duration" "$child" "$kill_after" &
else
  sh -c "$watcher_script" sh "$duration" "$child" "$kill_after" &
fi
watcher=$!
wait "$child"
status=$?
while kill -0 "$child" 2>/dev/null; do
  wait "$child"
  status=$?
done
kill "$watcher" 2>/dev/null || true
wait "$watcher" 2>/dev/null || true
exit "$status"
EOF
  } > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

make_immediate_exit_coderabbit() {
  exit_status="$1"
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  exit '"$exit_status"'
fi
exit 1
'
}

assert_immediate_review_exit_is_failure() {
  make_git_call_recorder
  make_immediate_exit_coderabbit "$1"
  export CODERABBIT_CRITIQUE_BASE=master

  run "$SCRIPT"

  assert_failure
  assert_output --partial "coderabbit review failed"
  assert_fallback_reason review-failed
  assert_no_git_calls
}

make_default_mocks() {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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
  assert_fallback_reason coderabbit-missing
  assert_no_git_calls
}

@test "prints usage for --help without invoking any command" {
  make_mock coderabbit 'printf "coderabbit:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"'
  make_git_call_recorder
  make_mock timeout 'printf "timeout:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"'

  run "$SCRIPT" --help

  assert_success
  assert_output "Usage: coderabbit-critique"
  assert_no_command_calls
}

@test "prints usage for -h without invoking any command" {
  make_mock coderabbit 'printf "coderabbit:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"'
  make_git_call_recorder
  make_mock timeout 'printf "timeout:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"'

  run "$SCRIPT" -h

  assert_success
  assert_output "Usage: coderabbit-critique"
  assert_no_command_calls
}

@test "rejects unexpected arguments without invoking any command" {
  make_mock coderabbit 'printf "coderabbit:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"'
  make_git_call_recorder
  make_mock timeout 'printf "timeout:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"'

  run --separate-stderr "$SCRIPT" --unexpected

  assert_failure
  assert_stderr "Usage: coderabbit-critique"
  assert_no_command_calls
}

@test "fails closed when no compatible timeout/gtimeout is found" {
  make_mock coderabbit 'exit 1'
  link_system_command date
  link_system_command mkdir

  # Scope PATH to only the mock bin dir (no real system timeout) for the
  # script invocation itself, mirroring pinentry-auto.bats's technique --
  # export'ing this into the whole test shell would also starve bats' own
  # `run` machinery.
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/bin" "$SCRIPT"

  assert_failure
  assert_stderr --partial "no timeout/gtimeout"
  assert_fallback_reason no-compatible-timeout-command
}

@test "fails closed when timeout exists but lacks --kill-after (BusyBox-style)" {
  make_mock coderabbit 'exit 1'
  link_system_command date
  link_system_command mkdir
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
  assert_fallback_reason no-compatible-timeout-command
}

@test "resolves to gtimeout when timeout is absent" {
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
exit 1
'
  make_mock_timeout gtimeout 'shift 4; exec "$@"'
  link_system_command date
  link_system_command jq
  link_system_command mktemp
  link_system_command cat
  link_system_command rm
  link_system_command mkdir
  link_system_command sh
  if [ -n "$_HOST_SETSID" ]; then
    ln -sf "$_HOST_SETSID" "$BATS_TEST_TMPDIR/bin/setsid"
  fi

  # Scope PATH so the real system timeout cannot mask the gtimeout-only
  # branch; the mock gtimeout remains available.
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/bin" CODERABBIT_CRITIQUE_BASE=master "$SCRIPT"

  refute_output --partial "no timeout/gtimeout"
  assert_fallback_reason review-failed
}

@test "fails closed when jq is not found" {
  make_mock coderabbit 'exit 1'
  make_mock_timeout timeout 'shift 4; exec "$@"'
  link_system_command date
  link_system_command mkdir

  # Scope PATH to only the mock bin dir (mocked coderabbit/timeout, no
  # real jq) -- the jq preflight check runs before auth_status or review,
  # so nothing past it (mktemp, cat, coderabbit auth/review) is ever
  # reached in this test.
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/bin" "$SCRIPT"

  assert_failure
  assert_stderr --partial "jq not found"
  assert_fallback_reason jq-missing
}

@test "fails without calling review when auth status reports signed out" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  printf "auth:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
  echo "{\"authenticated\":false}"
  exit 0
fi
printf "review:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
exit 0
'

  run "$SCRIPT"

  assert_failure
  assert_output --partial "not authenticated"
  assert_fallback_reason unauthenticated
  run grep -c '^review:' "$CODERABBIT_CRITIQUE_LOG"
  assert_output "0"
  run grep -c 'auth:auth status --agent' "$CODERABBIT_CRITIQUE_LOG"
  assert_output "1"
  assert_no_git_calls
}

@test "passes through a clean structured-findings response" {
  make_default_mocks

  run "$SCRIPT"

  assert_success
  assert_output --partial '"type":"finding"'
  assert_no_git_calls
}

@test "keeps standard review arguments for unset, empty, and false deep switches" {
  make_default_mocks

  for value in unset '' 0 false no; do
    if [ "$value" = unset ]; then
      unset CODERABBIT_CRITIQUE_DEEP
    else
      export CODERABBIT_CRITIQUE_DEEP="$value"
    fi
    run "$SCRIPT"
    assert_success
  done

  run grep -cF 'review:review --agent --base master' "$CODERABBIT_CRITIQUE_LOG"
  assert_output "5"
  run grep -cF -- '--deep' "$CODERABBIT_CRITIQUE_LOG"
  assert_output "0"
}

@test "passes exactly one deep flag for each accepted truthy spelling" {
  make_default_mocks

  for value in 1 true TRUE yes YeS; do
    export CODERABBIT_CRITIQUE_DEEP="$value"
    run "$SCRIPT"
    assert_success
  done

  run grep -cFx 'review:review --agent --base master --deep' "$CODERABBIT_CRITIQUE_LOG"
  assert_output "5"
  run grep -cF -- 'focus' "$CODERABBIT_CRITIQUE_LOG"
  assert_output "0"
}

@test "waits for setsid to establish its process group before checking isolation" {
  if [ -z "$_HOST_SETSID" ]; then
    skip "requires setsid"
  fi
  make_default_mocks
  export CODERABBIT_REAL_SETSID="$_HOST_SETSID"
  setsid_invocations="$BATS_TEST_TMPDIR/setsid.invocations"
  export CODERABBIT_SETSID_INVOCATIONS="$setsid_invocations"
  make_mock setsid '
printf "%s\n" "$*" >> "$CODERABBIT_SETSID_INVOCATIONS"
sleep 0.1
exec "$CODERABBIT_REAL_SETSID" "$@"
'

  run "$SCRIPT"

  assert_success
  assert_output --partial '"type":"finding"'
  # The delay only proves the wait if the wrapper really launched the review
  # through this setsid; without the record, a run that fell back to the
  # timeout-created group would pass just the same.
  assert [ -s "$setsid_invocations" ]
  assert_no_git_calls
}

@test "emits a progress line to stderr only, as the first stderr line, before invoking review" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  echo "{\"type\":\"finding\"}"
  echo "review-own-stderr-diagnostic" >&2
  exit 0
fi
exit 1
'
  # Non-default base/timeout values (not "master"/300s) so this proves the
  # line actually interpolates $BASE_BRANCH/$TIMEOUT_SECONDS rather than
  # merely matching a hardcoded literal that happened to equal the defaults.
  export CODERABBIT_CRITIQUE_BASE=develop
  export CODERABBIT_CRITIQUE_TIMEOUT=45

  run --separate-stderr "$SCRIPT"

  assert_success
  # Position: the progress line is the very first line this script writes
  # to its own stderr -- ahead of anything the wrapped `coderabbit review`
  # call itself produces (buffered and only forwarded afterward).
  assert_stderr_line --index 0 \
    "coderabbit-critique: invoking coderabbit review --agent --base develop (timeout 45s)"
  assert_stderr --partial "review-own-stderr-diagnostic"
  # Stream: never on stdout, and never mixed into the findings text.
  refute_output --partial "invoking coderabbit review"
  assert_output --partial '"type":"finding"'
  assert_no_git_calls
}

@test "fails closed when mktemp fails" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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
  assert_fallback_reason mktemp-failed
  assert_no_git_calls
}

@test "cleans an earlier auth temp directory when a later mktemp fails" {
  make_git_call_recorder
  # The auth probe is the only timeout call before the later mktemp fails.
  # Its ninth and tenth arguments are the stdout and done paths it hands to
  # `sh -c`; record them so the test can pin that both live inside the
  # private directory rather than beside it.
  probe_paths="$BATS_TEST_TMPDIR/probe.paths"
  export CODERABBIT_PROBE_PATHS="$probe_paths"
  make_mock_timeout timeout '
printf "%s\n" "$9" >> "$CODERABBIT_PROBE_PATHS"
printf "%s\n" "${10}" >> "$CODERABBIT_PROBE_PATHS"
shift 4
exec "$@"
'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
exit 1
'
  allocated_temp="$BATS_TEST_TMPDIR/allocated.tmp"
  mktemp_counter="$BATS_TEST_TMPDIR/mktemp.counter"
  mktemp_first_args="$BATS_TEST_TMPDIR/mktemp.first-args"
  export CODERABBIT_MKTEMP_COUNTER="$mktemp_counter"
  export CODERABBIT_MKTEMP_FIRST="$allocated_temp"
  export CODERABBIT_MKTEMP_FIRST_ARGS="$mktemp_first_args"
  later_mktemp_dir="$BATS_TEST_TMPDIR/later-mktemp-bin"
  mkdir -p "$later_mktemp_dir"
  # The first allocation is the auth probe's private directory: honor
  # `mktemp -d` by making a directory (the probe then writes its stdout
  # and done token inside it), and record the arguments so the private
  # directory contract cannot silently regress to a predictable sibling
  # file. A plain (non -d) call still yields a file, which the argument
  # assertion below rejects.
  make_mock mktemp '
if [ ! -e "$CODERABBIT_MKTEMP_COUNTER" ]; then
  : > "$CODERABBIT_MKTEMP_COUNTER"
  printf "%s\n" "$*" > "$CODERABBIT_MKTEMP_FIRST_ARGS"
  if [ "$1" = "-d" ]; then
    mkdir "$CODERABBIT_MKTEMP_FIRST"
  else
    : > "$CODERABBIT_MKTEMP_FIRST"
  fi
  printf "%s\n" "$CODERABBIT_MKTEMP_FIRST"
  exit 0
fi
exit 1
'
  mv "$BATS_TEST_TMPDIR/bin/mktemp" "$later_mktemp_dir/mktemp"
  link_system_command date
  link_system_command jq
  link_system_command mkdir
  link_system_command ps
  link_system_command rm

  run --separate-stderr env PATH="$later_mktemp_dir:$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" CODERABBIT_CRITIQUE_BASE=master "$SCRIPT"

  assert_failure
  assert_stderr --partial "mktemp failed"
  assert_fallback_reason mktemp-failed
  assert_equal "$(cut -d' ' -f1 "$mktemp_first_args")" "-d"
  assert_equal "$(dirname "$(sed -n 1p "$probe_paths")")" "$allocated_temp"
  assert_equal "$(dirname "$(sed -n 2p "$probe_paths")")" "$allocated_temp"
  assert [ ! -e "$allocated_temp" ]
  assert_no_git_calls
}

@test "keeps stderr out of a successful findings response" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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
  assert_fallback_reason action_required
  assert_no_git_calls
}

@test "keeps the delegate behavior when the fallback log is unwritable" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  echo "{\"type\":\"action_required\",\"phase\":\"billing\"}"
  exit 0
fi
exit 1
'
  export CODERABBIT_CRITIQUE_BASE=master
  mkdir -p "$FALLBACK_LOG_FILE"

  run --separate-stderr "$SCRIPT"

  assert_failure
  assert_output ""
  assert_stderr --partial "requires operator action"
  assert [ -d "$FALLBACK_LOG_FILE" ]
  assert_no_git_calls
}

@test "rejects a pretty-printed action_required response with whitespace around the marker" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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
  assert_fallback_reason action_required
  assert_no_git_calls
}

@test "rejects an action_required response arriving only on stderr" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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
  assert_fallback_reason action_required
  assert_no_git_calls
}

@test "does not trip on an unescaped nested action_required type field inside a finding" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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

@test "does not trip on an array-valued top-level type property" {
  # Twin-parity coverage for a PowerShell-specific regression (CodeRabbit
  # review on this PR): PowerShell's `-ceq` does an element-wise
  # comparison against a collection value, so `{"type":["action_required"]}`
  # could wrongly match there unless the value's type is checked first.
  # jq's raw output for a non-string `.type` value can never equal the
  # bare `action_required` literal in this script's plain string
  # comparison, so the shell twin was never exposed to this -- this test
  # locks that in.
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  echo "{\"type\":[\"action_required\"],\"phase\":\"billing\"}"
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
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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
  assert_fallback_reason review-failed
  assert_no_git_calls
}

@test "classifies a review exit 124 as review-failed rather than timeout" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  echo "review returned 124" >&2
  exit 124
fi
exit 1
'
  export CODERABBIT_CRITIQUE_BASE=master

  run "$SCRIPT"

  assert_failure
  assert_output --partial "coderabbit review failed"
  assert_fallback_reason review-failed
  assert_no_git_calls
}

@test "classifies an immediate review exit 15 as review-failed" {
  assert_immediate_review_exit_is_failure 15
}

@test "classifies an immediate review exit 137 as review-failed" {
  assert_immediate_review_exit_is_failure 137
}

@test "classifies an immediate review exit 143 as review-failed" {
  assert_immediate_review_exit_is_failure 143
}

@test "fails when review times out" {
  if ! require_compatible_host_timer; then
    skip "requires GNU timeout or gtimeout"
  fi

  make_git_call_recorder
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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
  assert_fallback_reason timeout
  assert_no_git_calls
}

@test "times out a review process that ignores TERM without waiting for an orphan" {
  make_git_call_recorder
  make_mock_timeout_with_kill timeout
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  trap "" TERM
  exec sleep 30
fi
exit 1
'
  export CODERABBIT_CRITIQUE_TIMEOUT=1
  export CODERABBIT_CRITIQUE_BASE=master

  started_at=$(date +%s)
  run "$SCRIPT"
  elapsed=$(( $(date +%s) - started_at ))

  assert_failure
  assert [ "$elapsed" -lt 10 ]
  assert_fallback_reason timeout
  assert_no_git_calls
}

@test "records a deadline when timeout interrupts descendant cleanup" {
  make_git_call_recorder
  make_mock_timeout_with_kill timeout
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  sleep 0.6
  trap "" TERM
  sleep 30 &
  printf "%s\\n" "$!" > "$CODERABBIT_DESCENDANT_PID_FILE"
  exit 0
fi
exit 1
'
  descendant_pid_file="$BATS_TEST_TMPDIR/cleanup-deadline.pid"
  export CODERABBIT_DESCENDANT_PID_FILE="$descendant_pid_file"
  export CODERABBIT_CRITIQUE_TIMEOUT=1
  export CODERABBIT_CRITIQUE_BASE=master

  run "$SCRIPT"

  assert_failure
  assert_output --partial "coderabbit review failed or timed out"
  assert_fallback_reason timeout
  descendant_pid=$(cat "$descendant_pid_file")
  run kill -0 "$descendant_pid"
  assert_failure
  assert_no_git_calls
}

@test "kills descendants before timeout's grace kills the setsid supervisor" {
  if [ -z "${_HOST_SETSID:-}" ]; then
    skip "requires setsid"
  fi
  if ! require_compatible_host_timer; then
    skip "requires GNU timeout or gtimeout"
  fi
  ln -sf "$_HOST_SETSID" "$BATS_TEST_TMPDIR/bin/setsid"

  make_git_call_recorder
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  sleep 0.6
  trap "" TERM
  sleep 30 &
  printf "%s\\n" "$!" > "$CODERABBIT_DESCENDANT_PID_FILE"
  exit 0
fi
exit 1
'
  descendant_pid_file="$BATS_TEST_TMPDIR/setsid-cleanup-deadline.pid"
  export CODERABBIT_DESCENDANT_PID_FILE="$descendant_pid_file"
  export CODERABBIT_CRITIQUE_TIMEOUT=1
  export CODERABBIT_CRITIQUE_BASE=master

  # Use the real GNU timeout so its process-group kill-after grace races the
  # supervisor's cleanup window just as it can in production.
  run "$SCRIPT"

  assert_failure
  assert_output --partial "coderabbit review failed or timed out"
  assert_fallback_reason timeout
  descendant_pid=$(cat "$descendant_pid_file")
  run kill -0 "$descendant_pid"
  assert_failure
  assert_no_git_calls
}

@test "keeps a deadline timeout fail-closed when the review handles TERM with exit 0" {
  make_git_call_recorder
  make_mock_timeout_with_kill timeout
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  sleep 30 &
  sleep_pid=$!
  trap "kill $sleep_pid 2>/dev/null || true; exit 0" TERM
  wait "$sleep_pid"
fi
exit 1
'
  export CODERABBIT_CRITIQUE_TIMEOUT=1
  export CODERABBIT_CRITIQUE_BASE=master

  run "$SCRIPT"

  assert_failure
  assert_output --partial "coderabbit review failed"
  assert_fallback_reason timeout
  assert_no_git_calls
}

@test "cleans up a descendant after the review exits successfully" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  trap "" TERM
  sleep 30 &
  printf "%s\\n" "$!" > "$CODERABBIT_DESCENDANT_PID_FILE"
  exit 0
fi
exit 1
'
  descendant_pid_file="$BATS_TEST_TMPDIR/descendant.pid"
  export CODERABBIT_DESCENDANT_PID_FILE="$descendant_pid_file"
  export CODERABBIT_CRITIQUE_BASE=master

  run "$SCRIPT"

  assert_success
  descendant_pid=$(cat "$descendant_pid_file")
  run kill -0 "$descendant_pid"
  assert_failure
  assert_no_git_calls
}

@test "uses timeout's process group when setsid is unavailable" {
  if ! require_compatible_host_timer; then
    skip "requires GNU timeout or gtimeout"
  fi

  make_git_call_recorder
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  trap "" TERM
  sleep 30 &
  printf "%s\\n" "$!" > "$CODERABBIT_DESCENDANT_PID_FILE"
  exit 0
fi
exit 1
'
  descendant_pid_file="$BATS_TEST_TMPDIR/descendant.pid"
  export CODERABBIT_DESCENDANT_PID_FILE="$descendant_pid_file"
  export CODERABBIT_CRITIQUE_BASE=master

  real_ps="$(command -v ps)"
  export CODERABBIT_REAL_PS="$real_ps"
  for command in awk cat date jq mkdir mktemp rm sh sleep tr; do
    link_system_command "$command"
  done
  make_mock ps '
if [ "$1" = "-o" ] && [ "$2" = "pgid=" ]; then
  sleep 0.2
fi
exec "$CODERABBIT_REAL_PS" "$@"
'
  export PATH="$BATS_TEST_TMPDIR/bin"

  # Keep setsid out of PATH so the helper must use the timeout-created
  # process group, as it does on macOS with Homebrew's gtimeout.
  run "$SCRIPT"

  assert_success
  descendant_pid=$(cat "$descendant_pid_file")
  run kill -0 "$descendant_pid"
  assert_failure
  assert_no_git_calls
}

@test "does not count the membership probe as a no-setsid review member" {
  if ! require_compatible_host_timer; then
    skip "requires GNU timeout or gtimeout"
  fi

  make_git_call_recorder
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  echo "{\"type\":\"finding\"}"
  exit 0
fi
exit 1
'
  export CODERABBIT_CRITIQUE_TIMEOUT=1
  export CODERABBIT_CRITIQUE_BASE=master

  real_ps="$(command -v ps)"
  export CODERABBIT_REAL_PS="$real_ps"
  for command in awk cat date jq mkdir mktemp rm sh sleep tr; do
    link_system_command "$command"
  done
  make_mock ps 'exec "$CODERABBIT_REAL_PS" "$@"'
  export PATH="$BATS_TEST_TMPDIR/bin"

  # Keep setsid out of PATH so the wrapper exercises the timeout-created
  # process group and its file-backed membership probe.
  run "$SCRIPT"

  assert_success
  assert_output --partial '"type":"finding"'
  assert_no_git_calls
}

@test "reaps a TERM-ignoring review without setsid when a group-directed TERM follows the first" {
  if ! command -v perl >/dev/null 2>&1; then
    skip "requires perl for the timeout mock's process group"
  fi
  make_git_call_recorder
  make_mock_timeout_with_kill timeout survive
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  trap "" TERM
  sleep 30 &
  printf "%s\\n" "$PPID" > "$CODERABBIT_REVIEW_PID_FILE.supervisor"
  printf "%s\\n" "$!" > "$CODERABBIT_REVIEW_PID_FILE"
  wait
fi
exit 1
'
  review_pid_file="$BATS_TEST_TMPDIR/review-members.pid"
  export CODERABBIT_REVIEW_PID_FILE="$review_pid_file"
  export CODERABBIT_CRITIQUE_TIMEOUT=1
  export CODERABBIT_CRITIQUE_BASE=master
  export TMPDIR="$BATS_TEST_TMPDIR"
  for command in awk cat date jq mkdir mktemp perl ps rm sh sleep tr; do
    link_system_command "$command"
  done

  # Keep setsid out of the wrapper's PATH so cleanup runs in members mode, the
  # mode a host without setsid uses, where the delayed-KILL helper shares the
  # review's process group. The mock timer TERMs the supervisor after 1s and
  # the helper's KILL is due 1s after that; a second TERM aimed at the whole
  # group in between, as the wrapper's own cancellation forwarding sends,
  # must not remove the helper. The mock timer keeps this independent of
  # whether the host's timeout kills its whole group itself. The second TERM
  # is timed from the supervisor recording the first one, not from the review
  # starting, because a slow host starts the review well after the mock timer.
  # start_wrapper_job closes FD 3 for the background run: a review left alive
  # by a regression would otherwise hold it and stall Bats until that process
  # exits.
  t_launch=$(date +%s.%N)
  start_wrapper_job "$BATS_TEST_TMPDIR/members.stdout" "$BATS_TEST_TMPDIR/members.stderr" \
    env PATH="$BATS_TEST_TMPDIR/bin" "$SCRIPT"
  wait_for_file "$review_pid_file" 20 "the review to record its PID"
  t_started=$(date +%s.%N)

  # The supervisor writes its deadline marker in the first TERM handler.
  wait_until 20 "the supervisor's deadline marker" deadline_marker_written
  sleep 0.3
  supervisor_pid=$(cat "$review_pid_file.supervisor")
  group_id="$(ps -o pgid= -p "$supervisor_pid" | tr -d '[:space:]')"
  assert [ -n "$group_id" ]
  t_group_term=$(date +%s.%N)
  kill -TERM -- "-$group_id" 2>/dev/null || true

  review_pid=$(cat "$review_pid_file")
  if ! poll_until 20 process_is_gone "$review_pid"; then
    # Leave enough evidence in the log to tell a wrapper that never escalated
    # from one whose KILL missed, since this only shows up on some hosts.
    {
      echo "DIAG launch=$t_launch started=$t_started group_term=$t_group_term now=$(date +%s.%N)"
      echo "DIAG group_id=$group_id supervisor_pid=$supervisor_pid review_pid=$review_pid script_pid=$script_pid"
      ps -eo pid,ppid,pgid,stat,etime,args |
        awk -v r="$review_pid" -v s="$supervisor_pid" -v g="$group_id" \
          'NR == 1 || $1 == r || $1 == s || $2 == r || $2 == s || $3 == g || $3 == r { print "DIAG " $0 }'
      echo "DIAG wrapper stderr:"
      cat "$BATS_TEST_TMPDIR/members.stderr"
    } >&3
    kill -KILL "$review_pid" "$supervisor_pid" 2>/dev/null || true
    fail "timed out after 20s waiting for review process $review_pid to exit"
  fi
}

@test "gives a cooperative review its cleanup grace when TERM reaches the supervisor twice" {
  if ! command -v perl >/dev/null 2>&1; then
    skip "requires perl for the timeout mock's process group"
  fi

  make_git_call_recorder
  make_mock_timeout_with_kill timeout
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  sleeper=
  # Needs about 0.4s of cleanup after TERM. Ignoring further TERMs stops the
  # sweeps from re-entering this handler and keeps them from cutting that work
  # short, and the review sends the supervisor a second TERM once cleanup has
  # begun, the duplicate delivery real timeout produces by forwarding and
  # broadcasting. The handler goes in first so a slow start cannot let the
  # first TERM kill the review before it is ready.
  cleanup() {
    trap "" TERM
    sleep 0.1
    kill -TERM "$PPID"
    sleep 0.3
    kill "$sleeper" 2>/dev/null
    printf "%s\\n" done > "$CODERABBIT_CLEANUP_MARKER"
    exit 143
  }
  trap cleanup TERM
  sleep 30 &
  sleeper=$!
  wait "$sleeper"
fi
exit 1
'
  cleanup_marker="$BATS_TEST_TMPDIR/cleanup.marker"
  export CODERABBIT_CLEANUP_MARKER="$cleanup_marker"
  export CODERABBIT_CRITIQUE_TIMEOUT=1
  export CODERABBIT_CRITIQUE_BASE=master
  export TMPDIR="$BATS_TEST_TMPDIR"
  for command in awk cat date jq mkdir mktemp perl ps rm sh sleep tr; do
    link_system_command "$command"
  done

  # Keep setsid out of the wrapper's PATH so cleanup runs in members mode,
  # where the delayed-KILL helper's grace can be cut short by a repeated sweep.
  run --separate-stderr env PATH="$BATS_TEST_TMPDIR/bin" "$SCRIPT"

  assert_failure
  assert_fallback_reason timeout
  assert [ -f "$cleanup_marker" ]
  assert_no_git_calls
}

@test "forwards external TERM to the timeout job before exiting" {
  if ! require_compatible_host_timer; then
    skip "requires GNU timeout or gtimeout"
  fi

  make_git_call_recorder
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  sleeper=
  # Ignoring further TERMs first makes the handler idempotent: the wrapper and
  # timeout both deliver TERM, and a second one landing between the log write
  # and the exit would otherwise log it twice. The handler is installed before
  # the pid file appears, so the test only signals a review that is ready.
  cleanup() {
    trap "" TERM
    kill "$sleeper" 2>/dev/null || true
    echo term >> "$CODERABBIT_CRITIQUE_LOG"
    exit 143
  }
  trap cleanup TERM
  sleep 30 &
  sleeper=$!
  printf "%s\\n" "$sleeper" > "$CODERABBIT_REVIEW_PID_FILE"
  wait "$sleeper"
fi
exit 1
'
  review_pid_file="$BATS_TEST_TMPDIR/review.pid"
  export CODERABBIT_REVIEW_PID_FILE="$review_pid_file"
  export CODERABBIT_CRITIQUE_TIMEOUT=30
  export CODERABBIT_CRITIQUE_BASE=master
  output_file="$BATS_TEST_TMPDIR/outer.stdout"
  error_file="$BATS_TEST_TMPDIR/outer.stderr"

  start_wrapper_job "$output_file" "$error_file" "$SCRIPT"
  wait_for_file "$review_pid_file" 10 "the review to record its PID"

  kill -TERM "$script_pid"
  set +e
  wait "$script_pid"
  status=$?
  set -e

  assert_equal 143 "$status"
  run grep -c '^term$' "$CODERABBIT_CRITIQUE_LOG"
  # The wrapper TERMs the timeout job's group itself and timeout forwards it
  # again, and the supervisor's on_term has no once-guard, so it re-sends TERM
  # to the review for each one it gets and the review can receive TERM more
  # than once (the duplicate delivery described in "gives a cooperative review
  # its cleanup grace when TERM reaches the supervisor twice"). The mock's
  # handler ignores TERM first, so it logs once however many arrive, and it is
  # installed before the pid file appears, so an early TERM cannot be missed.
  # That makes the count exactly one with setsid. Without setsid the review
  # shares timeout's own process group and which TERMs reach it depends on the
  # host, so this stays an at-least-one check there.
  if command -v setsid >/dev/null 2>&1; then
    assert_output "1"
  else
    assert [ "$output" -ge 1 ]
  fi
  review_pid=$(cat "$review_pid_file")
  run kill -0 "$review_pid"
  assert_failure
}

@test "forwards external INT and applies bounded cleanup before exiting" {
  signal_reset_command="$(command -v perl || true)"
  if [ -z "$signal_reset_command" ]; then
    skip "requires perl to reset inherited SIGINT disposition"
  fi
  if ! require_compatible_host_timer; then
    skip "requires GNU timeout or gtimeout"
  fi

  make_git_call_recorder
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  trap "" INT TERM
  sleep 30 &
  review_pid=$!
  printf "%s\\n" "$review_pid" > "$CODERABBIT_REVIEW_PID_FILE"
  wait "$review_pid"
fi
exit 1
'
  review_pid_file="$BATS_TEST_TMPDIR/review-int.pid"
  export CODERABBIT_REVIEW_PID_FILE="$review_pid_file"
  export CODERABBIT_CRITIQUE_TIMEOUT=30
  export CODERABBIT_CRITIQUE_BASE=master

  # Background jobs inherit SIGINT=ignored from the non-interactive Bats
  # shell. Reset it in a tiny exec shim so this exercises the delegate's
  # real external-cancellation trap rather than the shell's disposition.
  start_wrapper_job "$BATS_TEST_TMPDIR/outer-int.stdout" "$BATS_TEST_TMPDIR/outer-int.stderr" \
    "$signal_reset_command" -e '$SIG{INT} = "DEFAULT"; exec @ARGV' "$SCRIPT"
  wait_for_file "$review_pid_file" 10 "the review to record its PID"

  kill -INT "$script_pid"
  if wait "$script_pid"; then
    status=0
  else
    status=$?
  fi

  assert_equal 130 "$status"
  review_pid=$(cat "$review_pid_file")
  wait_until 10 "the review process to exit" process_is_gone "$review_pid"
}

@test "forwards external HUP and applies bounded cleanup before exiting" {
  signal_reset_command="$(command -v perl || true)"
  if [ -z "$signal_reset_command" ]; then
    skip "requires perl to reset inherited SIGHUP disposition"
  fi
  if ! require_compatible_host_timer; then
    skip "requires GNU timeout or gtimeout"
  fi

  make_git_call_recorder
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  trap "" HUP INT TERM
  sleep 30 &
  review_pid=$!
  printf "%s\\n" "$review_pid" > "$CODERABBIT_REVIEW_PID_FILE"
  wait "$review_pid"
fi
exit 1
'
  review_pid_file="$BATS_TEST_TMPDIR/review-hup.pid"
  export CODERABBIT_REVIEW_PID_FILE="$review_pid_file"
  export CODERABBIT_CRITIQUE_TIMEOUT=30
  export CODERABBIT_CRITIQUE_BASE=master

  start_wrapper_job "$BATS_TEST_TMPDIR/outer-hup.stdout" "$BATS_TEST_TMPDIR/outer-hup.stderr" \
    "$signal_reset_command" -e '$SIG{HUP} = "DEFAULT"; exec @ARGV' "$SCRIPT"
  wait_for_file "$review_pid_file" 10 "the review to record its PID"

  kill -HUP "$script_pid"
  if wait "$script_pid"; then
    status=0
  else
    status=$?
  fi

  assert_equal 129 "$status"
  review_pid=$(cat "$review_pid_file")
  wait_until 10 "the review process to exit" process_is_gone "$review_pid"
}

@test "forwards external QUIT and applies bounded cleanup before exiting" {
  signal_reset_command="$(command -v perl || true)"
  if [ -z "$signal_reset_command" ]; then
    skip "requires perl to reset inherited SIGQUIT disposition"
  fi
  if ! require_compatible_host_timer; then
    skip "requires GNU timeout or gtimeout"
  fi

  make_git_call_recorder
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  trap "" QUIT HUP INT TERM
  sleep 30 &
  review_pid=$!
  printf "%s\\n" "$review_pid" > "$CODERABBIT_REVIEW_PID_FILE"
  wait "$review_pid"
fi
exit 1
'
  review_pid_file="$BATS_TEST_TMPDIR/review-quit.pid"
  export CODERABBIT_REVIEW_PID_FILE="$review_pid_file"
  export CODERABBIT_CRITIQUE_TIMEOUT=30
  export CODERABBIT_CRITIQUE_BASE=master

  start_wrapper_job "$BATS_TEST_TMPDIR/outer-quit.stdout" "$BATS_TEST_TMPDIR/outer-quit.stderr" \
    "$signal_reset_command" -e '$SIG{QUIT} = "DEFAULT"; exec @ARGV' "$SCRIPT"
  wait_for_file "$review_pid_file" 10 "the review to record its PID"

  kill -QUIT "$script_pid"
  if wait "$script_pid"; then
    status=0
  else
    status=$?
  fi

  assert_equal 131 "$status"
  review_pid=$(cat "$review_pid_file")
  wait_until 10 "the review process to exit" process_is_gone "$review_pid"
}

@test "wait_for_file fails at its deadline and names what it was waiting for" {
  started_at=$SECONDS
  run wait_for_file "$BATS_TEST_TMPDIR/never-written" 1 "the never-written file"
  elapsed=$((SECONDS - started_at))

  assert_failure
  assert_output --partial "timed out after 1s waiting for the never-written file"
  # Bounded on both sides: it really waited, and it did not hang. SECONDS is a
  # whole-second clock, so the two-second lower bound is what proves that the
  # helper's extra second is there and that at least the requested second of
  # real time passed.
  assert [ "$elapsed" -ge 2 ]
  assert [ "$elapsed" -le 5 ]
}

@test "wait_for_file succeeds once a file appears after the wait has begun" {
  late_file="$BATS_TEST_TMPDIR/written-late"
  (
    sleep 0.5
    echo ready >"$late_file"
  ) >/dev/null 2>&1 3>&- &
  late_writer=$!

  wait_for_file "$late_file" 10 "the late file"

  wait "$late_writer"
  assert_equal ready "$(cat "$late_file")"
}

@test "teardown stops a wrapper and its review that a failed test left running" {
  if ! require_compatible_host_timer; then
    skip "requires GNU timeout or gtimeout"
  fi

  make_git_call_recorder
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
if [ "$1" = "review" ]; then
  sleep 30 &
  printf "%s\\n%s\\n" "$$" "$!" > "$CODERABBIT_REVIEW_PID_FILE"
  wait
fi
exit 1
'
  review_pid_file="$BATS_TEST_TMPDIR/review-left-running.pid"
  export CODERABBIT_REVIEW_PID_FILE="$review_pid_file"
  export CODERABBIT_CRITIQUE_TIMEOUT=30
  export CODERABBIT_CRITIQUE_BASE=master

  start_wrapper_job "$BATS_TEST_TMPDIR/left-running.stdout" \
    "$BATS_TEST_TMPDIR/left-running.stderr" "$SCRIPT"
  wrapper_pid=$script_pid
  wait_for_file "$review_pid_file" 10 "the review to record its PIDs"
  review_shell_pid=$(sed -n 1p "$review_pid_file")
  review_sleeper_pid=$(sed -n 2p "$review_pid_file")
  # Everything is running at this point, as it would be for a test that failed
  # an assertion right after launching the wrapper.
  run kill -0 "$wrapper_pid"
  assert_success
  run process_is_gone "$review_shell_pid"
  assert_failure
  run process_is_gone "$review_sleeper_pid"
  assert_failure

  # Return without stopping anything, then run the teardown routine itself.
  # Bats runs it again afterwards, which must stay harmless.
  teardown

  run kill -0 "$wrapper_pid"
  assert_failure
  run process_is_gone "$review_shell_pid"
  assert_success
  run process_is_gone "$review_sleeper_pid"
  assert_success
}

@test "stop_tracked_wrappers reaches descendants that would outlive their parent" {
  child_file="$BATS_TEST_TMPDIR/tree-child.pid"
  # The parent dies on the first TERM and leaves its sleeper running, so only a
  # walk of the parent links finds the sleeper in time.
  start_wrapper_job "$BATS_TEST_TMPDIR/tree.stdout" "$BATS_TEST_TMPDIR/tree.stderr" \
    sh -c 'sleep 30 & echo "$!" >"$1"; wait' sh "$child_file"
  wait_for_file "$child_file" 10 "the child to record its PID"
  child_pid=$(cat "$child_file")
  run process_is_gone "$child_pid"
  assert_failure

  stop_tracked_wrappers

  run process_is_gone "$script_pid"
  assert_success
  run process_is_gone "$child_pid"
  assert_success
}

@test "stop_tracked_wrappers kills a process tree that ignores TERM" {
  child_file="$BATS_TEST_TMPDIR/ignoring-child.pid"
  # The parent and its sleeper both ignore TERM, and the sleeper outlasts the
  # test, so only the KILL pass can end them.
  start_wrapper_job "$BATS_TEST_TMPDIR/ignoring.stdout" "$BATS_TEST_TMPDIR/ignoring.stderr" \
    sh -c 'trap "" TERM; sleep 60 & echo "$!" >"$1"; wait' sh "$child_file"
  wait_for_file "$child_file" 10 "the child to record its PID"
  child_pid=$(cat "$child_file")

  stop_tracked_wrappers

  run process_is_gone "$script_pid"
  assert_success
  run process_is_gone "$child_pid"
  assert_success
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
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
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
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
exit 1
'
  work="$(setup_git_repo_with_base both)"
  make_git_passthrough_logger

  run --separate-stderr sh -c 'cd "$1" && shift && exec "$@"' -- "$work" "$SCRIPT"

  assert_failure
  assert_stderr --partial "could not determine the default base branch"
  assert_fallback_reason base-branch-unresolved
}

@test "fails closed when the base branch cannot be determined" {
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 0
fi
exit 1
'
  work="$(setup_git_repo_with_base none)"
  make_git_passthrough_logger

  run --separate-stderr sh -c 'cd "$1" && shift && exec "$@"' -- "$work" "$SCRIPT"

  assert_failure
  assert_stderr --partial "could not determine the default base branch"
  assert_fallback_reason base-branch-unresolved
  assert_only_readonly_git_subcommands_and_at_least_one
}

# The next two tests model a caller that already has the policy variables
# set, instead of relying on the runner that happens to run the suite. Saving
# overwrites the snapshot setup() took, so they stash it first and teardown()
# puts it back, including when an assertion fails part way.
stash_critique_policy_snapshot() {
  _outer_snapshot_stashed=1
  _outer_deep_set=$_policy_deep_set
  _outer_deep_val=$_policy_deep_val
  _outer_base_set=$_policy_base_set
  _outer_base_val=$_policy_base_val
  _outer_timeout_set=$_policy_timeout_set
  _outer_timeout_val=$_policy_timeout_val
}

reinstate_critique_policy_snapshot() {
  _policy_deep_set=$_outer_deep_set
  _policy_deep_val=$_outer_deep_val
  _policy_base_set=$_outer_base_set
  _policy_base_val=$_outer_base_val
  _policy_timeout_set=$_outer_timeout_set
  _policy_timeout_val=$_outer_timeout_val
}

@test "saves, clears, and restores each policy variable exactly across absent, empty, and set states" {
  stash_critique_policy_snapshot

  for state in absent empty set; do
    case "$state" in
      absent)
        unset CODERABBIT_CRITIQUE_DEEP CODERABBIT_CRITIQUE_BASE CODERABBIT_CRITIQUE_TIMEOUT
        ;;
      empty)
        export CODERABBIT_CRITIQUE_DEEP= CODERABBIT_CRITIQUE_BASE= CODERABBIT_CRITIQUE_TIMEOUT=
        ;;
      set)
        export CODERABBIT_CRITIQUE_DEEP=1 CODERABBIT_CRITIQUE_BASE=develop CODERABBIT_CRITIQUE_TIMEOUT=45
        ;;
    esac

    save_critique_policy_env
    # Cleared after the save, whatever state the caller was in.
    [ "${CODERABBIT_CRITIQUE_DEEP+x}" != x ]
    [ "${CODERABBIT_CRITIQUE_BASE+x}" != x ]
    [ "${CODERABBIT_CRITIQUE_TIMEOUT+x}" != x ]

    restore_critique_policy_env
    case "$state" in
      absent)
        [ "${CODERABBIT_CRITIQUE_DEEP+x}" != x ]
        [ "${CODERABBIT_CRITIQUE_BASE+x}" != x ]
        [ "${CODERABBIT_CRITIQUE_TIMEOUT+x}" != x ]
        ;;
      empty)
        [ "${CODERABBIT_CRITIQUE_DEEP+x}" = x ]
        [ -z "$CODERABBIT_CRITIQUE_DEEP" ]
        [ "${CODERABBIT_CRITIQUE_BASE+x}" = x ]
        [ -z "$CODERABBIT_CRITIQUE_BASE" ]
        [ "${CODERABBIT_CRITIQUE_TIMEOUT+x}" = x ]
        [ -z "$CODERABBIT_CRITIQUE_TIMEOUT" ]
        ;;
      set)
        [ "${CODERABBIT_CRITIQUE_DEEP-}" = 1 ]
        [ "${CODERABBIT_CRITIQUE_BASE-}" = develop ]
        [ "${CODERABBIT_CRITIQUE_TIMEOUT-}" = 45 ]
        ;;
    esac
  done

  unset CODERABBIT_CRITIQUE_DEEP CODERABBIT_CRITIQUE_BASE CODERABBIT_CRITIQUE_TIMEOUT
}

@test "keeps standard review arguments when the runner already has deep, base, and timeout set" {
  stash_critique_policy_snapshot
  export CODERABBIT_CRITIQUE_DEEP=1 CODERABBIT_CRITIQUE_BASE=develop CODERABBIT_CRITIQUE_TIMEOUT=45
  # The same save-and-clear setup() applies before every test.
  save_critique_policy_env
  make_default_mocks

  run --separate-stderr "$SCRIPT"

  assert_success
  assert_stderr --partial "invoking coderabbit review --agent --base master (timeout 300s)"
  run grep -cF 'review:review --agent --base master' "$CODERABBIT_CRITIQUE_LOG"
  assert_output "1"
  run grep -cF -- '--deep' "$CODERABBIT_CRITIQUE_LOG"
  assert_output "0"
  assert_no_git_calls
}

@test "fails closed when structured auth status is malformed" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo not-json
  exit 0
fi
printf "review:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
exit 0
'

  run --separate-stderr "$SCRIPT"

  assert_failure
  assert_stderr --partial "authentication status was not a boolean authenticated field"
  assert_fallback_reason auth-malformed
  # Auth fails before review, so the invocation log may not exist.
  if [ -f "$CODERABBIT_CRITIQUE_LOG" ]; then
    run grep -c '^review:' "$CODERABBIT_CRITIQUE_LOG"
    assert_output "0"
  fi
  assert_no_git_calls
}

@test "fails closed when structured auth status is valid JSON of the wrong shape" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  printf "%s\\n" "$CODERABBIT_AUTH_JSON"
  exit 0
fi
printf "review:%s\\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
exit 0
'

  # Only an object whose authenticated field is the boolean true may pass. Each
  # of these parses as JSON, so only the wrapper's own shape check rejects them.
  for auth_json in '{"authenticated":"true"}' '{}' '{"authenticated":null}' '[{"authenticated":true}]'; do
    rm -f "$FALLBACK_LOG_FILE" "$CODERABBIT_CRITIQUE_LOG"
    export CODERABBIT_AUTH_JSON="$auth_json"

    run --separate-stderr "$SCRIPT"

    assert_failure
    assert_stderr --partial "authentication status was not a boolean authenticated field"
    assert_fallback_reason auth-malformed
    if [ -f "$CODERABBIT_CRITIQUE_LOG" ]; then
      run grep -c '^review:' "$CODERABBIT_CRITIQUE_LOG"
      assert_output "0"
    fi
    assert_no_git_calls
  done
}

@test "fails closed when structured auth status is unsupported" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exec "$@"'
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "{\"authenticated\":true}"
  exit 2
fi
printf "review:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
exit 0
'

  run --separate-stderr "$SCRIPT"

  assert_failure
  assert_stderr --partial "authentication status command is unsupported or failed"
  assert_fallback_reason auth-unsupported
  if [ -f "$CODERABBIT_CRITIQUE_LOG" ]; then
    run grep -c '^review:' "$CODERABBIT_CRITIQUE_LOG"
    assert_output "0"
  fi
  assert_no_git_calls
}

@test "fails closed when a real timer cuts off a hung structured auth probe" {
  if ! require_compatible_host_timer; then
    skip "requires GNU timeout or gtimeout"
  fi

  make_git_call_recorder
  make_mock coderabbit '
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  sleep 10
  echo "{\"authenticated\":true}"
  exit 0
fi
printf "review:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
exit 0
'
  export CODERABBIT_CRITIQUE_TIMEOUT=1
  started_at=$(date +%s)

  run --separate-stderr "$SCRIPT"

  elapsed=$(( $(date +%s) - started_at ))
  assert_failure
  # The mocked timer below never runs the probe, so only a real kill leaves
  # the done token unwritten. That absence, not the exit status (a killed
  # child under --preserve-status is not 124), is what marks the timeout.
  assert_stderr --partial "authentication status timed out"
  assert_fallback_reason auth-timeout
  assert [ "$elapsed" -lt 8 ]
  if [ -f "$CODERABBIT_CRITIQUE_LOG" ]; then
    run grep -c '^review:' "$CODERABBIT_CRITIQUE_LOG"
    assert_output "0"
  fi
  assert_no_git_calls
}

@test "fails closed when the structured auth probe times out" {
  make_git_call_recorder
  make_mock_timeout timeout 'shift 4; exit 124'
  make_mock coderabbit '
printf "review:%s\n" "$*" >> "$CODERABBIT_CRITIQUE_LOG"
exit 0
'

  run --separate-stderr "$SCRIPT"

  assert_failure
  assert_stderr --partial "authentication status timed out"
  assert_fallback_reason auth-timeout
  if [ -f "$CODERABBIT_CRITIQUE_LOG" ]; then
    run grep -c '^review:' "$CODERABBIT_CRITIQUE_LOG"
    assert_output "0"
  fi
  assert_no_git_calls
}
