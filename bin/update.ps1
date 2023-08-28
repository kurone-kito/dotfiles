#!/usr/bin/env pwsh

###########################################################################
### Functions

function Get-IsAdmin {
  $os = $PSVersionTable | Select-Object -ExpandProperty OS
  if ($os -notmatch 'Windows') {
    return $true
  }
  $user = [System.Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]$user
  $principal.IsInRole('Administrators')
  <#
  .SYNOPSIS
  The function gets whether the current user has privileges.
  .INPUTS
  None.
  .OUTPUTS
  System.Boolean. Whether the current user has privileges.
  #>
}

function Install-NodeJSViaFNM() {
  param(
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [string]
    $NodeVersion,
    [string]
    $NPMVersion = 'latest'
  )
  fnm install $NodeVersion
  fnm default $NodeVersion

  # https://qiita.com/Qoo_Rus/items/afb52517e0e17b720990
  npm install -g --silent 'agentkeepalive@latest'
  npm install -g --silent "npm@${NPMVersion}"
  npm upgrade -g --silent
  corepack enable
  <#
  .SYNOPSIS
  Install the Node.js and some global packages.
  #>
}

###########################################################################
### Main

if (-not (Get-IsAdmin)) {
  Write-Error 'This script requires elevated privileges'
  exit 1
}

if (Get-Command brew -ErrorAction SilentlyContinue) {
  brew upgrade
  brew cleanup
}

if (Get-Command choco -ErrorAction SilentlyContinue) {
  choco upgrade -y all
}

if (Get-Command fnm -ErrorAction SilentlyContinue) {
  fnm env --use-on-cd | Out-String | Invoke-Expression
  Install-NodeJSViaFNM -NodeVersion 16 -NPMVersion 8
  Install-NodeJSViaFNM -NodeVersion 18
  Install-NodeJSViaFNM -NodeVersion 20
}

if (Get-Command vagrant -ErrorAction SilentlyContinue) {
  vagrant plugin update
}

if (Get-Command docker -ErrorAction SilentlyContinue) {
  docker images `
  | Select-Object -Skip 1 `
  | Select-String -Pattern '^(?<Name>[^\s]+)\s+(?<Tag>[^\s]+)'
  | Select-Object -ExpandProperty Matches
  | ForEach-Object {
    $Name = $_.Groups['Name'] | Select-Object -ExpandProperty Value
    $Tag = $_.Groups['Tag'] | Select-Object -ExpandProperty Value
    docker pull ('{0}:{1}' -f $Name, $Tag)
  }
  docker images --filter 'dangling=true' -q --no-trunc `
  | ForEach-Object { docker rmi -f $_ }
  docker builder prune -f
}

$sage = @(
  Get-ChildItem `
    -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\ `
    -Recurse `
  | Select-Object -ExpandProperty Property `
  | Where-Object { $_ -eq 'StateFlags0001' }
)
if ($sage.Length -gt 0) {
  cleanmgr /dc /sagerun:1
}
