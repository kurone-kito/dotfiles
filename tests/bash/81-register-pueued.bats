#!/usr/bin/env bats
# Tests for run_onchange_after_81-register-pueued.sh.tmpl.
#
# The fixture mirrors the rendered template and reads the mode from
# PUEUE_LINUX_AUTOSTART. The tests stub systemctl, loginctl, and uname in a
# stub directory that is the only entry on PATH while the fixture runs. Each
# stub appends its call to $TRACE, so the call order is asserted exactly.
# A drift guard renders the real template and fails if its body diverges from
# the fixture.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_HOME="$BATS_TEST_DIRNAME/../../home"
  TEMPLATE="$REPO_HOME/run_onchange_after_81-register-pueued.sh.tmpl"
  IGNORE_TEMPLATE="$REPO_HOME/.chezmoiignore.tmpl"
  FIXTURE="$BATS_TEST_DIRNAME/fixtures/81-register-pueued.sh"

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export USER=testuser
  export TRACE="$BATS_TEST_TMPDIR/trace.log"
  : > "$TRACE"

  # The stub directory holds only the stubs and the shell tools the fixture
  # needs. Nothing else is on PATH while the fixture runs.
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  for cmd in bash sh cat printf echo test id dirname grep; do
    real="$(command -v "$cmd" 2>/dev/null || true)"
    [ -n "$real" ] && ln -sf "$real" "$STUB_BIN/$cmd"
  done

  cat > "$STUB_BIN/uname" <<'EOF'
#!/bin/sh
echo "${UNAME_VALUE:-Linux}"
EOF

  cat > "$STUB_BIN/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$TRACE"
if [ "$*" = "--user show-environment" ]; then
  [ "${DOTFILES_TEST_USER_SYSTEMD:-1}" = 1 ] || exit 1
  exit 0
fi
if [ "$*" = "--user is-active --quiet pueued.service" ]; then
  [ "${UNIT_ACTIVE:-0}" = 1 ]
  exit $?
fi
verb=""
for arg in "$@"; do
  case "$arg" in
    daemon-reload|enable|restart|disable) verb="$arg"; break ;;
  esac
done
if [ -n "$verb" ] && [ "${FAIL_VERB:-}" = "$verb" ]; then
  exit 1
fi
exit 0
EOF

  cat > "$STUB_BIN/loginctl" <<'EOF'
#!/bin/sh
echo "loginctl $*" >> "$TRACE"
echo "${DOTFILES_TEST_LINGER:-yes}"
EOF

  # pgrep finds a pueued only when the test asks for one (1), reports a probe
  # error (2), and otherwise finds nothing (default, exit 1).
  cat > "$STUB_BIN/pgrep" <<'EOF'
#!/bin/sh
case "${UNMANAGED_PUEUED:-0}" in
  1) exit 0 ;;
  2) exit 2 ;;
  *) exit 1 ;;
esac
EOF

  # launchctl logs every call, including print. Each failure knob fails one
  # subcommand. LAUNCHCTL_LOADED=1 makes print report the label as loaded.
  cat > "$STUB_BIN/launchctl" <<'EOF'
#!/bin/sh
echo "launchctl $*" >> "$TRACE"
case "$1" in
  enable) [ "${FAIL_ENABLE:-0}" = 1 ] && exit 1; exit 0 ;;
  disable) [ "${FAIL_DISABLE:-0}" = 1 ] && exit 1; exit 0 ;;
  bootout) [ "${FAIL_BOOTOUT:-0}" = 1 ] && exit 1; exit 0 ;;
  bootstrap) [ "${FAIL_BOOTSTRAP:-0}" = 1 ] && exit 1; exit 0 ;;
  print) [ "${LAUNCHCTL_LOADED:-0}" = 1 ] && exit 0; exit 1 ;;
  *) exit 0 ;;
