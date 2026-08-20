#!/usr/bin/env bash
# Drift-detection comparison logic for the `master` branch ruleset's
# `required_status_checks` rule, extracted from
# .github/workflows/ruleset-required-checks-guard.yml so it can be
# unit-tested against fixture JSON (see
# tests/bash/ruleset-drift-check.bats) without mutating the real
# ruleset. See docs/idd-policy.md's "Scheduled drift guard (#249)"
# section for the incident history this guards against.
#
# Usage: scripts/check-ruleset-drift.sh [<rules-json-file>]
#   Reads the flattened `rules/branches/master` rules array (the same
#   shape `jq 'flatten'` produces from that endpoint) from the given
#   file, or from stdin when no file argument is given (or the argument
#   is "-").
#
# Expected contexts default to the list below; override by exporting
# EXPECTED_CONTEXTS as a newline-separated list of context names before
# invoking this script (used by the bats fixtures to test drift cases
# without depending on the production list). This script is the
# canonical location for the default list -- keep it in sync with
# docs/idd-policy.md's "Required status checks on `master`" section (and
# the ruleset itself) whenever a required context is added or removed.
#
# Output contract (stdout):
#   - Zero-rule case: an `::error::` line naming the expected contexts,
#     plus `RULE_COUNT=0`; exits 1.
#   - Drift case: an `::error::` summary, conditional missing/extra
#     `::error::` lines, plus stable `MISSING_CONTEXTS=<comma-or-empty>`
#     / `EXTRA_CONTEXTS=<comma-or-empty>` lines for a caller to parse;
#     exits 1.
#   - Match case: a plain confirmation line plus `RULE_COUNT=<n>`; exits
#     0.
set -euo pipefail

# Force byte-order sorting regardless of the runner's locale, so the
# shell `sort` below and jq's (always byte-order) `sort` agree --
# otherwise a locale-aware sort (which orders case-insensitively) can
# silently desync from jq's output and make `comm` misreport drift or
# matches.
export LC_ALL=C

default_expected_contexts() {
  printf '%s\n' \
    'Bash tests (bats)' \
    'Lua syntax check' \
    'PowerShell tests (Pester)' \
    'idd-advisory-convergence' \
    'lint'
}

main() {
  local input="${1:--}"
  local rules_json
  if [ "$input" = "-" ]; then
    rules_json=$(cat)
  else
    rules_json=$(cat "$input")
  fi

  local expected_sorted
  expected_sorted=$(printf '%s\n' "${EXPECTED_CONTEXTS:-$(default_expected_contexts)}" | sort -u)

  local rule_count
  rule_count=$(printf '%s' "$rules_json" | jq '[.[] | select(.type == "required_status_checks")] | length')

  if [ "$rule_count" -eq 0 ]; then
    echo "::error::master ruleset has no required_status_checks rule (expected contexts: $(printf '%s' "$expected_sorted" | paste -sd, -))"
    echo "RULE_COUNT=0"
    exit 1
  fi

  local actual_sorted
  actual_sorted=$(printf '%s' "$rules_json" | jq -r '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | unique | .[]')

  local missing extra
  missing=$(comm -23 <(printf '%s\n' "$expected_sorted") <(printf '%s\n' "$actual_sorted"))
  extra=$(comm -13 <(printf '%s\n' "$expected_sorted") <(printf '%s\n' "$actual_sorted"))

  if [ -n "$missing" ] || [ -n "$extra" ]; then
    echo "::error::master ruleset required_status_checks context set has drifted from the expected set."
    if [ -n "$missing" ]; then
      echo "::error::Missing context(s): $(printf '%s' "$missing" | paste -sd, -)"
    fi
    if [ -n "$extra" ]; then
      echo "::error::Unexpected extra context(s): $(printf '%s' "$extra" | paste -sd, -)"
    fi
    echo "MISSING_CONTEXTS=$(printf '%s' "$missing" | paste -sd, -)"
    echo "EXTRA_CONTEXTS=$(printf '%s' "$extra" | paste -sd, -)"
    exit 1
  fi

  echo "master ruleset required_status_checks contexts match the expected set."
  echo "RULE_COUNT=$rule_count"
}

main "$@"
