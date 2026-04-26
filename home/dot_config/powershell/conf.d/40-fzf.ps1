# fzf (fuzzy finder) integration via PSFzf
# https://github.com/kelleyma49/PSFzf
# Requires: fzf binary + PSFzf module (Install-Module PSFzf)

if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return }

if (Get-Module -ListAvailable PSFzf) {
  Import-Module PSFzf
  # PSReadLine chord bindings require a fully initialized PSReadLine.
  # In non-standard hosts (psmux, VS Code background terminals, etc.)
  # PSReadLine may not be ready, causing GetHistoryItems null errors.
  if (Get-Module PSReadLine) {
    try {
      Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
    } catch {
      # PSReadLine not fully initialized; skip chord bindings
    }
  }
}
