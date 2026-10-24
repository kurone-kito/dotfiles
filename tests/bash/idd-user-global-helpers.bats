#!/usr/bin/env bats
#
# Tests for the user-global IDD activation helper wrappers (dotfiles issue
# #676; originally introduced by #646 under roadmap #643). Each execution
# wrapper runs upstream kurone-kito/idd-skill commit
# 77befdd4030757464bed7f31c7dfe6d0a404a18b (v0.17.0) through npx.
#
# The runtime cases fetch that tarball on the first run, so they need
# network access to codeload.github.com. They also need a Node.js that
# satisfies the upstream engines (22.23.2+, 24.2.0+, or 26+): on an older
# Node the upstream CLI prints nothing and exits 0. A missing npx fails the
# test; it is never skipped.

bats_require_minimum_version 1.5.0

UPSTREAM_COMMIT='77befdd4030757464bed7f31c7dfe6d0a404a18b'

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  BIN_DIR="$REPO_ROOT/home/dot_local/bin"

  # Keep the real npm cache, so a rerun reuses the fetched tarball. Read it
  # before HOME is overridden below.
  local npm_cache=''
  npm_cache="$(npm config get cache 2>/dev/null || true)"
  if [ -n "$npm_cache" ]; then
    export npm_config_cache="$npm_cache"
  fi

  # Every home and XDG root is an empty directory under this test's tmp
  # dir, so the real user-global config and payload cannot leak in.
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
}

# Fail with a clear message when npx is missing. The runtime cases run
# the wrappers through npx, so a missing npx must not pass silently.
require_npx() {
  if ! command -v npx >/dev/null 2>&1; then
    echo "npx is required on PATH (Node.js 22.23.2+, 24.2.0+, or 26+)" >&2
    return 1
  fi
}

# Expose one wrapper on PATH under the name chezmoi deploys it as.
put_on_path() {
  local name="$1"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  ln -sf "$BIN_DIR/executable_$name" "$BATS_TEST_TMPDIR/bin/$name"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

# Create a git repository with no IDD files and make it the working
# directory for the helper run.
enter_empty_repo() {
  local repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  cd "$repo" || return 1
}

# Report the Node.js version next to a helper failure, because an old Node
# fails silently (see the header note).
report_failure() {
  echo "stderr: $stderr" >&2
  echo "node: $(node --version 2>&1 || echo 'not found')" >&2
}

# Run one POSIX wrapper with a PATH that holds neither node nor npx, so the
# wrapper's fail-loud guard is the only code that can answer.
run_without_npx() {
  local name="$1"
  shift
  mkdir -p "$BATS_TEST_TMPDIR/bare-bin"
  ln -sf "$BIN_DIR/executable_$name" "$BATS_TEST_TMPDIR/bare-bin/$name"
  run --separate-stderr env -i PATH="$BATS_TEST_TMPDIR/bare-bin" /bin/sh "$BATS_TEST_TMPDIR/bare-bin/$name" "$@"
}

# A stand-in node for the Node.js floor probe. The probe reads
# process.versions.node, so substitute FAKE_NODE_VERSION into the probe and
# evaluate it with the real node. The wrapper's own expression then decides.
# Shell builtins only: the test PATH holds no sed.
make_versioned_node() {
  mkdir -p "$1"
  cat > "$1/node" <<'NODE'
#!/bin/sh
if [ "$1" = "-v" ]; then echo "v$FAKE_NODE_VERSION"; exit 0; fi
case "$2" in
  *process.versions.node*) ;;
  *) exit 1 ;;
esac
pre=${2%%process.versions.node*}
post=${2#*process.versions.node}
exec "$REAL_NODE" -e "$pre'$FAKE_NODE_VERSION'$post"
NODE
  chmod +x "$1/node"
}

@test "executable_idd-activation invokes the upstream v0.17.0 commit" {
  run grep -F -- "exec npx --yes --package \"https://codeload.github.com/kurone-kito/idd-skill/tar.gz/$UPSTREAM_COMMIT\" idd-activation \"\$@\"" "$BIN_DIR/executable_idd-activation"
  assert_success
}

@test "executable_idd-activation.ps1 pins upstream v0.17.0 commit" {
  assert_file_contains "$BIN_DIR/executable_idd-activation.ps1" "$UPSTREAM_COMMIT"
}

@test "executable_idd-effective-config invokes the upstream v0.17.0 commit" {
  run grep -F -- "exec npx --yes --package \"https://codeload.github.com/kurone-kito/idd-skill/tar.gz/$UPSTREAM_COMMIT\" idd-effective-config \"\$@\"" "$BIN_DIR/executable_idd-effective-config"
  assert_success
}

@test "executable_idd-effective-config.ps1 pins upstream v0.17.0 commit" {
  assert_file_contains "$BIN_DIR/executable_idd-effective-config.ps1" "$UPSTREAM_COMMIT"
}

@test "idd-activation prints active=false in a git repository with no IDD files" {
  require_npx
  put_on_path idd-activation
  enter_empty_repo

  run --separate-stderr idd-activation
  assert_success
  # The reason pins the classification: an active=false from the wrong
  # directory (one with a policy but no payload) would read differently.
  if ! jq -e '.active == false and .reason == "no-activation-rule"' <<<"$output" >/dev/null; then
    echo "expected {\"active\": false, \"reason\": \"no-activation-rule\"}, got: $output" >&2
    report_failure
    return 1
  fi
}

