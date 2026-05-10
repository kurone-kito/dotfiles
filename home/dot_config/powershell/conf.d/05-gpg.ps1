# GPG helper: expose the cache-priming script from ~/.local/bin.
# Also reload agent config so chezmoi-deployed TTL settings take effect.
$script:DotfilesGpgCacheScript = Join-Path (
  (Join-Path (Join-Path $HOME '.local') 'bin')
) 'gpg-cache.ps1'

if (Get-Command gpg-connect-agent -ErrorAction SilentlyContinue) {
  try {
    & gpg-connect-agent reloadagent /bye 2>$null | Out-Null
  } catch [System.Exception] {
  }
}

function Invoke-GpgCachePassphrase {
  if (-not (Test-Path -LiteralPath $script:DotfilesGpgCacheScript -PathType Leaf)) {
    Write-Warning "gpg-cache script not found: $script:DotfilesGpgCacheScript"
    return
  }

  & $script:DotfilesGpgCacheScript
}

Set-Alias -Name gpg-cache -Value Invoke-GpgCachePassphrase
