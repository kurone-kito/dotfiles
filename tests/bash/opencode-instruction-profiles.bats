#!/usr/bin/env bats
# Regression coverage for OpenCode's compact default and full opt-in profile,
# and for the user-global spans that the extended OpenCode render shares with
# the other agents' renders. No check reads another revision of the repository:
# the render checks compare renders of this working tree with each other, so an
# intended edit of the shared template keeps them green.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  CONFIG_TEMPLATE="$REPO_ROOT/.chezmoi.toml.tmpl"
  OPENCODE_TEMPLATE="$REPO_ROOT/home/dot_config/opencode/AGENTS.md.tmpl"
  TMP_CONFIG="$BATS_TEST_TMPDIR/chezmoi.json"
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

# Renders one peer template, given its path below home/, to stdout.
_render_peer() {
  chezmoi execute-template --file "$REPO_ROOT/home/$1" \
    --config "$TMP_CONFIG" --config-format json \
    --source "$REPO_ROOT/home" --destination "$BATS_TEST_TMPDIR/home"
}

# First shared span: from the commit rules heading up to, not including, the
# SSH key discovery step. Steps 5 and 6 take per-agent parameters, so they stay
# outside both spans. The end anchor is looked for only after the heading, and
# nothing is printed unless both were found, so a renamed or reordered anchor
# gives an empty span instead of a partial one.
_span_commit_rules() {
  awk '
    $0 == "## Commit rules" { n = 0; on = 1 }
    on && index($0, "  5. **SSH key discovery**") == 1 { found = 1; on = 0 }
    on { buf[n++] = $0 }
    END { if (found) for (i = 0; i < n; i++) print buf[i] }
  ' "$1"
}

# Second shared span: from the unsigned-commit step to the last line. The
# OpenCode template adds nothing after the shared template, so this is the last
# line of the shared template too.
_span_closing() {
  awk '
    index($0, "  7. **Unsigned commit") == 1 { on = 1 }
    on { print }
  ' "$1"
}

