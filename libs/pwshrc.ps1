#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
Import-Module -Name ./lib.psm1

Write-Output 'Install the profiles system for pwsh.exe'
Set-Location ..

### Setup profile.d
$dirName = '.pwsh.profile.d'
Join-Path $env:USERPROFILE $dirName | Add-Links -Source $dirName

### Setup PowerShell
$Documents = [Environment]::GetFolderPath('MyDocuments');

$PSProfile = Join-Path $Documents -ChildPath PowerShell # PowerShell Core
$WPSProfile = Join-Path $Documents -ChildPath WindowsPowerShell # PowerShell 5.x

$profileSrc = Get-Location `
| Join-Path -ChildPath PowerShell `
| Join-Path -ChildPath Microsoft.PowerShell_profile.ps1

@($PSProfile, $WPSProfile) | ForEach-Object {
  $dst = $_
  New-Item -Path $_ -ItemType Directory -Force | Out-Null
  @('Microsoft.PowerShell_profile.ps1', 'Microsoft.VSCode_profile.ps1') `
    | ForEach-Object {
      $profileSrc | Add-Link -Destination $dst -DestFileName $_
    }
}

Pop-Location
