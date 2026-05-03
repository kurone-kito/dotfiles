#!/bin/sh
# Bitwarden unlock helper for interactive shells.
#
# On some terminals (observed on WSL), `bw unlock --raw` can leave the
# current TTY in a broken state so a later `chezmoi apply` overwrite
# prompt stops accepting input. Running `stty sane` manually in the same
# interactive shell fixes it, so provide a shell function that mirrors
# that sequence in-process.

bw_unlock() {
  _dotfiles_bw_unlock_sync=false

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --sync)
        _dotfiles_bw_unlock_sync=true
        shift
        ;;
      -h|--help)
        cat <<'EOF'
Usage: bw_unlock [--sync]

Unlock Bitwarden in the current shell, export BW_SESSION, and repair the
terminal state with stty sane.

Options:
  --sync   Run `bw sync` before unlocking
EOF
        unset _dotfiles_bw_unlock_sync
        return 0
        ;;
      *)
        echo "bw_unlock: unknown argument '$1'." >&2
        unset _dotfiles_bw_unlock_sync
        return 1
        ;;
    esac
  done

  if ! command -v bw >/dev/null 2>&1; then
    echo "bw_unlock: bw not found in PATH." >&2
    unset _dotfiles_bw_unlock_sync
    return 127
  fi

  if [ "$_dotfiles_bw_unlock_sync" = true ]; then
    bw sync >/dev/null || {
      _dotfiles_bw_unlock_status=$?
      unset _dotfiles_bw_unlock_sync
      return "$_dotfiles_bw_unlock_status"
    }
  fi

  _dotfiles_bw_unlock_session="$(bw unlock --raw)" || {
    _dotfiles_bw_unlock_status=$?
    unset _dotfiles_bw_unlock_sync _dotfiles_bw_unlock_session
    return "$_dotfiles_bw_unlock_status"
  }

  export BW_SESSION="$_dotfiles_bw_unlock_session"

  if command -v stty >/dev/null 2>&1; then
    stty sane >/dev/null 2>&1 || true
  fi

  printf '\033[0m\033[?25h\r\n' > /dev/tty 2>/dev/null || true

  unset _dotfiles_bw_unlock_sync _dotfiles_bw_unlock_session
}

alias bw-unlock='bw_unlock'