@test "idd-effective-config reports no repository policy in a git repository with no IDD files" {
  require_npx
  put_on_path idd-effective-config
  enter_empty_repo

  run --separate-stderr idd-effective-config --no-user-global
  assert_success
  if ! jq -e '.repository.policyExists == false' <<<"$output" >/dev/null; then
    echo "unexpected effective-config output: $output" >&2
    report_failure
    return 1
  fi
}

@test "idd-activation fails loudly with a message when npx is missing" {
  run_without_npx idd-activation
  assert_failure
  assert_stderr --partial 'npx is required'
}

@test "idd-effective-config fails loudly with a message when npx is missing" {
  run_without_npx idd-effective-config
  assert_failure
  assert_stderr --partial 'npx is required'
}

@test "idd-activation fails loudly when Node.js is below the upstream floor" {
  # A fake npx passes the first guard. A fake node reports v20 and fails the
  # floor probe, so only the Node.js floor guard can answer.
  local fake_bin="$BATS_TEST_TMPDIR/old-node-bin"
  mkdir -p "$fake_bin"
  printf '#!/bin/sh\nif [ "$1" = "-v" ]; then echo v20.11.0; exit 0; fi\nexit 1\n' > "$fake_bin/node"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/npx"
  chmod +x "$fake_bin/node" "$fake_bin/npx"
  ln -sf "$BIN_DIR/executable_idd-activation" "$fake_bin/idd-activation"

  run --separate-stderr env -i PATH="$fake_bin" /bin/sh "$fake_bin/idd-activation"
  assert_failure
  assert_output ''
  assert_stderr --partial 'needs Node.js 22.23.2+, 24.2.0+, or 26+ (found: v20.11.0)'
}

@test "each helper has a .cmd launcher that dispatches to its .ps1 twin" {
  assert_file_contains "$BIN_DIR/executable_idd-activation.cmd" "$UPSTREAM_COMMIT"
  assert_file_contains "$BIN_DIR/executable_idd-effective-config.cmd" "$UPSTREAM_COMMIT"
  assert_file_contains "$BIN_DIR/executable_idd-activation.cmd" 'PS1_PATH=%SCRIPT_DIR%idd-activation\.ps1'
  assert_file_contains "$BIN_DIR/executable_idd-effective-config.cmd" 'PS1_PATH=%SCRIPT_DIR%idd-effective-config\.ps1'
  assert_file_contains "$BIN_DIR/executable_idd-activation.cmd" 'exit /b %ERRORLEVEL%'
  assert_file_contains "$BIN_DIR/executable_idd-effective-config.cmd" 'exit /b %ERRORLEVEL%'
}

@test "the .cmd launchers are excluded from non-Windows applies" {
  printf '%s\n' '{ "data": {} }' > "$BATS_TEST_TMPDIR/chezmoi-config.json"

  run --separate-stderr chezmoi execute-template --file "$REPO_ROOT/home/.chezmoiignore.tmpl" \
    --config "$BATS_TEST_TMPDIR/chezmoi-config.json" --config-format json \
    --source "$REPO_ROOT" --destination "$BATS_TEST_TMPDIR"
  assert_success
  assert_line '.local/bin/idd-activation.cmd'
  assert_line '.local/bin/idd-effective-config.cmd'
}

@test "the Node.js floor accepts 22.23.2, 24.2.0 and 26 and rejects the boundaries below" {
  local name v fake_bin="$BATS_TEST_TMPDIR/boundary-bin" real_node
  real_node="$(command -v node || true)"
  if [ -z "$real_node" ]; then
    echo "node is required to evaluate the Node.js floor probe" >&2
    return 1
  fi
  make_versioned_node "$fake_bin"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/npx"
  chmod +x "$fake_bin/npx"
  ln -sf "$BIN_DIR/executable_idd-activation" "$fake_bin/idd-activation"
  ln -sf "$BIN_DIR/executable_idd-effective-config" "$fake_bin/idd-effective-config"

  for name in idd-activation idd-effective-config; do
    for v in 22.23.2 22.23.3 24.2.0 24.21.0 26.0.0; do
      run --separate-stderr env -i PATH="$fake_bin" REAL_NODE="$real_node" FAKE_NODE_VERSION="$v" /bin/sh "$fake_bin/$name"
      if [ "$status" -ne 0 ]; then
        echo "$name: Node $v should pass the floor (status $status): $stderr" >&2
        return 1
      fi
    done
    for v in 22.23.1 22.18.0 23.11.0 24.1.9 25.0.0 20.11.0; do
      run --separate-stderr env -i PATH="$fake_bin" REAL_NODE="$real_node" FAKE_NODE_VERSION="$v" /bin/sh "$fake_bin/$name"
      if [ "$status" -eq 0 ] || [[ "$stderr" != *'needs Node.js'* ]]; then
        echo "$name: Node $v should be rejected (status $status): $stderr" >&2
        return 1
      fi
    done
  done
}
