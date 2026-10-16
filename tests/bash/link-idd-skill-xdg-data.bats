#!/usr/bin/env bats
#
# Tests for the run_after_83-link-idd-skill-xdg-data chezmoi script: links a
# customized XDG_DATA_HOME/idd-skill to the deployed IDD payload data root,
# only when XDG_DATA_HOME is a qualified root other than ~/.local/share.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  SCRIPT="$BATS_TEST_DIRNAME/../../home/run_after_83-link-idd-skill-xdg-data.sh"
  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  _ORIG_XDG="${XDG_DATA_HOME:-}"
  unset XDG_DATA_HOME
}

teardown() {
  if [ -n "$_ORIG_XDG" ]; then
    export XDG_DATA_HOME="$_ORIG_XDG"
  else
    unset XDG_DATA_HOME
  fi
}

write_deployed_payload() {
  mkdir -p "$HOME/.local/share/idd-skill/0.16.0"
}

@test "no-ops when XDG_DATA_HOME is unset (defaults to \$HOME/.local/share)" {
  write_deployed_payload

  run "$SCRIPT"

  assert_success
  assert_output ""
  assert_dir_exists "$HOME/.local/share/idd-skill"
}

@test "no-ops when XDG_DATA_HOME equals \$HOME/.local/share explicitly" {
  write_deployed_payload
  export XDG_DATA_HOME="$HOME/.local/share"

  run "$SCRIPT"

  assert_success
  assert_output ""
  assert_dir_exists "$HOME/.local/share/idd-skill"
  [ ! -L "$HOME/.local/share/idd-skill" ]
}

@test "no-ops when XDG_DATA_HOME is the default with a trailing slash" {
  write_deployed_payload
  export XDG_DATA_HOME="$HOME/.local/share/"

  run "$SCRIPT"

  assert_success
  assert_output ""
  [ ! -L "$HOME/.local/share/idd-skill" ]
}

@test "no-ops when XDG_DATA_HOME is a link to \$HOME/.local/share" {
  write_deployed_payload
  ln -s "$HOME/.local/share" "$BATS_TEST_TMPDIR/data-alias"
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/data-alias"

  run "$SCRIPT"

  assert_success
  assert_output ""
  [ ! -L "$HOME/.local/share/idd-skill" ]
}

@test "no-ops when XDG_DATA_HOME is the deployed data root or inside it (no self-link)" {
  write_deployed_payload
  export XDG_DATA_HOME="$HOME/.local/share/idd-skill"

  run "$SCRIPT"

  assert_success
  assert_output ""
  [ ! -e "$HOME/.local/share/idd-skill/idd-skill" ]
  [ ! -L "$HOME/.local/share/idd-skill/idd-skill" ]

  export XDG_DATA_HOME="$HOME/.local/share/idd-skill/0.16.0"
  run "$SCRIPT"

  assert_success
  assert_output ""
  [ ! -e "$HOME/.local/share/idd-skill/0.16.0/idd-skill" ]
}

@test "no-ops when XDG_DATA_HOME is a relative path" {
  write_deployed_payload
  export XDG_DATA_HOME="relative/data"
  cd "$BATS_TEST_TMPDIR"

  run "$SCRIPT"

  assert_success
  assert_output ""
  assert_dir_not_exists "$BATS_TEST_TMPDIR/relative"
}

@test "no-ops when XDG_DATA_HOME starts with // (not a qualified root)" {
  write_deployed_payload
  export XDG_DATA_HOME="//${BATS_TEST_TMPDIR#/}/custom-data"

  run "$SCRIPT"

  assert_success
  assert_output ""
  assert_dir_not_exists "$BATS_TEST_TMPDIR/custom-data"
}

@test "no-ops when the deployed data root does not exist yet" {
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/custom-data"

  run "$SCRIPT"

  assert_success
  assert_output ""
  assert_dir_not_exists "$XDG_DATA_HOME/idd-skill"
  [ ! -L "$XDG_DATA_HOME/idd-skill" ]
}