esac
EOF

  chmod +x "$STUB_BIN/uname" "$STUB_BIN/systemctl" "$STUB_BIN/loginctl" "$STUB_BIN/pgrep" "$STUB_BIN/launchctl"

  export PUEUE_LINUX_AUTOSTART=systemd-user
  export DOTFILES_TEST_USER_SYSTEMD=1
  export DOTFILES_TEST_LINGER=yes
  export UNAME_VALUE=Linux
  export FAIL_VERB=
  export UNMANAGED_PUEUED=0
  export UNIT_ACTIVE=0
  export PUEUE_MACOS_AUTOSTART=launchagent
  export LAUNCHCTL_LOADED=0
  export FAIL_ENABLE=0
  export FAIL_DISABLE=0
  export FAIL_BOOTOUT=0
  export FAIL_BOOTSTRAP=0
}

# Runs the fixture with only the stub directory on PATH.
_run_fixture() {
  # stdout and stderr stay separate, so a warning that moves to stdout fails.
  run --separate-stderr env PATH="$STUB_BIN" bash "$FIXTURE"
}

# $1: chezmoi.os (linux or windows). Renders .chezmoiignore.tmpl with no
# maintainer data, so the output depends only on the OS.
_render_ignore() {
  local config="$BATS_TEST_TMPDIR/chezmoi-config.json"
  printf '%s\n' '{ "data": {} }' > "$config"
  chezmoi execute-template --file "$IGNORE_TEMPLATE" \
    --config "$config" --config-format json \
    --override-data "{\"chezmoi\": {\"os\": \"$1\"}}" \
    --source "$REPO_HOME" --destination "$BATS_TEST_TMPDIR/destination"
}

_expected_show_env='systemctl --user show-environment'
_expected_enable_path=$'systemctl --user show-environment\nsystemctl --user daemon-reload\nsystemctl --user enable pueued.service\nsystemctl --user restart pueued.service\nloginctl show-user testuser -p Linger --value'

@test "systemd-user with a working bus runs daemon-reload, enable, and restart, then reads linger" {
  _run_fixture

  assert_success
  assert_output --partial 'pueued user service enabled.'
  assert_equal "$(cat "$TRACE")" "$_expected_enable_path"
}

@test "systemd-user with linger not yes warns but still enables the unit" {
  export DOTFILES_TEST_LINGER=no
  _run_fixture

  assert_success
  assert_stderr --partial 'warn: linger not enabled'
  assert_output --partial 'pueued user service enabled.'
  assert_equal "$(cat "$TRACE")" "$_expected_enable_path"
}

@test "systemd-user never calls loginctl enable-linger" {
  _run_fixture

  run grep -c 'enable-linger' "$TRACE"
  assert_output '0'
}

@test "systemd-user without systemctl warns, exits 0, and changes no unit" {
  rm "$STUB_BIN/systemctl" "$STUB_BIN/loginctl"
  _run_fixture

  assert_success
  assert_stderr --partial 'systemctl not found'
  assert_equal "$(cat "$TRACE")" ''
}

@test "systemd-user with a bus that does not answer warns, exits 0, and changes no unit" {
  export DOTFILES_TEST_USER_SYSTEMD=0
  _run_fixture

  assert_success
  assert_stderr --partial 'user systemd is not available'
  assert_equal "$(cat "$TRACE")" "$_expected_show_env"
}

@test "disabled with a working bus runs disable --now only and exits 0" {
  export PUEUE_LINUX_AUTOSTART=disabled
  _run_fixture

  assert_success
  assert_output --partial 'pueued user service disabled.'
  assert_equal "$(cat "$TRACE")" "$_expected_show_env"$'\n'"systemctl --user disable --now pueued.service"
}

@test "disabled when disable --now fails exits non-zero and reports no success" {
  export PUEUE_LINUX_AUTOSTART=disabled
  export FAIL_VERB=disable
  _run_fixture

  assert_failure
  refute_output --partial 'pueued user service disabled.'
  assert_equal "$(cat "$TRACE")" "$_expected_show_env"$'\n'"systemctl --user disable --now pueued.service"
}

