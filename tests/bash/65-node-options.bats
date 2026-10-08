#!/usr/bin/env bats
# Tests for the shared NODE_OPTIONS default in conf.d/65-node-options.sh.
#
# The script appends --network-family-autoselection-attempt-timeout=2000 to
# NODE_OPTIONS when that exact option is absent and the resolved `node`
# accepts it. Startup behavior is exercised through real `bash -li` and
# `zsh -li` invocations over the copied dot_profile/dot_bashrc/zsh chain (the
# approach of conf-d-double-sourcing.bats) with a mocked `node`, and the
# tokenizer is compared against real Node.js where the host provides one.
# cspell:words autoselection ETIMEOUT mawk gawk

bats_require_minimum_version 1.5.0

OPTION='--network-family-autoselection-attempt-timeout'
DEFAULT="$OPTION=2000"

# Explicit values in every spelling Node.js accepts; each must stay untouched.
PRESENT_FIXTURES=(
  "$OPTION=5000"
  "$OPTION 5000"
  "\"$OPTION=5000\""
  "\"$OPTION\" 5000"
  "--network_family_autoselection_attempt_timeout=5000"
  "--network-family_autoselection-attempt_timeout 5000"
  "--max-old-space-size=4096 $OPTION=5000 --trace-warnings"
  "$OPTION=\"5000\""
  "\"$OPTION\"=5000"
)

# Inputs that do not name the exact option; the default is appended after them.
ABSENT_FIXTURES=(
  "--max-old-space-size=4096"
  "--network-family-autoselection"
  "--no-network-family-autoselection"
  "--Network-Family-Autoselection-Attempt-Timeout=1"
  "--require \"/tmp/a b/x.js\""
  "--require \"/tmp/$OPTION=1/x.js\""
  "--require 'single quoted'"
  "--require=\"a b.js\""
  "\"\""
  " "
  "--require \"/tmp/日本語 é/x.js\""
  $'--max-old-space-size=1\t'"$OPTION=3"
  "--require \"a\\\"b\" --max-old-space-size=1"
)

# Inputs Node.js itself rejects; the script must leave them alone.
MALFORMED_FIXTURES=(
  "--max-old-space-size=4096 \"unterminated"
  "\"ends with escape\\"
)

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  REPO_HOME="$BATS_TEST_DIRNAME/../../home"
  SCRIPT="$REPO_HOME/dot_config/shell/conf.d/65-node-options.sh"
  REAL_NODE="$(command -v node 2> /dev/null || true)"
  REAL_CHEZMOI="$(command -v chezmoi 2> /dev/null || true)"
  _ORIG_PATH="$PATH"

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.config/shell/conf.d"
  cp "$REPO_HOME/dot_config/shell/conf.d/60-mise.sh" "$SCRIPT" \
    "$HOME/.config/shell/conf.d/"
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
  unset MISE_STATE_DIR XDG_STATE_HOME NODE_OPTIONS MISE_MOCK_NODE_DIR
  unset NODE_MOCK_MODE

  # A curated PATH: only what the startup files and mocks need, so a node on
  # the host (or the CI runner) cannot leak into the "node is absent" cases.
  SAFE_BIN_DIR="$BATS_TEST_TMPDIR/safe-bin"
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$SAFE_BIN_DIR" "$MOCK_BIN"
  local tool tool_path
  for tool in awk basename bash cat chmod cp cut date dirname env grep head id \
    ln ls mkdir mktemp mv printf readlink rm sed sh sha256sum shasum sleep \
    sort stat tail touch tr uname wc zsh; do
    tool_path="$(command -v "$tool" 2> /dev/null)" || continue
    ln -sf "$tool_path" "$SAFE_BIN_DIR/$tool"
  done
  export PATH="$MOCK_BIN:$SAFE_BIN_DIR"

  export NODE_MOCK_LOG="$BATS_TEST_TMPDIR/node-mock.log"
  : > "$NODE_MOCK_LOG"
  install_mise_mock
  install_node_mock "$MOCK_BIN"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

require_zsh() {
  command -v zsh > /dev/null 2>&1 || skip "zsh not available"
}

