#!/usr/bin/env bats
# Tests for scripts/with-pueue.sh, the wrapper that runs one heavy command
# through the shared `dotfiles` pueue group (or directly when no queue is
# usable), and for the command strings that now go through it.
#
# The queue is a fake `pueue`/`pueued` on a curated PATH. The fake keeps its
# state in files, records every call, and runs a queued command with `sh -c`
# in the --working-directory, with PUEUE_GROUP set, only inside `wait` (as the
# real daemon runs it while the client waits; `wait` itself exits 0 even for
# a failed task, as real pueue 4.0.4 does). Any single subcommand can be made
# to fail through FAKE_PUEUE_FAIL. Every test starts with PUEUE_GROUP unset:
# once validation runs through the queue, this file itself runs inside a
# queued task, which pueue gives PUEUE_GROUP, and every queue case would
# otherwise take the direct path.
# cspell:words gsub pueued

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  WRAPPER="$REPO_ROOT/scripts/with-pueue.sh"
  BASH_BIN="$(command -v bash)"
  _ORIG_PATH="$PATH"

  # Nothing from the surrounding session may reach the wrapper.
  unset PUEUE_GROUP PUEUE_CONFIG_PATH PUEUE_WORKER_ID
  unset FAKE_PUEUE_FAIL FAKE_PUEUE_RESULT FAKE_PUEUE_WAIT_HOLD FAKE_PUEUED_MODE FAKE_PUEUE_PAUSE_AFTER_ADD FAKE_PUEUE_ADD_HOLD FAKE_PUEUE_WAIT_DELAY
  unset SANDBOX

  export HOME="$BATS_TEST_TMPDIR/home"
  PARALLELISM_FILE="$HOME/.config/dotfiles/pueue-parallelism"
  mkdir -p "$HOME/.config/dotfiles"

  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$WORK"
  MARK="$BATS_TEST_TMPDIR/command-ran"
  : > "$MARK"

  # The fake builds its JSON with this jq, whatever the wrapper can find.
  FAKE_JQ="$(command -v jq)"
  export FAKE_JQ
  export FAKE_PUEUE_STATE="$BATS_TEST_TMPDIR/fake-state"
  mkdir -p "$FAKE_PUEUE_STATE/tasks"
  : > "$FAKE_PUEUE_STATE/calls.log"
  : > "$FAKE_PUEUE_STATE/pueued-calls"
  : > "$FAKE_PUEUE_STATE/executions"
  : > "$FAKE_PUEUE_STATE/groups"

  # Fast daemon-start polling for the cases where the daemon never comes up.
  export WITH_PUEUE_START_POLLS=2
  export WITH_PUEUE_START_POLL_DELAY=0.01
  export WITH_PUEUE_POLL_DELAY=0.01

  build_safe_path
  install_fake_pueue
  use_queue_path
}

teardown() {
  export PATH="$_ORIG_PATH"
  # A test that started the wrapper in the background records its PID.
  if [ -f "$BATS_TEST_TMPDIR/wrapper.pid" ]; then
    local pid
    pid="$(cat "$BATS_TEST_TMPDIR/wrapper.pid")"
    kill "$pid" 2> /dev/null || true
  fi
  if [ -f "$FAKE_PUEUE_STATE/hold.pid" ]; then
    local hold
    hold="$(cat "$FAKE_PUEUE_STATE/hold.pid")"
    kill "$hold" 2> /dev/null || true
  fi
  # The real-daemon case sets SANDBOX; a failed assertion must not leave its
  # daemon or directory behind.
  case "${SANDBOX:-}" in
    /tmp/pq.*)
      stop_sandbox_daemon
      rm -rf -- "$SANDBOX"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

