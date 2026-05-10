#!/usr/bin/env pwsh
# Set (or reset) the Windows OpenSSH server default shell to pwsh.
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter()]
  [string] $Shell,

  [switch] $Reset,

  [switch] $NoRestart
)
$ErrorActionPreference = 'Stop'

$script:OpenSSHRegistryPath = 'HKLM:\SOFTWARE\OpenSSH'
$script:DefaultShellCommandOption = '-NoLogo -NoProfile'

function Test-DotfilesAdminElevation {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DotfilesPreferredShell {
  $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  $cmd = Get-Command powershell -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  throw 'Neither pwsh nor powershell found on this system.'
}

function Set-DotfilesOpenSSHDefaultShell {
  param(
    [Parameter(Mandatory)]
    [string] $ShellPath
  )

  if (-not (Test-Path -LiteralPath $script:OpenSSHRegistryPath)) {
    New-Item -Path $script:OpenSSHRegistryPath -Force | Out-Null
  }

  New-ItemProperty -Path $script:OpenSSHRegistryPath `
    -Name DefaultShell -Value $ShellPath `
    -PropertyType String -Force | Out-Null
  New-ItemProperty -Path $script:OpenSSHRegistryPath `
    -Name DefaultShellCommandOption -Value $script:DefaultShellCommandOption `
    -PropertyType String -Force | Out-Null
}

function Reset-DotfilesOpenSSHDefaultShell {
  if (-not (Test-Path -LiteralPath $script:OpenSSHRegistryPath)) {
    return
  }

  $key = Get-Item -LiteralPath $script:OpenSSHRegistryPath
  foreach ($name in @('DefaultShell', 'DefaultShellCommandOption')) {
    if ($key.GetValue($name, $null) -ne $null) {
      Remove-ItemProperty -Path $script:OpenSSHRegistryPath -Name $name
    }
  }
}

function Restart-DotfilesSshdService {
  Restart-Service -Name sshd -Force
}

if ($env:DOTFILES_TEST_OPENSSH_SHELL_SKIP_MAIN -ne '1') {
  if (-not (Test-DotfilesAdminElevation)) {
    Write-Error 'This script requires administrator elevation. Re-run from an elevated prompt.'
    exit 1
  }

  if ($Reset) {
    if ($PSCmdlet.ShouldProcess($script:OpenSSHRegistryPath, 'Remove DefaultShell registry values')) {
      Reset-DotfilesOpenSSHDefaultShell
      Write-Host 'OpenSSH default shell reset to system default.'
    }

    if (-not $NoRestart) {
      if ($PSCmdlet.ShouldProcess('sshd', 'Restart service')) {
        Restart-DotfilesSshdService
        Write-Host 'sshd service restarted.'
      }
    }
  } else {
    $shellPath = if ([string]::IsNullOrWhiteSpace($Shell)) {
      Get-DotfilesPreferredShell
    } else {
      $Shell
    }

    if (-not (Test-Path -LiteralPath $shellPath -PathType Leaf)) {
      Write-Error "Shell not found: $shellPath"
      exit 1
    }

    $resolvedPath = [IO.Path]::GetFullPath($shellPath)

    if ($PSCmdlet.ShouldProcess($script:OpenSSHRegistryPath, "Set DefaultShell to $resolvedPath")) {
      Set-DotfilesOpenSSHDefaultShell -ShellPath $resolvedPath
      Write-Host "OpenSSH default shell set to: $resolvedPath"
    }

    if (-not $NoRestart) {
      if ($PSCmdlet.ShouldProcess('sshd', 'Restart service')) {
        Restart-DotfilesSshdService
        Write-Host 'sshd service restarted.'
      }
    }
  }
}
