#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
Import-Module -Name ./lib.psm1

Write-Output 'Install the profiles system for cmd.exe'
Set-Location ..

# Register the cmdrc
$cmdRegKey = 'HKCU:\SOFTWARE\Microsoft\Command Processor'
$cmdRcPath = Join-Path $env:USERPROFILE '.cmdrc.cmd'
$callCmdRc = 'call {0}' -f $cmdRcPath
New-Item $cmdRegKey -Force | Out-Null
New-ItemProperty $cmdRegKey AutoRun -PropertyType String -Value $callCmdRc -Force

$dirName = '.cmdrc.d'
Join-Path $env:USERPROFILE $dirName | Add-Links -Source $dirName

Pop-Location
