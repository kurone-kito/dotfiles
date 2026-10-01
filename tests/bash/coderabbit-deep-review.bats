#!/usr/bin/env bats
# Tests the CodeRabbit review setting (data.coderabbit.review, and the
# deprecated deepReview alias) across the shared review-mode helper, the
# chezmoi configuration template, and the generated POSIX shell profile.
# The ignore list and the user-global config have their own files:
# chezmoiignore-coderabbit-opt-in.bats and idd-skill-config-tmpl.bats.
#
# Every render passes an explicit --config, so the maintainer's own
# chezmoi data (an opted-in review, say) can never leak into a test.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  CONFIG_TEMPLATE="$REPO_ROOT/.chezmoi.toml.tmpl"
  PROFILE_TEMPLATE="$REPO_ROOT/home/dot_config/shell/conf.d/25-coderabbit.sh.tmpl"
  HELPER_TEMPLATE="$REPO_ROOT/home/.chezmoitemplates/coderabbit-review-mode"
  TMP_CONFIG="$BATS_TEST_TMPDIR/chezmoi.json"
  TMP_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TMP_HOME"
}

# $1: the value of data.coderabbit as JSON, or "absent" to omit it
_write_config() {
  if [ "$1" = absent ]; then
    printf '%s\n' '{ "data": {} }' > "$TMP_CONFIG"
  else
    printf '{ "data": { "coderabbit": %s } }\n' "$1" > "$TMP_CONFIG"
  fi
}

# Renders the config template and drops the trailing comment block, whose
# prose names these keys too, so assertions see the emitted TOML only.
# $1: the config file to read (default: $TMP_CONFIG)
_render_config() {
  chezmoi execute-template --init --file "$CONFIG_TEMPLATE" \
    --config "${1:-$TMP_CONFIG}" --config-format json \
    --promptString git.name="Test User" \
    --promptString git.email="test@example.com" \
    --promptString git.signingkey="" \
    --promptString secret.manager="none" \
    --source "$REPO_ROOT" --destination "$TMP_HOME" | grep -v '^#'
}

_render_profile() {
  chezmoi execute-template --file "$PROFILE_TEMPLATE" \
    --config "$TMP_CONFIG" --config-format json \
    --source "$REPO_ROOT/home" --destination "$TMP_HOME"
}

# $1: the config file to read (default: $TMP_CONFIG)
# $2: its format (default: json)
_render_helper() {
  chezmoi execute-template --file "$HELPER_TEMPLATE" \
    --config "${1:-$TMP_CONFIG}" --config-format "${2:-json}" \
    --source "$REPO_ROOT/home" --destination "$TMP_HOME"
}

# The helper's own verdict for the config currently in $TMP_CONFIG.
_resolved_mode() {
  run --separate-stderr _render_helper
  assert_success
  printf '%s' "$output"
}

# ---------------------------------------------------------------------------
# The review-mode helper
# ---------------------------------------------------------------------------

@test "the review-mode helper resolves every accepted combination" {
  local label coderabbit expected notice
  while IFS='|' read -r label coderabbit expected notice; do
    [ -n "$label" ] || continue
    _write_config "$coderabbit"

    run --separate-stderr _render_helper

    [ "$status" -eq 0 ] || fail "$label: exit $status: $stderr"
    [ "$output" = "$expected" ] || fail "$label: expected $expected, got '$output'"
    notices=$(printf '%s\n' "$stderr" | grep -c 'deepReview is deprecated; use review = "deep"' || true)
    if [ "$notice" = yes ]; then
      [ "$notices" -eq 1 ] || fail "$label: expected one deprecation notice, got $notices: $stderr"
    else
      [ -z "$stderr" ] || fail "$label: unexpected stderr: $stderr"
    fi
  done << 'ROWS'
absent|absent|off|no
empty-table|{}|off|no
review-false|{"review": false}|off|no
review-true|{"review": true}|lite|no
review-lite|{"review": "lite"}|lite|no
review-deep|{"review": "deep"}|deep|no
legacy-only|{"deepReview": true}|deep|yes
legacy-false|{"deepReview": false}|off|yes
review-false-legacy-true|{"review": false, "deepReview": true}|off|yes
review-false-legacy-false|{"review": false, "deepReview": false}|off|yes
review-true-legacy-true|{"review": true, "deepReview": true}|lite|yes
review-true-legacy-false|{"review": true, "deepReview": false}|lite|yes
review-lite-legacy-true|{"review": "lite", "deepReview": true}|lite|yes
review-lite-legacy-false|{"review": "lite", "deepReview": false}|lite|yes
review-deep-legacy-true|{"review": "deep", "deepReview": true}|deep|yes
review-deep-legacy-false|{"review": "deep", "deepReview": false}|deep|yes
ROWS
}

