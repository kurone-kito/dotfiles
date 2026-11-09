# Resolve starship, git-wt, and node to the executables that mise reports, so
# later startup scripts launch them directly instead of through the mise
# shims. A shim launch cost about 0.4 s on Windows, against tens of
# milliseconds for the real executable (#708).
#
# Runs after 30-mise.ps1 in load order but does not depend on it: 30-mise.ps1
# removes $miseCommand, so this script finds mise on its own with the same
# candidate order as 30-mise.ps1 (Get-Command, then the Windows fallbacks).
# 30-mise.ps1 is never sourced again.
#
# Result: the profile-scope hashtable $__miseExecutables, keyed by tool name.
# A tool has a key only when `mise which <tool>` exits 0 and prints the path
# of an existing file. A miss leaves that tool to PATH lookup, and the other
# tools keep their resolved paths. Nothing is written to the environment, so
# no child process inherits these paths. mise is looked up as an application
# only, so a function or alias named mise is never run.

$__miseExecutables = & {
  $resolved = @{}

  $miseExe = $null
  $miseCommand = Get-Command mise -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -ne $miseCommand) {
    if ($miseCommand.Path) { $miseExe = $miseCommand.Path } else { $miseExe = $miseCommand.Source }
  }

  # Windows fallbacks, in 30-mise.ps1's order. Nested Join-Path for PS5.
  if ($null -eq $miseExe -and $IsWindows -ne $false) {
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

    foreach ($candidate in $fallbacks) {
      if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $miseExe = $candidate
        break
      }
    }
  }

  if ($null -eq $miseExe) {
    return , $resolved
  }

  foreach ($tool in @('starship', 'git-wt', 'node')) {
    # `which` must not install a missing tool version, so auto-install is off
    # for this one call. Both variables are restored to their prior state.
    $savedAutoInstall = $env:MISE_AUTO_INSTALL
    $savedExecAutoInstall = $env:MISE_EXEC_AUTO_INSTALL
    $env:MISE_AUTO_INSTALL = '0'
    $env:MISE_EXEC_AUTO_INSTALL = '0'
    $global:LASTEXITCODE = $null
    try {
      $output = & $miseExe which $tool 2>$null
      $exitOk = ($null -eq $LASTEXITCODE -or $LASTEXITCODE -eq 0)
    } catch {
      $exitOk = $false
    } finally {
      $env:MISE_AUTO_INSTALL = $savedAutoInstall
      $env:MISE_EXEC_AUTO_INSTALL = $savedExecAutoInstall
    }
    if (-not $exitOk) {
      continue
    }

    $toolPath = @($output | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") }) |
      Select-Object -First 1
    if ($null -eq $toolPath) {
      continue
    }
    $toolPath = ([string]$toolPath).Trim()
    if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
      continue
    }

    $resolved[$tool] = $toolPath
  }

  return , $resolved
}
