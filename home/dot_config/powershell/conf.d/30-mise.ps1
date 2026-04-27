# mise (polyglot runtime manager) initialization
# https://mise.jdx.dev/

$miseCommand = & {
  function Resolve-MiseCommand {
    param(
      [string[]] $Candidates
    )

    $resolvedPaths = @{}

    foreach ($candidate in $Candidates) {
      if ([string]::IsNullOrWhiteSpace($candidate)) {
        continue
      }

      $resolvedCandidate = Resolve-Path -LiteralPath $candidate -ErrorAction SilentlyContinue |
        Select-Object -First 1
      if ($null -eq $resolvedCandidate) {
        continue
      }

      $resolvedPath = $resolvedCandidate.ProviderPath
      if ($resolvedPaths.ContainsKey($resolvedPath)) {
        continue
      }

      $resolvedPaths[$resolvedPath] = $true

      $command = Get-Command $candidate -ErrorAction SilentlyContinue
      if ($null -ne $command) {
        return $command
      }
    }

    return $null
  }

  $command = Get-Command mise -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command
  }

  if ($IsWindows -eq $false) {
    return $null
  }

  $fallbacks = @(
    (Join-Path (Join-Path (Join-Path $HOME '.local') 'bin') 'mise.exe')
  )

  if (-not [string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
    $wingetPackagesRoot = Join-Path (
      (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'WinGet')
    ) 'Packages'

    foreach ($package in @(
      Get-ChildItem -LiteralPath $wingetPackagesRoot -Directory -Filter 'jdx.mise_*' `
        -ErrorAction SilentlyContinue
    )) {
      $fallbacks += Join-Path (Join-Path (Join-Path $package.FullName 'mise') 'bin') 'mise.exe'
    }
  }

  return Resolve-MiseCommand -Candidates $fallbacks
}

if (-not $miseCommand) { return }

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

$env:MISE_TRUSTED_CONFIG_PATHS = $miseTrusted -join [IO.Path]::PathSeparator
$env:MISE_PWSH_CHPWD_WARNING = '0'
Remove-Variable miseTrusted -ErrorAction SilentlyContinue

# Also run mise trust for persistence across sessions
foreach ($cfg in @(
  (Join-Path (Join-Path $HOME '.mise') 'config.toml'),
  (Join-Path (Join-Path (Join-Path $HOME '.config') 'mise') 'config.toml')
)) {
  if (Test-Path $cfg) { & $miseCommand trust $cfg 2>$null }
}

# Windows: use shims mode to stay under cmd.exe's 8,191-char PATH limit.
# mise activate adds per-tool directories (~1,000+ chars for 14 tools);
# shims adds a single directory (~45 chars) and resolves per-directory
# versions internally via mise exec.
# Non-Windows: use activate mode for dynamic env var support (JAVA_HOME etc.)
if ($IsWindows -ne $false) {
  $shimsDir = Join-Path $env:LOCALAPPDATA 'mise\shims'
  if (-not (Test-Path $shimsDir)) {
    & $miseCommand reshim 2>$null
  }
  if (Test-Path $shimsDir) {
    $env:PATH = "$shimsDir$([IO.Path]::PathSeparator)$env:PATH"
  }
} else {
  (& $miseCommand activate pwsh --quiet 2>$null) | Out-String | Invoke-Expression
}
Remove-Variable miseCommand -ErrorAction SilentlyContinue
