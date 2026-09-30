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
  export DOTFILES_MISE_TRUST_STAMP="$BATS_TEST_TMPDIR/mise-trust-stamp"
  export DOTFILES_MISE_ACTIVATE_CACHE="$BATS_TEST_TMPDIR/mise-activate-cache"
  unset DOTFILES_MISE_ASSUME_WSL
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

@test "restricts the psmux github tool to Windows" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^"github:psmux/psmux"' "$config"
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

@test "restricts the tmux tool to Linux and macOS" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^tmux' "$config"
  assert_success
  assert_output --partial 'os = ["linux", "macos"]'
}

@test "pins 7zip to the aqua:ip7z/7zip backend" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^"aqua:ip7z/7zip"' "$config"
  assert_success
  assert_output --partial '"latest"'
}

@test "pins neovim to the aqua:neovim/neovim backend, not the registry's default vfox backend" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^"aqua:neovim/neovim"' "$config"
  assert_success
  assert_output --partial '"latest"'

  run grep -q '^neovim ' "$config"
  assert_failure 1
}

@test "declares ollama with the plain registry short name" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^ollama' "$config"
  assert_success
  assert_output --partial '"latest"'
}

@test "declares starship with the plain registry short name" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^starship' "$config"
  assert_success
  assert_output --partial '"latest"'
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

@test "tracks playwright/cli at latest now that upstream OIDC trust is restored, unpinned" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^"npm:@playwright/cli"' "$config"
  assert_success
  assert_output --partial '"latest"'
}

@test "allows low downloads for inshellisense past aube's reputation gate, unpinned" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^"npm:@microsoft/inshellisense"' "$config"
  assert_success
  assert_output --partial 'allow_low_downloads = true'
  assert_output --partial 'version = "latest"'
}

@test "allows low downloads for fast-cli past aube's reputation gate, unpinned" {
  local config="$BATS_TEST_DIRNAME/../../home/dot_config/mise/config.toml"

  run grep '^"npm:fast-cli"' "$config"
  assert_success
  assert_output --partial 'allow_low_downloads = true'
  assert_output --partial 'version = "latest"'
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

_setup_recording_mise() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/mise" << 'MOCK'
#!/bin/sh
case "$1" in
  trust)
    echo "$@" >> "${MISE_MOCK_LOG:-/dev/null}"
    ;;
  --version | version)
    if [ -n "${MISE_MOCK_VERSION:-}" ]; then
      printf '%s\n' "$MISE_MOCK_VERSION"
    fi
    ;;
  activate)
    echo "activate $2" >> "${MISE_MOCK_LOG:-/dev/null}"
    if [ "$2" = "bash" ]; then
      cat << 'EOF'
export MISE_ACTIVATED=bash
_mise_selected_node() {
  _d=${PWD:-/}
  _ver=global
  while [ -n "$_d" ] && [ "$_d" != / ]; do
    if [ -f "$_d/mise.toml" ]; then
      _ver=$(awk -F '"' '/^node = / { print $2; exit }' "$_d/mise.toml")
      [ -n "$_ver" ] || _ver=global
      break
    fi
    _d=$(dirname "$_d")
  done
  printf '%s\n' "$_ver"
}
_mise_hook() {
  echo "hook $*" >> "${MISE_MOCK_LOG:-/dev/null}"
  MISE_SELECTED_NODE=$(_mise_selected_node)
  export MISE_SELECTED_NODE
}
_mise_hook_chpwd() {
  echo "chpwd $*" >> "${MISE_MOCK_LOG:-/dev/null}"
  __MISE_BASH_CHPWD_RAN=1
  MISE_SELECTED_NODE=$(_mise_selected_node)
  export MISE_SELECTED_NODE
}
_mise_hook_prompt_command() {
  if [ "${__MISE_BASH_CHPWD_RAN:-0}" = 1 ]; then
    echo "prompt-skip" >> "${MISE_MOCK_LOG:-/dev/null}"
    __MISE_BASH_CHPWD_RAN=0
    unset __MISE_BASH_SKIP_FIRST_PROMPT
    return
  fi
  echo "prompt-hook" >> "${MISE_MOCK_LOG:-/dev/null}"
  MISE_SELECTED_NODE=$(_mise_selected_node)
  export MISE_SELECTED_NODE
}
EOF
    fi
    ;;
esac
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/mise"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

_count_log() {
  if [ ! -f "$MISE_MOCK_LOG" ]; then
    printf '%s\n' 0
    return 0
  fi
  grep -c -e "$1" "$MISE_MOCK_LOG" || true
}

