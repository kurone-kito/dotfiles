#!/usr/bin/env bash
# Stub `gh` binary for tests/bash/ruleset-drift-escalation.bats. Records
# every invocation (one line per call) to the file at $GH_CALL_LOG, and
# returns canned JSON for the read-only lookups the real test cases
# depend on:
#   - `gh issue list ...`  -> prints $GH_STUB_ISSUE_LIST_JSON, raw JSON
#     (default: `[]`) -- the real script applies its own local `jq`
#     filter to this command's output, so the stub returns unfiltered
#     JSON exactly like the real `gh issue list --json ...` would.
#   - `gh label list ...`  -> prints $GH_STUB_LABEL_LIST_NAMES, one label
#     name per line (default: empty) -- the real script asks `gh` itself
#     to apply `--jq '.[].name'`, so the stub returns the
#     already-filtered plain-text names that flag would produce, not
#     raw JSON.
# Every other subcommand (`issue create`, `issue comment`, `label
# create`, `issue close`) is a pure recording no-op: it never talks to
# GitHub, so these tests never create, comment on, or close anything in
# the live repository. `issue create`/`issue comment` additionally drain
# their piped `--body-file -` stdin so the real script's pipe never
# blocks waiting for a reader.
set -euo pipefail

: "${GH_CALL_LOG:?GH_CALL_LOG must be set by the test}"
printf 'CALL: %s\n' "$*" >> "$GH_CALL_LOG"

case "${1:-} ${2:-}" in
  "issue list")
    printf '%s\n' "${GH_STUB_ISSUE_LIST_JSON:-[]}"
    ;;
  "label list")
    printf '%s\n' "${GH_STUB_LABEL_LIST_NAMES:-}"
    ;;
  "issue create" | "issue comment")
    cat > /dev/null
    ;;
  "label create" | "issue close")
    : # no stdin expected for these
    ;;
esac

exit 0
