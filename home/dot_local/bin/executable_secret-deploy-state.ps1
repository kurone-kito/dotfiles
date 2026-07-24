#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Maintain ~/.config/chezmoi/secret-deploy-state.json — a small registry
  of SHA-256 fingerprints for files written by chezmoi secret deploy
  scripts.
.DESCRIPTION
  Used by `secret-status.ps1` to detect content drift (manual edits to
  a deployed secret file after the fact). The fingerprint is sensitive,
  so the state file is created with restricted ACL via icacls (Windows)
  or mode 600 (Unix).

  `record` is best-effort: a hashing or write failure logs a warning
  and exits 0 so the calling deploy script is not aborted.
.PARAMETER Subcommand
  One of: record, path, -h, --help.
.EXAMPLE
  secret-deploy-state.ps1 record secretFile api 'C:\Users\me\.secret\api.txt'
.EXAMPLE
  secret-deploy-state.ps1 path
#>
param(
  [Parameter(Position = 0)] [string] $Subcommand,
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)] [string[]] $Args
)

$ErrorActionPreference = 'Stop'

function Get-StatePath {
  if ($env:SECRET_DEPLOY_STATE) { return $env:SECRET_DEPLOY_STATE }
  $h = if ($env:HOME) { $env:HOME } else { $HOME }
  return (Join-Path $h '.config/chezmoi/secret-deploy-state.json')
}

function Show-Usage {
  @'
Maintain ~/.config/chezmoi/secret-deploy-state.json.

Usage:
  secret-deploy-state.ps1 record <category> <name> <absolute-path>
  secret-deploy-state.ps1 path
  secret-deploy-state.ps1 -h | --help
'@ | Write-Host
}

function Write-Warn([string]$Message) {
  [Console]::Error.WriteLine("secret-deploy-state: $Message")
}

function Get-FileMode {
  param([string]$Path)
  if ($IsWindows -ne $false) { return '' }
  try {
    $r = & stat -c '%a' $Path 2>$null
    if (-not $r) { $r = & stat -f '%A' $Path 2>$null }
    return ($r | Out-String).Trim()
  } catch { return '' }
}

function Set-RestrictedAcl {
  param([string]$Path)
  if ($IsWindows -ne $false -and $env:USERNAME) {
    & icacls $Path /inheritance:r /grant:r "${env:USERNAME}:(R,W)" 2>&1 | Out-Null
  } elseif ($IsWindows -eq $false) {
    & chmod 600 $Path 2>$null | Out-Null
  }
}

function Invoke-Record {
  param([string[]]$Rest)
  if ($Rest.Count -lt 3) {
    Write-Warn 'record requires <category> <name> <absolute-path>'
    return 2
  }
  $category = $Rest[0]; $name = $Rest[1]; $path = $Rest[2]

  if (-not [System.IO.Path]::IsPathRooted($path)) {
    Write-Warn "record: path must be absolute ($path)"
    return 0
  }
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    Write-Warn "record: file not found, skipping ($path)"
    return 0
  }

  try {
    $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
  } catch {
    Write-Warn "record: hashing failed; skipping ($_)"
    return 0
  }

  $mode = Get-FileMode -Path $path
  $ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ", [Globalization.CultureInfo]::InvariantCulture)

  $statePath = Get-StatePath
  $stateDir = Split-Path -Parent $statePath
  try {
    if (-not (Test-Path $stateDir)) {
      New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }
  } catch {
    Write-Warn "cannot create $stateDir"; return 0
  }

  $base = $null
  if (Test-Path -LiteralPath $statePath) {
    try {
      $raw = Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop
      if ($raw.Trim()) { $base = $raw | ConvertFrom-Json }
    } catch {
      Write-Warn "existing state unreadable; rewriting"
      $base = $null
    }
  }

  $entries = @()
  if ($base -and $base.entries) {
    foreach ($e in $base.entries) {
      if ($e.path -ne $path) { $entries += $e }
    }
  }
  $entries += [PSCustomObject]@{
    category   = $category
    name       = $name
    path       = $path
    sha256     = $sha
    mode       = $mode
    deployedAt = $ts
  }

  $merged = [PSCustomObject]@{
    version = 1
    entries = $entries
  } | ConvertTo-Json -Depth 5

  $tmp = "$statePath.tmp.$([System.Guid]::NewGuid().ToString('N'))"
  try {
    [System.IO.File]::WriteAllText($tmp, $merged, [System.Text.UTF8Encoding]::new($false))
    Set-RestrictedAcl -Path $tmp
    Move-Item -LiteralPath $tmp -Destination $statePath -Force
  } catch {
    Write-Warn "atomic write failed: $_"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    return 0
  }

  return 0
}

if (-not $Subcommand) { Show-Usage; exit 2 }
switch ($Subcommand) {
  '-h'     { Show-Usage; exit 0 }
  '--help' { Show-Usage; exit 0 }
  'path'   { Write-Output (Get-StatePath); exit 0 }
  'record' {
    $code = Invoke-Record -Rest $Args
    exit $code
  }
  default {
    Write-Warn "unknown subcommand: $Subcommand"
    Show-Usage
    exit 2
  }
}
