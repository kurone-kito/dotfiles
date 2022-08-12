#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
Set-Location $PSScriptRoot
Import-Module -Name ./lib.psm1

### Setup GPG
Set-Location ..
$GPGHome = Join-Path $env:APPDATA -ChildPath gnupg
Add-Links -Source .gnupg -Destination $GPGHome
gpgconf --kill gpg-agent