# A node that records how the probe called it. NODE_MOCK_MODE selects the
# outcome: ok (default), unsupported (exit 9, as Node.js rejects a disallowed
# NODE_OPTIONS entry) or fail.
install_node_mock() {
  cat > "$1/node" << 'MOCK'
#!/bin/sh
printf 'argv=%s NODE_OPTIONS=%s MISE_AUTO_INSTALL=%s MISE_EXEC_AUTO_INSTALL=%s MISE_OFFLINE=%s\n' \
  "$*" "${NODE_OPTIONS-<unset>}" "${MISE_AUTO_INSTALL-<unset>}" \
  "${MISE_EXEC_AUTO_INSTALL-<unset>}" "${MISE_OFFLINE-<unset>}" \
  >> "$NODE_MOCK_LOG"
case "${NODE_MOCK_MODE:-ok}" in
  unsupported)
    echo "node: --network-family-autoselection-attempt-timeout= is not allowed in NODE_OPTIONS" >&2
    exit 9
    ;;
  fail)
    echo "boom" >&2
    exit 1
    ;;
esac
exit 0
MOCK
  chmod +x "$1/node"
}

# A mise whose `activate` puts MISE_MOCK_NODE_DIR on PATH, the way the real
# activation puts a managed node there.
install_mise_mock() {
  cat > "$MOCK_BIN/mise" << 'MOCK'
#!/bin/sh
case "$1" in
  trust) exit 0 ;;
  activate)
    if [ -n "${MISE_MOCK_NODE_DIR:-}" ]; then
      printf 'export PATH="%s:$PATH"\n' "$MISE_MOCK_NODE_DIR"
    fi
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/mise"
}

# Run a fresh login+interactive shell and print its NODE_OPTIONS. Pass the
# literal word __unset__ to start without the variable.
login_options() {
  local shell_name="$1" value="$2"
  local -a launcher=(env)
  if [ "$value" = __unset__ ]; then
    launcher+=(-u NODE_OPTIONS)
  else
    launcher+=("NODE_OPTIONS=$value")
  fi
  case "$shell_name" in
    bash)
      run --separate-stderr "${launcher[@]}" bash -li -c 'printf "%s" "$NODE_OPTIONS"'
      ;;
    zsh)
      run --separate-stderr "${launcher[@]}" ZDOTDIR="$ZDOTDIR" zsh -li -c 'printf "%s" "$NODE_OPTIONS"'
      ;;
  esac
  # An empty NODE_OPTIONS must mean "left untouched", never "the shell broke".
  [ "$status" -eq 0 ] || fail "$shell_name login shell failed ($status): $stderr"
}

# Startup must not say anything about the option, the probe, or the mock.
assert_quiet_startup() {
  local noise
  for noise in NODE_OPTIONS "node:" boom autoselection "not allowed"; do
    [[ "$stderr" != *"$noise"* ]] || fail "startup stderr mentions '$noise': $stderr"
  done
}

# ---------------------------------------------------------------------------
# bash: merge behavior through the real login+interactive startup
# ---------------------------------------------------------------------------

@test "bash: exports the default when NODE_OPTIONS is unset" {
  login_options bash __unset__
  assert_success
  assert_output "$DEFAULT"
  assert_quiet_startup
}

@test "bash: exports the default when NODE_OPTIONS is empty" {
  login_options bash ''
  assert_success
  assert_output "$DEFAULT"
}

@test "bash: keeps unrelated options and adds the default once, after them" {
  login_options bash '--max-old-space-size=4096 --trace-warnings'
  assert_success
  assert_output "--max-old-space-size=4096 --trace-warnings $DEFAULT"
}

@test "bash: an explicit value in any Node.js spelling is left untouched" {
  local value
  for value in "${PRESENT_FIXTURES[@]}"; do
    login_options bash "$value"
    [ "$status" -eq 0 ] || fail "startup failed for [$value]"
    [ "$output" = "$value" ] || fail "[$value] became [$output]"
  done
}

@test "bash: inputs that do not name the exact option get the default appended" {
  local value
  for value in "${ABSENT_FIXTURES[@]}"; do
    login_options bash "$value"
    [ "$status" -eq 0 ] || fail "startup failed for [$value]"
    [ "$output" = "$value $DEFAULT" ] || fail "[$value] became [$output]"
  done
}