# ---------------------------------------------------------------------------
# WSL trust stamp and non-WSL trust
# ---------------------------------------------------------------------------

@test "WSL: trusts an unchanged config once and trusts it again after a change" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  mkdir -p "$HOME/.config/mise"
  printf '%s\n' 'node = "24"' > "$HOME/.config/mise/config.toml"

  _source_script
  printf '%s\n' 'node = "22"' > "$HOME/.config/mise/config.toml"
  _source_script

  run _count_log '^trust '
  assert_success
  assert_output "2"
}

@test "WSL: trusts a config that appears after the first startup" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  mkdir -p "$HOME/.config/mise"
  printf '%s\n' 'node = "24"' > "$HOME/.config/mise/config.toml"

  _source_script
  mkdir -p "$HOME/.mise"
  printf '%s\n' 'node = "22"' > "$HOME/.mise/config.toml"
  _source_script

  run _count_log '^trust '
  assert_success
  assert_output "2"
}

@test "non-WSL: trusts existing configs on every startup" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=0
  mkdir -p "$HOME/.mise" "$HOME/.config/mise"
  touch "$HOME/.mise/config.toml" "$HOME/.config/mise/config.toml"

  _source_script
  _source_script

  run _count_log '^trust '
  assert_success
  assert_output "4"
}

@test "WSL: directory hook applies and restores the selected tool across enter and leave" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  mkdir -p "$BATS_TEST_TMPDIR/empty-a" "$BATS_TEST_TMPDIR/empty-b" \
    "$BATS_TEST_TMPDIR/proj/sub" "$BATS_TEST_TMPDIR/proj-b"
  printf '%s\n' 'node = "24"' > "$BATS_TEST_TMPDIR/proj/mise.toml"
  printf '%s\n' 'node = "22"' > "$BATS_TEST_TMPDIR/proj-b/mise.toml"

  cd "$BATS_TEST_TMPDIR/empty-a"
  _source_script
  : > "$MISE_MOCK_LOG"

  cd "$BATS_TEST_TMPDIR/empty-b"
  _mise_hook_chpwd
  run _count_log '^chpwd '
  assert_success
  assert_output "0"
  assert [ -z "${MISE_SELECTED_NODE:-}" ]

  cd "$BATS_TEST_TMPDIR/proj"
  _mise_hook_chpwd
  assert_equal "$MISE_SELECTED_NODE" "24"

  cd "$BATS_TEST_TMPDIR/proj/sub"
  _mise_hook_chpwd
  assert_equal "$MISE_SELECTED_NODE" "24"
  run _count_log '^chpwd '
  assert_success
  assert_output "1"

  cd "$BATS_TEST_TMPDIR/empty-a"
  _mise_hook_chpwd
  assert_equal "$MISE_SELECTED_NODE" "global"

  cd "$BATS_TEST_TMPDIR/proj-b"
  _mise_hook_chpwd
  assert_equal "$MISE_SELECTED_NODE" "22"
}

@test "WSL: a cwd template and --force still run the directory hook" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  mkdir -p "$BATS_TEST_TMPDIR/tmpl/a" "$BATS_TEST_TMPDIR/tmpl/b"
  printf '%s\n' 'node = "24" # {{cwd}}' > "$BATS_TEST_TMPDIR/tmpl/mise.toml"

  cd "$BATS_TEST_TMPDIR/tmpl/a"
  _source_script
  : > "$MISE_MOCK_LOG"

  cd "$BATS_TEST_TMPDIR/tmpl/b"
  _mise_hook_chpwd
  run _count_log '^chpwd '
  assert_success
  assert_output "1"

  _mise_hook --force
  run _count_log '^hook '
  assert_success
  assert_output "1"
}

@test "WSL: reuses a cached activate script without skipping activation" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15

  _source_script
  _source_script

  run _count_log '^activate '
  assert_success
  assert_output "1"
  assert_equal "$MISE_ACTIVATED" "bash"
}

@test "WSL: prompt hook applies a same-directory config edit" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  mkdir -p "$BATS_TEST_TMPDIR/empty-a" "$BATS_TEST_TMPDIR/proj"
  printf '%s\n' 'node = "24"' > "$BATS_TEST_TMPDIR/proj/mise.toml"

  cd "$BATS_TEST_TMPDIR/empty-a"
  _source_script
  cd "$BATS_TEST_TMPDIR/proj"
  _mise_hook_chpwd
  assert_equal "$MISE_SELECTED_NODE" "24"

  printf '%s\n' 'node = "22"' > "$BATS_TEST_TMPDIR/proj/mise.toml"
  _mise_hook_prompt_command
  assert_equal "$MISE_SELECTED_NODE" "22"
  run _count_log '^prompt-hook$'
  assert_success
  assert_output "1"
}

