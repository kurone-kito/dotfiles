#!/usr/bin/env pwsh
# Pre-rendered test fixture for ensure-zellij-web.ps1.tmpl.
$ErrorActionPreference = 'Stop'

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

function global:Ensure-DotfilesZellijWeb {
  $zellijCommand = Get-DotfilesZellijCommand

  if (Test-DotfilesZellijWebRunning -ZellijCommand $zellijCommand) {
    return $false
  }

  Start-DotfilesZellijWeb -ZellijCommand $zellijCommand

  if (-not (Test-DotfilesZellijWebRunning -ZellijCommand $zellijCommand)) {
    throw 'zellij web failed to report healthy after startup.'
  }

  return $true
}

if ($env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_INIT -ne '1') {
  Ensure-DotfilesZellijWeb | Out-Null
}
