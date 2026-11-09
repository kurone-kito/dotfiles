#!/usr/bin/env bats
# Tests for the Neovim core options (home/dot_config/nvim/lua/options.lua).
# On WSL the win32yank clipboard provider must be selected before the
# clipboard option is set, so Neovim does not run the blocking `xsel -o -b`
# probe during startup.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  OPTIONS_LUA="$BATS_TEST_DIRNAME/../../home/dot_config/nvim/lua/options.lua"
  NVIM_BIN="$(command -v nvim 2> /dev/null || true)"
  ORIG_PATH="$PATH"
  XSEL_PIDFILE="$BATS_TEST_TMPDIR/xsel.pids"
  PIDS_FILE="$BATS_TEST_TMPDIR/pids"
  PROBE_LUA="$BATS_TEST_TMPDIR/probe.lua"
  INIT_LUA="$BATS_TEST_TMPDIR/init-wsl.lua"
  STARTED_FILE="$BATS_TEST_TMPDIR/started"
  EMPTY_BIN="$BATS_TEST_TMPDIR/empty-bin"
  XSEL_BIN="$BATS_TEST_TMPDIR/xsel-bin"
  WIN_BIN="$BATS_TEST_TMPDIR/win-bin"
  WORK_DIR="$BATS_TEST_TMPDIR/work"
  TMUX_LABEL=""
  TMUX_PANE_PID=""
  export XSEL_PIDFILE
  mkdir -p "$EMPTY_BIN" "$XSEL_BIN" "$WIN_BIN" "$WORK_DIR"
  : > "$XSEL_PIDFILE"
  : > "$PIDS_FILE"
  # Each PATH holds only the tools a case needs, so nothing under /usr/bin
  # (for example a real xclip, which Neovim tries first) can change the probe.
  link_core_tools "$EMPTY_BIN"
  link_core_tools "$XSEL_BIN"
  write_blocking_xsel "$XSEL_BIN/xsel"
  link_core_tools "$WIN_BIN"
  write_blocking_xsel "$WIN_BIN/xsel"
  write_fake_win32yank "$WIN_BIN/win32yank.exe"
  write_headless_probe
  write_init_wrapper
}

teardown() {
  if [ -n "$TMUX_PANE_PID" ]; then
    process_tree "$TMUX_PANE_PID" >> "$PIDS_FILE" 2> /dev/null || true
  fi
  if [ -n "$TMUX_LABEL" ]; then
    env -u TMUX tmux -L "$TMUX_LABEL" kill-server > /dev/null 2>&1 || true
  fi
  stop_recorded_pids
  export PATH="$ORIG_PATH"
}

require_nvim() {
  [ -n "$NVIM_BIN" ] || skip "nvim not available"
}

require_tui() {
  require_nvim
  command -v tmux > /dev/null 2>&1 || skip "tmux not available"
}

# Fake xsel: records its PID, then blocks like the WSL probe does. It exits
# on its own after a bounded time, and teardown stops it by recorded PID.
write_blocking_xsel() {
  cat > "$1" << 'SH'
#!/bin/sh
printf '%s\n' "$$" >> "$XSEL_PIDFILE"
i=0
while [ "$i" -lt 20 ]; do
  sleep 1
  i=$((i + 1))
done
exit 1
SH
  chmod +x "$1"
}

write_fake_win32yank() {
  printf '%s\n' '#!/bin/sh' 'exit 0' > "$1"
  chmod +x "$1"
}

# link_core_tools <dir>: give a test PATH the shell and sleep the probe needs.
link_core_tools() {
  ln -s "$(command -v sh)" "$1/sh"
  ln -s "$(command -v sleep)" "$1/sleep"
}

# win32yank_on_path <path>: succeed only when win32yank.exe resolves on <path>.
win32yank_on_path() {
  bash -c 'export PATH="$1"; command -v win32yank.exe > /dev/null 2>&1' _ "$1"
}

