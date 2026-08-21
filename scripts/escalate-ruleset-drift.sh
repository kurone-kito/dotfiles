#!/usr/bin/env bash
# Tracking-issue find/escalate/recover logic for the scheduled ruleset
# drift guard (.github/workflows/ruleset-required-checks-guard.yml).
# Extracted into its own script so the de-duplication behavior --
# never opening a second tracking issue while one is already open for
# repeated daily failures -- is directly testable against a stubbed
# `gh` binary (see tests/bash/ruleset-drift-escalation.bats) instead of
# only being verifiable by triggering a live failure against the real
# repository. See docs/idd-policy.md's "Scheduled drift guard (#249)"
# section.
#
# Usage:
#   scripts/escalate-ruleset-drift.sh find-tracking-issue \
#     --title <title> [--repo <owner/repo>]
#
#   scripts/escalate-ruleset-drift.sh escalate --title <title> \
#     --issue <number-or-empty> --missing <csv-or-empty> \
#     --extra <csv-or-empty> --run-url <url> [--repo <owner/repo>]
#
#   scripts/escalate-ruleset-drift.sh recover --issue <number> \
#     --run-url <url> [--repo <owner/repo>]
#
# `--repo` is optional; when omitted, `gh` infers the repository from
# the current working directory the way it always does.
set -euo pipefail

TRACKING_LABEL='bug'
TRACKING_LABEL_DESCRIPTION="Something isn't working"
TRACKING_LABEL_COLOR='d73a4a'

die() {
  echo "escalate-ruleset-drift.sh: $*" >&2
  exit 1
}

require_arg() {
  local name="$1" value="${2:-}"
  [ -n "$value" ] || die "missing required --${name}"
  printf '%s' "$value"
}

# find-tracking-issue -- prints the open tracking issue's number to
# stdout when one exists with an *exact* title match created by this
# workflow, or nothing when none does.
#
# Two narrowing layers, for two different reasons:
#   - gh's --search is a fuzzy text search, not an exact-title filter,
#     so the exact-match narrowing happens locally via jq to avoid
#     reusing (and commenting on) an unrelated issue whose title merely
#     contains the search phrase.
#   - The tracking-issue title is public and fixed, so anyone could
#     open an unrelated issue with that exact title -- the workflow
#     would then treat a stranger's issue as its own tracker (closing
#     it as "recovered" on the next passing run, or commenting on it as
#     if it were the real drift record). Requiring both the `bug` label
#     (server-side, also shrinks the result set against the --limit
#     truncation risk below) and an author matching this workflow's own
#     GITHUB_TOKEN identity (checked locally, tolerant of the different
#     login forms gh has reported for that identity across versions/
#     surfaces) means only an issue this workflow itself created can
#     ever be reused as the tracker.
cmd_find_tracking_issue() {
  local title="" repo=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --repo) repo="$2"; shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  title="$(require_arg title "$title")"

  # --limit high enough that a real truncation is not a practical
  # concern: with only 50, more than 50 open issues fuzzy-matching the
  # search phrase would push the real tracking issue past the page
  # boundary, making this return empty and the caller create a
  # duplicate -- silently defeating the de-duplication guarantee this
  # whole command exists for. `gh` paginates automatically to satisfy a
  # --limit above one page.
  local -a gh_args=(issue list --search "in:title \"${title}\"" --state open --label "$TRACKING_LABEL" --json number,title,author --limit 1000)
  [ -n "$repo" ] && gh_args+=(--repo "$repo")

  gh "${gh_args[@]}" | jq -r --arg t "$title" '
    [.[]
      | select(.title == $t)
      | select(.author.login == "github-actions" or .author.login == "github-actions[bot]" or .author.login == "app/github-actions")
    ][0].number // empty
  '
}