# A PATH made of symlinks to exactly the tools the wrapper and the fakes need,
# so a host that has pueue installed cannot leak it into the "absent" cases.
build_safe_path() {
  SAFE_BIN="$BATS_TEST_TMPDIR/safe-bin"
  mkdir -p "$SAFE_BIN"
  local tool tool_path
  for tool in awk basename bash cat chmod cp cut date dirname env grep head jq \
    id kill ln ls mkdir mkfifo mktemp mv od pgrep printf pwd readlink rm rmdir sed sh sleep \
    sort tail tr touch true false uname wc; do
    tool_path="$(command -v "$tool" 2> /dev/null)" || continue
    case "$tool_path" in /*) ln -sf "$tool_path" "$SAFE_BIN/$tool" ;; esac
  done
  FAKE_BIN="$BATS_TEST_TMPDIR/fake-bin"
  mkdir -p "$FAKE_BIN"
}

use_queue_path() {
  export PATH="$FAKE_BIN:$SAFE_BIN"
}

use_direct_path() {
  export PATH="$SAFE_BIN"
}

install_fake_pueue() {
  cat > "$FAKE_BIN/pueue" << 'FAKE'
#!/usr/bin/env bash
# Fake pueue 4.0.4 (see the header of with-pueue.bats).
state="$FAKE_PUEUE_STATE"
printf '%s\n' "$*" >> "$state/calls.log"

fails() {
  case ",${FAKE_PUEUE_FAIL:-}," in *",$1,"*) return 0 ;; esac
  return 1
}

daemon_up() {
  [ -e "$state/daemon-up" ]
}

list_groups() {
  printf 'Group "default" (1 parallel): running\n'
  local group
  while IFS= read -r group; do
    [ -n "$group" ] || continue
    # A vanished dotfiles group is simply not listed.
    if [ -e "$state/vanished" ] && [ "$group" = dotfiles ]; then continue; fi
    status=running
    [ ! -e "$state/paused-$group" ] || status=paused
    printf 'Group "%s" (%s parallel): %s\n' "$group" "$(cat "$state/parallel-$group" 2> /dev/null || echo 1)" "$status"
  done < "$state/groups"
  return 0
}

next_id() {
  local id=0
  while [ -e "$state/tasks/$id" ]; do id=$((id + 1)); done
  printf '%s' "$id"
}

run_task() {
  local dir="$state/tasks/$1" group cwd
  group="$(cat "$dir/group")"
  cwd="$(cat "$dir/cwd")"
  echo x >> "$state/executions"
  ( cd "$cwd" && PUEUE_GROUP="$group" sh -c "$(cat "$dir/cmd")" ) > "$dir/output" 2>&1
  echo $? > "$dir/exit"
}

case "${1:-}" in
  status)
    daemon_up || { echo "Couldn't find a configuration file." >&2; exit 1; }
    tasks='{}'
    for dir in "$state"/tasks/*/; do
      [ -d "$dir" ] || continue
      id="$(basename "$dir")"
      if fails result; then exit 1; fi
      if fails result-missing; then continue; fi
      if [ -e "$dir/exit" ] && ! fails result-running; then
        code="$(cat "$dir/exit")"
        if [ -n "${FAKE_PUEUE_RESULT:-}" ]; then
          result="$FAKE_PUEUE_RESULT"
        elif [ "$code" = 0 ]; then
          result='"Success"'
        else
          result="{\"Failed\":$code}"
        fi
        tasks="$("$FAKE_JQ" -c --arg id "$id" --arg label "$(cat "$dir/label" 2> /dev/null)" --argjson result "$result" '. + {($id): {id: ($id|tonumber), label: (if $label == "" then null else $label end), status: {Done: {result: $result}}}}' <<< "$tasks")"
      else
        tasks="$("$FAKE_JQ" -c --arg id "$id" --arg label "$(cat "$dir/label" 2> /dev/null)" '. + {($id): {id: ($id|tonumber), label: (if $label == "" then null else $label end), status: "Running"}}' <<< "$tasks")"
      fi
    done
    "$FAKE_JQ" -c -n --argjson tasks "$tasks" '{tasks: $tasks, groups: {}}'
    ;;
  group)
    daemon_up || exit 1
    case "${2:-}" in
      add)
        if fails group-add; then exit 1; fi
        if fails group-add-race; then
          echo "$3" >> "$state/groups"
          exit 1
        fi
        if grep -qx -- "$3" "$state/groups" 2> /dev/null; then
          echo "Group \"$3\" already exists" >&2
          exit 1
        fi
        echo "$3" >> "$state/groups"
        echo "New group \"$3\" has been created"
        ;;
      '')
        if [ -e "$state/flaky" ]; then
          # Every other listing fails once a task has been added.
          flaky=$(($(cat "$state/flaky-count" 2> /dev/null || echo 0) + 1))
          echo "$flaky" > "$state/flaky-count"
          [ $((flaky % 2)) -eq 0 ] || exit 1
        fi
        count=$(($(cat "$state/list-count" 2> /dev/null || echo 0) + 1))
        echo "$count" > "$state/list-count"
        if fails group-list; then exit 1; fi
        if fails group-vanish && [ "$count" -ge 2 ]; then : > "$state/vanished"; fi
        if fails group-relist && [ "$count" -ge 2 ]; then exit 1; fi
        list_groups
        ;;
      *) exit 1 ;;
    esac
    ;;
  parallel)
    daemon_up || exit 1
    if fails parallel; then exit 1; fi
    # pueue parallel <N> --group <name>
    echo "$2" > "$state/parallel-$4"
    echo "Parallel tasks setting for group \"$4\" adjusted"
    ;;
  add)
    daemon_up || exit 1
    if fails add; then exit 1; fi
    shift
    group='' cwd='' print=0 label=''
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --group) group="$2"; shift 2 ;;
        --label) label="$2"; shift 2 ;;
        --working-directory) cwd="$2"; shift 2 ;;
        --print-task-id) print=1; shift ;;
        --) shift; break ;;
        *) shift ;;
      esac
    done
    if fails add-garbage; then echo "Task added"; exit 0; fi
    if [ "${FAKE_PUEUE_ADD_HOLD:-}" = before ]; then
      # The client is stuck before the daemon has accepted anything.
      echo $$ > "$state/add.pid"
      : > "$state/adding"
      held=0
      while [ ! -e "$state/release" ] && [ "$held" -lt 300 ]; do sleep 0.05; held=$((held + 1)); done
    fi
    id="$(next_id)"
    mkdir -p "$state/tasks/$id"
    printf '%s' "$label" > "$state/tasks/$id/label"
    printf '%s' "$group" > "$state/tasks/$id/group"
    printf '%s' "$cwd" > "$state/tasks/$id/cwd"
    # pueue joins the words after -- with spaces and hands them to sh -c.
    printf '%s' "$*" > "$state/tasks/$id/cmd"
    if [ -n "${FAKE_PUEUE_PAUSE_AFTER_ADD:-}" ]; then : > "$state/paused-$group"; fi
    if fails group-flaky; then : > "$state/flaky"; fi
    if fails group-vanish-late; then : > "$state/vanished"; fi
    if [ "${FAKE_PUEUE_ADD_HOLD:-}" = after ]; then
      # The daemon has accepted the task; the client has not printed the id.
      echo $$ > "$state/add.pid"
      : > "$state/adding"
      held=0
      while [ ! -e "$state/release" ] && [ "$held" -lt 300 ]; do sleep 0.05; held=$((held + 1)); done
    fi
    # The daemon accepted the task but the client reports a failure.
    if fails add-late-fail; then exit 1; fi
    printf '%s\n' "$id"
    ;;
  start)
    daemon_up || exit 1
    if fails start; then exit 1; fi
    # Another session resumes the group at the same moment; this call fails.
    if fails start-race; then rm -f "$state/paused-$3"; exit 1; fi
    # Fails twice, then works: a hiccup, not a lasting problem.
    if fails start-twice; then
      starts=$(($(cat "$state/start-count" 2> /dev/null || echo 0) + 1))
      echo "$starts" > "$state/start-count"
      [ "$starts" -gt 2 ] || exit 1
    fi
    # pueue start --group <name>
    if fails start-vanish; then : > "$state/vanished"; fi
    rm -f "$state/paused-$3"
    printf 'Group "%s" is being resumed.\n' "$3"
    ;;
  wait)
    daemon_up || exit 1
    id="$2"
    if [ -n "${FAKE_PUEUE_WAIT_HOLD:-}" ]; then
      echo $$ > "$state/hold.pid"
      : > "$state/waiting"
      held=0
      while [ "$held" -lt 300 ]; do sleep 0.1; held=$((held + 1)); done
      exit 1
    fi
    paused_group="$(cat "$state/tasks/$id/group" 2> /dev/null)"
    hung=0
    while [ -e "$state/paused-$paused_group" ]; do
      hung=$((hung + 1))
      [ "$hung" -le 100 ] || exit 1
      sleep 0.05
    done
    [ -z "${FAKE_PUEUE_WAIT_DELAY:-}" ] || sleep "$FAKE_PUEUE_WAIT_DELAY"
    run_task "$id"
    if fails wait; then exit 1; fi
    exit 0
    ;;
  log)
    daemon_up || exit 1
    if fails log; then exit 1; fi
    if fails log-empty; then echo '{}'; exit 0; fi
    # pueue log --json --full <id>
    id="$4"
    "$FAKE_JQ" -c -n --arg id "$id" --rawfile out "$state/tasks/$id/output" '{($id): {task: {id: ($id|tonumber)}, output: $out}}'
    ;;
  kill)
    exit 0
    ;;
  remove)
    if fails remove; then exit 1; fi
    id="$2"
    if [ -d "$state/tasks/$id" ]; then
      rm -rf -- "$state/tasks/$id"
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
FAKE
  chmod +x "$FAKE_BIN/pueue"

  cat > "$FAKE_BIN/pueued" << 'FAKE'
#!/usr/bin/env bash
state="$FAKE_PUEUE_STATE"
echo "$*" >> "$state/pueued-calls"
# Collect first: writing the file here would replace fd 1 under inspection.
fds=""
for n in 0 1 2; do
  target="$(readlink "/proc/$$/fd/$n" 2> /dev/null)" || target=unknown
  fds="$fds"$(printf 'fd%s=%s' "$n" "${target:-unknown}")$'\n'
done
if { : >&3; } 2> /dev/null; then fds="${fds}fd3=open"; else fds="${fds}fd3=closed"; fi
printf '%s\n' "$fds" > "$state/pueued-fds"
# A real daemon prints a notice and, here, keeps no pipe open.
echo "Pueued is now running in the background"
case "${FAKE_PUEUED_MODE:-works}" in
  works) : > "$state/daemon-up" ;;
  fails) : ;;
