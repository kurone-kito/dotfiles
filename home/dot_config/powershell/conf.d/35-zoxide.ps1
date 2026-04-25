# zoxide (smarter cd command) initialization
# https://github.com/ajeetdsouza/zoxide
# Requires: zoxide installed via winget, cargo, or scoop

if (-not (Get-Command zoxide -ErrorAction SilentlyContinue)) { return }

(& zoxide init powershell 2>$null) | Out-String | Invoke-Expression
