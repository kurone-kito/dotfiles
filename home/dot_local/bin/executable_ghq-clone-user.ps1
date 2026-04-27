#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Clone all non-archived, non-fork repositories for a GitHub user or
  organization into the local ghq root.
.DESCRIPTION
  Skips repositories that are already cloned.
  Requires gh (GitHub CLI) and ghq.
.PARAMETER Owner
  GitHub user or organization name.
.PARAMETER Ssh
  Clone via SSH (default).
.PARAMETER Https
  Clone via HTTPS instead of SSH.
.PARAMETER Hostname
  GitHub hostname (default: github.com).
.PARAMETER Limit
  Maximum repositories to list (default: 1000).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory, Position = 0)]
  [string]$Owner,
  [switch]$Ssh,
  [switch]$Https,
  [string]$Hostname = 'github.com',
  [int]$Limit = 1000
)
$ErrorActionPreference = 'Stop'

$useSsh = -not $Https
if ($Ssh -and $Https) {
  Write-Error '--Ssh and --Https are mutually exclusive.'
  return
}

# Locate gh and ghq — check PATH first, then mise shims
function Find-Tool {
  param([string]$Name)
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  if (Get-Command mise -ErrorAction SilentlyContinue) {
    $p = mise which $Name 2>$null
    if ($p) { return $p }
  }
  return $null
}

$ghqBin = Find-Tool 'ghq'
if (-not $ghqBin) { Write-Error 'ghq not found.'; return }
$ghBin = Find-Tool 'gh'
if (-not $ghBin) { Write-Error 'gh not found.'; return }
$ghqRoot = & $ghqBin root

Write-Host "==> Cloning repos for ${Owner}@${Hostname}"

try {
  $repos = & $ghBin repo list $Owner `
    --no-archived --source --limit $Limit `
    --json nameWithOwner -q '.[].nameWithOwner' 2>$null
} catch {
  Write-Host "  error listing repos: $_"
  $repos = @()
}

foreach ($repo in ($repos -split "`n" | Where-Object { $_ })) {
  $target = Join-Path $ghqRoot (Join-Path $Hostname $repo)
  if (Test-Path (Join-Path $target '.git')) {
    Write-Host "  skip: $repo"
    continue
  }
  if (Test-Path $target) {
    Remove-Item -Path $target -Recurse -Force
  }
  Write-Host "  clone: $repo"
  try {
    if ($useSsh) {
      & $ghqBin get -p "${Hostname}/${repo}" 2>&1
    } else {
      & $ghqBin get "${Hostname}/${repo}" 2>&1
    }
  } catch {
    Write-Host "  error: $_"
  }
}

Write-Host '==> Done.'