@test "disabled with a bus that does not answer skips and exits 0" {
  export PUEUE_LINUX_AUTOSTART=disabled
  export DOTFILES_TEST_USER_SYSTEMD=0
  _run_fixture

  assert_success
  assert_output --partial 'not managed because user systemd is unavailable'
  assert_equal "$(cat "$TRACE")" "$_expected_show_env"
}

@test "an unknown mode fails before any service manager call and names the field" {
  export PUEUE_LINUX_AUTOSTART=system-user
  _run_fixture

  assert_failure
  assert_stderr --partial 'data.pueue.linux.autostart'
  assert_equal "$(cat "$TRACE")" ''
}

@test "a non-Linux, non-Darwin uname reports not managed, exits 0, and makes no service call" {
  export UNAME_VALUE=FreeBSD
  _run_fixture

  assert_success
  assert_output --partial 'not managed on this platform'
  assert_equal "$(cat "$TRACE")" ''
}

@test "a daemon-reload failure exits non-zero before enable" {
  export FAIL_VERB=daemon-reload
  _run_fixture

  assert_failure
  assert_equal "$(cat "$TRACE")" "$_expected_show_env"$'\n'"systemctl --user daemon-reload"
}

@test "an enable failure exits non-zero without restart" {
  export FAIL_VERB=enable
  _run_fixture

  assert_failure
  assert_equal "$(cat "$TRACE")" "$_expected_show_env"$'\n'"systemctl --user daemon-reload"$'\n'"systemctl --user enable pueued.service"
}

@test "a restart failure exits non-zero, leaves the unit enabled, and does not disable" {
  export FAIL_VERB=restart
  _run_fixture

  assert_failure
  assert_equal "$(cat "$TRACE")" "$_expected_show_env"$'\n'"systemctl --user daemon-reload"$'\n'"systemctl --user enable pueued.service"$'\n'"systemctl --user restart pueued.service"
  run grep -c 'disable' "$TRACE"
  assert_output '0'
}

@test "an unmanaged pueued blocks enable and restart and names the handover" {
  export UNMANAGED_PUEUED=1
  _run_fixture

  assert_success
  assert_stderr --partial 'an unmanaged pueued may be running'
  assert_stderr --partial 'pueue shutdown'
  refute_output --partial 'pueued user service enabled.'
  assert_equal "$(cat "$TRACE")" "$_expected_show_env"$'\n'"systemctl --user is-active --quiet pueued.service"
}

@test "a process probe that cannot run fails closed when the unit is inactive" {
  export UNMANAGED_PUEUED=2
  _run_fixture

  assert_success
  assert_stderr --partial 'the check could not run'
  refute_output --partial 'pueued user service enabled.'
  assert_equal "$(cat "$TRACE")" "$_expected_show_env"$'\n'"systemctl --user is-active --quiet pueued.service"
}

@test "a missing pgrep fails closed when the unit is inactive" {
  rm "$STUB_BIN/pgrep"
  _run_fixture

  assert_success
  assert_stderr --partial 'the check could not run'
  assert_equal "$(cat "$TRACE")" "$_expected_show_env"$'\n'"systemctl --user is-active --quiet pueued.service"
}

@test "an unmanaged pueued does not block a unit that is already active" {
  export UNMANAGED_PUEUED=1
  export UNIT_ACTIVE=1
  _run_fixture

  assert_success
  assert_output --partial 'pueued user service enabled.'
  assert_equal "$(cat "$TRACE")" "$_expected_show_env"$'\n'"systemctl --user is-active --quiet pueued.service"$'\n'"systemctl --user daemon-reload"$'\n'"systemctl --user enable pueued.service"$'\n'"systemctl --user restart pueued.service"$'\n'"loginctl show-user testuser -p Linger --value"
}

