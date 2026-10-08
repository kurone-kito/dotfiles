#!/usr/bin/env bats
# Runs the snippets that docs/secret-manager-setup.md tells readers to paste,
# so the guide cannot drift from the NODE_OPTIONS rules the managed profile
# applies (tests/bash/65-node-options.bats). Each snippet sits in the first
# fenced block after an HTML comment of the form
# `<!-- test-snippet: NAME -->`.
# cspell:words autoselection
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

OPTION='--network-family-autoselection-attempt-timeout'
DEFAULT="$OPTION=2000"

# Inputs the first-apply snippet must leave untouched: the option as a whole
# argument, in every spelling it documents.
PRESENT_FIXTURES=(
  "$OPTION=5000"
  "$OPTION 5000"
  "--network_family_autoselection_attempt_timeout=5000"
  "\"$OPTION=5000\""
  "--max-old-space-size=1 --network-family_autoselection-attempt_timeout 5000"
  "$OPTION"
)

# Inputs that only contain the option name inside another argument, or are
# unrelated; the default must be appended after them.
ABSENT_FIXTURES=(
  "--max-old-space-size=4096"
  "--no-network-family-autoselection-attempt-timeout=1"
  "--network-family-autoselection"
  "${OPTION}x=1"
  "--require \"/tmp/$OPTION=1/x.js\""
)

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  GUIDE="$BATS_TEST_DIRNAME/../../docs/secret-manager-setup.md"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  unset NODE_OPTIONS
}

# Print the first fenced block after the marker comment for snippet $1.
extract_snippet() {
  awk -v name="$1" '
    $0 == "<!-- test-snippet: " name " -->" { want = 1; next }
    want && /^```/ { if (in_block) { exit } in_block = 1; next }
    want && in_block { print }
  ' "$GUIDE"
}

# Run snippet text $1 under shell $2 with NODE_OPTIONS=$3 (or unset when $3 is
# the word __unset__) and print the resulting NODE_OPTIONS.
run_first_apply() {
  local snippet="$1" shell_name="$2" value="$3"
  local -a launcher=(env)
  if [ "$value" = __unset__ ]; then
    launcher+=(-u NODE_OPTIONS)
  else
    launcher+=("NODE_OPTIONS=$value")
  fi
  run "${launcher[@]}" "$shell_name" -c "$snippet
printf '%s' \"\$NODE_OPTIONS\""
}

available_shells() {
  local shell_name
  for shell_name in sh bash zsh; do
    command -v "$shell_name" > /dev/null 2>&1 && printf '%s\n' "$shell_name"
  done
}

@test "the guide marks every snippet this file runs" {
  local name
  for name in first-apply-bash first-apply-powershell support-check-powershell automation-bash; do
    [ -n "$(extract_snippet "$name")" ] || fail "no fenced block after the '$name' marker"
  done
}

@test "first-apply Bash snippet leaves a whole-argument option untouched in every shell" {
  local snippet shell_name value
  snippet="$(extract_snippet first-apply-bash)"
  [ -n "$snippet" ] || fail "snippet not found"

  for shell_name in $(available_shells); do
    for value in "${PRESENT_FIXTURES[@]}"; do
      run_first_apply "$snippet" "$shell_name" "$value"
      [ "$status" -eq 0 ] || fail "$shell_name failed for [$value]: $output"
      [ "$output" = "$value" ] || fail "$shell_name: [$value] became [$output]"
    done
  done
}

@test "first-apply Bash snippet appends the default after anything else in every shell" {
  local snippet shell_name value
  snippet="$(extract_snippet first-apply-bash)"
  [ -n "$snippet" ] || fail "snippet not found"

  for shell_name in $(available_shells); do
    run_first_apply "$snippet" "$shell_name" __unset__
    [ "$output" = "$DEFAULT" ] || fail "$shell_name: unset became [$output]"
    run_first_apply "$snippet" "$shell_name" ''
    [ "$output" = "$DEFAULT" ] || fail "$shell_name: empty became [$output]"
    for value in "${ABSENT_FIXTURES[@]}"; do
      run_first_apply "$snippet" "$shell_name" "$value"
      [ "$status" -eq 0 ] || fail "$shell_name failed for [$value]: $output"
      [ "$output" = "$value $DEFAULT" ] || fail "$shell_name: [$value] became [$output]"
    done
  done
}

@test "automation example appends to the job's own NODE_OPTIONS" {
  local snippet
  snippet="$(extract_snippet automation-bash)"
  [ -n "$snippet" ] || fail "snippet not found"

  # A mocked chezmoi reports what the child process sees.
  cat > "$BATS_TEST_TMPDIR/bin/chezmoi" << 'MOCK'
#!/bin/sh
printf '%s %s' "$1" "$NODE_OPTIONS"
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/chezmoi"

  run env NODE_OPTIONS='--max-old-space-size=4096' bash -c "$snippet"
  assert_success
  assert_output "apply --max-old-space-size=4096 $DEFAULT"

  run env -u NODE_OPTIONS bash -c "$snippet"
  assert_success
  assert_output "apply $DEFAULT"
}

@test "PowerShell first-apply snippet matches whole arguments, case-sensitively" {
  local snippet
  snippet="$(extract_snippet first-apply-powershell)"

  [[ "$snippet" == *"-cnotmatch"* ]] || fail "expected the case-sensitive -cnotmatch operator"
  [[ "$snippet" == *'(^|[ "])--network'* ]] || fail "expected the pattern anchored at an argument start"
  [[ "$snippet" == *'timeout($|[= "])'* ]] || fail "expected the pattern anchored at an argument end"
}

@test "PowerShell support check sets and restores the mise guards" {
  local snippet name
  snippet="$(extract_snippet support-check-powershell)"

  for name in NODE_OPTIONS MISE_AUTO_INSTALL MISE_EXEC_AUTO_INSTALL MISE_OFFLINE; do
    [[ "$snippet" == *"$name"* ]] || fail "expected $name in the PowerShell support check"
  done
  [[ "$snippet" == *'SetEnvironmentVariable($name, $saved[$name])'* ]] || fail "expected the variables to be restored"
  [[ "$snippet" == *'$global:LASTEXITCODE = $null'* ]] || fail "expected the exit code to be reset first"
}

@test "the install block no longer promises that any install works" {
  run grep -c 'any install works' "$GUIDE"
  assert_output 0
}
