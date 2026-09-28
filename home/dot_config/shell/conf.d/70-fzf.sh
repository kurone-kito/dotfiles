#!/bin/sh
# fzf (fuzzy finder) shell integration
# https://github.com/junegunn/fzf
# Sets up key bindings (Ctrl+T, Ctrl+R, Alt+C) and fuzzy completion.

command -v fzf >/dev/null 2>&1 || return 0
case "$-" in
  *i*) ;;
  *) return 0 ;;
esac

_dotfiles_fzf_proc_version="${DOTFILES_FZF_PROC_VERSION:-/proc/version}"
_dotfiles_fzf_is_wsl=false
if [ -f "$_dotfiles_fzf_proc_version" ] \
  && grep -qi microsoft "$_dotfiles_fzf_proc_version" 2>/dev/null
then
  _dotfiles_fzf_is_wsl=true
fi
unset _dotfiles_fzf_proc_version

_dotfiles_fzf_setup() {
  _fzf_version="$(fzf --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)"
  _fzf_major="${_fzf_version%%.*}"
  _fzf_minor="${_fzf_version#*.}"

  if [ "${_fzf_major:-0}" -gt 0 ] 2>/dev/null \
    || [ "${_fzf_minor:-0}" -ge 48 ] 2>/dev/null
  then
    # Modern fzf (0.48+)
    if [ -n "${ZSH_VERSION:-}" ]; then
      eval "$(fzf --zsh)"
    elif [ -n "${BASH_VERSION:-}" ]; then
      eval "$(fzf --bash)"
    fi
  else
    # Legacy fzf — source bundled scripts if available
    _fzf_dir="${FZF_DIR:-}"
    [ -z "${_fzf_dir}" ] \
      && _fzf_dir="$(dirname "$(command -v fzf)")/../share/fzf" 2>/dev/null
    if [ -d "${_fzf_dir}" ]; then
      [ -f "${_fzf_dir}/key-bindings.bash" ] \
        && [ -n "${BASH_VERSION:-}" ] \
        && . "${_fzf_dir}/key-bindings.bash"
      [ -f "${_fzf_dir}/key-bindings.zsh" ] \
        && [ -n "${ZSH_VERSION:-}" ] \
        && . "${_fzf_dir}/key-bindings.zsh"
      [ -f "${_fzf_dir}/completion.bash" ] \
        && [ -n "${BASH_VERSION:-}" ] \
        && . "${_fzf_dir}/completion.bash"
      [ -f "${_fzf_dir}/completion.zsh" ] \
        && [ -n "${ZSH_VERSION:-}" ] \
        && . "${_fzf_dir}/completion.zsh"
    fi
  fi

  unset _fzf_version _fzf_major _fzf_minor _fzf_dir
}

