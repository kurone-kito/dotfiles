#!/usr/bin/env bats
# Runs the snippets that docs/secret-manager-setup.md tells readers to paste,
# so the guide cannot drift from the NODE_OPTIONS rules the managed profile
# applies (tests/bash/65-node-options.bats). Each snippet sits in the first
# fenced block after an HTML comment of the form
# `<!-- test-snippet: NAME -->`. The snippets are meant to be pasted into a
# running shell, so they run through `-c` here, not a login shell.
# cspell:words autoselection
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

OPTION='--network-family-autoselection-attempt-timeout'
DEFAULT="$OPTION=2000"

# Inputs the first-apply snippets must leave untouched: the option as a whole
# argument, in every spelling the guide documents.
PRESENT_FIXTURES=(
  "$OPTION=5000"
  "$OPTION 5000"
  "--network_family_autoselection_attempt_timeout=5000"
  "\"$OPTION=5000\""
  "\"$OPTION\" 5000"
  "\"$OPTION\"=5000"
  "$OPTION=\"5000\""
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
  "--foo=$OPTION=1"
  "---$OPTION=1"
  "x$OPTION"
)

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  GUIDE="$BATS_TEST_DIRNAME/../../docs/secret-manager-setup.md"
  # Keep the host's shell startup files out of the picture.
  export HOME="$BATS_TEST_TMPDIR/home"
  export ZDOTDIR="$HOME"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin"
  unset BASH_ENV ENV NODE_OPTIONS
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

require_zsh() {
  command -v zsh > /dev/null 2>&1 || skip "zsh not available"
}

# Print the first fenced block that directly follows the marker comment for
# snippet $1. A marker followed by anything but its fence binds to nothing.
extract_snippet() {
  awk -v name="$1" '
    $0 == "<!-- test-snippet: " name " -->" { want = 1; next }
    want && !in_block && /^```/ { in_block = 1; next }
    want && in_block && /^```/ { exit }
    want && in_block { print }
    want && !in_block && NF { want = 0 }
  ' "$GUIDE"
}

# Run snippet text $1 under shell $2 with NODE_OPTIONS=$3 (or unset when $3 is
# the word __unset__), then print NODE_OPTIONS as a child process sees it, so
# a snippet that forgets to export fails.
run_first_apply() {
  local snippet="$1" shell_name="$2" value="$3"
  local child="sh -c 'printf %s \"\$NODE_OPTIONS\"'"
  local -a launcher=(env)
  if [ "$value" = __unset__ ]; then
    launcher+=(-u NODE_OPTIONS)
  else
    launcher+=("NODE_OPTIONS=$value")
  fi
  run "${launcher[@]}" "$shell_name" -c "$snippet"$'\n'"$child"
}

# Check the whole fixture contract of the first-apply Bash snippet under $1.
check_first_apply_bash() {
  local shell_name="$1" snippet value
  snippet="$(extract_snippet first-apply-bash)"
  [ -n "$snippet" ] || fail "first-apply-bash snippet not found"

  for value in "${PRESENT_FIXTURES[@]}"; do
    run_first_apply "$snippet" "$shell_name" "$value"
    [ "$status" -eq 0 ] || fail "$shell_name failed for [$value]: $output"
    [ "$output" = "$value" ] || fail "$shell_name: [$value] became [$output]"
  done

  run_first_apply "$snippet" "$shell_name" __unset__
  [ "$output" = "$DEFAULT" ] || fail "$shell_name: unset became [$output]"
  run_first_apply "$snippet" "$shell_name" ''
  [ "$output" = "$DEFAULT" ] || fail "$shell_name: empty became [$output]"
  for value in "${ABSENT_FIXTURES[@]}"; do
    run_first_apply "$snippet" "$shell_name" "$value"
    [ "$status" -eq 0 ] || fail "$shell_name failed for [$value]: $output"
    [ "$output" = "$value $DEFAULT" ] || fail "$shell_name: [$value] became [$output]"
  done
}

