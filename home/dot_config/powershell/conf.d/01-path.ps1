# Reconciles the repo-managed subset of PATH using a minimal-precedence
# strategy (Merge-ManagedPathEntries, lib/managed-paths.ps1): an
# already-present managed entry keeps its existing position; a missing
# one is appended at the end, after the user's own existing entries
# (never force-prepended ahead of them) — except the one documented
# WinGet\Links-anchored ordering constraint (see managed-paths.ps1's
# own comment). Session-level fallback — the primary mechanism is the
# chezmoi run_onchange script (35-register-path) which persists these
# in the Windows User PATH registry. This reconciles the repo-managed
# subset so profile reloads do not accumulate stale or duplicate
# entries while preserving the user's own PATH ordering, including
# entries set via the user's own `setx PATH ...` invocation, and any
# User PATH registry entry recovered below (a stale parent-process
# $env:PATH that predates a later `setx` is itself never authoritative).

# Windows-only: manage user-scoped tool directories here.
if ($IsWindows -eq $false) { return }

# Nested Join-Path for PS5 compatibility (no -AdditionalChildPath).
. (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path 'lib' 'managed-paths.ps1')))

$liveEntries = @(Split-PathEntries $env:PATH)
$currentEntries = @($liveEntries)

# Recover User PATH registry entries missing from this process's own
# $env:PATH. GUI-launched processes like VS Code inherit the PATH from
# their parent process, which may be stale if tools were installed
# after the parent started. Windows Terminal reads the registry for
# each new tab, but VS Code does not. Recovered BEFORE the
# managed-path merge below so a registry-only user entry is treated as
# part of the user's own entry sequence -- missing managed entries
# land after it too, not just after the (possibly stale) live entries
# -- and only when Test-IsManagedPath does not already recognize it,
# so a stale managed registry leftover (an old winget-package version,
# a since-disabled declared package) is never reintroduced;
# Merge-ManagedPathEntries alone decides which managed entries belong
# in the result.
$registryUserPath = Get-RegistryUserPath
if (-not [string]::IsNullOrEmpty($registryUserPath)) {
  $currentLookup = @{}
  foreach ($entry in $currentEntries) {
    $norm = Normalize-PathEntry $entry
    if ($norm -ne '') {
      $currentLookup[$norm] = $true
    }
  }

  foreach ($entry in (Split-PathEntries $registryUserPath)) {
    $norm = Normalize-PathEntry $entry
    if (
      $norm -ne '' -and
      -not (Test-IsManagedPath $entry) -and
      -not $currentLookup.ContainsKey($norm)
    ) {
      if (Test-Path -LiteralPath $entry -PathType Container) {
        $currentEntries += $entry
        $currentLookup[$norm] = $true
      }
    }
  }
}

$newEntries = @(Merge-ManagedPathEntries -CurrentEntries $currentEntries -DesiredManagedPaths $desiredManagedPaths)

# Compare against the true live $env:PATH ($liveEntries), not the
# registry-enriched $currentEntries -- otherwise a registry-recovered
# entry that the managed-path merge itself leaves untouched (already
# fully reconciled) would be silently dropped by an early return here.
$currentNormalized = @($liveEntries | ForEach-Object { Normalize-PathEntry $_ }) -join $sep
$newNormalized = @($newEntries | ForEach-Object { Normalize-PathEntry $_ }) -join $sep

if ($currentNormalized -ceq $newNormalized) {
  return
}

$env:PATH = $newEntries -join $sep
