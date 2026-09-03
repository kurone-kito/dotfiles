#!/usr/bin/env pwsh
# Pre-rendered test fixture for run_onchange_after_35-register-path.ps1.tmpl.
# Hash comments are replaced with dummy values since tests don't use
# chezmoi. The lib/managed-paths.ps1 block below is a literal copy of
# what chezmoi's `include` would splice in at apply time — keep it in
# sync with home/dot_config/powershell/lib/managed-paths.ps1 by hand;
# the managed-paths-parity Pester test fails if this copy drifts.
#
# hash: ae7bacf10ef20f21f4c9c7992c5fd51a9aa9620333b77b480b2121200dcd23e0
# winget user path packages hash: 44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a

# Reconcile the repo-managed subset of User PATH. Both surfaces
# compute the managed-path set from the shared source embedded
# below (see conf.d/01-path.ps1, which dot-sources the same file),
# so they cannot desync.

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
# placed ahead of WinGet\Links in $desiredManagedPaths. The repo
# ships such declarations as defaults (see docs/winget-user-path.md)
# — there is no hardcoded special case for any specific package here.

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
    # mise\shims must precede WinGet\Links: a same-named tool
    # duplicated across both is drift under this repo's
    # exclusive-ownership model (docs/setup-windows-boundary.md), and
    # WinGet\Links entries are NTFS reparse points that an inbound SSH
    # session's network logon token cannot traverse
    # (ERROR_UNTRUSTED_MOUNT_POINT). PATH resolution has no fallthrough
    # to a later working entry, so the working mise shim must win.
    $paths += (Join-Path (Join-Path $env:LOCALAPPDATA 'mise') 'shims')
    $paths += (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    $paths += (Join-Path $env:LOCALAPPDATA 'Zellij')
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

function Resolve-WingetUserPathBinDirectory {
  # Resolves a declared 'bin' value against a package directory.
  # - No bin (empty/whitespace): the package directory itself.
  # - Static bin (no '*'): unchanged single Join-Path, preserving the
  #   existing multi-segment behavior (e.g. 'mise/bin').
  # - Wildcard bin (contains '*'): split into segments and walk them
  #   from the package directory; a segment containing '*' resolves
  #   via Get-ChildItem, picking the lexicographically last match on
  #   FullName when more than one exists (not version-aware); a plain
  #   segment just extends the path. Handles a package directory whose
  #   real name is version-suffixed and changes on every winget
  #   update (e.g. Gyan.FFmpeg's 'ffmpeg-<version>-full_build/bin').
  #   Returns $null when a wildcard segment matches nothing, so the
  #   caller never probes a null/empty path with Test-Path.
  param(
    [Parameter(Mandatory)][string]$PackageDirFullName,
    [AllowNull()][string]$Bin
  )

  if ([string]::IsNullOrWhiteSpace($Bin)) {
    return $PackageDirFullName
  }

  if ($Bin -notmatch '\*') {
    return (Join-Path $PackageDirFullName $Bin)
  }

  $cursor = $PackageDirFullName
  foreach ($segment in ($Bin -split '[\\/]+')) {
    if ([string]::IsNullOrEmpty($segment)) {
      continue
    }

    if ($segment -match '\*') {
      $match = Get-ChildItem -LiteralPath $cursor -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like $segment } |
        Sort-Object -Property FullName |
        Select-Object -Last 1

      if ($null -eq $match) {
        return $null
      }

      $cursor = $match.FullName
    } else {
      $cursor = Join-Path $cursor $segment
    }
  }

  return $cursor
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
      $dir = Resolve-WingetUserPathBinDirectory -PackageDirFullName $packageDir.FullName -Bin $declared.bin

      if ($null -ne $dir -and (Test-Path -LiteralPath $dir -PathType Container)) {
        $paths += $dir
      }
    }
  }

  return $paths
}

$staticManagedPaths = @(Get-StaticManagedPaths)
$managedLookup = @{}
foreach ($dir in $staticManagedPaths) {
  $managedLookup[(Normalize-PathEntry $dir)] = $true
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
      [regex]::Escape(([string]$declared.id).ToLowerInvariant()) + '_[^\\]+' +
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

  foreach ($pattern in $wingetUserPathPatterns) {
    if ($normalized -match $pattern) {
      return $true
    }
  }

  return $false
}

$desiredManagedPaths = @()
$desiredLookup = @{}
foreach ($dir in @((@(Get-WingetUserPathManagedPaths)) + $staticManagedPaths)) {
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

$currentEntries = @(Split-PathEntries (Get-RegistryUserPath))
$remainingEntries = @()
foreach ($entry in $currentEntries) {
  if (-not (Test-IsManagedPath $entry)) {
    $remainingEntries += $entry
  }
}

$newEntries = @($desiredManagedPaths + $remainingEntries)
$currentNormalized = @($currentEntries | ForEach-Object { Normalize-PathEntry $_ }) -join $sep
$newNormalized = @($newEntries | ForEach-Object { Normalize-PathEntry $_ }) -join $sep

if ($currentNormalized -ceq $newNormalized) {
  Write-Host 'User PATH already up to date.'
} else {
  Set-RegistryUserPath ($newEntries -join $sep)
  Write-Host 'User PATH updated in registry.'
}
