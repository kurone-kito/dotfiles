#!/usr/bin/env bats
# Tests for the fzf (fuzzy finder) shell integration script.

bats_require_minimum_version 1.5.0

setup() {
  load 'helpers/bats-support/load'
  load 'helpers/bats-assert/load'

  export HOME="$BATS_TEST_TMPDIR"
  SCRIPT_PATH="$BATS_TEST_DIRNAME/../../home/dot_config/shell/conf.d/70-fzf.sh"
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  FZF_LOG="$BATS_TEST_TMPDIR/fzf.log"
  FZF_RESULT="$BATS_TEST_TMPDIR/fzf.result"
  FZF_CD_TARGET="$BATS_TEST_TMPDIR"
  FZF_PROC_VERSION="$BATS_TEST_TMPDIR/proc-version"
  unset FZF_MOCK_VERSION
  mkdir -p "$MOCK_BIN"
  : > "$FZF_LOG"
  : > "$FZF_RESULT"
  printf '%s\n' 'Linux version 6.6.0-microsoft-standard-WSL2' \
    > "$FZF_PROC_VERSION"
  export SCRIPT_PATH MOCK_BIN FZF_LOG FZF_RESULT FZF_CD_TARGET FZF_PROC_VERSION
  _ORIG_PATH="$PATH"
}

teardown() {
  export PATH="$_ORIG_PATH"
}

write_modern_mock() {
  cat > "$MOCK_BIN/fzf" << 'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$FZF_LOG"
  case "$1" in
  --version)
    echo "${FZF_MOCK_VERSION:-0.74.0} (test)"
    ;;
  --bash)
    cat << 'BASH'
fzf-file-widget() { printf 'file:%s\n' "${READLINE_LINE-}" >> "$FZF_RESULT"; }
__fzf_history__() { printf 'history:%s\n' "${READLINE_LINE-}" >> "$FZF_RESULT"; }
__fzf_cd__() { printf 'cd -- %s\n' "$FZF_CD_TARGET"; }
__fzf_default_completion() { printf 'completion:%s\n' "$*" >> "$FZF_RESULT"; }
_fzf_replacement() {
  printf 'replacement:%s:%s:%s:%s:%s\n' "$1" "$2" "$3" \
    "${COMP_LINE-}" "${COMP_POINT-}" >> "$FZF_RESULT"
  return 124
}
complete -F _fzf_replacement fzf-replaced-command
if [ "${FZF_CTRL_T_COMMAND-x}" != "" ]; then
  bind -m emacs-standard -x '"\C-t": fzf-file-widget'
fi
if [ "${FZF_ALT_C_COMMAND-x}" != "" ]; then
  bind -m emacs-standard -x '"\ec": __fzf_cd__'
fi
BASH
    ;;
  --zsh)
    cat << 'ZSH'
fzf-file-widget() { print -r -- "zsh-file:${BUFFER-}" >> "$FZF_RESULT"; }
fzf-history-widget() { print -r -- "zsh-history:${BUFFER-}" >> "$FZF_RESULT"; }
fzf-cd-widget() { print -r -- "zsh-cd:${BUFFER-}" >> "$FZF_RESULT"; }
fzf-completion() { print -r -- "zsh-completion:${BUFFER-}" >> "$FZF_RESULT"; }
ZSH
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/fzf"
  export PATH="$MOCK_BIN:$_ORIG_PATH"
}

write_legacy_mock() {
  write_modern_mock
  export FZF_MOCK_VERSION=0.42.0
  FZF_DIR="$BATS_TEST_TMPDIR/share/fzf"
  mkdir -p "$FZF_DIR"
  printf '%s\n' \
    'fzf-file-widget() { printf "legacy-file:%s\\n" "${READLINE_LINE-}" >> "$FZF_RESULT"; }' \
    > "$FZF_DIR/key-bindings.bash"
  printf '%s\n' \
    '__fzf_default_completion() { printf "legacy-completion:%s\\n" "$*" >> "$FZF_RESULT"; }' \
    > "$FZF_DIR/completion.bash"
  export FZF_DIR
}

@test "WSL startup defers version probe and integration" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    bash --noprofile --norc -i -c '. "$SCRIPT_PATH"; test ! -s "$FZF_LOG"'
  assert_success
}

@test "WSL first binding preserves input and initializes exactly once" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    FZF_RESULT="$FZF_RESULT" FZF_CD_TARGET="$FZF_CD_TARGET" \
    bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      READLINE_LINE="prefix"
      READLINE_POINT=6
      _dotfiles_fzf_file_widget
      printf "first:%s\n" "$(head -n 1 "$FZF_RESULT")"
      _dotfiles_fzf_cd_widget
      _dotfiles_fzf_file_widget
      printf "pwd:%s\n" "$PWD" >> "$FZF_RESULT"
      printf "%s\n" "$(cat "$FZF_RESULT")"
    '
  assert_success
  assert_output --partial 'first:file:prefix'
  assert_output --partial 'file:prefix'
  assert_output --partial "pwd:$BATS_TEST_TMPDIR"
  run grep -c -- '--version' "$FZF_LOG"
  assert_output '1'
  run grep -c -- '--bash' "$FZF_LOG"
  assert_output '1'
}

@test "WSL completion initializes once and dispatches the first completion" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    FZF_RESULT="$FZF_RESULT" bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      _dotfiles_fzf_completion first-input
      printf "%s\n" "$(cat "$FZF_RESULT")"
    '
  assert_success
  assert_output --partial 'completion:first-input'
  run grep -c -- '--bash' "$FZF_LOG"
  assert_output '1'
}

