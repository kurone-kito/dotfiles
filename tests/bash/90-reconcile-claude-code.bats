#!/usr/bin/env bats
# Tests for run_after_90-reconcile-claude-code.sh.tmpl.
# Exercises: env.DISABLE_AUTOUPDATER JSON merge-patch reconciliation on
# ~/.claude/settings.json (create/preserve/idempotent/fail-loudly-on-
# invalid-JSON), and the stray mise-managed-Node @anthropic-ai/claude-code
# copy detection/removal (only when the mise-managed npm copy is
# confirmed present).
#
# The fixture under test has zero go-template directives, so it is run
# directly from home/ rather than via a hand-maintained pre-rendered
# fixture (avoids drift between the fixture and the shipped script).
#
# SAFETY: every test overrides HOME to a bats tmpdir and mocks `mise`
# (and, where relevant, `jq`) via a PATH-prepended bin dir. setup()
# asserts both overrides actually took effect before any test body
# runs, so a broken mock can never fall through to the real machine's
# ~/.claude/settings.json or real mise-managed node_modules.

bats_require_minimum_version 1.5.0

setup() {
  # Captured before any override below: this is the real, unmodified
  # HOME of the process running bats. Used only by the preflight guard.
  _REAL_HOME="$HOME"

  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  FIXTURE="$BATS_TEST_DIRNAME/../../home/run_after_90-reconcile-claude-code.sh.tmpl"

  BIN_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN_DIR"
  _ORIG_PATH="$PATH"
  export PATH="$BIN_DIR:$PATH"

  NODE_DIR="$BATS_TEST_TMPDIR/node"
  MANAGED_DIR="$BATS_TEST_TMPDIR/managed"
  # Deliberately a directory distinct from NODE_DIR: npm's resolved
  # global prefix is not guaranteed to equal the Node.js install
  # directory (a user-level .npmrc or NPM_CONFIG_PREFIX can override
  # it), so the fixtures must prove the script follows the *resolved*
  # prefix rather than silently falling back to NODE_DIR.
  NPM_PREFIX_DIR="$BATS_TEST_TMPDIR/npm-prefix"
  mkdir -p "$NODE_DIR/lib/node_modules" "$NODE_DIR/bin" "$MANAGED_DIR" \
    "$NPM_PREFIX_DIR/lib/node_modules" "$NPM_PREFIX_DIR/bin"

  # Preflight guard: fail fast rather than silently touching the real
  # machine if the HOME override did not take effect (e.g. an empty
  # BATS_TEST_TMPDIR would make this a no-op override).
  [ -n "$BATS_TEST_TMPDIR" ]
  [ "$HOME" = "$BATS_TEST_TMPDIR/home" ]
  [ "$HOME" != "$_REAL_HOME" ]
}

teardown() {
  export PATH="$_ORIG_PATH"
}

write_mise_mock() {
  # $1: 0 or 1 -> whether `mise where npm:@anthropic-ai/claude-code`
  #     resolves successfully (default: 1, resolves)
  # $2: 0 or 1 -> whether `mise exec npm:@anthropic-ai/claude-code --
  #     claude --version` succeeds, i.e. the managed copy actually
  #     works (default: 1, works)
  local managed_resolves="${1:-1}"
  local managed_works="${2:-1}"
  cat > "$BIN_DIR/mise" << MOCK
#!/bin/bash
if [ "\$1" = "where" ] && [ "\$2" = "node" ]; then
  echo "$NODE_DIR"
  exit 0
fi
if [ "\$1" = "where" ] && [ "\$2" = "npm:@anthropic-ai/claude-code" ]; then
  if [ "$managed_resolves" = "1" ]; then
    echo "$MANAGED_DIR"
    exit 0
  else
    exit 1
  fi
fi
if [ "\$1" = "exec" ] && [ "\$2" = "npm:@anthropic-ai/claude-code" ]; then
  if [ "$managed_works" = "1" ]; then
    exit 0
  else
    exit 1
  fi
fi
exit 1
MOCK
  chmod +x "$BIN_DIR/mise"
  # Preflight guard: confirm the mock actually wins PATH resolution.
  [ "$(command -v mise)" = "$BIN_DIR/mise" ]

  write_npm_mock 1
}

write_npm_mock() {
  # $1: 0 or 1 -> whether `npm config get prefix` resolves successfully
  #     (default: 1, resolves to NPM_PREFIX_DIR)
  local prefix_resolves="${1:-1}"
  mkdir -p "$NODE_DIR/bin"
  cat > "$NODE_DIR/bin/npm" << MOCK
#!/bin/bash
if [ "\$1" = "config" ] && [ "\$2" = "get" ] && [ "\$3" = "prefix" ]; then
  if [ "$prefix_resolves" = "1" ]; then
    echo "$NPM_PREFIX_DIR"
    exit 0
  else
    exit 1
  fi
fi
exit 1
MOCK
  chmod +x "$NODE_DIR/bin/npm"
}