@test "bash: malformed NODE_OPTIONS is left untouched and quiet" {
  local value
  for value in "${MALFORMED_FIXTURES[@]}"; do
    login_options bash "$value"
    [ "$status" -eq 0 ] || fail "startup failed for [$value]"
    [ "$output" = "$value" ] || fail "[$value] became [$output]"
    assert_quiet_startup
  done
}

@test "bash: command substitutions and metacharacters in NODE_OPTIONS never execute" {
  local sentinel="$BATS_TEST_TMPDIR/pwned" value
  value="--require \"\$(touch $sentinel)\" ; \`touch $sentinel\` | & * ~ \$HOME"

  login_options bash "$value"
  assert_success
  assert_output "$value $DEFAULT"
  assert_file_not_exists "$sentinel"
}

@test "bash: a node that is absent leaves the environment untouched and quiet" {
  rm -f "$MOCK_BIN/node"

  login_options bash '--max-old-space-size=4096'
  assert_success
  assert_output '--max-old-space-size=4096'
  assert_quiet_startup

  login_options bash __unset__
  assert_output ''
}

@test "bash: a node that rejects the option leaves the environment untouched and quiet" {
  export NODE_MOCK_MODE=unsupported

  login_options bash '--max-old-space-size=4096'
  assert_success
  assert_output '--max-old-space-size=4096'
  assert_quiet_startup

  login_options bash __unset__
  assert_output ''
  assert_quiet_startup
}

@test "bash: a node that fails leaves the environment untouched and quiet" {
  export NODE_MOCK_MODE=fail

  login_options bash __unset__
  assert_success
  assert_output ''
  assert_quiet_startup
}

@test "bash: without awk a non-empty NODE_OPTIONS is left untouched" {
  run env PATH="$MOCK_BIN:/nonexistent" NODE_OPTIONS='--max-old-space-size=4096' \
    "$SAFE_BIN_DIR/sh" -c '. "$1"; printf "%s" "$NODE_OPTIONS"' _ "$SCRIPT"
  assert_success
  assert_output '--max-old-space-size=4096'
}

# ---------------------------------------------------------------------------
# bash: idempotence and inheritance
# ---------------------------------------------------------------------------

@test "bash: re-sourcing the script keeps one copy" {
  run --separate-stderr env -u NODE_OPTIONS bash -li -c \
    '. "$HOME/.config/shell/conf.d/65-node-options.sh"; . "$HOME/.config/shell/conf.d/65-node-options.sh"; printf "%s" "$NODE_OPTIONS"'
  assert_success
  assert_output "$DEFAULT"
}

@test "bash: a nested interactive shell and a plain subshell keep one copy" {
  run --separate-stderr env -u NODE_OPTIONS bash -li -c \
    'bash -i -c "printf %s \"\$NODE_OPTIONS\"" 2>/dev/null; printf "|"; (printf "%s" "$NODE_OPTIONS"); printf "|"; bash -c "printf %s \"\$NODE_OPTIONS\""'
  assert_success
  assert_output "$DEFAULT|$DEFAULT|$DEFAULT"
}

@test "bash: a child process inherits the default" {
  run --separate-stderr env -u NODE_OPTIONS bash -li -c 'sh -c "printf %s \"\$NODE_OPTIONS\""'
  assert_success
  assert_output "$DEFAULT"
}

@test "bash: the probe passes a non-empty script, only the option, and the mise guards" {
  login_options bash '--max-old-space-size=4096'
  assert_success

  run cat "$NODE_MOCK_LOG"
  assert_output "argv=-e 0 NODE_OPTIONS=$DEFAULT MISE_AUTO_INSTALL=0 MISE_EXEC_AUTO_INSTALL=0 MISE_OFFLINE=1"
}

@test "bash: no probe runs when the option is already present" {
  login_options bash "$OPTION=5000"
  assert_success
  run cat "$NODE_MOCK_LOG"
  assert_output ''
}

@test "bash: probes the node that mise puts on PATH during 60-mise.sh" {
  rm -f "$MOCK_BIN/node"
  mkdir -p "$BATS_TEST_TMPDIR/mise-node"
  install_node_mock "$BATS_TEST_TMPDIR/mise-node"

  login_options bash __unset__
  assert_output '' # without the mise-provided node, nothing is added

  export MISE_MOCK_NODE_DIR="$BATS_TEST_TMPDIR/mise-node"
  login_options bash __unset__
  assert_success
  assert_output "$DEFAULT"
}