@test "WSL completion preserves existing default and explicit handlers" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    FZF_RESULT="$FZF_RESULT" bash --noprofile --norc -i -c '
      _original_default() { printf "default:%s\n" "${COMP_WORDS[0]}" >> "$FZF_RESULT"; }
      _original_explicit() {
        COMPREPLY=(explicit-match)
        printf "explicit:%s:%s:%s\n" "$1" "$2" "$3" >> "$FZF_RESULT"
        return 124
      }
      complete -D -F _original_default
      complete -F _original_explicit -W "word-match" example-command
      . "$SCRIPT_PATH"
      COMP_WORDS=(printf)
      COMP_CWORD=1
      _dotfiles_fzf_completion default-input
      COMP_WORDS=(example-command)
      _dotfiles_fzf_completion explicit-command current-word previous-word
      printf "status:%s\n" "$?"
      printf "explicit-comreply:%s\n" "${COMPREPLY[*]}"
      cat "$FZF_RESULT"
    '
  assert_success
  assert_output --partial 'default:printf'
  assert_output --partial 'explicit:explicit-command:current-word:previous-word'
  assert_output --partial 'status:124'
  assert_output --partial 'explicit-comreply:explicit-match word-match'
}

@test "WSL completion preserves word-list and command handlers" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    bash --noprofile --norc -i -c '
      complete -D -W "alpha beta"
      __test_completion_command() {
        printf "command-result:%s:%s:%s:%s:%s\\n" "$1" "$2" "$3" \
          "${COMP_LINE-}" "${COMP_POINT-}"
      }
      complete -C __test_completion_command command-completion
      . "$SCRIPT_PATH"
      COMP_WORDS=(word-command a)
      COMP_CWORD=1
      _dotfiles_fzf_completion
      printf "word:%s\\n" "${COMPREPLY[*]}"
      COMP_WORDS=(command-completion)
      COMP_CWORD=1
      COMP_LINE="command-completion a"
      COMP_POINT=20
      _dotfiles_fzf_completion command-name current-word previous-word
      printf "command:%s\\n" "${COMPREPLY[*]}"
    '
  assert_success
  assert_output --partial 'word:alpha'
  assert_output --partial 'command:command-result:command-name:current-word:previous-word:command-completion a:20'
}

@test "WSL completion uses fzf replacement installed during lazy setup" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    FZF_RESULT="$FZF_RESULT" bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      COMP_WORDS=(fzf-replaced-command current)
      COMP_CWORD=1
      COMP_LINE="fzf-replaced-command current"
      COMP_POINT=29
      _dotfiles_fzf_completion replaced-command current previous
      printf "status:%s\n" "$?"
      cat "$FZF_RESULT"
    '
  assert_success
  assert_output --partial 'replacement:replaced-command:current:previous:fzf-replaced-command current:29'
  assert_output --partial 'status:124'
}

@test "WSL legacy integration loads on first use" {
  write_legacy_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" FZF_DIR="$FZF_DIR" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    FZF_RESULT="$FZF_RESULT" bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      READLINE_LINE="legacy-input"
      _dotfiles_fzf_file_widget
      _dotfiles_fzf_completion legacy-completion
      cat "$FZF_RESULT"
    '
  assert_success
  assert_output --partial 'legacy-file:legacy-input'
  assert_output --partial 'legacy-completion:legacy-completion'
  run grep -c -- '--version' "$FZF_LOG"
  assert_output '1'
}

@test "non-WSL interactive shells retain eager integration" {
  write_modern_mock
  printf '%s\n' 'Linux version 6.6.0-generic' > "$FZF_PROC_VERSION"

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    bash --noprofile --norc -i -c '. "$SCRIPT_PATH"; test -s "$FZF_LOG"'
  assert_success
  run grep -c -- '--bash' "$FZF_LOG"
  assert_output '1'
}

@test "disabled WSL bindings remain disabled" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    FZF_CTRL_T_COMMAND='' bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      ! bind -m emacs-standard -X | grep -q _dotfiles_fzf_file_widget
    '
  assert_success
  refute [ -s "$FZF_LOG" ]
}

@test "disabled WSL bindings survive lazy setup" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    FZF_CTRL_T_COMMAND='' FZF_ALT_C_COMMAND='' \
    bash --noprofile --norc -i -c '
      bind -m emacs-standard -x '\''"\C-t": echo custom-t'\''
      bind -m emacs-standard -x '\''"\ec": echo custom-c'\''
      . "$SCRIPT_PATH"
      _dotfiles_fzf_history_widget
      bind -m emacs-standard -X
    '
  assert_success
  assert_output --partial 'custom-t'
  assert_output --partial 'custom-c'
}

@test "missing fzf and non-interactive shells are clean no-op paths" {
  BASH_BIN="$(command -v bash)"
  run env PATH="$BATS_TEST_TMPDIR/no-fzf" \
    SCRIPT_PATH="$SCRIPT_PATH" DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" \
    "$BASH_BIN" --noprofile --norc -i -c \
      '! command -v fzf >/dev/null 2>&1; . "$SCRIPT_PATH"'
  assert_success

  write_modern_mock
  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    bash --noprofile --norc -c '. "$SCRIPT_PATH"; test ! -s "$FZF_LOG"'
  assert_success
}

@test "zsh WSL widgets defer and preserve the first buffer" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not available"
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    FZF_RESULT="$FZF_RESULT" zsh -f -i -c '
      . "$SCRIPT_PATH"
      BUFFER="zsh-input"
      _dotfiles_fzf_file_widget
      printf "first:%s\n" "$(head -n 1 "$FZF_RESULT")"
      _dotfiles_fzf_file_widget
      cat "$FZF_RESULT"
    '
  assert_success
  assert_output --partial 'first:zsh-file:zsh-input'
  assert_output --partial 'zsh-file:zsh-input'
  run grep -c -- '--zsh' "$FZF_LOG"
  assert_output '1'
}
