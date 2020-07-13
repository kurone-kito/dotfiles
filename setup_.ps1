Set-StrictMode -Version Latest

Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Add-Link {
  param(
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [System.IO.FileInfo]
    $Source,

    [Parameter(Mandatory = $true)]
    [string]
    $Destination
  )

  $FileName = $Source.Name
  $FullPath = $Source.FullName
  $Replace = Join-Path $Destination -ChildPath $FileName
  if (Test-Path -Path $Replace) {
    Remove-Item -Force $Replace
  }
  New-Item -Path $Destination -ItemType SymbolicLink -Name $FileName -Value $FullPath
}

### Link to dotfile for home dir
Get-ChildItem -Attributes !Directory `
| Where-Object { $_.Name -match '^\.' } `
| ForEach-Object { $_ | Add-Link -Destination $env:USERPROFILE }

function Add-Links {
  param(
    [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
    [string]
    $Source,

    [Parameter(Mandatory = $true)]
    [string]
    $Destination
  )

  New-Item -Path $Destination -ItemType Directory -Force
  Get-ChildItem -Path $Source -Attributes !Directory `
  | ForEach-Object { $_ | Add-Link -Destination $Destination }
}

### Setup GPG
$GPGHome = Join-Path $env:APPDATA -ChildPath gnupg
Add-Links -Source .gnupg -Destination $GPGHome
gpgconf --kill gpg-agent

### Setup PowerShell
# TDOO: This setting maybe not need. Posh-git may also generate Microsoft.PowerShell_profile.ps1.
$Documents = [Environment]::GetFolderPath('MyDocuments');

$PSProfile = Join-Path $Documents -ChildPath PowerShell
$WPSProfile = Join-Path $Documents -ChildPath WindowsPowerShell
Add-Links -Source PowerShell -Destination $PSProfile
Add-Links -Source PowerShell -Destination $WPSProfile

### Setup VSCode
$CodeHome = Join-Path (Join-Path $env:APPDATA -ChildPath Code) -ChildPath User
Add-Links -Source .vscode -Destination $CodeHome

### Setup Git
$GPGPath = (Get-Command -Name gpg).Source
Copy-Item -Path .\templates\.gitconfig -Destination $env:USERPROFILE -Force
git config --global gpg.program $GPGPath

### Setup bin
$BinRoot = Join-Path $env:USERPROFILE bin
Add-Links -Source bin -Destination $BinRoot
