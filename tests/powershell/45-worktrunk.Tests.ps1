# Tests for the PowerShell worktrunk initialization script.
# Exercises: early exit, command fallback, init evaluation, trailing-zero
# stripping, and cleanup.

BeforeAll {
  $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $script:Subject = Join-Path (
    (Join-Path (Join-Path (Join-Path $repoRoot 'home') 'dot_config') 'powershell\conf.d')
  ) '45-worktrunk.ps1'

  # Create a mock native executable that outputs given lines to stdout.
  # The production code invokes by resolved path, so tests need real files.
  function New-MockNativeCommand {
    param([string]$Dir, [string]$Name, [string[]]$Lines)
    $path = Join-Path $Dir $Name
    $body = "#!/bin/sh`n" + (
      ($Lines | ForEach-Object { "echo '$($_ -replace "'", "'\''")'" }) -join "`n"
    ) + "`n"
    [System.IO.File]::WriteAllText($path, $body)
    if ($IsWindows -eq $false) { & chmod +x $path }
    return $path
  }
}

Describe '45-worktrunk' {

  BeforeEach {
    $script:MockBin = Join-Path ([System.IO.Path]::GetTempPath()) `
      "wt-mock-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $script:MockBin -Force | Out-Null

    Remove-Variable __wtCmd -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkInitialized -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkCommand -Scope Script -ErrorAction SilentlyContinue

    Mock Get-Command { $null } -ParameterFilter { $Name -in @('git-wt', 'wt') }
  }

  AfterEach {
    Remove-Variable __wtCmd -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkInitialized -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable WorktrunkCommand -Scope Script -ErrorAction SilentlyContinue
    if ($script:MockBin -and (Test-Path $script:MockBin)) {
      Remove-Item $script:MockBin -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It 'returns early without error when neither git-wt nor wt is available' {
    { . $script:Subject } | Should -Not -Throw
  }

  It 'evaluates init output when git-wt is available' {
    $mockPath = New-MockNativeCommand $script:MockBin 'git-wt' @(
      '$script:WorktrunkInitialized = $true',
      '$script:WorktrunkCommand = "git-wt"'
    )
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $mockPath }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
    $script:WorktrunkCommand | Should -Be 'git-wt'
  }

  It 'falls back to wt when git-wt is not available' {
    $mockPath = New-MockNativeCommand $script:MockBin 'wt' @(
      '$script:WorktrunkInitialized = $true',
      '$script:WorktrunkCommand = "wt"'
    )
    Mock Get-Command {
      [pscustomobject]@{ Name = 'wt'; CommandType = 'Application'; Path = $mockPath }
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
    $script:WorktrunkCommand | Should -Be 'wt'
  }

  It 'ignores function/alias named git-wt (only Application type accepted)' {
    # Default mock returns $null — no Application-type git-wt or wt exists.
    . $script:Subject

    $script:WorktrunkInitialized | Should -BeNullOrEmpty
    $script:WorktrunkCommand | Should -BeNullOrEmpty
  }

  It 'does not fall back to wt when wt resolves to Windows Terminal' {
    Mock Get-Command {
      [pscustomobject]@{
        Name = 'wt'
        CommandType = 'Application'
        Path = 'C:\Users\me\AppData\Local\Microsoft\WindowsApps\wt.exe'
      }
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeNullOrEmpty
    $script:WorktrunkCommand | Should -BeNullOrEmpty
  }

  It 'skips Windows Terminal wt and uses worktrunk wt from later PATH entry' {
    $mockPath = New-MockNativeCommand $script:MockBin 'wt' @(
      '$script:WorktrunkInitialized = $true',
      '$script:WorktrunkCommand = "wt"'
    )
    Mock Get-Command {
      @(
        [pscustomobject]@{
          Name = 'wt'; CommandType = 'Application'
          Path = 'C:\Users\me\AppData\Local\Microsoft\WindowsApps\wt.exe'
        },
        [pscustomobject]@{
          Name = 'wt'; CommandType = 'Application'
          Path = $mockPath
        }
      )
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
    $script:WorktrunkCommand | Should -Be 'wt'
  }

  It 'prefers git-wt when both git-wt and wt are available' {
    $gitWtPath = New-MockNativeCommand $script:MockBin 'git-wt' @(
      '$script:WorktrunkInitialized = $true',
      '$script:WorktrunkCommand = "git-wt"'
    )
    $wtPath = New-MockNativeCommand $script:MockBin 'wt' @(
      '$script:WorktrunkInitialized = $true',
      '$script:WorktrunkCommand = "wt"'
    )
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $gitWtPath }
    } -ParameterFilter { $Name -eq 'git-wt' }
    Mock Get-Command {
      [pscustomobject]@{ Name = 'wt'; CommandType = 'Application'; Path = $wtPath }
    } -ParameterFilter { $Name -eq 'wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
    $script:WorktrunkCommand | Should -Be 'git-wt'
  }

  It 'strips trailing zero lines from init output before evaluation' {
    $mockPath = New-MockNativeCommand $script:MockBin 'git-wt' @(
      '$script:WorktrunkInitialized = $true',
      '0'
    )
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $mockPath }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeTrue
  }

  It 'strips output that is only a bare zero' {
    $mockPath = New-MockNativeCommand $script:MockBin 'git-wt' @('0')
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $mockPath }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    $script:WorktrunkInitialized | Should -BeNullOrEmpty
  }

  It 'cleans up temporary variables after execution' {
    $mockPath = New-MockNativeCommand $script:MockBin 'git-wt' @(
      '$script:WorktrunkInitialized = $true'
    )
    Mock Get-Command {
      [pscustomobject]@{ Name = 'git-wt'; CommandType = 'Application'; Path = $mockPath }
    } -ParameterFilter { $Name -eq 'git-wt' }

    . $script:Subject

    Get-Variable __wtCmd -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __wtInit -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __wtPath -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __wtCandidate -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __candidatePath -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
    Get-Variable __gitWtInfo -Scope Script -ErrorAction SilentlyContinue |
      Should -BeNullOrEmpty
  }
}
