#!/usr/bin/env bats
#
# Tests for scripts/check-idd-runtime-pins.py (dotfiles issue #688): the
# read-only consistency check between the user-global IDD inventory and the
# chezmoi source. Every case works on a copy of the source in
# BATS_TEST_TMPDIR, so the checkout is never modified. The release and the
# commit are read from the inventory, so a re-import does not edit this file.
# The checker itself is headless and needs no network access or GitHub
# mutation.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  CHECKER="$REPO_ROOT/scripts/check-idd-runtime-pins.py"
  SRC="$BATS_TEST_TMPDIR/src"
  INVENTORY="$REPO_ROOT/.github/idd/user-global-source.json"

  read -r RELEASE COMMIT < <(python3 -I -c \
    'import json, sys; d = json.load(open(sys.argv[1], encoding="utf-8")); print(d["release"], d["upstream"]["commit"])' \
    "$INVENTORY")
  # A release that the inventory never names, used to make a split source.
  OTHER_RELEASE='0.0.1'
  OTHER_COMMIT='0123456789abcdef0123456789abcdef01234567'
  PAYLOAD="home/dot_local/share/idd-skill/$RELEASE"

  mkdir -p "$SRC/.github/idd" "$SRC/$PAYLOAD" "$SRC/home/dot_local/bin" \
    "$SRC/home/dot_claude" "$SRC/home/dot_codex" "$SRC/home/dot_config/opencode" \
    "$SRC/home/dot_agents"
  cp "$REPO_ROOT/.github/idd/config.json" "$INVENTORY" "$SRC/.github/idd/"
  cp -R "$REPO_ROOT/$PAYLOAD/." "$SRC/$PAYLOAD/"
  cp "$REPO_ROOT/home/dot_local/share/idd-skill/symlink_current" "$SRC/home/dot_local/share/idd-skill/"
  cp "$REPO_ROOT/home/dot_local/bin/"executable_idd-* "$SRC/home/dot_local/bin/"
  cp -R "$REPO_ROOT/home/dot_claude/skills" "$SRC/home/dot_claude/"
  cp -R "$REPO_ROOT/home/dot_agents/skills" "$SRC/home/dot_agents/"
  cp "$REPO_ROOT/home/dot_claude/CLAUDE.md.tmpl" "$SRC/home/dot_claude/"
  cp "$REPO_ROOT/home/dot_codex/AGENTS.md.tmpl" "$SRC/home/dot_codex/"
  cp "$REPO_ROOT/home/dot_config/opencode/AGENTS.md.tmpl" "$SRC/home/dot_config/opencode/"
  mkdir -p "$SRC/home/dot_copilot" "$SRC/home/dot_gemini"
  cp "$REPO_ROOT/home/dot_copilot/copilot-instructions.md.tmpl" "$SRC/home/dot_copilot/"
  cp "$REPO_ROOT/home/dot_gemini/GEMINI.md.tmpl" "$SRC/home/dot_gemini/"
  cp "$REPO_ROOT/home/run_after_83-link-idd-skill-xdg-data.ps1" "$SRC/home/"
}

# Print a sorted digest listing of every regular file under a directory, so a
# test can prove the tree was not written to.
tree_digest() {
  (cd "$1" && find . -type f -print | LC_ALL=C sort | xargs sha256sum)
}

# Rewrite the first payload file name in the copied inventory, or drop a
# scoped entry, with python3 -I. Usage: set_inventory file-key NEW | drop-file KEY
set_inventory() {
  python3 -I - "$SRC/.github/idd/user-global-source.json" "$@" <<'PY'
import json, sys
path, mode, value = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path, encoding='utf-8'))
files = data['scopes'][0]['files']
if mode == 'file-key':
  files[value] = files.pop('.cspell.config.yml')
elif mode == 'drop-file':
  del files[value]
json.dump(data, open(path, 'w', encoding='utf-8'), indent=2)
PY
}

@test "the current checkout is consistent" {
  run python3 -I "$CHECKER" --source-root "$REPO_ROOT"
  assert_success
  assert_output --partial "idd-runtime-pins: consistent (release $RELEASE, commit $COMMIT"
}

@test "a retained older release beside the selected one is accepted" {
  mkdir -p "$SRC/home/dot_local/share/idd-skill/0.0.9/user-global"
  printf 'retained release\n' > "$SRC/home/dot_local/share/idd-skill/0.0.9/user-global/entry.md"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_success
  assert_output --partial 'consistent'
}

@test "a selected payload pointer naming another release is rejected" {
  printf '%s\n' "$OTHER_RELEASE" > "$SRC/home/dot_local/share/idd-skill/symlink_current"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_local/share/idd-skill/symlink_current: selected payload pointer names'
}

