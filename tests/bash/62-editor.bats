#!/usr/bin/env bats
# Tests for the shared EDITOR/VISUAL default in conf.d/62-editor.sh.
#
# The script exports the first of nvim, vim and vi that `command -v` finds as
# both EDITOR and VISUAL, and runs after 60-mise.sh so that an nvim which mise
# puts on PATH is found. Unit cases source the script with a PATH limited to a
# stub directory (the approach of 05-nvim.bats). Startup order is exercised
# through real `bash -li` and `zsh -li` invocations over the copied
# dot_profile/dot_bashrc/zsh chain with a mocked `mise` (the approach of
# 65-node-options.bats). The cleanup script and the Windows-only ignore entry
# that retire the old 30-editor.sh are covered at the end.
# cspell:words chezmoiignore

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  REPO_HOME="$REPO_ROOT/home"
  CONFD="$REPO_HOME/dot_config/shell/conf.d"
  SCRIPT="$CONFD/62-editor.sh"
  CLEANUP="$REPO_HOME/run_once_after_cleanup-editor-confd.sh"
  # Resolved before any test narrows PATH to a stub directory.
  BASH_BIN="$(command -v bash)"
  SH_BIN="$(command -v sh)"
  _ORIG_PATH="$PATH"
  unset EDITOR VISUAL
}

teardown() {
  export PATH="$_ORIG_PATH"
}

require_zsh() {
  command -v zsh > /dev/null 2>&1 || skip "zsh not available"
}

# Create $STUB_DIR holding an executable stub for each given name (none for an
# empty directory).
make_stub_dir() {
  STUB_DIR="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUB_DIR"
  local name
  for name in "$@"; do
    printf '#!/bin/sh\nexit 0\n' > "$STUB_DIR/$name"
    chmod +x "$STUB_DIR/$name"
  done
}

# Source the script with PATH limited to the given directory, then restore it
# so the assertions can use the usual tools.
source_editor_script() {
  PATH="$1"
  . "$SCRIPT"
  PATH="$_ORIG_PATH"
}

# ---------------------------------------------------------------------------
# Choice of editor
# ---------------------------------------------------------------------------

@test "uses nvim when nvim, vim and vi all exist" {
  make_stub_dir nvim vim vi
  source_editor_script "$STUB_DIR"
  assert_equal "$EDITOR" nvim
  assert_equal "$VISUAL" nvim
}

@test "falls back to vim when only vim and vi exist" {
  make_stub_dir vim vi
  source_editor_script "$STUB_DIR"
  assert_equal "$EDITOR" vim
  assert_equal "$VISUAL" vim
}

@test "falls back to vi when only vi exists" {
  make_stub_dir vi
  source_editor_script "$STUB_DIR"
  assert_equal "$EDITOR" vi
  assert_equal "$VISUAL" vi
}

@test "sets neither variable when no editor exists" {
  make_stub_dir
  source_editor_script "$STUB_DIR"
  [ -z "${EDITOR+x}" ] || fail "EDITOR is set to '$EDITOR'"
  [ -z "${VISUAL+x}" ] || fail "VISUAL is set to '$VISUAL'"
}

@test "exports both variables so a child process sees them" {
  make_stub_dir nvim
  source_editor_script "$STUB_DIR"
  PATH="$STUB_DIR" run "$BASH_BIN" -c 'printf "%s %s" "$EDITOR" "$VISUAL"'
  assert_success
  assert_output "nvim nvim"
}

# ---------------------------------------------------------------------------
# Inherited values
# ---------------------------------------------------------------------------

@test "replaces preset values when an editor exists" {
  make_stub_dir nvim
  export EDITOR=emacs VISUAL=code
  source_editor_script "$STUB_DIR"
  assert_equal "$EDITOR" nvim
  assert_equal "$VISUAL" nvim
}

@test "keeps preset values when no editor exists" {
  make_stub_dir
  export EDITOR=emacs VISUAL=code
  source_editor_script "$STUB_DIR"
  assert_equal "$EDITOR" emacs
  assert_equal "$VISUAL" code
}

# ---------------------------------------------------------------------------
# Sourcing safety
# ---------------------------------------------------------------------------

@test "sourcing under set -eu never aborts the caller and leaves no helper variable" {
  local stub_set stub_none
  make_stub_dir nvim
  stub_set="$STUB_DIR"
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  stub_none="$BATS_TEST_TMPDIR/empty"

  local shell_bin
  for shell_bin in "$SH_BIN" "$BASH_BIN"; do
    run env -u EDITOR -u VISUAL PATH="$stub_set" "$shell_bin" -eu -c \
      '. "$0"; printf "%s %s %s" "$EDITOR" "$VISUAL" "${_editor-gone}"' "$SCRIPT"
    assert_success
    assert_output "nvim nvim gone"

    run env -u EDITOR -u VISUAL PATH="$stub_none" "$shell_bin" -eu -c \
      '. "$0"; printf "%s %s %s" "${EDITOR-unset}" "${VISUAL-unset}" "${_editor-gone}"' "$SCRIPT"
    assert_success
    assert_output "unset unset gone"
  done
}

