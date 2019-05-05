Set-StrictMode -Version Latest

Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Create-Link {
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
  Remove-Item -Force (Join-Path $Destination -ChildPath $FileName)
  New-Item -Path $Destination -ItemType SymbolicLink -Name $FileName -Value $FullPath
}

### Link to dotfile for home dir
Get-ChildItem -Attributes !Directory `
| Where-Object { $_.Name -match '^\.' } `
| ForEach-Object { $_ | Create-Link -Destination $env:USERPROFILE }

### Setup GPG
$GPGHome = Join-Path $env:APPDATA -ChildPath 'gnupg'
Get-ChildItem -Path .gnupg -Attributes !Directory `
| ForEach-Object { $_ | Create-Link -Destination $GPGHome }

### Setup VSCode
$CodeHome = Join-Path (Join-Path $env:APPDATA -ChildPath 'Code') -ChildPath 'User'
Get-ChildItem -Path .vscode -Attributes !Directory `
| ForEach-Object { $_ | Create-Link -Destination $CodeHome }

### Setuo Git
$GPGPath = (Get-Command -Name gpg).Source
$GitConfData = Get-Content -Path .\templates\.gitconfig -Raw
$GitConfDst = Join-Path $env:USERPROFILE -ChildPath '.gitconfig'
Remove-Item -Force $GitConfDst
$Replaced = $GitConfData -f ($GPGPath -replace '\\', '\\')
$Replaced | Set-Content -Path $GitConfDst -Force -Encoding UTF8