@test "bash: an unexported NODE_OPTIONS is honored and not duplicated" {
  run env -u NODE_OPTIONS sh -c 'NODE_OPTIONS="$1"; . "$2"; printf "%s" "$NODE_OPTIONS"' \
    _ "$OPTION=5000" "$SCRIPT"
  assert_success
  assert_output "$OPTION=5000"

  run env -u NODE_OPTIONS sh -c \
    'NODE_OPTIONS=--max-old-space-size=1; . "$1"; sh -c "printf %s \"\$NODE_OPTIONS\""' _ "$SCRIPT"
  assert_success
  assert_output "--max-old-space-size=1 $DEFAULT"
}

@test "bash: sourcing under set -eu never aborts the caller" {
  local mode
  for mode in ok unsupported fail; do
    export NODE_MOCK_MODE=$mode
    run env -u NODE_OPTIONS sh -eu -c '. "$1"; printf "done:%s" "${NODE_OPTIONS-}"' _ "$SCRIPT"
    [ "$status" -eq 0 ] || fail "sh -eu aborted with node mode $mode: $output"
    run env NODE_OPTIONS='--max-old-space-size=4096' bash -eu -c \
      '. "$1"; printf "done:%s" "${NODE_OPTIONS-}"' _ "$SCRIPT"
    [ "$status" -eq 0 ] || fail "bash -eu aborted with node mode $mode: $output"
  done

  export NODE_MOCK_MODE=ok
  run env -u NODE_OPTIONS sh -eu -c '. "$1"; printf "%s" "${NODE_OPTIONS-}"' _ "$SCRIPT"
  assert_success
  assert_output "$DEFAULT"
}

@test "bash: a user-owned conf.d file that sorts first keeps its own value" {
  printf 'export NODE_OPTIONS="%s=5000"\n' "$OPTION" \
    > "$HOME/.config/shell/conf.d/64-node-options-local.sh"

  login_options bash __unset__
  assert_output "$OPTION=5000"
}

# ---------------------------------------------------------------------------
# zsh: the same contract through the zsh startup files
# ---------------------------------------------------------------------------

@test "zsh: exports the default when NODE_OPTIONS is unset or empty" {
  require_zsh

  login_options zsh __unset__
  assert_success
  assert_output "$DEFAULT"

  login_options zsh ''
  assert_output "$DEFAULT"
}

@test "zsh: keeps unrelated options and adds the default once, after them" {
  require_zsh

  login_options zsh '--max-old-space-size=4096 --trace-warnings'
  assert_success
  assert_output "--max-old-space-size=4096 --trace-warnings $DEFAULT"
}

@test "zsh: an explicit value in any Node.js spelling is left untouched" {
  require_zsh
  local value
  for value in "${PRESENT_FIXTURES[@]}"; do
    login_options zsh "$value"
    [ "$status" -eq 0 ] || fail "startup failed for [$value]"
    [ "$output" = "$value" ] || fail "[$value] became [$output]"
  done
}

@test "zsh: inputs that do not name the exact option get the default appended" {
  require_zsh
  local value
  for value in "${ABSENT_FIXTURES[@]}"; do
    login_options zsh "$value"
    [ "$status" -eq 0 ] || fail "startup failed for [$value]"
    [ "$output" = "$value $DEFAULT" ] || fail "[$value] became [$output]"
  done
}

@test "zsh: command substitutions and metacharacters in NODE_OPTIONS never execute" {
  require_zsh
  local sentinel="$BATS_TEST_TMPDIR/pwned" value
  value="--require \"\$(touch $sentinel)\" ; \`touch $sentinel\` | & * ~ \$HOME"

  login_options zsh "$value"
  assert_success
  assert_output "$value $DEFAULT"
  assert_file_not_exists "$sentinel"
}

