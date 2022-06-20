#!/usr/bin/env pwsh

Set-StrictMode -Version Latest

if (($env:FNM_SETUP -ne 'true') -and (Get-Command fnm)) {
  $env:FNM_SETUP = 'true'
  fnm env --use-on-cd | Out-String | Invoke-Expression
}
