#!/bin/bash
# Pre-rendered test fixture for run_onchange_after_80-register-zellij-web.sh.tmpl.
#
# Mirrors the rendered template but accepts the two `dig` values via
# environment variables so the same fixture can exercise every
# autostart mode (disabled / systemd-user / unknown / etc).
#
# This script is intentionally NOT a chezmoi template.
set -euo pipefail

exec </dev/null

linux_autostart="${LINUX_AUTOSTART:-disabled}"
macos_autostart="${MACOS_AUTOSTART:-disabled}"

dotfiles_user_systemd_available() {
  command -v systemctl >/dev/null 2>&1 \
    && systemctl --user show-environment >/dev/null 2>&1
}

register_linux_service() {
  case "$linux_autostart" in
    disabled|systemd-user) ;;
    *)
      echo "Unsupported zellij.web.linux.autostart mode: $linux_autostart" >&2
      return 1
      ;;
  esac

  case "$linux_autostart" in
    disabled)
      if ! dotfiles_user_systemd_available; then
        echo "Zellij Web user service not managed because user systemd is unavailable."
        return 0
      fi
      systemctl --user disable --now zellij-web.service >/dev/null 2>&1 || true
      echo "Zellij Web user service disabled."
      ;;
    systemd-user)
      if ! command -v systemctl >/dev/null 2>&1; then
        echo "systemctl is required for zellij.web.linux.autostart=systemd-user; install systemd or set autostart=disabled." >&2
        return 1
      fi
      if ! systemctl --user show-environment >/dev/null 2>&1; then
        echo "user systemd is not available; enable WSL systemd, run 'loginctl enable-linger', or set zellij.web.linux.autostart=disabled." >&2
        return 1
      fi
      systemctl --user daemon-reload
      systemctl --user enable zellij-web.service >/dev/null
      systemctl --user restart zellij-web.service
      if command -v loginctl >/dev/null 2>&1; then
        current_user="${USER:-$(id -un)}"
        linger="$(loginctl show-user "$current_user" -p Linger --value 2>/dev/null || true)"
        if [ "$linger" != "yes" ]; then
          echo "warn: linger not enabled; Zellij Web will not survive logout or reboot without an interactive login."
        fi
      fi
      echo "Zellij Web user service enabled."
      ;;
  esac
}

register_macos_agent() {
  if ! command -v launchctl >/dev/null 2>&1; then
    echo "launchctl not found; skipping Zellij Web LaunchAgent registration."
    return 0
  fi

  label="com.kurone-kito.zellij-web"
  plist="$HOME/Library/LaunchAgents/$label.plist"
  domain="gui/$(id -u)"

  case "$macos_autostart" in
    disabled)
      launchctl bootout "$domain" "$plist" >/dev/null 2>&1 || true
      echo "Zellij Web LaunchAgent disabled."
      ;;
    launchagent)
      if [ ! -f "$plist" ]; then
        echo "LaunchAgent not found: $plist" >&2
        return 1
      fi
      launchctl bootout "$domain" "$plist" >/dev/null 2>&1 || true
      launchctl bootstrap "$domain" "$plist"
      echo "Zellij Web LaunchAgent loaded."
      ;;
    *)
      echo "Unsupported zellij.web.macos.autostart mode: $macos_autostart" >&2
      return 1
      ;;
  esac
}

case "$(uname -s)" in
  Linux)
    register_linux_service
    ;;
  Darwin)
    register_macos_agent
    ;;
  *)
    echo "Zellij Web startup registration is not managed on this platform."
    ;;
esac