@test "zsh: absent, rejecting and failing node leave the environment untouched" {
  require_zsh

  export NODE_MOCK_MODE=unsupported
  login_options zsh '--max-old-space-size=4096'
  assert_output '--max-old-space-size=4096'
  assert_quiet_startup

  export NODE_MOCK_MODE=fail
  login_options zsh __unset__
  assert_output ''
  assert_quiet_startup

  unset NODE_MOCK_MODE
  rm -f "$MOCK_BIN/node"
  login_options zsh __unset__
  assert_output ''
}

@test "zsh: re-sourcing keeps one copy and a child process inherits it" {
  require_zsh

  run --separate-stderr env -u NODE_OPTIONS ZDOTDIR="$ZDOTDIR" zsh -li -c \
    '. "$HOME/.config/shell/conf.d/65-node-options.sh"; sh -c "printf %s \"\$NODE_OPTIONS\""'
  assert_success
  assert_output "$DEFAULT"
}

@test "zsh: probes the node that mise puts on PATH during 60-mise.sh" {
  require_zsh
  rm -f "$MOCK_BIN/node"
  mkdir -p "$BATS_TEST_TMPDIR/mise-node"
  install_node_mock "$BATS_TEST_TMPDIR/mise-node"
  export MISE_MOCK_NODE_DIR="$BATS_TEST_TMPDIR/mise-node"

  login_options zsh __unset__
  assert_success
  assert_output "$DEFAULT"
}

@test "zsh: a nested interactive shell keeps one copy" {
  require_zsh

  run --separate-stderr env -u NODE_OPTIONS ZDOTDIR="$ZDOTDIR" zsh -li -c \
    'zsh -i -c "printf %s \"\$NODE_OPTIONS\""'
  assert_success
  assert_output "$DEFAULT"
}

@test "zsh: a user-owned conf.d file that sorts first keeps its own value" {
  require_zsh
  printf 'export NODE_OPTIONS="%s=5000"\n' "$OPTION" \
    > "$HOME/.config/shell/conf.d/64-node-options-local.sh"

  login_options zsh __unset__
  assert_output "$OPTION=5000"
}

# ---------------------------------------------------------------------------
# The tokenizer must give the same verdict under every installed awk
# ---------------------------------------------------------------------------

@test "every installed awk gives the same verdicts on the fixtures" {
  local impl impl_path dir value found=0
  for impl in awk mawk gawk original-awk; do
    impl_path="$(command -v "$impl" 2> /dev/null)" || continue
    found=1
    dir="$BATS_TEST_TMPDIR/awk-$impl"
    mkdir -p "$dir"
    ln -sf "$impl_path" "$dir/awk"

    for value in "${PRESENT_FIXTURES[@]}" "${MALFORMED_FIXTURES[@]}"; do
      run env PATH="$dir:$MOCK_BIN:$SAFE_BIN_DIR" NODE_OPTIONS="$value" \
        sh -c '. "$1"; printf "%s" "$NODE_OPTIONS"' _ "$SCRIPT"
      [ "$output" = "$value" ] || fail "$impl: [$value] became [$output]"
    done
    for value in "${ABSENT_FIXTURES[@]}"; do
      run env PATH="$dir:$MOCK_BIN:$SAFE_BIN_DIR" NODE_OPTIONS="$value" \
        sh -c '. "$1"; printf "%s" "$NODE_OPTIONS"' _ "$SCRIPT"
      [ "$output" = "$value $DEFAULT" ] || fail "$impl: [$value] became [$output]"
    done
  done
  [ "$found" -eq 1 ] || skip "no awk implementation found"
}

# ---------------------------------------------------------------------------
# Real Node.js: the verdicts must agree with how Node.js itself parses them
# ---------------------------------------------------------------------------

# Link the host node in and skip when it is missing or rejects the option.
require_real_node() {
  [ -n "$REAL_NODE" ] || skip "node not available"
  mkdir -p "$BATS_TEST_TMPDIR/real-node"
  ln -sf "$REAL_NODE" "$BATS_TEST_TMPDIR/real-node/node"
  env NODE_OPTIONS="$DEFAULT" "$BATS_TEST_TMPDIR/real-node/node" -e 0 > /dev/null 2>&1 \
    || skip "host node does not accept $OPTION"
  rm -f "$MOCK_BIN/node"
  export PATH="$BATS_TEST_TMPDIR/real-node:$PATH"
}

