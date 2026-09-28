#!/usr/bin/env bats
# Tests the optional CodeRabbit deep-review setting across the chezmoi
# configuration template and the generated POSIX shell profile.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  CONFIG_TEMPLATE="$REPO_ROOT/.chezmoi.toml.tmpl"
  PROFILE_TEMPLATE="$REPO_ROOT/home/dot_config/shell/conf.d/25-coderabbit.sh.tmpl"
  TMP_CONFIG="$BATS_TEST_TMPDIR/chezmoi.json"
  TMP_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TMP_HOME"
}

_render_config() {
  local config="$1"
  chezmoi execute-template --init --file "$CONFIG_TEMPLATE" \
    --config "$config" --config-format json \
    --promptString git.name="Test User" \
    --promptString git.email="test@example.com" \
    --promptString git.signingkey="" \
    --promptString secret.manager="none" \
    --source "$REPO_ROOT" --destination "$TMP_HOME"
}

_render_profile() {
  local config="$1"
  chezmoi execute-template --file "$PROFILE_TEMPLATE" \
    --config "$config" --config-format json \
    --source "$REPO_ROOT/home" --destination "$TMP_HOME"
}

@test "the configuration template emits the enabled deep-review field" {
  cat > "$TMP_CONFIG" <<'JSON'
{ "data": { "coderabbit": { "deepReview": true } } }
JSON

  run _render_config "$TMP_CONFIG"
  assert_success
  assert_output --partial '[data.coderabbit]'
  assert_output --partial 'deepReview = true'
}

@test "the configuration template omits the field when disabled or absent" {
  for value in false absent; do
    if [ "$value" = false ]; then
      printf '%s\n' '{ "data": { "coderabbit": { "deepReview": false } } }' > "$TMP_CONFIG"
    else
      printf '%s\n' '{ "data": {} }' > "$TMP_CONFIG"
    fi

    run _render_config "$TMP_CONFIG"
    assert_success
    refute_output --partial '[data.coderabbit]'
    refute_output --partial 'deepReview = true'
  done
}

@test "the enabled POSIX profile assigns deep-review mode exactly once" {
  printf '%s\n' '{ "data": { "coderabbit": { "deepReview": true } } }' > "$TMP_CONFIG"

  run _render_profile "$TMP_CONFIG"
  assert_success
  assert_equal "$(printf '%s\n' "$output" | grep -c '^export CODERABBIT_CRITIQUE_DEEP=1$')" 1
}

@test "disabled and absent POSIX profiles preserve an external value" {
  for value in false absent; do
    if [ "$value" = false ]; then
      printf '%s\n' '{ "data": { "coderabbit": { "deepReview": false } } }' > "$TMP_CONFIG"
    else
      printf '%s\n' '{ "data": {} }' > "$TMP_CONFIG"
    fi

    run _render_profile "$TMP_CONFIG"
    assert_success
    refute_output --partial 'export CODERABBIT_CRITIQUE_DEEP='
    rendered="$BATS_TEST_TMPDIR/coderabbit-profile.sh"
    printf '%s\n' "$output" > "$rendered"
    run env CODERABBIT_CRITIQUE_DEEP=external sh -c '. "$1"; printf "%s" "$CODERABBIT_CRITIQUE_DEEP"' sh "$rendered"
    assert_success
    assert_output 'external'
  done
}

@test "the enabled POSIX profile sets the runtime value to 1" {
  printf '%s\n' '{ "data": { "coderabbit": { "deepReview": true } } }' > "$TMP_CONFIG"

  run _render_profile "$TMP_CONFIG"
  assert_success
  rendered="$BATS_TEST_TMPDIR/coderabbit-profile-enabled.sh"
  printf '%s\n' "$output" > "$rendered"
  run env CODERABBIT_CRITIQUE_DEEP=external sh -c '. "$1"; printf "%s" "$CODERABBIT_CRITIQUE_DEEP"' sh "$rendered"
  assert_success
  assert_output '1'
}
