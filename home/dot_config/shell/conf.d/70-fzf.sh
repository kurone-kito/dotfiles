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
    # fzf's own integration replaces complete -D. Restore the bridge after
    # every trigger, including key bindings, which never re-enter completion.
    if [ -n "${BASH_VERSION:-}" ] \
      && [ "$(type -t _dotfiles_fzf_restore_default_completion 2>/dev/null)" = function ]
    then
      _dotfiles_fzf_restore_default_completion
    fi
  }

  if [ -n "${BASH_VERSION:-}" ]; then
    if [ "${BASH_VERSION%%.*}" -lt 4 ] 2>/dev/null; then
      # Bash 3.2 has no bind -x or READLINE_LINE/READLINE_POINT support.
      _dotfiles_fzf_lazy_load
    else
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

    # Bash complete -X: a leading ! negates, and & is the current word.
    _dotfiles_fzf_x_removes() {
      local _dotfiles_fzf_word="$1"
      local _dotfiles_fzf_pat="$2"
      local _dotfiles_fzf_cur="$3"
      local _dotfiles_fzf_neg=0
      local _dotfiles_fzf_matched=0
      local _dotfiles_fzf_old_ifs="$IFS"
      case "$_dotfiles_fzf_pat" in
        '!'*)
          _dotfiles_fzf_neg=1
          _dotfiles_fzf_pat="${_dotfiles_fzf_pat#!}"
          ;;
      esac
      [ -n "$_dotfiles_fzf_pat" ] || return 1
      _dotfiles_fzf_pat="${_dotfiles_fzf_pat//&/$_dotfiles_fzf_cur}"
      [ -n "$_dotfiles_fzf_pat" ] || return 1
      IFS=
      case "$_dotfiles_fzf_word" in
        $_dotfiles_fzf_pat) _dotfiles_fzf_matched=1 ;;
      esac
      IFS="$_dotfiles_fzf_old_ifs"
      if [ "$_dotfiles_fzf_neg" = 1 ]; then
        [ "$_dotfiles_fzf_matched" = 0 ]
      else
        [ "$_dotfiles_fzf_matched" = 1 ]
      fi
    }

    _dotfiles_fzf_restore_default_completion() {
      if [ -z "${_dotfiles_fzf_original_default_spec-}" ]; then
        complete -D -F _dotfiles_fzf_completion -o default -o bashdefault 2>/dev/null || true
      else
        complete -D -F _dotfiles_fzf_completion 2>/dev/null || true
      fi
    }

    _dotfiles_fzf_completion_invoke_spec() {
      local _dotfiles_fzf_spec="$1"
      shift
      local _dotfiles_fzf_function=
      local _dotfiles_fzf_command=
      local _dotfiles_fzf_current=
      local _dotfiles_fzf_token
      local _dotfiles_fzf_option
      local _dotfiles_fzf_compgen_args=
      local _dotfiles_fzf_matches=
      local _dotfiles_fzf_source_matches=
      local _dotfiles_fzf_completion_args=
      local _dotfiles_fzf_completion_env=
      local _dotfiles_fzf_exclude=
      local _dotfiles_fzf_prefix=
      local _dotfiles_fzf_suffix=
      local _dotfiles_fzf_processed_matches=
      local _dotfiles_fzf_status=0
      local _dotfiles_fzf_source_status=0
      local _dotfiles_fzf_completion_command="${1-}"
      local _dotfiles_fzf_completion_current="${2-}"
      local _dotfiles_fzf_completion_previous="${3-}"
      eval "set -- ${_dotfiles_fzf_spec#complete }"
      while [ "$#" -gt 0 ]; do
        _dotfiles_fzf_token="$1"
        shift
        case "$_dotfiles_fzf_token" in
          -D|-E|-I) ;;
          -o)
            [ "$#" -gt 0 ] || continue
            _dotfiles_fzf_option="$1"
            shift
            compopt -o "$_dotfiles_fzf_option" 2>/dev/null || true
            _dotfiles_fzf_compgen_args="$_dotfiles_fzf_compgen_args \
              $(printf '%q %q' -o "$_dotfiles_fzf_option")"
            ;;
          -F)
            [ "$#" -gt 0 ] || continue
            _dotfiles_fzf_function="$1"
            shift
            ;;
          -C)
            [ "$#" -gt 0 ] || continue
            _dotfiles_fzf_command="$1"
            shift
            ;;
          -A|-G|-W)
            [ "$#" -gt 0 ] || continue
            _dotfiles_fzf_compgen_args="$_dotfiles_fzf_compgen_args \
              $(printf '%q %q' "$_dotfiles_fzf_token" "$1")"
            shift
            ;;
          -X)
            [ "$#" -gt 0 ] || continue
            _dotfiles_fzf_exclude="$1"
            shift
            ;;
          -P)
            [ "$#" -gt 0 ] || continue
            _dotfiles_fzf_prefix="$1"
            shift
            ;;
          -S)
            [ "$#" -gt 0 ] || continue
            _dotfiles_fzf_suffix="$1"
            shift
            ;;
          -*) _dotfiles_fzf_compgen_args="$_dotfiles_fzf_compgen_args $_dotfiles_fzf_token" ;;
        esac
      done
      _dotfiles_fzf_current="${COMP_WORDS[COMP_CWORD]-}"
      eval 'COMPREPLY=()'
      if [ -n "$_dotfiles_fzf_function" ]; then
        "$_dotfiles_fzf_function" \
          "$_dotfiles_fzf_completion_command" \
          "$_dotfiles_fzf_completion_current" \
          "$_dotfiles_fzf_completion_previous"
        _dotfiles_fzf_source_status=$?
        _dotfiles_fzf_status=$_dotfiles_fzf_source_status
        if [ "${#COMPREPLY[@]}" -gt 0 ]; then
          _dotfiles_fzf_matches="$(printf '%s\n' "${COMPREPLY[@]}")"
        fi
      fi
      if [ -n "$_dotfiles_fzf_command" ]; then
        _dotfiles_fzf_completion_args="$(printf ' %q' \
          "$_dotfiles_fzf_completion_command" \
          "$_dotfiles_fzf_completion_current" \
          "$_dotfiles_fzf_completion_previous")"
        _dotfiles_fzf_completion_env="$(printf \
          'COMP_LINE=%q COMP_POINT=%q COMP_TYPE=%q COMP_KEY=%q' \
          "${COMP_LINE-}" "${COMP_POINT-}" "${COMP_TYPE-}" "${COMP_KEY-}")"
        _dotfiles_fzf_source_matches="$(eval \
          "$_dotfiles_fzf_completion_env \
          $_dotfiles_fzf_command$_dotfiles_fzf_completion_args")"
        _dotfiles_fzf_source_status=$?
        [ "$_dotfiles_fzf_status" -ne 0 ] \
          || _dotfiles_fzf_status=$_dotfiles_fzf_source_status
        if [ -n "$_dotfiles_fzf_source_matches" ]; then
          [ -n "$_dotfiles_fzf_matches" ] \
            && _dotfiles_fzf_matches="$_dotfiles_fzf_matches