@test "real node: a login shell reports 2000 and an explicit alternative stays effective" {
  require_real_node

  run --separate-stderr env -u NODE_OPTIONS bash -li -c \
    'node -p "net.getDefaultAutoSelectFamilyAttemptTimeout()"'
  assert_success
  assert_output 2000

  run --separate-stderr env "NODE_OPTIONS=$OPTION=500" bash -li -c \
    'node -p "net.getDefaultAutoSelectFamilyAttemptTimeout()"'
  assert_success
  assert_output 500
}

@test "real node: present fixtures keep their value and absent fixtures get 2000" {
  require_real_node
  local value
  mkdir -p "$BATS_TEST_TMPDIR/req dir" "$BATS_TEST_TMPDIR/$OPTION=1"
  : > "$BATS_TEST_TMPDIR/req dir/x.js"
  : > "$BATS_TEST_TMPDIR/$OPTION=1/x.js"

  for value in "${PRESENT_FIXTURES[@]}"; do
    value="${value//5000/777}"
    run --separate-stderr env "NODE_OPTIONS=$value" bash -li -c \
      'node -p "net.getDefaultAutoSelectFamilyAttemptTimeout()"'
    [ "$output" = 777 ] || fail "[$value] reported [$output], node.js says it should keep 777"
  done

  for value in \
    "--max-old-space-size=4096" \
    "--network-family-autoselection" \
    "--no-network-family-autoselection" \
    "--require \"$BATS_TEST_TMPDIR/req dir/x.js\"" \
    "--require \"$BATS_TEST_TMPDIR/$OPTION=1/x.js\"" \
    "--require=\"$BATS_TEST_TMPDIR/req dir/x.js\""; do
    run --separate-stderr env "NODE_OPTIONS=$value" bash -li -c \
      'node -p "net.getDefaultAutoSelectFamilyAttemptTimeout()"'
    [ "$output" = 2000 ] || fail "[$value] reported [$output], expected the 2000 default"
  done
}

# ---------------------------------------------------------------------------
# chezmoi's bitwarden template function runs `bw` as a child process
# ---------------------------------------------------------------------------

@test "a chezmoi bitwarden template child inherits the default from a login shell" {
  [ -n "$REAL_CHEZMOI" ] || skip "chezmoi not available"
  ln -sf "$REAL_CHEZMOI" "$SAFE_BIN_DIR/chezmoi"

  local src="$BATS_TEST_TMPDIR/source" dst="$BATS_TEST_TMPDIR/dest"
  mkdir -p "$src/.chezmoitemplates" "$dst"
  cp "$REPO_HOME/.chezmoitemplates/get-secret" \
    "$REPO_HOME/.chezmoitemplates/read-local-file" "$src/.chezmoitemplates/"
  printf '%s' '{{ template "get-secret" dict "item" "example-item" "field" "password" "ctx" . }}' \
    > "$BATS_TEST_TMPDIR/wrapper.tmpl"
  printf '{ "data": { "secret": { "manager": "bitwarden" } } }\n' \
    > "$BATS_TEST_TMPDIR/chezmoi.json"

  export BW_MOCK_LOG="$BATS_TEST_TMPDIR/bw-mock.log"
  cat > "$MOCK_BIN/bw" << 'MOCK'
#!/bin/sh
printf 'args=%s NODE_OPTIONS=%s\n' "$*" "${NODE_OPTIONS-<unset>}" >> "$BW_MOCK_LOG"
if [ "$1" = get ] && [ "$2" = item ]; then
  printf '%s' '{"login":{"password":"mock-password"}}'
  exit 0
fi
exit 1
MOCK
  chmod +x "$MOCK_BIN/bw"

  run --separate-stderr env -u NODE_OPTIONS bash -li -c \
    'chezmoi execute-template --file "$1" --config "$2" --config-format json --source "$3" --destination "$4"' \
    _ "$BATS_TEST_TMPDIR/wrapper.tmpl" "$BATS_TEST_TMPDIR/chezmoi.json" "$src" "$dst"
  assert_success
  assert_output 'mock-password'

  run cat "$BW_MOCK_LOG"
  assert_output "args=get item example-item NODE_OPTIONS=$DEFAULT"
}
