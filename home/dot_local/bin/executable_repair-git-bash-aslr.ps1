#!/usr/bin/env pwsh
# Repair Git Bash under Windows system-wide mandatory ASLR
# (ForceRelocateImages). MSYS2/Cygwin's fork() emulation copies the
# parent process's memory into a child that must map the same DLLs at
# the same addresses; mandatory ASLR re-randomizes them per process, so
# the copy fails and Git Bash's usr\bin binaries die with
# STATUS_DLL_INIT_FAILED. Git for Windows documents this as an
# unfixable design constraint and its installer offers a "per-image
# mitigation exemption" option; this script reproduces that repair for
# hosts where it was skipped (e.g. after a Windows reinstall). See
# https://gitforwindows.org/why-git-for-windows-does-not-work-with-mandatory-address-space-layout-randomization.html
#
# Requires administrator elevation (per-image mitigation policy lives in
# HKLM Image File Execution Options). Never touches the system-wide
# ForceRelocateImages setting, and never touches <git-root>\mingw64\bin
# (MINGW builds, unaffected by mandatory ASLR). Process mitigations are
# keyed by image *name*, not path -- this is why usr\bin\bash.exe also
# covers Git for Windows' bin\bash.exe (a junction to usr\bin), and it
# means a same-named *.exe elsewhere on the system would share the
# exemption too; not a concern for Git for Windows' own layout.
[CmdletBinding(SupportsShouldProcess)]
param()
$ErrorActionPreference = 'Stop'