@test "the review-mode helper fails on every invalid value and names the key" {
  local label coderabbit key allowed
  while IFS='|' read -r label coderabbit key allowed; do
    [ -n "$label" ] || continue
    _write_config "$coderabbit"

    run --separate-stderr _render_helper

    [ "$status" -ne 0 ] || fail "$label: expected a render error, got '$output'"
    case "$stderr" in
      *"data.coderabbit$key"*) ;;
      *) fail "$label: stderr does not name data.coderabbit$key: $stderr" ;;
    esac
    case "$stderr" in
      *"$allowed"*) ;;
      *) fail "$label: stderr does not list the allowed values ($allowed): $stderr" ;;
    esac
  done << 'ROWS'
review-bogus|{"review": "bogus"}|.review|"lite" or "deep"
review-string-false|{"review": "false"}|.review|"lite" or "deep"
review-number|{"review": 1}|.review|"lite" or "deep"
review-empty|{"review": ""}|.review|"lite" or "deep"
review-bogus-legacy-true|{"review": "bogus", "deepReview": true}|.review|"lite" or "deep"
legacy-string|{"deepReview": "false"}|.deepReview|true or false
legacy-number|{"deepReview": 1}|.deepReview|true or false
legacy-string-review-deep|{"review": "deep", "deepReview": "yes"}|.deepReview|true or false
not-a-table|"on"||must be a table
ROWS
}

@test "the review-mode helper does not treat an absent key as present" {
  # Sprig's get returns "" for a missing key; a naive kindIs "string" test
  # on that result would reject every config that sets only one of the keys.
  for coderabbit in '{"review": "deep"}' '{"deepReview": true}'; do
    _write_config "$coderabbit"
    run --separate-stderr _render_helper
    assert_success
    assert_output deep
  done
}

# ---------------------------------------------------------------------------
# The POSIX shell profile
# ---------------------------------------------------------------------------

@test "the deep POSIX profile assigns deep-review mode exactly once" {
  for coderabbit in '{"review": "deep"}' '{"deepReview": true}' '{"review": "deep", "deepReview": true}'; do
    _write_config "$coderabbit"

    run --separate-stderr _render_profile

    assert_success
    assert_equal "$(printf '%s\n' "$output" | grep -c '^export CODERABBIT_CRITIQUE_DEEP=1$')" 1
  done
}

@test "off and lite POSIX profiles preserve an external value" {
  for coderabbit in absent '{}' '{"review": false}' '{"review": true}' '{"review": "lite"}' '{"deepReview": false}'; do
    _write_config "$coderabbit"

    run --separate-stderr _render_profile

    assert_success
    refute_output --partial 'export CODERABBIT_CRITIQUE_DEEP='
    rendered="$BATS_TEST_TMPDIR/coderabbit-profile.sh"
    printf '%s\n' "$output" > "$rendered"
    run env CODERABBIT_CRITIQUE_DEEP=external sh -c '. "$1"; printf "%s" "$CODERABBIT_CRITIQUE_DEEP"' sh "$rendered"
    assert_success
    assert_output 'external'
  done
}

@test "the deep POSIX profile sets the runtime value to 1" {
  for coderabbit in '{"review": "deep"}' '{"deepReview": true}'; do
    _write_config "$coderabbit"

    run --separate-stderr _render_profile

    assert_success
    rendered="$BATS_TEST_TMPDIR/coderabbit-profile-enabled.sh"
    printf '%s\n' "$output" > "$rendered"
    run env CODERABBIT_CRITIQUE_DEEP=external sh -c '. "$1"; printf "%s" "$CODERABBIT_CRITIQUE_DEEP"' sh "$rendered"
    assert_success
    assert_output '1'
  done
}

# ---------------------------------------------------------------------------
# The configuration template (what `chezmoi init` writes back)
# ---------------------------------------------------------------------------