# Headless probe: forces vim.fn.has('wsl') to NVIM_TEST_WSL, then loads
# options.lua with vim.opt wrapped so that the g:clipboard value is recorded
# at the moment clipboard is assigned (ordering). The OptionSet autocmd is
# not used because it does not fire for these assignments in this build.
# The final state is written to NVIM_TEST_OUT.
write_headless_probe() {
  cat > "$PROBE_LUA" << 'LUA'
local wsl = tonumber(os.getenv("NVIM_TEST_WSL") or "0")
local real_has = vim.fn.has
vim.fn.has = function(feature)
  if feature == "wsl" then
    return wsl
  end
  return real_has(feature)
end
local seen = {}
local real_opt = vim.opt
vim.opt = setmetatable({}, {
  __index = real_opt,
  __newindex = function(_, key, value)
    if key == "clipboard" then
      seen[#seen + 1] = tostring(vim.g.clipboard)
    end
    real_opt[key] = value
  end,
})
dofile(os.getenv("NVIM_TEST_OPTIONS"))
vim.opt = real_opt
vim.fn.writefile({
  "g:clipboard=" .. tostring(vim.g.clipboard),
  "clipboard=" .. vim.o.clipboard,
  "seen=" .. table.concat(seen, ","),
}, os.getenv("NVIM_TEST_OUT"))
LUA
}

# TUI init wrapper: stubs has('wsl') to 1, loads options.lua, then writes the
# start marker. The marker means options.lua finished without blocking.
write_init_wrapper() {
  cat > "$INIT_LUA" << 'LUA'
local real_has = vim.fn.has
vim.fn.has = function(feature)
  if feature == "wsl" then
    return 1
  end
  return real_has(feature)
end
dofile(os.getenv("NVIM_TEST_OPTIONS"))
vim.fn.writefile({ "started" }, os.getenv("NVIM_TEST_STARTED"))
LUA
}

# run_headless_options <wsl> <path> <display>: run options.lua in headless
# nvim. An empty <display> leaves DISPLAY unset. Result lines go to
# $RESULT_FILE.
run_headless_options() {
  local wsl="$1" path="$2" display="$3" display_arg=() timeout_cmd
  timeout_cmd="$(command -v timeout || command -v gtimeout || true)"
  [ -n "$timeout_cmd" ] || skip "timeout or gtimeout is unavailable"
  RESULT_FILE="$BATS_TEST_TMPDIR/result-$wsl-$RANDOM.txt"
  if [ -n "$display" ]; then
    display_arg=("DISPLAY=$display")
  fi
  run "$timeout_cmd" 15 env -u WAYLAND_DISPLAY -u TMUX -u DISPLAY "${display_arg[@]}" \
    PATH="$path" NVIM_TEST_WSL="$wsl" NVIM_TEST_OPTIONS="$OPTIONS_LUA" \
    NVIM_TEST_OUT="$RESULT_FILE" \
    "$NVIM_BIN" --headless -n -i NONE -u NONE -c "luafile $PROBE_LUA" -c 'qa!'
}

# start_tui <path> <nvim args...>: start nvim in a private tmux session on a
# unique socket label, with PATH=<path> and DISPLAY=:0. The pane PID is kept
# for the process-tree checks and for teardown.
start_tui() {
  local path="$1" runner="$BATS_TEST_TMPDIR/run-nvim.sh" arg
  shift
  TMUX_LABEL="idd704-$$-${BATS_TEST_NUMBER:-0}"
  {
    printf '#!/bin/sh\n'
    printf 'unset TMUX WAYLAND_DISPLAY\n'
    printf 'export PATH=%q DISPLAY=:0 XSEL_PIDFILE=%q NVIM_TEST_OPTIONS=%q NVIM_TEST_STARTED=%q\n' \
      "$path" "$XSEL_PIDFILE" "$OPTIONS_LUA" "$STARTED_FILE"
    printf 'cd %q || exit 1\n' "$WORK_DIR"
    printf 'exec %q' "$NVIM_BIN"
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  } > "$runner"
  chmod +x "$runner"
  env -u TMUX tmux -L "$TMUX_LABEL" -f /dev/null new-session -d -s probe \
    -x 120 -y 40 "$runner"
  TMUX_PANE_PID="$(env -u TMUX tmux -L "$TMUX_LABEL" display-message -p \
    -t probe:0.0 '#{pane_pid}')"
  printf '%s\n' "$TMUX_PANE_PID" >> "$PIDS_FILE"
}

# wait_for_file <path> <tenths>: poll for a file, bounded by tenths of a
# second.
wait_for_file() {
  local tries=0
  while [ ! -e "$1" ] && [ "$tries" -lt "$2" ]; do
    sleep 0.1
    tries=$((tries + 1))
  done
  [ -e "$1" ]
}

# process_tree <pid>: print <pid> and all of its descendants.
process_tree() {
  local child
  printf '%s\n' "$1"
  for child in $(ps -eo pid=,ppid= | awk -v p="$1" '$2 == p { print $1 }'); do
    process_tree "$child"
  done
}

# probe_pids <root>: print the PIDs in the tree of <root> whose argument list
# contains the blocking xsel probe.
probe_pids() {
  local pid args
  for pid in $(process_tree "$1"); do
    args="$(ps -o args= -p "$pid" 2> /dev/null || true)"
    case "$args" in
      *'xsel -o -b'*) printf '%s\n' "$pid" ;;
    esac
  done
}