# Succeeds when every line of the file $1 occurs, in order and as whole lines,
# as one contiguous block of the file $2. Text before or after the block does
# not matter. An empty $1 is an error (status 2), not a match.
_contains_block() {
  awk -v needle_file="$1" '
    BEGIN {
      while ((getline line < needle_file) > 0) needle[n++] = line
      close(needle_file)
    }
    { hay[h++] = $0 }
    END {
      if (n == 0) exit 2
      for (i = 0; i + n <= h; i++) {
        for (j = 0; j < n && hay[i + j] == needle[j]; j++) { }
        if (j == n) exit 0
      }
      exit 1
    }
  ' "$2"
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

@test "OpenCode defaults to compact, false and invalid values fall back to it, true selects the larger extended render" {
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

  local compact_words extended_words
  compact_words=$(printf '%s\n' "$compact" | wc -w)
  extended_words=$(printf '%s\n' "$extended" | wc -w)
  [ "$((compact_words * 2))" -le "$extended_words" ]
}

@test "peer user-global renders contain the shared spans of the extended OpenCode render" {
  local opencode="$BATS_TEST_TMPDIR/opencode-extended.md"
  local commit_rules="$BATS_TEST_TMPDIR/span-commit-rules.md"
  local closing="$BATS_TEST_TMPDIR/span-closing.md"
  local rel peer

  _write_config '{"data":{"opencode":{"extendedInstructions":true}}}'
  _render_opencode > "$opencode"
  _span_commit_rules "$opencode" > "$commit_rules"
  _span_closing "$opencode" > "$closing"
  # A renamed heading or step must not turn the check into a vacuous pass.
  [ -s "$commit_rules" ] || fail 'the extended OpenCode render has no commit rules span'
  [ -s "$closing" ] || fail 'the extended OpenCode render has no closing span'

  for rel in \
    dot_copilot/copilot-instructions.md.tmpl \
    dot_codex/AGENTS.md.tmpl \
    dot_claude/CLAUDE.md.tmpl \
    dot_gemini/GEMINI.md.tmpl; do
    peer="$BATS_TEST_TMPDIR/peer-$(basename "$rel").md"
    _render_peer "$rel" > "$peer" || fail "$rel does not render"
    _contains_block "$commit_rules" "$peer" ||
      fail "$rel lacks the commit rules span of the extended OpenCode render"
    _contains_block "$closing" "$peer" ||
      fail "$rel lacks the closing span of the extended OpenCode render"
  done
}

@test "the Antigravity AGENTS.md pointer links to GEMINI.md" {
  run grep -F '](GEMINI.md)' "$REPO_ROOT/home/dot_gemini/AGENTS.md"
  assert_success
}

# Prints the lines between the user-global managed-block markers, exclusive.
_block_body() {
  awk '
    index($0, "<!-- idd-skill:user-global:begin -->") == 1 { on = 1; next }
    index($0, "<!-- idd-skill:user-global:end -->") == 1 { on = 0 }
    on { print }
  ' "$1"
}

REIMPORT_LINK='docs/idd-user-global-reimport.md'

@test "the Codex, Copilot, Gemini and extended OpenCode blocks carry the vendored entry text byte for byte" {
  local version entry rel out
  # Follow the payload link, so that a bumped payload fails here until each
  # copy names the new version.
  version=$(cat "$REPO_ROOT/home/dot_local/share/idd-skill/symlink_current")
  entry="$REPO_ROOT/home/dot_local/share/idd-skill/$version/user-global/entry.md"
  [ -f "$entry" ] || fail "symlink_current does not name a vendored payload"
  _write_config '{"data":{"opencode":{"extendedInstructions":true}}}'
  for rel in \
    dot_codex/AGENTS.md.tmpl \
    dot_copilot/copilot-instructions.md.tmpl \
    dot_gemini/GEMINI.md.tmpl \
    dot_config/opencode/AGENTS.md.tmpl; do
    grep -qF "dot_local/share/idd-skill/$version/user-global/entry.md" "$REPO_ROOT/home/$rel" ||
      fail "$rel does not include the entry.md of payload $version"
    out="$BATS_TEST_TMPDIR/block-$(basename "$rel").md"
    _render_peer "$rel" > "$out" || fail "$rel does not render"
    _block_body "$out" > "$BATS_TEST_TMPDIR/body.md"
    cmp -s "$entry" "$BATS_TEST_TMPDIR/body.md" ||
      fail "$rel block body differs from the vendored entry.md"
  done
}

@test "the Claude block imports the deployed entry.md by absolute path" {
  _write_config '{"data":{}}'
  _render_peer dot_claude/CLAUDE.md.tmpl > "$BATS_TEST_TMPDIR/claude.md"
  run grep -c '^@/.*/\.local/share/idd-skill/current/user-global/entry\.md$' "$BATS_TEST_TMPDIR/claude.md"
  assert_output 1
}

@test "the compact OpenCode render routes IDD work and carries neither the commit rules nor the entry heading" {
  _write_config '{"data":{"opencode":{"extendedInstructions":false}}}'
  _render_opencode > "$BATS_TEST_TMPDIR/compact.md"
  run grep -c 'idd-<phase>-lite.instructions.md' "$BATS_TEST_TMPDIR/compact.md"
  assert_output 1
  run grep -c 'idd-overview-core.instructions.md' "$BATS_TEST_TMPDIR/compact.md"
  assert_output 1
  run grep -c -e '^## Commit rules$' -e '^# IDD entry (user-global)$' "$BATS_TEST_TMPDIR/compact.md"
  assert_output 0
}

@test "the extended OpenCode render carries the entry text and the commit rules" {
  _write_config '{"data":{"opencode":{"extendedInstructions":true}}}'
  _render_opencode > "$BATS_TEST_TMPDIR/extended.md"
  run grep -c '^# IDD entry (user-global)$' "$BATS_TEST_TMPDIR/extended.md"
  assert_output 1
  run grep -c '^## Commit rules$' "$BATS_TEST_TMPDIR/extended.md"
  assert_output 1
}

@test "all six user-global renders link the re-import procedure" {
  local rel
  _write_config '{"data":{}}'
  for rel in \
    dot_claude/CLAUDE.md.tmpl \
    dot_codex/AGENTS.md.tmpl \
    dot_copilot/copilot-instructions.md.tmpl \
    dot_gemini/GEMINI.md.tmpl; do
    _render_peer "$rel" | grep -qF "$REIMPORT_LINK" || fail "$rel does not link $REIMPORT_LINK"
  done
  _render_opencode | grep -qF "$REIMPORT_LINK" || fail 'the compact OpenCode render does not link the re-import procedure'
  _write_config '{"data":{"opencode":{"extendedInstructions":true}}}'
  _render_opencode | grep -qF "$REIMPORT_LINK" || fail 'the extended OpenCode render does not link the re-import procedure'
}

@test "flipping the OpenCode flag leaves the Claude, Codex, Copilot and Gemini renders byte-identical" {
  local rel
  for rel in \
    dot_claude/CLAUDE.md.tmpl \
    dot_codex/AGENTS.md.tmpl \
    dot_copilot/copilot-instructions.md.tmpl \
    dot_gemini/GEMINI.md.tmpl; do
    _write_config '{"data":{}}'
    _render_peer "$rel" > "$BATS_TEST_TMPDIR/flag-off.md" || fail "$rel does not render with the flag absent"
    _write_config '{"data":{"opencode":{"extendedInstructions":true}}}'
    _render_peer "$rel" > "$BATS_TEST_TMPDIR/flag-on.md" || fail "$rel does not render with the flag true"
    cmp -s "$BATS_TEST_TMPDIR/flag-off.md" "$BATS_TEST_TMPDIR/flag-on.md" ||
      fail "$rel changes when only the OpenCode flag changes"
  done
}

@test "the AI strategy page records the Cursor gap, the unverified Grok import and the harness advice" {
  local folded="$BATS_TEST_TMPDIR/ai-strategy-folded.md"
  tr '\n' ' ' < "$REPO_ROOT/docs/ai-strategy.md" > "$folded"
  run grep -F 'Cursor CLI documents no file-based global instruction file' "$folded"
  assert_success
  run grep -F 'whether Grok follows the `@` import' "$folded"
  assert_success
  run grep -F -- '--harness claude,codex' "$folded"
  assert_success
}

@test "no opencode.json chezmoi source is added" {
  run find "$REPO_ROOT/home" -name 'opencode.json*'
  assert_output ''
}

@test "the re-import link sits after each managed block, outside it" {
  local rel out end_line link_line
  _write_config '{"data":{"opencode":{"extendedInstructions":true}}}'
  for rel in \
    dot_claude/CLAUDE.md.tmpl \
    dot_codex/AGENTS.md.tmpl \
    dot_copilot/copilot-instructions.md.tmpl \
    dot_gemini/GEMINI.md.tmpl \
    dot_config/opencode/AGENTS.md.tmpl; do
    out="$BATS_TEST_TMPDIR/placement-$(basename "$rel").md"
    _render_peer "$rel" > "$out" || fail "$rel does not render"
    end_line=$(grep -n -F '<!-- idd-skill:user-global:end -->' "$out" | head -1 | cut -d: -f1)
    link_line=$(grep -n -F "$REIMPORT_LINK" "$out" | head -1 | cut -d: -f1)
    [ -n "$end_line" ] && [ -n "$link_line" ] || fail "$rel lacks the block end or the link"
    [ "$link_line" -gt "$end_line" ] || fail "$rel links the re-import procedure inside the managed block"
    if _block_body "$out" | grep -qF "$REIMPORT_LINK"; then
      fail "$rel puts the link inside the managed block"
    fi
  done
}
