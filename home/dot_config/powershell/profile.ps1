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

# zoxide must init AFTER Starship — Starship replaces $function:prompt
# entirely, which would destroy zoxide's prompt hook if loaded earlier.
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
  (& zoxide init powershell 2>$null) | Out-String | Invoke-Expression
}

# VS Code shell integration — load AFTER Starship and zoxide to avoid
# prompt handler conflicts. Only inject manually when VS Code has not
# already auto-injected (indicated by VSCODE_SHELL_INTEGRATION env var).
if ((Get-Command Test-DotfilesVSCodeTerminal -ErrorAction SilentlyContinue) -and
    (Test-DotfilesVSCodeTerminal) -and
    -not $env:VSCODE_SHELL_INTEGRATION -and
    (Get-Command code -ErrorAction SilentlyContinue)) {
  try {
    $siPath = & code --locate-shell-integration-path pwsh 2>$null
    if ($siPath -and (Test-Path $siPath)) {
      . $siPath
    }
  } catch {
    # Shell integration unavailable; continue without it
  }
}
