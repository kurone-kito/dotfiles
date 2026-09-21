#!/usr/bin/env bash
# Local pre-push/post-fix validation dispatcher. Always runs the bash
# bats suite; runs the (slow) PowerShell Pester suite only when the
# current branch's diff against the development branch touches a
# PowerShell-relevant path, so an unrelated change (e.g. a bash-only or
# config-only fix) does not pay for a full local Pester run that CI
# would run anyway. See issue #467 for the motivating example: a
# 2-file bash/config change still ran the full local Pester suite,
# taking ~15 minutes locally versus ~1.5 minutes on CI's Windows
# runners, for a change no Pester test actually depended on.
#
# Usage: scripts/run-validate.sh [--dry-run]
#   --dry-run   Print the run/skip decision (and why) without invoking
#               either suite. Exits 0 regardless of the decision --
#               used by tests/bash/70-run-validate.bats to exercise the
#               decision logic against fixture git repos without
#               paying for a real Pester run.
#
# Fail-safe: whenever the changed-file set cannot be determined (no git
# repository, no resolvable merge-base, no upstream), this always
# decides to run Pester -- it never fails safe to skipping it.
set -euo pipefail

# Deliberately no forced `cd` to the script's own directory: this must
# resolve paths (`.github/idd/config.json`, the bats/Pester suite
# invocations below) relative to the caller's current directory, both
# so a real invocation from the repository root behaves the same as
# the original combined command did, and so
# tests/bash/run-validate.bats can exercise this against an isolated
# fixture repository by `cd`-ing into it first.

development_branch() {
  local branch=""
  if [ -f .github/idd/config.json ]; then
    branch="$(jq -r '.developmentBranch // empty' .github/idd/config.json 2>/dev/null || true)"
  fi
  printf '%s' "${branch:-master}"
}

# Prints one changed path per line on success; prints nothing and
# returns non-zero when the diff cannot be determined.
changed_files() {
  local dev_branch merge_base
  dev_branch="$(development_branch)"
  merge_base="$(git merge-base HEAD "origin/$dev_branch" 2>/dev/null)" || return 1
  [ -n "$merge_base" ] || return 1
  git diff --name-only "$merge_base" HEAD 2>/dev/null
}

# Reads changed paths on stdin (one per line); prints "run-pester" or
# "skip-pester" on stdout. Pure decision logic -- no git, no suite
# invocation -- so it is directly testable against a synthetic file
# list.
decide_pester() {
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      home/dot_config/powershell/* | tests/powershell/* | *.ps1 | *.psm1)
        echo "run-pester"
        return 0
        ;;
    esac
  done
  echo "skip-pester"
}

decide() {
  local files
  if files="$(changed_files)"; then
    # A trailing newline is required: command substitution above
    # stripped it, but `while read` silently skips a final line with
    # no trailing newline, which would otherwise drop the only line in
    # a single-changed-file diff.
    printf '%s\n' "$files" | decide_pester
  else
    echo "run-pester"
  fi
}

main() {
  local dry_run=0
  if [ "${1:-}" = "--dry-run" ]; then
    dry_run=1
  fi

  local decision
  decision="$(decide)"

  if [ "$dry_run" -eq 1 ]; then
    if [ "$decision" = "run-pester" ]; then
      echo "would run: bats, Pester"
    else
      echo "would run: bats; would skip: Pester (no PowerShell-relevant path changed)"
    fi
    return 0
  fi

  tests/bash/helpers/bats-core/bin/bats tests/bash/

  if [ "$decision" = "run-pester" ]; then
    pwsh -c "Invoke-Pester tests/powershell/ -Output Detailed -CI"
  else
    echo "skipping PowerShell Pester suite: no path under home/dot_config/powershell/, tests/powershell/, or matching *.ps1/*.psm1 changed against $(development_branch)"
  fi
}

main "$@"