@test "the configuration template re-emits review with its type preserved" {
  local input expected
  while IFS='|' read -r input expected; do
    [ -n "$input" ] || continue
    _write_config "$input"

    run --separate-stderr _render_config

    [ "$status" -eq 0 ] || fail "$input: exit $status: $stderr"
    case "$output" in
      *"[data.coderabbit]"*) ;;
      *) fail "$input: no [data.coderabbit] section" ;;
    esac
    printf '%s\n' "$output" | grep -qx "$expected" || fail "$input: missing line '$expected'"
    case "$output" in
      *deepReview*) fail "$input: unexpected deepReview line" ;;
    esac
  done << 'ROWS'
{"review": true}|review = true
{"review": false}|review = false
{"review": "lite"}|review = "lite"
{"review": "deep"}|review = "deep"
ROWS
}

@test "the configuration template emits nothing for an absent review, never review = \"\"" {
  for coderabbit in absent '{}'; do
    _write_config "$coderabbit"

    run --separate-stderr _render_config

    assert_success
    refute_output --partial '[data.coderabbit]'
    refute_output --partial 'review ='
  done
}

@test "the configuration template drops a review that is neither a Boolean nor a string, with a warning" {
  for coderabbit in '{"review": 1}' '{"review": 1.5}' '{"review": ["deep"]}' '{"review": {"mode": "deep"}}'; do
    _write_config "$coderabbit"

    run --separate-stderr _render_config

    assert_success
    refute_output --partial '[data.coderabbit]'
    refute_output --partial 'review ='
    case "$stderr" in
      *"data.coderabbit.review must be true, false"*"dropping"*) ;;
      *) fail "$coderabbit: no drop warning: $stderr" ;;
    esac
  done
}

@test "the configuration template still emits the legacy deepReview = true" {
  _write_config '{"deepReview": true}'

  run --separate-stderr _render_config

  assert_success
  assert_output --partial '[data.coderabbit]'
  assert_output --partial 'deepReview = true'
  refute_output --partial 'review ='
}

@test "the configuration template omits deepReview when false, absent or not a Boolean" {
  for coderabbit in absent '{"deepReview": false}' '{"deepReview": "true"}' '{"deepReview": 1}'; do
    _write_config "$coderabbit"

    run --separate-stderr _render_config

    assert_success
    refute_output --partial '[data.coderabbit]'
    refute_output --partial 'deepReview ='
  done
}

@test "the configuration template emits one section when both keys are set" {
  _write_config '{"review": false, "deepReview": true}'

  run --separate-stderr _render_config

  assert_success
  assert_equal "$(printf '%s\n' "$output" | grep -c '^\[data\.coderabbit\]$')" 1
  # The header and both assignments sit on their own lines, in this order: the
  # trim markers around the conditionals must not join them.
  assert_equal "$(printf '%s\n' "$output" | grep -A2 -x '\[data\.coderabbit\]')" \
    "$(printf '%s\n' '[data.coderabbit]' 'review = false' 'deepReview = true')"
}

@test "the configuration template puts the header and a lone review on separate lines" {
  _write_config '{"review": "deep"}'

  run --separate-stderr _render_config

  assert_success
  assert_equal "$(printf '%s\n' "$output" | grep -A1 -x '\[data\.coderabbit\]')" \
    "$(printf '%s\n' '[data.coderabbit]' 'review = "deep"')"
}

# Re-parse the emitted TOML the way the next `chezmoi apply` would, and
# check that it resolves to the same mode as the input did.
@test "the emitted configuration resolves to the input's review mode" {
  local input
  for input in '{"review": true}' '{"review": false}' '{"review": "lite"}' '{"review": "deep"}' \
    '{"deepReview": true}' '{"review": false, "deepReview": true}'; do
    _write_config "$input"
    expected=$(_resolved_mode)
    run --separate-stderr _render_config
    assert_success
    emitted="$BATS_TEST_TMPDIR/emitted.toml"
    printf '%s\n' "$output" > "$emitted"

    run --separate-stderr _render_helper "$emitted" toml

    [ "$status" -eq 0 ] || fail "$input: exit $status: $stderr"
    [ "$output" = "$expected" ] || fail "$input: expected $expected after the round trip, got '$output'"
  done
}