@test "WSL: mise/config.toml still changes the directory hook" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  mkdir -p "$BATS_TEST_TMPDIR/empty-a" "$BATS_TEST_TMPDIR/proj/mise"
  printf '%s\n' 'node = "24"' > "$BATS_TEST_TMPDIR/proj/mise/config.toml"

  cd "$BATS_TEST_TMPDIR/empty-a"
  _source_script
  : > "$MISE_MOCK_LOG"
  cd "$BATS_TEST_TMPDIR/proj"
  _mise_hook_chpwd
  run _count_log '^chpwd '
  assert_success
  assert_output "1"
}

@test "WSL: editing config.local.toml refreshes the activate cache" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  mkdir -p "$HOME/.config/mise"

  _source_script
  printf '%s\n' 'not_found_auto_install = false' \
    > "$HOME/.config/mise/config.local.toml"
  _source_script

  run _count_log '^activate '
  assert_success
  assert_output "2"
}

@test "WSL: a failed hook-env does not stick the fingerprint" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  export MISE_MOCK_FAIL_ONCE="$BATS_TEST_TMPDIR/fail-once"
  cat > "$BATS_TEST_TMPDIR/bin/mise" << 'MOCK'
#!/bin/sh
case "$1" in
  --version | version)
    printf '%s\n' "${MISE_MOCK_VERSION:-}"
    ;;
  activate)
    echo "activate $2" >> "${MISE_MOCK_LOG:-/dev/null}"
    cat << 'EOF'
_mise_hook_prompt_command() {
  local previous_exit_status=$?
  eval "$(mise hook-env --reason precmd)"
  return $previous_exit_status
}
EOF
    ;;
  hook-env)
    echo "hook-env" >> "${MISE_MOCK_LOG:-/dev/null}"
    if [ ! -f "${MISE_MOCK_FAIL_ONCE}" ]; then
      : > "${MISE_MOCK_FAIL_ONCE}"
      exit 1
    fi
    printf '%s\n' 'export MISE_HOOK_APPLIED=1'
    ;;
esac
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/mise"

  mkdir -p "$BATS_TEST_TMPDIR/empty-a"
  cd "$BATS_TEST_TMPDIR/empty-a"
  _source_script
  printf '%s\n' 'node = "24"' > "$BATS_TEST_TMPDIR/empty-a/mise.toml"
  : > "$MISE_MOCK_LOG"
  unset MISE_HOOK_APPLIED

  _mise_hook_prompt_command
  [ -z "${MISE_HOOK_APPLIED:-}" ]
  _mise_hook_prompt_command
  assert_equal "$MISE_HOOK_APPLIED" "1"
  _mise_hook_prompt_command

  run _count_log '^hook-env$'
  assert_success
  assert_output "2"
}

@test "WSL: a failed activation hook does not stick the fingerprint" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  export MISE_MOCK_FAIL_ONCE="$BATS_TEST_TMPDIR/fail-activate"
  cat > "$BATS_TEST_TMPDIR/bin/mise" << 'MOCK'
#!/bin/sh
case "$1" in
  --version | version)
    printf '%s\n' "${MISE_MOCK_VERSION:-}"
    ;;
  activate)
    echo "activate $2" >> "${MISE_MOCK_LOG:-/dev/null}"
    cat << 'EOF'
__MISE_HOOK_ENABLED=1
_mise_hook() {
  local previous_exit_status=$?
  eval "$(mise hook-env -s bash "$@")"
  return $previous_exit_status
}
_mise_hook_prompt_command() {
  local previous_exit_status=$?
  if [ "${__MISE_BASH_SKIP_FIRST_PROMPT:-0}" = 1 ]; then
    unset __MISE_BASH_SKIP_FIRST_PROMPT
    echo "prompt-skip" >> "${MISE_MOCK_LOG:-/dev/null}"
    return $previous_exit_status
  fi
  echo "prompt-hook" >> "${MISE_MOCK_LOG:-/dev/null}"
  eval "$(mise hook-env --reason precmd)"
  return $previous_exit_status
}
if [ "$__MISE_HOOK_ENABLED" = "1" ]; then
  __MISE_BASH_SKIP_FIRST_PROMPT=1
  _mise_hook --force
