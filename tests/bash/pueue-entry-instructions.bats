#!/usr/bin/env bats
# Tests for the `## Testing` sections of the four repository entry files
# (CLAUDE.md, AGENTS.md, README.md, .github/copilot-instructions.md): each must
# document the full lint and test runs as the queue wrapper applied to
# scripts/run-fix-validate.sh and scripts/run-validate.sh, and must keep the
# explanations the issue asks to keep. The checker is a pair of shell functions
# below; mutation cases run it on edited copies to prove that it fails when a
# section omits any required piece.
# cspell:words pueue

bats_require_minimum_version 1.5.0

ENTRY_FILES=(CLAUDE.md AGENTS.md README.md .github/copilot-instructions.md)

LINT_RUN='scripts/with-pueue.sh scripts/run-fix-validate.sh'
TEST_RUN='scripts/with-pueue.sh scripts/run-validate.sh'
SUBMODULE_STEP='git submodule update --init --recursive'

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  MUTANT="$BATS_TEST_TMPDIR/mutant"
  mkdir -p "$MUTANT"
}

# ---------------------------------------------------------------------------
# The checker
# ---------------------------------------------------------------------------

# Print the lines of the `## Testing` section of $1: everything after the
# heading up to, not including, the next `## ` line. A `### ` heading does not
# end the section, and a `## ` line inside a fenced block does not either.
entry_section() {
  awk '
    /^```/ { fence = !fence }
    !started && !fence && /^## Testing$/ { started = 1; next }
    started && !fence && /^## / { exit }
    started { print }
  ' "$1"
}

# Reduce a line to its command: no indentation, list marker, backticks or
# prompt in front, no backticks or blanks behind.
normalize_line() {
  sed -E 's/^[[:space:]]*//; s/^([-*]|[0-9]+\.)[[:space:]]+//; s/^`+//; s/^\$ //; s/`+[[:space:]]*$//; s/[[:space:]]+$//'
}

# Succeed when one sentence of the text $1 contains every term given after it.
# Sentences are split at a full stop followed by a blank.
sentence_with_terms() {
  local text="$1" sentence term ok
  shift
  while IFS= read -r sentence; do
    ok=1
    for term in "$@"; do
      case "$sentence" in *"$term"*) ;; *)
        ok=0
        break
        ;;
      esac
    done
    [ "$ok" -eq 1 ] && return 0
  done < <(printf '%s\n' "$text" | sed -E 's/\. /.\n/g')
  return 1
}

# Print one message per problem found in the Testing section of $1; print
# nothing when the section is as required.
entry_problems() {
  local section collapsed normalized
  section="$(entry_section "$1")"
  if [ -z "$section" ]; then
    echo "missing section"
    return 0
  fi
  normalized="$(printf '%s\n' "$section" | normalize_line)"

  printf '%s\n' "$normalized" | grep -qxF "$LINT_RUN" || echo "missing queued lint run"
  printf '%s\n' "$normalized" | grep -qxF "$TEST_RUN" || echo "missing queued test run"
  printf '%s\n' "$normalized" | grep -qxF "$SUBMODULE_STEP" || echo "missing direct submodule step"

  # The wrapper may only be applied to the two scripts: an allowlist, so
  # `with-pueue.sh bats ...`, `with-pueue.sh git submodule ...` and a
  # continuation line all fail.
  local line
  while IFS= read -r line; do
    case "$line" in
      "scripts/with-pueue.sh" | "scripts/with-pueue.sh "*)
        [ "$line" = "$LINT_RUN" ] || [ "$line" = "$TEST_RUN" ] || echo "wrapper applied to something else: $line"
        ;;
    esac
  done <<< "$normalized"
  if printf '%s\n' "$section" | grep -F 'with-pueue.sh' | grep -qF 'git submodule'; then
    echo "submodule step queued"
  fi

  # The bare suites must not come first: the first command line that starts
  # with the wrapper precedes the first command line that starts with a bare
  # bats or Pester run. Prose that merely mentions them does not count.
  local wrapper_line bare_line
  wrapper_line="$(printf '%s\n' "$normalized" | grep -n -E '^scripts/with-pueue\.sh' | head -1 | cut -d: -f1)"
  bare_line="$(printf '%s\n' "$normalized" | grep -n -E '^(tests/bash/helpers/bats-core/bin/bats|Invoke-Pester)' | head -1 | cut -d: -f1)"
  if [ -n "$bare_line" ] && { [ -z "$wrapper_line" ] || [ "$bare_line" -lt "$wrapper_line" ]; }; then
    echo "bare suite before the queued runs"
  fi

  # Prose rules run on the collapsed text (one line, single blanks, no
  # backticks, so a sentence that wraps still matches) and ask for the meaning
  # rather than the exact wording: one sentence must carry every stable term.
  collapsed="$(printf '%s\n' "$section" | tr '\n' ' ' | tr -s ' ' | tr -d '`')"
  sentence_with_terms "$collapsed" 'scripts/run-validate.sh' 'skips' 'no PowerShell-relevant path' ||
    echo "missing skip-Pester statement"
  sentence_with_terms "$collapsed" 'authoritative' 'full PowerShell run' 'Windows CI' ||
    echo "missing Windows authority statement"
  sentence_with_terms "$collapsed" 'pueue-parallelism' 'corrupt' 'status 2' ||
    echo "missing fallback statement"
}

