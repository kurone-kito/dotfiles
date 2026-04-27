#!/usr/bin/env pwsh
# Pre-rendered test fixture for generate-authorized-keys.ps1.tmpl.
# Contains two hardcoded public key names:
#   primary.pub   - included when present
#   secondary.pub - included when present
$ErrorActionPreference = 'Stop'

$homeDir = if ($env:AUTHORIZED_KEYS_HOME) {
  $env:AUTHORIZED_KEYS_HOME
} else {
  $HOME
}

$sshDir = Join-Path $homeDir '.ssh'
$authorized = Join-Path $sshDir 'authorized_keys'

New-Item -ItemType Directory -Path $sshDir -Force | Out-Null

$lines = @()
foreach ($name in @('primary.pub', 'secondary.pub')) {
  $pubFile = Join-Path $sshDir $name
  if (Test-Path $pubFile) {
    $lines += (Get-Content -Path $pubFile -Raw).TrimEnd()
  }
}

if ($lines.Count -eq 0) {
  Write-Warning 'No public keys were found; authorized_keys will be empty.'
}

$lines -join "`n" | Set-Content -Path $authorized -Encoding utf8NoBOM -NoNewline

icacls $authorized /inheritance:r `
  /grant:r "${env:USERNAME}:(F)" `
  /grant "*S-1-5-18:(R)" 2>&1 | Out-Null

Write-Host 'authorized_keys generated.'
