#!/usr/bin/env bats
# Drift guard for the commit-signing ladder in the six agent guidance files:
# home/.chezmoitemplates/ai-agent-user-global, home/.chezmoitemplates/
# opencode-compact-instructions, CLAUDE.md, AGENTS.md, GEMINI.md and
# .github/copilot-instructions.md. Each passage is located by its own wording,
# not by the position or the headings around it. The pre-check passage must
# carry the same probe command in every file, keep the loopback case, and
# pre-classify only the probe's status line for a missing pinentry. The
# verdict sentences around the probe must stay as they are. The checker is the
# shell functions below; the mutation cases run it on edited copies to prove
# that it fails when a passage drifts.
# cspell:words clearsign gnupg pinentry passphrase

bats_require_minimum_version 1.5.0

SIX_FILES=(
  home/.chezmoitemplates/ai-agent-user-global
  home/.chezmoitemplates/opencode-compact-instructions
  CLAUDE.md
  AGENTS.md
  GEMINI.md
  .github/copilot-instructions.md
)

COMPACT=home/.chezmoitemplates/opencode-compact-instructions
SHARED=home/.chezmoitemplates/ai-agent-user-global
COPILOT=.github/copilot-instructions.md

PROBE_TERMS=(
  'printf probe |'
  '--pinentry-mode error'
  '--status-fd 2'
  '--clearsign'
)
VERDICT_TERMS=(
  'Only the status line'
  'is not pre-classified'
  'no TTY is attached'
  'does not set `pinentry-mode loopback`'
  'does not count toward the three-attempt bound'
  'still counts as attempt 1'
  'command timeout'
  'attempt GPG as normal'
)
STATUS_LINE='[GNUPG:] FAILURE sign 67108949'

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

# Print the list item that contains the marker text $2 in file $1: from the
# nearest list-item line above the marker (the marker line itself counts) up
# to, not including, the next list-item line. Print nothing when the marker is
# absent.
list_item_of() {
  awk -v marker="$2" '
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) if (index(line[i], marker)) { hit = i; break }
      if (!hit) exit 0
      start = hit
      for (i = hit; i >= 1; i--) if (line[i] ~ /^ *(-|[0-9]+\.) /) { start = i; break }
      end = NR + 1
      for (i = hit + 1; i <= NR; i++) if (line[i] ~ /^ *(-|[0-9]+\.) /) { end = i; break }
      for (i = start; i < end; i++) print line[i]
    }
  ' "$1"
}

# Print the paragraph that contains the marker text $2 in file $1: the lines
# between the blank lines around the marker. Print nothing when it is absent.
paragraph_of() {
  awk -v marker="$2" '
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) if (index(line[i], marker)) { hit = i; break }
      if (!hit) exit 0
      start = hit
      while (start > 1 && line[start - 1] ~ /[^ ]/) start--
      end = hit
      while (end < NR && line[end + 1] ~ /[^ ]/) end++
      for (i = start; i <= end; i++) print line[i]
    }
  ' "$1"
}

# Join stdin into one line with single spaces, so that a passage can be
# searched for a phrase whatever the wrapping.
flatten() {
  tr '\n' ' ' | tr -s ' '
}

# Print the pre-check passage of the file $2 (relative) under the root $1,
# flattened to one line.
pre_check_of() {
  local marker='No-TTY pre-check'
  [ "$2" = "$COMPACT" ] && marker='pinentry/TTY failure'
  list_item_of "$1/$2" "$marker" | flatten
}

# Print the probe command of the pre-check passage $1 (flattened), with the
# line continuations and the runs of blanks removed.
probe_command_of() {
  printf '%s\n' "$1" | sed -E 's/.*(printf probe \|.*> \/dev\/null).*/\1/' |
    tr -d '\\' | tr -s ' '
}

