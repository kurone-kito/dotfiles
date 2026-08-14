# Tests for run_after_90-reconcile-claude-code.ps1.tmpl.
# Exercises: env.DISABLE_AUTOUPDATER JSON merge-patch reconciliation on
# ~/.claude/settings.json (create/preserve/idempotent/fail-loudly-on-
# invalid-JSON), and the stray mise-managed-Node @anthropic-ai/claude-code
# copy detection/removal (only when the mise-managed npm copy is
# confirmed present).
#
# The template under test has zero go-template directives, so BeforeAll
# copies it byte-for-byte into $TestDrive as a plain .ps1 instead of
# hand-maintaining a separately-authored fixture (avoids drift between
# the fixture and the shipped script).
#
# SAFETY: every test overrides $HOME to a TestDrive path and mocks
# `mise` as a global function, never the real binary. Each test's
# preflight guard asserts both overrides actually took effect before
# invoking the script, so a broken mock can never fall through to the
# real machine's ~/.claude/settings.json or real mise-managed
# node_modules. The script is invoked via the `&` call operator (not
# dot-sourced), so its internal `exit` statements terminate only the
# child script context -- verified empirically not to kill the Pester
# process -- and are read back via $LASTEXITCODE.
#
# Windows-only claude-code shim naming (claude/claude.cmd/claude.ps1 at
# the npm prefix root, no `lib/` segment) is implemented from documented
# npm global-install behavior; the "stray claude-code copy cleanup
# (Windows layout)" Context below exercises it, but -Skip's condition
# means it never actually runs on this Linux/WSL session -- it is
# authoritative only under real Windows CI. The POSIX-layout Context
# is the mirror image: skipped on Windows, authoritative here.

