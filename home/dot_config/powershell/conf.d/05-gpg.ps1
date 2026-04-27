# GPG helper: expose the cache-priming script from ~/.local/bin.
$script:DotfilesGpgCacheScript = Join-Path (
  (Join-Path (Join-Path $HOME '.local') 'bin')
) 'gpg-cache.ps1'

function Invoke-GpgCachePassphrase {
  if (-not (Test-Path -LiteralPath $script:DotfilesGpgCacheScript -PathType Leaf)) {
    Write-Warning "gpg-cache script not found: $script:DotfilesGpgCacheScript"
    return
  }

  & $script:DotfilesGpgCacheScript
}

Set-Alias -Name gpg-cache -Value Invoke-GpgCachePassphrase