function Test-DotfilesAdminElevation {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-DotfilesFatalError {
  param([Parameter(Mandatory)] [string] $Message)
  # Write-Error under the script-wide $ErrorActionPreference = 'Stop'
  # throws a terminating error instead of writing to the error stream,
  # which would skip the caller's own 'return 1' entirely. Swap EAP to
  # 'Continue' for just this call so the message actually lands on the
  # error stream (capturable by callers via 2>&1 / *>&1), then restore
  # it. Mirrors the pattern in run_after_90-reconcile-claude-code.ps1.tmpl.
  $previousEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  Write-Error $Message
  $ErrorActionPreference = $previousEap
}

function Test-DotfilesSystemWideForceRelocateImagesEnabled {
  # Get-ProcessMitigation -System reports the machine-wide Exploit
  # Protection policy (Windows Security > App & browser control >
  # Exploit protection > System settings); ForceRelocateImages there is
  # the "Force randomization for images (Mandatory ASLR)" toggle.
  $systemMitigation = Get-ProcessMitigation -System
  return $systemMitigation.ASLR.ForceRelocateImages -eq 'ON'
}

function Resolve-DotfilesGitForWindowsRoot {
  # Prefer the registry key the Git for Windows installer itself writes
  # (the documented, tool-agnostic way to locate a Git for Windows
  # install without guessing a path); 32-bit PowerShell on a 64-bit OS
  # sees this key redirected under WOW6432Node, so check both. A
  # per-user ("only for me", non-admin) install writes the same
  # Software\GitForWindows subkey under HKCU instead of HKLM -- no
  # WOW6432Node redirection applies there -- so check that hive too
  # (git-for-windows/git#455). Verify usr\bin actually exists at the
  # resolved path too, rather than trusting a stale or
  # partially-uninstalled registry entry.
  foreach ($registryPath in @(
      'HKLM:\SOFTWARE\GitForWindows'
      'HKLM:\SOFTWARE\WOW6432Node\GitForWindows'
      'HKCU:\SOFTWARE\GitForWindows'
    )) {
    if (-not (Test-Path -LiteralPath $registryPath)) {
      continue
    }

    $installPath = $null
    $installPath = (Get-ItemProperty -LiteralPath $registryPath -Name 'InstallPath' `
        -ErrorAction SilentlyContinue).InstallPath

    if ($installPath -and (Test-Path -LiteralPath (Join-Path $installPath 'usr\bin') -PathType Container)) {
      return $installPath
    }
  }

  # Fallback: resolve git.exe on PATH and walk up its ancestor
  # directories looking for a sibling usr\bin -- handles cmd\git.exe,
  # mingw64\bin\git.exe, and usr\bin\git.exe layouts alike without
  # assuming a fixed directory depth.
  $gitCommand = Get-Command 'git.exe' -ErrorAction SilentlyContinue
  if ($gitCommand) {
    $candidate = Split-Path -Parent $gitCommand.Source
    for ($depth = 0; $depth -lt 3; $depth++) {
      if (-not $candidate) {
        break
      }
      if (Test-Path -LiteralPath (Join-Path $candidate 'usr\bin') -PathType Container) {
        return $candidate
      }
      $candidate = Split-Path -Parent $candidate
    }
  }

  return $null
}

function Get-DotfilesGitBashUsrBinExecutables {
  param([Parameter(Mandatory)] [string] $GitRoot)

  $usrBin = Join-Path $GitRoot 'usr\bin'
  return @(Get-ChildItem -LiteralPath $usrBin -Filter '*.exe' -File -ErrorAction SilentlyContinue)
}

function Test-DotfilesImageForceRelocateImagesDisabled {
  param([Parameter(Mandatory)] [string] $ImageName)

  $mitigation = Get-ProcessMitigation -Name $ImageName
  return $mitigation.ASLR.ForceRelocateImages -eq 'OFF'
}

function Disable-DotfilesImageForceRelocateImages {
  param([Parameter(Mandatory)] [string] $ImageName)

  # Per-image (HKLM Image File Execution Options) scope only -- never
  # -System, which would change the machine-wide policy this script is
  # explicitly designed to leave untouched.
  $null = Set-ProcessMitigation -Name $ImageName -Disable ForceRelocateImages
}

function Invoke-DotfilesRepairGitBashAslr {
  [CmdletBinding(SupportsShouldProcess)]
  param()

  try {
    if (-not (Test-DotfilesAdminElevation)) {
      Write-DotfilesFatalError 'This script requires administrator elevation. Re-run from an elevated prompt.'
      return 1
    }

    if (-not (Test-DotfilesSystemWideForceRelocateImagesEnabled)) {
      Write-Host 'System-wide mandatory ASLR (ForceRelocateImages) is not enabled; Git Bash needs no per-image exemption. Nothing to do.'
      return 0
    }

    $gitRoot = Resolve-DotfilesGitForWindowsRoot
    if (-not $gitRoot) {
      Write-DotfilesFatalError (
        'Could not resolve the Git for Windows install root (checked ' +
        'HKLM:\SOFTWARE\GitForWindows, HKLM:\SOFTWARE\WOW6432Node\GitForWindows, ' +
        'and git.exe on PATH). Install Git for Windows, or ensure git.exe is on ' +
        'PATH, then re-run.'
      )
      return 1
    }

    $usrBinPath = Join-Path $gitRoot 'usr\bin'
    $executables = @(Get-DotfilesGitBashUsrBinExecutables -GitRoot $gitRoot)
    if ($executables.Count -eq 0) {
      Write-DotfilesFatalError "No *.exe files found under $usrBinPath; the Git for Windows install at $gitRoot looks incomplete."
      return 1
    }

    $changedCount = 0
    $neededCount = 0
    foreach ($executable in $executables) {
      if (Test-DotfilesImageForceRelocateImagesDisabled -ImageName $executable.Name) {
        continue
      }

      $neededCount++
      if ($PSCmdlet.ShouldProcess($executable.Name, 'Disable ForceRelocateImages mitigation')) {
        Disable-DotfilesImageForceRelocateImages -ImageName $executable.Name
        $changedCount++
      }
    }

    if ($neededCount -eq 0) {
      Write-Host "Git Bash under $gitRoot is already exempted from mandatory ASLR; nothing to change."
    } elseif ($changedCount -eq 0) {
      # -WhatIf (or a declined -Confirm prompt) suppressed every write --
      # distinct from the true no-op case above, so do not claim
      # "already exempted" when a real run would still change something.
      Write-Host "$neededCount image(s) under $usrBinPath need the ForceRelocateImages exemption; no changes applied (re-run without -WhatIf to apply)."
    } elseif ($changedCount -lt $neededCount) {
      # A declined -Confirm prompt on some (not all) images -- report the
      # partial result explicitly rather than a plain "Disabled N" message
      # that would silently omit the remainder still needing the fix.
      $remaining = $neededCount - $changedCount
      Write-Host "Disabled ForceRelocateImages for $changedCount of $neededCount needed image(s) under $usrBinPath; $remaining still need it (declined?)."
    } else {
      Write-Host "Disabled ForceRelocateImages for $changedCount image(s) under $usrBinPath."
    }

    return 0
  } catch {
    Write-DotfilesFatalError "error: unexpected failure while repairing Git Bash mandatory-ASLR exemptions: $_"
    return 1
  }
}

if ($env:DOTFILES_TEST_REPAIR_GIT_BASH_ASLR_SKIP_MAIN -ne '1') {
  exit (Invoke-DotfilesRepairGitBashAslr @PSBoundParameters)
}