@test "the guide marks every snippet this file runs" {
  local name
  for name in first-apply-bash first-apply-powershell support-check-bash \
    support-check-powershell automation-bash; do
    [ -n "$(extract_snippet "$name")" ] || fail "no fenced block after the '$name' marker"
  done
}

@test "first-apply Bash snippet decides on whole arguments and exports under sh" {
  check_first_apply_bash sh
}

@test "first-apply Bash snippet decides on whole arguments and exports under bash" {
  check_first_apply_bash bash
}

@test "first-apply Bash snippet decides on whole arguments and exports under zsh" {
  require_zsh
  check_first_apply_bash zsh
}

@test "first-apply PowerShell pattern gives the same verdicts as the Bash snippet" {
  local snippet pattern value
  snippet="$(extract_snippet first-apply-powershell)"
  pattern="$(printf '%s\n' "$snippet" | sed -n "s/.*-cnotmatch '\\(.*\\)') {.*/\\1/p")"
  [ -n "$pattern" ] || fail "no -cnotmatch pattern found in the PowerShell snippet"

  for value in "${PRESENT_FIXTURES[@]}"; do
    printf '%s' "$value" | grep -Eq -- "$pattern" || fail "pattern missed the option in [$value]"
  done
  for value in "${ABSENT_FIXTURES[@]}" ''; do
    if printf '%s' "$value" | grep -Eq -- "$pattern"; then
      fail "pattern matched in [$value], which does not hold the option as a whole argument"
    fi
  done
}

@test "PowerShell first-apply snippet is case-sensitive and appends the default" {
  local snippet
  snippet="$(extract_snippet first-apply-powershell)"

  [[ "$snippet" == *"-cnotmatch"* ]] || fail "expected the case-sensitive -cnotmatch operator"
  [[ "$snippet" == *"'$DEFAULT'"* ]] || fail "expected the snippet to append $DEFAULT"
}

@test "Bash support check probes node with only the option and the mise guards" {
  local snippet
  snippet="$(extract_snippet support-check-bash)"

  cat > "$BATS_TEST_TMPDIR/bin/node" << 'MOCK'
#!/bin/sh
printf 'argv=%s NODE_OPTIONS=%s MISE_AUTO_INSTALL=%s MISE_EXEC_AUTO_INSTALL=%s MISE_OFFLINE=%s\n' \
  "$*" "${NODE_OPTIONS-<unset>}" "${MISE_AUTO_INSTALL-<unset>}" \
  "${MISE_EXEC_AUTO_INSTALL-<unset>}" "${MISE_OFFLINE-<unset>}" >> "$NODE_MOCK_LOG"
exit 0
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/node"
  export NODE_MOCK_LOG="$BATS_TEST_TMPDIR/node-mock.log"

  run env NODE_OPTIONS=--max-old-space-size=4096 bash -c "$snippet"
  assert_success
  assert_output 0

  run cat "$NODE_MOCK_LOG"
  assert_output "argv=-e 0 NODE_OPTIONS=$DEFAULT MISE_AUTO_INSTALL=0 MISE_EXEC_AUTO_INSTALL=0 MISE_OFFLINE=1"
}

@test "PowerShell support check sets each probe variable and restores them in finally" {
  local snippet line
  snippet="$(extract_snippet support-check-powershell | sed 's/^ *//')"

  for line in \
    "\$env:NODE_OPTIONS = '$DEFAULT'" \
    "\$env:MISE_AUTO_INSTALL = '0'" \
    "\$env:MISE_EXEC_AUTO_INSTALL = '0'" \
    "\$env:MISE_OFFLINE = '1'" \
    '$global:LASTEXITCODE = $null' \
    '} finally {' \
    'foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }'; do
    printf '%s\n' "$snippet" | grep -Fxq -- "$line" || fail "expected the line: $line"
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

@test "the install block says a packaged CLI may still fail during the first apply" {
  run grep -c 'any install works' "$GUIDE"
  assert_output 0

  run grep -c 'may still hit the reported ETIMEOUT' "$GUIDE"
  assert_output 1
}
