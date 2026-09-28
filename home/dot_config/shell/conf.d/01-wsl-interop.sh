#!/bin/sh
# Diagnose and repair a missing WSLInterop binfmt_misc registration.
#
# The source-time check is deliberately cheap on healthy systems: only shell
# builtins and binfmt_misc path tests run until the registration is missing.

_dotfiles_wsl_interop_binfmt_dir="${DOTFILES_WSL_INTEROP_BINFMT_DIR:-/proc/sys/fs/binfmt_misc}"
_dotfiles_wsl_interop_proc_version="${DOTFILES_WSL_INTEROP_PROC_VERSION:-/proc/version}"
_dotfiles_wsl_interop_dropin="${DOTFILES_WSL_INTEROP_DROPIN:-/run/systemd/generator/systemd-binfmt.service.d/override.conf}"

_dotfiles_wsl_interop_entry_is_enabled() {
  _dotfiles_wsl_interop_entry_state=
  if [ -e "$1" ] \
    && IFS= read -r _dotfiles_wsl_interop_entry_state <"$1" \
    && [ "$_dotfiles_wsl_interop_entry_state" = enabled ]
  then
    unset _dotfiles_wsl_interop_entry_state
    return 0
  fi
  unset _dotfiles_wsl_interop_entry_state
  return 1
}

_dotfiles_wsl_interop_status_is_enabled() {
  _dotfiles_wsl_interop_status_state=
  if [ -e "$1" ] \
    && IFS= read -r _dotfiles_wsl_interop_status_state <"$1" \
    && [ "$_dotfiles_wsl_interop_status_state" = enabled ]
  then
    unset _dotfiles_wsl_interop_status_state
    return 0
  fi
  unset _dotfiles_wsl_interop_status_state
  return 1
}

if [ -f "$_dotfiles_wsl_interop_binfmt_dir/status" ]; then
  _dotfiles_wsl_interop_warning_needed=false
  if ! _dotfiles_wsl_interop_status_is_enabled \
    "$_dotfiles_wsl_interop_binfmt_dir/status"
  then
    _dotfiles_wsl_interop_warning_needed=true
  elif ! _dotfiles_wsl_interop_entry_is_enabled \
      "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop" \
    && ! _dotfiles_wsl_interop_entry_is_enabled \
      "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop-late"
  then
    _dotfiles_wsl_interop_warning_needed=true
  fi

  if case "$-" in
    *i*) true ;;
    *) false ;;
  esac
  then
    if [ "${DOTFILES_WSL_INTEROP_WARN:-1}" != 0 ] \
      && [ "$_dotfiles_wsl_interop_warning_needed" = true ] \
      && grep -qi microsoft "$_dotfiles_wsl_interop_proc_version" 2>/dev/null
    then
      printf '%s\n' \
        'wsl_interop_repair: WSLInterop registration is missing, disabled, or globally disabled; run wsl_interop_repair to restore it.' >&2
    fi
  fi
fi

unset _dotfiles_wsl_interop_warning_needed
unset _dotfiles_wsl_interop_binfmt_dir
unset _dotfiles_wsl_interop_proc_version
unset _dotfiles_wsl_interop_dropin

