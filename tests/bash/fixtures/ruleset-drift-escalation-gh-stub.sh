#!/usr/bin/env bash
# Stub `gh` binary for tests/bash/ruleset-drift-escalation.bats. Records
# every invocation (one line per call) to the file at $GH_CALL_LOG, and
# returns canned JSON for the read-only lookups the real test cases
# depend on:
#   - `gh issue list ...`  -> prints $GH_STUB_ISSUE_LIST_JSON, raw JSON
#     (default: `[]`) -- the real script applies its own local `jq`
#     filter to this command's output, so the stub returns unfiltered
#     JSON exactly like the real `gh issue list --json ...` would.
#   - `gh api repos/{owner}/{repo}/labels/<name>` -> simulates the real
#     single-label GET endpoint: exits 0 (label exists) when <name>
#     appears (whitespace-separated) in $GH_STUB_EXISTING_LABELS,
#     otherwise exits 1 (label absent, mirroring a real 404) -- no
#     stdout either way, since the real script only checks this
#     command's exit status.
# Every other subcommand (`issue create`, `issue comment`, `label
# create`, `issue close`) is a pure recording no-op: it never talks to
# GitHub, so these tests never create, comment on, or close anything in
# the live repository. `issue create`/`issue comment` additionally
# capture their piped `--body-file -` stdin to the file at
# $GH_BODY_LOG (truncated once per invocation, not appended -- each
# call gets its own file so a test can assert on exactly what that one
# call piped) instead of discarding it, so a test can assert on the
# actual escalation/recovery body content (missing/extra contexts, the
# run URL), not just the `gh` argv -- an argv-only assertion would miss
# a regression that silently dropped that content from the piped body
# while leaving the command-line flags unchanged.
set -euo pipefail

: "${GH_CALL_LOG:?GH_CALL_LOG must be set by the test}"
printf 'CALL: %s\n' "$*" >> "$GH_CALL_LOG"

case "${1:-} ${2:-}" in
  "issue list")
    printf '%s\n' "${GH_STUB_ISSUE_LIST_JSON:-[]}"
    exit 0
    ;;
  "issue create" | "issue comment")
    if [ -n "${GH_BODY_LOG:-}" ]; then
      cat > "$GH_BODY_LOG"
    else
      cat > /dev/null
    fi
    exit 0
    ;;
  "label create" | "issue close")
    exit 0 # no stdin expected for these
    ;;
esac

if [ "${1:-}" = "api" ]; then
  case "${2:-}" in
    */labels/*)
      requested_label="${2##*/labels/}"
      for existing_label in ${GH_STUB_EXISTING_LABELS:-}; do
        if [ "$existing_label" = "$requested_label" ]; then
          exit 0
        fi
      done
      exit 1
      ;;
  esac
fi

exit 0
