#!/usr/bin/env pwsh
# Pre-rendered test fixture for run_once_before_20-deploy-ssh-keys.ps1.tmpl.
# Contains two hardcoded SSH key entries:
#   primary   - filename 'id_primary'
#   secondary - filename 'id_secondary'
#
# This script is intentionally NOT a chezmoi template, and the key
# content below is synthetic placeholder text (not a real key pair) --
# it exists only to exercise the encoding/newline/permission handling
# this script performs, not real SSH functionality.
$ErrorActionPreference = 'Stop'

$sshDir = Join-Path $HOME '.ssh'
New-Item -ItemType Directory -Path $sshDir -Force | Out-Null

# [System.IO.File] does not understand PS provider paths (e.g. TestDrive:\...),
# so resolve to a real filesystem path before using it with .NET I/O below.
$sshDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($sshDir)

$deployState = Join-Path $HOME '.local/bin/secret-deploy-state.ps1'
function Record-State {
  param([string]$Category, [string]$Name, [string]$Path)
  if (-not (Test-Path $deployState)) { return }
  try { & $deployState record $Category $Name $Path | Out-Null } catch { }
}

$sshKeys = [ordered]@{
  primary   = @{
    filename = 'id_primary'
    private  = "TEST-ONLY-PRIVATE-KEY-CONTENT-primary`nline two"
    public   = 'ssh-ed25519 AAAAPRIMARY primary@test'
  }
  secondary = @{
    filename = 'id_secondary'
    # A real SSH key secret, as commonly stored by a secret manager or
    # read from a PEM/OpenSSH-format file, conventionally ends with a
    # trailing newline. Model that shape here to verify it survives
    # the write untouched -- with no *additional* newline appended.
    private  = "TEST-ONLY-PRIVATE-KEY-CONTENT-secondary`n"
    public   = "ssh-ed25519 AAAASECONDARY secondary@test`n"
  }
}

foreach ($key in $sshKeys.Keys) {
  $sshKey = $sshKeys[$key]
  Write-Host "Deploying SSH key: $key ($($sshKey.filename))..."
  $privateKey = Join-Path $sshDir $sshKey.filename
  $publicKey = Join-Path $sshDir "$($sshKey.filename).pub"

  if (-not (Test-Path $privateKey)) {
    $privateKeyContent = $sshKey.private
    # PS5.1 rejects the utf8NoBOM encoding literal (PS6+ only); write the
    # BOM-less UTF-8 bytes directly instead. No trailing newline is added,
    # matching the prior -NoNewline call.
    [System.IO.File]::WriteAllText($privateKey, $privateKeyContent,
      [System.Text.UTF8Encoding]::new($false))
    # Restrict to current user only (icacls works without elevation)
    icacls $privateKey /inheritance:r /grant:r "${env:USERNAME}:(F)" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "Failed to restrict permissions on ${privateKey} (icacls exit code: $LASTEXITCODE)"
    }
    Write-Host '  Private key written.'
    Record-State -Category 'sshKey' -Name $key -Path $privateKey
  } else {
    Write-Host '  Private key already exists; skipping.'
  }

  if (-not (Test-Path $publicKey)) {
    $publicKeyContent = $sshKey.public
    # PS5.1 rejects the utf8NoBOM encoding literal (PS6+ only); write the
    # BOM-less UTF-8 bytes directly instead. No trailing newline is added,
    # matching the prior -NoNewline call.
    [System.IO.File]::WriteAllText($publicKey, $publicKeyContent,
      [System.Text.UTF8Encoding]::new($false))
    Write-Host '  Public key written.'
    Record-State -Category 'sshKey' -Name "$key.pub" -Path $publicKey
  } else {
    Write-Host '  Public key already exists; skipping.'
  }
}

Write-Host 'SSH key deployment complete.'
