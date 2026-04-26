# PowerShell profile (all platforms)
# Sources conf.d drop-in scripts, then initializes the prompt.
# Uses nested Join-Path for PowerShell 5 compatibility.

$confDir = Join-Path (Join-Path (Join-Path $HOME '.config') 'powershell') 'conf.d'
if (Test-Path $confDir) {
  Get-ChildItem (Join-Path $confDir '*.ps1') |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }
}

# Prompt
if (Get-Command starship -ErrorAction SilentlyContinue) {
  # Probe whether PSReadLine is fully initialized (not just loaded).
  # In psmux, VS Code background terminals, and other non-standard hosts,
  # PSReadLine may be present but its internal state is null, causing
  # GetHistoryItems null-reference errors from Starship's transient prompt.
  $psReadLineReady = $false
  if (Get-Module PSReadLine) {
    try {
      [void][Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems()
      $psReadLineReady = $true
    } catch {}
  }

  # Starship checks for this function to enable transient prompt;
  # define it only when PSReadLine is confirmed working.
  if ($psReadLineReady) {
    function Invoke-Starship-TransientFunction {
      &starship module character
    }
  }

  try {
    Invoke-Expression (&starship init powershell)
  } catch {
    # Starship init may call Set-PSReadLineOption; suppress on failure
  }

  if ($psReadLineReady -and
      (Get-Command Enable-TransientPrompt -ErrorAction SilentlyContinue)) {
    try { Enable-TransientPrompt } catch {}
  }
}