wsl_interop_repair() (
  _dotfiles_wsl_interop_binfmt_dir="${DOTFILES_WSL_INTEROP_BINFMT_DIR:-/proc/sys/fs/binfmt_misc}"
  _dotfiles_wsl_interop_proc_version="${DOTFILES_WSL_INTEROP_PROC_VERSION:-/proc/version}"
  _dotfiles_wsl_interop_dropin="${DOTFILES_WSL_INTEROP_DROPIN:-/run/systemd/generator/systemd-binfmt.service.d/override.conf}"
  _dotfiles_wsl_interop_register="$_dotfiles_wsl_interop_binfmt_dir/register"
  _dotfiles_wsl_interop_status=1
  _dotfiles_wsl_interop_is_wsl=false
  _dotfiles_wsl_interop_is_ready=false

  if _dotfiles_wsl_interop_status_is_enabled \
      "$_dotfiles_wsl_interop_binfmt_dir/status" \
    && { _dotfiles_wsl_interop_entry_is_enabled \
        "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop" \
      || _dotfiles_wsl_interop_entry_is_enabled \
        "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop-late"; }
  then
    _dotfiles_wsl_interop_is_ready=true
  fi

  if [ "$_dotfiles_wsl_interop_is_ready" = true ]; then
    printf '%s\n' 'wsl_interop_repair: WSLInterop is already registered.' >&2
    _dotfiles_wsl_interop_status=0
  else
    if [ -f "$_dotfiles_wsl_interop_proc_version" ] \
      && grep -qi microsoft "$_dotfiles_wsl_interop_proc_version" 2>/dev/null
    then
      _dotfiles_wsl_interop_is_wsl=true
    fi

    if [ "$_dotfiles_wsl_interop_is_wsl" != true ]; then
      printf '%s\n' 'wsl_interop_repair: this is not a WSL host.' >&2
    elif [ ! -f "$_dotfiles_wsl_interop_binfmt_dir/status" ]; then
      printf '%s\n' \
        'wsl_interop_repair: binfmt_misc is not mounted; cannot register WSLInterop.' >&2
    else
      if ! _dotfiles_wsl_interop_status_is_enabled \
        "$_dotfiles_wsl_interop_binfmt_dir/status"
      then
        printf '%s\n' '1' \
          | sudo tee "$_dotfiles_wsl_interop_binfmt_dir/status" >/dev/null
      fi

      if ! _dotfiles_wsl_interop_status_is_enabled \
        "$_dotfiles_wsl_interop_binfmt_dir/status"
      then
        printf '%s\n' 'wsl_interop_repair: binfmt_misc remains disabled.' >&2
      else
        if [ -e "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop" ] \
          && ! _dotfiles_wsl_interop_entry_is_enabled \
            "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop"
        then
          printf '%s\n' '1' \
            | sudo tee "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop" >/dev/null
        fi
        if [ -e "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop-late" ] \
          && ! _dotfiles_wsl_interop_entry_is_enabled \
            "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop-late"
        then
          printf '%s\n' '1' \
            | sudo tee "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop-late" >/dev/null
        fi

        if _dotfiles_wsl_interop_entry_is_enabled \
            "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop" \
          || _dotfiles_wsl_interop_entry_is_enabled \
            "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop-late"
        then
          _dotfiles_wsl_interop_status=0
        fi

        if [ "$_dotfiles_wsl_interop_status" -ne 0 ] \
          && [ -f "$_dotfiles_wsl_interop_dropin" ]
        then
          sudo systemctl restart systemd-binfmt.service >/dev/null 2>&1 || true
          if _dotfiles_wsl_interop_entry_is_enabled \
              "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop" \
            || _dotfiles_wsl_interop_entry_is_enabled \
              "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop-late"
          then
            _dotfiles_wsl_interop_status=0
          fi
        fi

        if [ "$_dotfiles_wsl_interop_status" -ne 0 ] \
          && [ ! -e "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop" ] \
          && [ ! -e "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop-late" ]
        then
          if [ ! -e "$_dotfiles_wsl_interop_register" ]; then
            printf '%s\n' \
              'wsl_interop_repair: binfmt_misc is not mounted; cannot register WSLInterop.' >&2
          else
            printf '%s\n' ':WSLInterop:M::MZ::/init:P' \
              | sudo tee "$_dotfiles_wsl_interop_register" >/dev/null
            if _dotfiles_wsl_interop_entry_is_enabled \
                "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop" \
              || _dotfiles_wsl_interop_entry_is_enabled \
                "$_dotfiles_wsl_interop_binfmt_dir/WSLInterop-late"
            then
              _dotfiles_wsl_interop_status=0
            fi
          fi
        fi
      fi

      if [ "$_dotfiles_wsl_interop_status" -eq 0 ]; then
        printf '%s\n' 'wsl_interop_repair: WSLInterop registration restored.' >&2
      else
        printf '%s\n' 'wsl_interop_repair: WSLInterop registration is still missing.' >&2
      fi
    fi
  fi

  _dotfiles_wsl_interop_return=$_dotfiles_wsl_interop_status
  unset _dotfiles_wsl_interop_binfmt_dir
  unset _dotfiles_wsl_interop_proc_version
  unset _dotfiles_wsl_interop_dropin
  unset _dotfiles_wsl_interop_register
  unset _dotfiles_wsl_interop_status
  unset _dotfiles_wsl_interop_is_wsl
  unset _dotfiles_wsl_interop_is_ready
  return "$_dotfiles_wsl_interop_return"
)
