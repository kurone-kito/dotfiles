#!/usr/bin/env bats
# Tests for the mise (polyglot runtime manager) shell initialization script.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/60-mise.sh"
  _ORIG_PATH="$PATH"
  export MISE_MOCK_LOG="$BATS_TEST_TMPDIR/mise-calls.log"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

# Wraps sourcing so top-level `return` exits this function, not the test
_source_script() { . "$SCRIPT_PATH"; }

_setup_mock_mise() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/mise" << 'MOCK'
#!/bin/sh
case "$1" in
  trust)
    echo "$@" >> "${MISE_MOCK_LOG:-/dev/null}"
    ;;
  activate)
    if [ "$2" = "bash" ]; then
      echo 'export MISE_ACTIVATED=bash'
    fi
    ;;
esac
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/mise"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# ---------------------------------------------------------------------------
# Missing dependency
# ---------------------------------------------------------------------------

@test "exits early without error when mise is not in PATH" {
  PATH="$BATS_TEST_TMPDIR/no-bin:/usr/bin:/bin"
  mkdir -p "$BATS_TEST_TMPDIR/no-bin"

  run _source_script
  assert_success
}

# ---------------------------------------------------------------------------
# Trusted config paths
# ---------------------------------------------------------------------------

@test "sets MISE_TRUSTED_CONFIG_PATHS to include home mise directories" {
  _setup_mock_mise
  _source_script

  assert_equal "$MISE_TRUSTED_CONFIG_PATHS" "$HOME/.mise:$HOME/.config/mise"
}

# ---------------------------------------------------------------------------
# Config file trusting
# ---------------------------------------------------------------------------

@test "calls mise trust for each existing config file" {
  _setup_mock_mise
  mkdir -p "$HOME/.mise" "$HOME/.config/mise"
  touch "$HOME/.mise/config.toml"
  touch "$HOME/.config/mise/config.toml"

  _source_script

  assert_file_exists "$MISE_MOCK_LOG"
  run grep -c "trust" "$MISE_MOCK_LOG"
  assert_success
  assert_output "2"
}

# ---------------------------------------------------------------------------
# Shell activation
# ---------------------------------------------------------------------------

@test "activates mise for bash shell" {
  _setup_mock_mise
  _source_script

  assert_equal "$MISE_ACTIVATED" "bash"
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

@test "cleans up temporary variables after sourcing" {
  _setup_mock_mise
  _source_script

  assert [ -z "${_mise_trusted+x}" ]
  assert [ -z "${_mise_dir+x}" ]
  assert [ -z "${_mise_cfg+x}" ]
}