# ---------------------------------------------------------------------------
# Mutation helpers
# ---------------------------------------------------------------------------

# Copy $1 (relative to the repository) into the mutant tree, replacing every
# literal occurrence of $2 by $3 inside the Testing section only.
mutate() {
  local rel="$1" from="$2" to="$3"
  mkdir -p "$MUTANT/$(dirname "$rel")"
  awk -v from="$from" -v to="$to" '
    function replace_all(s,   out, i) {
      out = ""
      while ((i = index(s, from)) > 0) {
        out = out substr(s, 1, i - 1) to
        s = substr(s, i + length(from))
      }
      return out s
    }
    /^```/ { fence = !fence }
    started && !fence && /^## / { started = 0 }
    !started && !done && !fence && /^## Testing$/ { started = 1; done = 1; print; next }
    started { print replace_all($0); next }
    { print }
  ' "$REPO_ROOT/$rel" > "$MUTANT/$rel"
  if cmp -s "$REPO_ROOT/$rel" "$MUTANT/$rel"; then
    fail "the mutation of $rel ('$from') changed nothing"
  fi
}

# ---------------------------------------------------------------------------
# The real files
# ---------------------------------------------------------------------------

@test "each entry file has a Testing section" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    [ -n "$(entry_section "$REPO_ROOT/$rel")" ] || fail "$rel has no Testing section"
  done
}

@test "each Testing section documents the queued full runs and keeps what the issue keeps" {
  local rel problems
  for rel in "${ENTRY_FILES[@]}"; do
    problems="$(entry_problems "$REPO_ROOT/$rel")"
    [ -z "$problems" ] || fail "$rel: $problems"
  done
}

@test "CLAUDE.md and AGENTS.md carry the same Testing section" {
  run diff <(entry_section "$REPO_ROOT/CLAUDE.md") <(entry_section "$REPO_ROOT/AGENTS.md")
  assert_success
}

@test "the sections link the queue guide with a path that resolves" {
  local rel link dir
  for rel in "${ENTRY_FILES[@]}"; do
    link="$(entry_section "$REPO_ROOT/$rel" | grep -o '([^)]*pueue-validation-queue\.md)' | head -1 | tr -d '()')"
    [ -n "$link" ] || fail "$rel does not link docs/pueue-validation-queue.md"
    dir="$(dirname "$REPO_ROOT/$rel")"
    [ -f "$dir/$link" ] || fail "$rel: the link '$link' does not resolve"
  done
}

# ---------------------------------------------------------------------------
# Mutations: the checker must notice each omission
# ---------------------------------------------------------------------------

@test "mutation: omitting scripts/with-pueue.sh from a section is reported" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" 'scripts/with-pueue.sh' ''
    run entry_problems "$MUTANT/$rel"
    assert_output --partial 'missing queued lint run'
    assert_output --partial 'missing queued test run'
  done
}

@test "mutation: omitting scripts/run-fix-validate.sh from a section is reported" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" 'scripts/run-fix-validate.sh' ''
    run entry_problems "$MUTANT/$rel"
    assert_output --partial 'missing queued lint run'
    refute_output --partial 'missing queued test run'
  done
}

@test "mutation: omitting scripts/run-validate.sh from a section is reported" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" 'scripts/run-validate.sh' ''
    run entry_problems "$MUTANT/$rel"
    assert_output --partial 'missing queued test run'
    assert_output --partial 'missing skip-Pester statement'
    refute_output --partial 'missing queued lint run'
  done
}

@test "mutation: dropping the skip-Pester sentence is reported" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" 'but skips the PowerShell' 'but runs the PowerShell'
    run entry_problems "$MUTANT/$rel"
    assert_output 'missing skip-Pester statement'
  done
}

@test "mutation: changing the condition of the skip-Pester sentence is reported" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" 'touches no PowerShell-relevant' 'touches any PowerShell-relevant'
    run entry_problems "$MUTANT/$rel"
    assert_output 'missing skip-Pester statement'
  done
}

@test "prose that mentions a bare suite before the queued runs is not a bare suite line" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" 'overload the host' 'overload the host, unlike Invoke-Pester or tests/bash/helpers/bats-core/bin/bats,'
    run entry_problems "$MUTANT/$rel"
    assert_output ''
  done
}

@test "mutation: dropping the corrupt-file qualification of the fallback is reported" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" 'with status 2 first' 'with an error first'
    run entry_problems "$MUTANT/$rel"
    assert_output 'missing fallback statement'
  done
}

@test "a rewording that keeps the meaning of the kept sentences is accepted" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" 'but skips the PowerShell' 'yet skips the PowerShell'
    run entry_problems "$MUTANT/$rel"
    assert_output ''
    mutate "$rel" 'remains Windows local execution' 'stays with Windows local execution'
    run entry_problems "$MUTANT/$rel"
    assert_output ''
    mutate "$rel" 'stops with status 2 first' 'ends with status 2 before anything else'
    run entry_problems "$MUTANT/$rel"
    assert_output ''
  done
}

@test "mutation: dropping the Windows authority sentence is reported" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" 'authoritative full PowerShell run remains' 'full PowerShell run remains'
    run entry_problems "$MUTANT/$rel"
    assert_output 'missing Windows authority statement'
  done
}

@test "mutation: dropping the direct submodule step is reported" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" 'git submodule update --init --recursive' 'git submodule status'
    run entry_problems "$MUTANT/$rel"
    assert_output 'missing direct submodule step'
  done
}

@test "mutation: queueing the submodule step is reported" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" "$TEST_RUN" 'scripts/with-pueue.sh git submodule update --init --recursive'
    run entry_problems "$MUTANT/$rel"
    assert_output --partial 'wrapper applied to something else: scripts/with-pueue.sh git submodule update --init --recursive'
    assert_output --partial 'missing queued test run'
    assert_output --partial 'submodule step queued'
  done
}

@test "mutation: queueing a bare bats run is reported" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" "$LINT_RUN" 'scripts/with-pueue.sh tests/bash/helpers/bats-core/bin/bats tests/bash/'
    run entry_problems "$MUTANT/$rel"
    assert_output --partial 'wrapper applied to something else'
    assert_output --partial 'missing queued lint run'
  done
}

@test "mutation: a bare suite line that comes before the queued runs is reported" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    # Insert a bare run right after the heading.
    mkdir -p "$MUTANT/$(dirname "$rel")"
    awk '
      /^```/ { fence = !fence }
      !done && !fence && /^## Testing$/ { print; print ""; print "  `tests/bash/helpers/bats-core/bin/bats tests/bash/`"; done = 1; next }
      { print }
    ' "$REPO_ROOT/$rel" > "$MUTANT/$rel"
    run entry_problems "$MUTANT/$rel"
    assert_output 'bare suite before the queued runs'
  done
}

@test "mutation: queued commands outside the Testing section do not count" {
  local rel
  for rel in "${ENTRY_FILES[@]}"; do
    mutate "$rel" 'scripts/with-pueue.sh' ''
    # The commands now live under another heading, after the section.
    printf '\n## Elsewhere\n\n%s\n%s\n' "$LINT_RUN" "$TEST_RUN" >> "$MUTANT/$rel"
    run entry_problems "$MUTANT/$rel"
    assert_output --partial 'missing queued lint run'
    assert_output --partial 'missing queued test run'
  done
}

@test "a section that is gone is reported as such, not as many small problems" {
  mkdir -p "$MUTANT"
  printf '# Title\n\n## Other\n\ntext\n' > "$MUTANT/none.md"
  run entry_problems "$MUTANT/none.md"
  assert_output 'missing section'
}

@test "the section ends at the next level-2 heading only" {
  printf '## Testing\n\n### Sub\n\nline in sub\n\n```text\n## not a heading\n```\n\nafter fence\n\n## Next\n\nnot in section\n' > "$MUTANT/shape.md"
  run entry_section "$MUTANT/shape.md"
  assert_line 'line in sub'
  assert_line '## not a heading'
  assert_line 'after fence'
  refute_line 'not in section'
}
