#!/usr/bin/env bats
#
# Drift guard for the advisory-wait required-field lists (issue #607).
#
# The pinned upstream schema's `required` array is vendored as
# tests/bash/fixtures/advisory-wait-required.txt: its first line is the
# idd-skill commit from helperRuntime.packageSpec, and its remaining lines
# are the schema's required names. Each advisory-wait instruction file
# must list every one of those names in backticks in its required-field
# paragraph. A pin update therefore fails this file until the fixture is
# refreshed, and a dropped backtick or missing name fails it too.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  FIXTURE="$REPO_ROOT/tests/bash/fixtures/advisory-wait-required.txt"
  FULL_FILE="$REPO_ROOT/.github/instructions/idd-advisory-wait.instructions.md"
  FULL_LEAD='Required helper fields:'
  LITE_FILE="$REPO_ROOT/.github/instructions/lite/idd-advisory-wait-lite.instructions.md"
  LITE_LEAD='Required fields (stop and ask if any are missing):'
}

# check_required_paragraph <fixture> <instruction-file> <lead>
#
# Takes the paragraph that starts with <lead> up to the first blank line
# and fails unless every fixture name appears in backticks inside it.
check_required_paragraph() {
  python3 -I - "$1" "$2" "$3" <<'PY'
import sys

fixture, path, lead = sys.argv[1], sys.argv[2], sys.argv[3]

with open(fixture, encoding="utf-8") as f:
    lines = f.read().split("\n")
names = [line for line in lines[1:] if line]

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

missing = [name for name in names if f"`{name}`" not in text]
if missing:
    print(f"error: {path} is missing backticked names: {', '.join(missing)}")
    sys.exit(1)
print(f"ok: {len(names)} names found in {path}")
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

@test "fixture lists the 24 required names of the pinned schema" {
  run bash -c "tail -n +2 '$FIXTURE' | grep -c ."
  assert_success
  assert_output "24"
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
  cp "$FULL_FILE" "$copy"
  # Strip the backticks around one name, only inside the required-field
  # paragraph, so the rest of the file stays identical.
  python3 -I - "$copy" "$FULL_LEAD" <<'PY'
import sys

path, lead = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    doc = f.read().split("\n")
start = next(i for i, line in enumerate(doc) if line.startswith(lead))
end = start
while end < len(doc) and doc[end].strip() != "":
    end += 1
for i in range(start, end):
    if "`copilotPending`" in doc[i]:
        doc[i] = doc[i].replace("`copilotPending`", "copilotPending", 1)
        break
else:
    sys.exit("name not found in paragraph")
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(doc))
PY
  run check_required_paragraph "$FIXTURE" "$copy" "$FULL_LEAD"
  assert_failure
  assert_output --partial 'copilotPending'
}
