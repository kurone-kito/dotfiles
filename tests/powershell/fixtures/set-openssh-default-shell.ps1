#!/usr/bin/env pwsh
# Pre-rendered test fixture for set-openssh-default-shell.ps1.tmpl.
# Simulates:
#   [data.ssh.server]
#   defaultShell = "modern-powershell"
#   defaultShellFallbackToLegacy = false
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
$script:DotfilesOpenSSHDefaultShellChoice = 'modern-powershell'
$script:DotfilesOpenSSHDefaultShellFallbackToLegacy = $false

function Test-DotfilesAdminElevation {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-DotfilesOpenSSHShellChoice {
  switch ($script:DotfilesOpenSSHDefaultShellChoice) {
    '' {
      return [pscustomobject]@{ Action = 'NoOp' }
    }
    'cmd' {
      return [pscustomobject]@{ Action = 'Reset' }
    }
    'legacy-powershell' {
      $cmd = Get-Command powershell -ErrorAction SilentlyContinue
      if (-not $cmd) {
        throw 'defaultShell = "legacy-powershell" requires powershell.exe, but it was not found on this system.'
      }

      return [pscustomobject]@{ Action = 'Set'; ShellPath = $cmd.Source }
    }
    'modern-powershell' {
      $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
      if ($cmd) {
        return [pscustomobject]@{ Action = 'Set'; ShellPath = $cmd.Source }
      }

      if ($script:DotfilesOpenSSHDefaultShellFallbackToLegacy) {
        $cmd = Get-Command powershell -ErrorAction SilentlyContinue
        if ($cmd) {
          return [pscustomobject]@{ Action = 'Set'; ShellPath = $cmd.Source }
        }

        throw 'defaultShell = "modern-powershell" with defaultShellFallbackToLegacy = true requires pwsh.exe or powershell.exe, but neither was found on this system.'
      }

      throw 'defaultShell = "modern-powershell" requires pwsh.exe, but it was not found on this system. Set defaultShellFallbackToLegacy = true to fall back to powershell.exe.'
    }
    default {
      throw "Unrecognized [data.ssh.server].defaultShell value: '$($script:DotfilesOpenSSHDefaultShellChoice)'. Valid choices: cmd, legacy-powershell, modern-powershell."
    }
  }
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

  if (-not $Reset -and [string]::IsNullOrWhiteSpace($Shell)) {
    $resolution = Resolve-DotfilesOpenSSHShellChoice

    switch ($resolution.Action) {
      'NoOp' {
        Write-Host 'No [data.ssh.server].defaultShell configured; pass -Shell, or set [data.ssh.server].defaultShell in chezmoi.toml.'
        exit 0
      }
      'Reset' {
        $Reset = $true
      }
      'Set' {
        $Shell = $resolution.ShellPath
      }
    }
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
    $shellPath = $Shell

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