fi
EOF
    ;;
  hook-env)
    echo "hook-env $*" >> "${MISE_MOCK_LOG:-/dev/null}"
    if [ ! -f "${MISE_MOCK_FAIL_ONCE}" ]; then
      : > "${MISE_MOCK_FAIL_ONCE}"
      exit 1
    fi
    printf '%s\n' 'export MISE_HOOK_APPLIED=1'
    ;;
esac
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/mise"

  mkdir -p "$BATS_TEST_TMPDIR/empty-a"
  cd "$BATS_TEST_TMPDIR/empty-a"
  _source_script

  [ -z "${MISE_HOOK_APPLIED:-}" ]
  [ -z "${_DOTFILES_MISE_FP:-}" ]
  run _count_log '^hook-env '
  assert_success
  assert_output "1"

  _mise_hook_prompt_command
  assert_equal "$MISE_HOOK_APPLIED" "1"
  [ -n "${_DOTFILES_MISE_FP:-}" ]
  run _count_log '^hook-env '
  assert_success
  assert_output "2"

  _mise_hook_prompt_command
  run _count_log '^hook-env '
  assert_success
  assert_output "2"
}

@test "WSL: the activation snapshot runs after the startup hook" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  cat > "$BATS_TEST_TMPDIR/bin/mise" << 'MOCK'
#!/bin/sh
case "$1" in
  --version | version)
    printf '%s\n' "${MISE_MOCK_VERSION:-}"
    ;;
  activate)
    echo "activate $2" >> "${MISE_MOCK_LOG:-/dev/null}"
    cat << 'EOF'
_mise_hook() {
  echo "hook $*" >> "${MISE_MOCK_LOG:-/dev/null}"
  export MISE_HOOK_RAN=1
}
_mise_hook --force
export MISE_SNAPSHOT="${MISE_HOOK_RAN:-0}"
EOF
    ;;
esac
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/mise"

  _source_script

  assert_equal "$MISE_SNAPSHOT" "1"
  assert_equal "$MISE_HOOK_RAN" "1"
  [ -n "${_DOTFILES_MISE_FP:-}" ]
  run _count_log '^hook '
  assert_success
  assert_output "1"
}

@test "WSL: cached activate keeps a leading shim directory on PATH" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  export MISE_DATA_DIR="$BATS_TEST_TMPDIR/mise-data"
  _source_script

  PATH="/sentinel:/usr/bin"
  unset __MISE_ORIG_PATH
  eval "$({
    printf '%s\n' "export PATH='${MISE_DATA_DIR}/shims:/frozen'"
    printf '%s\n' "export __MISE_ORIG_PATH='/frozen'"
    printf '%s\n' "export PATH=\"/exe:\$PATH\""
    printf '%s\n' "export PATH='/usr/bin:/${MISE_DATA_DIR}/shims'"
  } | _dotfiles_mise_strip_frozen_path)"

  case "$PATH" in
    "/exe:${MISE_DATA_DIR}/shims:/sentinel:/usr/bin") ;;
    *) printf 'PATH=%s\n' "$PATH" >&2; return 1 ;;
  esac
  assert_equal "$__MISE_ORIG_PATH" "/sentinel:/usr/bin"
  case "$PATH" in
    *frozen*) return 1 ;;
  esac
}

@test "WSL: editing MISE_CONFIG_FILE still runs the directory hook" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  mkdir -p "$BATS_TEST_TMPDIR/empty-a"
  printf '%s\n' 'node = "24"' > "$BATS_TEST_TMPDIR/selected.toml"
  export MISE_CONFIG_FILE="$BATS_TEST_TMPDIR/selected.toml"

  cd "$BATS_TEST_TMPDIR/empty-a"
  _source_script
  : > "$MISE_MOCK_LOG"
  printf '%s\n' 'node = "22"' > "$BATS_TEST_TMPDIR/selected.toml"
  _mise_hook_prompt_command

  run _count_log '^prompt-hook$'
  assert_success
  assert_output "1"
}

@test "WSL: cached activate script does not replace PATH" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  cat > "$BATS_TEST_TMPDIR/bin/mise" << 'MOCK'
#!/bin/sh
case "$1" in
  --version | version)
    printf '%s\n' "${MISE_MOCK_VERSION:-}"
    ;;
  activate)
    echo "activate $2" >> "${MISE_MOCK_LOG:-/dev/null}"
    printf '%s\n' "export PATH='/frozen'"
    printf '%s\n' 'export MISE_ACTIVATED=bash'
    printf '%s\n' 'export __MISE_ORIG_PATH="${__MISE_ORIG_PATH:-$PATH}"'
    ;;