@test "a Windows current-pointer version naming another release is rejected" {
  sed -i "s/^\$version = '$RELEASE'/\$version = '$OTHER_RELEASE'/" \
    "$SRC/home/run_after_83-link-idd-skill-xdg-data.ps1"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/run_after_83-link-idd-skill-xdg-data.ps1: Windows current-pointer version is'
}

@test "each wrapper variant pinned to another commit is rejected" {
  local wrapper
  for wrapper in executable_idd-activation executable_idd-activation.ps1 \
    executable_idd-effective-config executable_idd-effective-config.ps1; do
    cp "$REPO_ROOT/home/dot_local/bin/$wrapper" "$SRC/home/dot_local/bin/$wrapper"
    sed -i "s/$COMMIT/$OTHER_COMMIT/g" "$SRC/home/dot_local/bin/$wrapper"
    run python3 -I "$CHECKER" --source-root "$SRC"
    assert_failure 1
    assert_output --partial "FAIL home/dot_local/bin/$wrapper: pins idd-skill commit $OTHER_COMMIT"
    cp "$REPO_ROOT/home/dot_local/bin/$wrapper" "$SRC/home/dot_local/bin/$wrapper"
  done
}

@test "a launcher that drops its package spec is rejected" {
  sed -i 's#^exec npx .*#exec npx --yes idd-activation "$@"#' \
    "$SRC/home/dot_local/bin/executable_idd-activation"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_local/bin/executable_idd-activation: npx launch does not pass the exact package spec'
}

@test "a repository helper pin for another commit is rejected even when versions agree" {
  python3 -I - "$SRC/.github/idd/config.json" "$COMMIT" "$OTHER_COMMIT" <<'PY'
import json, sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(path, encoding='utf-8'))
data['helperRuntime']['packageSpec'] = data['helperRuntime']['packageSpec'].replace(old, new)
json.dump(data, open(path, 'w', encoding='utf-8'), indent=2)
PY
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL .github/idd/config.json: helperRuntime.packageSpec does not match the inventory commit'
}

@test "a package spec quoted only in a comment does not satisfy the launch rule" {
  sed -i 's#^exec npx .*#exec npx --yes idd-activation "$@"#' \
    "$SRC/home/dot_local/bin/executable_idd-activation"
  printf '# https://codeload.github.com/kurone-kito/idd-skill/tar.gz/%s\n' "$COMMIT" \
    >> "$SRC/home/dot_local/bin/executable_idd-activation"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'npx launch does not pass the exact package spec'
}

@test "a package spec placed in an inline comment does not satisfy the launch rule" {
  sed -i "s#^exec npx .*#exec npx --yes idd-activation \"\$@\" \# https://codeload.github.com/kurone-kito/idd-skill/tar.gz/$COMMIT#" \
    "$SRC/home/dot_local/bin/executable_idd-activation"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_local/bin/executable_idd-activation: npx launch does not pass the exact package spec'
}

@test "a launcher that runs another package with the spec only in a comment is rejected" {
  sed -i "s#^exec npx .*#exec npx --yes other-package \"\$@\" \# $COMMIT#" \
    "$SRC/home/dot_local/bin/executable_idd-activation"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_local/bin/executable_idd-activation: npx launch does not pass the exact package spec'
}

@test "a missing expected wrapper is diagnosed" {
  rm "$SRC/home/dot_local/bin/executable_idd-effective-config.cmd"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_local/bin/executable_idd-effective-config.cmd: expected wrapper is missing'
}

@test "an unlisted wrapper is rejected" {
  printf 'echo extra\n' > "$SRC/home/dot_local/bin/executable_idd-extra"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_local/bin/executable_idd-extra: unlisted wrapper'
}

@test "a payload scope that names another release is rejected even when files match" {
  python3 -I - "$SRC/.github/idd/user-global-source.json" "$RELEASE" <<'PY'
import json, sys
path, release = sys.argv[1], sys.argv[2]
data = json.load(open(path, encoding='utf-8'))
data['scopes'][0]['sourceRoot'] = 'home/dot_local/share/idd-skill/0.0.1'
json.dump(data, open(path, 'w', encoding='utf-8'), indent=2)
PY
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL .github/idd/user-global-source.json: scope payload must name'
}

@test "an inventory whose tag does not match its release is rejected" {
  python3 -I - "$SRC/.github/idd/user-global-source.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding='utf-8'))
data['upstream']['tag'] = 'v0.0.1'
json.dump(data, open(path, 'w', encoding='utf-8'), indent=2)
PY
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL .github/idd/user-global-source.json: upstream.tag must be v'
}

