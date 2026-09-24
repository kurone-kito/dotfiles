#!/usr/bin/env bats
# Tests for the zoxide shell integration in RC files.
#
# zoxide must be initialized after every earlier block that can replace
# PROMPT_COMMAND (starship replaces it wholesale instead of appending),
# or zoxide's own doctor check false-positives even though its hook
# keeps running correctly. See home/dot_bashrc and
# home/dot_config/zsh/dot_zshrc's trailing "# zoxide" blocks.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'
  load 'helpers/bats-file/load'

  export HOME="$BATS_TEST_TMPDIR"
  BASHRC_PATH="$BATS_TEST_DIRNAME/../../home/dot_bashrc"
  ZSHRC_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/zsh/dot_zshrc"
  CONFD_DIR="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d"
  _ORIG_PATH="$PATH"
  mkdir -p "$BATS_TEST_TMPDIR/bin"

  # A curated PATH containing only the interpreters/utilities the mocks
  # and the extracted RC blocks actually need, deliberately excluding
  # any real zoxide/starship binary that might be installed on the test
  # host — real system zoxide would otherwise leak into "not in PATH"
  # assertions below regardless of what this test mocks.
  SAFE_BIN_DIR="$BATS_TEST_TMPDIR/safe-bin"
  mkdir -p "$SAFE_BIN_DIR"
  for tool in cat awk grep sed zsh sh bash env chmod; do
    tool_path="$(command -v "$tool" 2> /dev/null)" || continue
    ln -sf "$tool_path" "$SAFE_BIN_DIR/$tool"
  done

  export PATH="$BATS_TEST_TMPDIR/bin:$SAFE_BIN_DIR"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

# Extracts from the trailing "# Prompt" block through end of file, since
# the zoxide block must be the very last thing in both RC files.
extract_bash_prompt_and_zoxide_block() {
  awk '/^# Prompt/ { in_block = 1 } in_block { print }' "$BASHRC_PATH"
}

extract_zsh_prompt_and_zoxide_block() {
  awk '/^# Prompt/ { in_block = 1 } in_block { print }' "$ZSHRC_PATH"
}

# A starship mock that reproduces the real starship init bash/zsh
# behavior relevant here: bash replaces PROMPT_COMMAND wholesale
# (moving any prior value into STARSHIP_PROMPT_COMMAND) instead of
# appending to it; zsh appends to the independent precmd_functions
# array instead.
make_starship_mock() {
  cat > "$BATS_TEST_TMPDIR/bin/starship" << 'MOCK'
#!/bin/sh
if [ "$1" = "init" ] && [ "$2" = "bash" ]; then
  cat << 'EOF'
if [ -z "${PROMPT_COMMAND-}" ]; then
  PROMPT_COMMAND="starship_precmd"
else
  STARSHIP_PROMPT_COMMAND="$PROMPT_COMMAND"
  PROMPT_COMMAND="starship_precmd"
fi
EOF
elif [ "$1" = "init" ] && [ "$2" = "zsh" ]; then
  cat << 'EOF'
typeset -ga precmd_functions
precmd_functions+=(starship_precmd)
EOF
fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/starship"
}

# A zoxide mock that reproduces the real zoxide init bash/zsh hook
# registration relevant here: bash appends "__zoxide_hook;" to
# PROMPT_COMMAND only when not already present; zsh appends to the
# independent chpwd_functions array.
make_zoxide_mock() {
  cat > "$BATS_TEST_TMPDIR/bin/zoxide" << 'MOCK'
#!/bin/sh
if [ "$1" = "init" ] && [ "$2" = "bash" ]; then
  cat << 'EOF'
if [[ ${PROMPT_COMMAND:=} != *'__zoxide_hook'* ]]; then
  PROMPT_COMMAND="__zoxide_hook;${PROMPT_COMMAND#;}"
fi
EOF
elif [ "$1" = "init" ] && [ "$2" = "zsh" ]; then
  cat << 'EOF'
typeset -ga chpwd_functions
chpwd_functions=("${(@)chpwd_functions:#__zoxide_hook}")
chpwd_functions+=(__zoxide_hook)
EOF
fi
MOCK
  chmod +x "$BATS_TEST_TMPDIR/bin/zoxide"
}

# ---------------------------------------------------------------------------
# Static validation
# ---------------------------------------------------------------------------

@test "conf.d no longer ships a standalone zoxide loader" {
  assert_not_exists "$CONFD_DIR/65-zoxide.sh"
}

@test "dot_bashrc initializes zoxide after the starship block" {
  run awk '
    /^# Prompt/ { prompt_line = NR }
    /zoxide init bash/ { zoxide_line = NR }
    END { exit !(prompt_line > 0 && zoxide_line > prompt_line) }
  ' "$BASHRC_PATH"
  assert_success
}

@test "dot_bashrc sets _ZO_DOCTOR=0 before initializing zoxide" {
  run grep -E '_ZO_DOCTOR=0' "$BASHRC_PATH"
  assert_success
}

@test "dot_zshrc initializes zoxide after the starship block" {
  run awk '
    /^# Prompt/ { prompt_line = NR }
    /zoxide init zsh/ { zoxide_line = NR }
    END { exit !(prompt_line > 0 && zoxide_line > prompt_line) }
  ' "$ZSHRC_PATH"
  assert_success
}

@test "dot_zshrc sets _ZO_DOCTOR=0 before initializing zoxide" {
  run grep -E '_ZO_DOCTOR=0' "$ZSHRC_PATH"
  assert_success
}

# ---------------------------------------------------------------------------
# Functional — regression guard for the fixed ordering (bash)
# ---------------------------------------------------------------------------

@test "PROMPT_COMMAND still contains __zoxide_hook after starship replaces it" {
  make_starship_mock
  make_zoxide_mock

  eval "$(extract_bash_prompt_and_zoxide_block)"

  [[ "$PROMPT_COMMAND" == *"__zoxide_hook"* ]]
}

@test "_ZO_DOCTOR is disabled after zoxide initializes" {
  make_starship_mock
  make_zoxide_mock

  eval "$(extract_bash_prompt_and_zoxide_block)"

  assert_equal "$_ZO_DOCTOR" "0"
}

@test "skips zoxide init without error when zoxide is not in PATH" {
  make_starship_mock

  eval "$(extract_bash_prompt_and_zoxide_block)"

  assert_equal "${_ZO_DOCTOR:-}" ""
}

# ---------------------------------------------------------------------------
# Functional — zsh (unaffected by the bug, kept symmetric)
# ---------------------------------------------------------------------------

@test "zsh chpwd_functions still contains __zoxide_hook after starship initializes" {
  make_starship_mock
  make_zoxide_mock

  run zsh -fc "$(extract_zsh_prompt_and_zoxide_block); print -r -- \${chpwd_functions[*]}"
  assert_success
  assert_output --partial "__zoxide_hook"
}

@test "zsh skips zoxide init without error when zoxide is not in PATH" {
  make_starship_mock

  run zsh -fc "$(extract_zsh_prompt_and_zoxide_block); print -r -- \${_ZO_DOCTOR:-}"
  assert_success
  assert_output ""
}