write_stray_copy() {
  mkdir -p "$NPM_PREFIX_DIR/lib/node_modules/@anthropic-ai/claude-code/bin"
  touch "$NPM_PREFIX_DIR/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
  ln -sf '../lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe' "$NPM_PREFIX_DIR/bin/claude"
}

@test "mise absent: whole script no-ops without touching settings.json" {
  export PATH="/usr/bin:/bin"
  # Preflight guard: don't assume /usr/bin:/bin lacks mise on every
  # host this suite might run on -- confirm it's genuinely
  # unresolvable before invoking the script, so a host where mise
  # happens to live under one of those directories fails the test
  # setup loudly instead of silently exercising the real mise-managed
  # environment.
  ! command -v mise &>/dev/null || {
    echo "test setup bug: mise still resolvable on the scoped PATH" >&2
    return 1
  }
  run bash "$FIXTURE"
  assert_success
  assert_output --partial "mise not found; skipping Claude Code autoupdater repair."
  assert_file_not_exists "$HOME/.claude/settings.json"
}

@test "settings.json absent: created with env.DISABLE_AUTOUPDATER=1" {
  write_mise_mock
  run bash "$FIXTURE"
  assert_success
  assert_file_exists "$HOME/.claude/settings.json"
  run jq -e '.env.DISABLE_AUTOUPDATER == "1"' "$HOME/.claude/settings.json"
  assert_success
}

@test "existing settings.json: only env.DISABLE_AUTOUPDATER changes, other keys preserved" {
  write_mise_mock
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" << 'JSON'
{
  "permissions": { "allow": ["Bash(git:*)"] },
  "env": { "OTHER_VAR": "keep-me" }
}
JSON
  run bash "$FIXTURE"
  assert_success
  run jq -e '.env.DISABLE_AUTOUPDATER == "1"' "$HOME/.claude/settings.json"
  assert_success
  run jq -e '.env.OTHER_VAR == "keep-me"' "$HOME/.claude/settings.json"
  assert_success
  run jq -e '.permissions.allow == ["Bash(git:*)"]' "$HOME/.claude/settings.json"
  assert_success
}

@test "already \"1\": no write occurs (byte-identical file)" {
  write_mise_mock
  mkdir -p "$HOME/.claude"
  printf '{"env":{"DISABLE_AUTOUPDATER":"1"}}' > "$HOME/.claude/settings.json"
  before_hash="$(sha256sum "$HOME/.claude/settings.json")"
  run bash "$FIXTURE"
  assert_success
  assert_output --partial "already set to \"1\""
  after_hash="$(sha256sum "$HOME/.claude/settings.json")"
  [ "$before_hash" = "$after_hash" ]
}

@test "invalid JSON: fails loudly, non-zero exit, file left untouched" {
  write_mise_mock
  mkdir -p "$HOME/.claude"
  printf '{not valid json' > "$HOME/.claude/settings.json"
  before_hash="$(sha256sum "$HOME/.claude/settings.json")"
  run bash "$FIXTURE"
  assert_failure
  assert_output --partial "invalid JSON"
  after_hash="$(sha256sum "$HOME/.claude/settings.json")"
  [ "$before_hash" = "$after_hash" ]
}

@test "non-object env key: fails loudly, non-zero exit, file left untouched" {
  write_mise_mock
  mkdir -p "$HOME/.claude"
  printf '{"env": "not-an-object"}' > "$HOME/.claude/settings.json"
  before_hash="$(sha256sum "$HOME/.claude/settings.json")"
  run bash "$FIXTURE"
  assert_failure
  after_hash="$(sha256sum "$HOME/.claude/settings.json")"
  [ "$before_hash" = "$after_hash" ]
}

@test "env:false (JSON false, not string): fails loudly, not silently treated as empty object" {
  # Regression test: jq's `//` operator substitutes for both `null`
  # and `false`, so a naive `.env // {}` would silently treat this as
  # an empty object and overwrite it instead of rejecting it.
  write_mise_mock
  mkdir -p "$HOME/.claude"
  printf '{"env": false}' > "$HOME/.claude/settings.json"
  before_hash="$(sha256sum "$HOME/.claude/settings.json")"
  run bash "$FIXTURE"
  assert_failure
  after_hash="$(sha256sum "$HOME/.claude/settings.json")"
  [ "$before_hash" = "$after_hash" ]
}