# ensure_label_exists -- a single targeted "get this one label" lookup
# rather than a paginated `label list` + local match. Two prior review
# rounds each flagged a real gap here that this design removes instead
# of patching around: (1) a `--limit`-bounded list can miss an existing
# label in a repository with more labels than the page size, wrongly
# treating it as absent, so `label create` then fails on a label that
# already exists and the whole escalation aborts under `set -e` before
# ever reaching `issue create`/`issue comment`; (2) piping a list
# through `grep` under `pipefail` makes a real `gh` lookup failure
# (rate limit, transient API error) indistinguishable from "label
# genuinely absent" -- both produce the same non-zero pipeline status.
# A single-label GET has no page to overflow, and its own exit code
# means exactly "found" or "not found/error" for that one label, with
# no separate pipeline stage to blur the distinction.
#
# `gh api` has no `--repo`/`-R` flag of its own (unlike `gh label`/
# `gh issue`) -- it resolves `{owner}`/`{repo}` placeholders from the
# ambient git remote or the `GH_REPO` environment variable, so an
# explicit `--repo` selection is threaded through via `GH_REPO` instead.
ensure_label_exists() {
  local label="$1" repo="$2"
  local -a get_args=(api "repos/{owner}/{repo}/labels/${label}" --silent)
  local -a repo_env=()
  [ -n "$repo" ] && repo_env=(env "GH_REPO=$repo")

  if "${repo_env[@]}" gh "${get_args[@]}" 2>/dev/null; then
    return 0
  fi

  local -a create_args=(label create "$label" --description "$TRACKING_LABEL_DESCRIPTION" --color "$TRACKING_LABEL_COLOR")
  [ -n "$repo" ] && create_args+=(--repo "$repo")
  gh "${create_args[@]}"
}

build_drift_body() {
  local missing="$1" extra="$2" run_url="$3"
  {
    echo "The scheduled ruleset drift guard detected that the \`master\` branch ruleset's \`required_status_checks\` rule has drifted from the expected context set."
    echo
    if [ -n "$missing" ]; then
      echo "- Missing context(s): ${missing}"
    fi
    if [ -n "$extra" ]; then
      echo "- Unexpected extra context(s): ${extra}"
    fi
    echo
    echo "Failed run: ${run_url}"
  }
}

build_recovery_body() {
  local run_url="$1"
  {
    echo "The scheduled ruleset drift guard now confirms the \`master\` branch ruleset's \`required_status_checks\` rule matches the expected context set again."
    echo
    echo "Passing run: ${run_url}"
  }
}

# escalate -- creates a tracking issue (labeling it `bug`, creating that
# label first if absent) when `--issue` is empty, or comments on the
# given issue instead when one is already open, so repeated daily
# failures never spam a second issue.
cmd_escalate() {
  local title="" issue="" missing="" extra="" run_url="" repo=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) title="$2"; shift 2 ;;
      --issue) issue="$2"; shift 2 ;;
      --missing) missing="$2"; shift 2 ;;
      --extra) extra="$2"; shift 2 ;;
      --run-url) run_url="$2"; shift 2 ;;
      --repo) repo="$2"; shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  title="$(require_arg title "$title")"
  run_url="$(require_arg run-url "$run_url")"

  local body
  body="$(build_drift_body "$missing" "$extra" "$run_url")"

  if [ -z "$issue" ]; then
    ensure_label_exists "$TRACKING_LABEL" "$repo"
    local -a create_args=(issue create --title "$title" --label "$TRACKING_LABEL" --body-file -)
    [ -n "$repo" ] && create_args+=(--repo "$repo")
    printf '%s\n' "$body" | gh "${create_args[@]}"
  else
    local -a comment_args=(issue comment "$issue" --body-file -)
    [ -n "$repo" ] && comment_args+=(--repo "$repo")
    printf '%s\n' "$body" | gh "${comment_args[@]}"
  fi
}

# recover -- closes the given tracking issue with an explanatory
# comment once the check passes again.
cmd_recover() {
  local issue="" run_url="" repo=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --issue) issue="$2"; shift 2 ;;
      --run-url) run_url="$2"; shift 2 ;;
      --repo) repo="$2"; shift 2 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  issue="$(require_arg issue "$issue")"
  run_url="$(require_arg run-url "$run_url")"

  local body
  body="$(build_recovery_body "$run_url")"

  local -a close_args=(issue close "$issue" --comment "$body")
  [ -n "$repo" ] && close_args+=(--repo "$repo")
  gh "${close_args[@]}"
}

main() {
  local sub="${1:-}"
  [ -n "$sub" ] || die "missing subcommand (find-tracking-issue|escalate|recover)"
  shift

  case "$sub" in
    find-tracking-issue) cmd_find_tracking_issue "$@" ;;
    escalate) cmd_escalate "$@" ;;
    recover) cmd_recover "$@" ;;
    *) die "unknown subcommand: $sub" ;;
  esac
}

main "$@"
