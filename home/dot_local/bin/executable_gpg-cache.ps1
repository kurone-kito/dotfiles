#!/usr/bin/env pwsh
# Prime the gpg-agent cache for the current session with a throwaway signature.
# Discovers all signing keys from git config and profile configs, then signs
# with each via --local-user so every key's passphrase is cached.
$ErrorActionPreference = 'Stop'

function global:Get-DotfilesGpgCommand {
  return Get-Command gpg -ErrorAction SilentlyContinue
}

function global:Get-DotfilesGpgSigningKeys {
  $keys = [System.Collections.Generic.List[string]]::new()

  # 1. Default git signing key (hex fingerprints only; when
  #    gpg.format=ssh, user.signingkey is an SSH public key path,
  #    which gpg cannot sign with, so skip it silently)
  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if ($gitCmd) {
    try {
      $defaultKey = & $gitCmd.Name config user.signingkey 2>$null
      if ($defaultKey -match '^[A-Fa-f0-9]+$') { $keys.Add($defaultKey) }
    } catch [System.Exception] {
    }
  }

  # 2. Per-directory profile signing keys
  $profileDir = Join-Path (Join-Path (Join-Path $HOME '.config') 'git') 'profiles'
  if (Test-Path -LiteralPath $profileDir -PathType Container) {
    Get-ChildItem $profileDir -File | ForEach-Object {
      $match = Select-String -LiteralPath $_.FullName `
        -Pattern '^\s*signingkey\s*=\s*"?([A-Fa-f0-9]+)"?' |
        Select-Object -First 1
      if ($match) {
        $fpr = $match.Matches.Groups[1].Value
        if ($fpr -and -not $keys.Contains($fpr)) {
          $keys.Add($fpr)
        }
      }
    }
  }

  return @($keys)
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
      & gpg-connect-agent reloadagent /bye 2>$null | Out-Null
    } catch [System.Exception] {
    }
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

  $signingKeys = Get-DotfilesGpgSigningKeys
  if ($signingKeys.Count -eq 0) {
    # No signing keys configured; fall back to default key
    Write-Host 'Prompting GPG passphrase...'
    'gpg-cache' | & $gpgCommand.Name --clearsign --yes 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Write-Host 'Passphrase cached successfully (24h TTL).'
      return $true
    }
    Write-Warning 'GPG passphrase caching failed.'
    return $false
  }

  $allSuccess = $true
  foreach ($key in $signingKeys) {
    Write-Host "Prompting GPG passphrase for key ${key}..."
    'gpg-cache' | & $gpgCommand.Name --local-user $key `
      --clearsign --yes 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "  GPG passphrase caching failed for key ${key}."
      $allSuccess = $false
    } else {
      Write-Host "  Passphrase cached successfully (24h TTL)."
    }
  }

  return $allSuccess
}

if ($env:DOTFILES_TEST_GPG_CACHE_SKIP_MAIN -ne '1') {
  if (Invoke-DotfilesGpgCachePassphrase) {
    exit 0
  }

  exit 1
}
