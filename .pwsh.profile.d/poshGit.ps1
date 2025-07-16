#!/usr/bin/env pwsh

Set-StrictMode -Version Latest

if ($env:ChocolateyToolsLocation) {
  # cSpell: disable
  $poshGitPath = $env:ChocolateyToolsLocation `
  | Join-Path -ChildPath poshgit `
  | Join-Path -ChildPath dahlbyk-posh-git-9bda399 `
  | Join-Path -ChildPath src `
  | Join-Path -ChildPath posh-git.psm1
  # cSpell: enable

  if (Test-Path $poshGitPath) {
    Import-Module $poshGitPath
  }

  if (Get-Module -ListAvailable -Name posh-git -ErrorAction SilentlyContinue) {
    Import-Module posh-git
  }
}