esac
exit 0
FAKE
  chmod +x "$FAKE_BIN/pueued"

  # The daemon is up unless a test says otherwise.
  : > "$FAKE_PUEUE_STATE/daemon-up"
}

# A queued or direct command that records that it ran.
ran_count() {
  wc -l < "$MARK" | tr -d ' '
}

executions() {
  wc -l < "$FAKE_PUEUE_STATE/executions" | tr -d ' '
}

calls() {
  cat "$FAKE_PUEUE_STATE/calls.log"
}

pueued_calls() {
  wc -l < "$FAKE_PUEUE_STATE/pueued-calls" | tr -d ' '
}

set_parallelism_file() {
  # $1 is a printf format, so tests can write exact bytes.
  # shellcheck disable=SC2059
  printf -- "$1" > "$PARALLELISM_FILE"
}

# Run the wrapper from $WORK with the current PATH.
wrap() {
  cd "$WORK" || return 1
  run --separate-stderr "$BASH_BIN" "$WRAPPER" "$@"
}

mark_command() {
  # $1: exit status; prints the recorded marker line and the cwd.
  printf 'echo ran >> "%s"; pwd; exit %s' "$MARK" "$1"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

@test "usage: no command is a usage error" {
  wrap
  assert_failure 2
  assert_equal "$(calls)" ""
}

@test "usage: a leading -- is accepted" {
  wrap -- sh -c 'echo hi'
  assert_success
  assert_output --partial hi
}

# ---------------------------------------------------------------------------
# The rendered parallelism file
# ---------------------------------------------------------------------------

@test "parallelism: a missing file sets the group's parallelism to 2" {
  wrap sh -c 'exit 0'
  assert_success
  assert_equal "$(cat "$FAKE_PUEUE_STATE/parallel-dotfiles")" "2"
}

@test "parallelism: a valid file sets that value (with and without the newline)" {
  local content expected
  while IFS='|' read -r content expected; do
    rm -rf "$FAKE_PUEUE_STATE/parallel-dotfiles"
    set_parallelism_file "$content"
    wrap sh -c 'exit 0'
    [ "$status" -eq 0 ] || fail "$content: exit $status: $stderr"
    assert_equal "$(cat "$FAKE_PUEUE_STATE/parallel-dotfiles")" "$expected"
  done << 'ROWS'
2|2
2\n|2
3\n|3
12\n|12
10\n|10
ROWS
}

# Each row is a printf format for the file's exact bytes.
corrupt_contents() {
  cat << 'ROWS'
0\n
-1\n
2.5\n
abc\n
2\n\n
2\r\n
2 \n
 2\n
\n
007\n
1e2\n
+2\n
2\n3\n
2\0\n
ROWS
}

assert_refused_before_anything() {
  [ "$status" -eq 2 ] || fail "exit $status (stderr: $stderr)"
  assert_equal "$(ran_count)" "0"
  assert_equal "$(pueued_calls)" "0"
  assert_equal "$(calls)" ""
  [[ "$stderr" == *"refusing"* ]] || fail "no refusal message: $stderr"
}

@test "parallelism: a corrupt file is refused before the command, the daemon or the queue" {
  local content
  while IFS= read -r content; do
    : > "$MARK"
    : > "$FAKE_PUEUE_STATE/calls.log"
    rm -f "$FAKE_PUEUE_STATE/daemon-up"
    set_parallelism_file "$content"
    wrap sh -c "$(mark_command 0)"
    assert_refused_before_anything || return 1
  done < <(corrupt_contents)
}

@test "parallelism: a corrupt file is refused even when PUEUE_GROUP is already set" {
  local content
  while IFS= read -r content; do
    : > "$MARK"
    set_parallelism_file "$content"
    PUEUE_GROUP=dotfiles wrap sh -c "$(mark_command 0)"
    assert_refused_before_anything || return 1
  done < <(corrupt_contents)
}

@test "parallelism: a corrupt file is refused even when pueue is not installed" {
  use_direct_path
  local content
  while IFS= read -r content; do
    : > "$MARK"
    set_parallelism_file "$content"
    wrap sh -c "$(mark_command 0)"
    [ "$status" -eq 2 ] || fail "exit $status"
    assert_equal "$(ran_count)" "0"
  done < <(corrupt_contents)
}

@test "parallelism: a read error is reported as unreadable, not as a bad value" {
  set_parallelism_file '2\n'
  printf '#!/bin/sh\nexit 1\n' > "$FAKE_BIN/cat"
  chmod +x "$FAKE_BIN/cat"
  wrap sh -c "$(mark_command 0)"
  [ "$status" -eq 2 ] || fail "exit $status"
  [[ "$stderr" == *"unreadable"* ]] || fail "a read error was not reported as unreadable: $stderr"
  assert_equal "$(ran_count)" "0"
}

@test "parallelism: a directory, an unreadable file and a dangling symlink are refused" {
  rm -f "$PARALLELISM_FILE"
  mkdir "$PARALLELISM_FILE"
  wrap sh -c "$(mark_command 0)"
  assert_refused_before_anything
  rmdir "$PARALLELISM_FILE"

  ln -s "$BATS_TEST_TMPDIR/nowhere" "$PARALLELISM_FILE"
  wrap sh -c "$(mark_command 0)"
  assert_refused_before_anything
  rm -f "$PARALLELISM_FILE"

  # Skipped for root, which can read anything.
  if [ "$(id -u)" -ne 0 ]; then
    printf '2\n' > "$PARALLELISM_FILE"
    chmod 000 "$PARALLELISM_FILE"
    wrap sh -c "$(mark_command 0)"
    chmod 600 "$PARALLELISM_FILE"
    assert_refused_before_anything
  fi
}

# ---------------------------------------------------------------------------
# The queue path
# ---------------------------------------------------------------------------

@test "queue: enqueues on the dotfiles group, waits, and returns success" {
  wrap sh -c "$(mark_command 0)"
  assert_success
  assert_output --partial "$WORK"
  assert_equal "$(ran_count)" "1"
  run calls
  assert_line --index 0 "status --json"
  assert_line "group"
  assert_line "group add dotfiles"
  assert_line "parallel 2 --group dotfiles"
  assert_output --regexp "add --group dotfiles --working-directory $WORK --label with-pueue-[0-9]+-[0-9]+-[0-9]+ --print-task-id -- "
  assert_line "wait 0 --quiet"
}

@test "queue: the task's exit status is returned for a failing command" {
  wrap sh -c "$(mark_command 7)"
  assert_failure 7
  assert_output --partial "$WORK"
  assert_equal "$(ran_count)" "1"
}

@test "queue: the queued command runs once, in the caller's working directory" {
  mkdir -p "$WORK/sub dir"
  cd "$WORK/sub dir" || return 1
  run --separate-stderr "$BASH_BIN" "$WRAPPER" sh -c 'pwd'
  assert_success
  assert_output "$WORK/sub dir"
  assert_equal "$(executions)" "1"
}

@test "queue: the task runs with PUEUE_GROUP set, so a nested call goes direct" {
  wrap sh -c 'printf "%s" "$PUEUE_GROUP"'
  assert_success
  assert_output "dotfiles"
}

@test "queue: arguments with spaces, quotes, globs, variables and semicolons survive" {
  wrap printf '[%s]\n' 'a b' "it's" '**' '$HOME' ';echo injected' ''
  assert_success
  assert_output "$(printf '[a b]\n[it'"'"'s]\n[**]\n[$HOME]\n[;echo injected]\n[]')"
}

