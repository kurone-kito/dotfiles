# fzf (fuzzy finder) integration via PSFzf
# https://github.com/kelleyma49/PSFzf
# Requires: fzf binary + PSFzf module (Install-Module PSFzf)

if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return }

if (Get-Module -ListAvailable PSFzf) {
  Import-Module PSFzf

  # Skip PSReadLine chord bindings in VS Code — Ctrl+r and Ctrl+t
  # are handled by VS Code's own keybindings.
  $skipChords = (
    (Get-Command Test-DotfilesVSCodeTerminal -ErrorAction SilentlyContinue) -and
    (Test-DotfilesVSCodeTerminal)
  )

  if (-not $skipChords) {
    if (Get-Command Invoke-DotfilesPSReadLineStartupAction -ErrorAction SilentlyContinue) {
      # PSReadLine chord bindings need the same startup timing workaround
      # as PSReadLine option changes inside psmux and other deferred hosts.
      Invoke-DotfilesPSReadLineStartupAction -Name 'psfzf-chords' -Action {
        try {
          Set-PsFzfOption `
            -PSReadlineChordProvider 'Ctrl+t' `
            -PSReadlineChordReverseHistory 'Ctrl+r' `
            -ErrorAction Stop
          return $true
        } catch [System.Exception] {
          return $false
        }
      } | Out-Null
    } elseif (Get-Module PSReadLine) {
      try {
        Set-PsFzfOption `
          -PSReadlineChordProvider 'Ctrl+t' `
          -PSReadlineChordReverseHistory 'Ctrl+r' `
          -ErrorAction Stop
      } catch [System.Exception] {
        # PSReadLine not fully initialized; skip chord bindings
      }
    }
  }
}