@test "zsh: sourcing under set -eu never aborts the caller and leaves no helper variable" {
  require_zsh
  make_stub_dir nvim
  run env -u EDITOR -u VISUAL PATH="$STUB_DIR" "$(command -v zsh)" -eu -c \
    '. "$0"; printf "%s %s %s" "$EDITOR" "$VISUAL" "${_editor-gone}"' "$SCRIPT"
  assert_success
  assert_output "nvim nvim gone"
}

# ---------------------------------------------------------------------------
# File order inside conf.d
# ---------------------------------------------------------------------------

@test "62-editor.sh sorts after 60-mise.sh and before 65-node-options.sh" {
  assert_file_exist "$CONFD/60-mise.sh"
  assert_file_exist "$CONFD/62-editor.sh"
  assert_file_exist "$CONFD/65-node-options.sh"

  # The numeric prefix is everything before the first hyphen of the file name.
  local prefix_mise prefix_editor prefix_node
  prefix_mise="$(basename "$CONFD/60-mise.sh")"
  prefix_mise="${prefix_mise%%-*}"
  prefix_editor="$(basename "$CONFD/62-editor.sh")"
  prefix_editor="${prefix_editor%%-*}"
  prefix_node="$(basename "$CONFD/65-node-options.sh")"
  prefix_node="${prefix_node%%-*}"

  [ "$((10#$prefix_editor))" -gt "$((10#$prefix_mise))" ]
  [ "$((10#$prefix_editor))" -lt "$((10#$prefix_node))" ]
}

@test "the old 30-editor.sh is gone from the source tree" {
  assert_file_not_exist "$CONFD/30-editor.sh"
}

# ---------------------------------------------------------------------------
# Cleanup of the deployed 30-editor.sh
# ---------------------------------------------------------------------------

@test "the cleanup script removes the old 30-editor.sh and keeps its neighbours" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.config/shell/conf.d"
  : > "$HOME/.config/shell/conf.d/30-editor.sh"
  : > "$HOME/.config/shell/conf.d/60-mise.sh"

  run sh "$CLEANUP"

  assert_success
  assert_file_not_exist "$HOME/.config/shell/conf.d/30-editor.sh"
  assert_file_exist "$HOME/.config/shell/conf.d/60-mise.sh"
}

@test "the cleanup script exits 0 when the old file is already gone" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.config/shell/conf.d"
  : > "$HOME/.config/shell/conf.d/60-mise.sh"

  run sh "$CLEANUP"

  assert_success
  assert_file_exist "$HOME/.config/shell/conf.d/60-mise.sh"
}

# ---------------------------------------------------------------------------
# The cleanup script is POSIX-only: ignored on Windows only
# ---------------------------------------------------------------------------

@test ".chezmoiignore.tmpl lists cleanup-editor-confd.sh once, in the Windows block" {
  local tmpl="$REPO_HOME/.chezmoiignore.tmpl"

  # Whole-line comparisons: the template has a second, differently spaced
  # `if` block further down that a loose pattern would open as well.
  run awk '
    $0 == "{{- if eq .chezmoi.os \"windows\" }}" { windows = 1; next }
    $0 == "{{- else }}" { windows = 0; next }
    windows && $0 == "cleanup-editor-confd.sh" { found++ }
    END { print found + 0 }
  ' "$tmpl"
  assert_success
  assert_output 1

  run grep -c -x 'cleanup-editor-confd.sh' "$tmpl"
  assert_success
  assert_output 1
}

@test ".chezmoiignore.tmpl does not ignore cleanup-editor-confd.sh on non-Windows" {
  printf '%s\n' '{ "data": {} }' > "$BATS_TEST_TMPDIR/chezmoi-config.json"

  run --separate-stderr chezmoi execute-template --file "$REPO_HOME/.chezmoiignore.tmpl" \
    --config "$BATS_TEST_TMPDIR/chezmoi-config.json" --config-format json \
    --source "$REPO_ROOT" --destination "$BATS_TEST_TMPDIR"

  assert_success
  # A line that only the non-Windows branch emits, so an empty or wrong-branch
  # render cannot satisfy the refusal below.
  assert_line 'AppData'
  refute_line 'cleanup-editor-confd.sh'
}

# ---------------------------------------------------------------------------
# Startup order through real login shells
# ---------------------------------------------------------------------------

