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
$beginMarker = '# >>> chezmoi managed keys >>>'
$endMarker = '# <<< chezmoi managed keys <<<'

New-Item -ItemType Directory -Path $sshDir -Force | Out-Null

$managedLines = @()
foreach ($name in @('primary.pub', 'secondary.pub')) {
  $pubFile = Join-Path $sshDir $name
  if (Test-Path $pubFile) {
    $managedLines += (Get-Content -Path $pubFile -Raw).TrimEnd()
    Write-Host "  Added $name"
  } else {
    Write-Host "  Skipped $name (not found)"
  }
}

if ($managedLines.Count -eq 0) {
  Write-Warning 'No public keys were found; managed block will be empty.'
}

$existingLines = @()
if (Test-Path $authorized) {
  $existingLines = @(Get-Content -Path $authorized)
}

$beginCount = ($existingLines | Where-Object { $_ -eq $beginMarker }).Count
$endCount = ($existingLines | Where-Object { $_ -eq $endMarker }).Count
$markersPresent = ($beginCount -gt 0) -or ($endCount -gt 0)
$blockShapeOk = ($beginCount -eq 1) -and ($endCount -eq 1)

$beginIndex = [array]::LastIndexOf($existingLines, $beginMarker)
$endIndex = -1
if ($beginIndex -ge 0) {
  $endIndex = [array]::IndexOf($existingLines, $endMarker, $beginIndex + 1)
}
$hasValidBlock = ($beginIndex -ge 0) -and ($endIndex -gt $beginIndex)

if ($markersPresent -and -not $blockShapeOk) {
  Write-Warning "Malformed managed-key markers found in ${authorized}; remove the stale/duplicate markers manually. A valid block will be updated in place if one can be found, otherwise a fresh block is appended."
}

$outLines = @()
if ($hasValidBlock) {
  if ($beginIndex -gt 0) {
    $outLines += $existingLines[0..($beginIndex - 1)]
  }
  $outLines += $beginMarker
  $outLines += $managedLines
  $outLines += $endMarker
  if ($endIndex + 1 -lt $existingLines.Count) {
    $outLines += $existingLines[($endIndex + 1)..($existingLines.Count - 1)]
  }
} else {
  $outLines += $existingLines | Where-Object { $managedLines -notcontains $_ }
  $outLines += $beginMarker
  $outLines += $managedLines
  $outLines += $endMarker
}

($outLines -join "`n") + "`n" | Set-Content -Path $authorized -Encoding utf8NoBOM -NoNewline

icacls $authorized /inheritance:r `
  /grant:r "${env:USERNAME}:(F)" `
  /grant "*S-1-5-18:(R)" 2>&1 | Out-Null

Write-Host 'authorized_keys generated.'
