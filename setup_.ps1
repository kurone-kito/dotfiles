#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
Push-Location $PSScriptRoot

Get-ChildItem -Recurse *.ps1 | Unblock-File
Import-Module -Name ./libs/lib.psm1

if (Invoke-SelfWithPrivileges) {
  exit
}

if (-not $args.Count) {
  Invoke-Self
  exit
}

./libs/link.ps1
./libs/cmdrc.ps1
./libs/pwshrc.ps1
./libs/terminal.ps1
./libs/gpg.ps1
./libs/git.ps1

Pop-Location