# Copy the real startup chain, 60-mise.sh and 62-editor.sh (and nothing else,
# so no other conf.d script can put a host nvim on PATH) into a temporary HOME,
# with a mise whose `activate` puts a stub nvim on PATH.
setup_e2e() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.config/shell/conf.d"
  cp "$CONFD/60-mise.sh" "$SCRIPT" "$HOME/.config/shell/conf.d/"
  cp "$REPO_HOME/dot_profile" "$HOME/.profile"
  cp "$REPO_HOME/dot_bash_profile" "$HOME/.bash_profile"
  cp "$REPO_HOME/dot_bashrc" "$HOME/.bashrc"
  ZDOTDIR="$HOME/.config/zsh"
  mkdir -p "$ZDOTDIR"
  cp "$REPO_HOME/dot_config/zsh/dot_zprofile" "$ZDOTDIR/.zprofile"
  cp "$REPO_HOME/dot_config/zsh/dot_zshrc" "$ZDOTDIR/.zshrc"

  # Keep 60-mise.sh away from the host: no WSL branch, no real trust stamp.
  export DOTFILES_MISE_ASSUME_WSL=0
  export DOTFILES_MISE_WSL_USERS_ROOT="$BATS_TEST_TMPDIR/no-windows-users"
  export DOTFILES_MISE_TRUST_STAMP="$BATS_TEST_TMPDIR/mise-trust-stamp"
  export DOTFILES_MISE_ACTIVATE_CACHE="$BATS_TEST_TMPDIR/mise-activate-cache"
  unset MISE_STATE_DIR XDG_STATE_HOME MISE_MOCK_EDITOR_DIR

  # A curated PATH: only what the startup files and mocks need.
  local safe_bin_dir="$BATS_TEST_TMPDIR/safe-bin"
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$safe_bin_dir" "$MOCK_BIN"
  local tool tool_path
  for tool in awk basename bash cat chmod cp cut date dirname env grep head id \
    ln ls mkdir mktemp mv printf readlink rm sed sh sha256sum shasum sleep \
    sort stat tail touch tr uname wc zsh; do
    tool_path="$(command -v "$tool" 2> /dev/null)" || continue
    ln -sf "$tool_path" "$safe_bin_dir/$tool"
  done
  export PATH="$MOCK_BIN:$safe_bin_dir"

  cat > "$MOCK_BIN/mise" << 'MOCK'
#!/bin/sh
case "$1" in
  trust) exit 0 ;;
  activate)
    if [ -n "${MISE_MOCK_EDITOR_DIR:-}" ]; then
      printf 'export PATH="%s:$PATH"\n' "$MISE_MOCK_EDITOR_DIR"
    fi
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/mise"

  # The nvim exists only in this directory, which only `activate` adds.
  ACTIVATE_DIR="$BATS_TEST_TMPDIR/activated"
  mkdir -p "$ACTIVATE_DIR"
  printf '#!/bin/sh\nexit 0\n' > "$ACTIVATE_DIR/nvim"
  chmod +x "$ACTIVATE_DIR/nvim"
}

# Run a fresh login+interactive shell and print "<nvim path>|<EDITOR>|<VISUAL>"
# (empty fields when absent). Pass __none__ as the second argument to start
# without the activation directory.
login_probe() {
  local shell_name="$1" activation="$2"
  local -a launcher=(env -u EDITOR -u VISUAL)
  if [ "$activation" = __none__ ]; then
    launcher+=(-u MISE_MOCK_EDITOR_DIR)
  else
    launcher+=("MISE_MOCK_EDITOR_DIR=$activation")
  fi
  local probe='printf "%s|%s|%s" "$(command -v nvim 2>/dev/null)" "${EDITOR-}" "${VISUAL-}"'
  case "$shell_name" in
    bash)
      run --separate-stderr "${launcher[@]}" bash -li -c "$probe"
      ;;
    zsh)
      run --separate-stderr "${launcher[@]}" ZDOTDIR="$ZDOTDIR" zsh -li -c "$probe"
      ;;
  esac
  [ "$status" -eq 0 ] || fail "$shell_name login shell failed ($status): $stderr"
}

# The control runs first: without the activation directory no nvim may be
# visible. When the host puts an nvim on the login shell's PATH the pair cannot
# prove anything and is skipped; any other control outcome must not pick nvim.
assert_control_has_no_nvim() {
  local shell_name="$1" nvim_path rest editor
  login_probe "$shell_name" __none__
  nvim_path="${output%%|*}"
  [ -z "$nvim_path" ] || skip "a host nvim is on the $shell_name login shell's PATH: $nvim_path"
  rest="${output#*|}"
  editor="${rest%%|*}"
  case "$editor" in
    '' | vim | vi) ;;
    *) fail "control: EDITOR is '$editor' although no nvim is on PATH" ;;
  esac
}

@test "bash: a login shell picks the nvim that mise activates" {
  setup_e2e
  assert_control_has_no_nvim bash

  login_probe bash "$ACTIVATE_DIR"
  assert_output "$ACTIVATE_DIR/nvim|nvim|nvim"
}

@test "zsh: a login shell picks the nvim that mise activates" {
  require_zsh
  setup_e2e
  assert_control_has_no_nvim zsh

  login_probe zsh "$ACTIVATE_DIR"
  assert_output "$ACTIVATE_DIR/nvim|nvim|nvim"
}

@test "bash: the same script under a 30- name misses the nvim that mise activates" {
  setup_e2e
  assert_control_has_no_nvim bash
  mv "$HOME/.config/shell/conf.d/62-editor.sh" "$HOME/.config/shell/conf.d/30-editor.sh"

  login_probe bash "$ACTIVATE_DIR"
  local rest="${output#*|}"
  [ "${rest%%|*}" != nvim ] || fail "the 30- name still found nvim: $output"
}
