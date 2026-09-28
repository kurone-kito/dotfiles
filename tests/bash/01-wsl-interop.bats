#!/usr/bin/env bats
# Tests for the WSLInterop warning and repair helper.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR/home"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/01-wsl-interop.sh"
  _ORIG_PATH="$PATH"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/binfmt"
  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"

  export DOTFILES_WSL_INTEROP_BINFMT_DIR="$BATS_TEST_TMPDIR/binfmt"
  export DOTFILES_WSL_INTEROP_PROC_VERSION="$BATS_TEST_TMPDIR/proc-version"
  export DOTFILES_WSL_INTEROP_DROPIN="$BATS_TEST_TMPDIR/drop-in/override.conf"
  export SUDO_LOG="$BATS_TEST_TMPDIR/sudo.log"
  export GREP_LOG="$BATS_TEST_TMPDIR/grep.log"
  export SYSTEMCTL_CREATES_ENTRY=0
  export SYSTEMCTL_STATUS=0
  export TEE_CREATES_ENTRY=0

  printf '%s\n' enabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/status"
  touch "$DOTFILES_WSL_INTEROP_BINFMT_DIR/register"
  printf '%s\n' 'Linux version 6.6.0-microsoft-standard-WSL2' \
    >"$DOTFILES_WSL_INTEROP_PROC_VERSION"
}

teardown() {
  export PATH="$_ORIG_PATH"
  unset DOTFILES_WSL_INTEROP_BINFMT_DIR DOTFILES_WSL_INTEROP_PROC_VERSION \
    DOTFILES_WSL_INTEROP_DROPIN DOTFILES_WSL_INTEROP_WARN SUDO_LOG \
    GREP_LOG SYSTEMCTL_CREATES_ENTRY SYSTEMCTL_STATUS TEE_CREATES_ENTRY
}

make_sudo_stub() {
  cat >"$BATS_TEST_TMPDIR/bin/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$SUDO_LOG"
case "$1" in
  systemctl)
    if [ "$SYSTEMCTL_CREATES_ENTRY" = 1 ]; then
      printf '%s\n' enabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop"
    fi
    exit "$SYSTEMCTL_STATUS"
    ;;
  tee)
    cat >"$2"
    case "$2" in
      "$DOTFILES_WSL_INTEROP_BINFMT_DIR/status"|\
      "$DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop"|\
      "$DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop-late")
        printf '%s\n' enabled >"$2"
        ;;
    esac
    if [ "$TEE_CREATES_ENTRY" = 1 ]; then
      printf '%s\n' enabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop"
    fi
    exit 0
    ;;
esac
exit 2
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/sudo"
}

run_interactive_source() {
  run --separate-stderr env HOME="$HOME" PATH="$PATH" \
    DOTFILES_WSL_INTEROP_BINFMT_DIR="$DOTFILES_WSL_INTEROP_BINFMT_DIR" \
    DOTFILES_WSL_INTEROP_PROC_VERSION="$DOTFILES_WSL_INTEROP_PROC_VERSION" \
    DOTFILES_WSL_INTEROP_DROPIN="$DOTFILES_WSL_INTEROP_DROPIN" \
    DOTFILES_WSL_INTEROP_WARN="${DOTFILES_WSL_INTEROP_WARN:-1}" \
    bash -i -c '. "$1"' _ "$SCRIPT_PATH"
}

@test "warns once for an interactive WSL shell with missing registration" {
  run_interactive_source
  assert_success
  count="$(printf '%s\n' "$stderr" | grep -c 'wsl_interop_repair' || true)"
  assert_equal "$count" 1
}

@test "does not warn when WSLInterop is registered" {
  printf '%s\n' enabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop"
  run_interactive_source
  assert_success
  refute_output --partial 'wsl_interop_repair'
  refute_stderr --partial 'wsl_interop_repair'
}