# assert_no_probe_window <root>: sample the tree of <root> at 0.1 s steps for
# 2 seconds and fail on the first sample that shows the xsel probe. A single
# sample could miss a probe that starts shortly after the marker.
assert_no_probe_window() {
  local i=0 found
  while [ "$i" -le 20 ]; do
    found="$(probe_pids "$1")"
    if [ -n "$found" ]; then
      echo "xsel probe present in the process tree at sample $i: $found" >&2
      return 1
    fi
    sleep 0.1
    i=$((i + 1))
  done
}

# stop_recorded_pids: SIGTERM, then SIGKILL, for PIDs this test recorded.
stop_recorded_pids() {
  local file pid
  for file in "$PIDS_FILE" "$XSEL_PIDFILE"; do
    [ -s "$file" ] || continue
    while IFS= read -r pid; do
      if [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null; then
        kill -TERM "$pid" 2> /dev/null || true
      fi
    done < "$file"
  done
  sleep 1
  for file in "$PIDS_FILE" "$XSEL_PIDFILE"; do
    [ -s "$file" ] || continue
    while IFS= read -r pid; do
      if [ -n "$pid" ] && kill -0 "$pid" 2> /dev/null; then
        kill -KILL "$pid" 2> /dev/null || true
      fi
    done < "$file"
  done
}

# ---------------------------------------------------------------------------
# Headless: option values, ordering, and the WSL / non-WSL split (AC1, AC2)
# ---------------------------------------------------------------------------

@test "WSL selects win32yank before enabling unnamedplus" {
  require_nvim
  local path="$WIN_BIN"
  run win32yank_on_path "$path"
  assert_success
  run_headless_options 1 "$path" ':0'
  assert_success
  run cat "$RESULT_FILE"
  assert_line 'g:clipboard=win32yank'
  assert_line 'clipboard=unnamedplus'
  assert_line 'seen=win32yank'
}

@test "WSL selects win32yank without win32yank.exe on PATH" {
  require_nvim
  local path="$XSEL_BIN"
  run win32yank_on_path "$path"
  assert_failure
  run_headless_options 1 "$path" ':0'
  assert_success
  run cat "$RESULT_FILE"
  assert_line 'g:clipboard=win32yank'
  assert_line 'clipboard=unnamedplus'
  assert_line 'seen=win32yank'
}

@test "non-WSL leaves g:clipboard unset and keeps unnamedplus" {
  require_nvim
  run_headless_options 0 "$EMPTY_BIN" ''
  assert_success
  run cat "$RESULT_FILE"
  assert_line 'g:clipboard=nil'
  assert_line 'clipboard=unnamedplus'
  assert_line 'seen=nil'
}

# ---------------------------------------------------------------------------
# TUI: no xsel probe in the process tree during WSL startup (AC3, AC4, AC5)
# ---------------------------------------------------------------------------

@test "WSL startup runs no xsel probe within 2 seconds" {
  require_tui
  local path="$WIN_BIN"
  run win32yank_on_path "$path"
  assert_success
  start_tui "$path" -n -i NONE -u "$INIT_LUA"
  wait_for_file "$STARTED_FILE" 20
  [ -e "$STARTED_FILE" ]
  assert_no_probe_window "$TMUX_PANE_PID"
}

@test "WSL startup runs no xsel probe without win32yank.exe on PATH" {
  require_tui
  local path="$XSEL_BIN"
  run win32yank_on_path "$path"
  assert_failure
  start_tui "$path" -n -i NONE -u "$INIT_LUA"
  wait_for_file "$STARTED_FILE" 20
  [ -e "$STARTED_FILE" ]
  assert_no_probe_window "$TMUX_PANE_PID"
}

@test "detector control: plain clipboard=unnamedplus starts the xsel probe" {
  require_tui
  local path="$XSEL_BIN" found="" tries=0
  start_tui "$path" -n -i NONE -u NONE -c 'set clipboard=unnamedplus'
  while [ -z "$found" ] && [ "$tries" -lt 50 ]; do
    found="$(probe_pids "$TMUX_PANE_PID")"
    [ -n "$found" ] || sleep 0.1
    tries=$((tries + 1))
  done
  [ -n "$found" ]
}
