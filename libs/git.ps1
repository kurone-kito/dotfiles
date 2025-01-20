#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
Import-Module -Name ./lib.psm1

### Setup Git
Set-Location ..
$GPGPath = (Get-Command -Name gpg).Source
$GitLocal = Join-Path $env:USERPROFILE .gitconfig.local
New-Item $GitLocal | Out-Null
git config --file $GitLocal gpg.program $GPGPath
git config --file $GitLocal http.sslBackend schannel

Pop-Location
