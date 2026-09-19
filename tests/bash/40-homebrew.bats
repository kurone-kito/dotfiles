#!/usr/bin/env bats
# Tests for the Homebrew shell initialization script.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/40-homebrew.sh"
  _ORIG_PATH="$PATH"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

# ---------------------------------------------------------------------------
# Missing dependency
# ---------------------------------------------------------------------------

@test "completes without error when brew is not available" {
  run bash "$SCRIPT_PATH"
  assert_success
}

# ---------------------------------------------------------------------------
# Brew detection and shellenv evaluation
# ---------------------------------------------------------------------------

@test "evaluates brew shellenv when brew is in PATH" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/brew" << 'MOCK'
#!/bin/sh
if [ "$1" = "shellenv" ]; then
  echo 'export HOMEBREW_TEST=loaded'
fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/brew"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

  . "$SCRIPT_PATH"

  assert_equal "$HOMEBREW_TEST" "loaded"
}

@test "resolves brew once before evaluating shellenv" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/brew" << 'MOCK'
#!/bin/sh
if [ "$1" = "shellenv" ]; then
  echo 'export HOMEBREW_TEST=loaded'
fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/brew"
  export PATH="$BATS_TEST_TMPDIR/bin"

  LOOKUP_LOG="$BATS_TEST_TMPDIR/command-lookups"
  : > "$LOOKUP_LOG"
  command() {
    if [ "$1" = "-v" ] && [ "$2" = "brew" ]; then
      printf '%s\n' "$2" >> "$LOOKUP_LOG"
    fi
    builtin command "$@"
  }
  export LOOKUP_LOG

  . "$SCRIPT_PATH"

  unset -f command
  lookup_count=0
  while IFS= read -r _lookup; do
    lookup_count=$((lookup_count + 1))
  done < "$LOOKUP_LOG"
  assert_equal "$lookup_count" "1"
  assert_equal "$HOMEBREW_TEST" "loaded"
}

@test "uses a standard Homebrew location when PATH has no brew" {
  fixture_brew="$BATS_TEST_TMPDIR/fallback/bin/brew"
  mkdir -p "${fixture_brew%/brew}"
  cat > "$fixture_brew" << 'MOCK'
#!/bin/sh
if [ "$1" = "shellenv" ]; then
  echo 'export HOMEBREW_PREFIX=fallback'
fi
MOCK
  chmod +x "$fixture_brew"
  fixture_script="$BATS_TEST_TMPDIR/40-homebrew-fallback.sh"
  sed \
    -e "s|/home/linuxbrew/.linuxbrew/bin/brew|$fixture_brew|g" \
    -e "s|/opt/homebrew/bin/brew|$fixture_brew|g" \
    -e "s|/usr/local/bin/brew|$fixture_brew|g" \
    "$SCRIPT_PATH" > "$fixture_script"

  export PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"
  unset HOMEBREW_PREFIX
  command() {
    if [ "$1" = "-v" ] && [ "$2" = "brew" ]; then
      return 1
    fi
    builtin command "$@"
  }

  . "$fixture_script"

  unset -f command
  assert_equal "$HOMEBREW_PREFIX" "fallback"
}

@test "keeps all supported standard Homebrew fallback locations" {
  run grep -F "/home/linuxbrew/.linuxbrew/bin/brew" "$SCRIPT_PATH"
  assert_success
  run grep -F "/opt/homebrew/bin/brew" "$SCRIPT_PATH"
  assert_success
  run grep -F "/usr/local/bin/brew" "$SCRIPT_PATH"
  assert_success
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

@test "find_brew function is cleaned up after sourcing" {
  . "$SCRIPT_PATH"

  run type find_brew
  assert_failure
}

@test "BREW variable is unset after sourcing" {
  . "$SCRIPT_PATH"

  assert [ -z "${BREW+x}" ]
}
