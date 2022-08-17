#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
Import-Module -Name ./lib.psm1

### Setup Git
Set-Location ..
$GPGPath = (Get-Command -Name gpg).Source
Copy-Item -Path .\templates\.gitconfig -Destination $env:USERPROFILE -Force
git config --global gpg.program $GPGPath

Pop-Location
