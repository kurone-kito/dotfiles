#!/usr/bin/env bats
#
# Drift guard for the advisory-wait required-field lists (issue #607).
#
# The pinned upstream schema's `required` array is vendored as
# tests/bash/fixtures/advisory-wait-required.txt: its first line is the
# idd-skill commit from helperRuntime.packageSpec, and its remaining lines
# are the schema's required names. The required-list sentence of each
# advisory-wait instruction file must backtick exactly those names, no more
# and no fewer. A pin update therefore fails this file until the fixture is
# refreshed, and a dropped backtick or a stray or missing name fails it too.
#
# Scope of the guarantee: this file checks snapshot consistency only. It
# does not fetch the schema at the pinned commit, so it cannot tell whether
# the fixture's names still match that schema. Refreshing the fixture from
# the schema at each pin is a manual step, recorded in docs/idd-policy.md.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  FIXTURE="$REPO_ROOT/tests/bash/fixtures/advisory-wait-required.txt"
  FULL_FILE="$REPO_ROOT/home/dot_local/share/idd-skill/0.17.0/dot_github/instructions/idd-advisory-wait.instructions.md"
  FULL_LEAD='Required helper fields:'
  LITE_FILE="$REPO_ROOT/home/dot_local/share/idd-skill/0.17.0/dot_github/instructions/lite/idd-advisory-wait-lite.instructions.md"
  LITE_LEAD='Required fields (stop and ask if any are missing):'
}

# check_required_paragraph <fixture> <instruction-file> <lead>
#
# Takes the paragraph that starts with <lead> up to the first blank line,
# then its required-list sentence (up to the first ". "). The names
# backticked in that sentence must equal the fixture names exactly, in
# both directions. A name missing from the sentence, or an extra backticked
# name in it, fails the check.
check_required_paragraph() {
  python3 -I - "$1" "$2" "$3" <<'PY'
import re
import sys

fixture, path, lead = sys.argv[1], sys.argv[2], sys.argv[3]

with open(fixture, encoding="utf-8") as f:
    lines = f.read().split("\n")
names = [line for line in lines[1:] if line]
if not names:
    print("error: fixture lists no required names")
    sys.exit(1)

with open(path, encoding="utf-8") as f:
    doc = f.read().split("\n")

start = next((i for i, line in enumerate(doc) if line.startswith(lead)), None)
if start is None:
    print(f"error: no paragraph starts with {lead!r} in {path}")
    sys.exit(1)

paragraph = []
for line in doc[start:]:
    if line.strip() == "":
        break
    paragraph.append(line)
text = " ".join(paragraph)

# Only the required-list sentence counts. A later sentence in the same
# paragraph (the lite file's optional staleRequestRecovery note) is not
# part of the schema-required list. The sentence ends at the first ". "
# outside backticks, so a required name that contains ". " does not end
# the sentence early.
end = -1
in_code = False
for i, ch in enumerate(text):
    if ch == "`":
        in_code = not in_code
    elif not in_code and text.startswith(". ", i):
        end = i
        break
sentence = text[: end + 1] if end != -1 else text
listed = re.findall(r"`([^`]+)`", sentence)

if len(names) != len(set(names)):
    print("error: fixture names must be unique")
    sys.exit(1)
# A set comparison hides a repeated name, so reject repeats in the list
# separately: each required name must appear exactly once.
if len(listed) != len(set(listed)):
    dups = sorted({n for n in listed if listed.count(n) > 1})
    print(f"error: {path}: repeated names in the required list: {dups}")
    sys.exit(1)

missing = sorted(set(names) - set(listed))
extra = sorted(set(listed) - set(names))
if missing or extra:
    print(f"error: {path}: missing {missing}, extra {extra}")
    sys.exit(1)
print(f"ok: {len(names)} names match in {path}")
PY
}

@test "fixture first line is the commit pinned in helperRuntime.packageSpec" {
  run python3 -I - "$REPO_ROOT/.github/idd/config.json" "$FIXTURE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    spec = json.load(f)["helperRuntime"]["packageSpec"]
with open(sys.argv[2], encoding="utf-8") as f:
    first = f.read().split("\n", 1)[0]

pinned = spec.rstrip("/").rsplit("/", 1)[-1]
if first != pinned:
    print(f"error: fixture commit {first!r} != pinned commit {pinned!r}")
    sys.exit(1)
print(f"ok: fixture commit {first}")
PY
  assert_success
}

@test "fixture names are non-empty, backtick-free, and unique (no fixed count)" {
  run python3 -I - "$FIXTURE" <<'PY'
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    names = [line for line in f.read().split("\n")[1:] if line]
if not names:
    print("error: fixture lists no required names")
    sys.exit(1)
# JSON Schema property names may be any string, so only reject what this
# line-based, backtick-delimited fixture cannot hold.
bad = [n for n in names if "`" in n or n != n.strip()]
dups = sorted({n for n in names if names.count(n) > 1})
if bad or dups:
    print(f"error: bad names {bad}, duplicates {dups}")
    sys.exit(1)
print(f"ok: {len(names)} unique names")
PY
  assert_success
}

