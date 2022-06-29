#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
Set-Location $env:USERPROFILE

$profileDir = Join-Path $env:USERPROFILE '.pwsh.profile.d'

if (-not (Test-Path $profileDir)) {
  New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
}

$profileDir `
  | Get-ChildItem -Filter '*.ps1' -Attributes !Directory `
  | ForEach-Object { . $_.FullName }
