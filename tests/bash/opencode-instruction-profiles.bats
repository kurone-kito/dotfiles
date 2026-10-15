#!/usr/bin/env bats
# Regression coverage for OpenCode's compact default and full opt-in profile,
# and for the user-global spans that the extended OpenCode render shares with
# the other agents' renders. Every check compares renders of this working tree
# with each other and never with another revision, so an intended edit of the
# shared template keeps them green.

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
