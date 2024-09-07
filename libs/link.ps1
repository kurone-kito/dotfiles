#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
Import-Module -Name ./lib.psm1

Set-Location ..

### Link to dotfile for home dir
Get-ChildItem -Force -Attributes !Directory `
| Where-Object { $_.Name -match '^\.' } `
| ForEach-Object { $_ | Add-Link -Destination $env:USERPROFILE }

$BinHome = Join-Path $HOME bin
Add-Links -Source bin -Destination $BinHome

$ConfigHome = Join-Path $HOME .config
New-Item -Path $ConfigHome -ItemType Directory -Force
$HuskyHome = Join-Path $ConfigHome husky
$HuskySrc = Join-Path .config husky
Add-Links -Source $HuskySrc -Destination $HuskyHome

Pop-Location