@test "an inventory that omits a required scope is rejected" {
  python3 -I - "$SRC/.github/idd/user-global-source.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding='utf-8'))
data['scopes'] = [s for s in data['scopes'] if s['id'] != 'skills-agents']
json.dump(data, open(path, 'w', encoding='utf-8'), indent=2)
PY
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL .github/idd/user-global-source.json: inventory must carry exactly the scopes'
}

@test "a versioned harness template naming another release is rejected" {
  sed -i "s#idd-skill/$RELEASE/#idd-skill/0.0.1/#" "$SRC/home/dot_gemini/GEMINI.md.tmpl"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_gemini/GEMINI.md.tmpl: harness entry names version 0.0.1'
}

@test "a symlinked ancestor of a scope root is rejected" {
  rm -rf "$SRC/home/dot_agents"
  ln -s dot_claude "$SRC/home/dot_agents"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_agents/skills: scope source root is missing or not a directory'
}

@test "help exits successfully" {
  run python3 -I "$CHECKER" --help
  assert_success
  assert_output --partial 'usage:'
}

@test "a repository config that is not a JSON object is rejected" {
  printf '[]\n' > "$SRC/.github/idd/config.json"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL .github/idd/config.json: config must be a JSON object'
}

@test "a repository iddVersion naming another release is rejected" {
  sed -i "s/\"iddVersion\": \"$RELEASE\"/\"iddVersion\": \"$OTHER_RELEASE\"/" "$SRC/.github/idd/config.json"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL .github/idd/config.json: iddVersion is'
}

@test "a skill edited while keeping the version string is rejected" {
  printf '\nlocal edit\n' >> "$SRC/home/dot_claude/skills/issue-authoring/SKILL.md"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_claude/skills/issue-authoring/SKILL.md: digest differs from the inventory (scope skills-claude)'
}

@test "an unlisted file in a skill tree is rejected" {
  printf 'extra\n' > "$SRC/home/dot_agents/skills/issue-authoring/extra.md"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_agents/skills/issue-authoring/extra.md: unlisted scoped file'
}

@test "a payload file missing from the source is diagnosed" {
  rm "$SRC/$PAYLOAD/dot_github/idd/config.json"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial "FAIL $PAYLOAD/dot_github/idd/config.json: listed in the inventory but missing"
}

@test "an inventory that omits a source file is diagnosed as an unlisted file" {
  set_inventory drop-file '.github/idd/config.json'
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial "FAIL $PAYLOAD/dot_github/idd/config.json: unlisted scoped file"
}

@test "a malformed inventory fails closed" {
  printf '{ "schemaVersion": 1,\n' > "$SRC/.github/idd/user-global-source.json"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL .github/idd/user-global-source.json: malformed JSON'
}

@test "an inventory path that escapes the source root is rejected" {
  set_inventory file-key '../../escape.txt'
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'unsafe path'
}

@test "a symbolic link inside a scoped tree is rejected" {
  ln -s ../../dot_claude/skills/issue-authoring/SKILL.md \
    "$SRC/home/dot_agents/skills/issue-authoring/linked.md"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_agents/skills/issue-authoring/linked.md: symbolic link is not allowed in a scope'
}

@test "a missing scoped source root is diagnosed" {
  rm -rf "$SRC/home/dot_agents/skills"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  assert_output --partial 'FAIL home/dot_agents/skills: scope source root is missing'
}

@test "a source root that is not a directory is a usage error" {
  run python3 -I "$CHECKER" --source-root "$BATS_TEST_TMPDIR/absent"
  assert_failure 2
  assert_output --partial 'source root is not a directory'
}

@test "the checker writes nothing to valid or invalid source trees" {
  local before after
  before="$(tree_digest "$SRC")"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_success
  after="$(tree_digest "$SRC")"
  assert_equal "$after" "$before"

  printf '\nlocal edit\n' >> "$SRC/home/dot_claude/skills/issue-authoring/SKILL.md"
  before="$(tree_digest "$SRC")"
  run python3 -I "$CHECKER" --source-root "$SRC"
  assert_failure 1
  after="$(tree_digest "$SRC")"
  assert_equal "$after" "$before"
}

@test "the checker never consults the operator's installed home" {
  local bogus_home="$BATS_TEST_TMPDIR/bogus-home"
  mkdir -p "$bogus_home/.local/share/idd-skill" "$bogus_home/.claude/skills"
  printf '9.9.9\n' > "$bogus_home/.local/share/idd-skill/current"
  run env HOME="$bogus_home" XDG_DATA_HOME="$bogus_home/.local/share" \
    python3 -I "$CHECKER" --source-root "$REPO_ROOT"
  assert_success
  assert_output --partial 'consistent'
}