$_dotfiles_fzf_source_matches" \
            || _dotfiles_fzf_matches="$_dotfiles_fzf_source_matches"
        fi
      fi
      if [ -n "$_dotfiles_fzf_compgen_args" ]; then
        _dotfiles_fzf_source_matches="$(eval "compgen$_dotfiles_fzf_compgen_args \
          -- \"\$_dotfiles_fzf_current\"")"
        _dotfiles_fzf_source_status=$?
        [ "$_dotfiles_fzf_status" -ne 0 ] \
          || _dotfiles_fzf_status=$_dotfiles_fzf_source_status
        if [ -n "$_dotfiles_fzf_source_matches" ]; then
          [ -n "$_dotfiles_fzf_matches" ] \
            && _dotfiles_fzf_matches="$_dotfiles_fzf_matches
$_dotfiles_fzf_source_matches" \
            || _dotfiles_fzf_matches="$_dotfiles_fzf_source_matches"
        fi
      fi
      if [ -n "$_dotfiles_fzf_matches" ]; then
        _dotfiles_fzf_processed_matches=
        while IFS= read -r _dotfiles_fzf_token; do
          if [ -n "$_dotfiles_fzf_exclude" ] \
            && _dotfiles_fzf_x_removes \
              "$_dotfiles_fzf_token" \
              "$_dotfiles_fzf_exclude" \
              "$_dotfiles_fzf_current"
          then
            continue
          fi
          _dotfiles_fzf_token="$_dotfiles_fzf_prefix$_dotfiles_fzf_token$_dotfiles_fzf_suffix"
          [ -n "$_dotfiles_fzf_processed_matches" ] \
            && _dotfiles_fzf_processed_matches="$_dotfiles_fzf_processed_matches
