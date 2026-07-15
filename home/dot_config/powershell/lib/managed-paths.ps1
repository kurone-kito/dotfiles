# Shared managed-PATH logic for conf.d/01-path.ps1 (session PATH) and
# run_onchange_after_35-register-path.ps1.tmpl (persisted User-PATH
# registry writer). Dot-sourced by the former and embedded verbatim
# via chezmoi's `include` into the latter, so both surfaces compute
# the managed-path set from this single source and cannot desync.
#
# Exposes: $sep, Split-PathEntries, Normalize-PathEntry,
# Test-IsManagedPath, Get-RegistryUserPath, Set-RegistryUserPath, and
# $desiredManagedPaths (deduplicated managed directories that exist
# on disk).
#
# WinGet declared-package directories (data.wingetUserPath.packages,
# see docs/winget-user-path.md) are discovered via the deployed
# winget-user-path-packages.json manifest (Get-WingetUserPath*) and
# placed ahead of WinGet\Links in $desiredManagedPaths, mirroring the
# mise special case below it (folding the two together is tracked
# separately).

$sep = [IO.Path]::PathSeparator

function Split-PathEntries {
  param([AllowNull()][string]$PathValue)

  if ([string]::IsNullOrEmpty($PathValue)) {
    return @()
  }

  return @(
    $PathValue.Split(
      [char[]]([IO.Path]::PathSeparator),
      [System.StringSplitOptions]::None
    )
  )
}

