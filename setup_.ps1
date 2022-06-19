#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
Set-Location $PSScriptRoot
Import-Module -Name ./libs/lib.psm1

Get-ChildItem -Recurse libs/*.ps1 | Unblock-File

if (Invoke-SelfWithPrivileges) {
  exit
}

if (-not $args.Count) {
  Invoke-Self
  exit
}

Get-ChildItem -Recurse *.ps1 | Unblock-File

### Link to dotfile for home dir
Get-ChildItem -Attributes !Directory `
  | Where-Object { $_.Name -match '^\.' } `
  | ForEach-Object { $_ | Add-Link -Destination $env:USERPROFILE }

./libs/cmdrc.ps1

### Setup GPG
$GPGHome = Join-Path $env:APPDATA -ChildPath gnupg
Add-Links -Source .gnupg -Destination $GPGHome
gpgconf --kill gpg-agent

### Setup PowerShell
# TDOO: This setting maybe not need. Posh-git may also generate Microsoft.PowerShell_profile.ps1.
$Documents = [Environment]::GetFolderPath('MyDocuments');

$PSProfile = Join-Path $Documents -ChildPath PowerShell # PowerShell Core
$WPSProfile = Join-Path $Documents -ChildPath WindowsPowerShell # PowerShell 5.x

Add-Links -Source PowerShell -Destination $PSProfile
Add-Links -Source PowerShell -Destination $WPSProfile
$WPSCurrentProfile = Join-Path $WPSProfile -ChildPath Microsoft.PowerShell_profile.ps1
Get-ChildItem -Path $WPSCurrentProfile -Attributes !Directory `
| ForEach-Object { $_ | Add-Link -Destination $PSProfile }

### Setup Git
$GPGPath = (Get-Command -Name gpg).Source
Copy-Item -Path .\templates\.gitconfig -Destination $env:USERPROFILE -Force
git config --global gpg.program $GPGPath
