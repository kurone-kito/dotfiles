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
  # Isolate the WSL-detection glob from the real host's Windows-side
  # filesystem (e.g. a real /mnt/c/Users/*/.mise on a WSL host running
  # this suite) by pointing it at a guaranteed-nonexistent directory.
  export DOTFILES_MISE_WSL_USERS_ROOT="$BATS_TEST_TMPDIR/no-windows-users"
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
# WSL: overridable Windows-side glob root
# ---------------------------------------------------------------------------

_require_wsl() {
  { [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null; } \
    || skip "not running on a WSL host"
}

@test "WSL: includes Windows-side mise directories under the overridable root" {
  _require_wsl
  _setup_mock_mise
  mkdir -p "$BATS_TEST_TMPDIR/winusers/alice/.mise" \
    "$BATS_TEST_TMPDIR/winusers/bob/.config/mise"
  export DOTFILES_MISE_WSL_USERS_ROOT="$BATS_TEST_TMPDIR/winusers"

  _source_script

  assert_equal "$MISE_TRUSTED_CONFIG_PATHS" \
    "$HOME/.mise:$HOME/.config/mise:$BATS_TEST_TMPDIR/winusers/alice/.mise:$BATS_TEST_TMPDIR/winusers/bob/.config/mise"
}

@test "WSL: trusts Windows-side mise config files under the overridable root" {
  _require_wsl
  _setup_mock_mise
  mkdir -p "$BATS_TEST_TMPDIR/winusers/alice/.mise" \
    "$BATS_TEST_TMPDIR/winusers/bob/.config/mise"
  touch "$BATS_TEST_TMPDIR/winusers/alice/.mise/config.toml" \
    "$BATS_TEST_TMPDIR/winusers/bob/.config/mise/config.toml"
  export DOTFILES_MISE_WSL_USERS_ROOT="$BATS_TEST_TMPDIR/winusers"

  _source_script

  assert_file_exists "$MISE_MOCK_LOG"
  run grep -c "trust" "$MISE_MOCK_LOG"
  assert_success
  assert_output "2"
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
# ghq trusted paths
# ---------------------------------------------------------------------------

@test "appends ghq-cloned owner paths from chezmoi-ghq-trusted-paths" {
  _setup_mock_mise

  # Create a mock ghq command that returns a fixed root
  cat > "$BATS_TEST_TMPDIR/bin/ghq" << 'MOCK'
#!/bin/sh
if [ "$1" = "root" ]; then echo "$HOME/ghq"; fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/ghq"

  # Create the trusted paths file
  mkdir -p "$HOME/.config/mise"
  printf '%s\n' "github.com/alice" "github.example.com/acme-corp" \
    > "$HOME/.config/mise/chezmoi-ghq-trusted-paths"

  _source_script

  assert_equal "$MISE_TRUSTED_CONFIG_PATHS" \
    "$HOME/.mise:$HOME/.config/mise:$HOME/ghq/github.com/alice:$HOME/ghq/github.example.com/acme-corp"
}

@test "skips ghq trusted paths when ghq is not installed" {
  _setup_mock_mise

  mkdir -p "$HOME/.config/mise"
  printf '%s\n' "github.com/alice" \
    > "$HOME/.config/mise/chezmoi-ghq-trusted-paths"

  # Restrict PATH to only mock mise + basic system dirs (no ghq)
  PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin"

  _source_script

  assert_equal "$MISE_TRUSTED_CONFIG_PATHS" "$HOME/.mise:$HOME/.config/mise"
}

@test "skips ghq trusted paths when file does not exist" {
  _setup_mock_mise
  _source_script

  assert_equal "$MISE_TRUSTED_CONFIG_PATHS" "$HOME/.mise:$HOME/.config/mise"
}

@test "skips blank lines in chezmoi-ghq-trusted-paths" {
  _setup_mock_mise

  cat > "$BATS_TEST_TMPDIR/bin/ghq" << 'MOCK'
#!/bin/sh
if [ "$1" = "root" ]; then echo "$HOME/ghq"; fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/ghq"

  mkdir -p "$HOME/.config/mise"
  printf '%s\n' "" "github.com/alice" "" \
    > "$HOME/.config/mise/chezmoi-ghq-trusted-paths"

  _source_script

  assert_equal "$MISE_TRUSTED_CONFIG_PATHS" \
    "$HOME/.mise:$HOME/.config/mise:$HOME/ghq/github.com/alice"
}

# ---------------------------------------------------------------------------
# config.toml tool entries
# (not templated, so the source file content is the rendered content)
# ---------------------------------------------------------------------------

@test "restricts the pstop github tool to Windows" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^"github:psmux/pstop"' "$config"
  assert_success
  assert_output --partial 'os = ["windows"]'
}

@test "declares the quoted llama.cpp registry tool with prerelease" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep -E '^"llama\.cpp"' "$config"
  assert_success
  assert_output --partial 'prerelease = true'
}

@test "does not restrict the llama.cpp tool by os" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep -E '^"llama\.cpp"' "$config"
  assert_success
  refute_output --partial 'os ='
}

@test "restricts the ttyd tool to Linux and Windows" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^ttyd' "$config"
  assert_success
  assert_output --partial 'os = ["linux", "windows"]'
}

@test "no longer references the deprecated pstop ubi identifier" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep -q '"ubi:marlocarlo/pstop"' "$config"
  assert_failure 1
}

@test "no longer overrides grok with the broken aqua backend" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep -q '"aqua:x.ai/cli/grok"' "$config"
  assert_failure 1
}

@test "uses the grok registry short name" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^grok' "$config"
  assert_success
  assert_output --partial '"latest"'
}

@test "no longer relies on the inert claude-code npm_args opt-in" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep -q 'npm_args = "--ignore-scripts=false"' "$config"
  assert_failure 1
}

@test "allow-lists claude-code's own build scripts" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^"npm:@anthropic-ai/claude-code"' "$config"
  assert_success
  assert_output --partial 'allow_builds = ["@anthropic-ai/claude-code"]'
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

@test "cleans up temporary variables after sourcing" {
  _setup_mock_mise
  _source_script

  assert [ -z "${_mise_trusted+x}" ]
  assert [ -z "${_mise_dir+x}" ]
  assert [ -z "${_mise_win_users+x}" ]
  assert [ -z "${_mise_cfg+x}" ]
  assert [ -z "${_ghq_trust_file+x}" ]
  assert [ -z "${_ghq_root+x}" ]
  assert [ -z "${_pair+x}" ]
}
