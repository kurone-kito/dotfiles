#!/usr/bin/env bats
#
# Tests for the run_after_82-link-idd-skill-xdg-config chezmoi script:
# bridges the rendered IDD critique-delegate config to a customized
# XDG_CONFIG_HOME.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  SCRIPT="$BATS_TEST_DIRNAME/../../home/run_after_82-link-idd-skill-xdg-config.sh"
  _ORIG_XDG="${XDG_CONFIG_HOME:-}"
  unset XDG_CONFIG_HOME
}

teardown() {
  if [ -n "$_ORIG_XDG" ]; then
    export XDG_CONFIG_HOME="$_ORIG_XDG"
  else
    unset XDG_CONFIG_HOME
  fi
}

write_rendered_config() {
  mkdir -p "$HOME/.config/idd-skill"
  printf '{"critiqueLoop":{"delegate":{"command":"x","mode":"combined"}}}' \
    > "$HOME/.config/idd-skill/config.json"
}

@test "no-ops when XDG_CONFIG_HOME is unset (defaults to \$HOME/.config)" {
  write_rendered_config

  run "$SCRIPT"

  assert_success
  assert_output ""
}

@test "no-ops when XDG_CONFIG_HOME equals \$HOME/.config explicitly" {
  write_rendered_config
  export XDG_CONFIG_HOME="$HOME/.config"

  run "$SCRIPT"

  assert_success
  assert_output ""
}

@test "no-ops when the rendered config does not exist yet" {
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/custom-xdg"

  run "$SCRIPT"

  assert_success
  assert_dir_not_exists "$XDG_CONFIG_HOME/idd-skill"
}

@test "symlinks the rendered config into a custom XDG_CONFIG_HOME" {
  write_rendered_config
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/custom-xdg"

  run "$SCRIPT"

  assert_success
  assert_symlink_to "$HOME/.config/idd-skill/config.json" "$XDG_CONFIG_HOME/idd-skill/config.json"
}

@test "is idempotent when the symlink already points at the rendered config" {
  write_rendered_config
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/custom-xdg"
  mkdir -p "$XDG_CONFIG_HOME/idd-skill"
  ln -s "$HOME/.config/idd-skill/config.json" "$XDG_CONFIG_HOME/idd-skill/config.json"

  run "$SCRIPT"

  assert_success
  assert_output ""
}

@test "does not overwrite a symlink pointing at a different target" {
  write_rendered_config
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/custom-xdg"
  mkdir -p "$XDG_CONFIG_HOME/idd-skill"
  echo '{"other":true}' > "$BATS_TEST_TMPDIR/other-managed-config.json"
  ln -s "$BATS_TEST_TMPDIR/other-managed-config.json" "$XDG_CONFIG_HOME/idd-skill/config.json"

  run "$SCRIPT"

  assert_success
  assert_output --partial "not overwriting"
  run readlink "$XDG_CONFIG_HOME/idd-skill/config.json"
  assert_output "$BATS_TEST_TMPDIR/other-managed-config.json"
}

@test "does not overwrite a real (non-symlink) file already at the target" {
  write_rendered_config
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/custom-xdg"
  mkdir -p "$XDG_CONFIG_HOME/idd-skill"
  echo '{"pre-existing":true}' > "$XDG_CONFIG_HOME/idd-skill/config.json"

  run "$SCRIPT"

  assert_success
  assert_output --partial "not overwriting"
  run cat "$XDG_CONFIG_HOME/idd-skill/config.json"
  assert_output --partial "pre-existing"
}

@test "chezmoiignore excludes the platform-inappropriate run_after script pair" {
  ignore_file="$BATS_TEST_DIRNAME/../../home/.chezmoiignore.tmpl"

  run grep -c '^82-link-idd-skill-xdg-config\.sh$' "$ignore_file"
  assert_output "1"
  run grep -c '^82-link-idd-skill-xdg-config\.ps1$' "$ignore_file"
  assert_output "1"
}
