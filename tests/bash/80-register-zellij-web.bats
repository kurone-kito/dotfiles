#!/usr/bin/env bats
# Tests for run_onchange_after_80-register-zellij-web.sh.tmpl.
#
# The fixture mirrors the rendered template and accepts the autostart
# mode via the LINUX_AUTOSTART env var. Tests stub `systemctl`,
# `loginctl`, and `uname` on PATH and toggle user-systemd availability
# via DOTFILES_TEST_USER_SYSTEMD.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  export HOME="$BATS_TEST_TMPDIR"
  FIXTURE="$BATS_TEST_DIRNAME/fixtures/80-register-zellij-web.sh"
  _ORIG_PATH="$PATH"

  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for cmd in bash sh cat printf echo chmod mkdir rm test id dirname grep; do
    real="$(command -v "$cmd" 2>/dev/null || true)"
    [ -n "$real" ] && ln -sf "$real" "$BATS_TEST_TMPDIR/bin/$cmd"
  done

  # Ensure uname always reports Linux so register_linux_service runs.
  cat > "$BATS_TEST_TMPDIR/bin/uname" <<'EOF'
#!/bin/sh
echo Linux
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/uname"

  # Trace file each stub appends to so tests can assert call sequences.
  export TRACE="$BATS_TEST_TMPDIR/trace.log"
  : > "$TRACE"

  export PATH="$BATS_TEST_TMPDIR/bin"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

install_systemctl_stub() {
  # Honors DOTFILES_TEST_USER_SYSTEMD: when "0", `show-environment`
  # exits non-zero (simulating no user bus).
  cat > "$BATS_TEST_TMPDIR/bin/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$TRACE"
case "$*" in
  "--user show-environment")
    [ "${DOTFILES_TEST_USER_SYSTEMD:-1}" = "1" ] || exit 1
    echo "PATH=$PATH"
    ;;
esac
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/systemctl"
}

install_loginctl_stub() {
  cat > "$BATS_TEST_TMPDIR/bin/loginctl" <<'EOF'
#!/bin/sh
echo "loginctl $*" >> "$TRACE"
echo "${DOTFILES_TEST_LINGER:-yes}"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/loginctl"
}

# -----------------------------------------------------------------------
# disabled mode
# -----------------------------------------------------------------------

@test "disabled + user systemd available: disables service, no daemon-reload" {
  install_systemctl_stub
  export DOTFILES_TEST_USER_SYSTEMD=1
  LINUX_AUTOSTART=disabled run bash "$FIXTURE"

  assert_success
  assert_output --partial "Zellij Web user service disabled."
  refute_output --partial "not managed"
  # daemon-reload must NOT be invoked in the disabled path.
  run grep -F "systemctl --user daemon-reload" "$TRACE"
  assert_failure
  # disable verb IS invoked.
  run grep -F "systemctl --user disable --now zellij-web.service" "$TRACE"
  assert_success
}

@test "disabled + user systemd unavailable: skips silently, no mutating calls" {
  install_systemctl_stub
  export DOTFILES_TEST_USER_SYSTEMD=0
  LINUX_AUTOSTART=disabled run bash "$FIXTURE"

  assert_success
  assert_output --partial "not managed because user systemd is unavailable"
  # Only the probe should have been invoked.
  run grep -F "systemctl --user disable" "$TRACE"
  assert_failure
  run grep -F "systemctl --user daemon-reload" "$TRACE"
  assert_failure
}

@test "disabled + systemctl missing: skips silently" {
  # Do NOT install the systemctl stub.
  LINUX_AUTOSTART=disabled run bash "$FIXTURE"

  assert_success
  assert_output --partial "not managed because user systemd is unavailable"
}

# -----------------------------------------------------------------------
# systemd-user mode
# -----------------------------------------------------------------------

@test "systemd-user + user systemd available: enables and restarts" {
  install_systemctl_stub
  install_loginctl_stub
  export DOTFILES_TEST_USER_SYSTEMD=1
  export DOTFILES_TEST_LINGER=yes
  LINUX_AUTOSTART=systemd-user run bash "$FIXTURE"

  assert_success
  assert_output --partial "Zellij Web user service enabled."
  refute_output --partial "warn: linger not enabled"
  for verb in "daemon-reload" "enable zellij-web.service" "restart zellij-web.service"; do
    run grep -F "systemctl --user $verb" "$TRACE"
    assert_success
  done
}

@test "systemd-user + user systemd available + no linger: warns" {
  install_systemctl_stub
  install_loginctl_stub
  export DOTFILES_TEST_USER_SYSTEMD=1
  export DOTFILES_TEST_LINGER=no
  LINUX_AUTOSTART=systemd-user run bash "$FIXTURE"

  assert_success
  assert_output --partial "warn: linger not enabled"
}

@test "systemd-user + user systemd unavailable: fails loudly" {
  install_systemctl_stub
  export DOTFILES_TEST_USER_SYSTEMD=0
  LINUX_AUTOSTART=systemd-user run bash "$FIXTURE"

  assert_failure
  assert_output --partial "user systemd is not available"
  # Must not have attempted enable/restart.
  run grep -F "systemctl --user enable" "$TRACE"
  assert_failure
  run grep -F "systemctl --user restart" "$TRACE"
  assert_failure
}

@test "systemd-user + systemctl missing: fails loudly" {
  # No systemctl stub.
  LINUX_AUTOSTART=systemd-user run bash "$FIXTURE"

  assert_failure
  assert_output --partial "systemctl is required"
}

@test "systemd-user + USER unset: falls back to id -un under set -u" {
  install_systemctl_stub
  install_loginctl_stub
  export DOTFILES_TEST_USER_SYSTEMD=1
  export DOTFILES_TEST_LINGER=yes
  unset USER
  LINUX_AUTOSTART=systemd-user run bash "$FIXTURE"

  assert_success
  assert_output --partial "Zellij Web user service enabled."
}

# -----------------------------------------------------------------------
# unknown mode
# -----------------------------------------------------------------------

@test "unknown mode: rejected before any dependency probe" {
  # Do NOT install systemctl: confirm validation runs first.
  LINUX_AUTOSTART="system-user" run bash "$FIXTURE"

  assert_failure
  assert_output --partial "Unsupported zellij.web.linux.autostart mode: system-user"
  # No probe should have been attempted.
  run grep -F "systemctl" "$TRACE"
  assert_failure
}
