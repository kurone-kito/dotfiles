#!/usr/bin/env bash
# Run one heavy command through the shared pueue queue, or directly when no
# queue is usable, and return its exit status.
#
# Usage: scripts/with-pueue.sh [--] <command> [args...]
#
# Concurrent sessions on one host overlap on heavy validation. The `dotfiles`
# pueue group serializes them; how many tasks it runs at once comes from the
# one-line file chezmoi renders to ~/.config/dotfiles/pueue-parallelism (2
# when the file is missing). See docs/pueue-validation-queue.md.
#
# Order of decisions:
#   1. A rendered parallelism file that is not one positive whole number
#      (plus at most one trailing newline) is refused with status 2, before
#      anything else runs, whatever else is true.
#   2. A non-empty PUEUE_GROUP means this call is already inside a queued
#      task (pueue sets it): run the command directly, so a nested call never
#      takes another slot.
#   3. Without pueue, pueued or jq, on a Windows shell (MINGW, MSYS, CYGWIN:
#      pueue runs a task through PowerShell there, not through a POSIX sh, so
#      the quoted command line below would not mean what it says), or when
#      one start attempt of the daemon leaves it unreachable, run the command
#      directly.
#   4. Otherwise create the `dotfiles` group when it is not listed, set its
#      parallelism, enqueue the command in the caller's working directory,
#      wait, print the task's output and return the task's exit status. The
#      group is dedicated to this wrapper, so while it waits the wrapper
#      resumes the group when it finds it paused (pueue can pause a group
#      after a failed task); otherwise one failed validation would leave
#      every queued one waiting forever. A group that cannot be confirmed
#      running stops the call (before the enqueue) or, after three checks in
#      a row, the wait (the task is then removed).
#      Every failure before the daemon accepts the task exits non-zero and
#      runs nothing; once it has accepted the task the command is never
#      started a second time locally.
#
# The default group and the user's pueue.yml are never changed.
#
# Test knobs (not part of the interface): WITH_PUEUE_START_POLLS and
# WITH_PUEUE_START_POLL_DELAY bound the wait for a freshly started daemon;
# WITH_PUEUE_POLL_DELAY is the tick of the wait loop (the group is checked
# every 20 ticks).

set -u

group_name=dotfiles
parallelism_file="${HOME:-}/.config/dotfiles/pueue-parallelism"
start_polls="${WITH_PUEUE_START_POLLS:-20}"
start_poll_delay="${WITH_PUEUE_START_POLL_DELAY:-0.25}"
poll_delay="${WITH_PUEUE_POLL_DELAY:-0.5}"
resume_every=20
max_group_failures=3

task_id=""
task_label=""
wait_pid=""
tick_pid=""
add_pid=""
add_error=""
add_out=""

say() {
  printf 'with-pueue: %s\n' "$*" >&2
}

die() {
  local status="$1"
  shift
  say "$*"
  exit "$status"
}

# Print the validated parallelism (2 when the file is missing); status 1 and a
# message on stderr when the file is not acceptable. Runs in a subshell with
# the C locale so the byte count below does not depend on the caller's locale.
read_parallelism() (
  LC_ALL=C
  local path="$parallelism_file" content size nl=$'\n'

  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    printf '2\n'
    return 0
  fi
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then
    say "refusing $path: not a readable regular file"
    return 1
  fi

  # Read byte-exactly: command substitution alone would drop every trailing
  # newline, so a second one would pass.
  content=$(cat -- "$path" && printf x) || {
    say "refusing $path: unreadable"
    return 1
  }
  content=${content%x}

  # A NUL byte cannot live in a shell variable, so compare the byte counts.
  size=$(wc -c < "$path") || return 1
  size=${size//[[:space:]]/}
  if [ "${#content}" -ne "$size" ]; then
    say "refusing $path: contains a NUL byte"
    return 1
  fi

  case $content in
    *"$nl") content=${content%"$nl"} ;;
  esac
  case $content in
    '' | *[!0-9]* | 0*)
      say "refusing $path: expected one positive whole number and at most one trailing newline"
      return 1
      ;;
  esac
  printf '%s\n' "$content"
)

