# mise (polyglot runtime manager) initialization
# https://mise.jdx.dev/

if (-not (Get-Command mise -ErrorAction SilentlyContinue)) { return }

# Build trusted config paths so hooks never show trust errors
$miseTrusted = @(
  (Join-Path $HOME '.mise'),
  (Join-Path (Join-Path $HOME '.config') 'mise')
)

# WSL: include Windows-side config directories (visible via /mnt/c/)
if (Test-Path /proc/version -ErrorAction SilentlyContinue) {
  $wslInfo = Get-Content /proc/version -ErrorAction SilentlyContinue
  if ($wslInfo -match 'microsoft|wsl') {
    foreach ($d in (Get-ChildItem /mnt/c/Users -Directory -ErrorAction SilentlyContinue)) {
      $p1 = Join-Path $d.FullName '.mise'
      $p2 = Join-Path (Join-Path $d.FullName '.config') 'mise'
      if (Test-Path $p1) { $miseTrusted += $p1 }
      if (Test-Path $p2) { $miseTrusted += $p2 }
    }
  }
}

$env:MISE_TRUSTED_CONFIG_PATHS = $miseTrusted -join ':'
$env:MISE_PWSH_CHPWD_WARNING = '0'
Remove-Variable miseTrusted -ErrorAction SilentlyContinue

# Also run mise trust for persistence across sessions
foreach ($cfg in @(
  (Join-Path (Join-Path $HOME '.mise') 'config.toml'),
  (Join-Path (Join-Path (Join-Path $HOME '.config') 'mise') 'config.toml')
)) {
  if (Test-Path $cfg) { mise trust $cfg 2>$null }
}

(& mise activate pwsh --quiet 2>$null) | Out-String | Invoke-Expression
