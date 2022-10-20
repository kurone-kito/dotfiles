#!/usr/bin/env pwsh

Set-StrictMode -Version Latest
Push-Location $PSScriptRoot
Import-Module -Name ./lib.psm1

Write-Output 'Setup the Windows Terminal configurations'
Set-Location ..
if ((Get-Command jq) -and (Get-Command wt)) {
  $process = Start-Process wt -PassThru
  $src = Join-Path templates 'windowsTerminal.settings.json'
  $dst = $env:LOCALAPPDATA `
  | Join-Path -ChildPath Packages `
  | Join-Path -ChildPath Microsoft.WindowsTerminal_8wekyb3d8bbwe `
  | Join-Path -ChildPath LocalState `
  | Join-Path -ChildPath settings.json
  while (-not (Test-Path $dst)) {
    Start-Sleep 3
  }
  Stop-Process -InputObject $process -Force -ErrorAction SilentlyContinue
  . ./.pwsh.profile.d/fnm.ps1
  npx -y strip-json-comments-cli $dst `
  | ConvertFrom-Json `
  | ConvertTo-Json -Depth 4 `
  | Set-Content $dst -Force
  $json = jq -s '.[0] * .[1]' $src $dst | Out-String
  $json | Out-File $dst -Encoding utf8 -Force
}

Write-Output 'Setup the Win32 Console configurations'

reg import templates/win32Console.reg

Pop-Location
