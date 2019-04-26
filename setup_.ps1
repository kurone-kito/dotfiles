Set-StrictMode -Version Latest

Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)

### Link to dotfile for home dirw
Get-ChildItem -Attributes !Directory `
| Where-Object { $_.Name -match '^\.' } `
| ForEach-Object {
  $Dst = Join-Path $env:USERPROFILE $_.Name
  Remove-Item -Force $Dst
  New-Item -Path $env:USERPROFILE -ItemType SymbolicLink -Name $_.Name -Value $_.FullName
}

### Setup GPG
$GPGHome = Join-Path $env:APPDATA gnupg
Get-ChildItem -Path .gnupg -Attributes !Directory `
| ForEach-Object {
  $Dst = Join-Path $GPGHome $_.Name
  Remove-Item -Force $Dst
  New-Item -Path $GPGHome -ItemType SymbolicLink -Name $_.Name -Value $_.FullName
}

### Setup VSCode
$CodeHome = Join-Path $env:APPDATA Code User
Get-ChildItem -Path .vscode -Attributes !Directory `
| ForEach-Object {
  $Dst = Join-Path $CodeHome $_.Name
  Remove-Item -Force $Dst
  New-Item -Path $CodeHome -ItemType SymbolicLink -Name $_.Name -Value $_.FullName
}

### Setuo Git
$GPGPath = (Get-Command -Name gpg).Source
$GitConfData = Get-Content -Path .\templates\.gitconfig -Raw
$GitConfDst = Join-Path $env:USERPROFILE .gitconfig
Remove-Item -Force $GitConfDst
$GitConfData -f ($GPGPath -replace '\\', '\\') | Out-File -FilePath $GitConfDst -Force
