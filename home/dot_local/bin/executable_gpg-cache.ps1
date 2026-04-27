#!/usr/bin/env pwsh
# Prime the gpg-agent cache for the current session with a throwaway signature.
$ErrorActionPreference = 'Stop'

function global:Get-DotfilesGpgCommand {
  return Get-Command gpg -ErrorAction SilentlyContinue
}

function global:Update-DotfilesGpgSession {
  $ttyCommand = Get-Command tty -ErrorAction SilentlyContinue
  if ($ttyCommand) {
    try {
      $ttyPath = (& $ttyCommand.Name 2>$null | Out-String).Trim()
      if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ttyPath)) {
        $env:GPG_TTY = $ttyPath
      }
    } catch [System.Exception] {
    }
  }

  if (Get-Command gpg-connect-agent -ErrorAction SilentlyContinue) {
    try {
      & gpg-connect-agent updatestartuptty /bye 2>$null | Out-Null
    } catch [System.Exception] {
    }
  }
}

function global:Invoke-DotfilesGpgCachePassphrase {
  $gpgCommand = Get-DotfilesGpgCommand
  if (-not $gpgCommand) {
    Write-Warning 'gpg not found in PATH'
    return $false
  }

  Update-DotfilesGpgSession
  Write-Host 'Prompting GPG passphrase...'
  'gpg-cache' | & $gpgCommand.Name --clearsign --yes 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Host 'Passphrase cached successfully (24h TTL).'
    return $true
  }

  Write-Warning 'GPG passphrase caching failed.'
  return $false
}

if ($env:DOTFILES_TEST_GPG_CACHE_SKIP_MAIN -ne '1') {
  if (Invoke-DotfilesGpgCachePassphrase) {
    exit 0
  }

  exit 1
}