@test "queue: output of the task is printed once, without the status JSON" {
  wrap sh -c 'echo one; echo two >&2'
  assert_success
  assert_output "$(printf 'one\ntwo')"
  [[ "$output" != *'"tasks"'* ]] || fail "raw JSON leaked: $output"
}

@test "queue: a second invocation with the group already listed still sets parallelism and enqueues" {
  set_parallelism_file '5\n'
  wrap sh -c 'exit 0'
  assert_success
  : > "$FAKE_PUEUE_STATE/calls.log"

  set_parallelism_file '3\n'
  wrap sh -c 'exit 0'
  assert_success
  run calls
  refute_line "group add dotfiles"
  assert_line "parallel 3 --group dotfiles"
  assert_output --regexp "add --group dotfiles "
  assert_equal "$(cat "$FAKE_PUEUE_STATE/parallel-dotfiles")" "3"
}

@test "queue: the wrapper removes its own finished task and never runs pueue clean" {
  wrap sh -c 'exit 0'
  assert_success
  run calls
  assert_line "remove 0"
  refute_line --partial "clean"
}

@test "queue: a running group is never started or resumed" {
  wrap sh -c 'exit 0'
  assert_success
  run calls
  refute_line --partial "start "
}

@test "paused: a group found paused before enqueueing is resumed, with a message" {
  wrap sh -c 'exit 0'
  : > "$FAKE_PUEUE_STATE/calls.log"
  : > "$FAKE_PUEUE_STATE/paused-dotfiles"
  wrap sh -c "$(mark_command 0)"
  assert_success
  assert_equal "$(ran_count)" "1"
  [[ "$stderr" == *"not running"* ]] || fail "no message: $stderr"
  run calls
  assert_line "start --group dotfiles"
  # The wait loop would also resume it, so require the resume to come first.
  local start_line add_line
  start_line="$(grep -n -x 'start --group dotfiles' "$FAKE_PUEUE_STATE/calls.log" | head -1 | cut -d: -f1)"
  add_line="$(grep -n '^add --group' "$FAKE_PUEUE_STATE/calls.log" | head -1 | cut -d: -f1)"
  [ -n "$start_line" ] && [ -n "$add_line" ] && [ "$start_line" -lt "$add_line" ] ||
    fail "the group was not resumed before the task was added (start at $start_line, add at $add_line)"
}

@test "paused: a group paused while the task waits is resumed by the wait loop" {
  FAKE_PUEUE_PAUSE_AFTER_ADD=1 wrap sh -c "$(mark_command 0)"
  assert_success
  assert_equal "$(ran_count)" "1"
  assert_equal "$(executions)" "1"
  run calls
  assert_line "start --group dotfiles"
}

@test "paused: a group that cannot be resumed before enqueueing is not enqueued into" {
  : > "$FAKE_PUEUE_STATE/paused-dotfiles"
  FAKE_PUEUE_FAIL=start wrap sh -c "$(mark_command 0)"
  assert_failure
  local explanation="$stderr"
  assert_equal "$(ran_count)" "0"
  assert_equal "$(executions)" "0"
  run calls
  refute_output --partial "add --group"
  [[ "$explanation" == *"could not confirm"* ]] || fail "no explanation: $explanation"
}

@test "paused: a group that is missing from the listing before enqueueing stops the call" {
  FAKE_PUEUE_FAIL=group-vanish wrap sh -c "$(mark_command 0)"
  assert_failure
  assert_equal "$(ran_count)" "0"
  run calls
  refute_output --partial "add --group"
  refute_line --partial "start "
}

@test "paused: a resumed group that is not listed afterwards is not confirmed running" {
  : > "$FAKE_PUEUE_STATE/paused-dotfiles"
  FAKE_PUEUE_FAIL=start-vanish wrap sh -c "$(mark_command 0)"
  assert_failure
  assert_equal "$(ran_count)" "0"
  run calls
  refute_output --partial "add --group"
}

@test "paused: a group that disappears while the task waits makes the wrapper give up and remove its task" {
  local started=$SECONDS
  FAKE_PUEUE_FAIL=group-vanish-late FAKE_PUEUE_WAIT_DELAY=8 wrap sh -c "$(mark_command 0)"
  assert_failure
  local explanation="$stderr"
  [ $((SECONDS - started)) -lt 6 ] || fail "the wrapper waited for the task to end"
  assert_equal "$(ran_count)" "0"
  [ ! -d "$FAKE_PUEUE_STATE/tasks/0" ] || fail "the abandoned task was left in the queue"
  [[ "$explanation" == *"gave up waiting for task 0"* ]] || fail "no explanation: $explanation"
}

@test "paused: a group listing that cannot be read before enqueueing stops the call" {
  FAKE_PUEUE_FAIL=group-relist wrap sh -c "$(mark_command 0)"
  assert_failure
  assert_equal "$(ran_count)" "0"
  run calls
  refute_output --partial "add --group"
}

@test "paused: a group that cannot be resumed while waiting makes the wrapper give up and remove its task" {
  local started=$SECONDS
  FAKE_PUEUE_PAUSE_AFTER_ADD=1 FAKE_PUEUE_FAIL=start wrap sh -c "$(mark_command 0)"
  assert_failure
  local explanation="$stderr"
  [ $((SECONDS - started)) -lt 20 ] || fail "the wrapper kept waiting"
  assert_equal "$(ran_count)" "0"
  assert_equal "$(executions)" "0"
  [ ! -d "$FAKE_PUEUE_STATE/tasks/0" ] || fail "the abandoned task was left in the queue"
  run calls
  assert_line "kill 0"
  assert_line "remove 0"
  [[ "$explanation" == *"gave up waiting for task 0"* ]] || fail "no explanation: $explanation"
}

@test "paused: a failed start is judged by a fresh listing, so another session's resume counts" {
  : > "$FAKE_PUEUE_STATE/paused-dotfiles"
  FAKE_PUEUE_FAIL=start-race wrap sh -c "$(mark_command 0)"
  assert_success
  assert_equal "$(ran_count)" "1"
}

@test "paused: failed checks interleaved with good ones never add up to giving up" {
  # Every other listing fails while the task waits for about 2 s, which is
  # around ten checks: five failures in all, never three in a row.
  FAKE_PUEUE_FAIL=group-flaky FAKE_PUEUE_WAIT_DELAY=2 wrap sh -c "$(mark_command 0)"
  assert_success
  assert_equal "$(ran_count)" "1"
  assert_equal "$(executions)" "1"
}

@test "paused: two failed checks in a row while waiting are tolerated" {
  FAKE_PUEUE_PAUSE_AFTER_ADD=1 FAKE_PUEUE_FAIL=start-twice wrap sh -c "$(mark_command 0)"
  assert_success
  assert_equal "$(ran_count)" "1"
  assert_equal "$(executions)" "1"
}

