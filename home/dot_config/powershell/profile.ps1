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
# When 31-mise-executables.ps1 resolved starship, launch that executable
# directly: its init module comes from one launch, and the transient hook
# does not start the mise shim. Without a resolution, PATH lookup is used.
$starshipExe = $null
if ($null -ne $__miseExecutables -and $__miseExecutables.ContainsKey('starship')) {
  $starshipExe = $__miseExecutables['starship']
}
if ($starshipExe -or (Get-Command starship -ErrorAction SilentlyContinue)) {
  # Probe whether PSReadLine is fully initialized (not just loaded).
  # In psmux, VS Code background terminals, and other non-standard hosts,
  # PSReadLine may be present but its internal state is null, causing
  # GetHistoryItems null-reference errors from Starship's transient prompt.
  $psReadLineReady = $false
  if (Get-Command Test-DotfilesPSReadLineReady -ErrorAction SilentlyContinue) {
    $psReadLineReady = Test-DotfilesPSReadLineReady
  } elseif (Get-Module PSReadLine) {
    try {
      [void][Microsoft.PowerShell.PSConsoleReadLine]::GetHistoryItems()
      $psReadLineReady = $true
    } catch [System.Exception] {
      $psReadLineReady = $false
    }
  }

  # Starship checks for this function to enable transient prompt;
  # define it only when PSReadLine is confirmed working.
  if ($psReadLineReady) {
    function Invoke-Starship-TransientFunction {
      if ($starshipExe) {
        & $starshipExe module character
      } else {
        &starship module character
      }
    }
  }

  try {
    if ($starshipExe) {
      Invoke-Expression ((& $starshipExe init powershell --print-full-init) | Out-String)
    } else {
      Invoke-Expression (&starship init powershell)
    }
  } catch {
    # Starship init may call Set-PSReadLineOption; suppress on failure
  }

  if ($psReadLineReady -and
      (Get-Command Enable-TransientPrompt -ErrorAction SilentlyContinue)) {
    try { Enable-TransientPrompt } catch {}
  }
}

# zoxide must init AFTER Starship — Starship replaces $function:prompt
# entirely, which would destroy zoxide's prompt hook if loaded earlier.
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
  (& zoxide init powershell 2>$null) | Out-String | Invoke-Expression
}
