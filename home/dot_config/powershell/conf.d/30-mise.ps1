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

# Append ghq-cloned owner directories opted in via mise_trust in chezmoi
$__ghqTrustFile = Join-Path (Join-Path (Join-Path $HOME '.config') 'mise') 'chezmoi-ghq-trusted-paths'
if ((Test-Path $__ghqTrustFile) -and (Get-Command ghq -ErrorAction SilentlyContinue)) {
  $__ghqRoot = (ghq root 2>$null)
  if (-not [string]::IsNullOrWhiteSpace($__ghqRoot)) {
    foreach ($__pair in @(Get-Content $__ghqTrustFile -ErrorAction SilentlyContinue)) {
      if (-not [string]::IsNullOrWhiteSpace($__pair)) {
        $miseTrusted += Join-Path $__ghqRoot $__pair
      }
    }
  }
}
Remove-Variable __ghqTrustFile, __ghqRoot, __pair -ErrorAction SilentlyContinue

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
    # Lightweight presence check with no dot-source of
    # managed-paths.ps1 -- conf.d load order (01- before this file's
    # 30-) means 01-path.ps1 already placed $shimsDir via
    # Merge-ManagedPathEntries whenever it existed on disk at that
    # point, the common case, so this normal path never repeats
    # managed-paths.ps1's manifest parsing and WinGet package
    # enumeration on every session startup.
    $normalizedShimsDir = ($shimsDir -replace '/', '\').TrimEnd('\')
    $shimsDirInPath = @($env:PATH -split [IO.Path]::PathSeparator) | Where-Object {
      (($_ -replace '/', '\').TrimEnd('\')) -ieq $normalizedShimsDir
    }

    if (-not $shimsDirInPath) {
      # 01-path.ps1 could not have placed $shimsDir if it did not yet
      # exist on disk at that point -- e.g. `& $miseCommand reshim`
      # above just created it. Dot-source managed-paths.ps1 (the one
      # place this pays the full discovery cost) and re-run the same
      # shared minimal-precedence merge 01-path.ps1 itself uses, so
      # $shimsDir lands with the same mise\shims-before-WinGet\Links
      # precedence 01-path.ps1 would have applied, instead of a bare
      # unconditional append that could land it after an
      # already-present WinGet\Links.
      # Nested Join-Path for PS5 compatibility (no -AdditionalChildPath).
      . (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path 'lib' 'managed-paths.ps1')))
      $env:PATH = @(
        Merge-ManagedPathEntries -CurrentEntries (Split-PathEntries $env:PATH) -DesiredManagedPaths $desiredManagedPaths
      ) -join $sep
    }
  }
} else {
  (& $miseCommand activate pwsh --quiet 2>$null) | Out-String | Invoke-Expression
}
Remove-Variable miseCommand -ErrorAction SilentlyContinue