# Darwin helpers. The plist path and the launchctl domain follow the template.
_darwin_plist() {
  mkdir -p "$HOME/Library/LaunchAgents"
  : > "$HOME/Library/LaunchAgents/com.kurone-kito.pueued.plist"
}

@test "launchagent with the plist present enables, checks, and bootstraps a label that is not loaded" {
  export UNAME_VALUE=Darwin
  _darwin_plist
  _run_fixture

  local d="gui/$(id -u)" l="com.kurone-kito.pueued"
  assert_success
  assert_output --partial 'pueued LaunchAgent loaded.'
  assert_equal "$(cat "$TRACE")" "launchctl enable $d/$l"$'\n'"launchctl print $d/$l"$'\n'"launchctl bootstrap $d $HOME/Library/LaunchAgents/$l.plist"
}

@test "launchagent with the label loaded boots it out before bootstrap" {
  export UNAME_VALUE=Darwin
  export LAUNCHCTL_LOADED=1
  _darwin_plist
  _run_fixture

  local d="gui/$(id -u)" l="com.kurone-kito.pueued"
  assert_success
  assert_equal "$(cat "$TRACE")" "launchctl enable $d/$l"$'\n'"launchctl print $d/$l"$'\n'"launchctl bootout $d/$l"$'\n'"launchctl bootstrap $d $HOME/Library/LaunchAgents/$l.plist"
}

@test "launchagent with no plist fails and makes no launchctl call" {
  export UNAME_VALUE=Darwin
  _run_fixture

  assert_failure
  assert_stderr --partial 'LaunchAgent plist not found'
  assert_equal "$(cat "$TRACE")" ''
}

@test "launchagent when enable fails exits non-zero before bootout or bootstrap" {
  export UNAME_VALUE=Darwin
  export FAIL_ENABLE=1
  export LAUNCHCTL_LOADED=1
  _darwin_plist
  _run_fixture

  local d="gui/$(id -u)" l="com.kurone-kito.pueued"
  assert_failure
  refute_output --partial 'pueued LaunchAgent loaded.'
  assert_equal "$(cat "$TRACE")" "launchctl enable $d/$l"
}

@test "launchagent when bootout fails after enable exits non-zero before bootstrap" {
  export UNAME_VALUE=Darwin
  export FAIL_BOOTOUT=1
  export LAUNCHCTL_LOADED=1
  _darwin_plist
  _run_fixture

  local d="gui/$(id -u)" l="com.kurone-kito.pueued"
  assert_failure
  refute_output --partial 'pueued LaunchAgent loaded.'
  assert_equal "$(cat "$TRACE")" "launchctl enable $d/$l"$'\n'"launchctl print $d/$l"$'\n'"launchctl bootout $d/$l"
}

@test "launchagent when bootstrap fails after a bootout exits non-zero and leaves the label unloaded" {
  export UNAME_VALUE=Darwin
  export FAIL_BOOTSTRAP=1
  export LAUNCHCTL_LOADED=1
  _darwin_plist
  _run_fixture

  local d="gui/$(id -u)" l="com.kurone-kito.pueued"
  assert_failure
  assert_equal "$(cat "$TRACE")" "launchctl enable $d/$l"$'\n'"launchctl print $d/$l"$'\n'"launchctl bootout $d/$l"$'\n'"launchctl bootstrap $d $HOME/Library/LaunchAgents/$l.plist"
}

@test "launchagent without launchctl skips and exits 0" {
  export UNAME_VALUE=Darwin
  _darwin_plist
  rm "$STUB_BIN/launchctl"
  _run_fixture

  assert_success
  assert_output --partial 'launchctl not found'
  assert_equal "$(cat "$TRACE")" ''
}

@test "disabled disables and boots out the label, and needs no plist" {
  export UNAME_VALUE=Darwin
  export PUEUE_MACOS_AUTOSTART=disabled
  _run_fixture

  local d="gui/$(id -u)" l="com.kurone-kito.pueued"
  assert_success
  assert_output --partial 'pueued LaunchAgent disabled.'
  assert_equal "$(cat "$TRACE")" "launchctl disable $d/$l"$'\n'"launchctl bootout $d/$l"
}