# Single-quote one argument for a POSIX shell (not printf %q, whose $'..'
# form a plain sh may not parse).
shell_quote() {
  local rest="$1" out="'" quote="'"
  while [[ $rest == *"$quote"* ]]; do
    out+="${rest%%"$quote"*}'\\''"
    rest=${rest#*"$quote"}
  done
  out+="$rest'"
  printf '%s' "$out"
}

queue_reachable() {
  pueue status --json > /dev/null 2>&1
}

# Best effort: stop the task so an interrupted call does not leave it holding
# a slot.
kill_task() {
  [ -n "$task_id" ] || return 0
  pueue kill "$task_id" > /dev/null 2>&1
  return 0
}

# Best effort: take the task out of the queue. A task that is still being
# killed cannot be removed yet, and a daemon may reconnect a moment late, so
# retry briefly. pueue keeps the caller's environment in a task until it is
# removed, so a task that stays is named in a warning.
remove_task() {
  [ -n "$task_id" ] || return 0
  for _ in 1 2 3 4 5; do
    pueue remove "$task_id" > /dev/null 2>&1 && return 0
    sleep 0.2
  done
  say "could not remove task $task_id; it keeps the captured environment until 'pueue remove $task_id' is run"
  return 0
}

# The id of the task the daemon accepted under this call's unique label, found
# in the queue state. Used when the client that should have printed the id
# died, was interrupted, or failed after the daemon had already accepted the
# task. A task accepted a moment ago may not show yet, so look a few times.
find_task_by_label() {
  local found
  [ -n "$task_label" ] || return 1
  for _ in 1 2 3; do
    found=$(pueue status --json 2> /dev/null |
      jq -r --arg label "$task_label" '[.tasks[] | select(.label == $label) | .id][0] // empty' 2> /dev/null) || found=""
    if [ -n "$found" ]; then
      printf '%s' "$found"
      return 0
    fi
    sleep 0.2
  done
  return 1
}

cleanup_temp_files() {
  [ -z "$add_error" ] || [ "$add_error" = /dev/null ] || rm -f -- "$add_error"
  [ -z "$add_out" ] || rm -f -- "$add_out"
  add_error=""
  add_out=""
}

# shellcheck disable=SC2329 # invoked through the traps set in main
on_signal() {
  local status="$1"
  [ -z "$wait_pid" ] || kill "$wait_pid" > /dev/null 2>&1
  [ -z "$tick_pid" ] || kill "$tick_pid" > /dev/null 2>&1
  [ -z "$add_pid" ] || kill "$add_pid" > /dev/null 2>&1
  if [ -z "$task_id" ]; then
    # Interrupted before the id arrived: the daemon may still have accepted it.
    task_id=$(find_task_by_label) || task_id=""
  fi
  kill_task
  remove_task
  cleanup_temp_files
  exit "$status"
}

# True when the group listing on stdin shows the dotfiles group paused.
group_is_paused() {
  grep -q "^Group \"$group_name\" .*: paused"
}

# Succeeds only when the group is known to be running: it was, or it was
# paused and has been resumed. The group is dedicated to this wrapper and a
# task waits forever in a paused group, so resume it (pueue pauses a group
# after a failed task when daemon.pause_group_on_failure is on). The result of
# the start is never trusted: another session may have resumed the group at
# the same moment, so a fresh listing decides. A listing that cannot be read
# counts as not confirmed.
ensure_group_running() {
  local listing
  listing=$(pueue group 2> /dev/null) || return 1
  printf '%s\n' "$listing" | group_is_paused || return 0
  say "the pueue group $group_name is paused; resuming it"
  pueue start --group "$group_name" > /dev/null 2>&1
  for _ in 1 2 3; do
    listing=$(pueue group 2> /dev/null) && ! printf '%s\n' "$listing" | group_is_paused && return 0
    sleep 0.2
  done
  return 1
}

# Map pueue's task result to an exit status; "unreadable" when it is not Done.
task_exit_status() {
  jq -r --arg id "$1" '
    (.tasks[$id].status.Done.result) as $result
    | if $result == null then "unreadable"
      elif $result == "Success" then "0"
      elif ($result | type) == "object" and ($result.Failed | type) == "number"
        and $result.Failed >= 1 and $result.Failed <= 255
        and $result.Failed == ($result.Failed | floor)
      then ($result.Failed | floor | tostring)
      else "1"
      end'
}

main() {
  local parallelism status_json exit_status log_json listing

  if [ "${1:-}" = "--" ]; then
    shift
  fi
  if [ "$#" -eq 0 ]; then
    say "usage: with-pueue.sh [--] <command> [args...]" >&2
    exit 2
  fi

  parallelism=$(read_parallelism) || exit 2

  if [ -n "${PUEUE_GROUP:-}" ]; then
    exec "$@"
  fi
  if ! command -v pueue > /dev/null 2>&1 ||
    ! command -v pueued > /dev/null 2>&1 ||
    ! command -v jq > /dev/null 2>&1; then
    exec "$@"
  fi
  case $(uname -s 2> /dev/null) in
    MINGW* | MSYS* | CYGWIN*) exec "$@" ;;
  esac

  if ! queue_reachable; then
    # One start attempt. Its exit status says nothing about reachability, and
    # the daemon would keep this call's output pipe open, so cut all three.
    pueued -d < /dev/null > /dev/null 2>&1 3>&-
    local poll=0
    while [ "$poll" -lt "$start_polls" ]; do
      queue_reachable && break
      sleep "$start_poll_delay"
      poll=$((poll + 1))
    done
    if ! queue_reachable; then
      exec "$@"
    fi
  fi

  listing=$(pueue group 2> /dev/null) || die 1 "could not list the pueue groups; not running the command"
  if ! printf '%s\n' "$listing" | grep -q "^Group \"$group_name\" "; then
    if ! pueue group add "$group_name" > /dev/null 2>&1; then
      # A concurrent session may have created it first. Decide from a fresh
      # listing; the rejection text is never parsed.
      listing=$(pueue group 2> /dev/null) || die 1 "could not create the pueue group $group_name; not running the command"
      printf '%s\n' "$listing" | grep -q "^Group \"$group_name\" " ||
        die 1 "could not create the pueue group $group_name; not running the command"
    fi
  fi

  pueue parallel "$parallelism" --group "$group_name" > /dev/null 2>&1 ||
    die 1 "could not set the parallelism of the pueue group $group_name to $parallelism; not running the command"

  ensure_group_running ||
    die 1 "could not confirm that the pueue group $group_name is running; not running the command"

  local command_line="" argument
  for argument in "$@"; do
    command_line+=" $(shell_quote "$argument")"
  done
  command_line=${command_line# }

  # Handlers first. The client runs in the background and is waited for with
  # the builtin, so a signal is acted on at once even when the client stalls.
  # The task carries a unique label: if the client dies, is interrupted, or
  # fails after the daemon accepted the task, the task is found by its label
  # instead of being stranded.
  trap 'on_signal 130' INT
  trap 'on_signal 143' TERM
  trap 'on_signal 129' HUP
  add_error=$(mktemp "${TMPDIR:-/tmp}/with-pueue.XXXXXX") || add_error=/dev/null
  add_out=$(mktemp "${TMPDIR:-/tmp}/with-pueue.XXXXXX") || {
    cleanup_temp_files
    die 1 "could not create a temporary file; not running the command"
  }
  task_label="with-pueue-$$-$(date +%s)-$RANDOM"
  pueue add --group "$group_name" --working-directory "$PWD" --label "$task_label" --print-task-id -- "$command_line" > "$add_out" 2> "$add_error" &
  add_pid=$!
  wait "$add_pid"
  local add_status=$?
  add_pid=""
  task_id=$(cat -- "$add_out" 2> /dev/null)
  case $task_id in
    '' | *[!0-9]*) task_id="" ;;
  esac
  if [ "$add_status" -ne 0 ] || [ -z "$task_id" ]; then
    [ "$add_error" = /dev/null ] || cat -- "$add_error" >&2
    # A daemon that accepted the task before the client failed still owns it.
    task_id=$(find_task_by_label) || task_id=""
    kill_task
    remove_task
    cleanup_temp_files
    die 1 "could not enqueue the command; not running it"
  fi
  cleanup_temp_files

  # From here on the daemon owns the task: never run the command locally.
  pueue wait "$task_id" --quiet > /dev/null 2>&1 &
  wait_pid=$!
  # The tick runs in the background and is waited for with the builtin, so a
  # trapped signal is acted on at once instead of after the sleep.
  local tick=0 group_failures=0
  while kill -0 "$wait_pid" > /dev/null 2>&1; do
    sleep "$poll_delay" &
    tick_pid=$!
    wait "$tick_pid" > /dev/null 2>&1
    tick_pid=""
    tick=$((tick + 1))
    if [ $((tick % resume_every)) -eq 0 ]; then
      if ensure_group_running; then
        group_failures=0
      else
        # One failed check may be a hiccup; several in a row mean the task
        # may never run, so give up instead of waiting forever.
        group_failures=$((group_failures + 1))
        if [ "$group_failures" -ge "$max_group_failures" ]; then
          kill "$wait_pid" > /dev/null 2>&1
          wait_pid=""
          kill_task
          remove_task
          die 1 "could not keep the pueue group $group_name running; gave up waiting for task $task_id"
        fi
      fi
    fi
  done
  wait "$wait_pid"
  local wait_status=$?
  wait_pid=""
  if [ "$wait_status" -ne 0 ]; then
    kill_task
    remove_task
    die 1 "waiting for task $task_id failed"
  fi

  status_json=$(pueue status --json 2> /dev/null) || die 1 "could not read the state of task $task_id"
  exit_status=$(printf '%s' "$status_json" | task_exit_status "$task_id") || exit_status=unreadable
  status_json=""
  if [ "$exit_status" = unreadable ]; then
    die 1 "could not read the result of task $task_id"
  fi

  if log_json=$(pueue log --json --full "$task_id" 2> /dev/null) &&
    printf '%s' "$log_json" | jq -j --arg id "$task_id" '
      if (.[$id].output | type) == "string" then .[$id].output else error("no output") end'; then
    :
  else
    say "could not read the output of task $task_id"
  fi

  remove_task
  exit "$exit_status"
}

main "$@"
