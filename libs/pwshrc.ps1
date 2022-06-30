#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
Set-Location $PSScriptRoot
Import-Module -Name ./lib.psm1

Write-Output 'Install the profiles system for pwsh.exe'
Set-Location ..

### Setup PowerShell
$Documents = [Environment]::GetFolderPath('MyDocuments');

$PSProfile = Join-Path $Documents -ChildPath PowerShell # PowerShell Core
$WPSProfile = Join-Path $Documents -ChildPath WindowsPowerShell # PowerShell 5.x

Add-Links -Source PowerShell -Destination $PSProfile
Add-Links -Source PowerShell -Destination $WPSProfile
Join-Path $WPSProfile -ChildPath Microsoft.PowerShell_profile.ps1 `
  | Get-ChildItem -Attributes !Directory `
  | ForEach-Object { $_ | Add-Link -Destination $PSProfile }

$dirName = '.pwsh.profile.d'
Join-Path $env:USERPROFILE $dirName | Add-Links -Source $dirName