@test "queue: a failed group listing exits non-zero and neither enqueues nor runs the command" {
  FAKE_PUEUE_FAIL=group-list wrap sh -c "$(mark_command 0)"
  assert_failure
  assert_equal "$(ran_count)" "0"
  run calls
  refute_output --partial "add --group"
  refute_output --partial "parallel "
}

@test "queue: a group that cannot be created exits non-zero and neither enqueues nor runs" {
  FAKE_PUEUE_FAIL=group-add wrap sh -c "$(mark_command 0)"
  assert_failure
  assert_equal "$(ran_count)" "0"
  run calls
  refute_output --partial "add --group"
}

@test "queue: a lost creation race (the group is listed afterwards) counts as success" {
  FAKE_PUEUE_FAIL=group-add-race wrap sh -c "$(mark_command 0)"
  assert_success
  assert_equal "$(ran_count)" "1"
}

@test "queue: a failing re-listing after a failed creation exits non-zero" {
  FAKE_PUEUE_FAIL=group-add,group-relist wrap sh -c "$(mark_command 0)"
  assert_failure
  assert_equal "$(ran_count)" "0"
  run calls
  refute_output --partial "add --group"
}

@test "queue: a failed parallelism update exits non-zero and neither enqueues nor runs" {
  FAKE_PUEUE_FAIL=parallel wrap sh -c "$(mark_command 0)"
  assert_failure
  assert_equal "$(ran_count)" "0"
  run calls
  refute_output --partial "add --group"
}

@test "queue: an enqueue that fails before acceptance exits non-zero and does not run directly" {
  FAKE_PUEUE_FAIL=add wrap sh -c "$(mark_command 0)"
  assert_failure
  assert_equal "$(ran_count)" "0"
  assert_equal "$(executions)" "0"
}

@test "queue: a reply that is not a task id exits non-zero and does not run" {
  FAKE_PUEUE_FAIL=add-garbage wrap sh -c "$(mark_command 0)"
  assert_failure
  assert_equal "$(ran_count)" "0"
}

@test "queue: Failed results map to 1..255, anything else to 1" {
  local result expected
  while IFS='|' read -r result expected; do
    FAKE_PUEUE_RESULT="$result" wrap sh -c 'exit 0'
    [ "$status" -eq "$expected" ] || fail "$result: expected $expected, got $status"
  done << 'ROWS'
{"Failed":42}|42
{"Failed":1}|1
{"Failed":255}|255
{"Failed":0}|1
{"Failed":256}|1
{"Failed":-1}|1
{"Failed":42.5}|1
{"Failed":1.5}|1
{"Failed":3.0}|3
"Killed"|1
"Errored"|1
{"FailedToSpawn":"boom"}|1
"Success"|0
ROWS
}

@test "queue: an unreadable result exits non-zero without a second local copy and keeps the task" {
  FAKE_PUEUE_FAIL=result wrap sh -c "$(mark_command 0)"
  assert_failure
  assert_equal "$(ran_count)" "1"
  assert_equal "$(executions)" "1"
  # Left in place so `pueue log <id>` can still show what happened.
  run calls
  refute_line "remove 0"
}

@test "queue: a state that lacks the task, or shows it unfinished, exits non-zero without a second copy" {
  local mode
  for mode in result-missing result-running; do
    : > "$MARK"
    : > "$FAKE_PUEUE_STATE/executions"
    : > "$FAKE_PUEUE_STATE/calls.log"
    rm -rf "$FAKE_PUEUE_STATE/tasks"
    mkdir -p "$FAKE_PUEUE_STATE/tasks"
    FAKE_PUEUE_FAIL=$mode wrap sh -c "$(mark_command 0)"
    [ "$status" -ne 0 ] || fail "$mode: exit 0 with output '$output'"
    assert_equal "$(ran_count)" "1"
    assert_equal "$(executions)" "1"
    # The task is left for inspection (`pueue log <id>`), not removed.
    run calls
    refute_line "remove 0"
  done
}

@test "queue: an unreadable log still returns the task's status, with a warning" {
  FAKE_PUEUE_FAIL=log wrap sh -c "$(mark_command 9)"
  assert_failure 9
  [[ "$stderr" == *"could not read the output"* ]] || fail "no warning: $stderr"
  assert_equal "$(ran_count)" "1"
}

@test "queue: a log that lacks the task still returns the status, with a warning" {
  FAKE_PUEUE_FAIL=log-empty wrap sh -c "$(mark_command 6)"
  assert_failure 6
  [[ "$stderr" == *"could not read the output"* ]] || fail "no warning: $stderr"
}

