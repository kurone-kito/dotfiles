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

# Validate hostname — reject path separators and traversal sequences
if ($Hostname -match '[/\\]' -or $Hostname -match '\.\.') {
  Write-Error "Invalid hostname '$Hostname'."
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

# Activate mise environment so git can find mise-managed tools (e.g., git-vrc)
if (Get-Command mise -ErrorAction SilentlyContinue) {
  (& mise env -s pwsh 2>$null) | Out-String | Invoke-Expression
}

$ghqRoot = & $ghqBin root

Write-Host "==> Cloning repos for ${Owner}@${Hostname}"

$hadGhHost = Test-Path Env:\GH_HOST
$prevGhHost = $env:GH_HOST
try {
  $env:GH_HOST = $Hostname
  $repos = & $ghBin repo list $Owner `
    --no-archived --source --limit $Limit `
    --json nameWithOwner -q '.[].nameWithOwner'
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to list repos for ${Owner}: $repos"
    return
  }
} catch {
  Write-Error "Failed to list repos for ${Owner}: $_"
  return
} finally {
  if ($hadGhHost) { $env:GH_HOST = $prevGhHost } else { Remove-Item Env:\GH_HOST -ErrorAction SilentlyContinue }
}

# Accept new SSH host keys on first contact (TOFU) to avoid
# "Host key verification failed" in non-interactive mode.
# Changed keys are still rejected to guard against MITM.
$hadGitSshCommand = Test-Path Env:\GIT_SSH_COMMAND
$prevGitSshCommand = $env:GIT_SSH_COMMAND
if ($useSsh) {
  if ($env:GIT_SSH_COMMAND) {
    $env:GIT_SSH_COMMAND = "$env:GIT_SSH_COMMAND -o StrictHostKeyChecking=accept-new"
  } else {
    $env:GIT_SSH_COMMAND = 'ssh -o StrictHostKeyChecking=accept-new'
  }
}
try {
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
} finally {
  if ($hadGitSshCommand) {
    $env:GIT_SSH_COMMAND = $prevGitSshCommand
  } else {
    Remove-Item Env:\GIT_SSH_COMMAND -ErrorAction SilentlyContinue
  }
}

Write-Host '==> Done.'