@test "disabled when disable fails and bootout succeeds exits non-zero" {
  export UNAME_VALUE=Darwin
  export PUEUE_MACOS_AUTOSTART=disabled
  export FAIL_DISABLE=1
  _run_fixture

  local d="gui/$(id -u)" l="com.kurone-kito.pueued"
  assert_failure
  assert_stderr --partial 'disable did not complete'
  refute_output --partial 'pueued LaunchAgent disabled.'
  assert_equal "$(cat "$TRACE")" "launchctl disable $d/$l"$'\n'"launchctl bootout $d/$l"
}

@test "disabled when disable succeeds and bootout of a loaded label fails exits non-zero" {
  export UNAME_VALUE=Darwin
  export PUEUE_MACOS_AUTOSTART=disabled
  export FAIL_BOOTOUT=1
  export LAUNCHCTL_LOADED=1
  _run_fixture

  local d="gui/$(id -u)" l="com.kurone-kito.pueued"
  assert_failure
  assert_equal "$(cat "$TRACE")" "launchctl disable $d/$l"$'\n'"launchctl bootout $d/$l"$'\n'"launchctl print $d/$l"
}

@test "disabled when both disable and bootout of a loaded label fail exits non-zero" {
  export UNAME_VALUE=Darwin
  export PUEUE_MACOS_AUTOSTART=disabled
  export FAIL_DISABLE=1
  export FAIL_BOOTOUT=1
  export LAUNCHCTL_LOADED=1
  _run_fixture

  local d="gui/$(id -u)" l="com.kurone-kito.pueued"
  assert_failure
  assert_equal "$(cat "$TRACE")" "launchctl disable $d/$l"$'\n'"launchctl bootout $d/$l"$'\n'"launchctl print $d/$l"
}

@test "disabled when bootout fails for a label that is not loaded counts as success" {
  export UNAME_VALUE=Darwin
  export PUEUE_MACOS_AUTOSTART=disabled
  export FAIL_BOOTOUT=1
  export LAUNCHCTL_LOADED=0
  _run_fixture

  local d="gui/$(id -u)" l="com.kurone-kito.pueued"
  assert_success
  assert_output --partial 'pueued LaunchAgent disabled.'
  assert_equal "$(cat "$TRACE")" "launchctl disable $d/$l"$'\n'"launchctl bootout $d/$l"$'\n'"launchctl print $d/$l"
}

@test "disabled without launchctl skips and exits 0" {
  export UNAME_VALUE=Darwin
  export PUEUE_MACOS_AUTOSTART=disabled
  rm "$STUB_BIN/launchctl"
  _run_fixture

  assert_success
  assert_output --partial 'launchctl not found'
  assert_equal "$(cat "$TRACE")" ''
}

@test "an unknown macOS mode fails at run time and names the field, with no launchctl call" {
  export UNAME_VALUE=Darwin
  export PUEUE_MACOS_AUTOSTART=system-launchagent
  _run_fixture

  assert_failure
  assert_stderr --partial 'data.pueue.macos.autostart'
  assert_equal "$(cat "$TRACE")" ''
}

@test "an unknown macOS mode fails the render and names the field" {
  local config="$BATS_TEST_TMPDIR/chezmoi-config.json"
  printf '%s\n' '{ "data": { "pueue": { "macos": { "autostart": "system-launchagent" } } } }' > "$config"
  run chezmoi execute-template --file "$TEMPLATE" \
    --config "$config" --config-format json \
    --source "$REPO_HOME" --destination "$BATS_TEST_TMPDIR/destination"
  assert_failure
  assert_output --partial 'data.pueue.macos.autostart'
}