# Start the wrapper in the background with the add held (FAKE_PUEUE_ADD_HOLD is
# "before" or "after" the daemon accepted the task) and wait until it is held.
start_held_add() {
  cd "$WORK" || return 1
  FAKE_PUEUE_ADD_HOLD="$1" "$BASH_BIN" "$WRAPPER" sh -c "$(mark_command 0)" > "$BATS_TEST_TMPDIR/add.out" 2>&1 &
  echo $! > "$BATS_TEST_TMPDIR/wrapper.pid"
  local waited=0
  while [ ! -e "$FAKE_PUEUE_STATE/adding" ] && [ "$waited" -lt 100 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  [ -e "$FAKE_PUEUE_STATE/adding" ] || fail "the wrapper never reached pueue add"
}

# Wait for the held wrapper; its exit status is left in HELD_STATUS (not
# printed, because `wait` only works in the shell that started the job). A
# wrapper that has not exited after 10 s is released and killed, and reported
# as status 999, so a regression fails the test instead of hanging it.
finish_held_add() {
  local pid waited=0
  pid="$(cat "$BATS_TEST_TMPDIR/wrapper.pid")"
  while kill -0 "$pid" 2> /dev/null && [ "$waited" -lt 100 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  HELD_STATUS=0
  if kill -0 "$pid" 2> /dev/null; then
    : > "$FAKE_PUEUE_STATE/release"
    kill -KILL "$pid" 2> /dev/null || true
    HELD_STATUS=999
  fi
  local wait_status=0
  wait "$pid" || wait_status=$?
  [ "$HELD_STATUS" -eq 999 ] || HELD_STATUS=$wait_status
  rm -f "$BATS_TEST_TMPDIR/wrapper.pid"
}

@test "queue: an interrupt that also kills the add client finds the accepted task by its label" {
  start_held_add after
  # A terminal's Ctrl-C reaches the wrapper and the client in flight alike.
  kill -TERM "$(cat "$BATS_TEST_TMPDIR/wrapper.pid")"
  kill -TERM "$(cat "$FAKE_PUEUE_STATE/add.pid")" 2> /dev/null || true
  finish_held_add
  [ "$HELD_STATUS" -eq 143 ] || fail "exit $HELD_STATUS"
  [ ! -d "$FAKE_PUEUE_STATE/tasks/0" ] || fail "the accepted task was left in the queue"
  run calls
  assert_line "remove 0"
  assert_equal "$(ran_count)" "0"
  assert_equal "$(executions)" "0"
}

@test "queue: an interrupt while the add client stalls is acted on at once" {
  start_held_add after
  local started=$SECONDS
  kill -TERM "$(cat "$BATS_TEST_TMPDIR/wrapper.pid")"
  finish_held_add
  [ "$HELD_STATUS" -eq 143 ] || fail "exit $HELD_STATUS"
  [ $((SECONDS - started)) -lt 10 ] || fail "the wrapper waited for the stalled client"
  # The stalled client is stopped and the accepted task is cleaned up.
  local gone=0
  while kill -0 "$(cat "$FAKE_PUEUE_STATE/add.pid")" 2> /dev/null && [ "$gone" -lt 20 ]; do
    sleep 0.1
    gone=$((gone + 1))
  done
  ! kill -0 "$(cat "$FAKE_PUEUE_STATE/add.pid")" 2> /dev/null || fail "the stalled client outlived the wrapper"
  [ ! -d "$FAKE_PUEUE_STATE/tasks/0" ] || fail "the accepted task was left in the queue"
  assert_equal "$(ran_count)" "0"
}

@test "queue: an interrupt before the daemon accepted anything leaves nothing to remove" {
  start_held_add before
  kill -TERM "$(cat "$BATS_TEST_TMPDIR/wrapper.pid")"
  finish_held_add
  [ "$HELD_STATUS" -eq 143 ] || fail "exit $HELD_STATUS"
  assert_equal "$(ls "$FAKE_PUEUE_STATE/tasks" | wc -l | tr -d ' ')" "0"
  run calls
  refute_line --partial "remove "
  assert_equal "$(ran_count)" "0"
}

@test "queue: an add that fails after the daemon accepted the task removes it and does not run" {
  FAKE_PUEUE_FAIL=add-late-fail wrap sh -c "$(mark_command 0)"
  assert_failure
  [ ! -d "$FAKE_PUEUE_STATE/tasks/0" ] || fail "the accepted task was left in the queue"
  run calls
  assert_line "remove 0"
  assert_equal "$(ran_count)" "0"
  assert_equal "$(executions)" "0"
}

@test "queue: every task is added under a label of its own" {
  wrap sh -c 'exit 0'
  assert_success
  run calls
  assert_output --regexp "add --group dotfiles --working-directory $WORK --label with-pueue-[0-9]+-[0-9]+-[0-9]+ --print-task-id -- "
}

@test "queue: a failed wait cleans up the task and exits non-zero without a second copy" {
  FAKE_PUEUE_FAIL=wait wrap sh -c "$(mark_command 0)"
  assert_failure
  assert_equal "$(ran_count)" "1"
  assert_equal "$(executions)" "1"
  run calls
  assert_line "kill 0"
  assert_line "remove 0"
}

@test "queue: SIGTERM while waiting removes the task and exits 143" {
  cd "$WORK" || return 1
  WITH_PUEUE_POLL_DELAY=30 FAKE_PUEUE_WAIT_HOLD=1 "$BASH_BIN" "$WRAPPER" sh -c 'exit 0' > "$BATS_TEST_TMPDIR/term.out" 2>&1 &
  echo $! > "$BATS_TEST_TMPDIR/wrapper.pid"

  local waited=0
  while [ ! -e "$FAKE_PUEUE_STATE/waiting" ] && [ "$waited" -lt 100 ]; do
    sleep 0.1
    waited=$((waited + 1))
  done
  [ -e "$FAKE_PUEUE_STATE/waiting" ] || fail "the wrapper never reached wait"

  # The wrapper's own tick (a `sleep 30`) is its only direct child named sleep.
  local tick_sleep=""
  tick_sleep="$(pgrep -P "$(cat "$BATS_TEST_TMPDIR/wrapper.pid")" -x sleep | head -1)"
  [ -n "$tick_sleep" ] || fail "the wrapper has no tick sleeping"

  kill -TERM "$(cat "$BATS_TEST_TMPDIR/wrapper.pid")"
  local status=0 started=$SECONDS
  wait "$(cat "$BATS_TEST_TMPDIR/wrapper.pid")" || status=$?
  rm -f "$BATS_TEST_TMPDIR/wrapper.pid"
  [ "$status" -eq 143 ] || fail "exit $status"
  # The 30 s tick must not delay the handler, and must not outlive it.
  [ $((SECONDS - started)) -lt 10 ] || fail "the handler waited for the tick"
  local gone=0
  while kill -0 "$tick_sleep" 2> /dev/null && [ "$gone" -lt 20 ]; do
    sleep 0.1
    gone=$((gone + 1))
  done
  ! kill -0 "$tick_sleep" 2> /dev/null || fail "the tick sleep outlived the wrapper"
  run calls
  assert_line "kill 0"
  assert_line "remove 0"
  assert_equal "$(ran_count)" "0"
}

# ---------------------------------------------------------------------------
# The direct path
# ---------------------------------------------------------------------------

@test "direct: without pueue and pueued the command runs directly with its own status" {
  use_direct_path
  wrap sh -c "$(mark_command 5)"
  assert_failure 5
  assert_output --partial "$WORK"
  assert_equal "$(ran_count)" "1"

  wrap sh -c "$(mark_command 0)"
  assert_success
}

@test "direct: without jq the command runs directly" {
  rm -f "$SAFE_BIN/jq"
  wrap sh -c "$(mark_command 0)"
  assert_success
  assert_equal "$(ran_count)" "1"
  assert_equal "$(executions)" "0"
}

@test "direct: pueue without pueued runs directly" {
  rm -f "$FAKE_BIN/pueued" "$FAKE_PUEUE_STATE/daemon-up"
  wrap sh -c "$(mark_command 0)"
  assert_success
  assert_equal "$(ran_count)" "1"
  assert_equal "$(executions)" "0"
}

@test "direct: a start that makes the daemon reachable continues on the queue, with one start" {
  rm -f "$FAKE_PUEUE_STATE/daemon-up"
  wrap sh -c "$(mark_command 0)"
  assert_success
  assert_equal "$(pueued_calls)" "1"
  assert_equal "$(executions)" "1"
  assert_equal "$(ran_count)" "1"
  # The daemon's chatter never reaches the caller's output.
  [[ "$output" != *"Pueued is now running"* ]] || fail "daemon output leaked: $output"
}

@test "direct: one start attempt that leaves the daemon unreachable falls back to a direct run" {
  rm -f "$FAKE_PUEUE_STATE/daemon-up"
  FAKE_PUEUED_MODE=fails wrap sh -c "$(mark_command 4)"
  assert_failure 4
  assert_equal "$(pueued_calls)" "1"
  assert_equal "$(executions)" "0"
  assert_equal "$(ran_count)" "1"
}

@test "direct: pueued is started as a daemon with all three standard streams detached" {
  rm -f "$FAKE_PUEUE_STATE/daemon-up"
  # Start the wrapper with fd 3 open and a real terminal-less stdin, as a
  # caller that collects its output through a pipe would.
  wrap sh -c 'exit 0' 3> "$BATS_TEST_TMPDIR/fd3.out" < /dev/zero
  assert_success
  assert_equal "$(cat "$FAKE_PUEUE_STATE/pueued-calls")" "-d"
  grep -qx 'fd3=closed' "$FAKE_PUEUE_STATE/pueued-fds" || fail "fd 3 stayed open: $(cat "$FAKE_PUEUE_STATE/pueued-fds")"
  # Without /proc the target of the other three cannot be read.
  if [ -d /proc/self/fd ]; then
    local n
    for n in 0 1 2; do
      grep -qx "fd$n=/dev/null" "$FAKE_PUEUE_STATE/pueued-fds" || fail "fd $n is not /dev/null: $(cat "$FAKE_PUEUE_STATE/pueued-fds")"
    done
  fi
}

@test "direct: a Windows shell (MINGW, MSYS, CYGWIN) runs the command directly, others use the queue" {
  local name
  for name in MINGW64_NT-10.0-26100 MSYS_NT-10.0 CYGWIN_NT-10.0; do
    : > "$MARK"
    printf '#!/bin/sh\necho %s\n' "$name" > "$FAKE_BIN/uname"
    chmod +x "$FAKE_BIN/uname"
    wrap sh -c "$(mark_command 3)"
    [ "$status" -eq 3 ] || fail "$name: exit $status"
    assert_equal "$(ran_count)" "1"
    assert_equal "$(executions)" "0"
    assert_equal "$(calls)" ""
  done
  for name in Linux Darwin; do
    : > "$MARK"
    : > "$FAKE_PUEUE_STATE/executions"
    printf '#!/bin/sh\necho %s\n' "$name" > "$FAKE_BIN/uname"
    wrap sh -c "$(mark_command 0)"
    [ "$status" -eq 0 ] || fail "$name: exit $status"
    assert_equal "$(executions)" "1"
  done
}

@test "direct: PUEUE_GROUP already set runs directly even when the daemon is reachable" {
  PUEUE_GROUP=dotfiles wrap sh -c "$(mark_command 6)"
  assert_failure 6
  assert_equal "$(ran_count)" "1"
  assert_equal "$(executions)" "0"
  assert_equal "$(calls)" ""
}

@test "direct: an empty PUEUE_GROUP does not count as a queued task" {
  PUEUE_GROUP= wrap sh -c "$(mark_command 0)"
  assert_success
  assert_equal "$(executions)" "1"
}

# ---------------------------------------------------------------------------
# run-fix-validate.sh
# ---------------------------------------------------------------------------

install_fake_npx() {
  cat > "$FAKE_BIN/npx" << 'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_NPX_LOG"
n=$(wc -l < "$FAKE_NPX_LOG" | tr -d ' ')
if [ "${FAKE_NPX_FAIL_AT:-0}" = "$n" ]; then
  exit "${FAKE_NPX_FAIL_STATUS:-1}"
fi
exit 0
FAKE
  chmod +x "$FAKE_BIN/npx"
  export FAKE_NPX_LOG="$BATS_TEST_TMPDIR/npx.log"
  : > "$FAKE_NPX_LOG"
}

@test "run-fix-validate: runs the three commands in order with the glob kept literal" {
  install_fake_npx
  run --separate-stderr "$BASH_BIN" "$REPO_ROOT/scripts/run-fix-validate.sh"
  assert_success
  assert_equal "$(cat "$FAKE_NPX_LOG")" "$(printf 'markdownlint-cli2 --fix\nmarkdownlint-cli2\ncspell lint ** --no-progress')"
}

@test "run-fix-validate: stops at the first failing command and returns its status" {
  install_fake_npx
  FAKE_NPX_FAIL_AT=2 FAKE_NPX_FAIL_STATUS=9 run --separate-stderr "$BASH_BIN" "$REPO_ROOT/scripts/run-fix-validate.sh"
  assert_failure 9
  assert_equal "$(wc -l < "$FAKE_NPX_LOG" | tr -d ' ')" "2"
}

# ---------------------------------------------------------------------------
# The command strings and where they are recorded
# ---------------------------------------------------------------------------

table_cell() {
  # $1: command name; prints the cell of the Project commands table, without
  # the backticks.
  awk -F'|' -v name="$1" '
    $0 ~ /^\|/ {
      key = $2; gsub(/^[[:space:]]*\*\*|\*\*[[:space:]]*$/, "", key)
      if (key == name) {
        cell = $3; gsub(/^[[:space:]]*`|`[[:space:]]*$/, "", cell); print cell; exit
      }
    }' "$REPO_ROOT/.github/instructions/idd-overview-core.instructions.md"
}

config_command() {
  jq -r --arg name "$1" '.commands[$name]' "$REPO_ROOT/.github/idd/config.json"
}

@test "commands: each heavy validation command is one wrapper invocation" {
  assert_equal "$(config_command fix-validate)" "scripts/with-pueue.sh scripts/run-fix-validate.sh"
  assert_equal "$(config_command pre-push-validate)" "scripts/with-pueue.sh scripts/run-validate.sh"
  assert_equal "$(config_command post-fix-validate)" "scripts/with-pueue.sh scripts/run-validate.sh"
  local name
  for name in fix-validate pre-push-validate post-fix-validate; do
    case "$(config_command "$name")" in
      *'&&'* | *';'* | *'|'*) fail "$name chains commands outside the wrapper" ;;
    esac
  done
}

@test "commands: install-deps is unchanged" {
  assert_equal "$(config_command install-deps)" "git submodule update --init --recursive"
}

@test "commands: the Project commands table cells equal the config strings" {
  local name
  for name in fix-validate pre-push-validate post-fix-validate install-deps; do
    assert_equal "$(table_cell "$name")" "$(config_command "$name")"
  done
}

@test "commands: the table carries one queued-validation-commands marker with a register row" {
  local overview="$REPO_ROOT/.github/instructions/idd-overview-core.instructions.md"
  run grep -c 'dotfiles-divergence: queued-validation-commands' "$overview"
  assert_output 1
  run grep -E '^\| `queued-validation-commands` ' "$REPO_ROOT/docs/idd-policy.md"
  assert_success
  assert_output --partial "re-add it above the table"
}

@test "commands: the new scripts are executable" {
  assert_file_executable "$WRAPPER"
  assert_file_executable "$REPO_ROOT/scripts/run-fix-validate.sh"
}

@test "commands: only idd-overview-core mentions pueue under .github/instructions" {
  run grep -ril 'pueue' "$REPO_ROOT/.github/instructions"
  assert_success
  assert_output "$REPO_ROOT/.github/instructions/idd-overview-core.instructions.md"
}

@test "commands: no command string names the tool that idd-doctor flagged as toolchain residue" {
  local name
  for name in fix-validate pre-push-validate post-fix-validate install-deps; do
    [[ "$(config_command "$name")" != *markdownlint-cli2* ]] || fail "config.json $name still names markdownlint-cli2"
    [[ "$(table_cell "$name")" != *markdownlint-cli2* ]] || fail "the Project commands table $name still names markdownlint-cli2"
  done
}

# ---------------------------------------------------------------------------
# A real pueue, when the binaries are on PATH (skipped otherwise, unless
# REQUIRE_REAL_PUEUE asks for the case, as the CI job does)
# ---------------------------------------------------------------------------

# True when REQUIRE_REAL_PUEUE makes the real-daemon case mandatory: any value
# but empty or 0. CI sets it, so a runner that lost the binaries fails instead
# of reporting a skip; a developer machine without pueue leaves it unset.
real_pueue_required() {
  case "${REQUIRE_REAL_PUEUE:-}" in
    '' | 0) return 1 ;;
  esac
  return 0
}