@test "does not warn when WSLInterop-late is registered" {
  printf '%s\n' enabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop-late"
  run_interactive_source
  assert_success
  refute_stderr --partial 'wsl_interop_repair'
}

@test "warns when global binfmt status is disabled" {
  printf '%s\n' disabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/status"
  printf '%s\n' enabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop"

  run_interactive_source
  assert_success
  assert_stderr --partial 'wsl_interop_repair'
}

@test "does not fork for a non-WSL host with missing registration" {
  cat >"$BATS_TEST_TMPDIR/bin/grep" <<'EOF'
#!/bin/sh
: >"$GREP_LOG"
exec /usr/bin/grep "$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/grep"
  printf '%s\n' 'Linux version 6.6.0-generic' \
    >"$DOTFILES_WSL_INTEROP_PROC_VERSION"

  run_interactive_source
  assert_success
  refute_stderr --partial 'wsl_interop_repair'
  assert_file_not_exists "$GREP_LOG"
}

@test "does not warn for non-interactive, non-WSL, unmounted, or opted-out shells" {
  run --separate-stderr env HOME="$HOME" PATH="$PATH" \
    DOTFILES_WSL_INTEROP_BINFMT_DIR="$DOTFILES_WSL_INTEROP_BINFMT_DIR" \
    DOTFILES_WSL_INTEROP_PROC_VERSION="$DOTFILES_WSL_INTEROP_PROC_VERSION" \
    DOTFILES_WSL_INTEROP_DROPIN="$DOTFILES_WSL_INTEROP_DROPIN" \
    /bin/sh "$SCRIPT_PATH"
  assert_success
  refute_stderr --partial 'wsl_interop_repair'

  printf '%s\n' 'Linux version 6.6.0-generic' >"$DOTFILES_WSL_INTEROP_PROC_VERSION"
  run_interactive_source
  assert_success
  refute_stderr --partial 'wsl_interop_repair'

  printf '%s\n' 'Linux version 6.6.0-microsoft-standard-WSL2' \
    >"$DOTFILES_WSL_INTEROP_PROC_VERSION"
  rm "$DOTFILES_WSL_INTEROP_BINFMT_DIR/status"
  run_interactive_source
  assert_success
  refute_stderr --partial 'wsl_interop_repair'

  touch "$DOTFILES_WSL_INTEROP_BINFMT_DIR/status"
  export DOTFILES_WSL_INTEROP_WARN=0
  run_interactive_source
  assert_success
  refute_stderr --partial 'wsl_interop_repair'
}

@test "repair succeeds without sudo when registration already exists" {
  make_sudo_stub
  printf '%s\n' enabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop"

  run --separate-stderr /bin/sh -c '. "$1"; wsl_interop_repair' _ "$SCRIPT_PATH"
  assert_success
  assert_stderr --partial 'already registered'
  assert_file_not_exists "$SUDO_LOG"
}

@test "warns when a WSLInterop entry is disabled" {
  printf '%s\n' disabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop"

  run_interactive_source
  assert_success
  assert_stderr --partial 'missing, disabled'
}

@test "repairs a disabled WSLInterop entry" {
  make_sudo_stub
  printf '%s\n' disabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop"

  run --separate-stderr /bin/sh -c '. "$1"; wsl_interop_repair' _ "$SCRIPT_PATH"
  assert_success
  assert_stderr --partial 'restored'
  assert_file_contains "$SUDO_LOG" "tee $DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop"
}

@test "repairs a globally disabled binfmt_misc status" {
  make_sudo_stub
  printf '%s\n' disabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/status"
  printf '%s\n' enabled >"$DOTFILES_WSL_INTEROP_BINFMT_DIR/WSLInterop"

  run --separate-stderr /bin/sh -c '. "$1"; wsl_interop_repair' _ "$SCRIPT_PATH"
  assert_success
  assert_stderr --partial 'restored'
  assert_file_contains "$SUDO_LOG" "tee $DOTFILES_WSL_INTEROP_BINFMT_DIR/status"
}

