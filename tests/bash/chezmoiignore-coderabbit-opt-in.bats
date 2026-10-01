#!/usr/bin/env bats
#
# The CodeRabbit critique launchers are opt-in: home/.chezmoiignore.tmpl
# lists them as ignored when data.coderabbit.review resolves to "off" (the
# default), and deploys them for "lite" and "deep". Renders the real ignore
# list for both Linux and Windows by overriding chezmoi.os.
#
# Every render passes an explicit --config, so the maintainer's own chezmoi
# data can never leak into a test, and --override-data only for chezmoi.os.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_HOME="$BATS_TEST_DIRNAME/../../home"
  IGNORE_TEMPLATE="$REPO_HOME/.chezmoiignore.tmpl"
}

# $1: chezmoi.os (linux or windows)
# $2: data.coderabbit as JSON, or "absent" to omit it
_render_ignore() {
  local config="$BATS_TEST_TMPDIR/chezmoi-config.json"
  if [ "$2" = absent ]; then
    printf '%s\n' '{ "data": {} }' > "$config"
  else
    printf '{ "data": { "coderabbit": %s } }\n' "$2" > "$config"
  fi
  chezmoi execute-template --file "$IGNORE_TEMPLATE" \
    --config "$config" --config-format json \
    --override-data "{\"chezmoi\": {\"os\": \"$1\"}}" \
    --source "$REPO_HOME" --destination "$BATS_TEST_TMPDIR/destination"
}

_assert_listed_once() {
  assert_equal "$(printf '%s\n' "$output" | grep -c -x -F -e "$1")" 1
}

@test "off ignores every CodeRabbit launcher on Linux" {
  for coderabbit in absent '{}' '{"review": false}' '{"deepReview": false}'; do
    run --separate-stderr _render_ignore linux "$coderabbit"

    assert_success
    _assert_listed_once '.local/bin/coderabbit-critique'
    _assert_listed_once '.local/bin/coderabbit-critique.ps1'
    _assert_listed_once '.local/bin/coderabbit-critique.cmd'
  done
}

@test "off ignores every CodeRabbit launcher on Windows" {
  for coderabbit in absent '{}' '{"review": false}' '{"deepReview": false}'; do
    run --separate-stderr _render_ignore windows "$coderabbit"

    assert_success
    _assert_listed_once '.local/bin/coderabbit-critique'
    _assert_listed_once '.local/bin/coderabbit-critique.ps1'
    _assert_listed_once '.local/bin/coderabbit-critique.cmd'
  done
}

@test "lite and deep deploy the launchers on Windows" {
  for coderabbit in '{"review": true}' '{"review": "lite"}' '{"review": "deep"}' '{"deepReview": true}'; do
    run --separate-stderr _render_ignore windows "$coderabbit"

    assert_success
    refute_output --partial 'coderabbit-critique'
  done
}

@test "lite and deep deploy the Linux launchers and ignore only the Windows .cmd twin" {
  for coderabbit in '{"review": true}' '{"review": "lite"}' '{"review": "deep"}' '{"deepReview": true}'; do
    run --separate-stderr _render_ignore linux "$coderabbit"

    assert_success
    assert_equal "$(printf '%s\n' "$output" | grep -c 'coderabbit-critique')" 1
    _assert_listed_once '.local/bin/coderabbit-critique.cmd'
  done
}

@test "the idd-critique-telemetry launchers are the same in every mode" {
  for os in linux windows; do
    run --separate-stderr _render_ignore "$os" '{"review": false}'
    assert_success
    off_telemetry=$(printf '%s\n' "$output" | grep 'idd-critique-telemetry' || true)

    for coderabbit in '{"review": "lite"}' '{"review": "deep"}'; do
      run --separate-stderr _render_ignore "$os" "$coderabbit"

      assert_success
      assert_equal "$(printf '%s\n' "$output" | grep 'idd-critique-telemetry' || true)" "$off_telemetry"
    done
  done
  # A guard on the premise: Linux lists the two .cmd telemetry launchers.
  run --separate-stderr _render_ignore linux absent
  _assert_listed_once '.local/bin/idd-critique-telemetry.cmd'
  _assert_listed_once '.local/bin/idd-critique-telemetry-report.cmd'
}

@test "every other ignore entry is unchanged by the mode" {
  for os in linux windows; do
    run --separate-stderr _render_ignore "$os" '{"review": "lite"}'
    assert_success
    lite_list=$(printf '%s\n' "$output" | grep -v 'coderabbit-critique')

    run --separate-stderr _render_ignore "$os" '{"review": false}'
    assert_success
    off_list=$(printf '%s\n' "$output" | grep -v 'coderabbit-critique')

    assert_equal "$off_list" "$lite_list"
  done
}

@test "an invalid review value fails the ignore-list render" {
  run --separate-stderr _render_ignore linux '{"review": "bogus"}'

  assert_failure
  assert_regex "$stderr" 'data\.coderabbit\.review'
}