$_dotfiles_fzf_token" \
            || _dotfiles_fzf_processed_matches="$_dotfiles_fzf_token"
        done <<EOF
$_dotfiles_fzf_matches
EOF
        eval 'COMPREPLY=()'
        if [ -n "$_dotfiles_fzf_processed_matches" ]; then
          readarray -t COMPREPLY <<EOF
$_dotfiles_fzf_processed_matches
EOF
        fi
      fi
      return "$_dotfiles_fzf_status"
    }

    _dotfiles_fzf_find_original_spec() {
      local _dotfiles_fzf_target="$1"
      local _dotfiles_fzf_spec
      local _dotfiles_fzf_token
      while IFS= read -r _dotfiles_fzf_spec; do
        [ -n "$_dotfiles_fzf_spec" ] || continue
        eval "set -- ${_dotfiles_fzf_spec#complete }"
        while [ "$#" -gt 0 ]; do
          _dotfiles_fzf_token="$1"
          shift
          case "$_dotfiles_fzf_token" in
            -F|-C|-A|-G|-W|-X|-P|-S|-o)
              [ "$#" -gt 0 ] && shift
              ;;
            -D|-E|-I|-*) ;;
            --)
              while [ "$#" -gt 0 ]; do
                [ "$1" = "$_dotfiles_fzf_target" ] \
                  && { printf '%s\n' "$_dotfiles_fzf_spec"; return 0; }
                shift
              done
              ;;
            "$_dotfiles_fzf_target")
              printf '%s\n' "$_dotfiles_fzf_spec"
              return 0
              ;;
          esac
        done
      done <<EOF
$_dotfiles_fzf_original_completion_specs
EOF
      return 1
    }

    _dotfiles_fzf_install_explicit_bridges() {
      local _dotfiles_fzf_spec
      local _dotfiles_fzf_token
      local _dotfiles_fzf_scope
      while IFS= read -r _dotfiles_fzf_spec; do
        [ -n "$_dotfiles_fzf_spec" ] || continue
        _dotfiles_fzf_scope=0
        eval "set -- ${_dotfiles_fzf_spec#complete }"
        while [ "$#" -gt 0 ]; do
          _dotfiles_fzf_token="$1"
          shift
          case "$_dotfiles_fzf_token" in
            -D|-E|-I) _dotfiles_fzf_scope=1 ;;
            -F|-C|-A|-G|-W|-X|-P|-S|-o)
              [ "$#" -gt 0 ] && shift
              ;;
            -*) ;;
            *)
              [ "$_dotfiles_fzf_scope" = 0 ] \
                && complete -F _dotfiles_fzf_completion \
                  "$_dotfiles_fzf_token" 2>/dev/null || true
              ;;
          esac
        done
      done <<EOF