BeforeAll {
  $script:Template = Join-Path (
    Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') 'home'
  ) 'run_after_90-reconcile-claude-code.ps1.tmpl'
  $script:Fixture = Join-Path $TestDrive 'run_after_90-reconcile-claude-code.ps1'
  Copy-Item -LiteralPath $script:Template -Destination $script:Fixture -Force

  function global:Set-TestMiseMock {
    param(
      [string] $NodeDir,
      [string] $ManagedDir,
      [bool] $ManagedResolves = $true,
      [bool] $ManagedWorks = $true
    )
    # NOTE: these must be $global:, not $script:. The mock function
    # below is invoked from inside the externally-invoked fixture
    # script's own call stack, where PowerShell's dynamic $script:
    # scope resolution binds to *that* script file's scope, not the
    # scope this function was defined in -- $script: state set here
    # would be invisible by the time `mise` is actually called.
    # Verified empirically with a minimal repro before writing this.
    $global:MockNodeDir = $NodeDir
    $global:MockManagedDir = $ManagedDir
    $global:MockManagedResolves = $ManagedResolves
    $global:MockManagedWorks = $ManagedWorks

    function global:mise {
      $a = $args
      if ($a.Count -ge 2 -and $a[0] -eq 'where' -and $a[1] -eq 'node') {
        if ($global:MockNodeDir) {
          Write-Output $global:MockNodeDir
          $global:LASTEXITCODE = 0
        } else {
          $global:LASTEXITCODE = 1
        }
        return
      }
      if ($a.Count -ge 2 -and $a[0] -eq 'where' -and $a[1] -eq 'npm:@anthropic-ai/claude-code') {
        if ($global:MockManagedResolves -and $global:MockManagedDir) {
          Write-Output $global:MockManagedDir
          $global:LASTEXITCODE = 0
        } else {
          $global:LASTEXITCODE = 1
        }
        return
      }
      if ($a.Count -ge 2 -and $a[0] -eq 'exec' -and $a[1] -eq 'npm:@anthropic-ai/claude-code') {
        $global:LASTEXITCODE = if ($global:MockManagedWorks) { 0 } else { 1 }
        return
      }
      $global:LASTEXITCODE = 1
    }
  }

  function global:Remove-TestMiseMock {
    Remove-Item Function:\mise -ErrorAction SilentlyContinue
    Remove-Variable -Name MockNodeDir, MockManagedDir, MockManagedResolves, MockManagedWorks -Scope Global -ErrorAction SilentlyContinue
  }

  function global:Set-TestNpmPrefixMock {
    # Windows-only: the fixture resolves npm's global prefix by
    # invoking "$NodeDir\npm.cmd config get prefix" directly (see
    # Resolve-MiseNpmPrefix), not via the `mise` mock -- so this needs
    # a real, executable .cmd file on disk rather than a PowerShell
    # function mock.
    param(
      [Parameter(Mandatory)] [string] $NodeDir,
      [string] $PrefixDir,
      [bool] $Resolves = $true
    )
    $npmCmdPath = Join-Path $NodeDir 'npm.cmd'
    if ($Resolves) {
      $content = "@echo off`r`necho $PrefixDir`r`n"
    } else {
      $content = "@echo off`r`nexit /b 1`r`n"
    }
    [System.IO.File]::WriteAllText($npmCmdPath, $content, [System.Text.ASCIIEncoding]::new())
  }

  function global:Assert-TestSafetyPreflight {
    # Fail fast rather than silently touching the real machine if
    # either override did not take effect.
    if ($HOME -ne $script:HomeDir) {
      throw "REFUSING TO RUN: HOME override did not take effect (HOME=$HOME)"
    }
    if ($HOME -eq $script:OriginalHome) {
      throw 'REFUSING TO RUN: HOME override is identical to the real HOME'
    }
  }

  function global:Write-TestStrayCopy {
    # Platform-adaptive so both the POSIX and the Windows-only Context
    # below can share one writer that always matches the layout the
    # script itself expects on whichever platform this actually runs.
    if ($IsWindows -ne $false) {
      # Stray dir and shims live under the resolved npm prefix, not
      # $script:NodeDir -- these are not guaranteed to be the same
      # directory (see Resolve-MiseNpmPrefix in the fixture).
      $strayBase = if ($script:NpmPrefixDir) { $script:NpmPrefixDir } else { $script:NodeDir }
      $strayDir = Join-Path $strayBase (Join-Path 'node_modules' (Join-Path '@anthropic-ai' 'claude-code'))
      New-Item -ItemType Directory -Path $strayDir -Force | Out-Null
      New-Item -ItemType File -Path (Join-Path $strayDir 'package.json') -Force | Out-Null
      foreach ($name in @('claude.cmd', 'claude.ps1', 'claude')) {
        New-Item -ItemType File -Path (Join-Path $strayBase $name) -Force | Out-Null
      }
    } else {
      $strayDir = Join-Path $script:NodeDir (Join-Path 'lib' (Join-Path 'node_modules' (Join-Path '@anthropic-ai' 'claude-code')))
      New-Item -ItemType Directory -Path (Join-Path $strayDir 'bin') -Force | Out-Null
      New-Item -ItemType File -Path (Join-Path $strayDir (Join-Path 'bin' 'claude.exe')) -Force | Out-Null
      $shim = Join-Path $script:NodeDir (Join-Path 'bin' 'claude')
      New-Item -ItemType File -Path $shim -Force | Out-Null
    }
    return $strayDir
  }
}