# Print one message per problem found in the signing ladder of the tree rooted
# at $1; print nothing when every passage is as required. Return 1 when at
# least one problem was printed.
signing_problems() {
  local root="$1" rel pre cmd ref='' flat ci term status=0

  for rel in "${SIX_FILES[@]}"; do
    if [ ! -f "$root/$rel" ]; then
      echo "$rel: file missing"
      status=1
      continue
    fi

    pre="$(pre_check_of "$root" "$rel")"
    if [ -z "$pre" ]; then
      echo "$rel: pre-check passage not found"
      status=1
      continue
    fi

    for term in "${PROBE_TERMS[@]}" "$STATUS_LINE" "${VERDICT_TERMS[@]}"; do
      case "$pre" in
        *"$term"*) ;;
        *)
          echo "$rel: pre-check passage lacks: $term"
          status=1
          ;;
      esac
    done
    case "$pre" in
      *'not a signing attempt'* | *'not an attempt'*) ;;
      *)
        echo "$rel: pre-check passage does not say the probe is not an attempt"
        status=1
        ;;
    esac
    case "$pre" in
      *allow-loopback-pinentry*)
        echo "$rel: pre-check passage still depends on allow-loopback-pinentry"
        status=1
        ;;
    esac
    case "$pre" in
      *both*)
        echo "$rel: pre-check passage restates the two-condition rule"
        status=1
        ;;
    esac

    cmd="$(probe_command_of "$pre")"
    if [ -z "$ref" ]; then
      ref="$cmd"
    elif [ "$cmd" != "$ref" ]; then
      echo "$rel: probe command differs from ${SIX_FILES[0]}"
      status=1
    fi

    flat="$(flatten < "$root/$rel")"
    case "$flat" in
      *'loopback pinentry automatically'* | *'enable loopback automatically'* \
        | *'not a recommendation to add one'*) ;;
      *)
        echo "$rel: lost the rule against configuring loopback automatically"
        status=1
        ;;
    esac
    for term in '(P)' '(C)' '(A)' '(U)' 'commit-ssh'; do
      case "$flat" in
        *"$term"*) ;;
        *)
          echo "$rel: lacks: $term"
          status=1
          ;;
      esac
    done
    if [ "$rel" != "$COMPACT" ]; then
      case "$flat" in
        *'at most three signing attempts'*) ;;
        *)
          echo "$rel: lacks the three-attempt bound"
          status=1
          ;;
      esac
    fi
  done

  # The copilot file and the shared template also carry the rule against
  # recommending loopback and a CI paragraph that must use the probe, not the
  # two conditions that the probe replaced.
  for rel in "$COPILOT" "$SHARED"; do
    flat="$(flatten < "$root/$rel")"
    case "$flat" in
      *'recommend `pinentry-mode loopback`'*) ;;
      *)
        echo "$rel: lost the rule against recommending pinentry-mode loopback"
        status=1
        ;;
    esac
    ci="$(paragraph_of "$root/$rel" 'In CI' | flatten)"
    case "$ci" in
      *probe*) ;;
      *)
        echo "$rel: In CI paragraph does not use the probe"
        status=1
        ;;
    esac
    case "$ci" in
      *both* | *condition*)
        echo "$rel: In CI paragraph restates the two conditions"
        status=1
        ;;
    esac
  done

  return "$status"
}

# Copy the six files into the mutant tree, keeping their relative paths.
mutant_copy() {
  local rel
  rm -rf "$MUTANT"
  for rel in "${SIX_FILES[@]}"; do
    mkdir -p "$MUTANT/$(dirname "$rel")"
    cp "$REPO_ROOT/$rel" "$MUTANT/$rel"
  done
}

# Apply the sed expression $2 to the mutant copy of file $1, in place.
mutate() {
  sed "$2" "$MUTANT/$1" > "$MUTANT/$1.tmp"
  mv "$MUTANT/$1.tmp" "$MUTANT/$1"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "the six signing-ladder passages satisfy the drift guard" {
  run signing_problems "$REPO_ROOT"
  assert_success
  assert_output ""
}

@test "removing --pinentry-mode error from any one file fails the guard" {
  local rel
  for rel in "${SIX_FILES[@]}"; do
    mutant_copy
    mutate "$rel" 's/--pinentry-mode error/--pinentry-mode ask/'
    run signing_problems "$MUTANT"
    assert_failure
    assert_output --partial "$rel: pre-check passage lacks: --pinentry-mode error"
  done
}

@test "a probe that differs in one file fails the guard" {
  mutant_copy
  mutate "$COPILOT" 's/--local-user/--local-key/'
  run signing_problems "$MUTANT"
  assert_failure
  assert_output --partial "$COPILOT: probe command differs from $SHARED"
}

@test "restoring the allow-loopback-pinentry clause in CLAUDE.md fails the guard" {
  mutant_copy
  mutate CLAUDE.md 's/run this probe/run this probe (no `allow-loopback-pinentry` in the effective `gpg-agent.conf`)/'
  run signing_problems "$MUTANT"
  assert_failure
  assert_output --partial "CLAUDE.md: pre-check passage still depends on allow-loopback-pinentry"
}

@test "reversing the not-pre-classified verdict in the copilot file fails the guard" {
  mutant_copy
  mutate "$COPILOT" 's/timeout) is not$/timeout) is/'
  run signing_problems "$MUTANT"
  assert_failure
  assert_output --partial "$COPILOT: pre-check passage lacks: is not pre-classified"
}

@test "restating both conditions in the copilot pre-check fails the guard" {
  mutant_copy
  mutate "$COPILOT" 's/Only when no TTY is attached/Only when **both** conditions hold: no TTY is attached/'
  run signing_problems "$MUTANT"
  assert_failure
  assert_output --partial "$COPILOT: pre-check passage restates the two-condition rule"
}

@test "restating both conditions in the copilot CI paragraph fails the guard" {
  mutant_copy
  mutate "$COPILOT" 's/when its probe reports a/when both conditions hold and its probe reports a/'
  run signing_problems "$MUTANT"
  assert_failure
  assert_output --partial "$COPILOT: In CI paragraph restates the two conditions"
}

@test "dropping the probe status line from the shared template fails the guard" {
  mutant_copy
  mutate "$SHARED" 's/67108949/00000000/'
  run signing_problems "$MUTANT"
  assert_failure
  assert_output --partial "$SHARED: pre-check passage lacks: [GNUPG:] FAILURE sign 67108949"
}

@test "dropping the three-attempt bound from GEMINI.md fails the guard" {
  mutant_copy
  mutate GEMINI.md 's/at most three signing attempts/at most three tries/'
  run signing_problems "$MUTANT"
  assert_failure
  assert_output --partial "GEMINI.md: lacks the three-attempt bound"
}
