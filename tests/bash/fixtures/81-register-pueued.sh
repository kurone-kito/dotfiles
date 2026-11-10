#!/bin/bash
# Pre-rendered test fixture for run_onchange_after_81-register-pueued.sh.tmpl.
#
# The body from `set -euo pipefail` onward mirrors the rendered template byte
# for byte. The only difference is the linux_autostart line, which reads
# PUEUE_LINUX_AUTOSTART so every mode can be exercised. The bats drift guard
# fails if the two bodies diverge.
#
# This script is intentionally NOT a chezmoi template.
set -euo pipefail

# See run_after_99-secret-status-summary.sh.tmpl for rationale.
exec </dev/null

linux_autostart="${PUEUE_LINUX_AUTOSTART:-systemd-user}"

dotfiles_user_systemd_available() {
  command -v systemctl >/dev/null 2>&1 \
    && systemctl --user show-environment >/dev/null 2>&1
}

register_linux_service() {
  # Validate the mode before any service manager call, so a typo fails loudly
  # on every host, with or without user systemd.
  case "$linux_autostart" in
    disabled|systemd-user) ;;
    *)
      echo "Unsupported data.pueue.linux.autostart mode: $linux_autostart" >&2
      return 1
      ;;
  esac

  case "$linux_autostart" in
    disabled)
      # Opt-out path: skip quietly when systemctl is missing or the user bus
      # does not answer, because there is nothing to disable there. A failing
      # disable is not hidden: set -e makes the script exit non-zero.
      if ! dotfiles_user_systemd_available; then
        echo "pueued user service not managed because user systemd is unavailable."
        return 0
      fi
      systemctl --user disable --now pueued.service
      echo "pueued user service disabled."
      ;;
    systemd-user)
      # Default-on path. A missing bus only warns: a host without user systemd
      # must not fail chezmoi apply. The pueued -d fallback in the wrapper
      # still covers that host.
      # chezmoi records a run_onchange script that exits 0, so these warnings
      # do not retry on the next apply. The warning names the manual command.
      if ! command -v systemctl >/dev/null 2>&1; then
        echo "warn: systemctl not found; pueued user service not registered. After installing systemd, run: systemctl --user enable --now pueued.service" >&2
        return 0
      fi
      if ! systemctl --user show-environment >/dev/null 2>&1; then
        echo "warn: user systemd is not available; pueued user service not registered. After enabling user systemd, run: systemctl --user enable --now pueued.service" >&2
        return 0
      fi
      systemctl --user daemon-reload
      systemctl --user enable pueued.service >/dev/null
      systemctl --user restart pueued.service
      if command -v loginctl >/dev/null 2>&1; then
        current_user="${USER:-$(id -un)}"
        linger="$(loginctl show-user "$current_user" -p Linger --value 2>/dev/null || true)"
        if [ "$linger" != "yes" ]; then
          echo "warn: linger not enabled; pueued will not survive logout or reboot without an interactive login." >&2
        fi
      fi
      echo "pueued user service enabled."
      ;;
  esac
}

case "$(uname -s)" in
  Linux)
    register_linux_service
    ;;
  *)
    # The macOS LaunchAgent branches are added by the launchd child (#723).
    echo "pueued registration is not managed on this platform."
    ;;
esac