$_dotfiles_fzf_original_completion_specs
EOF
    }

    _dotfiles_fzf_completion() {
      local _dotfiles_fzf_status=0
      local _dotfiles_fzf_fzf_status=0
      local _dotfiles_fzf_current_spec=
      local _dotfiles_fzf_original_reply=
      local _dotfiles_fzf_fzf_reply=
      local _dotfiles_fzf_combined_reply=
      _dotfiles_fzf_command_name="${COMP_WORDS[0]-}"
      _dotfiles_fzf_original_spec=
      if [ -n "$_dotfiles_fzf_command_name" ]; then
        _dotfiles_fzf_original_spec="$(_dotfiles_fzf_find_original_spec \
          "$_dotfiles_fzf_command_name" 2>/dev/null || true)"
      fi
      [ -n "$_dotfiles_fzf_original_spec" ] \
        || _dotfiles_fzf_original_spec="$_dotfiles_fzf_original_default_spec"
      _dotfiles_fzf_lazy_load || return
      _dotfiles_fzf_restore_default_completion
      if [ -n "$_dotfiles_fzf_command_name" ]; then
        _dotfiles_fzf_current_spec="$(complete -p -- \
          "$_dotfiles_fzf_command_name" 2>/dev/null || true)"
        case "$_dotfiles_fzf_current_spec" in
          *"_dotfiles_fzf_completion"*) ;;
          *)
            [ -n "$_dotfiles_fzf_current_spec" ] \
              && _dotfiles_fzf_original_spec="$_dotfiles_fzf_current_spec"
            ;;
        esac
      fi
      if [ -n "$_dotfiles_fzf_original_spec" ]; then
        _dotfiles_fzf_completion_invoke_spec "$_dotfiles_fzf_original_spec" "$@"
        _dotfiles_fzf_status=$?
        if [ "${#COMPREPLY[@]}" -gt 0 ]; then
          _dotfiles_fzf_original_reply="$(printf '%s\n' "${COMPREPLY[@]}")"
        fi
      fi
      if [ "$(type -t __fzf_default_completion 2>/dev/null)" = function ]; then
        eval 'COMPREPLY=()'
        __fzf_default_completion "$@"
        _dotfiles_fzf_fzf_status=$?
        [ "$_dotfiles_fzf_status" -ne 0 ] \
          || _dotfiles_fzf_status=$_dotfiles_fzf_fzf_status
        if [ "${#COMPREPLY[@]}" -gt 0 ]; then
          _dotfiles_fzf_fzf_reply="$(printf '%s\n' "${COMPREPLY[@]}")"
        fi
      fi
      if [ -n "$_dotfiles_fzf_original_reply" ]; then
        _dotfiles_fzf_combined_reply="$_dotfiles_fzf_original_reply"
      fi
      if [ -n "$_dotfiles_fzf_fzf_reply" ]; then
        [ -n "$_dotfiles_fzf_combined_reply" ] \
          && _dotfiles_fzf_combined_reply="$_dotfiles_fzf_combined_reply
$_dotfiles_fzf_fzf_reply" \
          || _dotfiles_fzf_combined_reply="$_dotfiles_fzf_fzf_reply"
      fi
      eval 'COMPREPLY=()'
      if [ -n "$_dotfiles_fzf_combined_reply" ]; then
        readarray -t COMPREPLY <<EOF
$_dotfiles_fzf_combined_reply
EOF
      fi
      unset _dotfiles_fzf_command_name _dotfiles_fzf_original_spec \
        _dotfiles_fzf_current_spec _dotfiles_fzf_original_reply \
        _dotfiles_fzf_fzf_reply _dotfiles_fzf_combined_reply
      return "$_dotfiles_fzf_status"
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
    _dotfiles_fzf_restore_default_completion
      _dotfiles_fzf_install_explicit_bridges
    fi
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
      if [ "$(whence -w fzf-completion 2>/dev/null)" = "fzf-completion: function" ]; then
        fzf-completion "$@"
      elif [ -n "${_dotfiles_fzf_zsh_original_tab:-}" ]; then
        bindkey '^I' "$_dotfiles_fzf_zsh_original_tab"
        if [ -n "${ZLE_STATE:-}" ]; then
          zle "$_dotfiles_fzf_zsh_original_tab"
        else
          "$_dotfiles_fzf_zsh_original_tab" "$@"
        fi
      fi
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