@test "symlinks the deployed data root into a custom XDG_DATA_HOME" {
  write_deployed_payload
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/custom-data"

  run "$SCRIPT"

  assert_success
  assert_symlink_to "$HOME/.local/share/idd-skill" "$XDG_DATA_HOME/idd-skill"
  assert_dir_exists "$XDG_DATA_HOME/idd-skill/0.16.0"
}

@test "trims surrounding whitespace from a qualified XDG_DATA_HOME" {
  write_deployed_payload
  export XDG_DATA_HOME="  $BATS_TEST_TMPDIR/custom-data  "

  run "$SCRIPT"

  assert_success
  assert_symlink_to "$HOME/.local/share/idd-skill" "$BATS_TEST_TMPDIR/custom-data/idd-skill"
}

@test "is idempotent when the symlink already points at the deployed data root" {
  write_deployed_payload
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/custom-data"
  mkdir -p "$XDG_DATA_HOME"
  ln -s "$HOME/.local/share/idd-skill" "$XDG_DATA_HOME/idd-skill"

  run "$SCRIPT"

  assert_success
  assert_output ""
}

@test "does not overwrite a symlink pointing at a different target" {
  write_deployed_payload
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/custom-data"
  mkdir -p "$XDG_DATA_HOME"
  mkdir -p "$BATS_TEST_TMPDIR/other-managed-data"
  ln -s "$BATS_TEST_TMPDIR/other-managed-data" "$XDG_DATA_HOME/idd-skill"

  run "$SCRIPT"

  assert_success
  assert_output --partial "not overwriting"
  run readlink "$XDG_DATA_HOME/idd-skill"
  assert_output "$BATS_TEST_TMPDIR/other-managed-data"
}

@test "does not overwrite a real directory already at the target" {
  write_deployed_payload
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/custom-data"
  mkdir -p "$XDG_DATA_HOME/idd-skill"
  echo 'pre-existing' > "$XDG_DATA_HOME/idd-skill/marker.txt"

  run "$SCRIPT"

  assert_success
  assert_output --partial "not overwriting"
  [ ! -L "$XDG_DATA_HOME/idd-skill" ]
  run cat "$XDG_DATA_HOME/idd-skill/marker.txt"
  assert_output "pre-existing"
}

@test "chezmoiignore excludes the 83 .sh on Windows and the 83 .ps1 elsewhere" {
  ignore_file="$REPO_ROOT/home/.chezmoiignore.tmpl"

  # Track which OS branch each entry sits in: the Windows branch opens at
  # `if eq .chezmoi.os "windows"` and the other-OS branch at `else`; `end`
  # closes either one.
  run awk '
    /\{\{- if eq \.chezmoi\.os "windows" \}\}/ { block = "windows" }
    /\{\{- else \}\}/ { block = "other" }
    /^\{\{- end \}\}/ { block = "" }
    /^83-link-idd-skill-xdg-data\.sh$/ { print "sh:" block }
    /^83-link-idd-skill-xdg-data\.ps1$/ { print "ps1:" block }
  ' "$ignore_file"
  assert_success
  assert_output "$(printf 'sh:windows\nps1:other')"
}

@test "rendered ignore list on this host excludes the 83 .ps1 and keeps the 83 .sh" {
  printf '%s\n' '{ "data": {} }' > "$BATS_TEST_TMPDIR/chezmoi-config.json"

  run --separate-stderr chezmoi execute-template --file "$REPO_ROOT/home/.chezmoiignore.tmpl" \
    --config "$BATS_TEST_TMPDIR/chezmoi-config.json" --config-format json \
    --source "$REPO_ROOT" --destination "$BATS_TEST_TMPDIR"

  assert_success
  assert_line '83-link-idd-skill-xdg-data.ps1'
  refute_line '83-link-idd-skill-xdg-data.sh'
}
