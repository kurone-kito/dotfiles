#!/usr/bin/env bats
# Tests for the tmp.conf template rendered by chezmoi at apply time.
#
# /etc/tmpfiles.d/tmp.conf masks (fully replaces) the shipped
# /usr/lib/tmpfiles.d/tmp.conf, so this template must reproduce BOTH
# the /tmp (parameterized age) and /var/tmp (literal 30d) rules. The
# tests below guard the parameterization, the quoting needed for
# multi-component (space-containing) systemd time spans, and the
# invariant that /var/tmp's literal age is unaffected by the
# configured /tmp age.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  TEMPLATE_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/tmpfiles.d/tmp.conf.tmpl"
  TMP_HOME="$BATS_TEST_TMPDIR/home"
  TMP_SOURCE="$BATS_TEST_TMPDIR/source"
  TMP_CONFIG="$BATS_TEST_TMPDIR/chezmoi.toml"
  mkdir -p "$TMP_HOME" "$TMP_SOURCE"
}

# Render the template using the provided config-format JSON file.
_render() {
  local config_file="$1"
  chezmoi execute-template --file "$TEMPLATE_PATH" \
    --config "$config_file" --config-format json \
    --source "$TMP_SOURCE" --destination "$TMP_HOME"
}

@test "default config renders the /tmp rule with the default 10d age, quoted" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": {} }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  assert_output --partial 'q /tmp 1777 root root "10d"'
}

@test "overridden tmpfiles.age renders that value in the /tmp line, quoted" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": { "tmpfiles": { "age": "2d" } } }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  assert_output --partial 'q /tmp 1777 root root "2d"'
}

@test "a multi-component (space-containing) age renders as a single quoted field" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": { "tmpfiles": { "age": "1d 12h" } } }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  assert_output --partial 'q /tmp 1777 root root "1d 12h"'
}

@test "/var/tmp renders as an active literal 30d rule, unaffected by tmpfiles.age" {
  cat > "$TMP_CONFIG" <<JSON
{ "data": { "tmpfiles": { "age": "2d" } } }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  # Assert the exact functional line (not just a substring match),
  # since explanatory comments in the header also mention the
  # "#q /var/tmp 1777 root root 30d" string as prose.
  assert_line "q /var/tmp 1777 root root 30d"
  refute_line "q /var/tmp 1777 root root 2d"
  # Guard against accidentally commenting the functional line back
  # out: no *line* (as opposed to substring anywhere in output) may
  # start with "#q /var/tmp" — it must be an active rule.
  refute_line --regexp '^#q /var/tmp'
}

@test "rendered default output validates with systemd-tmpfiles --create --dry-run" {
  if ! command -v systemd-tmpfiles > /dev/null 2>&1; then
    skip "systemd-tmpfiles not available"
  fi
  if ! systemd-tmpfiles --help 2>&1 | grep -q -- '--dry-run'; then
    skip "systemd-tmpfiles on this host predates --dry-run support"
  fi

  cat > "$TMP_CONFIG" <<JSON
{ "data": {} }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  local rendered="$BATS_TEST_TMPDIR/tmp.conf"
  printf '%s\n' "$output" > "$rendered"

  run systemd-tmpfiles --create --dry-run "$rendered"
  assert_success
  refute_output --partial "ignoring"
}

@test "a multi-component age validates with systemd-tmpfiles --create --dry-run without a warning" {
  if ! command -v systemd-tmpfiles > /dev/null 2>&1; then
    skip "systemd-tmpfiles not available"
  fi
  if ! systemd-tmpfiles --help 2>&1 | grep -q -- '--dry-run'; then
    skip "systemd-tmpfiles on this host predates --dry-run support"
  fi

  cat > "$TMP_CONFIG" <<JSON
{ "data": { "tmpfiles": { "age": "1d 12h" } } }
JSON
  run _render "$TMP_CONFIG"
  assert_success
  local rendered="$BATS_TEST_TMPDIR/tmp-space.conf"
  printf '%s\n' "$output" > "$rendered"

  run systemd-tmpfiles --create --dry-run "$rendered"
  assert_success
  refute_output --partial "ignoring"
}