@test "settings.json is a symlink: fails loudly, symlink left untouched" {
  # Regression test: the atomic-replace pattern (mktemp + mv, or
  # Python's os.replace) replaces whatever inode sits at the
  # destination path -- if settings.json is itself a symlink, that
  # would silently sever the link and put a plain file there instead
  # of updating the link's target.
  write_mise_mock
  mkdir -p "$HOME/.claude"
  real_target="$BATS_TEST_TMPDIR/real-settings.json"
  printf '{}' > "$real_target"
  ln -s "$real_target" "$HOME/.claude/settings.json"
  run bash "$FIXTURE"
  assert_failure
  assert_output --partial "is a symlink"
  assert_symlink_to "$real_target" "$HOME/.claude/settings.json"
}

@test "jq absent, python3 available: falls back to python3 and succeeds" {
  write_mise_mock
  # Build a PATH scoped to only the mise mock plus symlinks to the
  # coreutils the script needs (mkdir/mktemp/mv/rm) and python3, with
  # jq deliberately excluded -- regardless of where the host's real jq
  # binary happens to live, it cannot be resolved from this PATH.
  local bash_bin python3_bin
  bash_bin="$(command -v bash)"
  python3_bin="$(command -v python3 || true)"
  if [ -z "${python3_bin}" ]; then
    skip "python3 not available on this host; cannot exercise the fallback path"
  fi
  NO_JQ_DIR="$BATS_TEST_TMPDIR/no-jq-bin"
  mkdir -p "$NO_JQ_DIR"
  for cmd in mkdir mktemp mv rm; do
    ln -sf "$(command -v "$cmd")" "$NO_JQ_DIR/$cmd"
  done
  ln -sf "${python3_bin}" "$NO_JQ_DIR/python3"
  export PATH="$BIN_DIR:$NO_JQ_DIR"
  ! command -v jq &>/dev/null || {
    echo "test setup bug: jq still resolvable after PATH scoping" >&2
    return 1
  }
  mkdir -p "$HOME/.claude"
  printf '{"permissions":{"allow":["x"]},"env":{"OTHER":"keep-me"}}' > "$HOME/.claude/settings.json"

  run "$bash_bin" "$FIXTURE"
  assert_success
  assert_output --partial "Set env.DISABLE_AUTOUPDATER=\"1\""
  # The stray-copy check does not depend on jq/python3 and must still run.
  assert_output --partial "No stray @anthropic-ai/claude-code copy found"
  run python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['env']['DISABLE_AUTOUPDATER']=='1'; assert d['env']['OTHER']=='keep-me'; assert d['permissions']['allow']==['x']" "$HOME/.claude/settings.json"
  assert_success
}

@test "neither jq nor python3 available: fails loudly, stray-copy check still runs" {
  write_mise_mock
  local bash_bin
  bash_bin="$(command -v bash)"
  NONE_DIR="$BATS_TEST_TMPDIR/no-jq-no-python3-bin"
  mkdir -p "$NONE_DIR"
  for cmd in mkdir mktemp mv rm; do
    ln -sf "$(command -v "$cmd")" "$NONE_DIR/$cmd"
  done
  export PATH="$BIN_DIR:$NONE_DIR"
  ! command -v jq &>/dev/null || {
    echo "test setup bug: jq still resolvable after PATH scoping" >&2
    return 1
  }
  ! command -v python3 &>/dev/null || {
    echo "test setup bug: python3 still resolvable after PATH scoping" >&2
    return 1
  }

  run "$bash_bin" "$FIXTURE"
  assert_failure
  assert_output --partial "neither jq nor python3 found"
  assert_file_not_exists "$HOME/.claude/settings.json"
  # The stray-copy check does not depend on jq/python3 and must still run.
  assert_output --partial "No stray @anthropic-ai/claude-code copy found"
}

@test "npm global prefix not resolvable: stray-copy check skipped (fail-closed)" {
  # Regression test: npm's resolved global prefix is not guaranteed to
  # equal the Node.js install directory (a user-level .npmrc or
  # NPM_CONFIG_PREFIX can override it, like on Windows). When the
  # prefix can't be resolved, the check must be skipped entirely
  # rather than falling back to a guessed (and potentially wrong) path.
  write_mise_mock
  write_npm_mock 0
  run bash "$FIXTURE"
  assert_success
  assert_output --partial "npm global prefix not resolvable"
}

