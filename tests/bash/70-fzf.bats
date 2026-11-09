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

require_zsh() {
  command -v zsh > /dev/null 2>&1 || skip "zsh not available"
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
__fzf_default_completion() {
  printf 'completion:%s\n' "$*" >> "$FZF_RESULT"
  [ -n "${FZF_MOCK_DEFAULT_REPLY-}" ] \
    && COMPREPLY=("$FZF_MOCK_DEFAULT_REPLY")
}
complete -D -F __fzf_default_completion -o default -o bashdefault
_fzf_replacement() {
  printf 'replacement:%s:%s:%s:%s:%s\n' "$1" "$2" "$3" \
    "${COMP_LINE-}" "${COMP_POINT-}" >> "$FZF_RESULT"
  return 124
}
complete -F _fzf_replacement fzf-replaced-command
if [ -n "${FZF_MOCK_UPSTREAM_HOOK-}" ]; then
  _fzf_compgen_path() { printf 'upstream-path:%s\n' "$1"; }
fi
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
ZSH
    if [ "${FZF_MOCK_ZSH_NO_COMPLETION-}" != x ]; then
      cat << 'ZSH'
fzf-completion() { print -r -- "zsh-completion:${BUFFER-}" >> "$FZF_RESULT"; }
ZSH
    fi
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
    FZF_RESULT="$FZF_RESULT" FZF_MOCK_DEFAULT_REPLY=fzf-match \
    bash --noprofile --norc -i -c '
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
    FZF_RESULT="$FZF_RESULT" FZF_MOCK_DEFAULT_REPLY=fzf-match \
    bash --noprofile --norc -i -c '
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
      printf "default-spec:%s\n" "$(complete -p -D)"
      COMP_WORDS=(example-command)
      _dotfiles_fzf_completion explicit-command current-word previous-word
      printf "status:%s\n" "$?"
      printf "explicit-comreply:%s\n" "${COMPREPLY[*]}"
      cat "$FZF_RESULT"
    '
  assert_success
  assert_output --partial 'default:printf'
  assert_output --partial 'default-spec:complete -F _dotfiles_fzf_completion -D'
  assert_output --partial 'explicit:explicit-command:current-word:previous-word'
  assert_output --partial 'status:124'
  assert_output --partial 'explicit-comreply:explicit-match word-match fzf-match'
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
        bash -c '\''printf "command-context:%s:%s\\n" "$COMP_LINE" "$COMP_POINT"'\''
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
  assert_output --partial 'command-context:command-completion a:20'
}

@test "WSL completion applies modifiers to combined handler results" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    FZF_RESULT="$FZF_RESULT" bash --noprofile --norc -i -c '
      _test_modified_completion() { COMPREPLY=(drop keep); }
      complete -F _test_modified_completion -X "drop*" -P "pre-" -S "-suf" modified-command
      . "$SCRIPT_PATH"
      COMP_WORDS=(modified-command)
      COMP_CWORD=1
      _dotfiles_fzf_completion modified-command current previous
      printf "modifier:%s\n" "${COMPREPLY[*]}"
    '
  assert_success
  assert_output --partial 'modifier:pre-keep-suf'
}

@test "WSL completion honors negated and current-word -X filters" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    bash --noprofile --norc -i -c '
      _negated() { COMPREPLY=(a.txt b.tmp c.txt); }
      complete -F _negated -X "!*.txt" negated-command
      _anchored() { COMPREPLY=(foo.tmp foo.txt bar.tmp); }
      complete -F _anchored -X "&.tmp" anchored-command
      . "$SCRIPT_PATH"
      COMP_WORDS=(negated-command)
      COMP_CWORD=1
      _dotfiles_fzf_completion negated-command "" ""
      printf "neg:%s\n" "${COMPREPLY[*]}"
      COMP_WORDS=(anchored-command foo)
      COMP_CWORD=1
      _dotfiles_fzf_completion anchored-command foo ""
      printf "amp:%s\n" "${COMPREPLY[*]}"
    '
  assert_success
  assert_output --partial 'neg:a.txt c.txt'
  assert_output --partial 'amp:foo.txt bar.tmp'
}