@test "the rendered template body matches the fixture apart from the mode line" {
  local config="$BATS_TEST_TMPDIR/chezmoi-config.json"
  local rendered="$BATS_TEST_TMPDIR/rendered.sh"
  printf '%s\n' '{}' > "$config"
  chezmoi execute-template --file "$TEMPLATE" \
    --config "$config" --config-format json \
    --source "$REPO_HOME" --destination "$BATS_TEST_TMPDIR/destination" > "$rendered"

  # Compare from the strict-mode line onward, so the whole shared body is
  # guarded. Dropping the mode line on both sides leaves only the shared logic,
  # so any drift fails this test.
  body_of() { sed -n '/^set -euo pipefail$/,$p' "$1" | grep -v '^linux_autostart=\|^macos_autostart='; }
  body_of "$rendered" > "$BATS_TEST_TMPDIR/rendered-body.sh"
  body_of "$FIXTURE" > "$BATS_TEST_TMPDIR/fixture-body.sh"

  run diff "$BATS_TEST_TMPDIR/rendered-body.sh" "$BATS_TEST_TMPDIR/fixture-body.sh"
  assert_success
}

@test "the mode line renders the configured value and defaults to systemd-user" {
  local config="$BATS_TEST_TMPDIR/chezmoi-config.json"

  printf '%s\n' '{ "data": { "pueue": { "linux": { "autostart": "disabled" } } } }' > "$config"
  run chezmoi execute-template --file "$TEMPLATE" \
    --config "$config" --config-format json \
    --source "$REPO_HOME" --destination "$BATS_TEST_TMPDIR/destination"
  assert_success
  assert_line 'linux_autostart="disabled"'

  printf '%s\n' '{}' > "$config"
  run chezmoi execute-template --file "$TEMPLATE" \
    --config "$config" --config-format json \
    --source "$REPO_HOME" --destination "$BATS_TEST_TMPDIR/destination"
  assert_success
  assert_line 'linux_autostart="systemd-user"'
}

@test "an unknown mode fails the render and names the field" {
  local config="$BATS_TEST_TMPDIR/chezmoi-config.json"
  printf '%s\n' '{ "data": { "pueue": { "linux": { "autostart": "system-user" } } } }' > "$config"
  run chezmoi execute-template --file "$TEMPLATE" \
    --config "$config" --config-format json \
    --source "$REPO_HOME" --destination "$BATS_TEST_TMPDIR/destination"
  assert_failure
  assert_output --partial 'data.pueue.linux.autostart'
}

@test "a value that would break out of the quoted assignment fails the render" {
  local config="$BATS_TEST_TMPDIR/chezmoi-config.json"
  printf '%s\n' '{ "data": { "pueue": { "linux": { "autostart": "x\"; touch PWNED; \"" } } } }' > "$config"
  run chezmoi execute-template --file "$TEMPLATE" \
    --config "$config" --config-format json \
    --source "$REPO_HOME" --destination "$BATS_TEST_TMPDIR/destination"
  assert_failure
  assert_output --partial 'data.pueue.linux.autostart'
  refute_output --partial 'linux_autostart='
}

@test "the rendered template is valid bash and carries the unit hash line" {
  local config="$BATS_TEST_TMPDIR/chezmoi-config.json"
  local rendered="$BATS_TEST_TMPDIR/rendered-syntax.sh"
  printf '%s\n' '{}' > "$config"
  chezmoi execute-template --file "$TEMPLATE" \
    --config "$config" --config-format json \
    --source "$REPO_HOME" --destination "$BATS_TEST_TMPDIR/destination" > "$rendered"

  run bash -n "$rendered"
  assert_success
  run grep -c '^# unit hash: [0-9a-f]\{64\}$' "$rendered"
  assert_output '1'
}

@test ".chezmoiignore.tmpl lists the register script on Windows only" {
  run --separate-stderr _render_ignore windows
  assert_success
  assert_line '81-register-pueued.sh'

  run --separate-stderr _render_ignore linux
  assert_success
  refute_line '81-register-pueued.sh'
}
