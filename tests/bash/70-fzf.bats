#!/usr/bin/env bats
# Tests for the fzf (fuzzy finder) shell integration script.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/70-fzf.sh"
  _ORIG_PATH="$PATH"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

# Wraps sourcing so top-level `return` exits this function, not the test
_source_script() { . "$SCRIPT_PATH"; }

# ---------------------------------------------------------------------------
# Missing dependency
# ---------------------------------------------------------------------------

@test "exits early without error when fzf is not in PATH" {
  PATH="$BATS_TEST_TMPDIR/no-bin:/usr/bin:/bin"
  mkdir -p "$BATS_TEST_TMPDIR/no-bin"

  run _source_script
  assert_success
}

# ---------------------------------------------------------------------------
# Modern fzf (0.48+)
# ---------------------------------------------------------------------------

@test "modern fzf evaluates fzf --bash for shell integration" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/fzf" << 'MOCK'
#!/bin/sh
case "$1" in
  --version) echo "0.48.0 (abc1234)" ;;
  --bash) echo 'export FZF_BASH_LOADED=1' ;;
esac
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/fzf"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  _source_script

  assert_equal "$FZF_BASH_LOADED" "1"
}

# ---------------------------------------------------------------------------
# Legacy fzf (<0.48)
# ---------------------------------------------------------------------------

@test "legacy fzf sources key-bindings and completion scripts" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/fzf" << 'MOCK'
#!/bin/sh
case "$1" in
  --version) echo "0.42.0 (abc1234)" ;;
esac
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/fzf"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  mkdir -p "$BATS_TEST_TMPDIR/share/fzf"
  echo 'export FZF_KEYBINDINGS_LOADED=1' > "$BATS_TEST_TMPDIR/share/fzf/key-bindings.bash"
  echo 'export FZF_COMPLETION_LOADED=1' > "$BATS_TEST_TMPDIR/share/fzf/completion.bash"

  _source_script

  assert_equal "$FZF_KEYBINDINGS_LOADED" "1"
  assert_equal "$FZF_COMPLETION_LOADED" "1"
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

@test "cleans up temporary variables after sourcing" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/fzf" << 'MOCK'
#!/bin/sh
case "$1" in
  --version) echo "0.48.0 (abc1234)" ;;
  --bash) echo 'export FZF_BASH_LOADED=1' ;;
esac
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/fzf"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  _source_script

  assert [ -z "${_fzf_version+x}" ]
  assert [ -z "${_fzf_major+x}" ]
  assert [ -z "${_fzf_minor+x}" ]
  assert [ -z "${_fzf_dir+x}" ]
}
