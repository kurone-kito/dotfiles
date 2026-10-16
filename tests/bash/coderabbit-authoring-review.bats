#!/usr/bin/env bats
#
# Tests for home/dot_local/bin/executable_coderabbit-authoring-review, the
# IDD issue-authoring draft reviewer. Every test drives the launcher with a
# stub `coderabbit` on PATH, so no live CodeRabbit account is needed. The
# stub records its argv and working directory, and reads the committed draft
# from the repository it runs in.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_HOME="$BATS_TEST_DIRNAME/../../home"
  LAUNCHER="$REPO_HOME/dot_local/bin/executable_coderabbit-authoring-review"
  STUB_DIR="$BATS_TEST_TMPDIR/stubs"
  STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$STUB_DIR" "$TMPDIR"
  export TMPDIR STUB_LOG

  cat > "$STUB_DIR/coderabbit" <<'STUB'
#!/bin/sh
# Test stub: records argv and cwd, then behaves per STUB_MODE.
printf 'argv:%s\n' "$*" >> "$STUB_LOG"
printf 'cwd:%s\n' "$(pwd -P)" >> "$STUB_LOG"
case "$1 $2" in
  'auth status')
    if [ "${STUB_MODE:-ok}" = hang ]; then sleep 30; fi
    printf '{"authenticated": true}\n'
    exit 0 ;;
  'review --agent')
    git show HEAD:draft.md > "$STUB_LOG.draft"
    case "${STUB_MODE:-ok}" in
      ok) printf 'REVIEW OK\n'; exit 0 ;;
      fail) printf 'partial review\n'; exit 3 ;;
      extra) printf 'REVIEW OK\n'; : > extra-file.txt; exit 0 ;;
    esac ;;
esac
exit 9
STUB
  chmod +x "$STUB_DIR/coderabbit"

  # PATH holds only the stub and the tools the launcher needs. A real
  # coderabbit on the host must never be reachable from these tests: it would
  # send the draft to the external service.
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  for tool in sh bash git jq timeout cat cmp find rm rmdir mkdir mktemp ln chmod sort cut dirname grep sed awk wc tail head tr env uname sha256sum shasum printf kill sleep; do
    tool_path=$(command -v "$tool" 2>/dev/null || true)
    if [ -n "$tool_path" ]; then
      ln -s "$tool_path" "$BIN/$tool"
    fi
  done
  PATH="$STUB_DIR:$BIN"
  export PATH

  DRAFT='{"title":"Add the draft reviewer","body":"Body text.","packet":{"goal":"Ship the reviewer.","constraints":["No live calls"],"evidence":[],"relationships":["Refs #657"],"checklist":["Lint passes"]}}'
}

# Leaves no temporary repository behind after a run that removed its own.
_no_leftovers() {
  run find "$TMPDIR" -mindepth 1 -maxdepth 1
  assert_output ''
}

@test "help prints the usage line on stdout and exits 0" {
  run "$LAUNCHER" --help

  assert_success
  assert_output 'Usage: coderabbit-authoring-review'
}

@test "any other argument prints the usage line on stderr and exits 2" {
  run --separate-stderr "$LAUNCHER" --bogus

  assert_failure 2
  assert_output ''
  assert_equal "$stderr" 'Usage: coderabbit-authoring-review'
}

@test "stdin that is not the expected draft shape fails with empty stdout" {
  for input in '' 'not json' '{"title":"T"}' \
    '{"title":"","body":"B","packet":{"goal":"G","constraints":[],"evidence":[],"relationships":[],"checklist":[]}}' \
    '{"title":"T","body":"B","packet":{"goal":"G","constraints":[],"evidence":[],"relationships":[]}}' \
    '{"title":"T","body":"B","extra":1,"packet":{"goal":"G","constraints":[],"evidence":[],"relationships":[],"checklist":[]}}'; do
    run --separate-stderr bash -c 'printf "%s" "$1" | "$2"' _ "$input" "$LAUNCHER"

    assert_failure
    assert_output ''
  done
  [ ! -s "$STUB_LOG" ]
}

@test "a valid draft is committed, reviewed in a temporary repository, and cleaned up" {
  run --separate-stderr bash -c 'printf "%s" "$1" | "$2"' _ "$DRAFT" "$LAUNCHER"

  assert_success
  assert_output 'REVIEW OK'
  grep -q '^argv:auth status --agent$' "$STUB_LOG"
  grep -q '^argv:review --agent --base ' "$STUB_LOG"
  grep -q '^# Add the draft reviewer$' "$STUB_LOG.draft"
  grep -q '^- \[ \] Lint passes$' "$STUB_LOG.draft"
  _no_leftovers
}

@test "the review runs in the temporary repository, not in the caller's checkout" {
  caller="$BATS_TEST_TMPDIR/caller"
  mkdir -p "$caller"
  cd "$caller"

  run --separate-stderr bash -c 'printf "%s" "$1" | "$2"' _ "$DRAFT" "$LAUNCHER"

  assert_success
  ! grep -q "^cwd:$(pwd -P)\$" "$STUB_LOG"
  grep -q '^cwd:' "$STUB_LOG"
}

@test "a dirty caller checkout is left exactly as it was" {
  caller="$BATS_TEST_TMPDIR/caller"
  mkdir -p "$caller"
  git -C "$caller" init -q
  git -C "$caller" -c user.name=t -c user.email=t@invalid -c commit.gpgsign=false commit -q --allow-empty -m base
  printf 'tracked\n' > "$caller/tracked.txt"
  git -C "$caller" add tracked.txt
  printf 'untracked\n' > "$caller/untracked.txt"
  before=$(git -C "$caller" status --porcelain)
  cd "$caller"

  run bash -c 'printf "%s" "$1" | "$2"' _ "$DRAFT" "$LAUNCHER"

  assert_success
  assert_equal "$(git -C "$caller" status --porcelain)" "$before"
}

@test "a review that exits non-zero fails with empty stdout and leaves no repository" {
  export STUB_MODE=fail

  run --separate-stderr bash -c 'printf "%s" "$1" | "$2"' _ "$DRAFT" "$LAUNCHER"

  assert_failure 3
  assert_output ''
  _no_leftovers
}

@test "a missing coderabbit fails closed with empty stdout" {
  rm -f "$STUB_DIR/coderabbit"

  run --separate-stderr bash -c 'printf "%s" "$1" | "$2"' _ "$DRAFT" "$LAUNCHER"

  assert_failure
  assert_output ''
  assert_regex "$stderr" 'coderabbit is not on PATH'
}

@test "a probe that hangs is bounded by CODERABBIT_CRITIQUE_TIMEOUT and fails closed" {
  export STUB_MODE=hang CODERABBIT_CRITIQUE_TIMEOUT=1

  run --separate-stderr bash -c 'printf "%s" "$1" | "$2"' _ "$DRAFT" "$LAUNCHER"

  assert_failure
  assert_output ''
  _no_leftovers
}

@test "a repository with a user-added file is kept, and its review is still returned" {
  export STUB_MODE=extra

  run --separate-stderr bash -c 'printf "%s" "$1" | "$2"' _ "$DRAFT" "$LAUNCHER"

  assert_success
  assert_output 'REVIEW OK'
  assert_regex "$stderr" 'kept temporary repository at '
  kept=$(find "$TMPDIR" -mindepth 1 -maxdepth 1 -name 'coderabbit-authoring-review.*' | head -1)
  [ -n "$kept" ]
  [ -f "$kept/extra-file.txt" ]
  [ -f "$kept/draft.md" ]
}
