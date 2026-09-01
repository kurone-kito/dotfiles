# chezmoi run_after script: warn (never repair) when Windows system-wide
# mandatory ASLR (Exploit Protection's "Force randomization for images")
# is enabled and Git Bash (bash.exe) has no per-image exemption from it.
# That combination breaks every Git Bash fork() call (MSYS2/Cygwin's
# fork() emulation fails with child_copy/dofork errors) while git.exe
# itself keeps working (a MINGW build, unaffected), and chezmoi apply
# completes successfully throughout -- so the machine looks healthy
# while Git Bash is not. See
# https://gitforwindows.org/why-git-for-windows-does-not-work-with-mandatory-address-space-layout-randomization.html
#
# Detection lives here, in the unelevated apply path; repair does not:
# chezmoi never runs elevated here, and silently weakening a security
# mitigation during an ordinary apply would be the wrong trade. The
# actual (elevated, opt-in) repair is
# home/dot_local/bin/executable_repair-git-bash-aslr.ps1 (see its own
# header comment for the full mitigation-write details this script
# deliberately never performs).
#
# This script never modifies any exploit-mitigation setting and never
# checks the caller's privilege level -- an ordinary chezmoi apply must
# never be blocked or altered here. It also stays silent (exit 0, no
# warning) whenever the mitigation query itself fails or is unavailable,
# rather than warning speculatively on a guess. Runs on every apply (not
# run_once/run_onchange) since it depends on live system state, not
# chezmoi source content -- same rationale as
# run_after_82-link-idd-skill-xdg-config.ps1.
$ErrorActionPreference = 'Stop'

function Test-DotfilesSystemWideForceRelocateImagesOn {
  # Querying the machine-wide Exploit Protection policy (Windows
  # Security > App & browser control > Exploit protection > System
  # settings); ForceRelocateImages there is the "Force randomization for
  # images (Mandatory ASLR)" toggle. Returns $null (not $false) when the
  # query fails or its result shape is unreadable, so the caller can
  # stay silent instead of warning on a guess.
  try {
    $systemMitigation = Get-ProcessMitigation -System -ErrorAction Stop
  } catch {
    return $null
  }
  if (-not $systemMitigation -or -not $systemMitigation.ASLR) {
    return $null
  }
  return $systemMitigation.ASLR.ForceRelocateImages -eq 'ON'
}

function Test-DotfilesGitBashForceRelocateImagesExempt {
  # Per-image mitigation query for bash.exe specifically -- this
  # script's acceptance scope is bash.exe only (mitigations are keyed by
  # image name, so this needs no Git-for-Windows root resolution, unlike
  # the repair helper's usr\bin sweep). Tri-state like the check above:
  # $null on any query failure or unreadable result shape.
  try {
    $imageMitigation = Get-ProcessMitigation -Name 'bash.exe' -ErrorAction Stop
  } catch {
    return $null
  }
  if (-not $imageMitigation -or -not $imageMitigation.ASLR -or $null -eq $imageMitigation.ASLR.ForceRelocateImages) {
    # The extra explicit ForceRelocateImages-null check (absent from the
    # system-wide function above) matters only here: on the system-wide
    # side, a missing value already resolves to $null -eq 'ON' -> $false
    # -> silent, the safe direction. Here, "silent" is $true, and
    # comparing a missing value with -eq 'OFF' would otherwise resolve
    # to $false ("not exempt") -- the unsafe direction -- so this shape
    # is called out explicitly instead of relying on the same coercion.
    return $null
  }
  return $imageMitigation.ASLR.ForceRelocateImages -eq 'OFF'
}

function Invoke-DotfilesWarnGitBashAslr {
  [CmdletBinding()]
  param()

  try {
    $systemForceRelocateOn = Test-DotfilesSystemWideForceRelocateImagesOn
    if ($systemForceRelocateOn -ne $true) {
      # Not provably ON -- either confirmed OFF/NOTSET, or the query
      # failed/was unavailable ($null). Either way, nothing to warn
      # about, and the per-image state is never read.
      return 0
    }

    $bashExempt = Test-DotfilesGitBashForceRelocateImagesExempt
    if ($bashExempt -ne $false) {
      # Already exempt ($true), or the per-image query
      # failed/unavailable ($null) -- stay silent rather than warn on a
      # guess.
      return 0
    }

    Write-Warning (
      'Git Bash (bash.exe) has no per-image exemption from Windows mandatory ASLR ' +
      '(ForceRelocateImages) and every fork() call inside it will fail. Run & ' +
      '"$HOME\.local\bin\repair-git-bash-aslr.ps1" (elevated) to add the exemption.'
    )
    return 0
  } catch {
    # This script is advisory-only: an unexpected failure here must
    # never block or fail a normal chezmoi apply.
    return 0
  }
}

if ($env:DOTFILES_TEST_WARN_GIT_BASH_ASLR_SKIP_MAIN -ne '1') {
  exit (Invoke-DotfilesWarnGitBashAslr)
}