esac
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/mise"

  _source_script
  PATH="/sentinel:${PATH}"
  _source_script

  case "$PATH" in
    /frozen | /frozen:*) return 1 ;;
  esac
  case "$PATH" in
    *"/sentinel"*) ;;
    *) return 1 ;;
  esac
}

@test "WSL: does not cache activate output when the version is empty" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  unset MISE_MOCK_VERSION

  _source_script
  _source_script

  run _count_log '^activate '
  assert_success
  assert_output "2"
}

# ---------------------------------------------------------------------------
# Caller scratch names
# ---------------------------------------------------------------------------

# Scratch names the profile assigns while it runs (issue #530). Sourcing
# alone can only expose the first seven; the rest are assigned inside
# $(...) or by helpers a source never reaches, so the tests below also
# call those helpers directly. _data only exists inside a subshell and
# cannot be told apart at all.
_SCRATCH_NAMES=(
  _cfg _mtime _shell _hash _size _stamp _tmp
  _trust_dir _bin _mt _ver _key _cache_dir _cache_file _out _cfg_hash
  _env _data _file_hash
)

# $1: sentinel (set to a marker value) or unset
_preset_scratch_names() {
  local _name
  for _name in "${_SCRATCH_NAMES[@]}"; do
    if [ "$1" = unset ]; then
      unset "$_name"
    else
      printf -v "$_name" '%s' "caller-$_name"
    fi
  done
}

# $1: the mode given to _preset_scratch_names; names every change at once
_assert_scratch_names_kept() {
  local _name _changed=
  for _name in "${_SCRATCH_NAMES[@]}"; do
    if [ "$1" = unset ]; then
      [ -z "${!_name+x}" ] || _changed="$_changed $_name"
    else
      [ "${!_name-}" = "caller-$_name" ] || _changed="$_changed $_name"
    fi
  done
  assert_equal "$_changed" ""
}

# A first WSL startup: a config with no stamp yet, so the trust path
# runs, and a mise version, so the activate cache is used.
_setup_wsl_first_startup() {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=1
  export MISE_MOCK_VERSION=2026.9.15
  mkdir -p "$HOME/.config/mise"
  printf '%s\n' 'node = "24"' > "$HOME/.config/mise/config.toml"
}

_source_and_call_helpers() {
  _source_script
  export DOTFILES_MISE_ACTIVATE_CACHE="$BATS_TEST_TMPDIR/direct-cache"
  _dotfiles_mise_activate_cached bash > /dev/null
  _dotfiles_mise_fp_add_file "$HOME/.config/mise/config.toml" > /dev/null
  _dotfiles_mise_trust_dir_mtime > /dev/null
}

@test "WSL: keeps the caller's _cfg when sourced" {
  _setup_wsl_first_startup
  _cfg=caller-cfg

  _source_script

  assert_equal "$_cfg" "caller-cfg"
}

@test "non-WSL: keeps the caller's _cfg when sourced" {
  _setup_recording_mise
  export DOTFILES_MISE_ASSUME_WSL=0
  mkdir -p "$HOME/.config/mise"
  touch "$HOME/.config/mise/config.toml"
  _cfg=caller-cfg

  _source_script

  assert_equal "$_cfg" "caller-cfg"
}

@test "WSL: leaves _mtime unset when the caller had none" {
  _setup_wsl_first_startup
  unset _mtime

  _source_script

  assert [ -z "${_mtime+x}" ]
}

@test "WSL: keeps every scratch name the caller had set" {
  _setup_wsl_first_startup
  _preset_scratch_names sentinel

  _source_and_call_helpers

  _assert_scratch_names_kept sentinel
}

@test "WSL: leaves every scratch name unset when the caller had none" {
  _setup_wsl_first_startup
  _preset_scratch_names unset

  _source_and_call_helpers

  _assert_scratch_names_kept unset
}

# Declaring and assigning on one line (local _out=$(...)) would replace
# the failing status with local's own, and the partial output below
# would be cached.
@test "WSL: a failed mise activate leaves no cached script" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/mise" << 'MOCK'
#!/bin/sh
case "$1" in
  --version) echo 2026.9.15 ;;
  activate)
    echo 'export MISE_PARTIAL=1'
    exit 1
    ;;
esac
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/mise"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export DOTFILES_MISE_ASSUME_WSL=1

  _source_script

  assert [ -z "$(find "$DOTFILES_MISE_ACTIVATE_CACHE" -type f 2>/dev/null)" ]
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
