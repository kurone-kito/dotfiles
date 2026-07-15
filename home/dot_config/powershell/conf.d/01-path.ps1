# Prepend known tool directories to PATH when they exist on disk.
# Session-level fallback — the primary mechanism is the chezmoi
# run_onchange script (35-register-path) which persists these in
# the Windows User PATH registry. This reconciles the repo-managed
# subset so profile reloads do not accumulate stale or duplicate
# entries while preserving unrelated PATH entries.

# Windows-only: manage user-scoped tool directories here.
if ($IsWindows -eq $false) { return }

# Nested Join-Path for PS5 compatibility (no -AdditionalChildPath).
. (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path 'lib' 'managed-paths.ps1')))

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
