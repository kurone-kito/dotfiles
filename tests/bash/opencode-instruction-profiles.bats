#!/usr/bin/env bats
# Regression coverage for OpenCode's compact default and full opt-in profile.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  CONFIG_TEMPLATE="$REPO_ROOT/.chezmoi.toml.tmpl"
  OPENCODE_TEMPLATE="$REPO_ROOT/home/dot_config/opencode/AGENTS.md.tmpl"
  if ! BASE_REF=$(git -C "$REPO_ROOT" merge-base HEAD origin/master); then
    skip 'origin/master has no common ancestor for rendered-output comparisons'
  fi
  TMP_CONFIG="$BATS_TEST_TMPDIR/chezmoi.json"
  TMP_BASE="$BATS_TEST_TMPDIR/base"
  mkdir -p "$TMP_BASE"
}

_write_config() {
  printf '%s\n' "$1" > "$TMP_CONFIG"
}

_render_config() {
  chezmoi execute-template --init --file "$CONFIG_TEMPLATE" \
    --config "$TMP_CONFIG" --config-format json \
    --promptString git.name="Test User" \
    --promptString git.email="test@example.com" \
    --promptString git.signingkey="" \
    --promptString secret.manager="none" \
    --source "$REPO_ROOT" --destination "$BATS_TEST_TMPDIR/home"
}

_render_opencode() {
  chezmoi execute-template --file "$OPENCODE_TEMPLATE" \
    --config "$TMP_CONFIG" --config-format json \
    --source "$REPO_ROOT/home" --destination "$BATS_TEST_TMPDIR/home"
}

@test "chezmoi init preserves absent, Boolean, and invalid OpenCode profile values safely" {
  _write_config '{"data":{}}'
  run --separate-stderr _render_config
  assert_success
  refute_output --partial '[data.opencode]'

  _write_config '{"data":{"opencode":{"extendedInstructions":false}}}'
  run --separate-stderr _render_config
  assert_success
  assert_output --partial '[data.opencode]'
  assert_output --partial 'extendedInstructions = false'

  _write_config '{"data":{"opencode":{"extendedInstructions":true}}}'
  run --separate-stderr _render_config
  assert_success
  assert_output --partial 'extendedInstructions = true'

  _write_config '{"data":{"opencode":{"extendedInstructions":"true"}}}'
  run --separate-stderr _render_config
  assert_success
  assert_stderr --partial 'data.opencode.extendedInstructions must be true or false'
  refute_output --partial '[data.opencode]'

  _write_config '{"data":{"opencode":"invalid"}}'
  run --separate-stderr _render_config
  assert_success
  assert_stderr --partial 'data.opencode is not a table'
  refute_output --partial '[data.opencode]'
}

@test "OpenCode defaults to compact, true exactly preserves the existing full render" {
  _write_config '{"data":{}}'
  run --separate-stderr _render_opencode
  assert_success
  local compact="$output"

  _write_config '{"data":{"opencode":{"extendedInstructions":false}}}'
  run --separate-stderr _render_opencode
  assert_success
  [ "$output" = "$compact" ]

  _write_config '{"data":{"opencode":{"extendedInstructions":"invalid"}}}'
  run --separate-stderr _render_opencode
  assert_success
  assert_stderr --partial 'using compact OpenCode instructions'
  [ "$output" = "$compact" ]

  _write_config '{"data":{"opencode":{"extendedInstructions":true}}}'
  run --separate-stderr _render_opencode
  assert_success
  local extended="$output"

  git -C "$REPO_ROOT" archive "$BASE_REF" \
    home/.chezmoitemplates/ai-agent-user-global \
    home/dot_config/opencode/AGENTS.md.tmpl | tar -x -C "$TMP_BASE"
  chezmoi execute-template --file \
    "$TMP_BASE/home/dot_config/opencode/AGENTS.md.tmpl" \
    --config "$TMP_CONFIG" --config-format json \
    --source "$TMP_BASE/home" --destination "$BATS_TEST_TMPDIR/base-home" \
    > "$BATS_TEST_TMPDIR/base-opencode.md"
  [ "$extended" = "$(cat "$BATS_TEST_TMPDIR/base-opencode.md")" ]

  local compact_words extended_words
  compact_words=$(printf '%s\n' "$compact" | wc -w)
  extended_words=$(printf '%s\n' "$extended" | wc -w)
  [ "$((compact_words * 2))" -le "$extended_words" ]
}

@test "non-OpenCode user-global renders remain byte-identical to the base revision" {
  local rel base_file current_file
  git -C "$REPO_ROOT" archive "$BASE_REF" \
    home/.chezmoitemplates/ai-agent-user-global \
    home/dot_copilot/copilot-instructions.md.tmpl \
    home/dot_codex/AGENTS.md.tmpl \
    home/dot_claude/CLAUDE.md.tmpl \
    home/dot_gemini/GEMINI.md.tmpl \
    home/dot_gemini/AGENTS.md | tar -x -C "$TMP_BASE"

  _write_config '{"data":{}}'
  for rel in \
    dot_copilot/copilot-instructions.md.tmpl \
    dot_codex/AGENTS.md.tmpl \
    dot_claude/CLAUDE.md.tmpl \
    dot_gemini/GEMINI.md.tmpl; do
    base_file="$TMP_BASE/home/$rel"
    current_file="$REPO_ROOT/home/$rel"
    chezmoi execute-template --file "$base_file" \
      --config "$TMP_CONFIG" --config-format json \
      --source "$TMP_BASE/home" --destination "$BATS_TEST_TMPDIR/base-home" \
      > "$BATS_TEST_TMPDIR/base-output"
    chezmoi execute-template --file "$current_file" \
      --config "$TMP_CONFIG" --config-format json \
      --source "$REPO_ROOT/home" --destination "$BATS_TEST_TMPDIR/current-home" \
      > "$BATS_TEST_TMPDIR/current-output"
    cmp "$BATS_TEST_TMPDIR/base-output" "$BATS_TEST_TMPDIR/current-output"
  done
  cmp "$TMP_BASE/home/dot_gemini/AGENTS.md" "$REPO_ROOT/home/dot_gemini/AGENTS.md"
}
