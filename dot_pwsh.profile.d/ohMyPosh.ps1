#!/usr/bin/env pwsh

Set-StrictMode -Version Latest

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
  $config = Join-Path $env:POSH_THEMES_PATH 'powerlevel10k_modern.omp.json'
  oh-my-posh init pwsh --config $config | Out-String | Invoke-Expression
}