@test "full advisory-wait paragraph backticks every fixture name" {
  run check_required_paragraph "$FIXTURE" "$FULL_FILE" "$FULL_LEAD"
  assert_success
}

@test "lite advisory-wait paragraph backticks every fixture name" {
  run check_required_paragraph "$FIXTURE" "$LITE_FILE" "$LITE_LEAD"
  assert_success
}

@test "negative: removing the backticks around one name fails the check" {
  local copy="$BATS_TEST_TMPDIR/idd-advisory-wait.instructions.md"
  local name
  # Take a real fixture name at run time, so a later pin that drops a
  # particular field does not break this case. It asserts the generic
  # diagnostic, not the field name.
  name="$(sed -n 2p "$FIXTURE")"
  cp "$FULL_FILE" "$copy"
  # Strip the backticks around one name, only inside the required-field
  # paragraph, so the rest of the file stays identical.
  python3 -I - "$copy" "$FULL_LEAD" "$name" <<'PY'
import sys

path, lead, name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as f:
    doc = f.read().split("\n")
start = next(i for i, line in enumerate(doc) if line.startswith(lead))
end = start
while end < len(doc) and doc[end].strip() != "":
    end += 1
for i in range(start, end):
    if f"`{name}`" in doc[i]:
        doc[i] = doc[i].replace(f"`{name}`", name, 1)
        break
else:
    sys.exit("name not found in paragraph")
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(doc))
PY
  run check_required_paragraph "$FIXTURE" "$copy" "$FULL_LEAD"
  assert_failure
  assert_output --partial 'missing'
}

@test "negative: an extra backticked name in the required-list sentence fails the check" {
  local copy="$BATS_TEST_TMPDIR/idd-advisory-wait.instructions.md"
  local name sentinel
  name="$(sed -n 2p "$FIXTURE")"
  # The sentinel must not be a real field, so pick one the fixture lacks.
  sentinel="staleBogusField"
  while grep -qxF "$sentinel" "$FIXTURE"; do sentinel="${sentinel}X"; done
  cp "$FULL_FILE" "$copy"
  # Add a backticked name that the fixture does not list just before a real
  # fixture name in the required-field paragraph. The anchor is picked at run
  # time and found anywhere in the paragraph, so neither a later pin nor a
  # reflowed paragraph breaks this mutation.
  python3 -I - "$copy" "$FULL_LEAD" "$name" "$sentinel" <<'PY'
import sys

path, lead, name, sentinel = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path, encoding="utf-8") as f:
    doc = f.read().split("\n")
start = next(i for i, line in enumerate(doc) if line.startswith(lead))
found = False
for i in range(start, len(doc)):
    if doc[i].strip() == "":
        break
    if f"`{name}`" in doc[i]:
        doc[i] = doc[i].replace(f"`{name}`", f"`{sentinel}`, `{name}`", 1)
        found = True
        break
if not found:
    sys.exit("anchor not found")
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(doc))
PY
  run check_required_paragraph "$FIXTURE" "$copy" "$FULL_LEAD"
  assert_failure
  assert_output --partial 'extra'
}

@test "a required name containing '. ' does not end the required-list sentence" {
  local dir="$BATS_TEST_TMPDIR/dotted"
  mkdir -p "$dir"
  printf '%s\n' "sha-placeholder" "protocolVersion" "a. b" > "$dir/fixture.txt"
  printf '%s\n' \
    "Required fields (stop and ask if any are missing): \`protocolVersion\`, \`a. b\`. A later sentence mentions \`staleRequestRecovery\`." \
    > "$dir/instructions.md"
  run check_required_paragraph "$dir/fixture.txt" "$dir/instructions.md" \
    "Required fields (stop and ask if any are missing):"
  assert_success
}

@test "negative: a repeated name in the required-list sentence fails the check" {
  local copy="$BATS_TEST_TMPDIR/idd-advisory-wait.instructions.md"
  local name
  name="$(sed -n 2p "$FIXTURE")"
  cp "$FULL_FILE" "$copy"
  # Repeat a real fixture name, picked at run time, inside the required-field
  # paragraph. A set comparison alone would accept this, so the duplicate
  # check must catch it.
  python3 -I - "$copy" "$FULL_LEAD" "$name" <<'PY'
import sys

path, lead, name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as f:
    doc = f.read().split("\n")
start = next(i for i, line in enumerate(doc) if line.startswith(lead))
found = False
for i in range(start, len(doc)):
    if doc[i].strip() == "":
        break
    if f"`{name}`" in doc[i]:
        doc[i] = doc[i].replace(f"`{name}`", f"`{name}`, `{name}`", 1)
        found = True
        break
if not found:
    sys.exit("anchor not found")
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(doc))
PY
  run check_required_paragraph "$FIXTURE" "$copy" "$FULL_LEAD"
  assert_failure
  assert_output --partial 'repeated names'
}

@test "negative: a fixture with no names fails the check instead of passing vacuously" {
  local empty="$BATS_TEST_TMPDIR/advisory-wait-required.txt"
  head -n 1 "$FIXTURE" > "$empty"
  run check_required_paragraph "$empty" "$FULL_FILE" "$FULL_LEAD"
  assert_failure
  assert_output --partial 'no required names'
}
