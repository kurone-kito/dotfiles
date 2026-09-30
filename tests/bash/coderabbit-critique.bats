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
}

teardown() {
  export PATH="$_ORIG_PATH"
  restore_critique_policy_env
  unset XDG_STATE_HOME CODERABBIT_CRITIQUE_LOG
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
# leads a group, and a host without perl keeps the previous behavior.
timeout_mock_group_prelude() {
  cat << 'EOF'
if [ -z "$CODERABBIT_MOCK_TIMEOUT_GROUPED" ] && command -v perl >/dev/null 2>&1; then
  CODERABBIT_MOCK_TIMEOUT_GROUPED=1 exec perl -MPOSIX -e 'POSIX::setpgid(0, 0); exec @ARGV or die "exec: $!"' "$0" "$@"
fi
EOF
}

make_mock_timeout() {
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

make_mock_timeout_with_kill() {
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
  make_git_call_recorder
  make_mock_timeout_with_kill timeout
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

  # Keep setsid out of the wrapper's PATH so cleanup runs in the members
  # mode a host without setsid uses, where the delayed-KILL helper shares the
  # review's process group. The mock timer TERMs the supervisor after 1s and
  # the helper's KILL is due 1s after that; a second TERM aimed at the whole
  # group in between, as the wrapper's own cancellation forwarding sends,
  # must not remove the helper. The mock timer keeps this independent of
  # whether the host's timeout kills its whole group itself.
  # Close FD 3 for the background run: a review left alive by a regression
  # would otherwise hold it and stall Bats until that process exits.
  PATH="$BATS_TEST_TMPDIR/bin" "$SCRIPT" \
    >"$BATS_TEST_TMPDIR/members.stdout" 2>"$BATS_TEST_TMPDIR/members.stderr" 3>&- &
  script_pid=$!
  started=false
  for _ in $(seq 1 30); do
    if [ -s "$review_pid_file" ]; then
      started=true
      break
    fi
    sleep 0.1
  done
  assert [ "$started" = true ]

  sleep 1.3
  supervisor_pid=$(cat "$review_pid_file.supervisor")
  group_id="$(ps -o pgid= -p "$supervisor_pid" | tr -d '[:space:]')"
  assert [ -n "$group_id" ]
  kill -TERM -- "-$group_id" 2>/dev/null || true

  review_pid=$(cat "$review_pid_file")
  review_alive=true
  for _ in $(seq 1 60); do
    if ! kill -0 "$review_pid" 2>/dev/null; then
      review_alive=false
      break
    fi
    review_state="$(ps -o stat= -p "$review_pid" 2>/dev/null | tr -d '[:space:]')"
    case "$review_state" in
      '' | Z*)
        review_alive=false
        break
        ;;
    esac
    sleep 0.1
  done
  if [ "$review_alive" = true ]; then
    kill -KILL "$review_pid" "$supervisor_pid" 2>/dev/null || true
  fi
  assert [ "$review_alive" = false ]
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
  sleep 30 &
  review_pid=$!
  printf "%s\\n" "$review_pid" > "$CODERABBIT_REVIEW_PID_FILE"
  trap "kill $review_pid 2>/dev/null || true; echo term >> \"$CODERABBIT_CRITIQUE_LOG\"; exit 143" TERM
  wait "$review_pid"
fi
exit 1
'
  review_pid_file="$BATS_TEST_TMPDIR/review.pid"
  export CODERABBIT_REVIEW_PID_FILE="$review_pid_file"
  export CODERABBIT_CRITIQUE_TIMEOUT=30
  export CODERABBIT_CRITIQUE_BASE=master
  output_file="$BATS_TEST_TMPDIR/outer.stdout"
  error_file="$BATS_TEST_TMPDIR/outer.stderr"

  "$SCRIPT" >"$output_file" 2>"$error_file" &
  script_pid=$!
  started=false
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if [ -s "$review_pid_file" ]; then
      started=true
      break
    fi
    sleep 0.1
  done
  assert [ "$started" = true ]

  kill -TERM "$script_pid"
  set +e
  wait "$script_pid"
  status=$?
  set -e

  assert_equal 143 "$status"
  run grep -c '^term$' "$CODERABBIT_CRITIQUE_LOG"
  # With setsid the review's isolated session receives TERM exactly once.
  # Without it, GNU timeout's own group broadcast and the wrapper's sweep of
  # that group can legitimately both reach the review, so require at least
  # one delivery there rather than an exact count.
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
  "$signal_reset_command" -e '$SIG{INT} = "DEFAULT"; exec @ARGV' "$SCRIPT" \
    >"$BATS_TEST_TMPDIR/outer-int.stdout" 2>"$BATS_TEST_TMPDIR/outer-int.stderr" &
  script_pid=$!
  started=false
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if [ -s "$review_pid_file" ]; then
      started=true
      break
    fi
    sleep 0.1
  done
  assert [ "$started" = true ]

  kill -INT "$script_pid"
  if wait "$script_pid"; then
    status=0
  else
    status=$?
  fi

  assert_equal 130 "$status"
  review_pid=$(cat "$review_pid_file")
  review_alive=true
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
    if ! kill -0 "$review_pid" 2>/dev/null; then
      review_alive=false
      break
    fi
    review_state="$(ps -o stat= -p "$review_pid" 2>/dev/null | tr -d '[:space:]')"
    case "$review_state" in
      '' | Z*)
        review_alive=false
        break
        ;;
    esac
    sleep 0.1
  done
  assert [ "$review_alive" = false ]
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

  "$signal_reset_command" -e '$SIG{HUP} = "DEFAULT"; exec @ARGV' "$SCRIPT" \
    >"$BATS_TEST_TMPDIR/outer-hup.stdout" 2>"$BATS_TEST_TMPDIR/outer-hup.stderr" &
  script_pid=$!
  started=false
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if [ -s "$review_pid_file" ]; then
      started=true
      break
    fi
    sleep 0.1
  done
  assert [ "$started" = true ]

  kill -HUP "$script_pid"
  if wait "$script_pid"; then
    status=0
  else
    status=$?
  fi

  assert_equal 129 "$status"
  review_pid=$(cat "$review_pid_file")
  review_alive=true
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
    if ! kill -0 "$review_pid" 2>/dev/null; then
      review_alive=false
      break
    fi
    review_state="$(ps -o stat= -p "$review_pid" 2>/dev/null | tr -d '[:space:]')"
    case "$review_state" in
      '' | Z*)
        review_alive=false
        break
        ;;
    esac
    sleep 0.1
  done
  assert [ "$review_alive" = false ]
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

  "$signal_reset_command" -e '$SIG{QUIT} = "DEFAULT"; exec @ARGV' "$SCRIPT" \
    >"$BATS_TEST_TMPDIR/outer-quit.stdout" 2>"$BATS_TEST_TMPDIR/outer-quit.stderr" &
  script_pid=$!
  started=false
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if [ -s "$review_pid_file" ]; then
      started=true
      break
    fi
    sleep 0.1
  done
  assert [ "$started" = true ]

  kill -QUIT "$script_pid"
  if wait "$script_pid"; then
    status=0
  else
    status=$?
  fi

  assert_equal 131 "$status"
  review_pid=$(cat "$review_pid_file")
  review_alive=true
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60; do
    if ! kill -0 "$review_pid" 2>/dev/null; then
      review_alive=false
      break
    fi
    review_state="$(ps -o stat= -p "$review_pid" 2>/dev/null | tr -d '[:space:]')"
    case "$review_state" in
      '' | Z*)
        review_alive=false
        break
        ;;
    esac
    sleep 0.1
  done
  assert [ "$review_alive" = false ]
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
# set, instead of relying on the runner that happens to run the suite. Both
# helpers overwrite the snapshot setup() took, so put it back afterwards.
stash_critique_policy_snapshot() {
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

  reinstate_critique_policy_snapshot
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
  reinstate_critique_policy_snapshot
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