@test "npm prefix resolution uses the mise-managed node, not an earlier PATH decoy" {
  # Regression test: bin/npm is itself a script with a
  # '#!/usr/bin/env node' shebang, which resolves via the *ambient*
  # PATH -- not necessarily node_dir specifically. Without prepending
  # node_dir/bin to PATH for that one invocation, an unrelated 'node'
  # earlier on PATH (e.g. an older system install) would run instead,
  # and the resolved prefix would reflect *that* node, not the
  # mise-managed one.
  #
  # Real npm's shebang is honored by making $NODE_DIR/bin/npm a script
  # whose #!/usr/bin/env node line genuinely goes through PATH lookup;
  # since the interpreter it resolves to only needs to *execute*, not
  # actually be Node.js, two decoy "node" interpreters (one on the
  # pre-existing PATH, one at node_dir/bin) each just print a
  # distinguishable, hardcoded prefix so the test can tell which one
  # actually ran.
  write_mise_mock

  decoy_node_dir="$BATS_TEST_TMPDIR/decoy-node-bin"
  mkdir -p "$decoy_node_dir"
  cat > "$decoy_node_dir/node" << 'DECOY'
#!/bin/bash
echo "/decoy/wrong/prefix"
DECOY
  chmod +x "$decoy_node_dir/node"
  # Ahead of $NODE_DIR/bin (never itself added to PATH by the script)
  # on the ambient PATH used to run the fixture, simulating an
  # unrelated system/older node found first.
  export PATH="$decoy_node_dir:$PATH"

  cat > "$NODE_DIR/bin/node" << CORRECT
#!/bin/bash
echo "$NPM_PREFIX_DIR"
CORRECT
  chmod +x "$NODE_DIR/bin/node"
  cat > "$NODE_DIR/bin/npm" << 'REALNPM'
#!/usr/bin/env node
console.log("unused: the fake node interpreter above ignores this file's content entirely");
REALNPM
  chmod +x "$NODE_DIR/bin/npm"

  # Planted at the *correct* resolved prefix. If the buggy decoy node
  # ran instead, the script would look under /decoy/wrong/prefix/...,
  # never find this, and wrongly report "no stray copy found" even
  # though one exists -- exactly the failure mode described.
  write_stray_copy

  run bash "$FIXTURE"
  assert_success
  assert_output --partial "Removed stray @anthropic-ai/claude-code copy"
  refute_output --partial "No stray @anthropic-ai/claude-code copy found"
  refute_output --partial "/decoy/wrong/prefix"
  assert_dir_not_exists "$NPM_PREFIX_DIR/lib/node_modules/@anthropic-ai/claude-code"
}

@test "no stray copy: no-op, idempotent" {
  write_mise_mock
  run bash "$FIXTURE"
  assert_success
  assert_output --partial "No stray @anthropic-ai/claude-code copy found"
  assert_dir_not_exists "$NPM_PREFIX_DIR/lib/node_modules/@anthropic-ai/claude-code"
}

@test "stray copy + managed copy present: dir and bin shim both removed" {
  write_mise_mock 1
  write_stray_copy
  run bash "$FIXTURE"
  assert_success
  assert_output --partial "Removed stray @anthropic-ai/claude-code copy"
  assert_dir_not_exists "$NPM_PREFIX_DIR/lib/node_modules/@anthropic-ai/claude-code"
  assert_file_not_exists "$NPM_PREFIX_DIR/bin/claude"
  # Never touches the mise-managed copy itself.
  assert_dir_exists "$MANAGED_DIR"
}

@test "stray copy present, managed dir resolves but claude does not work: stray copy left in place" {
  # Regression test: a resolvable mise-managed install directory alone
  # does not prove the managed 'claude' actually works -- an
  # interrupted or failed npm-backend install can leave the directory
  # in place without a functional binary. The repair must not delete
  # the stray copy in that case (it could be the only working one).
  write_mise_mock 1 0
  write_stray_copy
  run bash "$FIXTURE"
  assert_success
  assert_output --partial "does not appear to work"
  assert_output --partial "leaving the stray copy in place"
  assert_dir_exists "$NPM_PREFIX_DIR/lib/node_modules/@anthropic-ai/claude-code"
  assert_file_exists "$NPM_PREFIX_DIR/bin/claude"
}

@test "settings failure does not skip stray-copy cleanup (both effects observable in one run)" {
  # Regression test: the settings-reconciliation and stray-copy-cleanup
  # steps are independent and must both run even when the first one
  # fails loudly (verifies the settings_status pattern, not just that
  # each step works in isolation).
  write_mise_mock 1
  mkdir -p "$HOME/.claude"
  printf '{not valid json' > "$HOME/.claude/settings.json"
  write_stray_copy
  run bash "$FIXTURE"
  assert_failure
  assert_output --partial "invalid JSON"
  assert_output --partial "Removed stray @anthropic-ai/claude-code copy"
  assert_dir_not_exists "$NPM_PREFIX_DIR/lib/node_modules/@anthropic-ai/claude-code"
  assert_file_not_exists "$NPM_PREFIX_DIR/bin/claude"
}

@test "stray copy present, managed copy unresolvable: stray copy left in place" {
  write_mise_mock 0
  write_stray_copy
  run bash "$FIXTURE"
  assert_success
  assert_output --partial "leaving the stray copy in place"
  assert_dir_exists "$NPM_PREFIX_DIR/lib/node_modules/@anthropic-ai/claude-code"
  assert_file_exists "$NPM_PREFIX_DIR/bin/claude"
}