# $@ are the pueue binaries missing from the original PATH. Skip the case, or
# fail naming them when it is mandatory. Call it directly, never inside
# $(...): skip and fail have to reach the test's own shell.
missing_real_pueue() {
  if real_pueue_required; then
    fail "REQUIRE_REAL_PUEUE is set, but missing from PATH: $*"
    return
  fi
  skip "not installed: $*"
}

# Run the wrapper against the sandbox daemon. $1: expected exit status, the
# rest: the command. The wrapper's output goes through a FIFO read by a
# recorded cat: a daemon that inherited the write end would keep the FIFO open
# after the wrapper exits, so cat would never end, which is the hang a caller
# reading the output with $(...) would suffer.
real_run() {
  local expected="$1"
  shift
  local sandbox="$SANDBOX" status_code=0 waited=0
  rm -f "$sandbox/fifo" "$sandbox/out"
  mkfifo "$sandbox/fifo"
  cat "$sandbox/fifo" > "$sandbox/out" &
  local cat_pid=$!
  (
    cd "$WORK" || exit 1
    HOME="$sandbox/home" XDG_CONFIG_HOME="$sandbox/config" XDG_DATA_HOME="$sandbox/data" \
      XDG_RUNTIME_DIR="$sandbox/runtime" \
      "$BASH_BIN" "$WRAPPER" "$@" > "$sandbox/fifo" 2> "$sandbox/err"
  ) || status_code=$?
  while kill -0 "$cat_pid" 2> /dev/null; do
    if [ "$waited" -ge 40 ]; then
      kill "$cat_pid" 2> /dev/null || true
      stop_sandbox_daemon
      rm -rf -- "$sandbox"
      fail "the daemon kept the wrapper's output pipe open"
    fi
    sleep 0.25
    waited=$((waited + 1))
  done
  if [ "$status_code" -ne "$expected" ]; then
    cat "$sandbox/err" >&2
    stop_sandbox_daemon
    rm -rf -- "$sandbox"
    fail "expected status $expected, got $status_code"
  fi
}

