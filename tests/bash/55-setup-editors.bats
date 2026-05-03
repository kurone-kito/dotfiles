#!/usr/bin/env bats
# Tests for the editor setup chezmoi post-apply script (POSIX version).

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  unset XDG_DATA_HOME
  FIXTURE="$BATS_TEST_DIRNAME/fixtures/55-setup-editors.sh"
  _ORIG_PATH="$PATH"

  # Build isolated bin directory BEFORE overriding PATH
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  for cmd in mkdir touch dirname chmod printf echo cat test rm; do
    real="$(command -v "$cmd" 2>/dev/null || true)"
    [ -n "$real" ] && ln -sf "$real" "$BATS_TEST_TMPDIR/bin/$cmd"
  done
  ln -sf "$(command -v bash)" "$BATS_TEST_TMPDIR/bin/bash"

  # Isolated PATH: only mock bin + symlinked essentials
  export PATH="$BATS_TEST_TMPDIR/bin"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

make_mock_command() {
  cat > "$BATS_TEST_TMPDIR/bin/$1" << EOF
#!/bin/sh
$2
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
}

# -----------------------------------------------------------------------
# Neither editor found
# -----------------------------------------------------------------------
@test "prints skip message when neither vim nor nvim is found" {
  run bash "$FIXTURE"

  assert_success
  assert_output --partial "vim not found"
  assert_output --partial "nvim not found"
  assert_output --partial "No editors found"
}

# -----------------------------------------------------------------------
# vim: vim-plug bootstrap + PlugInstall
# -----------------------------------------------------------------------
@test "bootstraps vim-plug with curl when plug.vim is missing" {
  # curl is invoked as: curl -fLo <path> --create-dirs <url>
  # The mock extracts the output path (arg after -fLo) and creates it.
  make_mock_command curl \
    'outpath=""; prev=""; for arg; do case "$prev" in -fLo) outpath="$arg";; esac; prev="$arg"; done; [ -n "$outpath" ] && mkdir -p "$(dirname "$outpath")" && touch "$outpath"; echo "curl:downloaded"'
  make_mock_command vim "echo 'vim:ran plugin sync'"

  run bash "$FIXTURE"

  assert_success
  assert_output --partial "Bootstrapping vim-plug"
  assert_output --partial "vim plugin sync complete"
}

@test "skips vim-plug bootstrap when plug.vim already exists" {
  mkdir -p "${BATS_TEST_TMPDIR}/.vim/autoload"
  touch "${BATS_TEST_TMPDIR}/.vim/autoload/plug.vim"
  make_mock_command vim "echo 'vim:ran plugin sync'"

  run bash "$FIXTURE"

  assert_success
  refute_output --partial "Bootstrapping vim-plug"
  assert_output --partial "vim plugin sync complete"
}

@test "warns when curl is not available for vim-plug bootstrap" {
  make_mock_command vim "echo 'vim:ran plugin sync'"
  # curl is not in our mocked PATH

  run bash "$FIXTURE"

  assert_success
  assert_output --partial "curl not found"
  refute_output --partial "vim plugin sync complete"
}

@test "warns when vim plugin sync fails" {
  mkdir -p "${BATS_TEST_TMPDIR}/.vim/autoload"
  touch "${BATS_TEST_TMPDIR}/.vim/autoload/plug.vim"
  make_mock_command vim "exit 1"

  run bash "$FIXTURE"

  assert_success
  assert_output --partial "WARNING: vim plugin sync reported errors"
}

@test "passes correct flags to vim" {
  mkdir -p "${BATS_TEST_TMPDIR}/.vim/autoload"
  touch "${BATS_TEST_TMPDIR}/.vim/autoload/plug.vim"
  make_mock_command vim "echo \"vim-args:\$*\""

  run bash "$FIXTURE"

  assert_success
  assert_output --partial "vim-args:-es -u ${BATS_TEST_TMPDIR}/.vimrc -c PlugInstall --sync -c PlugClean! -c qa!"
}

# -----------------------------------------------------------------------
# nvim: lazy.nvim
# -----------------------------------------------------------------------
@test "runs nvim two-phase bootstrap and lazy sync" {
  make_mock_command nvim '
mkdir -p "$HOME/.local/share/nvim/lazy/lazy.nvim"
echo "nvim-args:$*"
'

  run bash "$FIXTURE"

  assert_success
  assert_output --partial "nvim-args:--headless +qa"
  assert_output --partial "nvim-args:--headless +Lazy! sync +qa"
  assert_output --partial "nvim plugin sync complete"
}

@test "warns when lazy.nvim bootstrap fails (lazydir not created)" {
  make_mock_command nvim "exit 1"

  run bash "$FIXTURE"

  assert_success
  assert_output --partial "WARNING: lazy.nvim bootstrap failed; skipping nvim plugin sync"
}

@test "warns when nvim plugin sync fails" {
  make_mock_command nvim '
case "$*" in
  *Lazy*) exit 1 ;;
esac
mkdir -p "$HOME/.local/share/nvim/lazy/lazy.nvim"
'

  run bash "$FIXTURE"

  assert_success
  assert_output --partial "WARNING: nvim plugin sync reported errors"
}

# -----------------------------------------------------------------------
# Both editors present
# -----------------------------------------------------------------------
@test "sets up both editors when both are available" {
  mkdir -p "${BATS_TEST_TMPDIR}/.vim/autoload"
  touch "${BATS_TEST_TMPDIR}/.vim/autoload/plug.vim"
  make_mock_command vim "echo 'vim:ok'"
  make_mock_command nvim '
mkdir -p "$HOME/.local/share/nvim/lazy/lazy.nvim"
echo "nvim:ok"
'

  run bash "$FIXTURE"

  assert_success
  assert_output --partial "Setting up vim plugins"
  assert_output --partial "vim plugin sync complete"
  assert_output --partial "Setting up nvim plugins"
  assert_output --partial "nvim plugin sync complete"
  refute_output --partial "No editors found"
}
