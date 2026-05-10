#!/usr/bin/env bats
# Tests for the Neovim environment configuration (05-nvim.sh).

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  SCRIPT_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/05-nvim.sh"
}

# ---------------------------------------------------------------------------
# NVIM_NO_BG_WAIT — suppress DSR background detection
# ---------------------------------------------------------------------------

@test "exports NVIM_NO_BG_WAIT=1" {
  unset NVIM_NO_BG_WAIT
  . "$SCRIPT_PATH"
  assert_equal "$NVIM_NO_BG_WAIT" "1"
}

@test "unconditionally sets NVIM_NO_BG_WAIT=1" {
  export NVIM_NO_BG_WAIT=0
  . "$SCRIPT_PATH"
  assert_equal "$NVIM_NO_BG_WAIT" "1"
}
