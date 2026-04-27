#!/usr/bin/env pwsh
# Pre-rendered test fixture for run_onchange_after_80-register-zellij-web.ps1.tmpl.
# Simulates:
#   [data.zellij.web.windows]
#   autostart = "onlogon"
$ErrorActionPreference = 'Stop'

$script:DotfilesZellijWebWindowsAutostartMode = 'onlogon'

function Get-DotfilesZellijWebTaskName {
  return 'dotfiles-zellij-web'
}

function Get-DotfilesZellijWebCurrentUser {
  return [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Get-DotfilesPreferredPowerShell {
  $command = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Path
  }

  $command = Get-Command powershell -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Path
  }

  throw 'No PowerShell executable was found for Scheduled Task registration.'
}

function Get-DotfilesZellijWebWrapperPath {
  return Join-Path (Join-Path (Join-Path $HOME '.local') 'bin') 'ensure-zellij-web.ps1'
}

function Get-DotfilesZellijWebTaskDescription {
  return 'Ensure Zellij Web is running for the current user after logon.'
}

function Invoke-DotfilesZellijWebTaskRegistration {
  param(
    [Parameter(Mandatory)]
    [object] $Action,

    [Parameter(Mandatory)]
    [object] $Trigger,

    [Parameter(Mandatory)]
    [object] $Principal
  )

  Register-ScheduledTask `
    -TaskName (Get-DotfilesZellijWebTaskName) `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Description (Get-DotfilesZellijWebTaskDescription) `
    -Force | Out-Null
}

function Register-DotfilesZellijWebTask {
  $wrapperPath = Get-DotfilesZellijWebWrapperPath
  if (-not (Test-Path -LiteralPath $wrapperPath -PathType Leaf)) {
    throw "Zellij Web wrapper not found: $wrapperPath"
  }

  $currentUser = Get-DotfilesZellijWebCurrentUser
  $powerShell = Get-DotfilesPreferredPowerShell
  $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$wrapperPath`""

  $action = New-ScheduledTaskAction -Execute $powerShell -Argument $arguments
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
  $principal = New-ScheduledTaskPrincipal `
    -UserId $currentUser `
    -LogonType Interactive `
    -RunLevel Limited

  Invoke-DotfilesZellijWebTaskRegistration `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal
}

function Unregister-DotfilesZellijWebTaskIfPresent {
  $taskName = Get-DotfilesZellijWebTaskName

  try {
    Get-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
  } catch [System.Exception] {
    return $false
  }

  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
  return $true
}

function Set-DotfilesZellijWebTaskAutostart {
  param(
    [Parameter(Mandatory)]
    [string] $AutostartMode
  )

  switch ($AutostartMode) {
    'disabled' {
      Unregister-DotfilesZellijWebTaskIfPresent | Out-Null
      return
    }
    'onlogon' {
      Register-DotfilesZellijWebTask
      return
    }
    default {
      throw "Unsupported zellij.web.windows.autostart mode: $AutostartMode"
    }
  }
}

if ($env:DOTFILES_TEST_ZELLIJ_WEB_SKIP_REGISTER -ne '1') {
  Set-DotfilesZellijWebTaskAutostart `
    -AutostartMode $script:DotfilesZellijWebWindowsAutostartMode
}