function Normalize-PathEntry {
  param([AllowNull()][string]$PathEntry)

  if ($null -eq $PathEntry) {
    return ''
  }

  $normalized = $PathEntry -replace '/', '\'
  while ($normalized.Length -gt 3 -and $normalized.EndsWith('\')) {
    $normalized = $normalized.Substring(0, $normalized.Length - 1)
  }

  return $normalized.ToLowerInvariant()
}

function Get-StaticManagedPaths {
  $paths = @()

  if (-not [string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
    $paths += (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    $paths += (Join-Path $env:LOCALAPPDATA 'Zellij')
    $paths += (Join-Path (Join-Path $env:LOCALAPPDATA 'mise') 'shims')
  }

  if (-not [string]::IsNullOrEmpty(${env:ProgramFiles(x86)})) {
    $paths += (Join-Path ${env:ProgramFiles(x86)} 'GnuWin32\bin')
  }

  if (-not [string]::IsNullOrEmpty($HOME)) {
    $paths += (Join-Path $HOME '.local\bin')
    # Default Cargo bin. Honor only the default location on Windows
    # (not $env:CARGO_HOME) because this list is also consumed by
    # run_onchange_after_35-register-path.ps1.tmpl which writes to
    # the User PATH registry; persisting a transient process-level
    # CARGO_HOME would pollute future sessions. Persistent CARGO_HOME
    # users should set it themselves at User scope.
    $paths += (Join-Path $HOME '.cargo\bin')
  }

  return $paths
}

function Get-WingetPackagesRoot {
  if ([string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
    return $null
  }

  return Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'WinGet') 'Packages'
}

function Get-MisePackagesRoot {
  Get-WingetPackagesRoot
}

function Get-WingetUserPathManifestPath {
  if ($null -ne $env:DOTFILES_TEST_WINGET_USER_PATH_MANIFEST) {
    return $env:DOTFILES_TEST_WINGET_USER_PATH_MANIFEST
  }

  if ([string]::IsNullOrEmpty($HOME)) {
    return $null
  }

  return Join-Path (
    Join-Path (Join-Path $HOME '.config') 'powershell'
  ) (Join-Path 'lib' 'winget-user-path-packages.json')
}

function Get-WingetUserPathDeclaredPackages {
  $manifestPath = Get-WingetUserPathManifestPath
  if ([string]::IsNullOrEmpty($manifestPath) -or
      -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    return @()
  }

  $raw = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction SilentlyContinue
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return @()
  }

  try {
    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    return @()
  }

  return @($parsed | Where-Object { -not [string]::IsNullOrWhiteSpace($_.id) })
}

function Get-WingetUserPathManagedPaths {
  $packagesRoot = Get-WingetPackagesRoot
  if ([string]::IsNullOrEmpty($packagesRoot)) {
    return @()
  }

  if (-not (Test-Path -LiteralPath $packagesRoot -PathType Container)) {
    return @()
  }

  $paths = @()
  foreach ($declared in @(Get-WingetUserPathDeclaredPackages)) {
    # A missing 'enabled' property (older manifests, hand-built test
    # fixtures) defaults to enabled; only an explicit $false disables.
    if ($null -ne $declared.enabled -and $declared.enabled -eq $false) {
      continue
    }

    foreach ($packageDir in @(
      Get-ChildItem -LiteralPath $packagesRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.StartsWith("$($declared.id)_", [StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object -Property FullName
    )) {
      $dir = if ([string]::IsNullOrWhiteSpace($declared.bin)) {
        $packageDir.FullName
      } else {
        Join-Path $packageDir.FullName $declared.bin
      }

      if (Test-Path -LiteralPath $dir -PathType Container) {
        $paths += $dir
      }
    }
  }

  return $paths
}

function Get-MiseManagedPaths {
  $packagesRoot = Get-MisePackagesRoot
  if ([string]::IsNullOrEmpty($packagesRoot)) {
    return @()
  }

  if (-not (Test-Path -LiteralPath $packagesRoot -PathType Container)) {
    return @()
  }

  $paths = @()
  foreach ($packageDir in @(
    Get-ChildItem -LiteralPath $packagesRoot -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like 'jdx.mise_*' } |
      Sort-Object -Property FullName
  )) {
    $binDir = Join-Path (Join-Path $packageDir.FullName 'mise') 'bin'
    if (Test-Path -LiteralPath $binDir -PathType Container) {
      $paths += $binDir
    }
  }

  return $paths
}

$staticManagedPaths = @(Get-StaticManagedPaths)
$managedLookup = @{}
foreach ($dir in $staticManagedPaths) {
  $managedLookup[(Normalize-PathEntry $dir)] = $true
}

$misePackagesRoot = Get-MisePackagesRoot
$misePackagePattern = $null
if (-not [string]::IsNullOrEmpty($misePackagesRoot)) {
  $misePackagePattern = '^' +
    [regex]::Escape((Normalize-PathEntry $misePackagesRoot)) +
    '\\jdx\.mise_[^\\]+\\mise\\bin$'
}

$wingetPackagesRoot = Get-WingetPackagesRoot
$wingetUserPathPatterns = @()
if (-not [string]::IsNullOrEmpty($wingetPackagesRoot)) {
  $normalizedWingetRoot = Normalize-PathEntry $wingetPackagesRoot
  foreach ($declared in @(Get-WingetUserPathDeclaredPackages)) {
    # Match the whole package directory (any subpath), not just the
    # currently-declared $bin suffix — otherwise changing bin (or
    # disabling the entry, handled above) would orphan a previously
    # added PATH entry that no longer matches, and it would never be
    # recognized as stale for cleanup.
    $wingetUserPathPatterns += (
      '^' + [regex]::Escape($normalizedWingetRoot) + '\\' +
      [regex]::Escape($declared.id.ToLowerInvariant()) + '_[^\\]+' +
      '(\\.*)?$'
    )
  }
}

function Test-IsManagedPath {
  param([AllowNull()][string]$PathEntry)

  $normalized = Normalize-PathEntry $PathEntry
  if ($managedLookup.ContainsKey($normalized)) {
    return $true
  }

  if ($null -ne $misePackagePattern -and $normalized -match $misePackagePattern) {
    return $true
  }

  foreach ($pattern in $wingetUserPathPatterns) {
    if ($normalized -match $pattern) {
      return $true
    }
  }

  return $false
}

$desiredManagedPaths = @()
$desiredLookup = @{}
foreach ($dir in @((@(Get-WingetUserPathManagedPaths)) + (@(Get-MiseManagedPaths)) + $staticManagedPaths)) {
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
    continue
  }

  $normalized = Normalize-PathEntry $dir
  if ($desiredLookup.ContainsKey($normalized)) {
    continue
  }

  $desiredManagedPaths += $dir
  $desiredLookup[$normalized] = $true
}

function Get-RegistryUserPath {
  if ($null -ne $env:DOTFILES_TEST_REGISTRY_USER_PATH) {
    return $env:DOTFILES_TEST_REGISTRY_USER_PATH
  }

  [Environment]::GetEnvironmentVariable('PATH', 'User')
}

function Set-RegistryUserPath {
  param([string]$Value)

  if ($null -ne $env:DOTFILES_TEST_REGISTRY_USER_PATH) {
    $env:DOTFILES_TEST_REGISTRY_USER_PATH = $Value
    return
  }

  [Environment]::SetEnvironmentVariable('PATH', $Value, 'User')
}