@test "repair refuses non-WSL hosts without sudo" {
  make_sudo_stub
  printf '%s\n' 'Linux version 6.6.0-generic' >"$DOTFILES_WSL_INTEROP_PROC_VERSION"

  run --separate-stderr /bin/sh -c '. "$1"; wsl_interop_repair' _ "$SCRIPT_PATH"
  assert_failure
  assert_stderr --partial 'not a WSL host'
  assert_file_not_exists "$SUDO_LOG"
}

@test "repair uses systemd-binfmt when the generated drop-in is present" {
  make_sudo_stub
  mkdir -p "$(dirname "$DOTFILES_WSL_INTEROP_DROPIN")"
  touch "$DOTFILES_WSL_INTEROP_DROPIN"
  export SYSTEMCTL_CREATES_ENTRY=1

  run --separate-stderr /bin/sh -c '. "$1"; wsl_interop_repair' _ "$SCRIPT_PATH"
  assert_success
  assert_file_contains "$SUDO_LOG" 'systemctl restart systemd-binfmt.service'
  run grep -F 'tee ' "$SUDO_LOG"
  assert_failure
}

@test "repair falls back to direct registration when systemd does not restore it" {
  make_sudo_stub
  mkdir -p "$(dirname "$DOTFILES_WSL_INTEROP_DROPIN")"
  touch "$DOTFILES_WSL_INTEROP_DROPIN"
  export TEE_CREATES_ENTRY=1

  run --separate-stderr /bin/sh -c '. "$1"; wsl_interop_repair' _ "$SCRIPT_PATH"
  assert_success
  assert_file_contains "$SUDO_LOG" 'systemctl restart systemd-binfmt.service'
  assert_file_contains "$SUDO_LOG" "tee $DOTFILES_WSL_INTEROP_BINFMT_DIR/register"
  run cat "$DOTFILES_WSL_INTEROP_BINFMT_DIR/register"
  assert_output ':WSLInterop:M::MZ::/init:P'
}

@test "repair uses direct registration when the drop-in is absent" {
  make_sudo_stub
  export TEE_CREATES_ENTRY=1

  run --separate-stderr /bin/sh -c '. "$1"; wsl_interop_repair' _ "$SCRIPT_PATH"
  assert_success
  run grep -F 'systemctl restart systemd-binfmt.service' "$SUDO_LOG"
  assert_failure
  assert_file_contains "$SUDO_LOG" "tee $DOTFILES_WSL_INTEROP_BINFMT_DIR/register"
}

@test "repair fails when registration remains missing" {
  make_sudo_stub

  run --separate-stderr /bin/sh -c '. "$1"; wsl_interop_repair' _ "$SCRIPT_PATH"
  assert_failure
  assert_stderr --partial 'still missing'
}

@test "repair reports an unmounted binfmt_misc without sudo" {
  make_sudo_stub
  rm "$DOTFILES_WSL_INTEROP_BINFMT_DIR/register"

  run --separate-stderr /bin/sh -c '. "$1"; wsl_interop_repair' _ "$SCRIPT_PATH"
  assert_failure
  assert_stderr --partial 'binfmt_misc is not mounted'
  assert_file_not_exists "$SUDO_LOG"
}

@test "cleans all temporary variables after sourcing and repairing" {
  make_sudo_stub
  export TEE_CREATES_ENTRY=1

  run /bin/sh -c '. "$1"; wsl_interop_repair >/dev/null 2>&1; set' _ "$SCRIPT_PATH"
  assert_success
  refute_output --partial '_dotfiles_wsl_interop_'
}

@test "sources cleanly under zsh" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not available"

  run env HOME="$HOME" zsh -f -c '. "$1"; type wsl_interop_repair >/dev/null' _ "$SCRIPT_PATH"
  assert_success
}