@test "WSL completion leaves COMPREPLY empty when -X removes every match" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    bash --noprofile --norc -i -c '
      _removed() { COMPREPLY=(drop drop2); }
      complete -F _removed -X "drop*" empty-command
      . "$SCRIPT_PATH"
      COMP_WORDS=(empty-command)
      COMP_CWORD=1
      _dotfiles_fzf_completion empty-command "" ""
      printf "empty-count:%s\n" "${#COMPREPLY[@]}"
    '
  assert_success
  assert_output --partial 'empty-count:0'
}

@test "WSL key binding restores an existing default completion bridge" {
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    FZF_RESULT="$FZF_RESULT" bash --noprofile --norc -i -c '
      _original_default() { COMPREPLY=(original); }
      complete -D -F _original_default
      . "$SCRIPT_PATH"
      READLINE_LINE="prefix"
      READLINE_POINT=6
      _dotfiles_fzf_file_widget
      printf "default-spec:%s\n" "$(complete -p -D)"
    '
  assert_success
  assert_output --partial 'default-spec:complete -F _dotfiles_fzf_completion -D'
  refute_output --partial '__fzf_default_completion'
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
  require_zsh
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

@test "zsh WSL completion falls back to the original Tab widget" {
  require_zsh
  write_modern_mock

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    FZF_RESULT="$FZF_RESULT" FZF_MOCK_ZSH_NO_COMPLETION=x zsh -f -i -c '
      _original_tab() { print -r -- "original-tab:${BUFFER-}" >> "$FZF_RESULT"; }
      zle -N _original_tab
      bindkey "^I" _original_tab
      . "$SCRIPT_PATH"
      BUFFER="zsh-tab-input"
      _dotfiles_fzf_completion
      printf "first:%s\n" "$(head -n 1 "$FZF_RESULT")"
      cat "$FZF_RESULT"
    '
  assert_success
  assert_output --partial 'first:original-tab:zsh-tab-input'
  assert_output --partial 'original-tab:zsh-tab-input'
  run grep -c -- '--zsh' "$FZF_LOG"
  assert_output '1'
}

write_walk_fixture() {
  WALK="$BATS_TEST_TMPDIR/walk"
  mkdir -p "$WALK/a" "$WALK/mnt/c/d" "$BATS_TEST_TMPDIR/outside"
  : > "$WALK/a/b.txt"
  : > "$WALK/mnt/c/d/e.txt"
  : > "$BATS_TEST_TMPDIR/outside/leaked.txt"
  ln -s ../outside "$WALK/link"
  export WALK
}

run_walk() {
  # $1: widget variable, $2: directory to run it from, $3: mnt root (optional)
  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="${3:-$WALK/mnt}" WIDGET="$1" WALK_DIR="$2" \
    bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      cd "$WALK_DIR" && sh -c "${!WIDGET}"
    '
}

@test "WSL walk guard defines compgen hooks and widget commands without running fzf" {
  write_modern_mock
  write_walk_fixture

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="$WALK/mnt" \
    bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      printf "path:%s\n" "$(type -t _fzf_compgen_path)"
      printf "dir:%s\n" "$(type -t _fzf_compgen_dir)"
      printf "ctrl-t:%s\n" "${FZF_CTRL_T_COMMAND:+set}"
      printf "alt-c:%s\n" "${FZF_ALT_C_COMMAND:+set}"
    '
  assert_success
  assert_line 'path:function'
  assert_line 'dir:function'
  assert_line 'ctrl-t:set'
  assert_line 'alt-c:set'
  test ! -s "$FZF_LOG"
}

@test "WSL compgen path skips symlink targets and the mnt tree when outside mnt" {
  write_modern_mock
  write_walk_fixture

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="$WALK/mnt" \
    bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      _fzf_compgen_path "$WALK"
    '
  assert_success
  assert_line "$WALK"
  assert_line "$WALK/a/b.txt"
  assert_line "$WALK/link"
  assert_line "$WALK/mnt"
  refute_output --partial 'leaked.txt'
  refute_output --partial "$WALK/mnt/c"
}

@test "WSL compgen hooks list one level when the walk root is inside mnt" {
  write_modern_mock
  write_walk_fixture

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="$WALK/mnt" \
    bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      _fzf_compgen_path "$WALK/mnt/c"
      _fzf_compgen_dir "$WALK/mnt/c"
    '
  assert_success
  assert_line "$WALK/mnt/c"
  assert_line "$WALK/mnt/c/d"
  refute_output --partial 'e.txt'
}

@test "WSL Ctrl-T walk command runs as plain sh without following symlinks outside mnt" {
  write_modern_mock
  write_walk_fixture

  run_walk FZF_CTRL_T_COMMAND "$WALK"
  assert_success
  assert_line 'a/b.txt'
  assert_line 'link'
  assert_line 'mnt'
  refute_line 'mnt/c'
  refute_output --partial 'leaked.txt'
  refute_output --partial 'link/'
}

@test "WSL Alt-C walk command lists directories only outside mnt" {
  write_modern_mock
  write_walk_fixture

  run_walk FZF_ALT_C_COMMAND "$WALK"
  assert_success
  assert_line 'a'
  assert_line 'mnt'
  refute_line 'link'
  refute_output --partial 'b.txt'
  refute_line 'mnt/c'
}

@test "WSL walk commands list one level when run from inside mnt" {
  write_modern_mock
  write_walk_fixture

  run_walk FZF_CTRL_T_COMMAND "$WALK/mnt/c"
  assert_success
  assert_line 'd'
  refute_output --partial 'e.txt'

  run_walk FZF_ALT_C_COMMAND "$WALK/mnt/c"
  assert_success
  assert_line 'd'
  refute_output --partial 'e.txt'
}

@test "WSL key bindings stay bound with the walk widgets installed" {
  write_modern_mock
  write_walk_fixture

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="$WALK/mnt" \
    bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      bind -m emacs-standard -X
    '
  assert_success
  assert_output --partial '_dotfiles_fzf_file_widget'
  assert_output --partial '_dotfiles_fzf_cd_widget'
}

@test "non-WSL shells install neither compgen hooks nor walk widget commands" {
  write_modern_mock
  printf '%s\n' 'Linux version 6.6.0-generic' > "$FZF_PROC_VERSION"

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      printf "path:%s\n" "$(type -t _fzf_compgen_path)"
      printf "dir:%s\n" "$(type -t _fzf_compgen_dir)"
      printf "ctrl-t:%s\n" "${FZF_CTRL_T_COMMAND+set}"
      printf "alt-c:%s\n" "${FZF_ALT_C_COMMAND+set}"
    '
  assert_success
  assert_line 'path:'
  assert_line 'dir:'
  assert_line 'ctrl-t:'
  assert_line 'alt-c:'
}

@test "WSL walk guard leaves a predefined hook and widget command as they are" {
  write_modern_mock
  write_walk_fixture

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="$WALK/mnt" \
    bash --noprofile --norc -i -c '
      _fzf_compgen_path() { printf "custom-path:%s\n" "$1"; }
      FZF_ALT_C_COMMAND="echo custom-c"
      . "$SCRIPT_PATH"
      _fzf_compgen_path "$WALK"
      printf "alt-c:%s\n" "$FZF_ALT_C_COMMAND"
      printf "dir-owned:%s\n" "$(type -t _fzf_compgen_dir)"
    '
  assert_success
  assert_line "custom-path:$WALK"
  assert_line 'alt-c:echo custom-c'
  assert_line 'dir-owned:function'
}

@test "WSL lazy setup keeps the walk hook over an upstream definition" {
  write_modern_mock
  write_walk_fixture

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="$WALK/mnt" FZF_MOCK_UPSTREAM_HOOK=1 \
    bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      READLINE_LINE="x"
      READLINE_POINT=1
      _dotfiles_fzf_file_widget
      _fzf_compgen_path "$WALK/mnt/c"
    '
  assert_success
  assert_line "$WALK/mnt/c/d"
  refute_output --partial 'upstream-path'
}

@test "WSL walk hooks still list when the mnt root does not exist" {
  write_modern_mock
  write_walk_fixture

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="$WALK/absent" \
    bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      _fzf_compgen_path "$WALK/a"
    '
  assert_success
  assert_line "$WALK/a/b.txt"
}

@test "WSL walk commands quote an mnt root that contains an apostrophe" {
  write_modern_mock
  write_walk_fixture
  local quoted_mnt="$BATS_TEST_TMPDIR/it's/mnt"
  mkdir -p "$quoted_mnt/c/d"
  : > "$quoted_mnt/c/d/e.txt"

  run_walk FZF_CTRL_T_COMMAND "$quoted_mnt/c" "$quoted_mnt"
  assert_success
  assert_line 'd'
  refute_output --partial 'e.txt'
}

@test "WSL compgen path enters a symlinked root that the user typed" {
  write_modern_mock
  write_walk_fixture

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="$WALK/mnt" \
    bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      _fzf_compgen_path "$WALK/link"
    '
  assert_success
  assert_line "$WALK/link/leaked.txt"
}

@test "zsh WSL installs the same compgen hooks and widget commands" {
  require_zsh
  write_modern_mock
  write_walk_fixture

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="$WALK/mnt" WALK="$WALK" \
    zsh -f -i -c '
      . "$SCRIPT_PATH"
      whence -w _fzf_compgen_path
      whence -w _fzf_compgen_dir
      print -r -- "ctrl-t:${FZF_CTRL_T_COMMAND+set}"
      print -r -- "alt-c:${FZF_ALT_C_COMMAND+set}"
      (cd "$WALK" && sh -c "$FZF_ALT_C_COMMAND")
    '
  assert_success
  assert_line '_fzf_compgen_path: function'
  assert_line '_fzf_compgen_dir: function'
  assert_line 'ctrl-t:set'
  assert_line 'alt-c:set'
  assert_line 'a'
  refute_line 'link'
}

@test "zsh non-WSL installs neither compgen hook nor walk widget commands" {
  require_zsh
  write_modern_mock
  printf '%s\n' 'Linux version 6.6.0-generic' > "$FZF_PROC_VERSION"

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    zsh -f -i -c '
      . "$SCRIPT_PATH"
      whence -w _fzf_compgen_path
      print -r -- "ctrl-t:${FZF_CTRL_T_COMMAND+set}"
      print -r -- "alt-c:${FZF_ALT_C_COMMAND+set}"
    '
  assert_success
  refute_output --partial '_fzf_compgen_path: function'
  assert_line 'ctrl-t:'
  assert_line 'alt-c:'
}

@test "WSL lazy setup restores a user-defined hook over an upstream definition" {
  write_modern_mock
  write_walk_fixture

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="$WALK/mnt" FZF_MOCK_UPSTREAM_HOOK=1 WALK="$WALK" \
    bash --noprofile --norc -i -c '
      _fzf_compgen_path() { printf "custom-path:%s\n" "$1"; }
      . "$SCRIPT_PATH"
      READLINE_LINE="x"
      READLINE_POINT=1
      _dotfiles_fzf_file_widget
      _fzf_compgen_path "$WALK"
    '
  assert_success
  assert_line "custom-path:$WALK"
  refute_output --partial 'upstream-path'
}

@test "WSL walk commands run from beside an apostrophe mnt root skip its contents" {
  write_modern_mock
  write_walk_fixture
  local quoted_mnt="$BATS_TEST_TMPDIR/it's/mnt"
  mkdir -p "$quoted_mnt/c/d"
  : > "$quoted_mnt/c/d/e.txt"

  run_walk FZF_CTRL_T_COMMAND "$BATS_TEST_TMPDIR/it's" "$quoted_mnt"
  assert_success
  assert_line 'mnt'
  refute_line 'mnt/c'
  refute_output --partial 'e.txt'
}

@test "WSL Ctrl-T stays unbound with an empty FZF_CTRL_T_COMMAND while the walk is installed" {
  write_modern_mock
  write_walk_fixture

  run env PATH="$PATH" SCRIPT_PATH="$SCRIPT_PATH" \
    DOTFILES_FZF_PROC_VERSION="$FZF_PROC_VERSION" FZF_LOG="$FZF_LOG" \
    DOTFILES_FZF_MNT_ROOT="$WALK/mnt" FZF_CTRL_T_COMMAND='' \
    bash --noprofile --norc -i -c '
      . "$SCRIPT_PATH"
      printf "ctrl-t:[%s]\n" "$FZF_CTRL_T_COMMAND"
      if bind -m emacs-standard -X | grep -q _dotfiles_fzf_file_widget; then
        echo bound
      else
        echo unbound
      fi
    '
  assert_success
  assert_line 'ctrl-t:[]'
  assert_line 'unbound'
}
