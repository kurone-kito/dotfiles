#!/usr/bin/env pwsh
# Sync per-user authorized_keys into ProgramData for Windows admin SSH logins.
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter()]
  [string] $Source
)
$ErrorActionPreference = 'Stop'

$script:AdministratorsSid = '*S-1-5-32-544'
$script:SystemSid = '*S-1-5-18'
$script:AdministratorsAuthorizedKeysPath = Join-Path `
  $env:ProgramData 'ssh\administrators_authorized_keys'

function Test-DotfilesAdminElevation {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DotfilesAuthorizedKeysSource {
  param([string] $Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return Join-Path (Join-Path $HOME '.ssh') 'authorized_keys'
  }

  return [IO.Path]::GetFullPath($Path)
}

function Sync-DotfilesAdministratorsAuthorizedKeys {
  param(
    [Parameter(Mandatory)]
    [string] $SourcePath,

    [Parameter()]
    [string] $DestinationPath = $script:AdministratorsAuthorizedKeysPath
  )

  if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Source authorized_keys not found: $SourcePath"
  }

  $destinationDir = Split-Path -Parent $DestinationPath
  if (-not (Test-Path -LiteralPath $destinationDir -PathType Container)) {
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
  }

  Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
  icacls $DestinationPath /inheritance:r `
    /grant:r "${script:AdministratorsSid}:(F)" `
    /grant "${script:SystemSid}:(F)" 2>&1 | Out-Null

  return $DestinationPath
}

if ($env:DOTFILES_TEST_OPENSSH_AUTHORIZED_KEYS_SKIP_MAIN -ne '1') {
  if (-not (Test-DotfilesAdminElevation)) {
    Write-Error 'This script requires administrator elevation. Re-run from an elevated prompt.'
    exit 1
  }

  $sourcePath = Get-DotfilesAuthorizedKeysSource -Path $Source

  if ($PSCmdlet.ShouldProcess(
      $script:AdministratorsAuthorizedKeysPath,
      "Sync administrator authorized_keys from $sourcePath"
    )) {
    $destinationPath = Sync-DotfilesAdministratorsAuthorizedKeys `
      -SourcePath $sourcePath
    Write-Host "OpenSSH administrator authorized_keys synced to: $destinationPath"
  }
}