if [ "$_dotfiles_fzf_is_wsl" = true ]; then
  # WSL startup is latency-sensitive. Keep the loader and its bridges in the
  # shell so the first binding or completion can initialize fzf exactly once.
  _dotfiles_fzf_lazy_load() {
    if [ "${_dotfiles_fzf_loaded:-0}" = 1 ]; then
      return 0
    fi
    _dotfiles_fzf_loaded=1
    if [ -n "${ZSH_VERSION:-}" ] \
      && [ -n "${_dotfiles_fzf_zsh_original_tab:-}" ]
    then
      fzf_default_completion="$_dotfiles_fzf_zsh_original_tab"
    fi
    _dotfiles_fzf_setup
  }

  if [ -n "${BASH_VERSION:-}" ]; then
    _dotfiles_fzf_file_widget() {
      _dotfiles_fzf_lazy_load || return
      if [ "$(type -t fzf-file-widget 2>/dev/null)" = function ]; then
        fzf-file-widget "$@"
      elif [ "$(type -t __fzf_select__ 2>/dev/null)" = function ]; then
        local selected
        selected="$(__fzf_select__ "$@")"
        READLINE_LINE="${READLINE_LINE:0:READLINE_POINT}${selected}${READLINE_LINE:READLINE_POINT}"
        READLINE_POINT=$((READLINE_POINT + ${#selected}))
      fi
    }

    _dotfiles_fzf_history_widget() {
      _dotfiles_fzf_lazy_load || return
      if [ "$(type -t __fzf_history__ 2>/dev/null)" = function ]; then
        __fzf_history__ "$@"
      fi
    }

    _dotfiles_fzf_cd_widget() {
      _dotfiles_fzf_lazy_load || return
      if [ "$(type -t fzf-cd-widget 2>/dev/null)" = function ]; then
        fzf-cd-widget "$@"
      elif [ "$(type -t __fzf_cd__ 2>/dev/null)" = function ]; then
        local command_line
        command_line="$(__fzf_cd__ "$@")" || return
        eval "$command_line"
      fi
    }

    _dotfiles_fzf_completion_invoke_spec() {
      _dotfiles_fzf_spec="$1"
      _dotfiles_fzf_function="$(printf '%s\n' "$_dotfiles_fzf_spec" \
        | sed -n 's/.* -F \([^ ]*\).*/\1/p')"
      _dotfiles_fzf_command="$(printf '%s\n' "$_dotfiles_fzf_spec" \
        | sed -n 's/.* -C //p')"
      if [ -n "$_dotfiles_fzf_function" ]; then
        "$_dotfiles_fzf_function"
      elif [ -n "$_dotfiles_fzf_command" ]; then
        eval "$_dotfiles_fzf_command"
      fi
      unset _dotfiles_fzf_spec _dotfiles_fzf_function _dotfiles_fzf_command
    }

    _dotfiles_fzf_find_original_spec() {
      _dotfiles_fzf_target="$1"
      while IFS= read -r _dotfiles_fzf_spec; do
        [ -n "$_dotfiles_fzf_spec" ] || continue
        case "$_dotfiles_fzf_spec" in
          *" -D"*|*" -E"*|*" -I"*) continue ;;
        esac
        set -- $_dotfiles_fzf_spec
        shift
        while [ "$#" -gt 0 ]; do
          _dotfiles_fzf_token="$1"
          shift
          case "$_dotfiles_fzf_token" in
            -F|-C|-o|-A|-W|-P|-S|-X)
              [ "$#" -gt 0 ] && shift
              ;;
            -*) ;;
            "$_dotfiles_fzf_target")
              printf '%s\n' "$_dotfiles_fzf_spec"
              unset _dotfiles_fzf_target _dotfiles_fzf_spec _dotfiles_fzf_token
              return 0
              ;;
          esac
        done
      done <<EOF
$_dotfiles_fzf_original_completion_specs
EOF
      unset _dotfiles_fzf_target _dotfiles_fzf_spec _dotfiles_fzf_token
      return 1
    }

    _dotfiles_fzf_install_explicit_bridges() {
      while IFS= read -r _dotfiles_fzf_spec; do
        [ -n "$_dotfiles_fzf_spec" ] || continue
        case "$_dotfiles_fzf_spec" in
          *" -D"*|*" -E"*|*" -I"*) continue ;;
        esac
        set -- $_dotfiles_fzf_spec
        shift
        while [ "$#" -gt 0 ]; do
          _dotfiles_fzf_token="$1"
          shift
          case "$_dotfiles_fzf_token" in
            -F|-C|-o|-A|-W|-P|-S|-X)
              [ "$#" -gt 0 ] && shift
              ;;
            -*) ;;
            *) complete -F _dotfiles_fzf_completion "$_dotfiles_fzf_token" 2>/dev/null || true ;;
          esac
        done
      done <<EOF