# Stop the sandbox daemon by the PID it recorded, never by name.
stop_sandbox_daemon() {
  local daemon_pid="" waited=0
  [ -f "$SANDBOX/runtime/pueue.pid" ] && daemon_pid="$(cat "$SANDBOX/runtime/pueue.pid")"
  [ -n "$daemon_pid" ] || return 0
  kill "$daemon_pid" 2> /dev/null || true
  while kill -0 "$daemon_pid" 2> /dev/null && [ "$waited" -lt 40 ]; do
    sleep 0.25
    waited=$((waited + 1))
  done
}

@test "real pueue: runs through a real daemon, creates the group, and updates its parallelism" {
  local pueue_bin pueued_bin missing=()
  pueue_bin="$(PATH="$_ORIG_PATH" command -v pueue)" || missing+=(pueue)
  pueued_bin="$(PATH="$_ORIG_PATH" command -v pueued)" || missing+=(pueued)
  if [ "${#missing[@]}" -gt 0 ]; then
    missing_real_pueue "${missing[@]}"
  fi

  # The fake-daemon cases above shorten these waits to milliseconds. A real
  # daemon needs the wrapper's own defaults to come up, or a slow runner would
  # take the direct path and prove nothing.
  unset WITH_PUEUE_START_POLLS WITH_PUEUE_START_POLL_DELAY WITH_PUEUE_POLL_DELAY

  # A short path: a unix socket path must fit in SUN_LEN.
  SANDBOX="$(mktemp -d /tmp/pq.XXXXXX)"
  mkdir -p "$SANDBOX/home/.config/dotfiles" "$SANDBOX/config" "$SANDBOX/data" "$SANDBOX/runtime"
  chmod 700 "$SANDBOX/runtime"
  ln -sf "$pueue_bin" "$SAFE_BIN/pueue"
  ln -sf "$pueued_bin" "$SAFE_BIN/pueued"
  use_direct_path

  # First call: the daemon is started, the group is created with 3 slots.
  printf '3\n' > "$SANDBOX/home/.config/dotfiles/pueue-parallelism"
  real_run 4 sh -c 'echo "group=$PUEUE_GROUP"; pwd; exit 4'
  # A direct fallback would not set PUEUE_GROUP, so this proves the queue ran it.
  run cat "$SANDBOX/out"
  assert_line "group=dotfiles"
  assert_line "$WORK"
  [ -f "$SANDBOX/runtime/pueue.pid" ] || {
    rm -rf -- "$SANDBOX"
    fail "no daemon was started, so nothing was queued"
  }
  local listing
  listing="$(HOME="$SANDBOX/home" XDG_CONFIG_HOME="$SANDBOX/config" XDG_DATA_HOME="$SANDBOX/data" XDG_RUNTIME_DIR="$SANDBOX/runtime" pueue group 2>&1)"
  [[ "$listing" == *'Group "dotfiles" (3 parallel)'* ]] || {
    stop_sandbox_daemon
    rm -rf -- "$SANDBOX"
    fail "unexpected group listing: $listing"
  }

  # Second call: the group is already listed, the new value is applied.
  printf '4\n' > "$SANDBOX/home/.config/dotfiles/pueue-parallelism"
  real_run 0 sh -c 'echo "group=$PUEUE_GROUP"'
  run cat "$SANDBOX/out"
  assert_line "group=dotfiles"
  listing="$(HOME="$SANDBOX/home" XDG_CONFIG_HOME="$SANDBOX/config" XDG_DATA_HOME="$SANDBOX/data" XDG_RUNTIME_DIR="$SANDBOX/runtime" pueue group 2>&1)"
  [[ "$listing" == *'Group "dotfiles" (4 parallel)'* ]] || {
    stop_sandbox_daemon
    rm -rf -- "$SANDBOX"
    fail "the parallelism was not updated: $listing"
  }

  # The wrapper removed its own finished tasks.
  local tasks
  tasks="$(HOME="$SANDBOX/home" XDG_CONFIG_HOME="$SANDBOX/config" XDG_DATA_HOME="$SANDBOX/data" XDG_RUNTIME_DIR="$SANDBOX/runtime" pueue status --json | jq -c '.tasks')"
  stop_sandbox_daemon
  rm -rf -- "$SANDBOX"
  assert_equal "$tasks" "{}"
}

# The two helpers above decide between skipping and failing the real-daemon
# case. They get cases of their own, named so that the 'real pueue' filter
# still selects only the daemon case.
@test "REQUIRE_REAL_PUEUE: unset, empty and 0 leave the real-daemon case optional" {
  unset REQUIRE_REAL_PUEUE
  run real_pueue_required
  assert_failure
  REQUIRE_REAL_PUEUE= run real_pueue_required
  assert_failure
  REQUIRE_REAL_PUEUE=0 run real_pueue_required
  assert_failure
}

@test "REQUIRE_REAL_PUEUE: any other value makes the real-daemon case mandatory" {
  local value
  for value in 1 true 00 yes; do
    REQUIRE_REAL_PUEUE="$value" run real_pueue_required
    assert_success
  done
}

@test "REQUIRE_REAL_PUEUE: a mandatory case fails and names every missing binary" {
  REQUIRE_REAL_PUEUE=1 run missing_real_pueue pueue pueued
  assert_failure
  assert_output --partial "REQUIRE_REAL_PUEUE is set"
  assert_output --partial "pueue pueued"
}