Describe '90-reconcile-claude-code' {
  BeforeEach {
    $script:OriginalHome = $HOME
    $script:HomeDir = Join-Path $TestDrive ([guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:HomeDir -Force | Out-Null
    Set-Variable -Name HOME -Value $script:HomeDir -Scope Global -Force

    $script:NodeDir = Join-Path $TestDrive ([guid]::NewGuid())
    $script:ManagedDir = Join-Path $TestDrive ([guid]::NewGuid())
    # Used only by the Windows-layout Context: the npm global prefix is
    # now resolved via the mise-managed npm itself (Resolve-MiseNpmPrefix)
    # rather than assumed to equal $script:NodeDir, so tests must be able
    # to point it somewhere genuinely different to prove the fix isn't
    # accidentally still reading $script:NodeDir under the hood.
    $script:NpmPrefixDir = Join-Path $TestDrive ([guid]::NewGuid())
    New-Item -ItemType Directory -Path (Join-Path $script:NodeDir (Join-Path 'lib' 'node_modules')) -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:NodeDir 'bin') -Force | Out-Null
    New-Item -ItemType Directory -Path $script:ManagedDir -Force | Out-Null
    New-Item -ItemType Directory -Path $script:NpmPrefixDir -Force | Out-Null

    Remove-TestMiseMock
  }

  AfterEach {
    Set-Variable -Name HOME -Value $script:OriginalHome -Scope Global -Force
    Remove-TestMiseMock
  }

  Context 'mise absent' {
    It 'no-ops without touching settings.json' {
      Assert-TestSafetyPreflight
      # The real mise binary may also be on PATH in the host running
      # this suite; scope PATH down to an empty directory so `mise`
      # is genuinely unresolvable, not just unmocked.
      $originalPath = $env:PATH
      try {
        $emptyPathDir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $emptyPathDir -Force | Out-Null
        $env:PATH = $emptyPathDir
        Get-Command mise -ErrorAction SilentlyContinue | Should -BeNullOrEmpty

        $output = & $script:Fixture *>&1 | Out-String
        $LASTEXITCODE | Should -Be 0
        $output | Should -Match 'mise not found; skipping'
        (Join-Path $HOME (Join-Path '.claude' 'settings.json')) | Should -Not -Exist
      } finally {
        $env:PATH = $originalPath
      }
    }
  }

  Context 'settings.json reconciliation' {
    BeforeEach {
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir
      Assert-TestSafetyPreflight
      (Get-Command mise).CommandType | Should -Be 'Function'
    }

    It 'creates settings.json with env.DISABLE_AUTOUPDATER=1 when absent' {
      & $script:Fixture | Out-Null
      $LASTEXITCODE | Should -Be 0
      $settingsFile = Join-Path $HOME (Join-Path '.claude' 'settings.json')
      $settingsFile | Should -Exist
      $parsed = Get-Content -Raw $settingsFile | ConvertFrom-Json
      $parsed.env.DISABLE_AUTOUPDATER | Should -Be '1'
      # The atomic write (temp file + move) must not leave its temp
      # file behind on a successful run.
      $settingsDir = Split-Path -Parent $settingsFile
      Get-ChildItem -LiteralPath $settingsDir -Filter '.settings.json.*' -Force |
        Should -BeNullOrEmpty
    }

    It 'preserves other keys, including other env.* keys, when reconciling an existing file' {
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
      $settingsFile = Join-Path $settingsDir 'settings.json'
      $existing = '{"permissions":{"allow":["Bash(git:*)"]},"env":{"OTHER_VAR":"keep-me"}}'
      [System.IO.File]::WriteAllText($settingsFile, $existing, [System.Text.UTF8Encoding]::new($false))

      & $script:Fixture | Out-Null
      $LASTEXITCODE | Should -Be 0
      $parsed = Get-Content -Raw $settingsFile | ConvertFrom-Json
      $parsed.env.DISABLE_AUTOUPDATER | Should -Be '1'
      $parsed.env.OTHER_VAR | Should -Be 'keep-me'
      $parsed.permissions.allow | Should -Be @('Bash(git:*)')
    }

    It 'fails loudly on a differently-cased existing "ENV" key, file left untouched' {
      # Regression test: PSObject.Properties's index-by-name lookup is
      # case-insensitive, but JSON object keys are not. A naive lookup
      # would silently match "ENV" here and mutate it instead of the
      # exact "env" key Claude Code actually reads, while still
      # reporting success. The correct fix cannot instead silently
      # create a *new* exact-case "env" key alongside the existing
      # "ENV" one either: PowerShell's PSCustomObject member model is
      # itself case-insensitive (Add-Member refuses to add "env" when
      # "ENV" already exists), so the only safe behavior is to fail
      # loudly and leave the file for the user to fix by hand.
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
      $settingsFile = Join-Path $settingsDir 'settings.json'
      $existing = '{"ENV":{"SOME_OTHER_VAR":"keep-me"}}'
      [System.IO.File]::WriteAllText($settingsFile, $existing, [System.Text.UTF8Encoding]::new($false))
      $before = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 1
      $output | Should -Match "differs from 'env' only by letter case"
      $after = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256
      $after.Hash | Should -Be $before.Hash
    }

    It 'fails loudly on a differently-cased existing "env.disable_autoupdater" key, file left untouched' {
      # Same case-collision hazard as the top-level 'env' key, one
      # level down: an exact-case "env" object already exists, but its
      # own DISABLE_AUTOUPDATER key is present under different casing.
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
      $settingsFile = Join-Path $settingsDir 'settings.json'
      $existing = '{"env":{"disable_autoupdater":"0"}}'
      [System.IO.File]::WriteAllText($settingsFile, $existing, [System.Text.UTF8Encoding]::new($false))
      $before = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 1
      $output | Should -Match "differs from 'env\.DISABLE_AUTOUPDATER' only by letter case"
      $after = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256
      $after.Hash | Should -Be $before.Hash
    }

    It 'fails loudly when settings.json is a symlink, symlink left untouched' {
      # Regression test: the atomic-replace pattern (temp file +
      # Move-Item) replaces whatever item sits at the destination path
      # -- if settings.json is itself a symlink, that would silently
      # sever the link and put a plain file there instead of updating
      # the link's target.
      #
      # Creating a symlink can require elevated privileges or Developer
      # Mode on Windows; skip gracefully rather than fail the suite on
      # an environment limitation unrelated to the script under test.
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
      $settingsFile = Join-Path $settingsDir 'settings.json'
      $realTarget = Join-Path $TestDrive ("real-settings-{0}.json" -f [guid]::NewGuid())
      [System.IO.File]::WriteAllText($realTarget, '{}', [System.Text.UTF8Encoding]::new($false))
      try {
        New-Item -ItemType SymbolicLink -Path $settingsFile -Target $realTarget -ErrorAction Stop | Out-Null
      } catch {
        Set-ItResult -Skipped -Because "symlink creation not permitted in this environment: $_"
        return
      }

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 1
      $output | Should -Match 'is a symlink'
      (Get-Item -LiteralPath $settingsFile -Force).LinkType | Should -Be 'SymbolicLink'
      (Get-Item -LiteralPath $settingsFile -Force).Target | Should -Be $realTarget
    }

    It 'does not write when env.DISABLE_AUTOUPDATER is already "1" (byte-identical)' {
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
      $settingsFile = Join-Path $settingsDir 'settings.json'
      [System.IO.File]::WriteAllText($settingsFile, '{"env":{"DISABLE_AUTOUPDATER":"1"}}', [System.Text.UTF8Encoding]::new($false))
      $before = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 0
      $output | Should -Match 'already set to "1"'
      $after = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256
      $after.Hash | Should -Be $before.Hash
    }

    It 'fails loudly and leaves the file untouched on invalid JSON' {
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
      $settingsFile = Join-Path $settingsDir 'settings.json'
      [System.IO.File]::WriteAllText($settingsFile, '{not valid json', [System.Text.UTF8Encoding]::new($false))
      $before = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 1
      $output | Should -Match 'invalid JSON'
      $after = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256
      $after.Hash | Should -Be $before.Hash
    }

    It 'fails loudly on a single-element top-level JSON array, not silently treated as an object' {
      # Regression test: ConvertFrom-Json's output is enumerated onto
      # the pipeline, so a single-element array such as "[{}]"
      # collapses to its bare object element by the time
      # `$parsed = ... | ConvertFrom-Json` finishes assigning -- a
      # naive post-parse "is this a PSCustomObject" check alone would
      # accept this and silently rewrite an array as an object.
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
      $settingsFile = Join-Path $settingsDir 'settings.json'
      [System.IO.File]::WriteAllText($settingsFile, '[{}]', [System.Text.UTF8Encoding]::new($false))
      $before = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256

      & $script:Fixture 2>&1 | Out-Null
      $LASTEXITCODE | Should -Be 1
      $after = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256
      $after.Hash | Should -Be $before.Hash
    }

    It 'fails loudly on a non-object env key, file left untouched' {
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
      $settingsFile = Join-Path $settingsDir 'settings.json'
      [System.IO.File]::WriteAllText($settingsFile, '{"env":"not-an-object"}', [System.Text.UTF8Encoding]::new($false))
      $before = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256

      & $script:Fixture 2>&1 | Out-Null
      $LASTEXITCODE | Should -Be 1
      $after = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256
      $after.Hash | Should -Be $before.Hash
    }

    It 'fails loudly on env:false (JSON false), not silently treated as empty object' {
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
      $settingsFile = Join-Path $settingsDir 'settings.json'
      [System.IO.File]::WriteAllText($settingsFile, '{"env":false}', [System.Text.UTF8Encoding]::new($false))
      $before = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256

      & $script:Fixture 2>&1 | Out-Null
      $LASTEXITCODE | Should -Be 1
      $after = Get-FileHash -LiteralPath $settingsFile -Algorithm SHA256
      $after.Hash | Should -Be $before.Hash
    }

    It 'round-trips non-ASCII content in unrelated keys unchanged (PS5.1 encoding regression)' {
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
      $settingsFile = Join-Path $settingsDir 'settings.json'
      # A non-ASCII value that would be corrupted if this file were
      # ever read via the active ANSI code page instead of UTF-8 (the
      # PS5.1 Get-Content -Raw default when no encoding is given).
      # Built from code points rather than a literal non-ASCII string:
      # this source file has no BOM (matching every other .Tests.ps1 in
      # this repo), and Windows PowerShell 5.1 reads BOM-less .ps1
      # source via the active console code page, not UTF-8 -- a literal
      # non-ASCII string here previously broke PS5.1's *discovery* of
      # this entire file with a ParseException, not just this one test.
      $nonAsciiValue = [string]::new([char[]](0x65E5, 0x672C, 0x8A9E, 0x306E, 0x30C6, 0x30B9, 0x30C8, 0x5024))
      $existing = '{{"someKey":"{0}","env":{{"OTHER_VAR":"keep-me"}}}}' -f $nonAsciiValue
      [System.IO.File]::WriteAllText($settingsFile, $existing, [System.Text.UTF8Encoding]::new($false))

      & $script:Fixture | Out-Null
      $LASTEXITCODE | Should -Be 0
      $parsed = Get-Content -Raw $settingsFile -Encoding UTF8 | ConvertFrom-Json
      $parsed.someKey | Should -Be $nonAsciiValue
      $parsed.env.DISABLE_AUTOUPDATER | Should -Be '1'
      $parsed.env.OTHER_VAR | Should -Be 'keep-me'
    }
  }

  Context 'stray claude-code copy cleanup (POSIX layout)' -Skip:($IsWindows -ne $false) {
    BeforeEach {
      Assert-TestSafetyPreflight
    }

    It 'no-ops idempotently when no stray copy exists' {
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir
      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 0
      $output | Should -Match 'No stray @anthropic-ai/claude-code copy found'
    }

    It 'removes both the directory and the bin shim when the managed copy is confirmed present' {
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir
      $strayDir = Write-TestStrayCopy
      $shim = Join-Path $script:NodeDir (Join-Path 'bin' 'claude')

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 0
      $output | Should -Match 'Removed stray @anthropic-ai/claude-code copy'
      $strayDir | Should -Not -Exist
      $shim | Should -Not -Exist
      $script:ManagedDir | Should -Exist
    }

    It 'leaves the stray copy in place when the managed copy is not resolvable' {
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir -ManagedResolves $false
      $strayDir = Write-TestStrayCopy
      $shim = Join-Path $script:NodeDir (Join-Path 'bin' 'claude')

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 0
      $output | Should -Match 'leaving the stray copy in place'
      $strayDir | Should -Exist
      $shim | Should -Exist
    }

    It 'leaves the stray copy in place when the managed directory resolves but claude does not work' {
      # Regression test: a resolvable mise-managed install directory
      # alone does not prove the managed 'claude' actually works -- an
      # interrupted or failed npm-backend install can leave the
      # directory in place without a functional binary. The repair
      # must not delete the stray copy in that case (it could be the
      # only working one).
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir -ManagedWorks $false
      $strayDir = Write-TestStrayCopy
      $shim = Join-Path $script:NodeDir (Join-Path 'bin' 'claude')

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 0
      $output | Should -Match 'does not appear to work'
      $output | Should -Match 'leaving the stray copy in place'
      $strayDir | Should -Exist
      $shim | Should -Exist
    }

    It 'still runs the stray-copy cleanup even when settings reconciliation fails (regression: exit must not short-circuit cleanup)' {
      # Regression test: Merge-ClaudeSettings previously called `exit 1`
      # directly on failure, which terminates the whole script before
      # Remove-StrayClaudeCodeCopy ever runs. Both effects -- the
      # settings-side failure AND the unrelated stray-copy cleanup --
      # must be observable from a single invocation.
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
      $settingsFile = Join-Path $settingsDir 'settings.json'
      [System.IO.File]::WriteAllText($settingsFile, '{not valid json', [System.Text.UTF8Encoding]::new($false))
      $strayDir = Write-TestStrayCopy
      $shim = Join-Path $script:NodeDir (Join-Path 'bin' 'claude')

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 1
      $output | Should -Match 'invalid JSON'
      $output | Should -Match 'Removed stray @anthropic-ai/claude-code copy'
      $strayDir | Should -Not -Exist
      $shim | Should -Not -Exist
    }

    It 'still runs the stray-copy cleanup even when settings reconciliation throws an unhandled exception (regression: uncaught I/O errors must not skip cleanup)' {
      # Regression test: an I/O failure that Merge-ClaudeSettings does
      # not itself catch (e.g. the initial '{}' seed write) would
      # otherwise propagate as a terminating error under
      # $ErrorActionPreference = 'Stop' and crash the whole script
      # before Remove-StrayClaudeCodeCopy runs -- the call site itself
      # needs its own try/catch, not just Merge-ClaudeSettings's
      # internal ones. Force this by making .claude a *file* instead
      # of a directory, so the seed write's parent path segment isn't
      # a real directory and WriteAllText throws.
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir
      $settingsDir = Join-Path $HOME '.claude'
      New-Item -ItemType File -Path $settingsDir -Force | Out-Null
      $strayDir = Write-TestStrayCopy
      $shim = Join-Path $script:NodeDir (Join-Path 'bin' 'claude')

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 1
      $output | Should -Match 'unexpected failure'
      $output | Should -Match 'Removed stray @anthropic-ai/claude-code copy'
      $strayDir | Should -Not -Exist
      $shim | Should -Not -Exist
    }
  }

  Context 'stray claude-code copy cleanup (Windows layout)' -Skip:($IsWindows -eq $false) {
    # Only executes under real Windows PowerShell/pwsh (per the Skip
    # condition above); on this Linux/WSL development session it is
    # always skipped, so it is authoritative only under Windows CI --
    # see the file-level comment at the top of this file.
    BeforeEach {
      Assert-TestSafetyPreflight
      # The prefix mock defaults to "resolves"; the fail-closed test
      # below overrides this with its own -Resolves:$false call.
      Set-TestNpmPrefixMock -NodeDir $script:NodeDir -PrefixDir $script:NpmPrefixDir
    }

    It 'no-ops idempotently when no stray copy exists' {
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir
      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 0
      $output | Should -Match 'No stray @anthropic-ai/claude-code copy found'
    }

    It 'removes the directory and all three shims (claude, claude.cmd, claude.ps1) when the managed copy is confirmed present' {
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir
      $strayDir = Write-TestStrayCopy
      $shims = @('claude.cmd', 'claude.ps1', 'claude') | ForEach-Object { Join-Path $script:NpmPrefixDir $_ }

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 0
      $output | Should -Match 'Removed stray @anthropic-ai/claude-code copy'
      $strayDir | Should -Not -Exist
      foreach ($shim in $shims) {
        $shim | Should -Not -Exist
      }
      $script:ManagedDir | Should -Exist
    }

    It 'leaves the stray copy and shims in place when the managed copy is not resolvable' {
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir -ManagedResolves $false
      $strayDir = Write-TestStrayCopy
      $shims = @('claude.cmd', 'claude.ps1', 'claude') | ForEach-Object { Join-Path $script:NpmPrefixDir $_ }

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 0
      $output | Should -Match 'leaving the stray copy in place'
      $strayDir | Should -Exist
      foreach ($shim in $shims) {
        $shim | Should -Exist
      }
    }

    It 'leaves the stray copy and shims in place when the managed directory resolves but claude does not work' {
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir -ManagedWorks $false
      $strayDir = Write-TestStrayCopy
      $shims = @('claude.cmd', 'claude.ps1', 'claude') | ForEach-Object { Join-Path $script:NpmPrefixDir $_ }

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 0
      $output | Should -Match 'does not appear to work'
      $output | Should -Match 'leaving the stray copy in place'
      $strayDir | Should -Exist
      foreach ($shim in $shims) {
        $shim | Should -Exist
      }
    }

    It 'skips the stray-copy check (fail-closed) when the mise-managed npm global prefix is not resolvable' {
      # Regression test for deriving the stray-copy path from the
      # resolved npm prefix rather than assuming it equals $NodeDir:
      # when the prefix itself cannot be resolved, the script must
      # skip the check rather than fall back to a guessed path.
      Set-TestMiseMock -NodeDir $script:NodeDir -ManagedDir $script:ManagedDir
      Set-TestNpmPrefixMock -NodeDir $script:NodeDir -Resolves $false

      $output = & $script:Fixture *>&1 | Out-String
      $LASTEXITCODE | Should -Be 0
      $output | Should -Match 'npm global prefix not resolvable'
    }
  }
}