$_dotfiles_fzf_original_completion_specs
EOF
      unset _dotfiles_fzf_spec _dotfiles_fzf_token
    }

    _dotfiles_fzf_completion() {
      _dotfiles_fzf_lazy_load || return
      _dotfiles_fzf_command_name="${COMP_WORDS[0]-}"
      _dotfiles_fzf_current_spec=
      if [ -n "$_dotfiles_fzf_command_name" ]; then
        _dotfiles_fzf_current_spec="$(complete -p -- \
          "$_dotfiles_fzf_command_name" 2>/dev/null || true)"
      fi
      case "$_dotfiles_fzf_current_spec" in
        *"_dotfiles_fzf_completion"*)
          _dotfiles_fzf_current_spec="$(_dotfiles_fzf_find_original_spec \
            "$_dotfiles_fzf_command_name" 2>/dev/null || true)"
          ;;
      esac
      if [ -n "$_dotfiles_fzf_current_spec" ]; then
        _dotfiles_fzf_completion_invoke_spec "$_dotfiles_fzf_current_spec"
      elif [ -n "$_dotfiles_fzf_original_default_spec" ]; then
        _dotfiles_fzf_completion_invoke_spec "$_dotfiles_fzf_original_default_spec"
      elif [ "$(type -t __fzf_default_completion 2>/dev/null)" = function ]; then
        __fzf_default_completion "$@"
      fi
      unset _dotfiles_fzf_command_name _dotfiles_fzf_current_spec
    }

    if [ "${_dotfiles_fzf_completion_capture_done:-0}" != 1 ]; then
      _dotfiles_fzf_original_default_spec="$(complete -p -D 2>/dev/null || true)"
      _dotfiles_fzf_original_completion_specs="$(complete -p 2>/dev/null || true)"
      _dotfiles_fzf_completion_capture_done=1
    fi

    if [ "${FZF_CTRL_T_COMMAND-x}" != "" ]; then
      bind -m emacs-standard -x '"\C-t": _dotfiles_fzf_file_widget'
      bind -m vi-command -x '"\C-t": _dotfiles_fzf_file_widget'
      bind -m vi-insert -x '"\C-t": _dotfiles_fzf_file_widget'
    fi
    if [ "${FZF_CTRL_R_COMMAND-x}" != "" ]; then
      bind -m emacs-standard -x '"\C-r": _dotfiles_fzf_history_widget'
      bind -m vi-command -x '"\C-r": _dotfiles_fzf_history_widget'
      bind -m vi-insert -x '"\C-r": _dotfiles_fzf_history_widget'
    fi
    if [ "${FZF_ALT_C_COMMAND-x}" != "" ]; then
      bind -m emacs-standard -x '"\ec": _dotfiles_fzf_cd_widget'
      bind -m vi-command -x '"\ec": _dotfiles_fzf_cd_widget'
      bind -m vi-insert -x '"\ec": _dotfiles_fzf_cd_widget'
    fi
    case "$_dotfiles_fzf_original_default_spec" in
      ""|*" -F "*|*" -C "*)
        complete -D -F _dotfiles_fzf_completion -o default -o bashdefault 2>/dev/null || true
        ;;
    esac
    _dotfiles_fzf_install_explicit_bridges
  elif [ -n "${ZSH_VERSION:-}" ]; then
    _dotfiles_fzf_file_widget() {
      _dotfiles_fzf_lazy_load || return
      fzf-file-widget "$@"
    }

    _dotfiles_fzf_history_widget() {
      _dotfiles_fzf_lazy_load || return
      fzf-history-widget "$@"
    }

    _dotfiles_fzf_cd_widget() {
      _dotfiles_fzf_lazy_load || return
      fzf-cd-widget "$@"
    }

    _dotfiles_fzf_completion() {
      _dotfiles_fzf_lazy_load || return
      fzf-completion "$@"
    }

    if [ "${FZF_CTRL_T_COMMAND-x}" != "" ]; then
      zle -N _dotfiles_fzf_file_widget
      bindkey -M emacs '^T' _dotfiles_fzf_file_widget
      bindkey -M vicmd '^T' _dotfiles_fzf_file_widget
      bindkey -M viins '^T' _dotfiles_fzf_file_widget
    fi
    if [ "${FZF_CTRL_R_COMMAND-x}" != "" ]; then
      zle -N _dotfiles_fzf_history_widget
      bindkey -M emacs '^R' _dotfiles_fzf_history_widget
      bindkey -M vicmd '^R' _dotfiles_fzf_history_widget
      bindkey -M viins '^R' _dotfiles_fzf_history_widget
    fi
    if [ "${FZF_ALT_C_COMMAND-x}" != "" ]; then
      zle -N _dotfiles_fzf_cd_widget
      bindkey -M emacs '\ec' _dotfiles_fzf_cd_widget
      bindkey -M vicmd '\ec' _dotfiles_fzf_cd_widget
      bindkey -M viins '\ec' _dotfiles_fzf_cd_widget
    fi
    zle -N _dotfiles_fzf_completion
    if [ -z "${_dotfiles_fzf_zsh_original_tab:-}" ]; then
      _dotfiles_fzf_zsh_original_tab="$(bindkey '^I' 2>/dev/null | sed 's/^.* //')"
      [ -n "$_dotfiles_fzf_zsh_original_tab" ] \
        && [ "$_dotfiles_fzf_zsh_original_tab" != undefined-key ] \
        || _dotfiles_fzf_zsh_original_tab=expand-or-complete
    fi
    bindkey '^I' _dotfiles_fzf_completion
  fi
else
  _dotfiles_fzf_setup
fi

unset _dotfiles_fzf_is_wsl
