# Prepend known tool directories to PATH when they exist on disk.
# Session-level fallback — the primary mechanism is the chezmoi
# run_onchange script (35-register-path) which persists these in
# the Windows User PATH registry. This reconciles the repo-managed
# subset so profile reloads do not accumulate stale or duplicate
# entries while preserving unrelated PATH entries.

# Windows-only: manage user-scoped tool directories here.
if ($IsWindows -eq $false) { return }

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
  }

  return $paths
}

function Get-MisePackagesRoot {
  if ([string]::IsNullOrEmpty($env:LOCALAPPDATA)) {
    return $null
  }

  return Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'WinGet') 'Packages'
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

function Test-IsManagedPath {
  param([AllowNull()][string]$PathEntry)

  $normalized = Normalize-PathEntry $PathEntry
  if ($managedLookup.ContainsKey($normalized)) {
    return $true
  }

  if ($null -ne $misePackagePattern -and $normalized -match $misePackagePattern) {
    return $true
  }

  return $false
}

$desiredManagedPaths = @()
$desiredLookup = @{}
foreach ($dir in @((@(Get-MiseManagedPaths)) + $staticManagedPaths)) {
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

$currentEntries = @(Split-PathEntries $env:PATH)
$remainingEntries = @()
foreach ($entry in $currentEntries) {
  if (-not (Test-IsManagedPath $entry)) {
    $remainingEntries += $entry
  }
}

$newEntries = @($desiredManagedPaths + $remainingEntries)

# Sync missing User PATH entries from the Windows registry.
# GUI-launched processes like VS Code inherit the PATH from their
# parent process, which may be stale if tools were installed after
# the parent started. Windows Terminal reads the registry for each
# new tab, but VS Code does not.
$registryUserPath = Get-RegistryUserPath
if (-not [string]::IsNullOrEmpty($registryUserPath)) {
  $newLookup = @{}
  foreach ($entry in $newEntries) {
    $norm = Normalize-PathEntry $entry
    if ($norm -ne '') {
      $newLookup[$norm] = $true
    }
  }

  foreach ($entry in (Split-PathEntries $registryUserPath)) {
    $norm = Normalize-PathEntry $entry
    if ($norm -ne '' -and -not $newLookup.ContainsKey($norm)) {
      if (Test-Path -LiteralPath $entry -PathType Container) {
        $newEntries += $entry
        $newLookup[$norm] = $true
      }
    }
  }
}

$currentNormalized = @($currentEntries | ForEach-Object { Normalize-PathEntry $_ }) -join $sep
$newNormalized = @($newEntries | ForEach-Object { Normalize-PathEntry $_ }) -join $sep

if ($currentNormalized -ceq $newNormalized) {
  return
}

$env:PATH = $newEntries -join $sep
