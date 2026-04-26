# fzf (fuzzy finder) integration via PSFzf
# https://github.com/kelleyma49/PSFzf
# Requires: fzf binary + PSFzf module (Install-Module PSFzf)

if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) { return }

if (Get-Module -ListAvailable PSFzf) {
  Import-Module PSFzf
  Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}
