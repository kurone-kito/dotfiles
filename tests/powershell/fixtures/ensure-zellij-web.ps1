#!/usr/bin/env pwsh
# Pre-rendered test fixture for ensure-zellij-web.ps1.tmpl.
# Simulates:
#   [data.zellij.web]
#   bind = "127.0.0.1"
#   port = 8082
#   base_url = ""
#   [data.zellij.web.tailscale]
#   enabled = true
#   https_port = 443
$ErrorActionPreference = 'Stop'

$script:DotfilesZellijWebBind = '127.0.0.1'
$script:DotfilesZellijWebPort = 8082
$script:DotfilesZellijWebBaseUrl = ''
$script:DotfilesZellijWebTailscaleEnabled = $true
$script:DotfilesZellijWebTailscaleHttpsPort = 443

function global:Get-DotfilesZellijCommand {
  $command = Get-Command zellij -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Path
  }

  $candidates = @()
  if (-not [string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
    $candidates += (Join-Path $env:LOCALAPPDATA 'Zellij\zellij.exe')
  }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }

  throw 'zellij executable not found.'
}

function global:Get-DotfilesTailscaleCommand {
  $command = Get-Command tailscale -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Path
  }

  $candidates = @()
  if (-not [string]::IsNullOrEmpty($env:ProgramFiles)) {
    $candidates += (Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe')
  }
  if (-not [string]::IsNullOrEmpty(${env:ProgramFiles(x86)})) {
    $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe')
  }

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }

  throw 'tailscale executable not found.'
}

function global:Get-DotfilesZellijWebServePath {
  $baseUrl = $script:DotfilesZellijWebBaseUrl
  if ([string]::IsNullOrWhiteSpace($baseUrl)) {
    return '/'
  }

  $normalized = $baseUrl.Trim()
  if ($normalized -eq '/') {
    return '/'
  }

  return ('/' + $normalized.Trim('/'))
}

function global:Get-DotfilesZellijWebServeTarget {
  return "http://127.0.0.1:$($script:DotfilesZellijWebPort)"
}

function global:Assert-DotfilesZellijWebTailscaleSettings {
  if (-not $script:DotfilesZellijWebTailscaleEnabled) {
    return
  }

  if ($script:DotfilesZellijWebBind -ne '127.0.0.1') {
    throw 'zellij.web.tailscale.enabled requires zellij.web.bind to remain 127.0.0.1.'
  }
}

function global:Get-DotfilesTailscaleServeStatusJson {
  param(
    [Parameter(Mandatory)]
    [string] $TailscaleCommand
  )

  try {
    $status = & $TailscaleCommand serve status --json 2>$null
    if ($LASTEXITCODE -ne 0) {
      return $null
    }

    return ($status | Out-String)
  } catch [System.Exception] {
    return $null
  }
}

function global:Test-DotfilesZellijWebRunning {
  param(
    [Parameter(Mandatory)]
    [string] $ZellijCommand
  )

  try {
    & $ZellijCommand web --status --timeout 2 | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch [System.Exception] {
    return $false
  }
}

function global:Test-DotfilesZellijWebTailscaleServeConfigured {
  param(
    [Parameter(Mandatory)]
    [string] $TailscaleCommand
  )

  $statusJson = Get-DotfilesTailscaleServeStatusJson -TailscaleCommand $TailscaleCommand
  if ([string]::IsNullOrWhiteSpace($statusJson)) {
    return $false
  }

  $servePath = Get-DotfilesZellijWebServePath
  $serveTarget = Get-DotfilesZellijWebServeTarget
  $httpsPortPattern = '"' + [regex]::Escape([string]$script:DotfilesZellijWebTailscaleHttpsPort) + '"\s*:\s*\{\s*"HTTPS"\s*:\s*true'
  $servePathPattern = '"' + [regex]::Escape($servePath) + '"\s*:\s*\{\s*"Proxy"\s*:\s*"' + [regex]::Escape($serveTarget) + '"'

  return ($statusJson -match $httpsPortPattern -and $statusJson -match $servePathPattern)
}

function global:Start-DotfilesZellijWeb {
  param(
    [Parameter(Mandatory)]
    [string] $ZellijCommand
  )

  & $ZellijCommand web --start --daemonize | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'failed to start zellij web server.'
  }
}

function global:Set-DotfilesZellijWebTailscaleServe {
  param(
    [Parameter(Mandatory)]
    [string] $TailscaleCommand
  )

  $arguments = @(
    'serve'
    '--bg'
    '--yes'
    '--https'
    [string] $script:DotfilesZellijWebTailscaleHttpsPort
  )

  $servePath = Get-DotfilesZellijWebServePath
  if ($servePath -ne '/') {
    $arguments += @('--set-path', $servePath)
  }

  $arguments += (Get-DotfilesZellijWebServeTarget)

  & $TailscaleCommand @arguments | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw 'failed to configure tailscale serve for zellij web.'
  }
}

function global:Ensure-DotfilesZellijWebPublication {
  if (-not $script:DotfilesZellijWebTailscaleEnabled) {
    return $false
  }

  Assert-DotfilesZellijWebTailscaleSettings
  $tailscaleCommand = Get-DotfilesTailscaleCommand

  if (Test-DotfilesZellijWebTailscaleServeConfigured -TailscaleCommand $tailscaleCommand) {
    return $false
  }

  Set-DotfilesZellijWebTailscaleServe -TailscaleCommand $tailscaleCommand

  if (-not (Test-DotfilesZellijWebTailscaleServeConfigured -TailscaleCommand $tailscaleCommand)) {
    throw 'tailscale serve failed to report the expected zellij web configuration.'
  }

  return $true
}

function global:Ensure-DotfilesZellijWeb {
  $zellijCommand = Get-DotfilesZellijCommand
  $changed = $false

  if (Test-DotfilesZellijWebRunning -ZellijCommand $zellijCommand) {
    if (Ensure-DotfilesZellijWebPublication) {
      $changed = $true
    }

    return $changed
  } else {
    Start-DotfilesZellijWeb -ZellijCommand $zellijCommand

    if (-not (Test-DotfilesZellijWebRunning -ZellijCommand $zellijCommand)) {
      throw 'zellij web failed to report healthy after startup.'
    }

    $changed = $true
  }

  if (Ensure-DotfilesZellijWebPublication) {
    $changed = $true
  }

  return $changed
}

if ($env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_INIT -ne '1') {
  Ensure-DotfilesZellijWeb | Out-Null
}
