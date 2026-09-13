# Tests for executable_idd-critique-telemetry.cmd: the Windows-
# resolvable launcher for the IDD critiqueLoop.telemetryHook command
# "idd-critique-telemetry" -- native cmd.exe/PowerShell PATHEXT lookup
# cannot execute an extensionless shebang-only file (the POSIX
# script) at all, so this .cmd is what actually resolves on Windows
# and dispatches to the idd-critique-telemetry.ps1 twin.
#
# Unlike executable_coderabbit-critique.cmd (a real gate whose
# failure must propagate to the caller), this launcher fronts a
# fire-and-forget telemetry sink: it must never let a dispatch
# failure -- the shell being entirely absent from PATH, OR present but
# failing to start/run the script (broken runtime, missing/unreadable/
# blocked .ps1) -- surface as a nonzero exit or stray diagnostic output
# the C-phase loop could notice (PR #426 Codex review: an earlier
# version forwarded the latter failure's real exit code and skipped
# the available powershell fallback instead of trying it).
#
# Mirrors coderabbit-critique.Tests.ps1's own "Windows .cmd launcher
# dispatch" context structure and its cmd.exe-subprocess rationale (a
# .cmd cannot be launched directly via
# [Diagnostics.Process]::Start(UseShellExecute = $false); only
# cmd.exe itself can) -- see that file's comments for the full
# background this one does not repeat.
Describe 'idd-critique-telemetry.cmd launcher' -Skip:($IsWindows -eq $false) {
  BeforeAll {
    $script:CmdLauncherSource = Join-Path $PSScriptRoot `
      '../../home/dot_local/bin/executable_idd-critique-telemetry.cmd'
    $script:CmdExePath = (Get-Command cmd.exe).Source
    $script:SystemDir = [Environment]::SystemDirectory
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    $script:PwshDir = if ($pwshCommand) { Split-Path -Parent $pwshCommand.Source } else { $null }
    $powershellCommand = Get-Command powershell.exe -ErrorAction SilentlyContinue
    $script:PowerShellDir = if ($powershellCommand) {
      Split-Path -Parent $powershellCommand.Source
    } else {
      $null
    }

    # A minimal, local, space-only quoting helper -- deliberately not
    # reusing executable_coderabbit-critique.ps1's own
    # ConvertTo-DotfilesWindowsQuotedArgument, to avoid this test file
    # depending on an unrelated production script purely for a test
    # utility. $TestDrive-rooted paths (GUID-named directories under a
    # Pester-managed temp root) never contain an embedded double quote
    # in practice, so simple wrap-in-quotes is sufficient here.
    function script:ConvertTo-DotfilesTestQuotedPath {
      param([Parameter(Mandatory)] [string] $Path)
      return '"' + $Path + '"'
    }

    # Writes a fake idd-critique-telemetry.ps1 that records
    # $PSVersionTable.PSEdition (Core = pwsh, Desktop = Windows
    # PowerShell) to a file and exits with the given code -- so the
    # launcher tests below can assert which shell actually ran,
    # without depending on the real .ps1 twin's own logic.
    # `$MarkerPath`/`$RequireDesktop` are interpolated into the
    # generated script's literal text at authoring time (single-quoted
    # in the generated source).
    function script:New-DotfilesFakeIddCritiqueTelemetryPs1 {
      param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $MarkerPath,
        [int] $ExitCode = 0,
        [switch] $RequireDesktop
      )

      $requiresLine = if ($RequireDesktop) { '#Requires -PSEdition Desktop' } else { '' }
      $content = @"
$requiresLine
`$PSVersionTable.PSEdition | Out-File -FilePath '$MarkerPath' -Encoding utf8
exit $ExitCode
"@
      Set-Content -Path $Path -Value $content -Encoding utf8
    }

    # Invokes a copied .cmd launcher as a real subprocess via
    # `cmd.exe /d /s /c "<quoted-path>"`, with stdin fed from
    # `$InputText` (the launcher's real invocation always pipes a JSON
    # payload on stdin; an empty/no payload must still dispatch
    # cleanly since the .ps1 twin no-ops on empty input on its own).
    function script:Invoke-DotfilesIddCritiqueCmdLauncher {
      param(
        [Parameter(Mandatory)] [string] $LauncherPath,
        [string] $PathOverride = $env:PATH,
        [string] $InputText = ''
      )

      $quotedCmdPath = ConvertTo-DotfilesTestQuotedPath -Path $LauncherPath
      $psi = [Diagnostics.ProcessStartInfo]::new($script:CmdExePath)
      $psi.Arguments = "/d /s /c `"$quotedCmdPath`""
      $psi.UseShellExecute = $false
      $psi.RedirectStandardInput = $true
      $psi.RedirectStandardOutput = $true
      $psi.RedirectStandardError = $true
      $psi.CreateNoWindow = $true
      $psi.EnvironmentVariables['PATH'] = $PathOverride

      $proc = [Diagnostics.Process]::Start($psi)
      $proc.StandardInput.Write($InputText)
      $proc.StandardInput.Close()
      $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
      $stderrTask = $proc.StandardError.ReadToEndAsync()
      if (-not $proc.WaitForExit(30000)) {
        try { $proc.Kill() } catch [System.Exception] {}
        throw 'Invoke-DotfilesIddCritiqueCmdLauncher: launcher did not exit within 30s -- killed'
      }
      return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        Stdout   = $stdoutTask.GetAwaiter().GetResult()
        Stderr   = $stderrTask.GetAwaiter().GetResult()
      }
    }
  }

  AfterAll {
    foreach ($name in @(
        'ConvertTo-DotfilesTestQuotedPath'
        'New-DotfilesFakeIddCritiqueTelemetryPs1'
        'Invoke-DotfilesIddCritiqueCmdLauncher'
      )) {
      Remove-Item "Function:\$name" -ErrorAction SilentlyContinue
    }
  }

  BeforeEach {
    $script:FixtureDir = Join-Path $TestDrive ([Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $script:FixtureDir -Force | Out-Null
    $script:CmdLauncherCopy = Join-Path $script:FixtureDir 'idd-critique-telemetry.cmd'
    Copy-Item -Path $script:CmdLauncherSource -Destination $script:CmdLauncherCopy
    $script:FakePs1Path = Join-Path $script:FixtureDir 'idd-critique-telemetry.ps1'
    $script:MarkerPath = Join-Path $script:FixtureDir 'marker.txt'
  }

  It 'does not forward the dispatched process''s nonzero exit code (fire-and-forget regression)' {
    New-DotfilesFakeIddCritiqueTelemetryPs1 -Path $script:FakePs1Path `
      -MarkerPath $script:MarkerPath -ExitCode 7

    $result = Invoke-DotfilesIddCritiqueCmdLauncher -LauncherPath $script:CmdLauncherCopy

    $result.ExitCode | Should -Be 0
  }

  It 'prefers pwsh when it is on PATH' {
    if (-not $script:PwshDir) {
      Set-ItResult -Skipped -Because 'pwsh is not installed on this host'
      return
    }
    New-DotfilesFakeIddCritiqueTelemetryPs1 -Path $script:FakePs1Path `
      -MarkerPath $script:MarkerPath -ExitCode 0

    $result = Invoke-DotfilesIddCritiqueCmdLauncher -LauncherPath $script:CmdLauncherCopy

    $result.ExitCode | Should -Be 0
    (Get-Content -LiteralPath $script:MarkerPath -TotalCount 1) | Should -Be 'Core'
  }

  It 'falls back to powershell.exe when pwsh is not on PATH, and still exits 0' {
    if (-not $script:PowerShellDir) {
      Set-ItResult -Skipped -Because 'powershell.exe is not available on this host'
      return
    }
    New-DotfilesFakeIddCritiqueTelemetryPs1 -Path $script:FakePs1Path `
      -MarkerPath $script:MarkerPath -ExitCode 0
    # Allowlist (not an exclusion filter over the inherited PATH): only
    # powershell.exe's own resolved directory plus System32 (where
    # where.exe/cmd.exe live) are on the child PATH, so pwsh is
    # unresolvable regardless of what else the host's real PATH
    # happens to contain.
    $filteredPath = @($script:PowerShellDir, $script:SystemDir) -join [IO.Path]::PathSeparator

    $result = Invoke-DotfilesIddCritiqueCmdLauncher -LauncherPath $script:CmdLauncherCopy `
      -PathOverride $filteredPath

    $result.ExitCode | Should -Be 0
    (Get-Content -LiteralPath $script:MarkerPath -TotalCount 1) | Should -Be 'Desktop'
  }

  It 'falls back to powershell.exe when pwsh is on PATH but fails to run the script, and still exits 0 (regression)' {
    # The core Codex-flagged regression: a pwsh-specific runtime
    # failure -- not just pwsh being entirely absent from PATH -- must
    # still try the powershell fallback instead of forwarding pwsh's
    # own failure straight through. `#Requires -PSEdition Desktop`
    # gives a real, clean, edition-discriminating failure: pwsh (Core)
    # refuses to even start the script (nonzero exit, no marker
    # written) while powershell.exe (Desktop) runs it normally --
    # unlike a missing-file failure, which both shells would hit
    # identically and so could not prove the fallback was actually
    # attempted rather than pwsh alone happening to swallow it.
    if (-not $script:PwshDir) {
      Set-ItResult -Skipped -Because 'pwsh is not installed on this host'
      return
    }
    if (-not $script:PowerShellDir) {
      Set-ItResult -Skipped -Because 'powershell.exe is not available on this host'
      return
    }
    New-DotfilesFakeIddCritiqueTelemetryPs1 -Path $script:FakePs1Path `
      -MarkerPath $script:MarkerPath -ExitCode 0 -RequireDesktop

    $result = Invoke-DotfilesIddCritiqueCmdLauncher -LauncherPath $script:CmdLauncherCopy

    $result.ExitCode | Should -Be 0
    (Get-Content -LiteralPath $script:MarkerPath -TotalCount 1) | Should -Be 'Desktop'
  }

  It 'exits 0 with no stdout/stderr when neither pwsh nor powershell is on PATH (fire-and-forget regression)' {
    # Unlike coderabbit-critique.cmd's :no_shell (exit 1, a stderr
    # message), this fire-and-forget sink's contract is silence and
    # exit 0 regardless of cause.
    $filteredPath = $script:SystemDir

    $result = Invoke-DotfilesIddCritiqueCmdLauncher -LauncherPath $script:CmdLauncherCopy `
      -PathOverride $filteredPath

    $result.ExitCode | Should -Be 0
    $result.Stdout | Should -BeNullOrEmpty
    $result.Stderr | Should -BeNullOrEmpty
  }

  It 'exits 0 with no stdout/stderr when the script fails to run (missing .ps1) even though a shell is on PATH (regression)' {
    # No fake .ps1 is created in this test at all: whichever shell the
    # launcher prefers fails to find it (the exact "runtime broken, or
    # the script missing/unreadable/blocked" scenario the Codex review
    # named), and the launcher must still swallow that silently.
    if (-not $script:PwshDir -and -not $script:PowerShellDir) {
      Set-ItResult -Skipped -Because 'neither pwsh nor powershell is available on this host'
      return
    }

    $result = Invoke-DotfilesIddCritiqueCmdLauncher -LauncherPath $script:CmdLauncherCopy

    $result.ExitCode | Should -Be 0
    $result.Stdout | Should -BeNullOrEmpty
    $result.Stderr | Should -BeNullOrEmpty
  }

  It 'keeps stdout empty (no echoed commands or where.exe noise)' {
    # Regression guard for a missing `@echo off`: without it, cmd.exe
    # echoes every executed command line (and `where`'s own matched
    # path) onto real stdout, which this exact-content assertion would
    # catch even though the redirected `where ... >nul` hides that
    # command's own output specifically.
    if (-not $script:PwshDir -and -not $script:PowerShellDir) {
      Set-ItResult -Skipped -Because 'neither pwsh nor powershell is available on this host'
      return
    }
    New-DotfilesFakeIddCritiqueTelemetryPs1 -Path $script:FakePs1Path `
      -MarkerPath $script:MarkerPath -ExitCode 0

    $result = Invoke-DotfilesIddCritiqueCmdLauncher -LauncherPath $script:CmdLauncherCopy

    $result.Stdout | Should -BeNullOrEmpty
  }
}
