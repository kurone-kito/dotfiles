# GPG helper: prime the passphrase cache from SSH/terminal sessions.
# After running Invoke-GpgCachePassphrase (alias: gpg-cache), the
# 24-hour cache allows background tools (e.g., VS Code git) to sign
# without a pinentry prompt.

function Invoke-GpgCachePassphrase {
  if (-not (Get-Command gpg -ErrorAction SilentlyContinue)) {
    Write-Warning 'gpg not found in PATH'
    return
  }
  Write-Host 'Prompting GPG passphrase (loopback mode)...'
  '' | gpg --pinentry-mode loopback --clearsign --batch --yes 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Host 'Passphrase cached successfully (24h TTL).'
  } else {
    Write-Warning 'GPG passphrase caching failed.'
  }
}

Set-Alias -Name gpg-cache -Value Invoke-GpgCachePassphrase
