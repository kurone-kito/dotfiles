#!/usr/bin/env bats
# Tests for the shared conf.d double-sourcing guard.
#
# home/dot_profile and home/dot_bashrc (and dot_zshrc) each source
# every ~/.config/shell/conf.d/*.sh script. In a login+interactive
# shell (every macOS terminal, the initial WSL shell) both the
# .profile chain and .bashrc/.zshrc run, so without a guard the shared
# conf.d loop executes twice. A per-process, unexported sentinel
# variable prevents the second run without leaking into subshells.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  export HOME="$BATS_TEST_TMPDIR"
  mkdir -p "$HOME/.config/shell/conf.d"

  COUNTER="$HOME/confd-sourced.count"
  : > "$COUNTER"
  echo "echo x >> '$COUNTER'" > "$HOME/.config/shell/conf.d/00-counter.sh"

  REPO_HOME="$BATS_TEST_DIRNAME/../../home"
  cp "$REPO_HOME/dot_profile" "$HOME/.profile"
  cp "$REPO_HOME/dot_bash_profile" "$HOME/.bash_profile"
  cp "$REPO_HOME/dot_bashrc" "$HOME/.bashrc"
}

@test "sources shared conf.d exactly once during a login+interactive bash startup" {
  bash -li -c true > /dev/null 2>&1

  run wc -l < "$COUNTER"
  assert_output '1'
}

@test "a nested interactive bash shell still sources conf.d (sentinel does not leak)" {
  run bash -li -c "bash -i -c true" 2>/dev/null
  assert_success

  run wc -l < "$COUNTER"
  assert_output '2'
}

@test "a fresh non-interactive bash invocation still sources conf.d via .profile" {
  run bash -c ". '$HOME/.profile'; wc -l < '$COUNTER'"
  assert_success
  assert_output '1'
}
