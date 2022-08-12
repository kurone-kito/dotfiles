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
Get-ChildItem -Force -Attributes !Directory `
  | Where-Object { $_.Name -match '^\.' } `
  | ForEach-Object { $_ | Add-Link -Destination $env:USERPROFILE }

./libs/cmdrc.ps1
./libs/pwshrc.ps1
./libs/terminal.ps1
./libs/gpg.ps1
./libs/git.ps1
